import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_auth/transen_auth.dart';
import '../data/services/subscription_service.dart';
import '../providers/wallet_provider.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _isProcessing = false;

  Future<void> _subscribe(SubscriptionPlan plan) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isProcessing = true);
    try {
      final walletState = ref.read(walletProvider);
      final auth = ref.read(authProvider);
      final service = SubscriptionService();

      final userId = auth?.userId ?? '';
      if (userId.isEmpty) {
        throw Exception('Utilisateur non connecté.');
      }

      // Vérifier le solde avant de tenter
      if (walletState.balance < plan.price) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            '❌ Solde insuffisant. Vous avez ${walletState.balance.toInt()} FCFA, '
            'il vous faut ${plan.price.toInt()} FCFA.',
          ),
          backgroundColor: Colors.red,
        ));
        return;
      }

      await service.subscribe(userId: userId, plan: plan);

      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('✅ Abonnement ${plan.label} activé pour ${plan.durationDays} jours !'),
          backgroundColor: Colors.green,
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('❌ ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final auth = ref.watch(authProvider);
    final userId = auth?.userId ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Abonnement TranSen', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: userId.isEmpty
          ? const Center(child: CircularProgressIndicator(color: TranSenColors.primaryGreen))
          : StreamBuilder<SubscriptionInfo>(
              stream: SubscriptionService().watchSubscription(userId),
              builder: (context, snapshot) {
                final info = snapshot.data;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Statut actuel
                      _buildStatusCard(info),
                      const SizedBox(height: 28),

                      // ── Plans
                      const Text(
                        'Choisissez votre plan',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      _buildPlanCard(
                        plan: SubscriptionPlan.weekly,
                        isRecommended: false,
                        walletBalance: walletState.balance,
                      ),
                      const SizedBox(height: 14),
                      _buildPlanCard(
                        plan: SubscriptionPlan.monthly,
                        isRecommended: true,
                        walletBalance: walletState.balance,
                      ),
                      const SizedBox(height: 28),

                      // ── Solde
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet, color: TranSenColors.primaryGreen),
                            const SizedBox(width: 12),
                            Text(
                              'Solde TransPay : ${walletState.balance.toInt()} FCFA',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Note
                      const Text(
                        'Les abonnements sont débités depuis votre portefeuille TransPay. '
                        'Rechargez votre portefeuille via Wave ou Orange Money si nécessaire.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusCard(SubscriptionInfo? info) {
    if (info == null) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(color: TranSenColors.primaryGreen)),
      );
    }

    Color bgColor;
    IconData icon;
    String title;
    String subtitle;

    if (info.isActive) {
      final isTrial = info.plan == SubscriptionPlan.trial;
      bgColor = isTrial
          ? const Color(0xFF1A3A2A)
          : const Color(0xFF1A2E3A);
      icon = isTrial ? Icons.hourglass_top : Icons.verified;
      title = isTrial
          ? '🎁 Essai gratuit en cours'
          : '✅ Abonnement actif — ${info.plan?.label}';
      subtitle = info.daysRemaining > 0
          ? 'Expire dans ${info.daysRemaining} jour(s) et ${info.hoursRemaining}h'
          : 'Expire aujourd\'hui !';
    } else if (info.isExpired) {
      bgColor = const Color(0xFF3A1A1A);
      icon = Icons.warning_amber;
      title = '⚠️ Abonnement expiré';
      subtitle = 'Renouvelez pour continuer à accepter des trajets';
    } else {
      bgColor = const Color(0xFF2A2A2A);
      icon = Icons.lock_outline;
      title = 'Aucun abonnement actif';
      subtitle = 'Choisissez un plan ci-dessous pour commencer';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: info.isActive ? TranSenColors.primaryGreen.withValues(alpha: 0.4) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: info.isActive ? TranSenColors.primaryGreen : Colors.orange, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required SubscriptionPlan plan,
    required bool isRecommended,
    required double walletBalance,
  }) {
    final canAfford = walletBalance >= plan.price;
    final savingsPerDay = (plan == SubscriptionPlan.monthly)
        ? (6000 / 7) - (20000 / 30)
        : null;

    return GestureDetector(
      onTap: _isProcessing ? null : () => _showConfirmDialog(plan),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: isRecommended
              ? const LinearGradient(
                  colors: [Color(0xFF1A4A3A), Color(0xFF0D3A2A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isRecommended ? null : const Color(0xFF1A2030),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRecommended
                ? TranSenColors.primaryGreen
                : Colors.white24,
            width: isRecommended ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: TranSenColors.primaryGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '⭐ Meilleur rapport',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${plan.price.toInt()} FCFA',
                  style: TextStyle(
                    color: isRecommended ? TranSenColors.primaryGreen : Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '/ ${plan.durationDays} jours',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (savingsPerDay != null) ...[
              const SizedBox(height: 6),
              Text(
                '≈ ${(20000 / 30).toInt()} FCFA/jour — économisez ${(6000 / 7 - 20000 / 30).toInt()} FCFA/jour vs hebdo',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isProcessing || !canAfford) ? null : () => _showConfirmDialog(plan),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRecommended ? TranSenColors.primaryGreen : Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isProcessing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        canAfford ? 'S\'abonner — ${plan.price.toInt()} FCFA' : 'Solde insuffisant',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfirmDialog(SubscriptionPlan plan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirmer l\'abonnement',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${plan.price.toInt()} FCFA seront déduits de votre portefeuille TransPay '
          'pour ${plan.durationDays} jours d\'accès.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _subscribe(plan);
            },
            style: ElevatedButton.styleFrom(backgroundColor: TranSenColors.primaryGreen),
            child: const Text('Confirmer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
