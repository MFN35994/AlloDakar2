import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/trip_repository.dart';
import './auth_provider.dart';
import '../models/trip_model.dart';
import '../models/pool_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';

final driverOccupancyProvider = StreamProvider.family<int, String>((ref, driverId) {
  return ref.watch(tripRepositoryProvider).watchDriverOccupancy(driverId);
});

final driverRatingProvider = StreamProvider.family<double, String>((ref, driverId) {
  return ref.watch(tripRepositoryProvider).watchDriverRating(driverId);
});

final activeTripProvider = StreamProvider<TripModel?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null) return Stream.value(null);
  
  final firestore = FirebaseFirestore.instance;
  
  // Les pools (Covoiturage) - Sans whereIn pour éviter l'index composite
  final poolsStream = firestore.collection('pools')
      .where('passengerIds', arrayContains: auth.userId)
      .snapshots();

  // Les trips (VTC/Yobanté) - Sans whereIn pour éviter l'index composite
  final tripsStream = firestore.collection('trips')
      .where('clientId', isEqualTo: auth.userId)
      .snapshots();

  return Rx.combineLatest2(poolsStream, tripsStream, (QuerySnapshot poolsSnap, QuerySnapshot tripsSnap) {
    // Filtrage local pour les status
    final validTripStatus = ['pending', 'accepted', 'departed'];
    final validPoolStatus = ['open', 'full', 'accepted', 'departed'];

    // S'il y a un trip actif (ex: Yobanté)
    final activeTrips = tripsSnap.docs.where((doc) {
      final status = (doc.data() as Map<String, dynamic>)['status'] as String? ?? 'pending';
      return validTripStatus.contains(status);
    }).toList();

    if (activeTrips.isNotEmpty) {
      return TripModel.fromFirestore(activeTrips.first);
    }
    
    // Sinon, s'il y a un pool actif
    final activePools = poolsSnap.docs.where((doc) {
      final status = (doc.data() as Map<String, dynamic>)['status'] as String? ?? 'open';
      return validPoolStatus.contains(status);
    }).toList();

    if (activePools.isNotEmpty) {
      final doc = activePools.first;
      final data = doc.data() as Map<String, dynamic>;
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

final driverActivePoolProvider = StreamProvider<PoolModel?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null || auth.userId.isEmpty) return Stream.value(null);
  
  final firestore = FirebaseFirestore.instance;
  
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
