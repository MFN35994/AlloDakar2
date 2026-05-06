import "package:flutter/foundation.dart";
import "package:firebase_core/firebase_core.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import 'package:transen_core/transen_core.dart';

import 'package:transen_payment/transen_payment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

class TripRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');
  final PaymentRepository _paymentRepo;

  TripRepository(this._paymentRepo);

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
      final query = await _firestore.collection('pools')
          .where('departure', isEqualTo: departure)
          .where('destination', isEqualTo: destination)
          .where('status', isEqualTo: 'open')
          .get();

      DateTime parseDate(String d) {
        try {
          final parts = d.split(' ');
          final dateParts = parts[0].split('/');
          final timeParts = parts[1].split(':');
          return DateTime(int.parse(dateParts[2]), int.parse(dateParts[1]), int.parse(dateParts[0]), int.parse(timeParts[0]), int.parse(timeParts[1]));
        } catch (_) {
          return DateTime.now();
        }
      }

      final reqDate = parseDate(scheduledDate);
      final fullUserDetails = {...userDetails, 'lat': lat, 'lng': lng, 'seats': seats};
      
      DocumentSnapshot? poolToJoin;
      for (var doc in query.docs) {
        final data = doc.data();
        final poolScheduledStr = data['scheduledDate'] as String?;
        if (poolScheduledStr == null) continue;
        
        final poolDate = parseDate(poolScheduledStr);
        if (poolDate.difference(reqDate).inMinutes.abs() <= 15) {
          final currentFilling = data['currentFilling'] as int? ?? 0;
          if (currentFilling + seats <= 4) {
            poolToJoin = doc;
            break;
          }
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
    final userDoc = await _firestore.collection('users').doc(driverId).get();
    final userData = userDoc.data() ?? {};

    String driverName = userData['name'] ?? 'Chauffeur TranSen';
    if (driverName == 'Chauffeur TranSen' && userData['firstName'] != null) {
      driverName = "${userData['firstName']} ${userData['lastName'] ?? ''}";
    }
    final driverPhone = (userData['phone'] as String? ?? '').replaceAll(' ', '');

    final poolRef = _firestore.collection('pools').doc(poolId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(poolRef);
      if (!snapshot.exists) {
        throw Exception("Ce trajet est introuvable.");
      }
      final data = snapshot.data()!;
      final currentStatus = data['status'] as String?;
      if (currentStatus != 'open' && currentStatus != 'full') {
        throw Exception("Ce trajet n'est plus disponible ou a déjà été accepté.");
      }
      transaction.update(poolRef, {
        'status': 'accepted',
        'driverId': driverId,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    });

    try {
      await _firestore.collection('active_drivers').doc(driverId).set({
        'activePoolId': poolId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Erreur active_drivers: $e");
    }
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
    if (userId == null) return;
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data()!;
      final referredBy = userData['referredBy'] as String?;
      final alreadyClaimed = userData['referralRewardClaimed'] ?? false;
      final filleulDeviceId = userData['deviceId'] as String?;

      if (referredBy != null && !alreadyClaimed) {
        final referrerDoc = await _firestore.collection('users').doc(referredBy).get();
        if (referrerDoc.exists) {
          final referrerDeviceId = referrerDoc.data()?['deviceId'];
          if (filleulDeviceId != null && referrerDeviceId != null && filleulDeviceId == referrerDeviceId) {
            await _firestore.collection('users').doc(userId).update({'referralRewardClaimed': true});
            return;
          }
        }
        
        final userName = userData['name'] ?? 'Un client';
        await _firestore.collection('users').doc(userId).update({'referralRewardClaimed': true});
        await _paymentRepo.updatePoints(referredBy, 10, "Gains Parrainage: $tripType (Client: $userName)");
      }
    } catch (e) {
      debugPrint("Erreur parrainage: $e");
    }
  }

  Future<String> createTrip(TripModel trip) async {
    try {
      final doc = await _firestore.collection('trips').add(trip.toMap());
      return doc.id;
    } catch (e) {
      debugPrint("Erreur création trip: $e");
      return '';
    }
  }

  Stream<List<TripModel>> getPendingTrips({String? departure, String? destination}) {
    return _firestore.collection('trips')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final trips = <TripModel>[];
          for (var doc in snapshot.docs) {
            try {
              trips.add(TripModel.fromFirestore(doc));
            } catch (_) {}
          }
          return trips.where((t) {
            bool matchesDep = (departure == null || departure == 'TOUTES LES RÉGIONS' || departure.isEmpty) || t.departure == departure;
            bool matchesDest = (destination == null || destination == 'TOUTES LES RÉGIONS' || destination.isEmpty) || t.destination == destination;
            return matchesDep && matchesDest;
          }).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
  }

  Future<void> deleteTrip(String tripId) async {
    await _firestore.collection('trips').doc(tripId).delete();
  }

  Future<void> publishDriverRoute(String driverId, String dep, [String? dest, String? note]) async {
    await _firestore.collection('driver_routes').doc(driverId).set({
      'departure': dep,
      'destination': dest,
      'note': note,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    final activeDoc = _firestore.collection('active_drivers').doc(driverId);
    final docSnapshot = await activeDoc.get();
    if (docSnapshot.exists) {
      await activeDoc.update({'departure': dep, 'destination': dest, 'note': note});
    }
  }

  Stream<DocumentSnapshot> getDriverRoute(String driverId) {
    return _firestore.collection('driver_routes').doc(driverId).snapshots();
  }

  Future<void> acceptTrip(String tripId, String driverId) async {
    try {
      debugPrint("Tentative d'acceptation du trip: $tripId par driver: $driverId");
      final tripRef = _firestore.collection('trips').doc(tripId);
      
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(tripRef);
        if (!snapshot.exists) {
          throw Exception("Course introuvable.");
        }
        final data = snapshot.data()!;
        final status = data['status'] as String?;
        
        debugPrint("Statut actuel de la course: $status");
        
        if (status != 'pending') {
          throw Exception("Cette course a déjà été acceptée ou annulée.");
        }
        
        transaction.update(tripRef, {
          'status': 'accepted',
          'driverId': driverId,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint("Transaction d'acceptation réussie.");
    } catch (e, stack) {
      debugPrint("Erreur critique dans acceptTrip: $e");
      debugPrint("Stacktrace: $stack");
      rethrow;
    }

    try {
      await _firestore.collection('active_drivers').doc(driverId).set({
        'activeTripId': tripId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Erreur active_drivers trip: $e");
    }
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

  Future<void> completeTrip(String tripId) async {
    final poolDoc = await _firestore.collection('pools').doc(tripId).get();
    if (poolDoc.exists) {
      final data = poolDoc.data()!;
      final passengerIds = List<String>.from(data['passengerIds'] ?? []);
      for (var uid in passengerIds) {
        await _checkAndAwardReferralPoints(uid, "Covoiturage");
      }
      await _firestore.collection('pools').doc(tripId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final tripDoc = await _firestore.collection('trips').doc(tripId).get();
      if (tripDoc.exists) {
        final data = tripDoc.data()!;
        final clientId = data['clientId'];
        final type = data['type'] ?? 'Course';
        await _checkAndAwardReferralPoints(clientId, type);
        await _firestore.collection('trips').doc(tripId).update({
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  Stream<TripModel?> watchTrip(String tripId) {
    final tripStream = _firestore.collection('trips').doc(tripId).snapshots();
    final poolStream = _firestore.collection('pools').doc(tripId).snapshots();
    return Rx.combineLatest2(tripStream, poolStream, (tripSnap, poolSnap) {
      if (tripSnap.exists) return TripModel.fromFirestore(tripSnap);
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
    await _firestore.collection('trips').doc(tripId).delete().catchError((_) {});
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
            'status': 'open',
          });
        }
      }
    }
  }

  Stream<List<TripModel>> watchUserTrips(String userId) {
    final tripsStream = _firestore.collection('trips')
        .where('clientId', isEqualTo: userId)
        .where('status', isEqualTo: 'completed')
        .snapshots();
    final poolsStream = _firestore.collection('pools')
        .where('passengerIds', arrayContains: userId)
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
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        ));
      }
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return all;
    });
  }
}

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  return TripRepository(paymentRepo);
});
