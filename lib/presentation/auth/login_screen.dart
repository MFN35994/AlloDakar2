import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/auth_provider.dart';
import '../../domain/providers/referral_provider.dart';
import '../../core/theme/transen_colors.dart';
import '../legal/legal_screen.dart';
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
    if (phone.isEmpty) {
      HapticFeedback.heavyImpact();
      _showError("Veuillez entrer un numéro de téléphone");
      return;
    }

    if (!phone.startsWith('+')) {
      phone = '+221$phone';
    }

    setState(() => _localLoading = true);

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
      HapticFeedback.heavyImpact();
      _showError("Veuillez entrer votre prénom et votre nom");
      return;
    }

    setState(() => _localLoading = true);
    try {
      String phone = _phoneController.text.trim().replaceAll(' ', '');
      if (!phone.startsWith('+')) phone = '+221$phone';

      await ref.read(authProvider.notifier).updateUserData(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: phone,
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
    } finally {
      setState(() => _localLoading = false);
    }
  }

  Future<void> _signInWithOtp() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      HapticFeedback.heavyImpact();
      _showError("Le code doit comporter 6 chiffres");
      return;
    }

    try {
      HapticFeedback.lightImpact();
      await ref.read(authProvider.notifier).verifySmsCode(code);
    } catch (e) {
      HapticFeedback.heavyImpact();
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
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.white,
      body: SingleChildScrollView(
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
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 70, bottom: 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [TranSenColors.primaryGreen, TranSenColors.darkGreen],
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
          Image.asset('assets/images/logo.png',
              height: 100,
              errorBuilder: (c, e, s) => const Icon(Icons.directions_car,
                  size: 80, color: Colors.white)),
          const SizedBox(height: 15),
          const Text("Bienvenue sur TranSen",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const Text("LE TRANSPORT 5 ÉTOILES AU SÉNÉGAL",
              style: TextStyle(
                  color: Colors.white70,
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
              if (step == AuthStep.phone)
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
              if (step == AuthStep.identity) ...[
                const SizedBox(height: 10),
                _buildTextField(
                    controller: _referralController,
                    label: "Code parrainage (optionnel)",
                    icon: Icons.card_giftcard,
                    isDarkMode: isDarkMode,
                    textCapitalization: TextCapitalization.characters),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    const Text(
                      "En vous inscrivant, vous acceptez nos ",
                      style: TextStyle(fontSize: 11),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LegalScreen(
                            title: 'Conditions Générales',
                            assetPath: 'assets/legal/cgu.md',
                          ),
                        ),
                      ),
                      child: const Text(
                        "CGU",
                        style: TextStyle(
                          fontSize: 11,
                          color: TranSenColors.primaryGreen,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                          decorationColor: TranSenColors.primaryGreen,
                        ),
                      ),
                    ),
                    const Text(" et notre ", style: TextStyle(fontSize: 11)),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LegalScreen(
                            title: 'Politique de Confidentialité',
                            assetPath: 'assets/legal/politique_confidentialite.md',
                          ),
                        ),
                      ),
                      child: const Text(
                        "Politique de Confidentialité",
                        style: TextStyle(
                          fontSize: 11,
                          color: TranSenColors.primaryGreen,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                          decorationColor: TranSenColors.primaryGreen,
                        ),
                      ),
                    ),
                    const Text(".", style: TextStyle(fontSize: 11)),
                  ],
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
                    onPressed: step == AuthStep.phone 
                        ? _sendOtp 
                        : (step == AuthStep.identity ? _saveIdentity : _signInWithOtp),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDarkMode ? Colors.white : Colors.black87,
                      foregroundColor: isDarkMode ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
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
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      Text(
                        'En vous connectant, vous acceptez nos ',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LegalScreen(
                              title: 'Conditions Générales',
                              assetPath: 'assets/legal/cgu.md',
                            ),
                          ),
                        ),
                        child: const Text(
                          'CGU',
                          style: TextStyle(
                            fontSize: 11,
                            color: TranSenColors.primaryGreen,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: TranSenColors.primaryGreen,
                          ),
                        ),
                      ),
                      Text(' et notre ', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LegalScreen(
                              title: 'Politique de Confidentialité',
                              assetPath: 'assets/legal/politique_confidentialite.md',
                            ),
                          ),
                        ),
                        child: const Text(
                          'Politique de Confidentialité',
                          style: TextStyle(
                            fontSize: 11,
                            color: TranSenColors.primaryGreen,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: TranSenColors.primaryGreen,
                          ),
                        ),
                      ),
                      Text('.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
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
      style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade600),
        prefixIcon: Icon(icon, color: TranSenColors.primaryGreen),
        filled: true,
        fillColor: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade100,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      ),
    );
  }
}
