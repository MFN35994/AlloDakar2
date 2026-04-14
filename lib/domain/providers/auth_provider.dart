import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/notification_service.dart';

class AuthState {
  final String userId;
  final String role; // 'client', 'driver', or 'none'
  final bool isLoading;

  AuthState({
    required this.userId,
    required this.role,
    this.isLoading = false,
  });

  AuthState copyWith({String? userId, String? role, bool? isLoading}) {
    return AuthState(
      userId: userId ?? this.userId,
      role: role ?? this.role,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState?> {
  final AuthRepository _repository;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
        // Initialiser les notifications
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
      // Ré-initialiser les notifications avec le rôle à jour si besoin
      NotificationService().init(state!.userId);
    } catch (e) {
      debugPrint("Erreur saving role: $e");
    }
  }

  Future<void> updateUserData({String? firstName, String? lastName, String? phone, String? email}) async {
    if (state == null) return;
    try {
      final name = (firstName != null && lastName != null) ? "$firstName $lastName" : null;
      await _firestore.collection('users').doc(state!.userId).set({
        if (name != null) 'name': name,
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Erreur saving user data: $e");
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

  Future<void> signUpDriver({required String firstName, required String lastName, required String phone}) async {
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
        throw Exception("Cette opération nécessite une connexion récente. Veuillez vous déconnecter et vous reconnecter avant de supprimer votre compte.");
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

