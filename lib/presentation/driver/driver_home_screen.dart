import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_rating/transen_rating.dart';
import 'package:transen_payment/transen_payment.dart';
import 'package:shimmer/shimmer.dart';
import 'package:transen_profile/transen_profile.dart';
import 'package:transen/presentation/widgets/profile_drawer.dart';
import 'trip_detail_screen.dart';
import 'pool_detail_screen.dart';
import 'destination_pools_screen.dart';
import 'active_deliveries_sheet.dart';

final pendingTripsProvider =
    StreamProvider.family<List<TripModel>, String>((ref, filterStr) {
  final parts = filterStr.split('|');
  final dep = parts[0] == 'ANY' ? null : parts[0];
  final dest = parts[1] == 'ANY' ? null : parts[1];

  return ref.watch(tripRepositoryProvider).getPendingTrips(
        departure: dep,
        destination: dest,
      );
});

final driverRouteStreamProvider =
    StreamProvider.family<DocumentSnapshot, String>((ref, driverId) {
  return ref.watch(tripRepositoryProvider).getDriverRoute(driverId);
});

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(14.7167, -17.4677),
    zoom: 13.0,
  );

  GoogleMapController? _mapController;
  bool _isOnline = false;
  Timer? _locationTimer;
  String? _currentDriverId;
  String? _pubDeparture;
  String? _pubDestination;
  bool _isAutoFull = false;
  final _noteController = TextEditingController();
  final Set<String> _ignoredPoolIds = {};

  final List<String> _regions = [
    'Dakar',
    'Diourbel',
    'Fatick',
    'Kaffrine',
    'Kaolack',
    'Kédougou',
    'Kolda',
    'Louga',
    'Matam',
    'Saint-Louis',
    'Sédhiou',
    'Tambacounda',
    'Thiès',
    'Ziguinchor',
  ];

  @override
  void initState() {
    super.initState();
    _initInitialPosition();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Déclencher le flash toutes les 10 secondes
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _pulseController.forward().then((value) => _pulseController.reverse());
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _initInitialPosition() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _locationTimer?.cancel();
    // Marquer comme hors ligne à la fermeture
    if (_isOnline && _currentDriverId != null) {
      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
          .collection('active_drivers')
          .doc(_currentDriverId)
          .delete();
    }
    _noteController.dispose();
    super.dispose();
  }

  void _toggleOnline(bool val, String driverId) async {
    _currentDriverId = driverId;
    if (val) {
      // 1. Vérifier si le service de localisation est activé
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "Veuillez activer la localisation sur votre téléphone.")),
          );
        }
        return;
      }

      // 2. Vérifier les permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "Permission de localisation refusée. Veuillez l'activer dans les paramètres.")),
          );
        }
        return;
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        // Récupérer les infos du profil une seule fois
        final userDoc = await FirebaseFirestore.instanceFor(
                app: Firebase.app(), databaseId: 'transen')
            .collection('users')
            .doc(driverId)
            .get();
        final userData = userDoc.data();
        final name = userData?['name'] ?? 'Chauffeur TranSen';

        final phone = userData?['phone'] ?? '';

        setState(() => _isOnline = true);
        _startLocationUpdates(driverId, name, phone);
      }
    } else {
      setState(() {
        _isOnline = false;
        _isAutoFull = false; // Reset auto-full
      });
      _locationTimer?.cancel();
      // Supprimer le marqueur actif
      await FirebaseFirestore.instanceFor(
              app: Firebase.app(), databaseId: 'transen')
          .collection('active_drivers')
          .doc(driverId)
          .delete();
    }
  }

  void _startLocationUpdates(String driverId, String name, String phone) {
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition();
        await FirebaseFirestore.instanceFor(
                app: Firebase.app(), databaseId: 'transen')
            .collection('active_drivers')
            .doc(driverId)
            .set({
          'lat': position.latitude,
          'lng': position.longitude,
          'lastUpdated': FieldValue.serverTimestamp(),
          'status': 'online',
          'driverName': name,
          'driverPhone': phone,
          'departure': _pubDeparture,
          'destination': _pubDestination,
          'note': _noteController.text.trim(),
        });
      } catch (e) {
        debugPrint("Erreur update position: $e");
      }
    });
  }

  Future<void> _acceptTripDirectly(TripModel trip) async {
    final auth = ref.read(authProvider);
    if (auth == null) return;
    
    try {
      // Pré-validation financière
      final subInfo = await SubscriptionService().checkSubscription(auth.userId);
      final wallet = ref.read(walletProvider);
      final commission = trip.price * 0.01;

      if (!subInfo.isActive && wallet.balance < commission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Solde insuffisant pour la commission (${commission.toInt()} F). Rechargez votre portefeuille."),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: "RECHARGER",
                textColor: Colors.white,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Acceptation en cours..."), duration: Duration(milliseconds: 500)),
        );
      }

      await ref.read(tripRepositoryProvider).acceptTrip(trip.id, auth.userId);
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TripDetailScreen(trip: trip),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _acceptPoolDirectly(PoolModel pool) async {
    final auth = ref.read(authProvider);
    if (auth == null) return;
    
    try {
      // Pré-validation financière
      final subInfo = await SubscriptionService().checkSubscription(auth.userId);
      final wallet = ref.read(walletProvider);
      final commission = (pool.currentFilling * 10000) * 0.01;

      if (!subInfo.isActive && wallet.balance < commission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Solde insuffisant pour la commission (${commission.toInt()} F). Rechargez votre portefeuille."),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: "RECHARGER",
                textColor: Colors.white,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
              ),
            ),
          );
        }
        return;
      }

      // Confirmation si peu de passagers
      if (pool.currentFilling < 3) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Départ anticipé ?"),
            content: Text("Il n'y a que ${pool.currentFilling} passager(s). Voulez-vous quand même accepter ce trajet ?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ANNULER")),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("OUI, ACCEPTER")),
            ],
          ),
        );
        if (confirm != true) return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Acceptation en cours..."), duration: Duration(milliseconds: 500)),
        );
      }

      await ref.read(tripRepositoryProvider).acceptPool(pool.id, auth.userId);
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PoolDetailScreen(pool: pool),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final wallet = ref.watch(walletProvider);
    final currentUserId = auth?.userId ?? 'unknown_driver';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('TranSen'),
            const SizedBox(width: 5),
            Consumer(builder: (context, ref, child) {
              final auth = ref.watch(authProvider);
              if (auth == null) return const SizedBox.shrink();
              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instanceFor(
                        app: Firebase.app(), databaseId: 'transen')
                    .collection('users')
                    .doc(auth.userId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasData &&
                      (snapshot.data!.data()
                              as Map<String, dynamic>?)?['isVerified'] ==
                          true) {
                    return const Icon(Icons.verified,
                        color: Colors.blue, size: 18);
                  }
                  return const SizedBox.shrink();
                },
              );
            }),
          ],
        ),
        backgroundColor: TranSenColors.darkGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Row(
            children: [
              Text(
                _isOnline ? 'En Ligne' : 'Hors Ligne',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isOnline ? Colors.greenAccent : Colors.white54,
                ),
              ),
              Switch(
                value: _isOnline,
                activeThumbColor: Colors.greenAccent,
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.white24,
                onChanged: (val) async {
                  await HapticFeedback.mediumImpact();
                  _toggleOnline(val, currentUserId);
                },
              ),
              IconButton(
                onPressed: () => DriverReviewsSheet.show(
                    context, currentUserId, auth?.name ?? 'Moi'),
                icon: const Icon(Icons.stars, color: Colors.amber),
                tooltip: "Mes Avis",
              ),
            ],
          ),
        ],
      ),
      drawer: const ProfileDrawer(),
      body: Column(
        children: [
          // ── BANNIÈRE ABONNEMENT ──────────────────────────────────────
          StreamBuilder<SubscriptionInfo>(
            stream: SubscriptionService().watchSubscription(currentUserId),
            builder: (context, snapshot) {
              final info = snapshot.data;
              if (info == null) return const SizedBox.shrink();
              
              // Si l'abonnement est actif et ne finit pas bientôt, on ne montre rien
              if (info.isActive && !info.expiresSOon) {
                return const SizedBox.shrink();
              }

              final isExpired = info.isExpired || info.isNone;
              final hasBalanceForCommission = wallet.balance >= 100; // Seuil arbitraire pour le message

              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: isExpired 
                    ? (hasBalanceForCommission ? Colors.blue.shade700 : Colors.red.shade700)
                    : Colors.orange.shade700,
                  child: Row(
                    children: [
                      Icon(
                        isExpired 
                          ? (hasBalanceForCommission ? Icons.info_outline : Icons.lock)
                          : Icons.warning_amber,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isExpired
                              ? (hasBalanceForCommission 
                                  ? 'ℹ️ Mode Commission (1%) actif — Abonnez-vous pour l\'illimité'
                                  : '⛔ Solde insuffisant pour la commission (1%) — Rechargez ou Abonnez-vous')
                              : '⚠️ Abonnement expire dans ${info.daysRemaining}j ${info.hoursRemaining}h — Appuyez pour renouveler',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white),
                    ],
                  ),
                ),
              );
            },
          ),
          // ────────────────────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.white,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: _initialPosition,
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                      _initInitialPosition();
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: FloatingActionButton(
                      onPressed: () async {
                        try {
                          Position position =
                              await Geolocator.getCurrentPosition();
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLng(
                                LatLng(position.latitude, position.longitude)),
                          );
                        } catch (e) {
                          debugPrint("Erreur recentrage: $e");
                        }
                      },
                      backgroundColor: Colors.white,
                      child:
                          const Icon(Icons.my_location, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Container(
              color: Colors.white,
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        /*
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Consumer(builder: (context, ref, child) {
                                final rating = ref.watch(driverRatingProvider(currentUserId)).value ?? 0.0;
                                final count = ref.watch(driverRatingCountProvider(currentUserId)).value ?? 0;
                                return _buildStatChip(Icons.star, "${rating.toStringAsFixed(1)} ($count)", Colors.amber);
                              }),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Consumer(builder: (context, ref, child) {
                                final occupancy = ref.watch(driverOccupancyProvider(currentUserId)).value ?? 0;
                                return _buildStatChip(Icons.groups, "$occupancy / 4", Colors.green);
                              }),
                            ),
                          ],
                        ),
                      ),
                      */

                        if (_isOnline) ...[
                          Consumer(builder: (context, ref, child) {
                            final activePoolAsync =
                                ref.watch(driverActivePoolProvider);
                            return activePoolAsync.when(
                              data: (pool) => pool == null
                                  ? const SizedBox.shrink()
                                  : _buildActiveDriverTripCard(context, pool),
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          }),
                          Consumer(builder: (context, ref, child) {
                            final activeTripAsync =
                                ref.watch(driverActiveTripProvider);
                            return activeTripAsync.when(
                              data: (trip) => trip == null
                                  ? const SizedBox.shrink()
                                  : _buildActiveVtcTripCard(context, trip),
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          }),
                          Consumer(builder: (context, ref, child) {
                            final activeDeliveriesAsync =
                                ref.watch(driverActiveDeliveriesProvider);
                            return activeDeliveriesAsync.when(
                              data: (deliveries) => deliveries.isEmpty
                                  ? const SizedBox.shrink()
                                  : _buildActiveDeliveriesBanner(context, deliveries),
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          }),
                          // ── CARTE TRAJET COMPACTE ────────────────────────────
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  TranSenColors.darkGreen,
                                  TranSenColors.primaryGreen.withValues(alpha: 0.85),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: TranSenColors.primaryGreen.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _showRouteBottomSheet(context, ref, currentUserId),
                                  child: const Icon(Icons.route, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _showRouteBottomSheet(context, ref, currentUserId),
                                    child: Text(
                                      _pubDeparture == null && _pubDestination == null
                                          ? 'Définir mon trajet du jour...'
                                          : '${_pubDeparture ?? '—'}  →  ${_pubDestination ?? '—'}',
                                      style: TextStyle(
                                        color: _pubDeparture == null
                                            ? Colors.white60
                                            : Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (_pubDeparture != null || _pubDestination != null)
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      setState(() {
                                        _pubDeparture = null;
                                        _pubDestination = null;
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("Trajet annulé.")),
                                      );
                                    },
                                  ),
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: () => _showRouteBottomSheet(context, ref, currentUserId),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Modifier',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── BOUTONS D'ACTION RAPIDE 2×2 ──────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Consumer(builder: (context, ref, child) {
                              final subStream = SubscriptionService().watchSubscription(currentUserId);
                              return StreamBuilder<SubscriptionInfo>(
                                stream: subStream,
                                builder: (context, subSnap) {
                                  final subInfo = subSnap.data;
                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          // ── TransPay
                                          Expanded(
                                            child: _buildQuickActionTile(
                                              context: context,
                                              icon: Icons.account_balance_wallet_rounded,
                                              label: 'TransPay',
                                              sublabel: wallet.balance == 0.0 && wallet.transactions.isEmpty
                                                  ? 'chargement...'
                                                  : '${wallet.balance.toInt()} FCFA',
                                              isLoading: wallet.balance == 0.0 && wallet.transactions.isEmpty,
                                              gradientColors: const [Color(0xFF1A3A5C), Color(0xFF0D6EFD)],
                                              iconColor: const Color(0xFF5BB8FF),
                                              onTap: () {
                                                HapticFeedback.lightImpact();
                                                Navigator.push(context,
                                                    MaterialPageRoute(builder: (_) => const WalletScreen()));
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          // ── Abonnement
                                          Expanded(
                                            child: ScaleTransition(
                                              scale: _pulseAnimation,
                                              child: _buildQuickActionTile(
                                                context: context,
                                                icon: Icons.workspace_premium_rounded,
                                                label: 'Abonnement',
                                                sublabel: subSnap.connectionState == ConnectionState.waiting
                                                    ? 'chargement...'
                                                    : subInfo == null
                                                        ? 'Souscrire'
                                                        : subInfo.isActive
                                                            ? '${subInfo.daysRemaining}j restants'
                                                            : 'Renouveler',
                                                isLoading: subSnap.connectionState == ConnectionState.waiting,
                                                gradientColors: subInfo != null && subInfo.isExpired
                                                    ? const [Color(0xFF5C1A1A), Color(0xFFB71C1C)]
                                                    : const [Color(0xFF3A2A00), Color(0xFFF9A825)],
                                                iconColor: subInfo != null && subInfo.isExpired
                                                    ? Colors.red.shade300
                                                    : const Color(0xFFFFD54F),
                                                badge: subInfo != null && (subInfo.isExpired || subInfo.expiresSOon)
                                                    ? '!'
                                                    : null,
                                                onTap: () {
                                                  HapticFeedback.lightImpact();
                                                  Navigator.push(context,
                                                      MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          // ── Parrainage
                                          Expanded(
                                            child: _buildQuickActionTile(
                                              context: context,
                                              icon: Icons.card_giftcard_rounded,
                                              label: 'Parrainage',
                                              sublabel: 'Gagner des points',
                                              gradientColors: const [Color(0xFF1A3A2A), Color(0xFF2E7D32)],
                                              iconColor: const Color(0xFF81C784),
                                              onTap: () {
                                                HapticFeedback.lightImpact();
                                                Navigator.push(context,
                                                    MaterialPageRoute(builder: (_) => const ReferralScreen()));
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          // ── Historique
                                          Expanded(
                                            child: _buildQuickActionTile(
                                              context: context,
                                              icon: Icons.history_rounded,
                                              label: 'Historique',
                                              sublabel: 'Mes courses',
                                              gradientColors: const [Color(0xFF1A1A3A), Color(0xFF4527A0)],
                                              iconColor: const Color(0xFFB39DDB),
                                              onTap: () {
                                                HapticFeedback.lightImpact();
                                                Navigator.push(context,
                                                    MaterialPageRoute(builder: (_) => const HistoryScreen()));
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              );
                            }),
                          ),
                          // ─────────────────────────────────────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Zones de forte demande",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                TextButton.icon(
                                  onPressed: () => setState(
                                      () => _isAutoFull = !_isAutoFull),
                                  icon: Icon(
                                      _isAutoFull
                                          ? Icons.flash_on
                                          : Icons.flash_off,
                                      size: 16,
                                      color: _isAutoFull
                                          ? TranSenColors.accentGold
                                          : Colors.grey),
                                  label: Text(
                                      _isAutoFull
                                          ? "AUTO-FULL ACTIVÉ"
                                          : "AUTO-FULL DÉSACTIVÉ",
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: _isAutoFull
                                              ? TranSenColors.accentGold
                                              : Colors.grey)),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 50,
                            child: Consumer(builder: (context, ref, child) {
                              final heatmapAsync =
                                  ref.watch(demandHeatmapProvider);
                              return heatmapAsync.when(
                                data: (heatmap) {
                                  if (heatmap.isEmpty) {
                                    return const Center(
                                        child: Text(
                                            "Aucune demande en attente.",
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey)));
                                  }
                                  final sortedEntries = heatmap.entries.toList()
                                    ..sort(
                                        (a, b) => b.value.compareTo(a.value));
                                  return ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    itemCount: sortedEntries.length,
                                    itemBuilder: (context, index) {
                                      final entry = sortedEntries[index];
                                      return InkWell(
                                        onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    DestinationPoolsScreen(
                                                        destination:
                                                            entry.key))),
                                        child: Container(
                                          margin:
                                              const EdgeInsets.only(right: 10),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withValues(
                                                alpha: entry.value > 5
                                                    ? 0.2
                                                    : 0.05),
                                            borderRadius:
                                                BorderRadius.circular(15),
                                            border: Border.all(
                                                color: Colors.red
                                                    .withValues(alpha: 0.3)),
                                          ),
                                          child: Center(
                                              child: Text(
                                                  "${entry.key} (${entry.value} pers.)",
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.red))),
                                        ),
                                      );
                                    },
                                  );
                                },
                                loading: () => const SizedBox.shrink(),
                                error: (_, __) => const SizedBox.shrink(),
                              );
                            }),
                          ),

                          // === COURSES VTC EN ATTENTE ===
                          Consumer(builder: (context, ref, child) {
                            final tripsAsync = ref.watch(pendingTripsProvider(
                                "${_pubDeparture ?? 'ANY'}|ANY"));
                            return tripsAsync.when(
                              data: (trips) {
                                final vtcTrips = trips.where((t) {
                                  final type = t.type.toLowerCase();
                                  return !type.contains('livraison') &&
                                      !type.contains('colis') &&
                                      !type.contains('yobante') &&
                                      (_pubDeparture == null ||
                                          _pubDeparture ==
                                              'TOUTES LES RÉGIONS' ||
                                          t.departure == _pubDeparture);
                                }).toList();

                                if (vtcTrips.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 10),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Courses VTC',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16)),
                                          Text('${vtcTrips.length} demande(s)',
                                              style: const TextStyle(
                                                  color: TranSenColors
                                                      .primaryGreen,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      height: 130,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20),
                                        itemCount: vtcTrips.length,
                                        itemBuilder: (context, index) =>
                                            _buildVtcSmallCard(
                                                context, vtcTrips[index]),
                                      ),
                                    ),
                                  ],
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          }),

                          Consumer(builder: (context, ref, child) {
                            final deliveriesAsync = ref.watch(
                                pendingTripsProvider(
                                    "${_pubDeparture ?? 'ANY'}|ANY"));
                            return deliveriesAsync.when(
                              data: (trips) {
                                final deliveries = trips.where((t) {
                                  final type = t.type.toLowerCase();
                                  return (type.contains('livraison') ||
                                          type.contains('colis') ||
                                          type.contains('yobante')) &&
                                      (_pubDeparture == null ||
                                          _pubDeparture ==
                                              'TOUTES LES RÉGIONS' ||
                                          t.departure == _pubDeparture);
                                }).toList();

                                if (deliveries.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 10),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text("Livraisons Yobanté",
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16)),
                                          Text(
                                              "${deliveries.length} correspondances",
                                              style: const TextStyle(
                                                  color:
                                                      TranSenColors.accentGold,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      height: 160,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20),
                                        itemCount: deliveries.length,
                                        itemBuilder: (context, index) =>
                                            _buildDeliverySmallCard(
                                                context, deliveries[index]),
                                      ),
                                    ),
                                  ],
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          }),
                          Consumer(builder: (context, ref, child) {
                            final poolsAsyncValue = ref.watch(pendingPoolsProvider(
                                "${_pubDeparture ?? 'ANY'}|${_pubDestination ?? 'ANY'}"));
                            return poolsAsyncValue.when(
                              data: (pools) {
                                if (pools.isEmpty) {
                                  return Center(
                                      child: Padding(
                                          padding: const EdgeInsets.all(40.0),
                                          child: Text(
                                              _pubDeparture == null
                                                  ? 'Sélectionnez un trajet pour voir les covoiturages.'
                                                  : 'Aucun groupe de voyageur pour le moment.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color:
                                                      Colors.grey.shade600))));
                                }
                                final sortedPools = pools
                                    .where(
                                        (p) => !_ignoredPoolIds.contains(p.id))
                                    .toList();
                                if (_isAutoFull) {
                                  sortedPools.sort((a, b) => b.currentFilling
                                      .compareTo(a.currentFilling));
                                }

                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 10, 20, 20),
                                  child: Column(
                                    children: [
                                      const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Groupes à destination',
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      const SizedBox(height: 15),
                                      ...sortedPools.map((pool) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 15),
                                            child: _buildPoolCard(
                                                pool: pool,
                                                driverId: currentUserId),
                                          )),
                                    ],
                                  ),
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const Center(
                                  child: Text("Erreur d'accès aux groupes")),
                            );
                          }),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(40),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.power_settings_new,
                                    size: 60, color: Colors.grey.shade300),
                                const SizedBox(height: 15),
                                Text('Vous êtes hors ligne',
                                    style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 5),
                                Text(
                                    'Passez en ligne pour recevoir des courses.',
                                    style:
                                        TextStyle(color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoolCard({required PoolModel pool, required String driverId}) {
    final canAcceptAt3 = pool.currentFilling >= 3;
    final isFull = pool.currentFilling >= 4;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: InkWell(
          onTap: null, // Désactivé selon demande utilisateur
          borderRadius: BorderRadius.circular(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 15,
                  spreadRadius: 1,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: TranSenColors.primaryGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.groups,
                        color: TranSenColors.primaryGreen, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Trajet ${pool.departure} ➔ ${pool.destination}",
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "Prévu pour le: ${pool.scheduledDate}",
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                  if (isFull)
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 24)
                  else ...[
                    if (canAcceptAt3)
                      const Icon(Icons.info_outline,
                          color: TranSenColors.primaryGreen, size: 20),
                    IconButton(
                      icon:
                          const Icon(Icons.close, color: Colors.grey, size: 20),
                      onPressed: () =>
                          setState(() => _ignoredPoolIds.add(pool.id)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 15),

              // Barre de progression simplifiée
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: pool.currentFilling / 4,
                  backgroundColor: Colors.grey.shade100,
                  color: isFull ? Colors.green : TranSenColors.primaryGreen,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${pool.currentFilling}/4 passagers",
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  if (canAcceptAt3 && !isFull)
                    const Text("Acceptable (3/4)",
                        style: TextStyle(
                            fontSize: 11,
                            color: TranSenColors.accentGold,
                            fontWeight: FontWeight.bold)),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Divider(height: 1, color: Colors.black12),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total (estimé)",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text("${pool.currentFilling * 10000} FCFA",
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Colors.green)),
                ],
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _acceptPoolDirectly(pool),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFull
                        ? Colors.green
                        : (canAcceptAt3
                            ? TranSenColors.accentGold
                            : TranSenColors.darkGreen),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                      isFull
                          ? 'DÉPART IMMÉDIAT (COMPLET)'
                          : (canAcceptAt3
                              ? 'ACCEPTER (3/4)'
                              : 'ACCEPTER (${pool.currentFilling}/4)'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildActiveVtcTripCard(BuildContext context, TripModel trip) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade800, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.blue.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TripDetailScreen(trip: trip)));
          },
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.inventory_2,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.type.contains('Livraison')
                            ? "Livraison Active !"
                            : "Course Active !",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${trip.departure} ➔ ${trip.destination}",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Client: ${trip.clientName ?? 'Anonyme'}",
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveDeliveriesBanner(BuildContext context, List<TripModel> deliveries) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade800, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.blue.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            ActiveDeliveriesSheet.show(context, deliveries);
          },
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.inventory_2, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Livraisons Actives",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${deliveries.length} livraison(s) en cours",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Cliquez pour gérer",
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveDriverTripCard(BuildContext context, PoolModel pool) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade800, Colors.green.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.green.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PoolDetailScreen(pool: pool)));
          },
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.airport_shuttle,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Course Active !",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${pool.departure} ➔ ${pool.destination}",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pool.status == 'departed'
                            ? "Trajet en cours"
                            : "En route vers le point de collecte",
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeliverySmallCard(BuildContext context, TripModel delivery) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: InkWell(
        onTap: null, // Désactivé selon demande utilisateur
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2,
                    color: TranSenColors.primaryGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    delivery.departure,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.arrow_downward, size: 12, color: Colors.grey),
            ),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    delivery.destination,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => _acceptTripDirectly(delivery),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: TranSenColors.primaryGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('ACCEPTER',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ),
                Text(
                  "${delivery.price.toInt()} F",
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.green,
                      fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVtcSmallCard(BuildContext context, TripModel trip) {
    return Container(
      width: 195,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: TranSenColors.primaryGreen.withValues(alpha: 0.4),
            width: 1.5),
        boxShadow: [
          BoxShadow(
              color: TranSenColors.primaryGreen.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 6)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: null, // Désactivé selon demande utilisateur
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: TranSenColors.primaryGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.directions_car,
                        color: TranSenColors.primaryGreen, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trip.clientName ?? 'Client',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.my_location, color: Colors.blue, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(trip.departure,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(trip.destination,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${trip.price.toInt()} FCFA',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.green,
                        fontSize: 13),
                  ),
                  GestureDetector(
                    onTap: () => _acceptTripDirectly(trip),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: TranSenColors.primaryGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('ACCEPTER',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // QUICK ACTION TILE — tuile d'action rapide avec gradient premium
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildQuickActionTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String sublabel,
    required List<Color> gradientColors,
    required Color iconColor,
    required VoidCallback onTap,
    String? badge,
    bool isLoading = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white.withValues(alpha: 0.1),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: gradientColors.last.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    if (badge != null)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Center(
                            child: Text(badge,
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      if (isLoading)
                        Shimmer.fromColors(
                          baseColor: Colors.white.withValues(alpha: 0.2),
                          highlightColor: Colors.white.withValues(alpha: 0.4),
                          child: Container(
                            height: 10,
                            width: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        )
                      else
                        Text(sublabel,
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
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // BOTTOM SHEET : Sélection du trajet du jour
  // ────────────────────────────────────────────────────────────────────────
  void _showRouteBottomSheet(BuildContext context, WidgetRef ref, String driverId) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: TranSenColors.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.route, color: TranSenColors.primaryGreen, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Mon trajet du jour',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Ville de départ',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    hint: const Text('Sélectionner le départ'),
                    value: _pubDeparture,
                    isExpanded: true,
                    items: _regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (val) { setState(() => _pubDeparture = val); setModalState(() {}); },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text("Ville d'arrivée",
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    hint: const Text("Sélectionner l'arrivée"),
                    value: _pubDestination,
                    isExpanded: true,
                    items: _regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (val) { setState(() => _pubDestination = val); setModalState(() {}); },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Message aux passagers (optionnel)',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    hintText: 'Ex: Départ à 8h, Climatisé...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    prefixIcon: Icon(Icons.chat_bubble_outline, size: 18),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _pubDeparture == null
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          ref.read(tripRepositoryProvider).publishDriverRoute(
                            driverId, _pubDeparture!, _pubDestination, _noteController.text.trim(),
                          );
                          Navigator.pop(ctx);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TranSenColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Confirmer mon trajet',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
