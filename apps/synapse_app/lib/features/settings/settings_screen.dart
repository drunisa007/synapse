import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/token_store.dart';
import '../../core/config/server_store.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';

/// App-level settings: server switching and links to sub-settings.
class SettingsScreen extends StatefulWidget {
  final ServerStore serverStore;
  final TokenStore tokenStore;

  /// Called after token + server URL are cleared so the live API client
  /// can reset its baseUrl before the router redirect fires.
  final VoidCallback onServerCleared;

  const SettingsScreen({
    super.key,
    required this.serverStore,
    required this.tokenStore,
    required this.onServerCleared,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _serverUrl;

  @override
  void initState() {
    super.initState();
    _loadServer();
  }

  Future<void> _loadServer() async {
    final url = await widget.serverStore.getUrl();
    if (mounted) setState(() => _serverUrl = url);
  }

  Future<void> _switchServer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch server?'),
        content: const Text(
          'You will be signed out and asked to connect to a new server. '
          'Your local data is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Switch',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await widget.tokenStore.clearToken();
    await widget.serverStore.clear();
    widget.onServerCleared();

    if (mounted) context.go('/server-setup');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(SynSpacing.xl),
      children: [
        SynSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connection', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: SynSpacing.md),
              SynMetaRow(
                label: 'Backend',
                value: _serverUrl ?? 'Not connected',
              ),
              const SizedBox(height: SynSpacing.lg),
              OutlinedButton.icon(
                onPressed: _switchServer,
                icon: const Icon(Icons.dns_outlined, size: 16),
                label: const Text('Switch server'),
              ),
            ],
          ),
        ),
        const SizedBox(height: SynSpacing.md),
        SynSurface(
          onTap: () => context.push('/settings/notifications'),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: SynColors.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SynRadii.md),
                  border: Border.all(
                    color: SynColors.cyan.withValues(alpha: 0.28),
                  ),
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  size: 18,
                  color: SynColors.cyan,
                ),
              ),
              const SizedBox(width: SynSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: SynSpacing.xs),
                    Text(
                      'Email, push, ntfy fallback, and registered devices.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SynColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SynColors.textMuted),
            ],
          ),
        ),
      ],
    );
  }
}
