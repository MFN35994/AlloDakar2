import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:transen_auth/transen_auth.dart';
import 'pool_detail_screen.dart';

class DriverPoolDetailSheet extends ConsumerStatefulWidget {
  final PoolModel pool;

  const DriverPoolDetailSheet({super.key, required this.pool});

  static Future<bool?> show(BuildContext context, PoolModel pool) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: DriverPoolDetailSheet(pool: pool),
      ),
    );
  }

  @override
  ConsumerState<DriverPoolDetailSheet> createState() =>
      _DriverPoolDetailSheetState();
}

class _DriverPoolDetailSheetState
    extends ConsumerState<DriverPoolDetailSheet> {
  bool _isLoading = false;

  Future<void> _acceptPool() async {
    final auth = ref.read(authProvider);
    if (auth == null) return;
    setState(() => _isLoading = true);

    try {
      await ref
          .read(tripRepositoryProvider)
          .acceptPool(widget.pool.id, auth.userId);

      if (mounted) {
        Navigator.of(context).pop(true);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PoolDetailScreen(pool: widget.pool),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.contains('Exception: ')) {
          errorMsg = errorMsg.split('Exception: ').last;
        } else {
          errorMsg = "Erreur lors de l'acceptation du trajet.";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _declinePool() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final pool = widget.pool;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const color = TranSenColors.primaryGreen;

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
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header gradient
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [TranSenColors.primaryGreen, Color(0xFF2E7D32)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${pool.currentFilling} passager(s) - Covoiturage',
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
                          child: const Text(
                            '🚐 Trajet Groupé',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable body
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                children: [
                  // Route card
                  _SectionCard(children: [
                    _InfoRow(
                      icon: Icons.my_location,
                      iconColor: Colors.blue,
                      label: 'Départ',
                      value: pool.departure,
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 11),
                      child: Icon(Icons.more_vert, size: 16, color: Colors.grey),
                    ),
                    _InfoRow(
                      icon: Icons.location_on,
                      iconColor: Colors.red,
                      label: 'Destination',
                      value: pool.destination,
                    ),
                  ]),

                  const SizedBox(height: 12),

                  // Info card
                  _SectionCard(children: [
                    _InfoRow(
                      icon: Icons.group,
                      iconColor: color,
                      label: 'Passagers',
                      value:
                          '${pool.currentFilling} / 4 place(s) remplie(s)',
                    ),
                    const Divider(height: 20),
                    _InfoRow(
                      icon: Icons.calendar_today,
                      iconColor: Colors.orange,
                      label: 'Date prévue',
                      value: pool.scheduledDate,
                    ),
                  ]),

                  const SizedBox(height: 12),

                  // Passengers list
                  if (pool.passengerDetails.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Liste des passagers',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    ...pool.passengerDetails.entries.map((entry) {
                      final p = entry.value;
                      String name = p['name'] ?? 'Passager';
                      if (p['firstName'] != null && p['lastName'] != null) {
                        name = '${p['firstName']} ${p['lastName']}';
                      }
                      final phone = (p['phone'] as String? ?? '').replaceAll(' ', '');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: color.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person,
                                color: TranSenColors.primaryGreen, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (phone.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.phone,
                                    color: TranSenColors.primaryGreen,
                                    size: 20),
                                onPressed: () =>
                                    DeviceUtils.launchPhoneCall(phone),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],

                  // Prix card
                  _SectionCard(children: [
                    _InfoRow(
                      icon: Icons.payments,
                      iconColor: Colors.amber.shade700,
                      label: 'Gains estimés',
                      value:
                          '${(pool.currentFilling * 1000).toInt()} FCFA (commission incluse)',
                    ),
                  ]),

                  const SizedBox(height: 90),
                ],
              ),
            ),

            // Action buttons
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Decline
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _declinePool,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('REFUSER'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Accept
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _acceptPool,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check, size: 18),
                      label: Text(
                          _isLoading ? 'Acceptation...' : 'ACCEPTER LE TRAJET'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TranSenColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
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

// ─── Shared helpers ────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252540) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.grey.shade200,
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.grey)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
        ),
      ],
    );
  }
}
