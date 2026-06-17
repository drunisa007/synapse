import 'app_names.dart';

/// Concrete path strings paired 1:1 with [AppNames]. Use these when
/// constructing navigation calls (`context.go(AppPaths.councilList)`)
/// — never inline string literals.
///
/// For parameterised routes, expose a tiny builder function alongside
/// the template (e.g. [councilDetail]).
abstract class AppPaths {
  // ── Always-on home ────────────────────────────────────────────────────
  static const home = '/';

  // ── Auth / setup ──────────────────────────────────────────────────────
  static const serverSetup = '/server-setup';
  static const login = '/login';
  static const register = '/register';

  // ── Councils ──────────────────────────────────────────────────────────
  static const councilList = '/councils';
  static const councilCreate = '/councils/new';
  static const councilDetailTemplate = '/councils/:id';
  static const councilChatTemplate = '/councils/:id/chat';
  static const councilVerdictTemplate = '/councils/:id/verdict';

  static String councilDetail(String id) => '/councils/$id';
  static String councilChat(String id) => '/councils/$id/chat';
  static String councilVerdict(String id) => '/councils/$id/verdict';

  // ── Chat (free-standing) ──────────────────────────────────────────────
  static const chatSessions = '/chat/sessions';
  static const chatSessionDetailTemplate = '/chat/sessions/:id';
  static String chatSessionDetail(String id) => '/chat/sessions/$id';

  // ── Settings & adjacents ──────────────────────────────────────────────
  static const settings = '/settings';
  static const settingsProfile = '/settings/profile';
  static const settingsNotifications = '/settings/notifications';
  static const notifications = '/notifications';
  static const memory = '/memory';
  static const analytics = '/analytics';

  /// Lookup: name → path template (or unparameterised path).
  ///
  /// Useful for command palette / shortcut systems that want to render
  /// "go to <name>" with the canonical path.
  static const Map<String, String> byName = {
    AppNames.homeScreen: home,
    AppNames.serverSetupScreen: serverSetup,
    AppNames.loginScreen: login,
    AppNames.registerScreen: register,
    AppNames.councilListScreen: councilList,
    AppNames.councilCreateScreen: councilCreate,
    AppNames.councilDetailScreen: councilDetailTemplate,
    AppNames.councilChatScreen: councilChatTemplate,
    AppNames.councilVerdictScreen: councilVerdictTemplate,
    AppNames.chatSessionsScreen: chatSessions,
    AppNames.chatSessionDetailScreen: chatSessionDetailTemplate,
    AppNames.settingsScreen: settings,
    AppNames.profileScreen: settingsProfile,
    AppNames.notificationsSettingsScreen: settingsNotifications,
    AppNames.notificationsScreen: notifications,
    AppNames.memoryScreen: memory,
    AppNames.analyticsScreen: analytics,
  };
}
