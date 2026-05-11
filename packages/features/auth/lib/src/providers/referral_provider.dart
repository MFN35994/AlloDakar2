import "package:firebase_core/firebase_core.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReferralNotifier extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() {
    return const AsyncValue.data(null);
  }

  Future<bool> validateAndApply(String code, String userId) async {
    if (code.isEmpty) return true;
    
    state = const AsyncValue.loading();
    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');
      
      // 0. Vérification Anti-Fraude : Device ID
      final deviceId = await DeviceUtils.getDeviceId();
      
      // Vérifier si cet appareil a déjà été parrainé
      final deviceQuery = await db.collection('users')
          .where('deviceId', isEqualTo: deviceId)
          .where('referredBy', isNull: false)
          .limit(1)
          .get();
          
      if (deviceQuery.docs.isNotEmpty && deviceQuery.docs.first.id != userId) {
        state = AsyncValue.error("Cet appareil a déjà été utilisé pour un parrainage.", StackTrace.current);
        return false;
      }

      // 1. Rechercher le parrain
      final query = await db.collection('users')
          .where('referralCode', isEqualTo: code.toUpperCase())
          .get();

      if (query.docs.isEmpty) {
        state = AsyncValue.error("Code de parrainage invalide", StackTrace.current);
        return false;
      }

      final referrerDoc = query.docs.first;
      final referrerId = referrerDoc.id;
      final referrerData = referrerDoc.data();

      if (referrerId == userId) {
        state = AsyncValue.error("Vous ne pouvez pas vous parrainer vous-même", StackTrace.current);
        return false;
      }

      // Vérification Anti-Fraude : Même appareil ?
      if (referrerData['deviceId'] == deviceId) {
        state = AsyncValue.error("Parrainage impossible sur le même appareil.", StackTrace.current);
        return false;
      }

      // 2. Marquer l'utilisateur actuel comme parrainé
      await db.collection('users').doc(userId).set({
        'referredBy': referrerId,
        'referralRewardClaimed': false,
        'deviceId': deviceId,
        'referralAppliedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3. Mettre à jour le compteur du parrain
      await db.collection('users').doc(referrerId).update({
        'referralCount': FieldValue.increment(1),
      });

      state = const AsyncValue.data("Code appliqué avec succès ! Vos gains seront actifs après votre premier trajet.");
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }
}

final referralProvider = NotifierProvider<ReferralNotifier, AsyncValue<String?>>(ReferralNotifier.new);
