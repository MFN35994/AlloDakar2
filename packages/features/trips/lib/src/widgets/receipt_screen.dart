import "package:flutter/foundation.dart";
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:transen_core/transen_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';


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
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Le partage de reçu n'est pas encore disponible sur Web.")),
      );
      return;
    }
    
    try {
      RenderRepaintBoundary? boundary = _boundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final buffer = byteData.buffer.asUint8List();
      
      // On utilise XFile directement pour éviter l'import de dart:io
      final xFile = XFile.fromData(
        buffer,
        name: 'recu_${widget.orderId}.png',
        mimeType: 'image/png',
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: 'Mon reçu TranSen 🚕',
        ),
      );

    } catch (e) {
      debugPrint("Erreur capture reçu: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Reçu de Course'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black87,
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
                      color: isDark ? Colors.grey[900] : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('trips').doc(widget.tripId).snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const CircularProgressIndicator(strokeWidth: 2);
                            }

                            String statusText = "Demande annulée";
                            Color statusColor = Colors.red;
                            
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final status = snapshot.data!.get('status');
                              if (status == 'pending') {
                                statusText = "En attente";
                                statusColor = Colors.grey;
                              } else if (status == 'accepted' || status == 'departed') {
                                statusText = "En cours";
                                statusColor = Colors.orange;
                              } else if (status == 'completed') {
                                statusText = "Effectué";
                                statusColor = Colors.green;
                              } else if (status == 'cancelled') {
                                statusText = "Annulé";
                                statusColor = Colors.red;
                              }
                            } else {
                              // Si pas dans trips, on regarde dans pools
                              return StreamBuilder<DocumentSnapshot>(
                                stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('pools').doc(widget.tripId).snapshots(),
                                builder: (context, poolSnapshot) {
                                   if (poolSnapshot.connectionState == ConnectionState.waiting) {
                                     return const CircularProgressIndicator(strokeWidth: 2);
                                   }

                                   String pText = "Demande annulée";
                                   Color pColor = Colors.red;

                                   if (poolSnapshot.hasData && poolSnapshot.data!.exists) {
                                     final pStatus = poolSnapshot.data!.get('status');
                                     if (pStatus == 'open' || pStatus == 'full') {
                                       pText = "En attente";
                                       pColor = Colors.grey;
                                     } else if (pStatus == 'accepted' || pStatus == 'departed') {
                                       pText = "En cours";
                                       pColor = Colors.orange;
                                     } else if (pStatus == 'completed') {
                                       pText = "Effectué";
                                       pColor = Colors.green;
                                     } else if (pStatus == 'cancelled') {
                                       pText = "Annulé";
                                       pColor = Colors.red;
                                     }
                                   }

                                   return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: pColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: pColor.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        pText,
                                        style: TextStyle(
                                          color: pColor,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                   );
                                }
                              );
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            );
                          }
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.price,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : Colors.black87,
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
                                  color: isDark ? Colors.white24 : Colors.grey.shade300,
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
                  backgroundColor: TranSenColors.primaryGreen,

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
          style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.grey.shade600, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            fontSize: 14,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }
}
