import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // 🚨 1. THE HIGH-PRIORITY CHANNEL
  final AndroidNotificationChannel _androidChannel =
      const AndroidNotificationChannel(
        'trideta_high_importance',
        'High Importance Notifications',
        description: 'Used for important school alerts and RBAC triggers.',
        importance: Importance.max,
        playSound: true,
      );

  Future<void> initialize() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('✅ OS Push Permission Granted');

      // 🚨 2. THE LOGIN TRIPWIRE (RBAC Foundation)
      Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          debugPrint(
            "✅ User signed in! Locking FCM token to their RBAC profile...",
          );
          await _forceSaveToken();
        }
      });

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_androidChannel);

      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings = InitializationSettings(
        android: androidInit,
      );

      await _localNotifications.initialize(settings: initSettings);

      // 🚨 4. THE FOREGROUND DROP-DOWN INTERCEPTOR
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          "🚨 IN-APP NOTIFICATION CAUGHT: ${message.notification?.title}",
        );
        _showLocalNotification(message);
      });

      await _forceSaveToken();

      _fcm.onTokenRefresh.listen((newToken) {
        _updateTokenInSupabase(newToken);
      });
    }
  }

  Future<void> _forceSaveToken() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      String? token = await _fcm.getToken();
      if (token != null) {
        await _updateTokenInSupabase(token);
      }
    } catch (e) {
      debugPrint("❌ Error fetching FCM token: $e");
    }
  }

  Future<void> _updateTokenInSupabase(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('fcm_tokens')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null) {
        List<String> tokens = List<String>.from(profile['fcm_tokens'] ?? []);

        if (!tokens.contains(token)) {
          tokens.add(token);
          await Supabase.instance.client
              .from('profiles')
              .update({'fcm_tokens': tokens})
              .eq('id', userId);

          debugPrint("✅ Token successfully locked into Supabase Profile!");
        } else {
          // ✨ THE MISSING PRINT: This proves it's already safely in the database!
          debugPrint(
            "✅ Token is already safely locked in the database. (No update needed)",
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error saving push token to database: $e");
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  }
}
