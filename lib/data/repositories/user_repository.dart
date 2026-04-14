import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> updateWalletBalance(String userId, double amountDelta, String description) async {
    try {
      final batch = _firestore.batch();
      
      // 1. Mettre à jour le solde
      final userRef = _firestore.collection('users').doc(userId);
      batch.set(userRef, {
        'walletBalance': FieldValue.increment(amountDelta),
      }, SetOptions(merge: true));

      // 2. Ajouter la transaction
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
  Stream<Map<String, dynamic>?> watchUser(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) => doc.data());
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});
