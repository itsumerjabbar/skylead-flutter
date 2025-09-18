import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skylead_app/services/api_service.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Function(Map<String, dynamic>)? _onNotificationReceived;

  Future<void> initialize({
    required Function(Map<String, dynamic>) onNotificationReceived,
  }) async {
    _onNotificationReceived = onNotificationReceived;

    // Initialize local notifications
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    // Request permissions
    await _requestPermissions();

    // Set up message handlers
    await _setupMessageHandlers();

    // FCM Service initialized successfully
  }

  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel defaultChannel =
        AndroidNotificationChannel(
          'default_channel',
          'Default Notifications',
          description: 'Default notification channel',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );

    const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
      'call_channel',
      'Call Notifications',
      description: 'Call notification channel',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(defaultChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(callChannel);
  }

  Future<void> _requestPermissions() async {
    // Request FCM permissions
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Request local notification permissions for iOS
    if (Platform.isIOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> _setupMessageHandlers() async {
    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle messages when app is in background but opened
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // Handle messages when app is terminated
    FirebaseMessaging.instance.getInitialMessage().then(
      _handleTerminatedMessage,
    );

    // Handle token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen(_handleTokenRefresh);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // FCM Message received in foreground

    // Show local notification
    if (Platform.isAndroid) {
      _showLocalNotification(
        title:
            message.notification?.title ??
            message.data['title'] ??
            'New Message',
        body:
            message.notification?.body ??
            message.data['body'] ??
            'You have a new notification',
        data: message.data,
      );
    }

    // Call the notification handler
    if (_onNotificationReceived != null && message.data.isNotEmpty) {
      _onNotificationReceived!(message.data);
    }
  }

  void _handleBackgroundMessage(RemoteMessage message) {
    // FCM Message opened from background

    if (_onNotificationReceived != null && message.data.isNotEmpty) {
      _onNotificationReceived!(message.data);
    }
  }

  void _handleTerminatedMessage(RemoteMessage? message) {
    // FCM Message opened from terminated state

    if (message != null &&
        _onNotificationReceived != null &&
        message.data.isNotEmpty) {
      _onNotificationReceived!(message.data);
    }
  }

  void _handleTokenRefresh(String token) async {
    // FCM Token refreshed

    // Store the new token
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);

    // Send to backend if user is logged in
    final userToken = prefs.getString('userToken');
    final userDataString = prefs.getString('userData');
    log("User token is $userToken");
    if (userToken != null && userDataString != null) {
      try {
        final userData = jsonDecode(userDataString);
        await _sendTokenToBackend(token, userToken, userData['id']?.toString());
      } catch (e) {
        // Error sending refreshed token to backend
      }
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Notification tapped

    if (response.payload != null && _onNotificationReceived != null) {
      try {
        final data = jsonDecode(response.payload!);
        _onNotificationReceived!(data);
      } catch (e) {
        // Error parsing notification payload
      }
    }
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'default_channel',
          'Default Notifications',
          channelDescription: 'Default notification channel',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
      title,
      body,
      details,
      payload: jsonEncode(data),
    );
  }

  Future<String?> getFCMToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      log("Token is ${token}");
      // FCM Token retrieved

      // Store token locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token ?? '');

      return token;
    } catch (e) {
      log("Error is $e");
      // Error getting FCM token
      return null;
    }
  }

  Future<void> registerForPushNotifications() async {
    try {
      final token = await getFCMToken();
      log("FCM Token is ${token}");
      if (token == null) {
        // Failed to get FCM token
        return;
      }

      // Get user data for backend registration
      final prefs = await SharedPreferences.getInstance();
      final userToken = prefs.getString('userToken');
      final userDataString = prefs.getString('userData');

      if (userToken != null && userDataString != null) {
        final userData = jsonDecode(userDataString);
        await _sendTokenToBackend(token, userToken, userData['id']?.toString());
        // FCM token registered with backend
      } else {
        // User not logged in, FCM token stored locally only
      }
    } catch (e) {
      // Error registering for push notifications
    }
  }

  Future<void> _sendTokenToBackend(
    String fcmToken,
    String authToken,
    String? userId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/expoTokenSave'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'expo_token': fcmToken,
          'device_name':
              '${Platform.operatingSystem}_${Platform.operatingSystemVersion}',
          'user_id': userId,
          'device_type': Platform.isIOS ? 'ios' : 'android',
        }),
      );

      if (response.statusCode == 200) {
        // FCM token sent to backend successfully
      } else {
        // Failed to send FCM token to backend
      }
    } catch (e) {
      // Error sending FCM token to backend
    }
  }

  Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fcm_token');
      // FCM token deleted
    } catch (e) {
      // Error deleting FCM token
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      // Subscribed to topic successfully
    } catch (e) {
      // Error subscribing to topic
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      // Unsubscribed from topic successfully
    } catch (e) {
      // Error unsubscribing from topic
    }
  }
}
