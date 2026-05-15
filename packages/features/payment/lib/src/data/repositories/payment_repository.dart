import "package:flutter/foundation.dart";
import "package:firebase_core/firebase_core.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/senepay_service.dart';

class PaymentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');

  Future<void> updatePoints(String userId, int pointsDelta, String description) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      
      await _firestore.runTransaction((transaction) async {
        transaction.set(userRef, {
          'bonusPoints': FieldValue.increment(pointsDelta),
        }, SetOptions(merge: true));

        final transRef = userRef.collection('transactions').doc();
        transaction.set(transRef, {
          'description': description,
          'amount': 0.0,
          'points': pointsDelta,
          'date': FieldValue.serverTimestamp(),
          'type': 'points',
          'status': 'completed',
        });
      });
    } catch (e) {
      debugPrint("Erreur mise à jour points: $e");
    }
  }

  Stream<int> watchPoints(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return 0;
      final data = doc.data() as Map<String, dynamic>;
      return (data['bonusPoints'] ?? 0).toInt();
    });
  }

  Future<void> updateWalletBalance(String userId, double amountDelta, String description, {String type = 'transaction', String status = 'completed'}) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final batch = _firestore.batch();
      
      batch.set(userRef, {
        'walletBalance': FieldValue.increment(amountDelta),
      }, SetOptions(merge: true));

      final transRef = userRef.collection('transactions').doc();
      batch.set(transRef, {
        'description': description,
        'amount': amountDelta,
        'date': FieldValue.serverTimestamp(),
        'type': type,
        'status': status,
      });

      await batch.commit();
    } catch (e) {
      debugPrint("Erreur mise à jour wallet Firebase: $e");
    }
  }

  Stream<List<Map<String, dynamic>>> watchTransactions(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Stream<double> watchWalletBalance(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return 0.0;
      final data = doc.data() as Map<String, dynamic>;
      return (data['walletBalance'] ?? 0).toDouble();
    });
  }

  Future<String?> createSenePaySession({
    required double amount,
    required String orderId,
    required String description,
    String? customerName,
    String? customerPhone,
    String? providerId,
  }) async {
    return SenePayService().createCheckoutSession(
      amount: amount,
      orderId: orderId,
      description: description,
      customerName: customerName,
      customerPhone: customerPhone,
      providerId: providerId,
    );
  }

  Future<Map<String, dynamic>?> requestPayout({
    required String userId,
    required double amount,
    required String recipientPhone,
    required String recipientName,
    required String operator,
    String? description,
  }) async {
    try {
      // Le backend /api/payment/secure-payout vérifie le solde, déduit l'argent, 
      // crée l'historique et appelle l'API SenePay de manière atomique et sécurisée.
      final result = await SenePayService().createPayout(
        amount: amount,
        recipientPhone: recipientPhone,
        recipientName: recipientName,
        operator: operator,
        description: description ?? "Retrait TranSen",
      );

      return result;
    } catch (e) {
      debugPrint("Erreur lors de la demande de payout: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> syncPayoutStatus(String userId, String internalId) async {
    final status = await SenePayService().getPayoutStatus(internalId);
    if (status != null) {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('payouts')
          .doc(internalId)
          .update({
        'status': status['status'],
        'updatedAt': FieldValue.serverTimestamp(),
        if (status['completedAt'] != null) 'completedAt': status['completedAt'],
      });

      // Si le payout a échoué, on recrédite le wallet
      if (status['status'] == 'Failed' || status['status'] == 'Cancelled') {
         final amount = (status['amount'] as num).toDouble();
         await updateWalletBalance(userId, amount, "Remboursement retrait échoué : $internalId", type: 'withdrawal');
      }
    }
    return status;
  }

  Future<bool> verifyAndCreditDeposit(String userId, String orderReference) async {
    try {
      // 1. Vérifier si déjà traité (Idempotence)
      final existing = await _firestore
          .collection('users')
          .doc(userId)
          .collection('transactions')
          .where('description', isEqualTo: "Dépôt SenePay réussi : $orderReference")
          .get();

      if (existing.docs.isNotEmpty) return true;

      // 2. Vérifier auprès de SenePay
      final session = await SenePayService().checkCheckoutStatus(orderReference);
      if (session != null && (session['status'] == 'Completed' || session['status'] == 'PAID')) {
        final amount = (session['amount'] as num).toDouble();
        await updateWalletBalance(userId, amount, "Dépôt SenePay réussi : $orderReference", type: 'deposit');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Erreur vérification dépôt: $e");
      return false;
    }
  }

  Future<void> recordCommission(double amount, String tripId, String type) async {
    await SenePayService().recordCommission(amount: amount, tripId: tripId, type: type);
  }

  Future<void> processReferralReward(String referredUserId, String tripId) async {
    await SenePayService().processReferralReward(referredUserId, tripId);
  }
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository();
});
