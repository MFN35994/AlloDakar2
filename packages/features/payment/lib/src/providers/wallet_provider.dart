import "package:cloud_firestore/cloud_firestore.dart";
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_auth/transen_auth.dart';
import '../data/repositories/payment_repository.dart';

class WalletTransaction {
  final String description;
  final double amount;
  final DateTime date;

  WalletTransaction(this.description, this.amount, this.date);
}

class WalletState {
  final double balance;
  final int points;
  final List<WalletTransaction> transactions;

  WalletState(this.balance, this.points, this.transactions);
}

class WalletNotifier extends Notifier<WalletState> {
  late final PaymentRepository _paymentRepo;

  @override
  WalletState build() {
    _paymentRepo = ref.watch(paymentRepositoryProvider);
    final auth = ref.watch(authProvider);
    final userId = auth?.userId ?? 'unknown_user';
    
    _init(userId);
    return WalletState(0.0, 0, []);
  }

  void _init(String userId) {
    if (userId == 'unknown_user') return;
    
    // Écouter le solde
    _paymentRepo.watchWalletBalance(userId).listen((balance) {
      state = WalletState(balance, state.points, state.transactions);
    });

    // Écouter les points
    _paymentRepo.watchPoints(userId).listen((points) {
      state = WalletState(state.balance, points, state.transactions);
    });

    // Écouter les transactions
    _paymentRepo.watchTransactions(userId).listen((transData) {
      final transactions = transData.map((data) {
        return WalletTransaction(
          data['description'] ?? '',
          (data['amount'] ?? 0).toDouble(),
          (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();
      state = WalletState(state.balance, state.points, transactions);
    });
  }

  Future<void> debit(double amount, String description) async {
    final auth = ref.read(authProvider);
    if (auth == null) return;
    await _paymentRepo.updateWalletBalance(auth.userId, -amount, description);
  }

  Future<void> credit(double amount, String description) async {
    final auth = ref.read(authProvider);
    if (auth == null) return;
    await _paymentRepo.updateWalletBalance(auth.userId, amount, description);
  }
}

final walletProvider = NotifierProvider<WalletNotifier, WalletState>(WalletNotifier.new);
