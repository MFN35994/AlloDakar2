import 'dart:math' as math;
import 'dart:convert';
import "package:flutter/foundation.dart";
import "package:firebase_core/firebase_core.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:transen_core/transen_core.dart';
import 'package:transen_payment/transen_payment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:http/http.dart' as http;

class TripRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');
  final PaymentRepository _paymentRepo;

  TripRepository(this._paymentRepo);

  // 1. ACTIONS COVOITURAGE (POOL)
  Future<void> acceptPool(String poolId, String driverId, [double commission = 0]) async {
    // 1. Obtenir le token ID de l'utilisateur actuel pour sécuriser l'appel
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Utilisateur non connecté");
    final token = await user.getIdToken();

    // 2. Appeler le backend pour accepter le covoiturage
    final response = await http.post(
      Uri.parse("https://transen-api.onrender.com/api/pools/accept"),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'poolId': poolId,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'] ?? "Erreur lors de l'acceptation";
      throw Exception(error);
    }
  }

  Future<void> departPool(String poolId) async {
    await _firestore.collection('pools').doc(poolId).update({
      'status': 'departed',
      'departedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> joinOrCreatePool({
    required String userId,
    required String departure,
    required String destination,
    required String scheduledDate,
    required double lat,
    required double lng,
    required int seats,
    String? preferredDriverId,
    required Map<String, dynamic> userDetails,
  }) async {
    final query = await _firestore.collection('pools')
        .where('departure', isEqualTo: departure)
        .where('destination', isEqualTo: destination)
        .where('scheduledDate', isEqualTo: scheduledDate)
        .where('status', isEqualTo: 'open')
        .get();

    if (query.docs.isNotEmpty) {
      final poolDoc = query.docs.first;
      final data = poolDoc.data();
      final passengerIds = List<String>.from(data['passengerIds'] ?? []);
      final currentFilling = data['currentFilling'] ?? 0;
      final maxCapacity = data['maxCapacity'] ?? 4;

      if (currentFilling + seats <= maxCapacity) {
        passengerIds.add(userId);
        final passengerDetails = Map<String, dynamic>.from(data['passengerDetails'] ?? {});
        passengerDetails[userId] = {
          ...userDetails,
          'seats': seats,
          'lat': lat,
          'lng': lng,
        };

        await poolDoc.reference.update({
          'passengerIds': passengerIds,
          'passengerDetails': passengerDetails,
          'currentFilling': currentFilling + seats,
          'status': (currentFilling + seats >= maxCapacity) ? 'full' : 'open',
        });
        return poolDoc.id;
      }
    }

    // Création d'un nouveau pool
    final ref = _firestore.collection('pools').doc();
    final pool = PoolModel(
      id: ref.id,
      departure: departure,
      destination: destination,
      status: 'open',
      passengerIds: [userId],
      passengerDetails: {
        userId: {
          ...userDetails,
          'seats': seats,
          'lat': lat,
          'lng': lng,
        }
      },
      createdAt: DateTime.now(),
      scheduledDate: scheduledDate,
      currentFilling: seats,
      driverId: preferredDriverId,
    );

    await ref.set({
      ...pool.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // 2. PARRAINAGE
  Future<void> _checkAndAwardReferralPoints(String? userId, String tripType) async {
    if (userId == null) return;
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data()!;
      final referredBy = userData['referredBy'] as String?;
      final alreadyClaimed = userData['referralRewardClaimed'] ?? false;

      if (referredBy != null && !alreadyClaimed) {
        debugPrint(">>> PARRAINAGE: Demande de 10 points au backend pour $referredBy");
        await _paymentRepo.processReferralReward(userId, tripType);
      }
    } catch (e) {
      debugPrint("Erreur parrainage: $e");
    }
  }

  // 3. ACTIONS COURSES (VTC)
  Future<String> createTrip(TripModel trip) async {
    final ref = _firestore.collection('trips').doc();
    await ref.set({
      ...trip.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> acceptTrip(String tripId, String driverId) async {
    // 1. Obtenir le token ID de l'utilisateur actuel pour sécuriser l'appel
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Utilisateur non connecté");
    final token = await user.getIdToken();

    // 2. Appeler le backend pour accepter la course
    final response = await http.post(
      Uri.parse("https://transen-api.onrender.com/api/trips/accept"),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'tripId': tripId,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'] ?? "Erreur lors de l'acceptation";
      throw Exception(error);
    }
  }

  Future<void> completeTrip(String tripId, {double? currentLat, double? currentLng}) async {
    final poolDoc = await _firestore.collection('pools').doc(tripId).get();
    if (poolDoc.exists) {
      final data = poolDoc.data()!;
      final driverId = data['driverId'] as String?;
      
      await _firestore.collection('pools').doc(tripId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });
      
      if (driverId != null) {
        await _firestore.collection('active_drivers').doc(driverId).update({
          'activePoolId': FieldValue.delete(),
        }).catchError((_) {});
      }
    } else {
      final tripDoc = await _firestore.collection('trips').doc(tripId).get();
      if (tripDoc.exists) {
        final data = tripDoc.data()!;
        final clientId = data['clientId'];
        final driverId = data['driverId'] as String?;
        final type = data['type'] ?? 'Course';
        
        await _checkAndAwardReferralPoints(clientId, type);
        
        final pointsDiscount = (data['pointsDiscount'] ?? 0).toDouble();
        final destLat = data['destinationLat'] as double?;
        final destLng = data['destinationLng'] as double?;
        
        bool locationVerified = false;
        if (currentLat != null && currentLng != null && destLat != null && destLng != null) {
          double distance = _calculateDistance(currentLat, currentLng, destLat, destLng);
          if (distance <= 0.5) { 
            locationVerified = true;
          }
        }

        await _firestore.collection('trips').doc(tripId).update({
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'locationVerified': locationVerified,
        });

        if (pointsDiscount > 0 && locationVerified && driverId != null) {
          await _paymentRepo.updateWalletBalance(
            driverId, 
            pointsDiscount, 
            "Remboursement points client (Course : $tripId)",
            type: 'points_payout'
          );
        }
        
        if (driverId != null) {
          await _firestore.collection('active_drivers').doc(driverId).update({
            'activeTripId': FieldValue.delete(),
          }).catchError((_) {});
        }
      }
    }
  }

  Future<void> cancelTrip(String tripId, String userId) async {
    await _firestore.collection('trips').doc(tripId).update({'status': 'cancelled'}).catchError((_) {});
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

  // 4. WATCHERS (COVOITURAGE)
  Stream<List<PoolModel>> watchActivePools() {
    return _firestore.collection('pools')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => PoolModel.fromFirestore(doc)).toList());
  }

  Stream<PoolModel?> watchPool(String poolId) {
    return _firestore.collection('pools').doc(poolId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return PoolModel.fromFirestore(doc);
    });
  }

  // 5. WATCHERS (COURSES & STATS)
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
          price: (data['price'] ?? 10000).toDouble(),
          status: data['status'] ?? 'open',
          type: 'Covoiturage Intelligent',
          driverId: data['driverId'],
          driverName: data['driverName'],
          driverPhone: data['driverPhone'],
          scheduledDate: data['scheduledDate'],
          passengerDetails: data['passengerDetails'],
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }
      return null;
    });
  }

  Stream<List<TripModel>> getPendingTrips({String? departure, String? destination}) {
    Query query = _firestore.collection('trips').where('status', isEqualTo: 'pending');
    if (departure != null) query = query.where('departure', isEqualTo: departure);
    if (destination != null) query = query.where('destination', isEqualTo: destination);
    
    return query.snapshots().map((snap) => snap.docs.map((doc) => TripModel.fromFirestore(doc)).toList());
  }

  Stream<List<TripModel>> watchUserTrips(String userId) {
    return _firestore.collection('trips')
        .where('clientId', isEqualTo: userId)
        .where('status', whereIn: ['completed', 'cancelled'])
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => TripModel.fromFirestore(doc)).toList());
  }

  Stream<int> watchDriverOccupancy(String driverId) {
    return _firestore.collection('trips')
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Stream<Map<String, int>> watchDemandHeatmap() {
    return _firestore.collection('trips')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final Map<String, int> heatmap = {};
          for (var doc in snapshot.docs) {
            final departure = doc.data()['departure'] as String? ?? 'Inconnu';
            heatmap[departure] = (heatmap[departure] ?? 0) + 1;
          }
          return heatmap;
        });
  }

  // 6. ROUTES CHAUFFEUR
  Stream<DocumentSnapshot> getDriverRoute(String driverId) {
    return _firestore.collection('driver_routes').doc(driverId).snapshots();
  }

  Future<void> publishDriverRoute(String driverId, String departure, String? destination, String? note) async {
    await _firestore.collection('driver_routes').doc(driverId).set({
      'departure': departure,
      'destination': destination,
      'note': note,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 7. UTILS
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; 
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degree) => degree * (math.pi / 180.0);
}

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  return TripRepository(paymentRepo);
});
