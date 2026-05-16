// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:transen_core/transen_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:transen_maps/transen_maps.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:transen_trips/transen_trips.dart' as providers;
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_profile/transen_profile.dart';
import 'package:transen_payment/transen_payment.dart';
import 'package:transen/presentation/widgets/profile_drawer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

final activeDriversStreamProvider = StreamProvider<Set<Marker>>((ref) {
  return FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
      .collection('active_drivers')
      .snapshots()
      .asyncMap((snapshot) async {
    final markers = <Marker>{};
    final icon = await MapMarkerUtils.getCarIcon();
    
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final driverId = doc.id;
      if (data['status'] != 'online') continue;
      
      if (data['lastUpdated'] != null) {
        final lastUpdated = (data['lastUpdated'] as Timestamp).toDate();
        if (DateTime.now().difference(lastUpdated).inMinutes > 10) continue;
      }
      
      final dep = data['departure'];
      final dest = data['destination'];
      final note = data['note'];
      String snippet = "Chauffeur actif";
      if (dep != null || dest != null) {
        snippet = "Trajet : ${dep ?? '?'} ➔ ${dest ?? '?'}";
        if (note != null && note.toString().isNotEmpty) {
          snippet += " | $note";
        }
      }
      
      markers.add(Marker(
        markerId: MarkerId(driverId),
        position: LatLng(data['lat'], data['lng']),
        infoWindow: InfoWindow(
          title: data['driverName'] ?? 'Chauffeur TranSen',
          snippet: snippet,
        ),
        icon: icon,
      ));
    }
    return markers;
  });
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(14.7167, -17.4677),
    zoom: 13.0,
  );
  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    final driverMarkers = ref.watch(activeDriversStreamProvider).value ?? {};
    final userId = ref.watch(authProvider)?.userId ?? '';
    final historyAsync = ref.watch(providers.tripHistoryProvider(userId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.grey[100],
      appBar: AppBar(
        title: const Text('TranSen', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: TranSenColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      drawer: const ProfileDrawer(),
      body: Column(
        children: [
          // MAP COMPACTE
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.40,
            child: GoogleMap(
              initialCameraPosition: _initialPosition,
              onMapCreated: (GoogleMapController controller) async {
                _mapController = controller;
                try {
                  Position position = await Geolocator.getCurrentPosition();
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
                  );
                } catch (_) {}
              },
              markers: driverMarkers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
          
          // ACTIONS & HISTORIQUE
          Expanded(
            child: Stack(
              children: [
                // Fond flou (Glassmorphism)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.6),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  child: CustomScrollView(
                  slivers: [
                    // ACTIVE TRIPS
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                        child: Consumer(builder: (context, ref, child) {
                          final activePoolAsync = ref.watch(providers.activePoolProvider);
                          final activeTripAsync = ref.watch(providers.activeTripProvider);
                          return Column(
                            children: [
                              activePoolAsync.when(
                                data: (pool) => pool == null ? const SizedBox.shrink() : _buildActiveTripCard(context, pool, isYobante: false),
                                loading: () => const SizedBox.shrink(),
                                error: (_, __) => const SizedBox.shrink(),
                              ),
                              activeTripAsync.when(
                                data: (trip) => trip == null ? const SizedBox.shrink() : _buildActiveTripCard(context, trip, isYobante: true),
                                loading: () => const SizedBox.shrink(),
                                error: (_, __) => const SizedBox.shrink(),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),

                    // GRID ACTIONS COMPACTE (Style Wave)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: PremiumPulseCard(
                                    label: 'Course',
                                    sublabel: 'Commander un trajet',
                                    icon: Icons.directions_car,
                                    gradientColors: const [Color(0xFF1A3A2A), Color(0xFF2E7D32)],
                                    iconColor: const Color(0xFF81C784),
                                    onTap: () => OrderSheet.show(context),
                                    animated: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: PremiumPulseCard(
                                    label: 'Yobanté',
                                    sublabel: 'Envoyer un colis',
                                    icon: Icons.inventory_2,
                                    gradientColors: const [Color(0xFF1A3A5C), Color(0xFF0D6EFD)],
                                    iconColor: const Color(0xFF5BB8FF),
                                    onTap: () => YobanteSheet.show(context),
                                    animated: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: PremiumPulseCard(
                                    label: 'Favoris',
                                    sublabel: 'Lieux enregistrés',
                                    icon: Icons.favorite,
                                    gradientColors: const [Color(0xFF1A1A3A), Color(0xFF4527A0)],
                                    iconColor: const Color(0xFFB39DDB),
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen())),
                                    animated: false,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: PremiumPulseCard(
                                    label: 'Parrainage',
                                    sublabel: 'Gagner des points',
                                    icon: Icons.card_giftcard,
                                    gradientColors: const [Color(0xFF3A2A00), Color(0xFFF9A825)],
                                    iconColor: const Color(0xFFFFD54F),
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReferralScreen())),
                                    animated: false,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: Divider(height: 30, thickness: 1)),

                    // HISTORIQUE
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("HISTORIQUE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                            TextButton(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
                              child: const Text("Plus d'historique", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: TranSenColors.primaryGreen)),
                            ),
                          ],
                        ),
                      ),
                    ),

                    historyAsync.when(
                      data: (trips) {
                        final items = trips.take(12).toList();
                        if (items.isEmpty) {
                          return const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(child: Text("Aucun trajet récent", style: TextStyle(color: Colors.grey))),
                          );
                        }
                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildHistoryItem(context, items[index]),
                            childCount: items.length,
                          ),
                        );
                      },
                      loading: () => SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildHistoryShimmer(context),
                          childCount: 5,
                        ),
                      ),
                      error: (e, _) => SliverToBoxAdapter(child: Center(child: Text("Erreur: $e"))),
                    ),
                    
                    const SliverToBoxAdapter(child: SizedBox(height: 50)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: () async {
          try {
            Position pos = await Geolocator.getCurrentPosition();
            _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)));
          } catch (_) {}
        },
        backgroundColor: Colors.white,
        foregroundColor: TranSenColors.primaryGreen,
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, TripModel trip) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        _showTripDetails(context, trip);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!, width: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: trip.type.contains('Yobanté') ? Colors.blue.withValues(alpha: 0.1) : TranSenColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                trip.type.contains('Yobanté') ? Icons.inventory_2 : Icons.directions_car,
                size: 20,
                color: trip.type.contains('Yobanté') ? Colors.blue : TranSenColors.primaryGreen,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip.destination, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                  Text(
                    "${trip.createdAt.day} ${_getMonth(trip.createdAt.month)}, ${trip.createdAt.hour}:${trip.createdAt.minute.toString().padLeft(2, '0')}",
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              "${trip.price.toInt()} F",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.white10 : Colors.grey[300]!,
      highlightColor: isDark ? Colors.white24 : Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        child: Row(
          children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 150, height: 12, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(width: 80, height: 10, color: Colors.white),
                ],
              ),
            ),
            Container(width: 60, height: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }

  String _getMonth(int month) {
    const months = ['janv', 'févr', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc'];
    return months[month - 1];
  }

  void _showTripDetails(BuildContext context, TripModel trip) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      useSafeArea: true,
      builder: (context) => _TripDetailsSheet(trip: trip),
    );
  }


  Widget _buildActiveTripCard(BuildContext context, TripModel trip, {required bool isYobante}) {
    final color = isYobante ? Colors.blue : TranSenColors.primaryGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Icon(isYobante ? Icons.inventory_2 : Icons.directions_car, color: Colors.white, size: 22),
            ),
            title: Text(
              isYobante ? "LIVRAISON EN COURS" : "COURSE EN COURS",
              style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 12, letterSpacing: 1.2),
            ),
            subtitle: Text(
              "${trip.departure} ➔ ${trip.destination}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(Icons.arrow_forward_ios, size: 14, color: color),
            ),
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.push(context, MaterialPageRoute(builder: (_) => TripTrackingScreen(tripId: trip.id)));
            },
          ),
        ),
      ),
    );
  }
}

class PremiumActionCard extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const PremiumActionCard({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<PremiumActionCard> createState() => _PremiumActionCardState();
}

class _PremiumActionCardState extends State<PremiumActionCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: SweepGradient(
                    center: Alignment.center,
                    startAngle: 0.0,
                    endAngle: 3.14 * 2,
                    colors: [
                      widget.color.withValues(alpha: 0.0),
                      widget.color,
                      widget.color.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                    transform: GradientRotation(_controller.value * 3.14 * 2),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF252525) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        widget.onTap();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(child: Icon(widget.icon, color: widget.color, size: 32)),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label, 
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _TripDetailsSheet extends StatefulWidget {
  final TripModel trip;
  const _TripDetailsSheet({required this.trip});

  @override
  State<_TripDetailsSheet> createState() => _TripDetailsSheetState();
}

class _TripDetailsSheetState extends State<_TripDetailsSheet> {
  final GlobalKey _receiptKey = GlobalKey();
  bool _isGenerating = false;

  Future<void> _shareReceiptImage() async {
    HapticFeedback.mediumImpact();
    setState(() => _isGenerating = true);
    try {
      // 1. Capture du widget
      RenderRepaintBoundary boundary = _receiptKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // 2. Sauvegarde temporaire
      final directory = await getTemporaryDirectory();
      final imagePath = await File('${directory.path}/recu_transen_${widget.trip.id.substring(0,8)}.png').create();
      await imagePath.writeAsBytes(pngBytes);

      // 3. Partage
      await Share.shareXFiles(
        [XFile(imagePath.path)],
        text: 'Reçu de trajet TranSen - ${widget.trip.price.toInt()} FCFA',
      );
    } catch (e) {
      debugPrint("Erreur partage reçu: $e");
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
      child: Column(
        children: [
          Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 20),
          
          // LA ZONE DE CAPTURE (LE REÇU)
          Expanded(
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _receiptKey,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF252525) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: TranSenColors.primaryGreen.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Column(
                    children: [
                      // LOGO & HEADER
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Image.asset('assets/images/logo.png', height: 40),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("REÇU", style: TextStyle(fontWeight: FontWeight.w900, color: TranSenColors.primaryGreen, fontSize: 18, letterSpacing: 2)),
                              Text("DE PAIEMENT", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 30),
                      
                      // MONTANT
                      Text("-${widget.trip.price.toInt()} F", style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: TranSenColors.primaryGreen)),
                      Text("Payé à ${widget.trip.driverName ?? 'Chauffeur'}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 25),
                      
                      // DETAILS
                      _buildStatusDisplay(widget.trip),
                      _buildDetailRow("Date", "${widget.trip.createdAt.day} ${_getMonth(widget.trip.createdAt.month)} ${widget.trip.createdAt.year}", null),
                      _buildDetailRow("Heure", "${widget.trip.createdAt.hour}:${widget.trip.createdAt.minute.toString().padLeft(2,'0')}", null),
                      _buildDetailRow("Départ", widget.trip.departure, null),
                      _buildDetailRow("Destination", widget.trip.destination, null),
                      _buildDetailRow("ID Trans.", "TR-${widget.trip.id.substring(0, 8).toUpperCase()}", null),
                      
                      const SizedBox(height: 30),
                      const Text("Merci d'avoir choisi TranSen !", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isGenerating ? null : _shareReceiptImage,
                  icon: _isGenerating 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.share, size: 18),
                  label: Text(_isGenerating ? "GÉNÉRATION..." : "PARTAGER L'IMAGE"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TranSenColors.primaryGreen,
                    side: const BorderSide(color: TranSenColors.primaryGreen),
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TranSenColors.primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("FERMER"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDisplay(TripModel trip) {
    String text = "En attente";
    Color color = Colors.grey;
    if (trip.status == 'accepted' || trip.status == 'departed') {
      text = "En cours";
      color = Colors.orange;
    } else if (trip.status == 'completed') {
      text = "Effectué";
      color = Colors.green;
    } else if (trip.status == 'cancelled') {
      text = "Annulé";
      color = Colors.red;
    } else if (trip.status == 'open' || trip.status == 'full') {
      text = "En attente";
      color = Colors.blue;
    }
    return _buildDetailRow("Statut", text, color);
  }

  Widget _buildDetailRow(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  String _getMonth(int month) {
    const months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    return months[month - 1];
  }
}

class PremiumPulseCard extends StatefulWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final List<Color> gradientColors;
  final Color iconColor;
  final VoidCallback onTap;
  final bool animated;

  const PremiumPulseCard({
    super.key,
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.gradientColors,
    required this.iconColor,
    required this.onTap,
    this.animated = false,
  });

  @override
  State<PremiumPulseCard> createState() => _PremiumPulseCardState();
}

class _PremiumPulseCardState extends State<PremiumPulseCard> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    if (widget.animated) {
      Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted) {
          _pulseController.forward().then((value) => _pulseController.reverse());
        } else {
          timer.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ScaleTransition(
      scale: widget.animated ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
      child: AnimatedBuilder(
        animation: _rotateController,
        builder: (context, child) {
          return Container(
            padding: EdgeInsets.all(widget.animated ? 2 : 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: widget.animated ? SweepGradient(
                center: Alignment.center,
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white,
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.5, 1.0],
                transform: GradientRotation(_rotateController.value * 3.14 * 2),
              ) : null,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(16),
                  splashColor: Colors.white.withValues(alpha: 0.1),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: widget.gradientColors.last.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(widget.icon, color: widget.iconColor, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.label,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(widget.sublabel,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.4), size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }
}
