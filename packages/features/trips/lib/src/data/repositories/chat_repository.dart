import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/foundation.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');

  Stream<List<ChatMessage>> watchMessages(String tripId, {String? passengerId}) {
    if (passengerId != null) {
      // Chat privé pour le pooling
      return _firestore
          .collection('pools')
          .doc(tripId)
          .collection('chats')
          .doc(passengerId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList());
    }

    // Comportement par défaut (Trips normaux ou anciens messages de pool)
    final tripsStream = _firestore.collection('trips').doc(tripId).collection('messages').orderBy('timestamp', descending: true).snapshots();
    final poolsStream = _firestore.collection('pools').doc(tripId).collection('messages').orderBy('timestamp', descending: true).snapshots();
    
    return Rx.combineLatest2(tripsStream, poolsStream, (tripsSnap, poolsSnap) {
      final allDocs = [...tripsSnap.docs, ...poolsSnap.docs];
      allDocs.sort((a, b) {
        final ta = (a.data()['timestamp'] as Timestamp?) ?? Timestamp.now();
        final tb = (b.data()['timestamp'] as Timestamp?) ?? Timestamp.now();
        return tb.compareTo(ta);
      });
      return allDocs.map((doc) => ChatMessage.fromFirestore(doc)).toList();
    });
  }

  Future<void> sendMessage(String tripId, String senderId, String text, {String? passengerId}) async {
    if (text.trim().isEmpty) return;
    
    if (passengerId != null) {
      // Envoi dans le chat privé du pool
      await _firestore
          .collection('pools')
          .doc(tripId)
          .collection('chats')
          .doc(passengerId)
          .collection('messages')
          .add({
        'senderId': senderId,
        'text': text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      try {
        await _firestore.collection('pools').doc(tripId).collection('chats').doc(passengerId).set({
          'lastMessage': text.trim(),
          'lastMessageAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("Erreur update lastMessage chat: $e");
      }
      return;
    }

    // Déterminer quelle collection utiliser pour les trips normaux
    final tripDoc = await _firestore.collection('trips').doc(tripId).get();
    final isTrip = tripDoc.exists;
    final collectionName = isTrip ? 'trips' : 'pools';

    await _firestore.collection(collectionName).doc(tripId).collection('messages').add({
      'senderId': senderId,
      'text': text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    try {
      await _firestore.collection(collectionName).doc(tripId).update({
        'lastMessage': text.trim(),
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Erreur update lastMessage: $e");
    }
  }
}

final chatRepositoryProvider = Provider((ref) => ChatRepository());

// Provider qui accepte une clé composite "tripId|passengerId" ou juste "tripId"
final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((ref, key) {
  final parts = key.split('|');
  final tripId = parts[0];
  final passengerId = parts.length > 1 ? parts[1] : null;
  return ref.watch(chatRepositoryProvider).watchMessages(tripId, passengerId: passengerId);
});
