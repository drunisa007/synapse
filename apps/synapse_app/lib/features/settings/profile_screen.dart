import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../core/auth/token_store.dart';
import '../../core/config/server_store.dart';
import '../../core/routing/app_paths.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';

class ProfileScreen extends StatefulWidget {
  final SynapseApiClient apiClient;
  final TokenStore tokenStore;
  final ServerStore serverStore;

  const ProfileScreen({
    super.key,
    required this.apiClient,
    required this.tokenStore,
    required this.serverStore,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<_ProfileData> _future;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ProfileData> _load() async {
    final serverUrl = await widget.serverStore.getUrl();
    final authMode = await widget.serverStore.getAuthMode();
    final token = await widget.tokenStore.getToken();

    CurrentUser? currentUser;
    Object? profileError;

    try {
      currentUser = await widget.apiClient.getCurrentUser();
    } on ApiException catch (e) {
      profileError = e;
      if (authMode == 'local') {
        rethrow;
      }
    } catch (e) {
      profileError = e;
      if (authMode == 'local') {
        rethrow;
      }
    }

    return _ProfileData(
      serverUrl: serverUrl,
      authMode: authMode,
      currentUser: currentUser,
      tokenIdentity: currentUser == null
          ? TokenIdentity.tryParseJwt(token)
          : null,
      profileError: profileError,
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'This clears the current token but keeps the configured server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);
    await widget.tokenStore.clearToken();
    if (mounted) context.go(AppPaths.login);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProfileData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return SynErrorState(
            title: 'Could not load profile',
            message: snapshot.error.toString(),
            onRetry: () => setState(() => _future = _load()),
          );
        }

        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(SynSpacing.xl),
          children: [
            SynSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: SynColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(SynRadii.md),
                          border: Border.all(
                            color: SynColors.primary.withValues(alpha: 0.32),
                          ),
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: SynColors.primary,
                        ),
                      ),
                      const SizedBox(width: SynSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: SynSpacing.xs),
                            Text(
                              data.identityKind,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: SynColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SynSpacing.lg),
                  SynMetaRow(label: 'Auth mode', value: data.authModeLabel),
                  const SizedBox(height: SynSpacing.sm),
                  SynMetaRow(
                    label: 'Server',
                    value: data.serverUrl ?? 'Unknown',
                  ),
                  const SizedBox(height: SynSpacing.sm),
                  SynMetaRow(label: 'User ID / subject', value: data.subject),
                  const SizedBox(height: SynSpacing.sm),
                  SynMetaRow(label: 'Email', value: data.email),
                  const SizedBox(height: SynSpacing.sm),
                  SynMetaRow(label: 'Role(s)', value: data.roles),
                  if (data.tenantId != null) ...[
                    const SizedBox(height: SynSpacing.sm),
                    SynMetaRow(label: 'Tenant', value: data.tenantId!),
                  ],
                  if (data.profileError != null &&
                      data.currentUser == null) ...[
                    const SizedBox(height: SynSpacing.lg),
                    const SynNotice(
                      icon: Icons.info_outline,
                      title: 'Limited profile',
                      message:
                          'The server did not expose /auth/me for this auth mode, so token claims are shown where available.',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SynSpacing.md),
            SynSurface(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Session',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loggingOut
                        ? null
                        : () => context.go(AppPaths.settings),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Settings'),
                  ),
                  const SizedBox(width: SynSpacing.sm),
                  FilledButton.icon(
                    onPressed: _loggingOut ? null : _logout,
                    icon: _loggingOut
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout, size: 16),
                    label: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileData {
  final String? serverUrl;
  final String authMode;
  final CurrentUser? currentUser;
  final TokenIdentity? tokenIdentity;
  final Object? profileError;

  const _ProfileData({
    required this.serverUrl,
    required this.authMode,
    required this.currentUser,
    required this.tokenIdentity,
    required this.profileError,
  });

  String get displayName =>
      currentUser?.email ?? tokenIdentity?.displayName ?? 'Authenticated token';

  String get identityKind =>
      currentUser != null ? 'Signed in account' : 'Authenticated token';

  String get authModeLabel => switch (authMode) {
    'local' => 'Local email/password',
    'jwt_oidc' => 'OIDC / Casdoor',
    'jwt_hs256' => 'Bearer token / API key',
    _ => authMode,
  };

  String get subject => _blankToDash(currentUser?.id ?? tokenIdentity?.sub);

  String get email => _blankToDash(currentUser?.email ?? tokenIdentity?.email);

  String get roles {
    final localRole = currentUser?.role;
    if (localRole != null && localRole.isNotEmpty) return localRole;
    final values = tokenIdentity?.roles ?? const <String>[];
    return values.isEmpty ? '-' : values.join(', ');
  }

  String? get tenantId => tokenIdentity?.tenantId;

  static String _blankToDash(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? '-' : trimmed;
  }
}
