import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/repositories/user_repository.dart';
import 'auth_provider.dart';

class WalletTransaction {
  final String description;
  final double amount;
  final DateTime date;

  WalletTransaction(this.description, this.amount, this.date);
}

class WalletState {
  final double balance;
  final List<WalletTransaction> transactions;

  WalletState(this.balance, this.transactions);
}

class WalletNotifier extends StateNotifier<WalletState> {
  final UserRepository _userRepo = UserRepository();
  final String _userId;

  WalletNotifier(this._userId) : super(WalletState(0.0, [])) {
    _init();
  }

  void _init() {
    // Écouter le solde
    _userRepo.watchWalletBalance(_userId).listen((balance) {
      state = WalletState(balance, state.transactions);
    });

    // Écouter les transactions
    _userRepo.watchTransactions(_userId).listen((transData) {
      final transactions = transData.map((data) {
        return WalletTransaction(
          data['description'] ?? '',
          (data['amount'] ?? 0).toDouble(),
          (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();
      state = WalletState(state.balance, transactions);
    });
  }

  void debit(double amount, String description) async {
    await _userRepo.updateWalletBalance(_userId, -amount, description);
  }

  void credit(double amount, String description) async {
    await _userRepo.updateWalletBalance(_userId, amount, description);
  }
}

final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  final auth = ref.watch(authProvider);
  final userId = auth?.userId ?? 'unknown_user';
  return WalletNotifier(userId);
});
