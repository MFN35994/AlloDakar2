import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../home/trip_tracking_screen.dart';

class ReceiptScreen extends StatefulWidget {
  final String orderId;
  final String departure;
  final String destination;
  final String price;
  final String type;
  final String tripId;

  const ReceiptScreen({
    super.key,
    required this.orderId,
    required this.departure,
    required this.destination,
    required this.price,
    required this.type,
    required this.tripId,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final GlobalKey _boundaryKey = GlobalKey();

  Future<void> _captureAndShare() async {
    try {
      RenderRepaintBoundary? boundary = _boundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final buffer = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file =
          await File('${tempDir.path}/recu_${widget.orderId}.png').create();
      await file.writeAsBytes(buffer);

      await Share.shareXFiles([XFile(file.path)],
          text: 'Mon reçu Allô Dakar 🚗');
    } catch (e) {
      debugPrint("Erreur capture reçu: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Reçu de Course'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            RepaintBoundary(
              key: _boundaryKey,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 40),
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Commande Réussi',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.price,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: List.generate(
                            30,
                            (index) => Expanded(
                              child: Container(
                                height: 1.5,
                                color: index % 2 == 0
                                    ? Colors.grey.shade300
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        _buildReceiptRow('ID Commande', widget.orderId),
                        const SizedBox(height: 15),
                        _buildReceiptRow('Type', widget.type),
                        const SizedBox(height: 15),
                        if (widget.type.contains('Covoiturage')) ...[
                          _buildReceiptRow('Frais Plateforme (5%)', '500 FCFA'),
                          const SizedBox(height: 15),
                        ],
                        _buildReceiptRow('Date',
                            '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}'),
                        const SizedBox(height: 30),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                const Icon(Icons.my_location,
                                    color: Colors.blueAccent, size: 20),
                                Container(
                                  height: 30,
                                  width: 2,
                                  color: Colors.grey.shade300,
                                ),
                                const Icon(Icons.location_on,
                                    color: Colors.redAccent, size: 20),
                              ],
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.departure,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 28),
                                  Text(
                                    widget.destination,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.3),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      padding: const EdgeInsets.all(0),
                      child: const SizedBox(
                        width: 80,
                        height: 80,
                        child: Icon(
                          Icons.check_circle_outline,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              TripTrackingScreen(tripId: widget.tripId)));
                },
                icon: const Icon(Icons.map, color: Colors.white),
                label: const Text(
                  'SUIVRE MA COMMANDE',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _captureAndShare,
                icon: const Icon(Icons.image, color: Colors.white),
                label: const Text(
                  'PARTAGER LE REÇU (PNG)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 5,
                  shadowColor: Colors.blueAccent.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}
