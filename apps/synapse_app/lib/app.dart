import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/api/client.dart';
import 'core/auth/token_store.dart';
import 'core/config/server_store.dart';
import 'core/notifications/notification_service.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/councils/council_list_screen.dart';
import 'features/councils/council_detail_screen.dart';
import 'features/councils/create_council_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/chat_session_detail_screen.dart';
import 'features/chat/chat_sessions_screen.dart';
import 'features/chat/verdict_chat_screen.dart';
import 'features/memory/memory_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/server_setup/server_setup_screen.dart';
import 'features/settings/notifications_settings_screen.dart';
import 'features/settings/settings_screen.dart';
import 'ui/synapse_components.dart';
import 'ui/synapse_navigation_history.dart';
import 'ui/synapse_shell.dart';
import 'ui/synapse_theme.dart';

class SynapseApp extends StatefulWidget {
  final bool firebaseReady;

  const SynapseApp({super.key, this.firebaseReady = false});

  @override
  State<SynapseApp> createState() => _SynapseAppState();
}

class _SynapseAppState extends State<SynapseApp> {
  late final TokenStore _tokenStore;
  late final ServerStore _serverStore;
  late final SynapseApiClient _client;
  late final NotificationService _notifications;
  late final GoRouter _router;
  bool _pushHooked = false;

  @override
  void initState() {
    super.initState();
    _tokenStore = TokenStore();
    _serverStore = ServerStore();

    // baseUrl and isCerebro start empty/false; the redirect below syncs them
    // from ServerStore on every navigation so the client is always in step
    // with stored state.
    _client = SynapseApiClient(baseUrl: '', tokenStore: _tokenStore);
    _notifications = NotificationService();
    _notifications.bindApiClient(_client);
    // Push-tap deep linking (Slice 6a). The service stays decoupled from
    // go_router — it just calls back here with a council id; we trampoline
    // through the router. `mounted` guards against late callbacks after
    // the widget is gone (e.g. signed-out cold-start tap).
    _notifications.onCouncilOpen = (councilId) {
      if (!mounted) return;
      _router.go('/councils/$councilId');
    };
    _notifications.initialize(firebaseReady: widget.firebaseReady);

    _router = GoRouter(
      initialLocation: '/councils',
      redirect: (context, state) async {
        final serverUrl = await _serverStore.getUrl();
        final loc = state.matchedLocation;
        final isSetup = loc == '/server-setup';

        // Keep the live client in sync whenever routing occurs.
        if (serverUrl != null) {
          _client.baseUrl = serverUrl;
          _client.isCerebro = await _serverStore.getIsCerebro();
        }

        if (serverUrl == null && !isSetup) return '/server-setup';

        final token = await _tokenStore.getToken();
        final isLogin = loc == '/login';
        if (token == null && !isSetup && !isLogin) return '/login';
        if (token == null) _pushHooked = false;

        // Post-login: register FCM/APNs device token + start ntfy fallback.
        if (token != null && serverUrl != null && !_pushHooked) {
          _pushHooked = true;
          unawaited(_notifications.onAuthenticated());
        }

        return null;
      },
      routes: [
        GoRoute(path: '/', redirect: (_, __) => '/councils'),

        // ── Server setup (first run + server switch) ────────────────────────
        GoRoute(
          path: '/server-setup',
          builder: (context, state) => ServerSetupScreen(
            serverStore: _serverStore,
            tokenStore: _tokenStore,
            onServerConfigured: (url, isCerebro) {
              _client.baseUrl = url;
              _client.isCerebro = isCerebro;
            },
          ),
        ),

        // ── Auth ────────────────────────────────────────────────────────────
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              LoginScreen(tokenStore: _tokenStore, serverStore: _serverStore),
        ),

        ShellRoute(
          builder: (context, state, child) => SynapseWorkspaceRoot(
            selected: _navItemForPath(state.uri.path),
            child: child,
          ),
          routes: [
            // ── Councils ────────────────────────────────────────────────────
            GoRoute(
              path: '/councils',
              pageBuilder: (context, state) =>
                  NoTransitionPage(child: CouncilListScreen(client: _client)),
            ),
            GoRoute(
              path: '/councils/new',
              pageBuilder: (context, state) =>
                  NoTransitionPage(child: CreateCouncilScreen(client: _client)),
            ),
            GoRoute(
              path: '/councils/:id',
              pageBuilder: (context, state) => NoTransitionPage(
                child: CouncilDetailScreen(
                  sessionId: state.pathParameters['id']!,
                  client: _client,
                ),
              ),
            ),
            GoRoute(
              path: '/councils/:id/chat',
              pageBuilder: (context, state) {
                final sessionId = state.pathParameters['id']!;
                final extra = state.extra as Map<String, dynamic>?;
                final threadId = extra?['threadId'] as String?;
                final status = extra?['status'] as String? ?? 'pending';
                return NoTransitionPage(
                  child: SynapseWorkspaceFrame(
                    selected: SynapseNavItem.councils,
                    title: 'Council thread',
                    onBack: () => context.go('/councils/$sessionId'),
                    body: _CouncilChatRoute(
                      sessionId: sessionId,
                      threadId: threadId,
                      councilStatus: status,
                      client: _client,
                    ),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/councils/:id/verdict',
              pageBuilder: (context, state) {
                final sessionId = state.pathParameters['id']!;
                return NoTransitionPage(
                  child: SynapseWorkspaceFrame(
                    selected: SynapseNavItem.councils,
                    title: 'Verdict chat',
                    onBack: () => context.go('/councils/$sessionId'),
                    body: VerdictChatScreen(
                      sessionId: sessionId,
                      client: _client,
                    ),
                  ),
                );
              },
            ),

            // ── Chat-with-tools (Mode 4 — free-standing) ────────────────────
            GoRoute(
              path: '/chat/sessions',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SynapseWorkspaceFrame(
                  selected: SynapseNavItem.chat,
                  title: 'Assistant',
                  subtitle: 'Free-form chat with tool use and human mentions.',
                  body: ChatSessionsScreen(client: _client),
                ),
              ),
            ),
            GoRoute(
              path: '/chat/sessions/:id',
              pageBuilder: (context, state) {
                final sessionId = state.pathParameters['id']!;
                return NoTransitionPage(
                  child: SynapseWorkspaceFrame(
                    selected: SynapseNavItem.chat,
                    title: 'Assistant thread',
                    onBack: () => context.go('/chat/sessions'),
                    body: ChatSessionDetailScreen(
                      client: _client,
                      sessionId: sessionId,
                    ),
                  ),
                );
              },
            ),

            // ── Settings ────────────────────────────────────────────────────
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SynapseWorkspaceFrame(
                  selected: SynapseNavItem.settings,
                  title: 'Settings',
                  subtitle: 'Connection, account, and device preferences.',
                  body: SettingsScreen(
                    serverStore: _serverStore,
                    tokenStore: _tokenStore,
                    onServerCleared: () => _client.baseUrl = '',
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/settings/notifications',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SynapseWorkspaceFrame(
                  selected: SynapseNavItem.settings,
                  title: 'Notification settings',
                  onBack: () => context.go('/settings'),
                  body: NotificationsSettingsScreen(
                    apiClient: _client,
                    notificationService: _notifications,
                  ),
                ),
              ),
            ),

            // ── Other features ──────────────────────────────────────────────
            GoRoute(
              path: '/notifications',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SynapseWorkspaceFrame(
                  selected: SynapseNavItem.notifications,
                  title: 'Notifications',
                  subtitle: 'Verdicts, summons, and async council work.',
                  body: NotificationsScreen(apiClient: _client),
                ),
              ),
            ),
            GoRoute(
              path: '/memory',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SynapseWorkspaceFrame(
                  selected: SynapseNavItem.memory,
                  title: 'Memory',
                  subtitle:
                      'Search decisions, precedents, and council records.',
                  body: MemoryScreen(apiClient: _client),
                ),
              ),
            ),
            GoRoute(
              path: '/analytics',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SynapseWorkspaceFrame(
                  selected: SynapseNavItem.analytics,
                  title: 'Analytics',
                  subtitle: 'Consensus, velocity, and member participation.',
                  body: AnalyticsScreen(apiClient: _client),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    _router.routeInformationProvider.addListener(_recordRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordRoute());
  }

  void _recordRoute() {
    SynapseNavigationHistory.instance.record(
      _router.routeInformationProvider.value.uri.toString(),
    );
  }

  SynapseNavItem _navItemForPath(String path) {
    if (path.startsWith('/chat')) return SynapseNavItem.chat;
    if (path.startsWith('/memory')) return SynapseNavItem.memory;
    if (path.startsWith('/analytics')) return SynapseNavItem.analytics;
    if (path.startsWith('/notifications')) return SynapseNavItem.notifications;
    if (path.startsWith('/settings')) return SynapseNavItem.settings;
    return SynapseNavItem.councils;
  }

  @override
  void dispose() {
    _router.routeInformationProvider.removeListener(_recordRoute);
    _router.dispose();
    SynapseNavigationHistory.instance.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Synapse',
      debugShowCheckedModeBanner: false,
      theme: buildSynapseTheme(),
      routerConfig: _router,
    );
  }
}

class _CouncilChatRoute extends StatelessWidget {
  final String sessionId;
  final String? threadId;
  final String councilStatus;
  final SynapseApiClient client;

  const _CouncilChatRoute({
    required this.sessionId,
    required this.threadId,
    required this.councilStatus,
    required this.client,
  });

  @override
  Widget build(BuildContext context) {
    final knownThreadId = threadId;
    if (knownThreadId != null) {
      return ChatScreen(
        sessionId: sessionId,
        threadId: knownThreadId,
        councilStatus: councilStatus,
        client: client,
      );
    }

    return FutureBuilder<String>(
      future: client.getCouncilThreadId(sessionId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return SynErrorState(
            title: 'Thread unavailable',
            message: snapshot.error?.toString() ?? 'Thread not found',
          );
        }
        return ChatScreen(
          sessionId: sessionId,
          threadId: snapshot.data!,
          councilStatus: councilStatus,
          client: client,
        );
      },
    );
  }
}
