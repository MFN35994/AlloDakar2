import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Fonction globale pour gérer les messages en arrière-plan
// Doit être en dehors de toute classe
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Canal pour les notifications Android (important pour les bannières)
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description: 'This channel is used for important notifications.', // description
    importance: Importance.max,
  );

  final Map<String, StreamSubscription> _chatSubscriptions = {};

  Future<void> init(String userId) async {
    // 1. Demander la permission
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
      
      // 2. Initialiser les notifications locales pour le premier plan
      await _initLocalNotifications();

      // 3. Récupérer et sauvegarder le token
      String? token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToDatabase(userId, token);
      }

      // 4. Écouter les changements de token
      _fcm.onTokenRefresh.listen((newToken) {
        _saveTokenToDatabase(userId, newToken);
      });

      // 5. Démarrer l'écouteur de messages de chat internes
      startChatListener(userId);
    }
  }

  void startChatListener(String userId) {
    final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');
    
    // Écouter les trajets actifs (trips)
    db.collection('trips')
      .where(Filter.or(
        Filter('clientId', isEqualTo: userId),
        Filter('driverId', isEqualTo: userId),
      ))
      .snapshots()
      .listen((snapshot) {
        _manageChatSubscriptions(userId, snapshot.docs, 'trips');
      });

    // Écouter les covoiturages actifs (pools)
    db.collection('pools')
      .where(Filter.or(
        Filter('passengerIds', arrayContains: userId),
        Filter('driverId', isEqualTo: userId),
      ))
      .snapshots()
      .listen((snapshot) {
        _manageChatSubscriptions(userId, snapshot.docs, 'pools');
      });
  }

  void _manageChatSubscriptions(String userId, List<QueryDocumentSnapshot> docs, String collectionName) {
    final activeIds = docs.map((d) => d.id).toSet();
    
    // Supprimer les écouteurs pour les trajets qui ne sont plus actifs ou plus là
    _chatSubscriptions.removeWhere((id, sub) {
      if (!activeIds.contains(id) && id.startsWith(collectionName)) {
        sub.cancel();
        return true;
      }
      return false;
    });

    // Ajouter des écouteurs pour les nouveaux trajets
    for (var doc in docs) {
      final tripId = doc.id;
      final key = "${collectionName}_$tripId";
      if (!_chatSubscriptions.containsKey(key)) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        
        // On n'écoute que si le trajet est "actif"
        if (status == 'completed' || status == 'cancelled') continue;

        _chatSubscriptions[key] = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
          .collection(collectionName)
          .doc(tripId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((msgSnapshot) {
            if (msgSnapshot.docs.isNotEmpty) {
              final msgData = msgSnapshot.docs.first.data();
              final senderId = msgData['senderId'] as String?;
              final timestamp = msgData['timestamp'] as Timestamp?;
              
              // On ne notifie que si :
              // 1. Le message n'est pas de nous
              // 2. Le message est récent (moins de 30 secondes pour éviter les notifs au démarrage)
              if (senderId != userId && timestamp != null) {
                final diff = DateTime.now().difference(timestamp.toDate()).inSeconds;
                if (diff.abs() < 30) {
                  _showLocalNotification(
                    "Nouveau message",
                    msgData['text'] ?? "Vous avez reçu un message",
                    payload: tripId,
                  );
                }
              }
            }
          });
      }
    }
  }

  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint("Notification clicked: ${details.payload}");
      },
    );

    // Créer le canal sur Android
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  Future<void> _saveTokenToDatabase(String userId, String token) async {
    try {
      await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('users').doc(userId).set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.toString().split('.').last,
      }, SetOptions(merge: true));
      debugPrint('FCM Token saved for user: $userId');
    } catch (e) {
      debugPrint('Error saving FCM Token: $e');
    }
  }

  Future<void> _showLocalNotification(String title, String body, {String? payload}) async {
    const androidDetails = AndroidNotificationDetails(
      'internal_messages',
      'Messages Internes',
      channelDescription: 'Notifications pour les messages du chat',
      importance: Importance.max,
      priority: Priority.high,
    );
    
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }

  // Écouter les messages quand l'app est au premier plan
  static void listenToMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      // Si c'est une notification Android et qu'on a les infos, on l'affiche localement
      if (notification != null && android != null && !kIsWeb) {
        FlutterLocalNotificationsPlugin().show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: android.smallIcon,
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      }
      
      debugPrint('Message reçu au premier plan: ${notification?.title}');
    });

    // Gérer le clic sur une notification quand l'app est ouverte
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification cliquée! Message ID: ${message.messageId}');
      // Ici vous pouvez naviguer vers un écran spécifique
    });
  }
}
