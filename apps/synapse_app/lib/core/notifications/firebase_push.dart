import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// Top-level background handler required by Firebase Messaging.
/// Must live in main.dart (or a file imported by main.dart).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final title =
      message.notification?.title ?? message.data['title'] ?? 'Synapse';
  final body = message.notification?.body ?? message.data['body'] ?? '';
  if (title.isNotEmpty || body.isNotEmpty) {
    await NotificationService.showBackgroundNotification(title, body);
  }
}

/// Initialise Firebase if platform config is present. Returns false when
/// google-services.json / GoogleService-Info.plist are not bundled.
Future<bool> initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    return true;
  } catch (e) {
    debugPrint('Firebase not configured — native push disabled: $e');
    return false;
  }
}
