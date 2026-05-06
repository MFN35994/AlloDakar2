import "package:flutter/foundation.dart";
import "package:firebase_core/firebase_core.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:transen_core/transen_core.dart';

class MapMarkerUtils {
  static BitmapDescriptor? _cachedCarIcon;

  static Future<BitmapDescriptor> getCarIcon() async {
    if (_cachedCarIcon != null) return _cachedCarIcon!;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 48.0;

    final paint = Paint()..color = TranSenColors.primaryGreen;
    
    // Corps voiture
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(8, 16, 32, 20), const Radius.circular(6)),
      paint,
    );
    // Toit
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(14, 8, 20, 12), const Radius.circular(4)),
      paint,
    );
    // Roue avant
    canvas.drawCircle(const Offset(14, 36), 5, Paint()..color = Colors.black87);
    // Roue arriere
    canvas.drawCircle(const Offset(34, 36), 5, Paint()..color = Colors.black87);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    _cachedCarIcon = BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
    return _cachedCarIcon!;
  }
}
