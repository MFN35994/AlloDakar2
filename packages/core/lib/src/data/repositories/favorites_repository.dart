import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FavoriteAddress {
  final String id;
  final String label; // Home, Work, etc.
  final String address;
  final IconData icon;

  FavoriteAddress({required this.id, required this.label, required this.address, required this.icon});

  factory FavoriteAddress.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FavoriteAddress(
      id: doc.id,
      label: data['label'] ?? '',
      address: data['address'] ?? '',
      icon: _getIconData(data['iconName']),
    );
  }

  static IconData _getIconData(String? name) {
    switch (name) {
      case 'home': return Icons.home;
      case 'work': return Icons.work;
      case 'school': return Icons.school;
      case 'favorite': return Icons.favorite;
      default: return Icons.location_on;
    }
  }
}

class FavoriteDriver {
  final String id;
  final String driverId;
  final String name;
  final String phone;

  FavoriteDriver({required this.id, required this.driverId, required this.name, required this.phone});

  factory FavoriteDriver.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FavoriteDriver(
      id: doc.id,
      driverId: data['driverId'] ?? '',
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
    );
  }
}

class FavoritesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');

  Stream<List<FavoriteAddress>> watchFavoriteAddresses(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('favorite_addresses')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => FavoriteAddress.fromFirestore(doc)).toList());
  }

  Future<void> addFavoriteAddress(String userId, String label, String address, String iconName) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('favorite_addresses')
        .add({
      'label': label,
      'address': address,
      'iconName': iconName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<FavoriteDriver>> watchFavoriteDrivers(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('favorite_drivers')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => FavoriteDriver.fromFirestore(doc)).toList());
  }

  Future<void> addFavoriteDriver(String userId, String driverId, String name, String phone) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('favorite_drivers')
        .doc(driverId)
        .set({
      'driverId': driverId,
      'name': name,
      'phone': phone,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeFavoriteAddress(String userId, String id) async {
    await _firestore.collection('users').doc(userId).collection('favorite_addresses').doc(id).delete();
  }

  Future<void> removeFavoriteDriver(String userId, String driverId) async {
    await _firestore.collection('users').doc(userId).collection('favorite_drivers').doc(driverId).delete();
  }
}

final favoritesRepositoryProvider = Provider((ref) => FavoritesRepository());

final favoriteAddressesProvider = StreamProvider.family<List<FavoriteAddress>, String>((ref, userId) {
  return ref.watch(favoritesRepositoryProvider).watchFavoriteAddresses(userId);
});

final favoriteDriversProvider = StreamProvider.family<List<FavoriteDriver>, String>((ref, userId) {
  return ref.watch(favoritesRepositoryProvider).watchFavoriteDrivers(userId);
});
