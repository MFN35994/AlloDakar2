import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReferralNotifier extends StateNotifier<AsyncValue<String?>> {
  ReferralNotifier() : super(const AsyncValue.data(null));

  Future<bool> validateAndApply(String code, String userId) async {
    if (code.isEmpty) return true;
    
    state = const AsyncValue.loading();
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('referralCode', isEqualTo: code.toUpperCase())
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        state = AsyncValue.error("Code de parrainage invalide", StackTrace.current);
        return false;
      }

      final referrerId = query.docs.first.id;
      if (referrerId == userId) {
        state = AsyncValue.error("Vous ne pouvez pas vous parrainer vous-même", StackTrace.current);
        return false;
      }

      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'referredBy': referrerId,
        'referralRewardClaimed': false,
      }, SetOptions(merge: true));

      state = AsyncValue.data(referrerId);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }
}

final referralProvider = StateNotifierProvider<ReferralNotifier, AsyncValue<String?>>((ref) {
  return ReferralNotifier();
});
