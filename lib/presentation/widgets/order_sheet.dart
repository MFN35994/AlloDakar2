import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/transen_colors.dart';

import 'receipt_screen.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/providers/trip_providers.dart' as providers;
import '../../domain/providers/auth_provider.dart';
import '../../domain/providers/pool_providers.dart';
import 'pool_progress_indicator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class OrderSheet extends ConsumerStatefulWidget {
  final String? initialDeparture;
  final String? initialDestination;
  final String? driverId;

  const OrderSheet({
    super.key,
    this.initialDeparture,
    this.initialDestination,
    this.driverId,
  });

  /// Affiche le panneau coulissant (BottomSheet) depuis n'importe où
  static void show(
    BuildContext context, {
    String? departure,
    String? destination,
    String? driverId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: OrderSheet(
          initialDeparture: departure,
          initialDestination: destination,
          driverId: driverId,
        ),
      ),
    );
  }

  @override
  ConsumerState<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends ConsumerState<OrderSheet> {
  String _selectedVehicle = 'Voiture 4 places';
  String? _selectedDeparture;
  String? _selectedDestination;
  int _selectedSeats = 1;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String _paymentMethod = 'Espèces';
  bool _isProcessing = false;
  bool _useBonusPoints = false;
  int _userBonusPoints = 0;

  @override
  void initState() {
    super.initState();
    _selectedDeparture = widget.initialDeparture;
    _selectedDestination = widget.initialDestination;
  }


  // Liste des 14 régions du Sénégal
  final List<String> _regions = [
    'Dakar',
    'Diourbel',
    'Fatick',
    'Kaffrine',
    'Kaolack',
    'Kédougou',
    'Kolda',
    'Louga',
    'Matam',
    'Saint-Louis',
    'Sédhiou',
    'Tambacounda',
    'Thiès',
    'Ziguinchor',
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
            // Petite barre horizontale au dessus pour indiquer qu'on peut glisser vers le bas
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            // Titre du formulaire
            const Text(
              'Où allez-vous ?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // Liste déroulante : Point de départ
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                hintText: 'Région de départ',
                prefixIcon: const Icon(Icons.my_location, color: Colors.blue),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.light ? Colors.grey[100] : Colors.grey[850],
              ),
              initialValue: _selectedDeparture,
              icon: const Icon(Icons.arrow_drop_down),
              isExpanded: true,
              items: _regions.map((region) {
                return DropdownMenuItem(
                  value: region,
                  child: Text(region),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDeparture = value;
                });
              },
            ),
            const SizedBox(height: 15),

            // Liste déroulante : Destination
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                hintText: 'Région de destination',
                prefixIcon: const Icon(Icons.location_on, color: Colors.red),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              initialValue: _selectedDestination,
              icon: const Icon(Icons.arrow_drop_down),
              isExpanded: true,
              items: _regions.map((region) {
                return DropdownMenuItem(
                  value: region,
                  child: Text(region),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDestination = value;
                });
              },
            ),
            const SizedBox(height: 15),

            // --- LOGIQUE DE POOLING VISUELLE ---
            if (_selectedDeparture != null && _selectedDestination != null)
              Consumer(
                builder: (context, ref, child) {
                  final poolsAsync = ref.watch(activePoolsProvider);
                  return poolsAsync.when(
                    data: (pools) {
                      final existingPool = pools.where((p) => 
                        p.departure == _selectedDeparture && 
                        p.destination == _selectedDestination &&
                        p.status == 'open'
                      ).firstOrNull;

                      final currentFilling = existingPool?.currentFilling ?? 0;
                      final estMinutes = (4 - currentFilling) * 15;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: TranSenColors.primaryGreen.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: TranSenColors.primaryGreen.withValues(alpha: 0.2)),

                        ),
                        child: Column(
                          children: [
                            PoolProgressIndicator(
                              current: currentFilling,
                              estimatedDeparture: "Départ estimé dans ~$estMinutes min",
                            ),
                            const SizedBox(height: 10),
                            Text(
                              existingPool != null 
                                ? "Groupe trouvé ! Rejoignez-le pour partir plus vite." 
                                : "Aucun groupe en cours. Soyez le premier à lancer ce trajet !",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                            if (existingPool != null) ...[
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _isProcessing ? null : () => _handleConfirmation(ref, overrideDate: existingPool.scheduledDate),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: TranSenColors.primaryGreen,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 4,
                                ),
                                child: const Text(
                                  "REJOINDRE CE GROUPE", 
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),

            // Nouveau : Nombre de places
            Row(
              children: [
                const Icon(Icons.groups, color: Colors.grey),
                const SizedBox(width: 10),
                const Text('Places à prendre :', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                DropdownButton<int>(
                  value: _selectedSeats,
                  items: [1, 2, 3, 4].map((i) => DropdownMenuItem(value: i, child: Text('$i'))).toList(),
                  onChanged: (val) => setState(() => _selectedSeats = val!),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Nouveau : Date et Heure souhaitées
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (date != null) setState(() => _selectedDate = date);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light ? Colors.grey[100] : Colors.grey[850],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month, color: TranSenColors.primaryGreen, size: 20),

                          const SizedBox(width: 8),
                          Text('${_selectedDate.day}/${_selectedDate.month}', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (time != null) setState(() => _selectedTime = TimeOfDay(hour: time.hour, minute: 0));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light ? Colors.grey[100] : Colors.grey[850],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, color: TranSenColors.primaryGreen, size: 20),

                          const SizedBox(width: 8),
                          Text(_selectedTime.format(context), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Sélection du type de véhicule
            const Text(
              'Type de véhicule',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildVehicleOption(
                    'Voiture 4 places',
                    Icons.local_taxi,
                    _selectedVehicle == 'Voiture 4 places',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Sélection du mode de paiement
            const Text(
              'Mode de paiement',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                   _buildPaymentTile('Espèces', Icons.payments, Colors.green),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- NOUVEAU: POINTS BONUS ---
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('users').doc(ref.read(authProvider)?.userId).get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                _userBonusPoints = data?['bonusPoints'] ?? 0;

                if (_userBonusPoints <= 0) return const SizedBox.shrink();

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.stars, color: Colors.green, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Points Bonus: $_userBonusPoints",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                            ),
                            const Text(
                              "Utilisez vos points pour une réduction",
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _useBonusPoints,
                        onChanged: (val) => setState(() => _useBonusPoints = val),
                        activeThumbColor: Colors.green,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),


            Consumer(builder: (context, ref, child) {
              final activePool = ref.watch(providers.activePoolProvider).value;
              final hasActivePool = activePool != null;

              return ElevatedButton(
                onPressed: (_selectedDeparture != null && _selectedDestination != null)
                    ? () => _handleConfirmation(ref, hasActivePool: hasActivePool)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasActivePool ? Colors.grey : TranSenColors.primaryGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 8,
                  shadowColor: TranSenColors.primaryGreen.withValues(alpha: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      hasActivePool ? 'COURSE DÉJÀ EN COURS' : 'REJOINDRE LE TRAJET  • ',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (_isProcessing)
                      const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    else if (!hasActivePool)
                      Text(
                        '${_useBonusPoints ? (10000 - _userBonusPoints).clamp(0, 10000) : 10000} FCFA',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _handleConfirmation(WidgetRef ref, {bool hasActivePool = false, String? overrideDate}) async {
    if (hasActivePool) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vous avez déjà une course en cours. Terminez-la ou attendez avant d'en créer une nouvelle."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final auth = ref.read(authProvider);
    final userId = auth?.userId ?? '';
    
    try {
      setState(() => _isProcessing = true);

      final userData = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('users').doc(userId).get();
      final existingPhone = userData.data()?['phone'] as String?;
      
      if (!mounted) return;
      if (existingPhone == null || existingPhone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Veuillez compléter votre profil avec un numéro de téléphone valide.")),
        );
        setState(() => _isProcessing = false);
        return;
      }

      // Simulation de paiement externe (si pas portefeuille)
      if (_paymentMethod != 'Portefeuille') {
        await Future.delayed(const Duration(seconds: 1));
      }

      final userFirstName = userData.data()?['firstName'];
      final userLastName = userData.data()?['lastName'];
      final userName = userData.data()?['name'] ?? "Client ${userId.substring(0, 5)}";
      final userPhone = existingPhone;

      final tripRepo = ref.read(tripRepositoryProvider);
      final scheduledDate = overrideDate ?? "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} ${_selectedTime.hour}:${_selectedTime.minute.toString().padLeft(2, '0')}";
      
      int finalPrice = 10000;
      if (_useBonusPoints) {
        finalPrice = (10000 - _userBonusPoints).clamp(0, 10000);
      }

      double lat = 14.7167; 
      double lng = -17.4677;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 3),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (e) {
        debugPrint("Erreur localisation: $e");
      }

      final poolId = await tripRepo.joinOrCreatePool(
        userId: userId,
        departure: _selectedDeparture!,
        destination: _selectedDestination!,
        scheduledDate: scheduledDate,
        lat: lat,
        lng: lng,
        seats: _selectedSeats,
        userDetails: {
          'name': userName,
          'firstName': userFirstName,
          'lastName': userLastName,
          'phone': userPhone,
        },
      );

      if (_useBonusPoints && _userBonusPoints > 0) {
        await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('users').doc(userId).update({
          'bonusPoints': 0,
        });
      }

      if (!mounted) return;
      setState(() => _isProcessing = false);
      
      final navigator = Navigator.of(context);
      navigator.pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Demande enregistrée ! Votre départ sera confirmé dès que le groupe sera complet."),
            backgroundColor: Colors.green,
          ),
        );

        navigator.push(MaterialPageRoute(
          builder: (_) => ReceiptScreen(
            orderId: 'POOL-${poolId.substring(0, 5).toUpperCase()}',
            departure: _selectedDeparture!,
            destination: _selectedDestination!,
            price: '$finalPrice FCFA',
            type: 'Covoiturage Intelligent',
            tripId: poolId,
          ),
        ));
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red),
        );
      }
    }
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

  // Widget personnalisé pour les options de véhicule
  Widget _buildVehicleOption(String title, IconData icon, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVehicle = title;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? TranSenColors.primaryGreen.withValues(alpha: isSelected ? (Theme.of(context).brightness == Brightness.light ? 0.05 : 0.15) : 1) 
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: isSelected ? TranSenColors.accentGold : (Theme.of(context).brightness == Brightness.light ? Colors.grey.shade200 : Colors.grey.shade800),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected ? [
            BoxShadow(
              color: TranSenColors.primaryGreen.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ] : [],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? TranSenColors.primaryGreen : (Theme.of(context).brightness == Brightness.light ? Colors.grey.shade600 : Colors.grey.shade400),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? TranSenColors.primaryGreen : (Theme.of(context).brightness == Brightness.light ? Colors.grey.shade800 : Colors.grey.shade400),

                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
