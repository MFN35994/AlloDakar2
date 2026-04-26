import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/trip_repository.dart';
import './auth_provider.dart';
import '../models/trip_model.dart';
import '../models/pool_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final driverOccupancyProvider = StreamProvider.family<int, String>((ref, driverId) {
  return ref.watch(tripRepositoryProvider).watchDriverOccupancy(driverId);
});

final driverRatingProvider = StreamProvider.family<double, String>((ref, driverId) {
  return ref.watch(tripRepositoryProvider).watchDriverRating(driverId);
});

final driverRatingCountProvider = StreamProvider.family<int, String>((ref, driverId) {
  return FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('reviews')
      .where('driverId', isEqualTo: driverId)
      .snapshots()
      .map((snap) => snap.docs.length);
});

final driverReviewsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, driverId) {
  return ref.watch(tripRepositoryProvider).watchDriverReviews(driverId).map((reviews) {
    // Trier en mémoire pour éviter de demander un index composite à l'utilisateur
    final sorted = List<Map<String, dynamic>>.from(reviews);
    sorted.sort((a, b) {
      final dateA = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
      final dateB = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });
    return sorted;
  });
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
          // On suppose que le chauffeur n'a qu'une seule course active à la fois
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
        if (snapshot.docs.isNotEmpty) {
          return TripModel.fromFirestore(snapshot.docs.first);
        }
        return null;
      });
});
