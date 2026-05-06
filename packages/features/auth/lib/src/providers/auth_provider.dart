import "package:flutter/foundation.dart";
import "package:firebase_core/firebase_core.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:transen_core/transen_core.dart';
import '../data/repositories/auth_repository.dart';

class AuthState {
  final String userId;
  final String role; // 'client', 'driver', or 'none'
  final bool isLoading;
  final bool codeSent;
  final String? name;
  final String? phone;

  AuthState({
    required this.userId,
    required this.role,
    this.isLoading = false,
    this.codeSent = false,
    this.name,
    this.phone,
  });

  AuthState copyWith({
    String? userId,
    String? role,
    bool? isLoading,
    bool? codeSent,
    String? name,
    String? phone,
  }) {
    return AuthState(
      userId: userId ?? this.userId,
      role: role ?? this.role,
      isLoading: isLoading ?? this.isLoading,
      codeSent: codeSent ?? this.codeSent,
      name: name ?? this.name,
      phone: phone ?? this.phone,
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

class AuthNotifier extends Notifier<AuthState?> {
  late final AuthRepository _repository;
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');

  @override
  AuthState? build() {
    _repository = ref.watch(authRepositoryProvider);
    
    // Écouter les changements d'état d'authentification
    _repository.authStateChanges.listen((user) async {
      if (user == null) {
        state = null;
      } else {
        state = AuthState(userId: user.uid, role: 'none', isLoading: true);
        await _fetchUserRole(user.uid);
      }
    });
    return null;
  }

  Future<void> _fetchUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final role = data['role'] ?? 'none';
        final name = data['name'] ?? data['firstName'];
        final phone = data['phone'];
        state = state?.copyWith(role: role, name: name, phone: phone, isLoading: false);
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
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      state = state?.copyWith(role: role, isLoading: false);
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
    try {
      final name = (firstName != null && lastName != null)
          ? "$firstName $lastName"
          : null;
      
      final updates = <String, dynamic>{
        'lastActive': FieldValue.serverTimestamp(),
      };
      if (name != null) updates['name'] = name;
      if (firstName != null) updates['firstName'] = firstName;
      if (lastName != null) updates['lastName'] = lastName;
      if (phone != null) updates['phone'] = phone.replaceAll(' ', '');
      if (email != null) updates['email'] = email;

      await _firestore.collection('users').doc(state!.userId).update(updates);
      
      // Mise à jour immédiate du state
      state = state?.copyWith(
        name: name ?? state!.name,
        phone: phone ?? state!.phone,
        isLoading: false,
      );
    } catch (e) {
      debugPrint("Erreur saving user data: $e");
    }
  }

  String? _verificationId;
  ConfirmationResult? _webConfirmationResult;

  Future<void> sendPhoneVerificationCode(String phoneNumber) async {
    state = state?.copyWith(isLoading: true) ??
        AuthState(userId: '', role: 'none', isLoading: true);
    
    if (kIsWeb) {
      try {
        _webConfirmationResult = await FirebaseAuth.instance.signInWithPhoneNumber(phoneNumber);
        state = state?.copyWith(isLoading: false, codeSent: true);
      } catch (e) {
        state = state?.copyWith(isLoading: false);
        throw Exception(e.toString());
      }
      return;
    }

    final completer = Completer<void>();
    await _repository.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
        if (!completer.isCompleted) completer.complete();
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) completer.completeError(Exception(e.message));
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        state = state?.copyWith(isLoading: false, codeSent: true);
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
    return completer.future;
  }

  Future<void> verifySmsCode(String smsCode) async {
    state = state?.copyWith(isLoading: true);
    try {
      if (kIsWeb) {
        if (_webConfirmationResult == null) {
          throw Exception("Demandez d'abord un code SMS.");
        }
        await _webConfirmationResult!.confirm(smsCode);
      } else {
        if (_verificationId == null) {
          throw Exception("Demandez d'abord un code SMS.");
        }
        await _repository.signInWithSmsCode(_verificationId!, smsCode);
      }
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
      });
      state = AuthState(userId: uid, role: 'client', isLoading: false);
    } catch (e) {
      debugPrint("Erreur signInAsAnonymousClient: $e");
    }
  }

  Future<void> signUpDriver({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception("Utilisateur non connecté");
      final uid = currentUser.uid;
      final name = "$firstName $lastName";
      
      await _firestore.collection('users').doc(uid).set({
        'role': 'driver',
        'name': name,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone.replaceAll(' ', ''),
        'email': currentUser.email ?? currentUser.phoneNumber ?? '',
      }, SetOptions(merge: true));

      state = AuthState(userId: uid, role: 'driver', isLoading: false);
    } catch (e) {
      debugPrint("Erreur signUpDriver: $e");
      rethrow;
    }
  }

  Future<void> logout() async {
    await _repository.signOut();
    state = null;
  }

  Future<void> deleteAccount() async {
    if (state == null) return;
    final uid = state!.userId;
    try {
      if (state?.role == 'driver') {
        await _firestore.collection('active_drivers').doc(uid).delete();
        await _firestore.collection('driver_routes').doc(uid).delete();
      }
      await _firestore.collection('users').doc(uid).delete();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.delete();
      }
      state = null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception("Opération nécessite une connexion récente.");
      }
      debugPrint("Erreur suppression compte: $e");
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState?>(AuthNotifier.new);
