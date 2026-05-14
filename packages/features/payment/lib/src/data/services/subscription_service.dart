import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plans d'abonnement disponibles
enum SubscriptionPlan { trial, weekly, monthly }

extension SubscriptionPlanExtension on SubscriptionPlan {
  String get label {
    switch (this) {
      case SubscriptionPlan.trial:
        return 'Essai gratuit';
      case SubscriptionPlan.weekly:
        return 'Hebdomadaire';
      case SubscriptionPlan.monthly:
        return 'Mensuel';
    }
  }

  int get durationDays {
    switch (this) {
      case SubscriptionPlan.trial:
        return 5;
      case SubscriptionPlan.weekly:
        return 7;
      case SubscriptionPlan.monthly:
        return 30;
    }
  }

  double get price {
    switch (this) {
      case SubscriptionPlan.trial:
        return 0;
      case SubscriptionPlan.weekly:
        return 6000;
      case SubscriptionPlan.monthly:
        return 20000;
    }
  }
}

/// Statut d'abonnement retourné par checkSubscription
enum SubscriptionStatus {
  /// Abonnement actif (essai ou payant)
  active,
  /// Pas encore d'abonnement (nouveau chauffeur avant activation essai)
  none,
  /// Abonnement expiré
  expired,
}

class SubscriptionInfo {
  final SubscriptionStatus status;
  final SubscriptionPlan? plan;
  final DateTime? expiresAt;

  const SubscriptionInfo({
    required this.status,
    this.plan,
    this.expiresAt,
  });

  /// Nombre de jours restants (0 si expiré)
  int get daysRemaining {
    if (expiresAt == null) return 0;
    final remaining = expiresAt!.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  /// Heures restantes pour le dernier jour
  int get hoursRemaining {
    if (expiresAt == null) return 0;
    final remaining = expiresAt!.difference(DateTime.now()).inHours;
    return remaining < 0 ? 0 : remaining % 24;
  }

  bool get isActive => status == SubscriptionStatus.active;
  bool get isExpired => status == SubscriptionStatus.expired;
  bool get isNone => status == SubscriptionStatus.none;

  /// Vrai si l'abonnement expire dans moins de 3 jours (alerte)
  bool get expiresSOon => isActive && daysRemaining <= 3;
}

class SubscriptionService {
  final FirebaseFirestore _db =
      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');

  // ─────────────────────────────────────────────────────────────────────────
  // LECTURE DU STATUT
  // ─────────────────────────────────────────────────────────────────────────

  /// Vérifie l'abonnement d'un chauffeur et retourne les infos détaillées.
  Future<SubscriptionInfo> checkSubscription(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (!doc.exists) return const SubscriptionInfo(status: SubscriptionStatus.none);

      final data = doc.data()!;
      final planStr = data['subscriptionPlan'] as String?;
      final expiresRaw = data['subscriptionExpires'];

      if (planStr == null || expiresRaw == null) {
        return const SubscriptionInfo(status: SubscriptionStatus.none);
      }

      final expiresAt = (expiresRaw as Timestamp).toDate();
      final now = DateTime.now();
      final plan = _parsePlan(planStr);

      if (now.isBefore(expiresAt)) {
        return SubscriptionInfo(
          status: SubscriptionStatus.active,
          plan: plan,
          expiresAt: expiresAt,
        );
      } else {
        return SubscriptionInfo(
          status: SubscriptionStatus.expired,
          plan: plan,
          expiresAt: expiresAt,
        );
      }
    } catch (e) {
      debugPrint('[SubscriptionService] checkSubscription error: $e');
      return const SubscriptionInfo(status: SubscriptionStatus.none);
    }
  }

  /// Stream temps réel pour afficher le statut dans l'UI.
  Stream<SubscriptionInfo> watchSubscription(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return const SubscriptionInfo(status: SubscriptionStatus.none);
      final data = doc.data()!;
      final planStr = data['subscriptionPlan'] as String?;
      final expiresRaw = data['subscriptionExpires'];
      if (planStr == null || expiresRaw == null) {
        return const SubscriptionInfo(status: SubscriptionStatus.none);
      }
      final expiresAt = (expiresRaw as Timestamp).toDate();
      final plan = _parsePlan(planStr);
      final isActive = DateTime.now().isBefore(expiresAt);
      return SubscriptionInfo(
        status: isActive ? SubscriptionStatus.active : SubscriptionStatus.expired,
        plan: plan,
        expiresAt: expiresAt,
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVATION DE L'ESSAI GRATUIT
  // ─────────────────────────────────────────────────────────────────────────

  /// Active le plan d'essai gratuit (5 jours) pour un nouveau chauffeur.
  ///
  /// Double protection anti-fraude :
  ///  1. `phone_trials/{phoneNumber}` — 1 essai par numéro de téléphone
  ///  2. `devices/{deviceId}` — 1 essai par appareil physique
  ///
  /// Throws une [Exception] descriptive si l'essai a déjà été utilisé.
  Future<void> activateTrial({
    required String userId,
    required String deviceId,
    required String phoneNumber,
  }) async {
    // Normaliser le numéro (enlever espaces, s'assurer du préfixe)
    final normalizedPhone = _normalizePhone(phoneNumber);
    final phoneKey = 'phone_$normalizedPhone'; // clé Firestore-safe

    debugPrint('[SubscriptionService] Tentative essai: userId=$userId device=$deviceId phone=$normalizedPhone');

    // ── Vérification 1 : ce numéro de téléphone a-t-il déjà utilisé un essai ?
    final phoneTrialDoc = await _db.collection('phone_trials').doc(phoneKey).get();
    if (phoneTrialDoc.exists && (phoneTrialDoc.data()?['trialUsed'] == true)) {
      throw Exception(
        'Ce numéro de téléphone a déjà bénéficié de l\'essai gratuit.\n'
        'Choisissez un plan d\'abonnement pour continuer.',
      );
    }

    // ── Vérification 2 : cet appareil a-t-il déjà utilisé un essai ?
    final deviceDoc = await _db.collection('devices').doc(deviceId).get();
    if (deviceDoc.exists && (deviceDoc.data()?['trialUsed'] == true)) {
      throw Exception(
        'Un essai gratuit a déjà été activé sur cet appareil.\n'
        'Choisissez un plan d\'abonnement pour continuer.',
      );
    }

    // ── Vérification 3 : ce compte a-t-il déjà un abonnement ?
    final userDoc = await _db.collection('users').doc(userId).get();
    if (userDoc.exists) {
      final existing = userDoc.data()?['subscriptionPlan'];
      if (existing != null) {
        debugPrint('[SubscriptionService] Abonnement déjà présent: $existing — essai ignoré');
        return; // Silencieux : déjà abonné
      }
    }

    // ── Tout est OK : activation atomique
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 5));
    final batch = _db.batch();

    // Mettre à jour le profil chauffeur
    batch.set(
      _db.collection('users').doc(userId),
      {
        'subscriptionPlan': 'trial',
        'subscriptionStart': Timestamp.fromDate(now),
        'subscriptionExpires': Timestamp.fromDate(expiresAt),
        'trialActivated': true,
      },
      SetOptions(merge: true),
    );

    // Marquer le numéro comme ayant utilisé un essai
    batch.set(_db.collection('phone_trials').doc(phoneKey), {
      'trialUsed': true,
      'userId': userId,
      'phone': normalizedPhone,
      'deviceId': deviceId,
      'usedAt': Timestamp.fromDate(now),
    });

    // Marquer l'appareil comme ayant utilisé un essai
    batch.set(_db.collection('devices').doc(deviceId), {
      'trialUsed': true,
      'userId': userId,
      'phone': normalizedPhone,
      'usedAt': Timestamp.fromDate(now),
    });

    await batch.commit();
    debugPrint('[SubscriptionService] ✅ Essai gratuit activé jusqu\'au ${expiresAt.toIso8601String()}');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SOUSCRIPTION À UN PLAN PAYANT
  // ─────────────────────────────────────────────────────────────────────────

  /// Souscrit à un plan payant (weekly ou monthly).
  ///
  /// Déduit le montant de manière atomique depuis le walletBalance.
  /// Si un abonnement est encore actif, repart de la date d'expiration actuelle.
  Future<void> subscribe({
    required String userId,
    required SubscriptionPlan plan,
  }) async {
    if (plan == SubscriptionPlan.trial) {
      throw Exception('Utilisez activateTrial() pour le plan essai.');
    }

    final price = plan.price;
    final days = plan.durationDays;
    final userRef = _db.collection('users').doc(userId);

    await _db.runTransaction((transaction) async {
      final userDoc = await transaction.get(userRef);
      if (!userDoc.exists) throw Exception('Utilisateur introuvable.');

      final data = userDoc.data()!;
      final balance = (data['walletBalance'] ?? 0).toDouble();

      if (balance < price) {
        throw Exception(
          'Solde TransPay insuffisant (${balance.toInt()} FCFA).\n'
          'Recharge nécessaire : ${(price - balance).toInt()} FCFA de plus.',
        );
      }

      // Si un abonnement est encore actif, on part de la date d'expiration
      final now = DateTime.now();
      DateTime baseDate = now;
      final expiresRaw = data['subscriptionExpires'];
      if (expiresRaw != null) {
        final currentExpiry = (expiresRaw as Timestamp).toDate();
        if (currentExpiry.isAfter(now)) {
          baseDate = currentExpiry; // Renouvellement anticipé
        }
      }

      final newExpiry = baseDate.add(Duration(days: days));

      transaction.update(userRef, {
        'walletBalance': FieldValue.increment(-price),
        'subscriptionPlan': plan == SubscriptionPlan.weekly ? 'weekly' : 'monthly',
        'subscriptionStart': Timestamp.fromDate(now),
        'subscriptionExpires': Timestamp.fromDate(newExpiry),
      });

      // Enregistrer dans l'historique des transactions
      final txRef = userRef.collection('transactions').doc();
      transaction.set(txRef, {
        'amount': -price,
        'description': 'Abonnement TranSen ${plan.label} (${days}j)',
        'date': FieldValue.serverTimestamp(),
        'type': 'subscription',
      });

      // Stats plateforme
      final statsRef = _db.collection('system_stats').doc('subscriptions');
      transaction.set(statsRef, {
        'totalRevenue': FieldValue.increment(price),
        'lastUpdate': FieldValue.serverTimestamp(),
        plan == SubscriptionPlan.weekly ? 'weeklyCount' : 'monthlyCount':
            FieldValue.increment(1),
      }, SetOptions(merge: true));
    });

    debugPrint('[SubscriptionService] ✅ Abonnement ${plan.label} souscrit pour $userId');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  SubscriptionPlan? _parsePlan(String planStr) {
    switch (planStr) {
      case 'trial':
        return SubscriptionPlan.trial;
      case 'weekly':
        return SubscriptionPlan.weekly;
      case 'monthly':
        return SubscriptionPlan.monthly;
      default:
        return null;
    }
  }

  String _normalizePhone(String phone) {
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    // Enlever le préfixe 221 si présent et si > 9 chiffres
    while (digits.startsWith('221') && digits.length > 9) {
      digits = digits.substring(3);
    }
    return digits;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});

final subscriptionInfoProvider = StreamProvider.family<SubscriptionInfo, String>((ref, userId) {
  return ref.watch(subscriptionServiceProvider).watchSubscription(userId);
});
