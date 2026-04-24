import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/providers/auth_provider.dart';
import '../../domain/providers/referral_provider.dart';
import '../../core/theme/transen_colors.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _referralController = TextEditingController();

  bool _otpSent = false;
  bool _isLogin = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  // --- LOGIQUE D'AUTHENTIFICATION ---

  Future<void> _handleAuth() async {
    if (_isLogin) {
      await _signInWithEmail();
    } else {
      await _signUpWithEmail();
    }
  }

  Future<void> _signInWithEmail() async {
    try {
      await ref.read(authRepositoryProvider).signInWithEmail(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );
    } catch (e) {
      _showError("Erreur de connexion : Vérifiez vos identifiants");
    }
  }

  Future<void> _signUpWithEmail() async {
    if (_firstNameController.text.isEmpty || _lastNameController.text.isEmpty) {
      _showError("Veuillez remplir votre nom et prénom");
      return;
    }
    try {
      await ref.read(authRepositoryProvider).signUpWithEmail(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );

      await ref.read(authProvider.notifier).updateUserData(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
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
    } catch (e) {
      _showError("Erreur d'inscription : ${e.toString()}");
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      _showError("Connexion Google annulée ou échouée");
    }
  }

  // LOGIQUE SMS (Connectée au Provider)
  Future<void> _verifyPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      _showError(
          "Format invalide. Utilisez le format international (ex: +221...)");
      return;
    }

    try {
      await ref.read(authProvider.notifier).sendPhoneVerificationCode(phone);
      setState(() => _otpSent = true);
    } catch (e) {
      _showError("Erreur d'envoi : ${e.toString()}");
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
    final isLoading = authState?.isLoading ?? false;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(isDarkMode),
            const SizedBox(height: 10),
            _buildTabs(isDarkMode),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _otpSent
                  ? 220
                  : (_tabController.index == 0 ? (_isLogin ? 250 : 470) : 160),
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildEmailForm(isDarkMode, isLoading),
                  _buildPhoneForm(isDarkMode, isLoading),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text("OU", style: TextStyle(color: Colors.grey))),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            _buildGoogleButton(isDarkMode),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
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

  // --- RESTAURATION DE TES WIDGETS ORIGINAUX ---

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

  Widget _buildTabs(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 30),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white10 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(30),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: TranSenColors.primaryGreen),
        onTap: (index) => setState(() {}),
        tabs: const [Tab(text: "E-mail"), Tab(text: "Téléphone")],
      ),
    );
  }

  Widget _buildEmailForm(bool isDarkMode, bool isLoading) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          if (!_isLogin) ...[
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
          _buildTextField(
              controller: _emailController,
              label: "Email",
              icon: Icons.email_outlined,
              isDarkMode: isDarkMode),
          const SizedBox(height: 10),
          if (!_isLogin) ...[
            _buildTextField(
                controller: _phoneController,
                label: "Téléphone",
                icon: Icons.phone_android_outlined,
                keyboardType: TextInputType.phone,
                isDarkMode: isDarkMode),
            const SizedBox(height: 10),
          ],
          _buildTextField(
              controller: _passwordController,
              label: "Mot de passe",
              icon: Icons.lock_outline,
              isPassword: true,
              isDarkMode: isDarkMode),
          if (!_isLogin) ...[
            const SizedBox(height: 10),
            _buildTextField(
              controller: _referralController,
              label: "Code parrainage (optionnel)",
              icon: Icons.card_giftcard,
              isDarkMode: isDarkMode,
              textCapitalization: TextCapitalization.characters,
            ),
          ],
          const SizedBox(height: 25),
          if (isLoading)
            const CircularProgressIndicator(color: TranSenColors.primaryGreen)
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleAuth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TranSenColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  elevation: 5,
                ),
                child: Text(_isLogin ? "SE CONNECTER" : "S'INSCRIRE",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhoneForm(bool isDarkMode, bool isLoading) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          if (!_otpSent)
            _buildTextField(
                controller: _phoneController,
                label: "Numéro (ex: +221...)",
                icon: Icons.phone_android,
                keyboardType: TextInputType.phone,
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
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    required bool isDarkMode,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
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

  Widget _buildGoogleButton(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: OutlinedButton(
        onPressed: _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          side: BorderSide(
              color: isDarkMode ? Colors.white24 : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network(
                "https://img.icons8.com/color/48/000000/google-logo.png",
                height: 24),
            const SizedBox(width: 12),
            Text("Continuer avec Google",
                style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
