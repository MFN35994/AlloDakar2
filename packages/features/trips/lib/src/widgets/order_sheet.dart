
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:transen_trips/transen_trips.dart' as providers;
import 'package:flutter/services.dart';

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
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: OrderSheet(
            initialDeparture: departure,
            initialDestination: destination,
            driverId: driverId,
          ),
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
  String _paymentMethod = 'Espèces'; // Par défaut
  bool _isProcessing = false;

  TimeOfDay _roundToNearest15Mins(TimeOfDay time) {
    int minute = time.minute;
    int roundedMinute = (minute / 15).round() * 15;
    int hour = time.hour;
    if (roundedMinute == 60) {
      roundedMinute = 0;
      hour = (hour + 1) % 24;
    }
    return TimeOfDay(hour: hour, minute: roundedMinute);
  }

  DateTime _parseDate(String d) {
    try {
      final parts = d.split(' ');
      final dateParts = parts[0].split('/');
      final timeParts = parts[1].split(':');
      return DateTime(int.parse(dateParts[2]), int.parse(dateParts[1]), int.parse(dateParts[0]), int.parse(timeParts[0]), int.parse(timeParts[1]));
    } catch (_) {
      return DateTime.now();
    }
  }

  String? _preferredDriverName;
  String? _preferredDriverId;

  @override
  void initState() {
    super.initState();
    _selectedTime = _roundToNearest15Mins(TimeOfDay.now());
    _selectedDeparture = widget.initialDeparture;
    _selectedDestination = widget.initialDestination;
    _preferredDriverId = widget.driverId;
    
    if (_preferredDriverId != null) {
      _fetchDriverName();
    }

    if (_selectedDeparture == null) {
      _autoDetectLocation();
    }
  }

  Future<void> _fetchDriverName() async {
    try {
      final doc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
          .collection('users').doc(widget.driverId).get();
      if (doc.exists && mounted) {
        setState(() {
          _preferredDriverName = doc.data()?['name'] ?? doc.data()?['firstName'] ?? 'Chauffeur favori';
        });
      }
    } catch (e) {
      debugPrint("Erreur fetch driver name: $e");
    }
  }

  Future<void> _autoDetectLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 5),
          ),
        );
        final region = LocationHelper.detectRegion(pos);
        if (mounted) {
          setState(() => _selectedDeparture = region);
        }
      }
    } catch (e) {
      debugPrint("Erreur auto-detection: $e");
    }
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
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text(
                    'Où allez-vous ? (Paiement Espèces)',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48), // Pour équilibrer le titre
              ],
            ),
            const SizedBox(height: 20),
            if (_preferredDriverName != null)
              Container(
                margin: const EdgeInsets.only(bottom: 15),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Chauffeur favori : $_preferredDriverName",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _preferredDriverName = null;
                        _preferredDriverId = null;
                      }),
                    ),
                  ],
                ),
              ),
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

            // --- FAVORIS RAPIDES ---
            Consumer(builder: (context, ref, child) {
              final auth = ref.watch(authProvider);
              final favoritesAsync = ref.watch(favoriteAddressesProvider(auth?.userId ?? ''));
              
              return favoritesAsync.when(
                data: (favs) {
                  if (favs.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Favoris", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 35,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: favs.length,
                          itemBuilder: (context, index) {
                            final fav = favs[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                avatar: Icon(fav.icon, size: 14, color: TranSenColors.primaryGreen),
                                label: Text(fav.label, style: const TextStyle(fontSize: 11)),
                                onPressed: () => setState(() => _selectedDestination = fav.address),
                                backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.grey[100] : Colors.grey[850],
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: EdgeInsets.zero,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 15),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            }),

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
                fillColor: Theme.of(context).brightness == Brightness.light ? Colors.grey[100] : Colors.grey[850],
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
                      final reqDate = _parseDate("${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} ${_selectedTime.hour}:${_selectedTime.minute.toString().padLeft(2, '0')}");
                      
                      final existingPool = pools.where((p) {
                        if (p.departure != _selectedDeparture || p.destination != _selectedDestination || p.status != 'open') return false;
                        final poolDate = _parseDate(p.scheduledDate);
                        return poolDate.difference(reqDate).inMinutes.abs() <= 15;
                      }).firstOrNull;

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
                      if (time != null) {
                        setState(() => _selectedTime = _roundToNearest15Mins(time));
                      }
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
              'Mode de paiement (Remise espèces au chauffeur)',
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
                   _buildPaymentIconTile('Espèces', null, Colors.green),
                   const SizedBox(width: 10),
                   _buildPaymentIconTile('Wave', 'assets/images/wave.png', Colors.blue),
                   const SizedBox(width: 10),
                   _buildPaymentIconTile('Orange Money', 'assets/images/om.png', Colors.orange),
                   const SizedBox(width: 10),
                   _buildPaymentIconTile('Free Money', 'assets/images/fm.png', Colors.red),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const SizedBox(height: 10),


            Consumer(builder: (context, ref, child) {
              final activePool = ref.watch(providers.activePoolProvider).value;
              final hasActivePool = activePool != null;

              return ElevatedButton(
                onPressed: (_selectedDeparture != null && _selectedDestination != null && !_isProcessing)
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
                      const Text(
                        '10000 FCFA',
                        style: TextStyle(
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
      final data = userData.data();
      String phoneToValidate = data?['phone'] ?? (data?['phoneNumber'] ?? (auth?.phone ?? ''));
      final userPhoneDigits = phoneToValidate.replaceAll(RegExp(r'\D'), '');
      
      if (!mounted) return;
      
      // Validation : au moins 9 chiffres (format Sénégal)
      if (userPhoneDigits.length < 9) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Numéro de téléphone incomplet (9 chiffres requis)."),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isProcessing = false);
        return;
      }

      final userFirstName = userData.data()?['firstName'];
      final userLastName = userData.data()?['lastName'];
      final userName = userData.data()?['name'] ?? "Client ${userId.substring(0, 5)}";
      
      // On s'assure d'avoir les 9 chiffres propres
      String finalPhone = userPhoneDigits;
      if (finalPhone.startsWith('221') && finalPhone.length >= 12) {
        finalPhone = finalPhone.substring(3);
      }

      // Gestion SenePay reportée à l'écran de suivi
      if (_paymentMethod != 'Espèces' && _paymentMethod != 'Portefeuille') {
        // On enregistre juste l'intention de paiement
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final tripRepo = ref.read(tripRepositoryProvider);
      final scheduledDate = overrideDate ?? "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} ${_selectedTime.hour}:${_selectedTime.minute.toString().padLeft(2, '0')}";
      
      int finalPrice = 10000;

      double lat = 14.7167; 
      double lng = -17.4677;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 3),
          ),
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
        preferredDriverId: _preferredDriverId,
        userDetails: {
          'name': userName,
          'firstName': userFirstName,
          'lastName': userLastName,
          'phone': finalPhone,
          'paymentMethod': _paymentMethod,
        },
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);
      
      final navigator = Navigator.of(context);
      navigator.pop();
      
      SuccessDialog.show(
        context,
        title: 'Demande enregistrée !',
        message: 'Votre départ sera confirmé dès que le groupe sera complet.',
        onDismiss: () {
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
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red),
        );
      }
    }
  }


  Widget _buildPaymentIconTile(String name, String? assetPath, Color color) {
    final isSelected = _paymentMethod == name;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _paymentMethod = name);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : (isDark ? Colors.grey[850] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? color : Colors.transparent, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (assetPath != null)
              Image.asset(assetPath, width: 24, height: 24, errorBuilder: (_, __, ___) => Icon(Icons.payment, color: color, size: 20))
            else
              Icon(Icons.payments, color: isSelected ? color : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
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
