import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/notifications/firebase_push.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      title: 'Synapse',
      size: const Size(1240, 860),
      minimumSize: const Size(980, 680),
      center: true,
      skipTaskbar: false,
      backgroundColor: Colors.transparent,
      titleBarStyle: Platform.isLinux
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final firebaseReady = await initializeFirebase();
  runApp(SynapseApp(firebaseReady: firebaseReady));
}

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;
