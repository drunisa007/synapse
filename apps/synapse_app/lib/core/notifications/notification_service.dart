import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../api/client.dart';

/// F3 — push notification orchestration for the Synapse Flutter app.
///
/// Delivery paths (in priority order when configured):
///   1. **FCM/APNs** (Phase 2) — `firebase_messaging` for background/killed-app
///      delivery on iOS and Android. Token registered as `token_type: fcm`.
///   2. **ntfy long-poll** (Phase 1) — foreground/desktop fallback via HTTP
///      stream to `https://ntfy.sh/{topic}/json`.
class NotificationService {
  static const _kTopicPrefKey = 'synapse_ntfy_topic';
  static const _kDeviceLabelPrefKey = 'synapse_ntfy_device_label';
  static const _kFcmRegisteredPrefKey = 'synapse_fcm_registered_token';
  static const _ntfyServer = 'https://ntfy.sh';

  static final FlutterLocalNotificationsPlugin _backgroundLocal =
      FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  String? _topic;
  bool _initialized = false;
  bool _firebaseReady = false;
  bool _backendRegistered = false;
  http.Client? _streamClient;
  SynapseApiClient? _apiClient;

  /// Subscribe to be notified in-app.
  void Function(String title, String body)? onMessage;
  void Function(String reason)? onError;

  /// Fired when the user taps a notification that carries a council deep
  /// link. The handler is responsible for navigation (the service
  /// deliberately doesn't import go_router so it stays unit-testable).
  ///
  /// Fires from THREE entry points, all funnelled through one callback:
  ///   1. `FirebaseMessaging.onMessageOpenedApp` — tap while app is in
  ///      the background but still running.
  ///   2. `FirebaseMessaging.getInitialMessage` — tap that cold-started
  ///      the app from a terminated state.
  ///   3. `flutter_local_notifications.onDidReceiveNotificationResponse`
  ///      — tap on a notification the app rendered itself (foreground
  ///      delivery + ntfy long-poll).
  void Function(String councilId)? onCouncilOpen;

  /// Tenant the user is currently signed into. Used by the defence-in-
  /// depth filter that drops incoming pushes whose `data.tenant_id`
  /// doesn't match — guards against stale device-token rows in a tenant
  /// the user has since signed out of (the row persists server-side
  /// until explicitly deleted, so pushes can keep arriving). Set by the
  /// app shell on auth, cleared on sign-out.
  String? _currentTenantId;

  /// Called when the user signs into a tenant (or switches). Mismatches
  /// after this point cause silent suppression of any push whose payload
  /// carries a different `tenant_id`.
  ///
  /// `null` means "no current tenant" — in that case the filter still
  /// runs but suppresses ALL tenant-tagged pushes. Pre-Slice-8 pushes
  /// (no `tenant_id` field on the payload) always pass — that's the
  /// graceful-fallback behaviour for old server versions.
  void setCurrentTenantId(String? tenantId) {
    _currentTenantId = tenantId;
  }

  /// Bind the API client for automatic post-login device registration.
  void bindApiClient(SynapseApiClient client) {
    _apiClient = client;
  }

  /// Run once at app start. Idempotent.
  Future<void> initialize({bool firebaseReady = false}) async {
    if (_initialized) return;
    _firebaseReady = firebaseReady;

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    if (Platform.isAndroid) {
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _local
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      await _local
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    if (_firebaseReady) {
      await _setupFirebaseMessaging();
    }

    _initialized = true;
  }

  /// Register push endpoints with the backend after login.
  /// Safe to call multiple times — skips duplicate FCM registration.
  Future<void> registerWithBackend() async {
    final client = _apiClient;
    if (client == null) return;

    if (_firebaseReady) {
      await _registerFcmToken(client);
    }
  }

  /// Called from GoRouter redirect when auth + server are ready.
  Future<void> onAuthenticated() async {
    await registerWithBackend();
    // Foreground ntfy fallback when FCM is unavailable or for desktop builds.
    if (!_firebaseReady && !kIsWeb) {
      await startListening();
    }
  }

  Future<void> _setupFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;

    if (Platform.isIOS) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      // Ensure APNs token is available before FCM token on iOS.
      await messaging.getAPNSToken();
    }

    FirebaseMessaging.onMessage.listen((message) {
      if (!_passesTenantFilter(message.data)) return;
      final title =
          message.notification?.title ?? message.data['title'] ?? 'Synapse';
      final body = message.notification?.body ?? message.data['body'] ?? '';
      // Pass council_id + tenant_id through to _showLocal so a tap on
      // the local notification we render here still deep-links AND
      // re-runs the tenant filter at tap time (the user may have
      // switched tenants between receive and tap).
      _showLocal(
        title,
        body,
        councilId: _councilIdFrom(message.data),
        tenantId: message.data['tenant_id'] as String?,
      );
      onMessage?.call(title, body);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (!_passesTenantFilter(message.data)) return;
      final title =
          message.notification?.title ?? message.data['title'] ?? 'Synapse';
      final body = message.notification?.body ?? message.data['body'] ?? '';
      onMessage?.call(title, body);
      _maybeOpenCouncil(_councilIdFrom(message.data));
    });

    // Cold start from a notification tap. Returns the message that
    // launched the app, or null if launched normally — we drain it once
    // here so the deep link still fires. Tenant filter applies here too
    // so a cold-start tap on a stale-tenant push doesn't yank the user
    // into the wrong tenant's council screen.
    final initial = await messaging.getInitialMessage();
    if (initial != null && _passesTenantFilter(initial.data)) {
      _maybeOpenCouncil(_councilIdFrom(initial.data));
    }

    messaging.onTokenRefresh.listen((token) async {
      final client = _apiClient;
      if (client != null) {
        await _uploadFcmToken(client, token);
      }
    });
  }

  // Backend payload contract (see Synapse.Notifications.Push.Fcm/Apns):
  // `data` carries string-keyed fields including `council_id` and `kind`.
  // Tolerate either a top-level `council_id` or a nested `data.council_id`
  // shape — APNs places everything alongside `aps` but FCM sometimes
  // bubbles `data` up depending on platform plumbing.
  String? _councilIdFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    final direct = data['council_id'];
    if (direct is String && direct.isNotEmpty) return direct;
    final nested = data['data'];
    if (nested is Map) {
      final nestedId = nested['council_id'];
      if (nestedId is String && nestedId.isNotEmpty) return nestedId;
    }
    return null;
  }

  void _maybeOpenCouncil(String? councilId) {
    if (councilId == null || councilId.isEmpty) return;
    final handler = onCouncilOpen;
    if (handler != null) handler(councilId);
  }

  /// Defence-in-depth filter: drop pushes whose payload `tenant_id`
  /// doesn't match the currently-signed-in tenant.
  ///
  /// Three cases:
  ///   * Payload has no `tenant_id` (old-server pre-Slice-8 OR an
  ///     ntfy payload that lacks the field): pass. Backwards-compatible.
  ///   * Payload has `tenant_id` AND `_currentTenantId` is null
  ///     (user signed out, but device-token row still live on server):
  ///     SUPPRESS. Log it so the operator can see stale tokens piling
  ///     up server-side.
  ///   * Payload `tenant_id` differs from `_currentTenantId`
  ///     (user signed into a different tenant since this token was
  ///     registered): SUPPRESS. Same logging.
  ///
  /// The server-side `list_devices(tenant_id, ...)` lookup is already
  /// tenant-scoped; this guard catches the edge case where the user is
  /// a member of multiple tenants and the OS just delivered a push
  /// from a tenant they're not currently looking at.
  bool _passesTenantFilter(Map<String, dynamic>? data) {
    if (data == null) return true;
    final payloadTenant = data['tenant_id'];
    if (payloadTenant is! String || payloadTenant.isEmpty) return true;

    final current = _currentTenantId;
    if (current == null || payloadTenant != current) {
      if (kDebugMode) {
        debugPrint(
          'NotificationService: suppressed push for tenant=$payloadTenant '
          '(current=$current). Server-side device-token row likely stale.',
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _registerFcmToken(SynapseApiClient client) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_kFcmRegisteredPrefKey);
      if (last == token && _backendRegistered) return;

      await _uploadFcmToken(client, token);
      _backendRegistered = true;
    } catch (e) {
      onError?.call('FCM registration failed: $e');
    }
  }

  Future<void> _uploadFcmToken(SynapseApiClient client, String token) async {
    final label = await getDeviceLabel() ?? _defaultDeviceLabel();
    await client.registerDeviceToken(
      token: token,
      tokenType: 'fcm',
      deviceLabel: label,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFcmRegisteredPrefKey, token);
  }

  String _defaultDeviceLabel() {
    if (Platform.isIOS) return 'iOS device';
    if (Platform.isAndroid) return 'Android device';
    return 'Mobile device';
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      // Same defence-in-depth filter as the FCM path. If a stale
      // notification (rendered before the user switched tenants) sits in
      // the OS tray, tapping it must not yank them into the wrong
      // tenant's council screen.
      if (!_passesTenantFilter(data)) return;

      final title = (data['title'] as String?) ?? 'Synapse';
      final body = (data['body'] as String?) ?? '';
      onMessage?.call(title, body);
      // Local-render path (foreground FCM + ntfy long-poll) — payload
      // carries the same council_id we extracted at receive time.
      final councilId = data['council_id'];
      if (councilId is String) _maybeOpenCouncil(councilId);
    } catch (_) {}
  }

  /// Background isolate entry — shows a notification without the app instance.
  static Future<void> showBackgroundNotification(
    String title,
    String body,
  ) async {
    await _backgroundLocal.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      ),
    );
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'synapse_default',
        'Synapse',
        channelDescription: 'Verdicts, summons, and approval requests',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    await _backgroundLocal.show(
      DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title,
      body,
      details,
    );
  }

  Future<String> ensureTopic() async {
    if (_topic != null) return _topic!;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kTopicPrefKey);
    if (stored != null && stored.isNotEmpty) {
      _topic = stored;
      return stored;
    }
    final fresh = 'synapse-${const Uuid().v4()}';
    await prefs.setString(_kTopicPrefKey, fresh);
    _topic = fresh;
    return fresh;
  }

  Future<void> setDeviceLabel(String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceLabelPrefKey, label);
  }

  Future<String?> getDeviceLabel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDeviceLabelPrefKey);
  }

  Future<void> startListening() async {
    if (_topic == null) await ensureTopic();
    final url = '$_ntfyServer/$_topic/json';

    _streamClient?.close();
    _streamClient = http.Client();

    () async {
      while (_streamClient != null) {
        try {
          final request = http.Request('GET', Uri.parse(url));
          final response = await _streamClient!.send(request);
          if (response.statusCode != 200) {
            onError?.call('ntfy returned ${response.statusCode}');
            await Future.delayed(const Duration(seconds: 5));
            continue;
          }
          await for (final line
              in response.stream
                  .transform(const Utf8Decoder())
                  .transform(const LineSplitter())) {
            if (line.trim().isEmpty) continue;
            try {
              final event = jsonDecode(line) as Map<String, dynamic>;
              if (event['event'] == 'message') {
                final title = (event['title'] as String?) ?? 'Synapse';
                final body = (event['message'] as String?) ?? '';
                await _showLocal(title, body);
                onMessage?.call(title, body);
              }
            } catch (_) {}
          }
        } catch (e) {
          onError?.call(e.toString());
          await Future.delayed(const Duration(seconds: 5));
        }
      }
    }();
  }

  void stopListening() {
    _streamClient?.close();
    _streamClient = null;
  }

  Future<void> _showLocal(
    String title,
    String body, {
    String? councilId,
    String? tenantId,
  }) async {
    // Serialise everything the tap handler needs — `_onNotificationTap`
    // re-parses this exact shape. Keep optional fields off the payload
    // when nil so tap-on-non-council notifications don't misroute and
    // the tenant filter doesn't run against a missing value.
    final payload = jsonEncode({
      'title': title,
      'body': body,
      if (councilId != null) 'council_id': councilId,
      if (tenantId != null) 'tenant_id': tenantId,
    });
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'synapse_default',
        'Synapse',
        channelDescription: 'Verdicts, summons, and approval requests',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title,
      body,
      details,
      payload: payload,
    );
  }

  // ── Test-only seam (Slice 6a) ────────────────────────────────────────────
  //
  // Production push-tap routing fires through three async entry points
  // (FCM background tap, FCM cold-start, local-tap on app-rendered
  // notification) — none of which are practical to drive end-to-end in a
  // unit test without a live Firebase + APNs stack. This visible-for-
  // testing helper exposes the parse-then-dispatch core so tests can
  // verify the data-shape handling (top-level `council_id`, nested
  // `data.council_id`, missing/empty values) without spinning up the
  // platform plumbing.
  @visibleForTesting
  void handlePushDataForTest(Map<String, dynamic>? data) {
    _maybeOpenCouncil(_councilIdFrom(data));
  }

  /// Test seam for the tenant filter — exposes the production decision
  /// (suppress vs. pass) without spinning up the FCM/local-notification
  /// plumbing. The real handlers call `_passesTenantFilter/1` before
  /// any side-effecting work.
  @visibleForTesting
  bool passesTenantFilterForTest(Map<String, dynamic>? data) {
    return _passesTenantFilter(data);
  }
}
