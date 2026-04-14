import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Fonction globale pour gérer les messages en arrière-plan
// Doit être en dehors de toute classe
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
  // Note: Si vous avez besoin de Firebase, vous devez l'initialiser ici
  // await Firebase.initializeApp();
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

    await _localNotifications.initialize(initializationSettings);

    // Créer le canal sur Android
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  Future<void> _saveTokenToDatabase(String userId, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.toString().split('.').last,
      }, SetOptions(merge: true));
      debugPrint('FCM Token saved for user: $userId');
    } catch (e) {
      debugPrint('Error saving FCM Token: $e');
    }
  }

  // Écouter les messages quand l'app est au premier plan
  static void listenToMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      // Si c'est une notification Android et qu'on a les infos, on l'affiche localement
      if (notification != null && android != null && !kIsWeb) {
        FlutterLocalNotificationsPlugin().show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
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
