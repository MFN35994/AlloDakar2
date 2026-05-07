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

  Stream<Map<String, dynamic>?> watchUser(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) => doc.data());
  }

  Future<void> updateUserData(String userId, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(userId).set(data, SetOptions(merge: true));
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});
