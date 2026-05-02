import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/theme/transen_colors.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/providers/auth_provider.dart';
import '../home/trip_tracking_screen.dart';

class DriverTripDetailSheet extends ConsumerStatefulWidget {
  final TripModel trip;

  const DriverTripDetailSheet({super.key, required this.trip});

  /// Affiche la modale et retourne true si accepté
  static Future<bool?> show(BuildContext context, TripModel trip) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DriverTripDetailSheet(trip: trip),
    );
  }

  @override
  ConsumerState<DriverTripDetailSheet> createState() =>
      _DriverTripDetailSheetState();
}

class _DriverTripDetailSheetState
    extends ConsumerState<DriverTripDetailSheet> {
  bool _isLoading = false;
  String? _clientPhone;

  @override
  void initState() {
    super.initState();
    _fetchClientPhone();
  }

  Future<void> _fetchClientPhone() async {
    // Récupérer le numéro en temps réel depuis Firestore
    if (widget.trip.clientId == null || widget.trip.clientId!.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instanceFor(
              app: Firebase.app(), databaseId: 'transen')
          .collection('users')
          .doc(widget.trip.clientId)
          .get();
      final data = doc.data();
      if (data != null && data['phone'] != null && mounted) {
        setState(() => _clientPhone = data['phone']);
      }
    } catch (_) {}
  }

  Future<void> _acceptTrip() async {
    final auth = ref.read(authProvider);
    if (auth == null) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(tripRepositoryProvider)
          .acceptTrip(widget.trip.id, auth.userId);

      if (mounted) {
        // Fermer la modale puis naviguer vers l'écran de suivi chauffeur
        Navigator.of(context).pop(true);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TripTrackingScreen(tripId: widget.trip.id),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _callClient() {
    final phone = _clientPhone ?? widget.trip.clientPhone;
    if (phone != null && phone.isNotEmpty) {
      launchUrl(Uri.parse('tel:$phone'));
    }
  }

  bool get _isYobante {
    final type = widget.trip.type.toLowerCase();
    return type.contains('livraison') ||
        type.contains('colis') ||
        type.contains('yobante');
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _isYobante ? Colors.blue : TranSenColors.primaryGreen;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            // --- Handle ---
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // --- Header coloré ---
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.9), color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Icon(
                      _isYobante ? Icons.inventory_2 : Icons.person,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.clientName ?? 'Client TranSen',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _isYobante ? '📦 Livraison Yobanté' : '🚕 Course VTC',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bouton appel rapide
                  IconButton(
                    onPressed: _callClient,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                    ),
                    icon: const Icon(Icons.phone, color: Colors.white),
                  ),
                ],
              ),
            ),

            // --- Corps scrollable ---
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                children: [
                  // Trajet
                  _SectionCard(
                    children: [
                      _InfoRow(
                        icon: Icons.my_location,
                        iconColor: Colors.blue,
                        label: 'Départ',
                        value: trip.departure,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 11),
                        child: Icon(Icons.more_vert, size: 16, color: Colors.grey),
                      ),
                      _InfoRow(
                        icon: Icons.location_on,
                        iconColor: Colors.red,
                        label: 'Destination',
                        value: trip.destination,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Infos course
                  _SectionCard(
                    children: [
                      _InfoRow(
                        icon: Icons.category,
                        iconColor: color,
                        label: 'Type',
                        value: trip.type,
                      ),
                      if (trip.scheduledDate != null) ...[
                        const Divider(height: 20),
                        _InfoRow(
                          icon: Icons.calendar_today,
                          iconColor: Colors.orange,
                          label: 'Date prévue',
                          value: trip.scheduledDate!,
                        ),
                      ],
                      if (trip.seats != null) ...[
                        const Divider(height: 20),
                        _InfoRow(
                          icon: Icons.groups,
                          iconColor: TranSenColors.primaryGreen,
                          label: 'Passagers',
                          value: '${trip.seats} personne(s)',
                        ),
                      ],
                      if (trip.baggageDescription != null &&
                          trip.baggageDescription!.isNotEmpty) ...[
                        const Divider(height: 20),
                        _InfoRow(
                          icon: Icons.inventory,
                          iconColor: Colors.purple,
                          label: 'Colis',
                          value: trip.baggageDescription!,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Paiement
                  _SectionCard(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.payments,
                                  color: Colors.green, size: 20),
                              SizedBox(width: 10),
                              Text('À encaisser',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                          Text(
                            '${trip.price.toInt()} FCFA',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Numéro client
                  if (_clientPhone != null || trip.clientPhone != null) ...[
                    const SizedBox(height: 12),
                    _SectionCard(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.phone,
                                    color: Colors.blue, size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  _clientPhone ?? trip.clientPhone ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _callClient,
                                  icon: const Icon(Icons.phone,
                                      color: Colors.green),
                                  tooltip: 'Appeler',
                                ),
                                IconButton(
                                  onPressed: () {
                                    final phone = (_clientPhone ??
                                            trip.clientPhone ??
                                            '')
                                        .replaceAll(' ', '');
                                    launchUrl(Uri.parse(
                                        'https://wa.me/221$phone'));
                                  },
                                  icon: const Icon(Icons.chat,
                                      color: Colors.green),
                                  tooltip: 'WhatsApp',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),

            // --- Boutons Accepter / Refuser ---
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Refuser
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('REFUSER',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Accepter
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _acceptTrip,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle, size: 20),
                      label: Text(
                        _isLoading ? 'Acceptation...' : 'ACCEPTER LA COURSE',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Widgets helpers ---

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
