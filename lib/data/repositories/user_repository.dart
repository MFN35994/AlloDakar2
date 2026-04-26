import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');

  /// Génère un code de parrainage unique pour l'utilisateur s'il n'en a pas
  Future<String> ensureReferralCode(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (doc.exists && doc.data()?.containsKey('referralCode') == true) {
      return doc.data()!['referralCode'];
    }
    
    // Générer un code court basé sur l'UID ou aléatoire
    final code = "TS${userId.substring(0, 4).toUpperCase()}";
    await _firestore.collection('users').doc(userId).set({
      'referralCode': code,
    }, SetOptions(merge: true));
    return code;
  }

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
          'amount': 0.0, // C'est une transaction de points
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
      // Utilisation de toInt() au cas où Firestore stocke un double ou un long
      return (data['bonusPoints'] ?? 0).toInt();
    });
  }

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
