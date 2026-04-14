import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/trip_repository.dart';
import '../models/pool_model.dart';

final activePoolsProvider = StreamProvider<List<PoolModel>>((ref) {
  return ref.watch(tripRepositoryProvider).watchActivePools();
});

final poolDetailProvider = StreamProvider.family<PoolModel?, String>((ref, poolId) {
  return ref.watch(tripRepositoryProvider).watchPool(poolId);
});

final demandHeatmapProvider = StreamProvider<Map<String, int>>((ref) {
  return ref.watch(tripRepositoryProvider).watchDemandHeatmap();
});

final pendingPoolsProvider = StreamProvider.family<List<PoolModel>, String>((ref, filterKey) {
  final parts = filterKey.split('|');
  final departure = parts[0] == 'ANY' ? null : parts[0];
  final destination = parts[1] == 'ANY' ? null : parts[1];

  return ref.watch(tripRepositoryProvider).watchActivePools().map((pools) {
    return pools.where((p) {
      if (departure != null && p.departure != departure) return false;
      if (destination != null && p.destination != destination) return false;
      return true;
    }).toList();
  });
});
