import 'dart:math';
import 'package:geolocator/geolocator.dart';

class LocationHelper {
  static const Map<String, List<double>> _regionCenters = {
    'Dakar': [14.7167, -17.4677],
    'Thiès': [14.791, -16.936],
    'Diourbel': [14.65, -16.23],
    'Saint-Louis': [16.02, -16.50],
    'Louga': [15.61, -16.22],
    'Fatick': [14.33, -16.40],
    'Kaolack': [14.14, -16.07],
    'Kaffrine': [14.10, -15.54],
    'Tambacounda': [13.77, -13.67],
    'Kédougou': [12.55, -12.17],
    'Kolda': [12.88, -14.94],
    'Sédhiou': [12.70, -15.55],
    'Ziguinchor': [12.58, -16.27],
    'Matam': [15.65, -13.25],
  };

  static String detectRegion(Position pos) {
    String closestRegion = 'Dakar';
    double minDistance = double.infinity;

    _regionCenters.forEach((name, coords) {
      final distance = _calculateDistance(
        pos.latitude, 
        pos.longitude, 
        coords[0], 
        coords[1]
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestRegion = name;
      }
    });

    return closestRegion;
  }

  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) *
            (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }
}
