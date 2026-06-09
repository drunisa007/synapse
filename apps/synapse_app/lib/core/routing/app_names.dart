/// Route name constants. **Always** reference routes through these —
/// never use literal path strings inline. Typo-safe; refactor-safe.
///
/// Pattern adopted from HelloHQ — see
/// `cerebro/docs/_design/synapse-chat-execution-plan.md §4`.
abstract class AppNames {
  // ── Always-on home ────────────────────────────────────────────────────
  /// Chat shell — the first screen the user sees. Works without a
  /// configured server (renders welcome + connect CTA in that case).
  static const homeScreen = 'home';

  // ── Auth / setup ──────────────────────────────────────────────────────
  static const serverSetupScreen = 'server-setup';
  static const loginScreen = 'login';
  static const registerScreen = 'register';

  // ── Main app surface ──────────────────────────────────────────────────
  static const councilListScreen = 'councils';
  static const councilDetailScreen = 'council-detail';
  static const councilCreateScreen = 'council-create';
  static const councilChatScreen = 'council-chat';
  static const councilVerdictScreen = 'council-verdict';
  static const chatSessionsScreen = 'chat-sessions';
  static const chatSessionDetailScreen = 'chat-session-detail';

  // ── Adjacent surfaces ─────────────────────────────────────────────────
  static const memoryScreen = 'memory';
  static const analyticsScreen = 'analytics';
  static const notificationsScreen = 'notifications';
  static const notificationsSettingsScreen = 'notifications-settings';
  static const profileScreen = 'settings-profile';
  static const settingsScreen = 'settings';
}
