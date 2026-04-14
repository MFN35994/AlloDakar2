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

final activeTripProvider = StreamProvider<TripModel?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null) return Stream.value(null);
  
  final firestore = FirebaseFirestore.instance;
  
  // Cette logique est un peu complexe car on doit chercher dans 'trips' ET 'pools'
  // On va surveiller les 'pools' où l'utilisateur est présent et le statut n'est pas terminé
  return firestore.collection('pools')
      .where('passengerIds', arrayContains: auth.userId)
      .where('status', whereIn: ['open', 'full', 'accepted', 'departed'])
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
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
