import "package:flutter/foundation.dart";
import "package:firebase_core/firebase_core.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> updateWalletBalance(String userId, double amountDelta, String description) async {
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
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  Stream<double> watchWalletBalance(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return 0.0;
      final data = doc.data() as Map<String, dynamic>;
      return (data['walletBalance'] ?? 0).toDouble();
    });
  }
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository();
});
