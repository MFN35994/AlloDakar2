import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';

class ItineraryOptimizer {
  /// Calcule l'ordre optimal de ramassage pour minimiser la distance totale.
  /// Pour 4 points, un simple algorithme de type "Plus Proche Voisin" suffit.
  static List<MapEntry<String, dynamic>> optimizePickupOrder(
    LatLng startPos,
    Map<String, dynamic> passengers,
  ) {
    List<MapEntry<String, dynamic>> entries = passengers.entries.toList();
    List<MapEntry<String, dynamic>> optimized = [];
    LatLng currentPos = startPos;

    while (entries.isNotEmpty) {
      MapEntry<String, dynamic>? closest;
      double minDistance = double.infinity;
      int closestIndex = -1;

      for (int i = 0; i < entries.length; i++) {
        final lat = entries[i].value['lat'] as double;
        final lng = entries[i].value['lng'] as double;
        final dist = _calculateDistance(currentPos, LatLng(lat, lng));
        
        if (dist < minDistance) {
          minDistance = dist;
          closest = entries[i];
          closestIndex = i;
        }
      }

      if (closest != null) {
        optimized.add(closest);
        currentPos = LatLng(closest.value['lat'], closest.value['lng']);
        entries.removeAt(closestIndex);
      }
    }

    return optimized;
  }

  static double _calculateDistance(LatLng p1, LatLng p2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((p2.latitude - p1.latitude) * p)/2 + 
          c(p1.latitude * p) * c(p2.latitude * p) * 
          (1 - c((p2.longitude - p1.longitude) * p))/2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }
}
