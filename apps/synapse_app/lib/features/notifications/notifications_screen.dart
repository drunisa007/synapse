import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';

/// Notification feed screen — lists verdicts, summons, in-progress, and
/// pending-approval items for the current user. Polls the
/// [SynapseApiClient.getNotificationFeed] endpoint on pull-to-refresh.
class NotificationsScreen extends StatefulWidget {
  final SynapseApiClient apiClient;

  const NotificationsScreen({super.key, required this.apiClient});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<FeedItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<FeedItem>> _load() =>
      widget.apiClient.getNotificationFeed(limit: 30);

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<FeedItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return SynErrorState(
              title: 'Could not load notifications',
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const SynEmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'No notifications yet',
              message: 'Verdicts, summons, and approvals will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(SynSpacing.xl),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: SynSpacing.sm),
            itemBuilder: (context, i) => _FeedItemTile(item: items[i]),
          );
        },
      ),
    );
  }
}

class _FeedItemTile extends StatelessWidget {
  final FeedItem item;
  const _FeedItemTile({required this.item});

  Color _badgeColour(String type, ColorScheme cs) {
    switch (type) {
      case 'verdict_ready':
        return SynColors.green;
      case 'pending_approval':
        return SynColors.amber;
      case 'summon_requested':
        return SynColors.primary;
      case 'awaited_contribution':
        // Distinct from `summon_requested` — that's the operator-voice
        // ("your council is waiting for humans"); this one is the
        // participant-voice ("you are one of those humans"). Hotter
        // colour to reflect action required of THIS user. Matches the
        // Svelte web side (rose-500/15 token).
        return SynColors.magenta;
      case 'in_progress':
        return SynColors.cyan;
      default:
        return cs.outline;
    }
  }

  String _label(String type) {
    switch (type) {
      case 'verdict_ready':
        return 'Verdict ready';
      case 'pending_approval':
        return 'Needs approval';
      case 'summon_requested':
        return 'You are summoned';
      case 'awaited_contribution':
        return "You're awaited";
      case 'in_progress':
        return 'In progress';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badge = _badgeColour(item.type, cs);

    return SynSurface(
      padding: const EdgeInsets.all(SynSpacing.md),
      onTap: () => context.go('/councils/${item.councilId}'),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
          ),
          const SizedBox(width: SynSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: SynSpacing.sm),
                Wrap(
                  spacing: SynSpacing.sm,
                  runSpacing: SynSpacing.xs,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badge.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(SynRadii.sm),
                      ),
                      child: Text(
                        _label(item.type),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: badge,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (item.confidenceLabel != null)
                      Text(
                        item.confidenceLabel!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SynColors.textMuted,
                        ),
                      ),
                    if (item.consensusScore != null)
                      Text(
                        '${(item.consensusScore! * 100).round()}% consensus',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SynColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: SynSpacing.md),
          const Icon(Icons.chevron_right, size: 18, color: SynColors.textMuted),
        ],
      ),
    );
  }
}
