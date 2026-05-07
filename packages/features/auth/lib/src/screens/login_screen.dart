
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_core/transen_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart'; // Par sécurité car on utilise Firebase.app() ailleurs
import '../providers/auth_provider.dart';
import '../providers/referral_provider.dart';
import 'package:flutter/services.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

enum AuthStep { phone, identity, otp }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _referralController = TextEditingController();

  final _phoneMaskFormatter = MaskTextInputFormatter(mask: '## ### ## ##', filter: { "#": RegExp(r'[0-9]') });
  String _validatedPhone = "";

  AuthStep _step = AuthStep.phone;
  bool _localLoading = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  // LOGIQUE SÉCURISÉE (Solution 2)
  Future<void> _sendOtp() async {
    String phone = _phoneController.text.trim().replaceAll(' ', '');
    
    // Validation de longueur pour le Sénégal (9 chiffres attendus après nettoyage)
    String digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 9) {
      HapticFeedback.heavyImpact();
      _showError("Numéro incomplet. Veuillez entrer 9 chiffres.");
      return;
    }
    
    if (!phone.startsWith('+')) {
      phone = '+221$digitsOnly';
    } else {
      // Si déjà avec +, on s'assure qu'il n'y a pas d'espaces
      phone = phone.replaceAll(' ', '');
    }

    setState(() {
      _validatedPhone = digitsOnly; // On stocke les 9 chiffres
      _localLoading = true;
    });
    try {
      HapticFeedback.lightImpact();
      await ref.read(authProvider.notifier).sendPhoneVerificationCode(phone);
      setState(() => _step = AuthStep.otp);
    } catch (e) {
      _showError("Erreur d'envoi : ${e.toString()}");
    } finally {
      setState(() => _localLoading = false);
    }
  }

  Future<void> _saveIdentity() async {
    if (_firstNameController.text.trim().isEmpty || _lastNameController.text.trim().isEmpty) {
      _showError("Veuillez entrer votre prénom et votre nom");
      return;
    }

    try {
      // 1. Essayer de récupérer le numéro mémorisé localement
      String finalPhone = _validatedPhone;

      // 2. Si perdu (remount), essayer de le récupérer depuis Firebase Auth
      if (finalPhone.length < 9) {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser?.phoneNumber != null && currentUser!.phoneNumber!.length >= 9) {
          finalPhone = currentUser.phoneNumber!.replaceAll(RegExp(r'\D'), '');
          // Enlever le 221 si présent pour garder 9 chiffres
          if (finalPhone.startsWith('221') && finalPhone.length >= 12) {
            finalPhone = finalPhone.substring(3);
          }
        }
      }

      // 3. Si toujours rien, essayer de relire le controller
      if (finalPhone.length < 9) {
        String rawPhone = _phoneController.text.trim().replaceAll(' ', '');
        finalPhone = rawPhone.replaceAll(RegExp(r'\D'), '');
        if (finalPhone.startsWith('221') && finalPhone.length >= 12) {
          finalPhone = finalPhone.substring(3);
        }
      }

      if (finalPhone.length < 9) {
        _showError("Session expirée : numéro de téléphone introuvable. Veuillez recommencer l'étape 1.");
        setState(() => _step = AuthStep.phone);
        return;
      }

      await ref.read(authProvider.notifier).updateUserData(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: finalPhone,
      );

      if (_referralController.text.isNotEmpty) {
        final auth = ref.read(authProvider);
        if (auth != null) {
          await ref.read(referralProvider.notifier).validateAndApply(
                _referralController.text.trim(),
                auth.userId,
              );
        }
      }
      // Une fois sauvegardé, le AuthGate redirigera vers RoleSelectionScreen
    } catch (e) {
      _showError("Erreur de sauvegarde : ${e.toString()}");
    }
  }

  Future<void> _signInWithOtp() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      _showError("Le code doit comporter 6 chiffres");
      return;
    }
    try {
      await ref.read(authProvider.notifier).verifySmsCode(code);
    } catch (e) {
      _showError("Code incorrect ou expiré");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authProvider);
    final isLoading = (authState?.isLoading ?? false) || _localLoading;

    // Détermination de l'étape en fonction de l'état d'authentification
    AuthStep currentStep = _step;
    if (authState != null && authState.userId.isNotEmpty && (authState.name == null || authState.name!.isEmpty)) {
      currentStep = AuthStep.identity;
    }

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : TranSenColors.primaryGreen,
      body: PremiumBackground(
        blobColors: isDarkMode 
          ? [Colors.blue.withValues(alpha: 0.1), Colors.purple.withValues(alpha: 0.1)]
          : [Colors.white.withValues(alpha: 0.2), Colors.greenAccent.withValues(alpha: 0.1)],
        child: SingleChildScrollView(
          child: Column(
            children: [
            _buildHeader(isDarkMode),
            const SizedBox(height: 30),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              // Ajuste la hauteur de manière fluide en fonction des champs affichés
              height: currentStep == AuthStep.otp ? 200 : (currentStep == AuthStep.identity ? 450 : 200),
              child: _buildPhoneForm(isDarkMode, isLoading, currentStep),
            ),
            const SizedBox(height: 40),
            Text(
              'v1.0.0+1',
              style: TextStyle(
                color: isDarkMode ? Colors.white24 : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 70, bottom: 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode ? [const Color(0xFF1A1A1A), const Color(0xFF121212)] : [Colors.white, Colors.grey.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(80)),
        boxShadow: [
          BoxShadow(
              color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))
        ],
      ),
      child: Column(
        children: [
          Hero(
            tag: 'auth_icon',
            child: Image.asset('assets/images/logo.png',
                height: 100,
                errorBuilder: (c, e, s) => Icon(Icons.directions_car,
                    size: 80, color: isDarkMode ? Colors.white : TranSenColors.primaryGreen)),
          ),
          const SizedBox(height: 15),
          Text("Bienvenue sur TranSen",
              style: TextStyle(
                  color: isDarkMode ? Colors.white : TranSenColors.primaryGreen,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          Text("LE TRANSPORT 5 ÉTOILES AU SÉNÉGAL",
              style: TextStyle(
                  color: isDarkMode ? Colors.white70 : TranSenColors.primaryGreen.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _buildPhoneForm(bool isDarkMode, bool isLoading, AuthStep step) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.2),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Column(
            key: ValueKey<String>('$step'),
            children: [
              if (step == AuthStep.identity) ...[
                _buildTextField(
                    controller: _firstNameController,
                    label: "Prénom",
                    icon: Icons.person_outline,
                    isDarkMode: isDarkMode),
                const SizedBox(height: 10),
                _buildTextField(
                    controller: _lastNameController,
                    label: "Nom",
                    icon: Icons.person_outline,
                    isDarkMode: isDarkMode),
                const SizedBox(height: 10),
                // Affichage du numéro validé
                Builder(
                  builder: (context) {
                    String displayPhone = _validatedPhone;
                    if (displayPhone.isEmpty) {
                      displayPhone = FirebaseAuth.instance.currentUser?.phoneNumber?.replaceAll(RegExp(r'\D'), '') ?? '';
                      if (displayPhone.startsWith('221') && displayPhone.length >= 12) {
                        displayPhone = displayPhone.substring(3);
                      }
                    }
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.phone_android, size: 20, color: isDarkMode ? Colors.white70 : Colors.grey),
                          const SizedBox(width: 10),
                          Text(
                            displayPhone.length == 9 
                              ? "${displayPhone.substring(0, 2)} ${displayPhone.substring(2, 5)} ${displayPhone.substring(5, 7)} ${displayPhone.substring(7, 9)}"
                              : displayPhone.isEmpty ? "Numéro validé" : displayPhone,
                            style: TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : Colors.black87
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        ],
                      ),
                    );
                  }
                ),
              ],

              if (step == AuthStep.phone)
                _buildTextField(
                    controller: _phoneController,
                    label: "Numéro de téléphone (ex: 77 123 45 67)",
                    icon: Icons.phone_android,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [_phoneMaskFormatter],
                    isDarkMode: isDarkMode),

              if (step == AuthStep.otp)
                _buildTextField(
                    controller: _otpController,
                    label: "Code OTP",
                    icon: Icons.vibration,
                    keyboardType: TextInputType.number,
                    isDarkMode: isDarkMode),

              if (step == AuthStep.identity) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4, bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 13, color: Colors.orange),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          "Utilisez votre vrai numéro. Les chauffeurs et clients vous contacteront à ce numéro.",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildTextField(
                    controller: _referralController,
                    label: "Code parrainage (optionnel)",
                    icon: Icons.card_giftcard,
                    isDarkMode: isDarkMode,
                    textCapitalization: TextCapitalization.characters),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    text: "En vous inscrivant, vous acceptez nos ",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                    children: [
                      TextSpan(
                        text: "CGU",
                        style: const TextStyle(
                          color: TranSenColors.primaryGreen,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LegalScreen(
                                title: 'Conditions Générales',
                                assetPath: 'assets/legal/cgu.md',
                              ),
                            ),
                          ),
                      ),
                      const TextSpan(text: " et notre "),
                      TextSpan(
                        text: "Politique de Confidentialité",
                        style: const TextStyle(
                          color: TranSenColors.primaryGreen,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LegalScreen(
                                title: 'Politique de Confidentialité',
                                assetPath: 'assets/legal/politique_confidentialite.md',
                              ),
                            ),
                          ),
                      ),
                      const TextSpan(text: "."),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              if (step == AuthStep.otp)
                TextButton(
                    onPressed: () => setState(() => _step = AuthStep.phone),
                    child: const Text("Changer de numéro",
                        style: TextStyle(color: Colors.grey, fontSize: 12))),
              
              const SizedBox(height: 15),

              if (isLoading)
                const CircularProgressIndicator(color: TranSenColors.primaryGreen)
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : () async {
                      await HapticFeedback.lightImpact();
                      if (step == AuthStep.phone) {
                        _sendOtp();
                      } else if (step == AuthStep.identity) {
                        _saveIdentity();
                      } else {
                        _signInWithOtp();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDarkMode ? Colors.white : Colors.white,
                      foregroundColor: isDarkMode ? Colors.black : TranSenColors.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      elevation: 5,
                    ),
                    child: Text(
                        step == AuthStep.otp 
                            ? "VÉRIFIER LE CODE" 
                            : (step == AuthStep.identity ? "FINALISER" : "CONTINUER"),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),

              // Mention légale pour la CONNEXION (Step Téléphone)
              if (step == AuthStep.phone) ...
                [
                  const SizedBox(height: 12),
                  Text.rich(
                      TextSpan(
                        text: "En continuant, vous acceptez nos ",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode ? Colors.white70 : Colors.white.withValues(alpha: 0.9),
                        ),
                        children: [
                          TextSpan(
                            text: "CGU",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LegalScreen(
                                    title: 'Conditions Générales',
                                    assetPath: 'assets/legal/cgu.md',
                                  ),
                                ),
                              ),
                          ),
                          TextSpan(
                            text: " et notre ",
                            style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.white.withValues(alpha: 0.9)),
                          ),
                          TextSpan(
                            text: "Politique de Confidentialité",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LegalScreen(
                                    title: 'Politique de Confidentialité',
                                    assetPath: 'assets/legal/politique_confidentialite.md',
                                  ),
                                ),
                              ),
                          ),
                          TextSpan(
                            text: ".",
                            style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.white.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    required bool isDarkMode,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      style: TextStyle(color: isDarkMode ? Colors.white : TranSenColors.primaryGreen),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey.shade600),
        prefixIcon: Icon(icon, color: TranSenColors.primaryGreen),
        filled: true,
        fillColor: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      ),
    );
  }
}
