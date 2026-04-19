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

  static LatLng? getRegionCoordinates(String regionName) {
    final Map<String, LatLng> regions = {
      'Dakar': const LatLng(14.7167, -17.4677),
      'Thiès': const LatLng(14.791, -16.935),
      'Saint-Louis': const LatLng(16.02, -16.48),
      'Kaolack': const LatLng(14.14, -16.07),
      'Ziguinchor': const LatLng(12.58, -16.27),
      'Diourbel': const LatLng(14.65, -16.23),
      'Louga': const LatLng(15.61, -16.22),
      'Tambacounda': const LatLng(13.77, -13.67),
      'Kolda': const LatLng(12.88, -14.94),
      'Matam': const LatLng(15.65, -13.25),
      'Fatick': const LatLng(14.35, -16.40),
      'Kaffrine': const LatLng(14.10, -15.55),
      'Kédougou': const LatLng(12.55, -12.18),
      'Sédhiou': const LatLng(12.70, -15.55),
    };
    return regions[regionName];
  }
}
