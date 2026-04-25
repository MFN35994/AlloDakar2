import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/auth_provider.dart';
import '../../domain/providers/referral_provider.dart';
import '../../core/theme/transen_colors.dart';
import '../legal/legal_screen.dart';
import 'package:flutter/services.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

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

  bool _otpSent = false;
  bool _isLogin = true;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  // LOGIQUE SMS (Connectée au Provider)
  Future<void> _verifyPhone() async {
    if (!_isLogin) {
      if (_firstNameController.text.isEmpty || _lastNameController.text.isEmpty) {
        HapticFeedback.heavyImpact();
        _showError("Veuillez entrer votre prénom et votre nom");
        return;
      }
    }

    String phone = _phoneController.text.trim().replaceAll(' ', '');
    if (phone.isEmpty) {
      HapticFeedback.heavyImpact();
      _showError("Veuillez entrer un numéro de téléphone");
      return;
    }

    // Ajout automatique de l'indicatif +221 si l'utilisateur l'omet
    if (!phone.startsWith('+')) {
      phone = '+221$phone';
    }

    try {
      HapticFeedback.lightImpact();
      await ref.read(authProvider.notifier).sendPhoneVerificationCode(phone);
      setState(() => _otpSent = true);
    } catch (e) {
      HapticFeedback.heavyImpact();
      _showError("Erreur d'envoi : ${e.toString()}");
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
      
      if (!_isLogin) {
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
      }
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
    final isLoading = authState?.isLoading ?? false;

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
              height: _otpSent ? 200 : (_isLogin ? 200 : 450),
              child: _buildPhoneForm(isDarkMode, isLoading),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLogin = !_isLogin;
                  _otpSent = false;
                });
              },
              child: Text(
                _isLogin
                    ? "Pas de compte ? Inscrivez-vous"
                    : "Déjà inscrit ? Connectez-vous",
                style: const TextStyle(
                    color: TranSenColors.primaryGreen,
                    fontWeight: FontWeight.bold),
              ),
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

  Widget _buildPhoneForm(bool isDarkMode, bool isLoading) {
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
            key: ValueKey<String>('$_otpSent-$_isLogin'),
            children: [
              if (!_isLogin && !_otpSent) ...[
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
              if (!_otpSent)
                _buildTextField(
                    controller: _phoneController,
                    label: "Numéro (ex: 77 123 45 67)",
                    icon: Icons.phone_android,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [_phoneMaskFormatter],
                    isDarkMode: isDarkMode)
              else
                _buildTextField(
                    controller: _otpController,
                    label: "Code OTP",
                    icon: Icons.vibration,
                    keyboardType: TextInputType.number,
                    isDarkMode: isDarkMode),
              if (!_isLogin && !_otpSent) ...[
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
              if (_otpSent)
                TextButton(
                    onPressed: () => setState(() => _otpSent = false),
                    child: const Text("Changer de numéro",
                        style: TextStyle(color: Colors.grey, fontSize: 12))),
              const SizedBox(height: 15),
              if (isLoading)
                const CircularProgressIndicator(color: TranSenColors.primaryGreen)
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _otpSent ? _signInWithOtp : _verifyPhone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDarkMode ? Colors.white : Colors.black87,
                      foregroundColor: isDarkMode ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    child: Text(_otpSent ? "VÉRIFIER LE CODE" : "RECEVOIR LE CODE",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              // Mention légale pour la CONNEXION
              if (_isLogin && !_otpSent) ...
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
