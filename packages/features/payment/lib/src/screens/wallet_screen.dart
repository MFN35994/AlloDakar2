import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_payment/transen_payment.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _isLoading = false;
  final GlobalKey _receiptBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _handleSync());
  }

  Future<void> _handleSync() async {
    final auth = ref.read(authProvider);
    if (auth == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');
      final pendingDeps = await db.collection('users').doc(auth.userId).collection('pending_deposits').get();
      if (pendingDeps.docs.isEmpty) return;
      int creditedCount = 0;
      for (var doc in pendingDeps.docs) {
        final success = await ref.read(paymentRepositoryProvider).verifyAndCreditDeposit(auth.userId, doc.id);
        if (success) {
          creditedCount++;
          await doc.reference.delete();
        }
      }
      if (creditedCount > 0) {
        messenger.showSnackBar(SnackBar(content: Text('$creditedCount dépôt(s) crédité(s) !'), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Erreur sync auto: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.grey[50],
      appBar: AppBar(
        title: const Text('TransPay Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : TranSenColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.sync), onPressed: () => _handleSync()),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Balance Card
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(25),
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark 
                        ? [const Color(0xFF1E1E1E), const Color(0xFF121212)] 
                        : [TranSenColors.primaryGreen, TranSenColors.darkGreen],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('SOLDE DISPONIBLE', 
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        Icon(Icons.account_balance_wallet, color: Colors.white.withValues(alpha: 0.3), size: 24),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('${walletState.balance.toInt()} FCFA', 
                      style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _buildQuickAction(Icons.add, "Déposer", () => _showRechargeDialog(context)),
                        const SizedBox(width: 12),
                        _buildQuickAction(Icons.arrow_upward, "Retirer", () => _showWithdrawDialog(context, walletState.balance)),
                      ],
                    )
                  ],
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                child: Row(
                  children: [
                    Text('HISTORIQUE', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.5, color: Colors.grey)),
                    Spacer(),
                  ],
                ),
              ),
              
              Expanded(
                child: _buildTransactionsList(context, walletState),
              ),
            ],
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: TranSenColors.primaryGreen),
                        SizedBox(height: 20),
                        Text("Traitement SenePay...", style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("Veuillez patienter", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showRechargeDialog(BuildContext context) {
    final amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recharger mon compte'),
        content: TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant (FCFA)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANNULER')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text) ?? 0;
              if (amount < 100) return;
              Navigator.pop(context);
              setState(() => _isLoading = true);
              final messenger = ScaffoldMessenger.of(context);
              
              try {
                final auth = ref.read(authProvider);
                if (auth == null) return;
                final orderId = "D-${DateTime.now().millisecondsSinceEpoch}-${auth.userId}";
                
                messenger.showSnackBar(const SnackBar(content: Text('⏳ Envoi de la demande...')));
                
                final checkoutUrl = await ref.read(paymentRepositoryProvider).createSenePaySession(
                  amount: amount,
                  orderId: orderId,
                  description: "Depot TranSen",
                  customerName: auth.name,
                  customerPhone: auth.phone,
                );

                if (!mounted) return;

                if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
                  messenger.showSnackBar(const SnackBar(content: Text('✅ URL reçue ! Ouverture...'), backgroundColor: Colors.green));
                  
                  try {
                    await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
                        .collection('users').doc(auth.userId).collection('pending_deposits').doc(orderId).set({
                      'amount': amount, 'method': 'SenePay', 'status': 'Pending', 'createdAt': FieldValue.serverTimestamp(),
                    });
                  } catch (fsErr) {
                    debugPrint('>>> Firestore save pending deposit error: $fsErr');
                    // On ne bloque pas l'ouverture de l'URL même si Firebase refuse l'écriture (règles de sécurité)
                  }

                  final uri = Uri.parse(checkoutUrl);
                  try {
                    await launchUrl(uri);
                  } catch (launchErr) {
                    messenger.showSnackBar(SnackBar(content: Text('❌ Impossible d\'ouvrir le lien. Erreur: $launchErr'), backgroundColor: Colors.orange));
                  }
                } else {
                  messenger.showSnackBar(const SnackBar(content: Text('❌ Pas de réponse du serveur.'), backgroundColor: Colors.red));
                }
              } catch (e) {
                if (mounted) messenger.showSnackBar(SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red));
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: TranSenColors.primaryGreen, foregroundColor: Colors.white),
            child: const Text('PAYER'),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context, double balance) {
    final amountController = TextEditingController();
    final phoneController = TextEditingController();
    final nameController = TextEditingController();
    String selectedOperator = 'WAVE';
    bool isWithdrawing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Retrait vers Mobile Money', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Solde disponible : ${balance.toStringAsFixed(0)} FCFA', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Montant (min 500 FCFA)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    initialValue: selectedOperator,
                    decoration: const InputDecoration(labelText: 'Opérateur', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'WAVE', child: Text('Wave')),
                      DropdownMenuItem(value: 'ORANGE_MONEY', child: Text('Orange Money')),
                      DropdownMenuItem(value: 'FREE_MONEY', child: Text('Free Money')),
                    ],
                    onChanged: (val) {
                      if (val != null) setStateDialog(() => selectedOperator = val);
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Numéro de téléphone (ex: 771234567)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nom complet du destinataire', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              if (!isWithdrawing)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
                ),
              ElevatedButton(
                onPressed: isWithdrawing
                    ? null
                    : () async {
                        final amountText = amountController.text;
                        final amount = double.tryParse(amountText) ?? 0;
                        if (amount < 500) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le montant minimum est de 500 FCFA'), backgroundColor: Colors.red));
                          return;
                        }
                        if (amount > balance) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solde insuffisant'), backgroundColor: Colors.red));
                          return;
                        }
                        if (phoneController.text.isEmpty || nameController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez remplir tous les champs'), backgroundColor: Colors.red));
                          return;
                        }

                        setStateDialog(() => isWithdrawing = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(ctx);

                        try {
                          final auth = FirebaseAuth.instance.currentUser;
                          if (auth == null) throw Exception("Non connecté");
                          
                          await ref.read(paymentRepositoryProvider).requestPayout(
                            userId: auth.uid,
                            amount: amount,
                            recipientPhone: phoneController.text,
                            recipientName: nameController.text,
                            operator: selectedOperator,
                            description: 'Retrait TranSen',
                          );
                          if (nav.mounted) {
                            nav.pop();
                            messenger.showSnackBar(const SnackBar(content: Text('✅ Retrait initié avec succès !'), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          if (nav.mounted) {
                            messenger.showSnackBar(SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red));
                            setStateDialog(() => isWithdrawing = false);
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: TranSenColors.primaryGreen, foregroundColor: Colors.white),
                child: isWithdrawing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('RETIRER'),
              ),
            ],
          );
        },
      ),
    );
  }


  Widget _buildTransactionsList(BuildContext context, dynamic walletState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (walletState.transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('Aucune transaction pour le moment.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      itemCount: walletState.transactions.length,
      itemBuilder: (context, index) {
        final txn = walletState.transactions[index];
        final isDebit = txn.amount < 0;
        final isPoints = txn.points > 0;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white.withValues(alpha: 0.5),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () => _showTransactionDetails(context, txn),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isPoints 
                    ? Colors.amber.withValues(alpha: 0.1)
                    : (isDebit ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1)),
                child: Icon(
                  isPoints ? Icons.stars : (isDebit ? Icons.arrow_outward : Icons.arrow_downward),
                  color: isPoints ? Colors.amber : (isDebit ? Colors.red : Colors.green),
                ),
              ),
              title: Text(txn.description, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black)),
              subtitle: Text(
                '${txn.date.day}/${txn.date.month}/${txn.date.year} à ${txn.date.hour}:${txn.date.minute.toString().padLeft(2, "0")}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              trailing: Text(
                isPoints 
                    ? '+${txn.points} pts'
                    : '${isDebit ? "" : "+"}${txn.amount.toInt()} F',
                style: TextStyle(
                  color: isPoints ? Colors.amber.shade700 : (isDebit ? Colors.red : Colors.green),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _captureAndShare(String orderId) async {
    try {
      RenderRepaintBoundary? boundary = _receiptBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final buffer = byteData.buffer.asUint8List();
      
      final xFile = XFile.fromData(
        buffer,
        name: 'recu_$orderId.png',
        mimeType: 'image/png',
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: 'Mon reçu TranSen 🚕',
        ),
      );
    } catch (e) {
      debugPrint("Erreur capture: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors du partage : $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showTransactionDetails(BuildContext context, WalletTransaction txn) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 25),
            RepaintBoundary(
              key: _receiptBoundaryKey,
              child: Container(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                child: Column(
                  children: [
                    const Text('REÇU DE TRANSACTION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.5, color: Colors.grey)),
                    const SizedBox(height: 20),
                    
                    // Amount and Icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          txn.amount < 0 ? Icons.arrow_outward : Icons.arrow_downward,
                          color: txn.amount < 0 ? Colors.red : Colors.green,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${txn.amount < 0 ? "" : "+"}${txn.amount.toInt()} FCFA',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(txn.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _getStatusColor(txn.status).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _getStatusLabel(txn.status).toUpperCase(),
                        style: TextStyle(color: _getStatusColor(txn.status), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Dotted Separator
                    Row(
                      children: List.generate(
                        30,
                        (index) => Expanded(
                          child: Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            color: index % 2 == 0 ? Colors.grey[300] : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Details
                    _buildDetailRow("Type de transaction", _getTypeLabel(txn.type)),
                    _buildDetailRow("ID Transaction", txn.id.substring(0, 8).toUpperCase()),
                    _buildDetailRow("Date", '${txn.date.day}/${txn.date.month}/${txn.date.year} à ${txn.date.hour}:${txn.date.minute.toString().padLeft(2, "0")}'),
                    _buildDetailRow("Description", txn.description),
                    if (txn.reference != null)
                      _buildDetailRow("Référence", txn.reference!),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _captureAndShare(txn.id),
                    icon: const Icon(Icons.share, color: TranSenColors.primaryGreen),
                    label: const Text('PARTAGER', style: TextStyle(color: TranSenColors.primaryGreen, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: TranSenColors.primaryGreen),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TranSenColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('FERMER', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 20),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return Colors.green;
      case 'pending': return Colors.orange;
      case 'failed': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return "Terminé";
      case 'pending': return "En attente";
      case 'failed': return "Échoué";
      default: return status;
    }
  }

  String _getTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'deposit': return "Dépôt SenePay";
      case 'withdrawal': return "Retrait Mobile Money";
      case 'commission': return "Commission Plateforme";
      case 'subscription': return "Abonnement Premium";
      case 'points': return "Bonus Fidélité";
      default: return "Transaction";
    }
  }
}
