import 'package:flutter/material.dart';
import '../core/api/models.dart';

/// Renders [council.deliberationRounds] as a list of expansion tiles. Empty
/// when the council ran in standard mode (the widget returns
/// SizedBox.shrink so callers don't need to gate the render site).
class DeliberationRoundsCard extends StatelessWidget {
  final List<DeliberationRound> rounds;

  const DeliberationRoundsCard({super.key, required this.rounds});

  @override
  Widget build(BuildContext context) {
    if (rounds.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Deliberation rounds',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${rounds.length} round${rounds.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...rounds.map((r) => _RoundTile(round: r)),
          ],
        ),
      ),
    );
  }
}

class _RoundTile extends StatelessWidget {
  final DeliberationRound round;

  const _RoundTile({required this.round});

  String get _modeLabel => switch (round.mode) {
    'red_team' => 'Red team',
    'deliberation' => 'Deliberation',
    _ => round.mode,
  };

  Color get _accent => switch (round.mode) {
    'red_team' => Colors.red,
    'deliberation' => Colors.deepPurple,
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
        color: _accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Row(
          children: [
            Text(
              '#${round.round}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(width: 8),
            Text(
              _modeLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (round.converged) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'converged',
                  style: TextStyle(fontSize: 10, color: Colors.greenAccent),
                ),
              ),
            ],
          ],
        ),
        children: [
          if (round.attacks.isNotEmpty)
            _CritiqueList(label: 'Attacks', items: round.attacks),
          if (round.critiques.isNotEmpty)
            _CritiqueList(label: 'Critiques', items: round.critiques),
          if (round.revisedResponses.isNotEmpty)
            _RevisedList(items: round.revisedResponses),
        ],
      ),
    );
  }
}

class _CritiqueList extends StatelessWidget {
  final String label;
  final List<MemberCritique> items;

  const _CritiqueList({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${label.toUpperCase()} (${items.length})',
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
          const SizedBox(height: 4),
          ...items.map(
            (c) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.memberName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (c.error != null)
                    Text(
                      'error: ${c.error}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.redAccent,
                      ),
                    )
                  else
                    Text(c.critique, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RevisedList extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const _RevisedList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'REVISED RESPONSES (${items.length})',
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
          const SizedBox(height: 4),
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final r = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (r['member'] as String?) ?? 'member ${i + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (r['content'] as String?) ?? '',
                    style: const TextStyle(fontSize: 12),
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
