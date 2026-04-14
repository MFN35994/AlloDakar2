import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'receipt_screen.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/providers/auth_provider.dart';

class YobanteSheet extends ConsumerStatefulWidget {
  const YobanteSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: const YobanteSheet(),
      ),
    );
  }

  @override
  ConsumerState<YobanteSheet> createState() => _YobanteSheetState();
}

class _YobanteSheetState extends ConsumerState<YobanteSheet> {
  String? _selectedDeparture;
  String? _selectedDestination;
  String? _selectedParcelType;
  final _baggageController = TextEditingController();
  final _senderPhoneController = TextEditingController();
  final _receiverPhoneController = TextEditingController();
  final _userPhoneController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String _paymentMethod = 'Espèces';
  bool _isProcessing = false;

  final List<String> _regions = [
    'Dakar', 'Diourbel', 'Fatick', 'Kaffrine', 'Kaolack', 'Kédougou', 
    'Kolda', 'Louga', 'Matam', 'Saint-Louis', 'Sédhiou', 'Tambacounda', 
    'Thiès', 'Ziguinchor',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const Text(
              'Yobanté (colis) 📦',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // Départ
            _buildDropdown('Région de récupération', Icons.outbox, Colors.blue, _selectedDeparture, (val) => setState(() => _selectedDeparture = val)),
            const SizedBox(height: 15),

            // Arrivée
            _buildDropdown('Région de livraison', Icons.inbox, Colors.red, _selectedDestination, (val) => setState(() => _selectedDestination = val)),
            const SizedBox(height: 15),

            // Téléphones
            _buildTextField(_senderPhoneController, 'Téléphone de l\'expéditeur', Icons.phone, Colors.blueAccent),
            const SizedBox(height: 10),
            _buildTextField(_receiverPhoneController, 'Téléphone du destinataire', Icons.phone, Colors.green),
            const SizedBox(height: 10),
            _buildTextField(
              _baggageController, 
              'Description des bagages', 
              Icons.inventory, 
              Colors.orange,
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 15),

            // Date & Heure
            _buildDateTimePickers(),
            const SizedBox(height: 15),

            // Type de colis
            DropdownButtonFormField<String>(
              decoration: _inputDecoration('Type de colis', Icons.inventory_2, Colors.orange),
              initialValue: _selectedParcelType,
              items: ['Petit', 'Moyen', 'Grand'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) => setState(() => _selectedParcelType = val),
            ),
            const SizedBox(height: 20),

            _buildPhoneFieldIfNeeded(),
            const SizedBox(height: 10),

            // Type de véhicule (optionnel ici mais gardé pour cohérence)
            _buildVehicleOption('Voiture 4 places', Icons.local_taxi, true),
            const SizedBox(height: 20),

            const Text(
              'Mode de paiement',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPaymentTile('Espèces', Icons.payments, Colors.green),
                  /* COMMENTÉ POUR LE LANCEMENT GRATUIT
                  if (ref.read(authProvider)?.role == 'driver') ...[
                    _buildPaymentTile('Portefeuille', Icons.account_balance_wallet, Colors.green),
                    const SizedBox(width: 10),
                  ],
                  _buildPaymentTile('Wave', Icons.tsunami, Colors.blue),
                  const SizedBox(width: 10),
                  _buildPaymentTile('Orange Money', Icons.money, Colors.orange),
                  */
                ],
              ),
            ),
            const SizedBox(height: 25),

            ElevatedButton(
              onPressed: (_selectedDeparture != null && _selectedDestination != null && _selectedParcelType != null)
                ? () async {
                    /* COMMENTÉ POUR LE LANCEMENT GRATUIT
                    if (_paymentMethod == 'Portefeuille') {
                      final wallet = ref.read(walletProvider);
                      if (wallet.balance < 10000) {
                        _showSnackBar("Solde insuffisant ! Veuillez recharger.", Colors.red);
                        return;
                      }
                    }
                    */

                    final auth = ref.read(authProvider);
                    final userId = auth?.userId ?? '';
                    final userData = await FirebaseFirestore.instance.collection('users').doc(userId).get();
                    final existingPhone = userData.data()?['phone'] as String?;

                    if ((existingPhone == null || existingPhone.isEmpty) && _userPhoneController.text.isEmpty) {
                      _showSnackBar("Votre numéro de téléphone est obligatoire.", Colors.red);
                      return;
                    }

                    // Simulation de paiement externe
                    if (_paymentMethod != 'Portefeuille') {
                      setState(() => _isProcessing = true);
                      await Future.delayed(const Duration(seconds: 2));
                      if (!mounted) return;
                      setState(() => _isProcessing = false);
                    }

                    if (_userPhoneController.text.isNotEmpty) {
                      await ref.read(authProvider.notifier).updateUserData(phone: _userPhoneController.text.trim());
                    }

                    final userName = userData.data()?['name'] ?? "Client ${userId.substring(0, 5)}";
                    final userPhone = _userPhoneController.text.isNotEmpty ? _userPhoneController.text.trim() : (existingPhone ?? "");

                    /* COMMENTÉ POUR LE LANCEMENT GRATUIT
                    if (_paymentMethod == 'Portefeuille') {
                      ref.read(walletProvider.notifier).debit(10000, "Yobanté $_selectedDeparture - $_selectedDestination");
                    }
                    */

                    final tripId = await ref.read(tripRepositoryProvider).createTrip(TripModel(
                      id: '',
                      departure: _selectedDeparture!,
                      destination: _selectedDestination!,
                      type: 'Livraison de colis ($_selectedParcelType)',
                      price: 10000,
                      status: 'pending',
                      createdAt: DateTime.now(),
                      scheduledDate: "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} ${_selectedTime.hour}:${_selectedTime.minute.toString().padLeft(2, '0')}",
                      baggageDescription: _baggageController.text,
                      clientName: userName,
                      clientPhone: userPhone,
                    ));

                    if (context.mounted) {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      
                      navigator.push(MaterialPageRoute(builder: (_) => ReceiptScreen(
                        orderId: 'YOB-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                        departure: _selectedDeparture!,
                        destination: _selectedDestination!,
                        price: '10 000 FCFA',
                        type: 'Livraison de colis ($_selectedParcelType)',
                        tripId: tripId,
                      )));
                    }
                  }
                : null,
              style: _buttonStyle(),
              child: _isProcessing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Confirmer • 10 000 FCFA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String hint, IconData icon, Color color, String? value, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      decoration: _inputDecoration(hint, icon, color),
      initialValue: value,
      items: _regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, Color color, {TextInputType keyboardType = TextInputType.phone}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _inputDecoration(hint, icon, color),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon, Color color) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: color),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      filled: true,
      fillColor: Theme.of(context).brightness == Brightness.light ? Colors.grey[100] : Colors.grey[850],
    );
  }

  Widget _buildDateTimePickers() {
    return Row(
      children: [
        Expanded(child: _buildPickerCell(Icons.calendar_month, '${_selectedDate.day}/${_selectedDate.month}', () async {
          final d = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
          if (d != null) setState(() => _selectedDate = d);
        })),
        const SizedBox(width: 10),
        Expanded(child: _buildPickerCell(Icons.access_time, _selectedTime.format(context), () async {
          final t = await showTimePicker(context: context, initialTime: _selectedTime);
          if (t != null) setState(() => _selectedTime = t);
        })),
      ],
    );
  }

  Widget _buildPickerCell(IconData icon, String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.light ? Colors.grey[100] : Colors.grey[850],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [Icon(icon, color: Colors.orange, size: 20), const SizedBox(width: 8), Text(text)]),
      ),
    );
  }

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.deepOrange,
      padding: const EdgeInsets.symmetric(vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      elevation: 8,
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Widget _buildPhoneFieldIfNeeded() {
    final auth = ref.watch(authProvider);
    if (auth == null) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(auth.userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data?['phone'] != null && (data?['phone'] as String).isNotEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Votre téléphone est obligatoire pour cette opération', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 5),
            TextField(controller: _userPhoneController, decoration: _inputDecoration('Votre numéro (ex: 77...)', Icons.phone_android, Colors.orange)),
          ],
        );
      },
    );
  }

  Widget _buildPaymentTile(String name, IconData icon, Color color) {
    final isSelected = _paymentMethod == name;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : (isDark ? Colors.grey[850] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? color : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleOption(String title, IconData icon, bool isSelected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: isDark ? 0.15 : 0.05),
        border: Border.all(color: Colors.deepOrange, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: Colors.orange),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
          ),
        ],
      ),
    );
  }
}
