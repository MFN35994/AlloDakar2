import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/notification_service.dart';

class AuthState {
  final String userId;
  final String role; // 'client', 'driver', or 'none'
  final bool isLoading;
  final bool codeSent;

  AuthState({
    required this.userId,
    required this.role,
    this.isLoading = false,
    this.codeSent = false,
  });

  AuthState copyWith(
      {String? userId, String? role, bool? isLoading, bool? codeSent}) {
    return AuthState(
      userId: userId ?? this.userId,
      role: role ?? this.role,
      isLoading: isLoading ?? this.isLoading,
      codeSent: codeSent ?? this.codeSent,
    );
  }

  Widget when({
    required Widget Function(AuthState auth) data,
    required Widget Function() loading,
    required Widget Function(Object error, StackTrace? stack) error,
  }) {
    if (isLoading) return loading();
    return data(this);
  }
}

class AuthNotifier extends StateNotifier<AuthState?> {
  final AuthRepository _repository;
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');

  AuthNotifier(this._repository) : super(null) {
    _init();
  }

  void _init() {
    _repository.authStateChanges.listen((user) async {
      if (user == null) {
        state = null;
      } else {
        state = AuthState(userId: user.uid, role: 'none', isLoading: true);
        await _fetchUserRole(user.uid);
      }
    });
  }

  Future<void> _fetchUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final role = doc.data()!['role'] ?? 'none';
        state = state?.copyWith(role: role, isLoading: false);
        NotificationService().init(uid);
      } else {
        state = state?.copyWith(role: 'none', isLoading: false);
      }
    } catch (e) {
      state = state?.copyWith(role: 'none', isLoading: false);
    }
  }

  Future<void> setUserRole(String role) async {
    if (state == null) return;
    try {
      await _firestore.collection('users').doc(state!.userId).set({
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      state = state?.copyWith(role: role);
      NotificationService().init(state!.userId);
    } catch (e) {
      debugPrint("Erreur saving role: $e");
    }
  }

  Future<void> updateUserData({
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
  }) async {
    if (state == null) return;
    try {
      final name = (firstName != null && lastName != null)
          ? "$firstName $lastName"
          : null;
      await _firestore.collection('users').doc(state!.userId).set({
        if (name != null) 'name': name,
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Erreur saving user data: $e");
    }
  }

// Variable pour stocker l'ID de vérification du SMS en mémoire
  String? _verificationId;

  // 1. Déclencher l'envoi du SMS
  Future<void> sendPhoneVerificationCode(String phoneNumber) async {
    state = state?.copyWith(isLoading: true) ??
        AuthState(userId: '', role: 'none', isLoading: true);

    await _repository.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        state = state?.copyWith(isLoading: false);
        throw Exception(e.message);
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        // On active codeSent pour basculer l'UI vers le champ OTP
        state = state?.copyWith(isLoading: false, codeSent: true);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  // 2. Valider le code OTP tapé par l'utilisateur
  Future<void> verifySmsCode(String smsCode) async {
    if (_verificationId == null) {
      throw Exception("Demandez d'abord un code SMS.");
    }

    state = state?.copyWith(isLoading: true);
    try {
      await _repository.signInWithSmsCode(_verificationId!, smsCode);
    } catch (e) {
      state = state?.copyWith(isLoading: false);
      throw Exception("Code incorrect.");
    }
  }

  Future<void> signInAsAnonymousClient() async {
    try {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      final uid = credential.user!.uid;

      await _firestore.collection('users').doc(uid).set({
        'role': 'client',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      state = AuthState(userId: uid, role: 'client', isLoading: false);
    } catch (e) {
      debugPrint("Erreur signInAsAnonymousClient: $e");
    }
  }

  Future<void> signUpDriver(
      {required String firstName,
      required String lastName,
      required String phone}) async {
    try {
      // Utiliser l'utilisateur DÉJÀ connecté (email/phone depuis LoginScreen)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception("Utilisateur non connecté");

      final uid = currentUser.uid;
      final name = "$firstName $lastName";

      await _firestore.collection('users').doc(uid).set({
        'role': 'driver',
        'name': name,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'email': currentUser.email ?? currentUser.phoneNumber ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      state = AuthState(userId: uid, role: 'driver', isLoading: false);
    } catch (e) {
      debugPrint("Erreur signUpDriver: $e");
      rethrow;
    }
  }

  Future<void> logout() async {
    await _repository.signOut();
  }

  Future<void> deleteAccount() async {
    if (state == null) return;
    final uid = state!.userId;
    try {
      // 1. Supprimer le document Firestore
      await _firestore.collection('users').doc(uid).delete();

      // 2. Supprimer l'utilisateur Firebase Auth
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.delete();
      }

      state = null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception(
            "Cette opération nécessite une connexion récente. Veuillez vous déconnecter et vous reconnecter avant de supprimer votre compte.");
      }
      rethrow;
    } catch (e) {
      debugPrint("Erreur suppression compte: $e");
      rethrow;
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthNotifier(repository);
});
