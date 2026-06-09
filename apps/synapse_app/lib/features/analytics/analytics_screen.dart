import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';

/// W7 / B8 - analytics overview.
///
/// Data is fetched in parallel on first build and refreshed via pull-to-refresh.
class AnalyticsScreen extends StatefulWidget {
  final SynapseApiClient apiClient;
  const AnalyticsScreen({super.key, required this.apiClient});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

enum _TopicView { summary, clusters }

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<_AnalyticsData> _future;
  _TopicView _topicView = _TopicView.summary;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AnalyticsData> _load() async {
    final results = await Future.wait<dynamic>([
      widget.apiClient.getAnalyticsConsensus(),
      widget.apiClient.getAnalyticsVelocity(days: 14),
      widget.apiClient.getAnalyticsMembers(limit: 5),
      _loadTopics(),
    ]);
    final topicResult = results[3] as _TopicResult;
    return _AnalyticsData(
      consensus: results[0] as Map<String, dynamic>,
      velocity: results[1] as Map<String, dynamic>,
      members: results[2] as List<dynamic>,
      topics: topicResult.data,
      topicsError: topicResult.error,
    );
  }

  Future<_TopicResult> _loadTopics() async {
    try {
      final data = await widget.apiClient.getAnalyticsTopics(
        cluster: _topicView == _TopicView.clusters,
        limit: 12,
      );
      return _TopicResult(data: data);
    } catch (error) {
      return _TopicResult(error: error);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
  }

  void _setTopicView(_TopicView view) {
    if (view == _topicView) return;
    setState(() {
      _topicView = view;
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
              _TopicsCard(
                data: d.topics,
                error: d.topicsError,
                view: _topicView,
                onViewChanged: _setTopicView,
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
  final TopicAnalytics? topics;
  final Object? topicsError;

  _AnalyticsData({
    required this.consensus,
    required this.velocity,
    required this.members,
    required this.topics,
    required this.topicsError,
  });
}

class _TopicResult {
  final TopicAnalytics? data;
  final Object? error;

  const _TopicResult({this.data, this.error});
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
          _bar(context, 'High (>=75%)', high, total, SynColors.green),
          const SizedBox(height: 6),
          _bar(context, 'Medium (50-74%)', medium, total, SynColors.amber),
          const SizedBox(height: 6),
          _bar(context, 'Low (<50%)', low, total, SynColors.red),
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

class _TopicsCard extends StatelessWidget {
  final TopicAnalytics? data;
  final Object? error;
  final _TopicView view;
  final ValueChanged<_TopicView> onViewChanged;

  const _TopicsCard({
    required this.data,
    required this.error,
    required this.view,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SynSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Topics', style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    'Closed council tags',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: SynColors.textMuted),
                  ),
                ],
              );
              final control = SegmentedButton<_TopicView>(
                segments: const [
                  ButtonSegment(
                    value: _TopicView.summary,
                    label: Text('Summary'),
                    icon: Icon(Icons.format_list_bulleted, size: 16),
                  ),
                  ButtonSegment(
                    value: _TopicView.clusters,
                    label: Text('Clusters'),
                    icon: Icon(Icons.account_tree_outlined, size: 16),
                  ),
                ],
                selected: {view},
                onSelectionChanged: (selection) {
                  onViewChanged(selection.single);
                },
              );

              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: SynSpacing.md),
                    control,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: SynSpacing.md),
                  control,
                ],
              );
            },
          ),
          const SizedBox(height: SynSpacing.md),
          if (error != null)
            SynNotice(
              icon: Icons.error_outline,
              title: 'Could not load topics',
              message: error.toString(),
              color: SynColors.red,
            )
          else if (data == null || data!.topics.isEmpty)
            const _InlineEmpty(
              icon: Icons.topic_outlined,
              title: 'No topic data yet',
              message:
                  'Topic summaries will appear after closed councils have tags.',
            )
          else if (view == _TopicView.clusters)
            _TopicClusters(data: data!)
          else
            _TopicSummaryList(data: data!),
        ],
      ),
    );
  }
}

class _TopicSummaryList extends StatelessWidget {
  final TopicAnalytics data;

  const _TopicSummaryList({required this.data});

  @override
  Widget build(BuildContext context) {
    final topics = data.topics;
    final maxCount = topics.fold<int>(
      0,
      (max, topic) => topic.count > max ? topic.count : max,
    );
    final total = topics.fold<int>(0, (sum, topic) => sum + topic.count);

    return Column(
      children: [
        for (final topic in topics)
          Padding(
            padding: const EdgeInsets.only(bottom: SynSpacing.sm),
            child: _TopicRow(
              topic: topic,
              maxCount: maxCount,
              totalCount: total,
            ),
          ),
      ],
    );
  }
}

class _TopicRow extends StatelessWidget {
  final TopicSummary topic;
  final int maxCount;
  final int totalCount;

  const _TopicRow({
    required this.topic,
    required this.maxCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final share = totalCount == 0 ? 0.0 : topic.count / totalCount;
    final bar = maxCount == 0 ? 0.0 : topic.count / maxCount;
    final avgConsensus = topic.avgConsensus;
    final meta = [
      '${topic.count} councils',
      '${(share * 100).round()}% share',
      if (avgConsensus != null)
        '${(avgConsensus * 100).round()}% avg consensus',
    ].join(' / ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                topic.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: SynSpacing.md),
            Text(
              meta,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: SynColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: SynSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: bar,
            minHeight: 6,
            backgroundColor: SynColors.surfaceRaised,
            valueColor: const AlwaysStoppedAnimation(SynColors.cyan),
          ),
        ),
      ],
    );
  }
}

class _TopicClusters extends StatelessWidget {
  final TopicAnalytics data;

  const _TopicClusters({required this.data});

  @override
  Widget build(BuildContext context) {
    final clusters = data.clusters.trim();
    if (clusters.isEmpty) {
      return const _InlineEmpty(
        icon: Icons.account_tree_outlined,
        title: 'No clusters returned',
        message: 'The topic clustering response was empty.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(clusters, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: SynSpacing.md),
        Wrap(
          spacing: SynSpacing.xs,
          runSpacing: SynSpacing.xs,
          children: [
            for (final topic in data.topics)
              _TopicChip(label: topic.label, count: topic.count),
          ],
        ),
        if (data.clusterSources.isNotEmpty) ...[
          const SizedBox(height: SynSpacing.md),
          Text(
            'Cluster sources',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: SynSpacing.xs),
          _JsonBlock(value: data.clusterSources),
        ],
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  final String label;
  final int count;

  const _TopicChip({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SynSpacing.sm,
        vertical: SynSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: SynColors.cyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SynRadii.pill),
        border: Border.all(color: SynColors.cyan.withValues(alpha: 0.32)),
      ),
      child: Text(
        '$label ($count)',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: SynColors.cyan),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SynSpacing.lg),
      decoration: BoxDecoration(
        color: SynColors.surfaceMuted,
        borderRadius: BorderRadius.circular(SynRadii.md),
        border: Border.all(color: SynColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: SynColors.textFaint, size: 24),
          const SizedBox(width: SynSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: SynSpacing.xs),
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: SynColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  final Object value;

  const _JsonBlock({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(SynSpacing.md),
      decoration: BoxDecoration(
        color: SynColors.surfaceMuted,
        borderRadius: BorderRadius.circular(SynRadii.md),
        border: Border.all(color: SynColors.border),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          const JsonEncoder.withIndent('  ').convert(value),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
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
