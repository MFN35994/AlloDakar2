import "package:flutter/foundation.dart";
import "package:firebase_core/firebase_core.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RatingRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');

  Future<void> submitRating({
    required String tripId, 
    required String driverId,
    required String userId,
    required String userName,
    required int rating, 
    required String comment
  }) async {
    try {
      // 1. Enregistrer l'avis dans une collection globale
      await _firestore.collection('reviews').add({
        'tripId': tripId,
        'driverId': driverId,
        'userId': userId,
        'userName': userName,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Marquer comme noté pour CET utilisateur
      final userReviewRef = _firestore.collection('users').doc(userId).collection('my_reviews').doc(tripId);
      await userReviewRef.set({
        'rated': true,
        'date': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Erreur submitRating: $e");
      rethrow;
    }
  }

  Stream<bool> hasUserRated(String userId, String tripId) {
    return _firestore.collection('users').doc(userId).collection('my_reviews').doc(tripId).snapshots().map((doc) => doc.exists);
  }

  Stream<double> watchDriverRating(String driverId) {
    return _firestore.collection('reviews')
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return 0.0;
          double total = 0;
          for (var doc in snapshot.docs) {
            total += (doc.data()['rating'] as int).toDouble();
          }
          return total / snapshot.docs.length;
        });
  }

  Stream<int> watchDriverRatingCount(String driverId) {
    return _firestore.collection('reviews')
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<List<Map<String, dynamic>>> watchDriverReviews(String driverId) {
    return _firestore.collection('reviews')
        .where('driverId', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }
}

final ratingRepositoryProvider = Provider<RatingRepository>((ref) {
  return RatingRepository();
});

final driverRatingProvider = StreamProvider.family<double, String>((ref, driverId) {
  return ref.watch(ratingRepositoryProvider).watchDriverRating(driverId);
});

final driverRatingCountProvider = StreamProvider.family<int, String>((ref, driverId) {
  return ref.watch(ratingRepositoryProvider).watchDriverRatingCount(driverId);
});

final driverReviewsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, driverId) {
  return ref.watch(ratingRepositoryProvider).watchDriverReviews(driverId);
});
