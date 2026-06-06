import 'package:flutter/material.dart';

import '../../core/api/client.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';

/// W7 / B8 — analytics overview. Three cards:
///   * Consensus distribution (high/medium/low/unscored bars)
///   * Member leaderboard (top participating LLMs)
///   * Decision velocity sparkline (last N days)
///
/// Data is fetched in parallel on first build and refreshed via pull-to-refresh.
class AnalyticsScreen extends StatefulWidget {
  final SynapseApiClient apiClient;
  const AnalyticsScreen({super.key, required this.apiClient});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<_AnalyticsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AnalyticsData> _load() async {
    final results = await Future.wait([
      widget.apiClient.getAnalyticsConsensus(),
      widget.apiClient.getAnalyticsVelocity(days: 14),
      widget.apiClient.getAnalyticsMembers(limit: 5),
    ]);
    return _AnalyticsData(
      consensus: results[0] as Map<String, dynamic>,
      velocity: results[1] as Map<String, dynamic>,
      members: results[2] as List<dynamic>,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_AnalyticsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return SynErrorState(
              title: 'Could not load analytics',
              message: snap.error.toString(),
              onRetry: _refresh,
            );
          }
          final d = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(SynSpacing.xl),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 820;
                  final cards = [
                    _ConsensusCard(payload: d.consensus),
                    _VelocityCard(payload: d.velocity),
                  ];
                  if (narrow) {
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: SynSpacing.md),
                        cards[1],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: SynSpacing.md),
                      Expanded(child: cards[1]),
                    ],
                  );
                },
              ),
              const SizedBox(height: SynSpacing.md),
              _MembersCard(rows: d.members),
            ],
          );
        },
      ),
    );
  }
}

class _AnalyticsData {
  final Map<String, dynamic> consensus;
  final Map<String, dynamic> velocity;
  final List<dynamic> members;
  _AnalyticsData({
    required this.consensus,
    required this.velocity,
    required this.members,
  });
}

class _ConsensusCard extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _ConsensusCard({required this.payload});

  @override
  Widget build(BuildContext context) {
    final data = payload['data'] as Map<String, dynamic>? ?? {};
    final total = (data['total'] as num?)?.toInt() ?? 0;
    final high = (data['high'] as num?)?.toInt() ?? 0;
    final medium = (data['medium'] as num?)?.toInt() ?? 0;
    final low = (data['low'] as num?)?.toInt() ?? 0;
    final unscored = (data['unscored'] as num?)?.toInt() ?? 0;

    return SynSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Consensus distribution',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '$total councils total',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: SynColors.textMuted),
          ),
          const SizedBox(height: 12),
          _bar(context, 'High (>=70%)', high, total, SynColors.green),
          const SizedBox(height: 6),
          _bar(context, 'Medium (40-70%)', medium, total, SynColors.amber),
          const SizedBox(height: 6),
          _bar(context, 'Low (<40%)', low, total, SynColors.red),
          const SizedBox(height: 6),
          _bar(context, 'Unscored', unscored, total, SynColors.textFaint),
        ],
      ),
    );
  }

  Widget _bar(
    BuildContext context,
    String label,
    int n,
    int total,
    Color colour,
  ) {
    final pct = total == 0 ? 0.0 : n / total;
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: SynColors.surfaceRaised,
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          child: Text(
            '$n',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _VelocityCard extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _VelocityCard({required this.payload});

  @override
  Widget build(BuildContext context) {
    final points = (payload['data'] as List<dynamic>?) ?? [];
    final counts = points
        .map((e) => ((e['count'] as num?) ?? 0).toInt())
        .toList();
    final maxCount = counts.isEmpty
        ? 1
        : counts.reduce((a, b) => a > b ? a : b);
    final total = counts.fold<int>(0, (a, b) => a + b);

    return SynSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Decision velocity (14d)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '$total councils closed',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: SynColors.textMuted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: counts
                  .map(
                    (c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Container(
                          height: 56 * (maxCount == 0 ? 0 : c / maxCount),
                          decoration: const BoxDecoration(
                            color: SynColors.primary,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MembersCard extends StatelessWidget {
  final List<dynamic> rows;
  const _MembersCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SynEmptyState(
        icon: Icons.groups_2_outlined,
        title: 'No member data yet',
        message: 'Participation analytics will appear after councils run.',
      );
    }
    return SynSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top members', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: SynSpacing.md),
          ...rows.take(5).map((row) {
            final m = row as Map<String, dynamic>;
            final name = (m['member_name'] ?? m['member_id'] ?? '-').toString();
            final n = (m['councils_participated'] as num?)?.toInt() ?? 0;
            final cs = (m['avg_consensus_score'] as num?)?.toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: SynSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$n councils${cs == null ? '' : ' / ${(cs * 100).round()}% avg'}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: SynColors.textMuted),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
