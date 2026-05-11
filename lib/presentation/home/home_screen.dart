import 'dart:ui' as ui;
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
                        child: GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 4,
                          mainAxisSpacing: 15,
                          crossAxisSpacing: 12,
                          children: [
                            _buildCompactAction(context, 'Course', Icons.directions_car, TranSenColors.primaryGreen, () => OrderSheet.show(context)),
                            _buildCompactAction(context, 'Yobanté', Icons.inventory_2, Colors.blue, () => YobanteSheet.show(context)),
                            _buildCompactAction(context, 'Favoris', Icons.favorite, Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()))),
                            _buildCompactAction(context, 'Parrainage', Icons.card_giftcard, Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReferralScreen()))),
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
                      loading: () => const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))),
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

  Widget _buildCompactAction(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return PremiumActionCard(
      label: label,
      icon: icon,
      color: color,
      onTap: onTap,
    );
  }

  Widget _buildHistoryItem(BuildContext context, TripModel trip) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _showTripDetails(context, trip),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!, width: 0.5)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: trip.type.contains('Yobanté') ? Colors.blue.withValues(alpha: 0.1) : TranSenColors.primaryGreen.withValues(alpha: 0.1),
              child: Icon(
                trip.type.contains('Yobanté') ? Icons.inventory_2 : Icons.directions_car,
                size: 18,
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
              "-${trip.price.toInt()} F",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TripDetailsSheet(trip: trip),
    );
  }


  Widget _buildActiveTripCard(BuildContext context, TripModel trip, {required bool isYobante}) {
    final color = isYobante ? Colors.blue : TranSenColors.primaryGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: Icon(isYobante ? Icons.inventory_2 : Icons.directions_car, color: Colors.white)),
        title: Text(isYobante ? "Livraison en cours..." : "Course en cours...", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        subtitle: Text("${trip.departure} ➔ ${trip.destination}"),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: color),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripTrackingScreen(tripId: trip.id))),
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

class _TripDetailsSheet extends StatelessWidget {
  final TripModel trip;
  const _TripDetailsSheet({required this.trip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        children: [
          Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 30),
          Icon(trip.type.contains('Yobanté') ? Icons.inventory_2 : Icons.directions_car, size: 48, color: TranSenColors.primaryGreen),
          const SizedBox(height: 10),
          Text("-${trip.price.toInt()} F", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          Text("Payé à ${trip.driverName ?? 'Chauffeur'}", style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          _buildStatusDisplay(trip),
          _buildDetailRow("Date et heure", "${trip.createdAt.day} ${_getMonth(trip.createdAt.month)} ${trip.createdAt.year} ${trip.createdAt.hour}:${trip.createdAt.minute}", null),
          _buildDetailRow("Départ", trip.departure, null),
          _buildDetailRow("Destination", trip.destination, null),
          _buildDetailRow("Mode de paiement", trip.paymentMethod ?? "Cash / SenePay", null),
          _buildDetailRow("ID Transaction", "TR-${trip.id.substring(0, 8).toUpperCase()}", null),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final text = "Reçu de trajet TranSen\n"
                        "De : ${trip.departure}\n"
                        "À : ${trip.destination}\n"
                        "Montant : ${trip.price.toInt()} FCFA\n"
                        "Date : ${trip.createdAt.day}/${trip.createdAt.month}/${trip.createdAt.year}\n"
                        "ID : TR-${trip.id.substring(0, 8).toUpperCase()}";
                    Share.share(text);
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text("PARTAGER"),
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
