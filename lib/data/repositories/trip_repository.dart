import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/models/pool_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

class TripRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- LOGIQUE POOLING (COVOITURAGE) ---

  Future<String> joinOrCreatePool({
    required String departure,
    required String destination,
    required String scheduledDate,
    required String userId,
    required Map<String, dynamic> userDetails,
    required double lat,
    required double lng,
    int seats = 1,
  }) async {
    try {
      // Chercher tous les pools ouverts pour ce trajet
      final query = await _firestore.collection('pools')
          .where('departure', isEqualTo: departure)
          .where('destination', isEqualTo: destination)
          .where('scheduledDate', isEqualTo: scheduledDate)
          .where('status', isEqualTo: 'open')
          .get();

      final fullUserDetails = {...userDetails, 'lat': lat, 'lng': lng, 'seats': seats};

      // Filtrer en Dart pour trouver celui qui a assez de place
      DocumentSnapshot? poolToJoin;
      for (var doc in query.docs) {
        final currentFilling = doc.data()['currentFilling'] as int? ?? 0;
        if (currentFilling + seats <= 4) {
          poolToJoin = doc;
          break;
        }
      }

      if (poolToJoin != null) {
        final poolId = poolToJoin.id;
        final data = poolToJoin.data() as Map<String, dynamic>;
        final currentFilling = data['currentFilling'] as int;
        final passengerIds = List<String>.from(data['passengerIds'] ?? []);
        final passengerDetails = Map<String, dynamic>.from(data['passengerDetails'] ?? {});

        if (!passengerIds.contains(userId)) {
          passengerIds.add(userId);
          passengerDetails[userId] = fullUserDetails;
          
          final newFilling = currentFilling + seats;
          await _firestore.collection('pools').doc(poolId).update({
            'passengerIds': passengerIds,
            'passengerDetails': passengerDetails,
            'currentFilling': newFilling,
            'status': newFilling >= 4 ? 'full' : 'open',
          });
        }
        return poolId;
      } else {
        // Créer un nouveau pool
        final doc = await _firestore.collection('pools').add({
          'departure': departure,
          'destination': destination,
          'scheduledDate': scheduledDate,
          'status': seats >= 4 ? 'full' : 'open',
          'passengerIds': [userId],
          'passengerDetails': {userId: fullUserDetails},
          'currentFilling': seats,
          'maxCapacity': 4,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return doc.id;
      }
    } catch (e) {
      debugPrint("Erreur joinOrCreatePool: $e");
      rethrow;
    }
  }

  Stream<List<PoolModel>> watchActivePools() {
    return _firestore.collection('pools')
        .where('status', whereIn: ['open', 'full'])
        .snapshots()
        .map((snapshot) {
          final pools = snapshot.docs.map((doc) => PoolModel.fromFirestore(doc)).toList();
          // Tri manuel pour éviter les problèmes d'index composite en dev
          pools.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return pools;
        });
  }

  Stream<PoolModel?> watchPool(String poolId) {
    return _firestore.collection('pools').doc(poolId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return PoolModel.fromFirestore(doc);
    });
  }

  Future<void> acceptPool(String poolId, String driverId) async {
    // Récupérer les infos du chauffeur pour les synchroniser (cache)
    final userDoc = await _firestore.collection('users').doc(driverId).get();
    final userData = userDoc.data() ?? {};
    
    String driverName = userData['name'] ?? 'Chauffeur Allô Dakar';
    if (driverName == 'Chauffeur Allô Dakar' && userData['firstName'] != null) {
      driverName = "${userData['firstName']} ${userData['lastName'] ?? ''}";
    }
    final driverPhone = userData['phone'] ?? '';

    await _firestore.collection('pools').doc(poolId).update({
      'status': 'accepted',
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    // Également mettre à jour active_drivers pour le tracking temps réel
    await _firestore.collection('active_drivers').doc(driverId).update({
      'driverName': driverName,
      'driverPhone': driverPhone,
    });
  }

  Future<void> departPool(String poolId) async {
    await _firestore.collection('pools').doc(poolId).update({
      'status': 'departed',
      'departedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<Map<String, int>> watchDemandHeatmap() {
    return _firestore.collection('pools')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) {
          final heatmap = <String, int>{};
          for (var doc in snapshot.docs) {
            final dest = doc.data()['destination'] as String;
            final filling = doc.data()['currentFilling'] as int;
            heatmap[dest] = (heatmap[dest] ?? 0) + filling;
          }
          return heatmap;
        });
  }

  // --- LOGIQUE TRIPS (VTC CLASSIQUE - GARDÉ POUR RÉTROCOMPATIBILITÉ) ---

  Future<String> createTrip(TripModel trip) async {
    try {
      final doc = await _firestore.collection('trips').add(trip.toMap());
      return doc.id;
    } catch (e) {
      debugPrint("Erreur création trip Firebase: $e");
      return '';
    }
  }

  Stream<List<TripModel>> getPendingTrips({String? departure, String? destination}) {
    // On ne filtre par Firestore QUE sur le status pour éviter le besoin d'index composites complexes
    return _firestore.collection('trips')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final trips = snapshot.docs.map((doc) => TripModel.fromFirestore(doc)).toList();
          
          // Filtrage manuel en Dart
          return trips.where((t) {
            bool matchesDep = true;
            if (departure != null && departure != 'TOUTES LES RÉGIONS' && departure.isNotEmpty) {
              matchesDep = t.departure == departure;
            }
            
            bool matchesDest = true;
            if (destination != null && destination != 'TOUTES LES RÉGIONS' && destination.isNotEmpty) {
              matchesDest = t.destination == destination;
            }
            
            return matchesDep && matchesDest;
          }).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
  }

  Future<void> deleteTrip(String tripId) async {
    await _firestore.collection('trips').doc(tripId).delete();
  }

  Future<void> publishDriverRoute(String driverId, String dep, [String? dest]) async {
    // 1. Mise à jour de la table des routes
    await _firestore.collection('driver_routes').doc(driverId).set({
      'departure': dep,
      'destination': dest,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Mise à jour immédiate du document chauffeur actif pour le client (si en ligne)
    final activeDoc = _firestore.collection('active_drivers').doc(driverId);
    final docSnapshot = await activeDoc.get();
    if (docSnapshot.exists) {
      await activeDoc.update({
        'departure': dep,
        'destination': dest,
      });
    }
  }

  Stream<DocumentSnapshot> getDriverRoute(String driverId) {
    return _firestore.collection('driver_routes').doc(driverId).snapshots();
  }

  Future<void> acceptTrip(String tripId, String driverId) async {
    // Récupérer les infos du chauffeur pour les synchroniser (cache)
    final userDoc = await _firestore.collection('users').doc(driverId).get();
    final userData = userDoc.data() ?? {};
    
    String driverName = userData['name'] ?? 'Chauffeur Allô Dakar';
    if (driverName == 'Chauffeur Allô Dakar' && userData['firstName'] != null) {
      driverName = "${userData['firstName']} ${userData['lastName'] ?? ''}";
    }
    final driverPhone = userData['phone'] ?? '';

    await _firestore.collection('trips').doc(tripId).update({
      'status': 'accepted',
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    // Également mettre à jour active_drivers pour le tracking temps réel
    await _firestore.collection('active_drivers').doc(driverId).update({
      'driverName': driverName,
      'driverPhone': driverPhone,
    });
  }

  Stream<int> watchDriverOccupancy(String driverId) {
    return _firestore.collection('trips')
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snapshot) {
          int count = 0;
          for (var doc in snapshot.docs) {
            count += (doc.data()['seats'] as int? ?? 1);
          }
          return count;
        });
  }

  Future<void> submitRating(String tripId, int rating, String comment) async {
    await _firestore.collection('trips').doc(tripId).update({
      'rating': rating,
      'comment': comment,
      'status': 'rated',
    });
  }

  Future<void> completeTrip(String tripId) async {
    // Vérifier si c'est un pool
    final poolDoc = await _firestore.collection('pools').doc(tripId).get();
    if (poolDoc.exists) {
      await _firestore.collection('pools').doc(tripId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _firestore.collection('trips').doc(tripId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Stream<double> watchDriverRating(String driverId) {
    return _firestore.collection('trips')
        .where('driverId', isEqualTo: driverId)
        .where('rating', isNull: false)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return 5.0;
          double total = 0;
          for (var doc in snapshot.docs) {
            total += (doc.data()['rating'] as int).toDouble();
          }
          return total / snapshot.docs.length;
        });
  }

  Stream<TripModel?> watchTrip(String tripId) {
    final tripStream = _firestore.collection('trips').doc(tripId).snapshots();
    final poolStream = _firestore.collection('pools').doc(tripId).snapshots();

    return Rx.combineLatest2(tripStream, poolStream, (tripSnap, poolSnap) {
      if (tripSnap.exists) {
        return TripModel.fromFirestore(tripSnap);
      }
      
      if (poolSnap.exists) {
        final data = poolSnap.data()!;
        return TripModel(
          id: poolSnap.id,
          departure: data['departure'] ?? '',
          destination: data['destination'] ?? '',
          price: 10000,
          status: data['status'] ?? 'open',
          type: 'Covoiturage Intelligent',
          driverId: data['driverId'],
          driverName: data['driverName'],
          driverPhone: data['driverPhone'],
          scheduledDate: data['scheduledDate'],
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }
      return null;
    });
  }

  Future<void> cancelTrip(String tripId, String userId) async {
    // Essayer de supprimer dans 'trips'
    await _firestore.collection('trips').doc(tripId).delete();
    
    // Essayer de retirer l'utilisateur du 'pool'
    final poolDoc = await _firestore.collection('pools').doc(tripId).get();
    if (poolDoc.exists) {
      final passengerIds = List<String>.from(poolDoc.data()?['passengerIds'] ?? []);
      final passengerDetails = Map<String, dynamic>.from(poolDoc.data()?['passengerDetails'] ?? {});
      
      if (passengerIds.contains(userId)) {
        passengerIds.remove(userId);
        passengerDetails.remove(userId);
        
        if (passengerIds.isEmpty) {
          await _firestore.collection('pools').doc(tripId).delete();
        } else {
          await _firestore.collection('pools').doc(tripId).update({
            'passengerIds': passengerIds,
            'passengerDetails': passengerDetails,
            'currentFilling': passengerIds.length,
            'status': 'open', // Re-ouvrir si quelqu'un part
          });
        }
      }
    }
  }
}

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  return TripRepository();
});
