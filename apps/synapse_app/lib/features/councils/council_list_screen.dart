import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_shell.dart';
import '../../ui/synapse_tokens.dart';
import '../../widgets/council_status_badge.dart';

class CouncilListScreen extends StatefulWidget {
  final SynapseApiClient client;

  const CouncilListScreen({super.key, required this.client});

  @override
  State<CouncilListScreen> createState() => _CouncilListScreenState();
}

class _CouncilListScreenState extends State<CouncilListScreen> {
  List<CouncilSummary> _councils = [];
  Set<String> _awaitedIds = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCouncils();
  }

  Future<void> _loadCouncils() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.client.listCouncils(),
        widget.client
            .getNotificationFeed(limit: 50)
            .then<List<FeedItem>>(
              (items) => items,
              onError: (_) => const <FeedItem>[],
            ),
      ]);
      final councils = results[0] as List<CouncilSummary>;
      final feed = results[1] as List<FeedItem>;
      if (!mounted) return;
      setState(() {
        _councils = councils;
        _awaitedIds = feed
            .where((it) => it.type == 'awaited_contribution')
            .map((it) => it.councilId)
            .toSet();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return DateFormat('h:mm a').format(dt);
      }
      return DateFormat('MMM d').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SynapseWorkspaceFrame(
      selected: SynapseNavItem.councils,
      title: 'Councils',
      subtitle: '${_councils.length} sessions',
      actions: [
        SynIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          onPressed: _loading ? null : _loadCouncils,
        ),
        const SizedBox(width: SynSpacing.sm),
        FilledButton.icon(
          onPressed: () => context.push('/councils/new'),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New council'),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _loadCouncils,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SynErrorState(message: _error!, onRetry: _loadCouncils);
    }
    if (_councils.isEmpty) {
      return SynEmptyState(
        icon: Icons.account_tree_outlined,
        title: 'No councils yet',
        message: 'Create a council to start a deliberation.',
        action: FilledButton.icon(
          onPressed: () => context.push('/councils/new'),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New council'),
        ),
      );
    }

    final failed = _councils.where((c) => c.status == 'failed').length;
    final active = _councils.where((c) => c.status.startsWith('stage_')).length;
    final closed = _councils.where((c) => c.status == 'closed').length;

    return ListView(
      padding: const EdgeInsets.all(SynSpacing.xl),
      children: [
        Row(
          children: [
            _MetricTile(label: 'Active', value: active.toString()),
            const SizedBox(width: SynSpacing.md),
            _MetricTile(label: 'Closed', value: closed.toString()),
            const SizedBox(width: SynSpacing.md),
            _MetricTile(
              label: 'Failed',
              value: failed.toString(),
              accent: failed == 0 ? SynColors.textMuted : SynColors.red,
            ),
          ],
        ),
        const SizedBox(height: SynSpacing.lg),
        SynSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < _councils.length; i++) ...[
                _CouncilRow(
                  council: _councils[i],
                  dateLabel: _formatDate(_councils[i].createdAt),
                  awaited: _awaitedIds.contains(_councils[i].sessionId),
                  onTap: () =>
                      context.push('/councils/${_councils[i].sessionId}'),
                ),
                if (i != _councils.length - 1)
                  const Divider(height: 1, color: SynColors.border),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _MetricTile({
    required this.label,
    required this.value,
    this.accent = SynColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SynSurface(
        color: SynColors.surfaceMuted,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 34,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(SynRadii.pill),
              ),
            ),
            const SizedBox(width: SynSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: SynColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CouncilRow extends StatelessWidget {
  final CouncilSummary council;
  final String dateLabel;
  final bool awaited;
  final VoidCallback onTap;

  const _CouncilRow({
    required this.council,
    required this.dateLabel,
    required this.awaited,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final failureReason = council.failureReason;
    return Material(
      color: awaited
          ? SynColors.magenta.withValues(alpha: 0.07)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SynSpacing.lg,
            vertical: SynSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: synStatusStyle(
                    council.status,
                  ).color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SynRadii.md),
                  border: Border.all(
                    color: synStatusStyle(
                      council.status,
                    ).color.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  synStatusStyle(council.status).icon,
                  color: synStatusStyle(council.status).color,
                  size: 18,
                ),
              ),
              const SizedBox(width: SynSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            council.question,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: SynSpacing.md),
                        Text(
                          dateLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: SynColors.textFaint),
                        ),
                      ],
                    ),
                    const SizedBox(height: SynSpacing.sm),
                    Wrap(
                      spacing: SynSpacing.sm,
                      runSpacing: SynSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CouncilStatusBadge(status: council.status),
                        _TinyPill(
                          icon: Icons.category_outlined,
                          label: council.councilType.toUpperCase(),
                        ),
                        if (council.confidenceLabel != null)
                          _TinyPill(
                            icon: Icons.verified_outlined,
                            label: council.confidenceLabel!,
                          ),
                        if (awaited)
                          const _TinyPill(
                            icon: Icons.person_add_alt_1_outlined,
                            label: 'AWAITING YOU',
                            color: SynColors.magenta,
                          ),
                      ],
                    ),
                    if (failureReason != null && failureReason.isNotEmpty) ...[
                      const SizedBox(height: SynSpacing.sm),
                      Text(
                        failureReason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: SynColors.red),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: SynSpacing.sm),
              const Icon(
                Icons.chevron_right,
                color: SynColors.textFaint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TinyPill({
    required this.icon,
    required this.label,
    this.color = SynColors.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: SynSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SynRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: SynSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
