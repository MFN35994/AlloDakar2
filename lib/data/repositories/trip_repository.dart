import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/models/pool_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

class TripRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');

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
    
    String driverName = userData['name'] ?? 'Chauffeur TranSen';
    if (driverName == 'Chauffeur TranSen' && userData['firstName'] != null) {
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

  Future<void> _checkAndAwardReferralPoints(String? userId, String tripType) async {
    if (userId == null) {
      debugPrint("[PARRAINAGE] userId est null, arrêt.");
      return;
    }
    try {
      debugPrint("[PARRAINAGE] Vérification parrainage pour client: $userId (Type: $tripType)");
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        debugPrint("[PARRAINAGE] Document client $userId introuvable dans 'users'.");
        return;
      }

      final referredBy = userDoc.data()?['referredBy'] as String?;
      final alreadyClaimed = userDoc.data()?['referralRewardClaimed'] ?? false;

      if (referredBy != null && !alreadyClaimed) {
        debugPrint("[PARRAINAGE] Parrain trouvé: $referredBy. Premier trajet détecté. Attribution de 10 points.");
        final userName = userDoc.data()?['name'] ?? 'Un client';
        final referrerRef = _firestore.collection('users').doc(referredBy);
        
        await _firestore.runTransaction((transaction) async {
          // 1. Marquer la récompense comme réclamée pour le filleul
          transaction.update(_firestore.collection('users').doc(userId), {
            'referralRewardClaimed': true,
          });

          // 2. Créditer le parrain
          transaction.set(referrerRef, {
            'bonusPoints': FieldValue.increment(10), // Gain de 10 points (1000 FCFA)
          }, SetOptions(merge: true));

          // 3. Ajouter la transaction
          final transRef = referrerRef.collection('transactions').doc();
          transaction.set(transRef, {
            'description': "Gains Parrainage: $tripType (Client: $userName)",
            'amount': 0.0,
            'points': 10,
            'date': FieldValue.serverTimestamp(),
          });
        });
        debugPrint("[PARRAINAGE] 10 points attribués avec succès à $referredBy !");
      } else if (alreadyClaimed) {
        debugPrint("[PARRAINAGE] Le client $userId a déjà généré une récompense parrainage. Pas de points cette fois.");
      } else {
        debugPrint("[PARRAINAGE] Le client $userId n'a pas de parrain (champ 'referredBy' absent).");
      }
    } catch (e) {
      debugPrint("[PARRAINAGE] ERREUR lors de l'attribution: $e");
    }
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
          final trips = <TripModel>[];
          for (var doc in snapshot.docs) {
            try {
              trips.add(TripModel.fromFirestore(doc));
            } catch (e) {
              debugPrint("Erreur parsing trip ${doc.id}: $e");
            }
          }
          
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
    
    String driverName = userData['name'] ?? 'Chauffeur TranSen';
    if (driverName == 'Chauffeur TranSen' && userData['firstName'] != null) {
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

  Future<void> submitRating({
    required String tripId, 
    required String driverId,
    required String userId,
    required String userName,
    required int rating, 
    required String comment
  }) async {
    try {
      debugPrint("[RATING] Soumission avis par $userId pour trajet $tripId");
      
      // 1. Enregistrer l'avis dans une collection globale
      await _firestore.collection('reviews').add({
        'tripId': tripId,
        'driverId': driverId,
        'userId': userId,
        'userName': userName,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Marquer comme noté pour CET utilisateur (dans sa propre collection de participations)
      // Note: On ne change plus le status global du pool/trip à 'rated' pour ne pas bloquer les autres
      final userReviewRef = _firestore.collection('users').doc(userId).collection('my_reviews').doc(tripId);
      await userReviewRef.set({
        'rated': true,
        'rating': rating,
        'date': FieldValue.serverTimestamp(),
      });
      
      debugPrint("[RATING] Avis enregistré avec succès.");
    } catch (e) {
      debugPrint("Erreur submitRating: $e");
      rethrow;
    }
  }

  Stream<bool> hasUserRated(String userId, String tripId) {
    return _firestore.collection('users').doc(userId).collection('my_reviews').doc(tripId).snapshots().map((doc) => doc.exists);
  }

  Future<void> completeTrip(String tripId) async {
    debugPrint("[TRIP] Tentative de complétion du trajet: $tripId");
    // Vérifier si c'est un pool
    final poolDoc = await _firestore.collection('pools').doc(tripId).get();
    if (poolDoc.exists) {
      debugPrint("[TRIP] C'est un covoiturage (pool).");
      final data = poolDoc.data() as Map<String, dynamic>;
      final passengerIds = List<String>.from(data['passengerIds'] ?? []);
      
      // Récompense pour CHAQUE passager parrainé
      for (var uid in passengerIds) {
        await _checkAndAwardReferralPoints(uid, "Covoiturage");
      }

      await _firestore.collection('pools').doc(tripId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });
      debugPrint("[TRIP] Status pool mis à jour: completed");
    } else {
      debugPrint("[TRIP] C'est une course classique (trip/yobante).");
      final tripDoc = await _firestore.collection('trips').doc(tripId).get();
      if (tripDoc.exists) {
        final data = tripDoc.data() as Map<String, dynamic>;
        final clientId = data['clientId'] as String?;
        final type = data['type'] as String? ?? 'Course';
        
        // Récompense pour le client parrainé
        await _checkAndAwardReferralPoints(clientId, type);

        await _firestore.collection('trips').doc(tripId).update({
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        });
        debugPrint("[TRIP] Status trip mis à jour: completed");
      } else {
        debugPrint("[TRIP] Document $tripId introuvable dans 'pools' ET 'trips'.");
      }
    }
  }

  Stream<double> watchDriverRating(String driverId) {
    return _firestore.collection('reviews')
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return 0.0;
          double total = 0;
          for (var doc in snapshot.docs) {
            total += (doc.data()['rating'] as int).toDouble();
          }
          return total / snapshot.docs.length;
        });
  }

  Stream<List<Map<String, dynamic>>> watchDriverReviews(String driverId) {
    return _firestore.collection('reviews')
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => doc.data()).toList();
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
  Stream<List<TripModel>> watchUserTrips(String userId) {
    // On regarde dans 'trips' où il est client
    final tripsStream = _firestore.collection('trips')
        .where('clientId', isEqualTo: userId)
        .where('status', isEqualTo: 'completed')
        .snapshots();

    // On regarde dans 'pools' où il est dans passengerIds
    final poolsStream = _firestore.collection('pools')
        .where('passengerIds', arrayContains: userId)
        .where('status', isEqualTo: 'completed')
        .snapshots();

    return Rx.combineLatest2(tripsStream, poolsStream, (tripsSnap, poolsSnap) {
      final List<TripModel> all = [];
      
      for (var doc in tripsSnap.docs) {
        all.add(TripModel.fromFirestore(doc));
      }

      for (var doc in poolsSnap.docs) {
        final data = doc.data();
        all.add(TripModel(
          id: doc.id,
          departure: data['departure'] ?? '',
          destination: data['destination'] ?? '',
          price: 10000,
          status: data['status'] ?? 'completed',
          type: 'Covoiturage',
          driverId: data['driverId'],
          driverName: data['driverName'],
          driverPhone: data['driverPhone'],
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        ));
      }

      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return all;
    });
  }
}

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  return TripRepository();
});
