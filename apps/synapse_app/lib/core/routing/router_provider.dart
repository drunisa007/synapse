import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../providers/services.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/chat_session_detail_screen.dart';
import '../../features/chat/chat_sessions_screen.dart';
import '../../features/chat/verdict_chat_screen.dart';
import '../../features/councils/council_detail_screen.dart';
import '../../features/councils/council_list_screen.dart';
import '../../features/councils/create_council_screen.dart';
import '../../features/home/chat_home_screen.dart';
import '../../features/memory/memory_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/server_setup/server_setup_screen.dart';
import '../../features/settings/notifications_settings_screen.dart';
import '../../features/settings/profile_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_navigation_history.dart';
import '../../ui/synapse_shell.dart';
import 'app_paths.dart';

/// The single `GoRouter` instance for the app, wired against the
/// services held in Riverpod.
///
/// Build-only — never read across navigations; the router instance
/// itself is stable for the life of the process. Side effects in
/// `initState` of the legacy `SynapseApp` widget (notification
/// callback wiring, firebase init kick-off) happen here at provider
/// build time instead.
///
/// The router is bootstrapped with [firebaseReadyProvider] which the
/// app sets at startup via `overrideWithValue`.
final firebaseReadyProvider = Provider<bool>((ref) {
  throw UnimplementedError(
    'firebaseReadyProvider must be overridden in main.dart with the '
    'actual firebase initialization result.',
  );
});

final routerProvider = Provider<GoRouter>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  final serverStore = ref.watch(serverStoreProvider);
  final client = ref.watch(synapseApiClientProvider);
  final notifications = ref.watch(notificationServiceProvider);
  final firebaseReady = ref.watch(firebaseReadyProvider);

  // The router instance, captured via a late variable so the
  // notification callback below can reference it.
  late final GoRouter router;
  var pushHooked = false;

  // Push-tap deep linking — the service stays decoupled from go_router
  // and just calls back into us with a council id. Set BEFORE
  // `.initialize()` so the cold-start tap path can fire.
  notifications.onCouncilOpen = (councilId) {
    router.go(AppPaths.councilDetail(councilId));
  };
  notifications.initialize(firebaseReady: firebaseReady);

  // Routes the user can reach WITHOUT a configured server / signed-in
  // session. The chat-home shell handles its own empty state and
  // surfaces a "Connect to server" CTA contextually.
  const publicPaths = <String>{
    AppPaths.home,
    AppPaths.serverSetup,
    AppPaths.login,
    AppPaths.register,
  };

  router = GoRouter(
    initialLocation: AppPaths.home,
    redirect: (context, state) async {
      final loc = state.matchedLocation;
      final serverUrl = await serverStore.getUrl();

      // Keep the live client in sync whenever routing occurs.
      if (serverUrl != null) {
        client.baseUrl = serverUrl;
        client.isCerebro = await serverStore.getIsCerebro();
      }

      // Public routes (home / setup / login) never redirect — the
      // home screen explicitly handles the disconnected state with a
      // welcome card. Only routes that need API access are gated.
      if (publicPaths.contains(loc)) {
        if (serverUrl != null) {
          final token = await tokenStore.getToken();
          if (token == null) pushHooked = false;
          if (token != null && !pushHooked) {
            pushHooked = true;
            unawaited(notifications.onAuthenticated());
          }
        }
        return null;
      }

      // Non-public route: enforce server then auth, but trampoline
      // back to home on cancel rather than dead-ending on /server-setup.
      if (serverUrl == null) return AppPaths.serverSetup;

      final token = await tokenStore.getToken();
      if (token == null) return AppPaths.login;

      if (!pushHooked) {
        pushHooked = true;
        unawaited(notifications.onAuthenticated());
      }
      return null;
    },
    routes: [
      // ── Home (chat shell — public) ────────────────────────────────────
      GoRoute(
        path: AppPaths.home,
        builder: (context, state) => const ChatHomeScreen(),
      ),

      // ── Server setup ──────────────────────────────────────────────────
      GoRoute(
        path: AppPaths.serverSetup,
        builder: (context, state) => ServerSetupScreen(
          serverStore: serverStore,
          tokenStore: tokenStore,
          onServerConfigured: (url, isCerebro) {
            client.baseUrl = url;
            client.isCerebro = isCerebro;
          },
        ),
      ),

      // ── Auth ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppPaths.login,
        builder: (context, state) => LoginScreen(
          tokenStore: tokenStore,
          serverStore: serverStore,
          apiClient: client,
        ),
      ),
      GoRoute(
        path: AppPaths.register,
        builder: (context, state) => RegisterScreen(
          apiClient: client,
          tokenStore: tokenStore,
          serverStore: serverStore,
        ),
      ),

      ShellRoute(
        builder: (context, state, child) => SynapseWorkspaceRoot(
          selected: _navItemForPath(state.uri.path),
          child: child,
        ),
        routes: [
          // ── Councils ──────────────────────────────────────────────────
          GoRoute(
            path: AppPaths.councilList,
            pageBuilder: (context, state) =>
                NoTransitionPage(child: CouncilListScreen(client: client)),
          ),
          GoRoute(
            path: AppPaths.councilCreate,
            pageBuilder: (context, state) =>
                NoTransitionPage(child: CreateCouncilScreen(client: client)),
          ),
          GoRoute(
            path: AppPaths.councilDetailTemplate,
            pageBuilder: (context, state) => NoTransitionPage(
              child: CouncilDetailScreen(
                sessionId: state.pathParameters['id']!,
                client: client,
              ),
            ),
          ),
          GoRoute(
            path: AppPaths.councilChatTemplate,
            pageBuilder: (context, state) {
              final sessionId = state.pathParameters['id']!;
              final extra = state.extra as Map<String, dynamic>?;
              final threadId = extra?['threadId'] as String?;
              final status = extra?['status'] as String? ?? 'pending';
              return NoTransitionPage(
                child: SynapseWorkspaceFrame(
                  selected: SynapseNavItem.councils,
                  title: 'Council thread',
                  onBack: () => context.go(AppPaths.councilDetail(sessionId)),
                  body: _CouncilChatRoute(
                    sessionId: sessionId,
                    threadId: threadId,
                    councilStatus: status,
                    client: client,
                  ),
                ),
              );
            },
          ),
          GoRoute(
            path: AppPaths.councilVerdictTemplate,
            pageBuilder: (context, state) {
              final sessionId = state.pathParameters['id']!;
              return NoTransitionPage(
                child: SynapseWorkspaceFrame(
                  selected: SynapseNavItem.councils,
                  title: 'Verdict chat',
                  onBack: () => context.go(AppPaths.councilDetail(sessionId)),
                  body: VerdictChatScreen(sessionId: sessionId, client: client),
                ),
              );
            },
          ),

          // ── Chat-with-tools (free-standing) ───────────────────────────
          GoRoute(
            path: AppPaths.chatSessions,
            pageBuilder: (context, state) => NoTransitionPage(
              child: SynapseWorkspaceFrame(
                selected: SynapseNavItem.chat,
                title: 'Assistant',
                subtitle: 'Free-form chat with tool use and human mentions.',
                body: ChatSessionsScreen(client: client),
              ),
            ),
          ),
          GoRoute(
            path: AppPaths.chatSessionDetailTemplate,
            pageBuilder: (context, state) {
              final sessionId = state.pathParameters['id']!;
              return NoTransitionPage(
                child: SynapseWorkspaceFrame(
                  selected: SynapseNavItem.chat,
                  title: 'Assistant thread',
                  onBack: () => context.go(AppPaths.chatSessions),
                  body: ChatSessionDetailScreen(
                    client: client,
                    sessionId: sessionId,
                  ),
                ),
              );
            },
          ),

          // ── Settings ──────────────────────────────────────────────────
          GoRoute(
            path: AppPaths.settings,
            pageBuilder: (context, state) => NoTransitionPage(
              child: SynapseWorkspaceFrame(
                selected: SynapseNavItem.settings,
                title: 'Settings',
                subtitle: 'Connection, account, and device preferences.',
                body: SettingsScreen(
                  serverStore: serverStore,
                  tokenStore: tokenStore,
                  onServerCleared: () => client.baseUrl = '',
                ),
              ),
            ),
          ),
          GoRoute(
            path: AppPaths.settingsNotifications,
            pageBuilder: (context, state) => NoTransitionPage(
              child: SynapseWorkspaceFrame(
                selected: SynapseNavItem.settings,
                title: 'Notification settings',
                onBack: () => context.go(AppPaths.settings),
                body: NotificationsSettingsScreen(
                  apiClient: client,
                  notificationService: notifications,
                ),
              ),
            ),
          ),
          GoRoute(
            path: AppPaths.settingsProfile,
            pageBuilder: (context, state) => NoTransitionPage(
              child: SynapseWorkspaceFrame(
                selected: SynapseNavItem.settings,
                title: 'Profile',
                subtitle: 'Account and session.',
                onBack: () => context.go(AppPaths.settings),
                body: ProfileScreen(
                  apiClient: client,
                  tokenStore: tokenStore,
                  serverStore: serverStore,
                ),
              ),
            ),
          ),

          // ── Other features ────────────────────────────────────────────
          GoRoute(
            path: AppPaths.notifications,
            pageBuilder: (context, state) => NoTransitionPage(
              child: SynapseWorkspaceFrame(
                selected: SynapseNavItem.notifications,
                title: 'Notifications',
                subtitle: 'Verdicts, summons, and async council work.',
                body: NotificationsScreen(apiClient: client),
              ),
            ),
          ),
          GoRoute(
            path: AppPaths.memory,
            pageBuilder: (context, state) => NoTransitionPage(
              child: SynapseWorkspaceFrame(
                selected: SynapseNavItem.memory,
                title: 'Memory',
                subtitle: 'Search decisions, precedents, and council records.',
                body: MemoryScreen(apiClient: client),
              ),
            ),
          ),
          GoRoute(
            path: AppPaths.analytics,
            pageBuilder: (context, state) => NoTransitionPage(
              child: SynapseWorkspaceFrame(
                selected: SynapseNavItem.analytics,
                title: 'Analytics',
                subtitle: 'Consensus, velocity, and member participation.',
                body: AnalyticsScreen(apiClient: client),
              ),
            ),
          ),
        ],
      ),
    ],
  );

  void recordRoute() {
    SynapseNavigationHistory.instance.record(
      router.routeInformationProvider.value.uri.toString(),
    );
  }

  router.routeInformationProvider.addListener(recordRoute);
  unawaited(Future.microtask(recordRoute));
  ref.onDispose(() {
    router.routeInformationProvider.removeListener(recordRoute);
    SynapseNavigationHistory.instance.clear();
  });

  return router;
});

SynapseNavItem _navItemForPath(String path) {
  if (path.startsWith('/chat')) return SynapseNavItem.chat;
  if (path.startsWith('/memory')) return SynapseNavItem.memory;
  if (path.startsWith('/analytics')) return SynapseNavItem.analytics;
  if (path.startsWith('/notifications')) return SynapseNavItem.notifications;
  if (path.startsWith('/settings')) return SynapseNavItem.settings;
  return SynapseNavItem.councils;
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
