
import "package:firebase_core/firebase_core.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_trips/transen_trips.dart';

final driverOccupancyProvider = StreamProvider.family<int, String>((ref, driverId) {
  return ref.watch(tripRepositoryProvider).watchDriverOccupancy(driverId);
});

final activePoolProvider = StreamProvider<TripModel?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null) return Stream.value(null);
  
  final firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');
  
  return firestore.collection('pools')
      .where('passengerIds', arrayContains: auth.userId)
      .snapshots()
      .map((snapshot) {
        final validPoolStatus = ['open', 'full', 'accepted', 'departed'];
        final activePools = snapshot.docs.where((doc) {
          final status = doc.data()['status'] as String? ?? 'open';
          return validPoolStatus.contains(status);
        }).toList();

        if (activePools.isNotEmpty) {
          final doc = activePools.first;
          final data = doc.data();
          return TripModel(
            id: doc.id,
            departure: data['departure'] ?? '',
            destination: data['destination'] ?? '',
            price: 10000,
            status: data['status'] ?? 'open',
            type: 'Covoiturage Intelligent',
            driverId: data['driverId'],
            scheduledDate: data['scheduledDate'],
            createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          );
        }
        return null;
      });
});

final activeTripProvider = StreamProvider<TripModel?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null) return Stream.value(null);
  
  final firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');
  
  return firestore.collection('trips')
      .where('clientId', isEqualTo: auth.userId)
      .snapshots()
      .map((snapshot) {
        final validTripStatus = ['pending', 'accepted', 'departed'];
        final activeTrips = snapshot.docs.where((doc) {
          final status = doc.data()['status'] as String? ?? 'pending';
          return validTripStatus.contains(status);
        }).toList();

        if (activeTrips.isNotEmpty) {
          return TripModel.fromFirestore(activeTrips.first);
        }
        return null;
      });
});

final driverActivePoolProvider = StreamProvider<PoolModel?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null || auth.userId.isEmpty) return Stream.value(null);
  
  final firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');
  
  return firestore.collection('pools')
      .where('driverId', isEqualTo: auth.userId)
      .where('status', whereIn: ['accepted', 'departed'])
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          return PoolModel.fromFirestore(snapshot.docs.first);
        }
        return null;
      });
});

final driverActiveTripProvider = StreamProvider<TripModel?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null || auth.userId.isEmpty) return Stream.value(null);
  
  return FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('trips')
      .where('driverId', isEqualTo: auth.userId)
      .where('status', isEqualTo: 'accepted')
      .snapshots()
      .map((snapshot) {
        final vtcTrips = snapshot.docs.where((doc) {
          final type = (doc.data()['type'] as String? ?? '').toLowerCase();
          return !type.contains('livraison') && !type.contains('colis') && !type.contains('yobante');
        });
        if (vtcTrips.isNotEmpty) {
          return TripModel.fromFirestore(vtcTrips.first);
        }
        return null;
      });
});

final driverActiveDeliveriesProvider = StreamProvider<List<TripModel>>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null || auth.userId.isEmpty) return Stream.value([]);
  
  return FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('trips')
      .where('driverId', isEqualTo: auth.userId)
      .where('status', isEqualTo: 'accepted')
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.where((doc) {
          final type = (doc.data()['type'] as String? ?? '').toLowerCase();
          return type.contains('livraison') || type.contains('colis') || type.contains('yobante');
        }).map((doc) => TripModel.fromFirestore(doc)).toList();
      });
});

final tripHistoryProvider = StreamProvider.family<List<TripModel>, String>((ref, userId) {
  return ref.watch(tripRepositoryProvider).watchUserTrips(userId);
});
