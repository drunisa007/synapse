import 'package:flutter/material.dart';

import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';

/// W4 / B12 — Astrocyte memory search.
///
/// Lets the user query a bank (decisions / precedents / councils) and
/// view the top hits. Score is rendered as a horizontal bar so quality
/// of match is glanceable.
class MemoryScreen extends StatefulWidget {
  final SynapseApiClient apiClient;
  const MemoryScreen({super.key, required this.apiClient});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _queryCtrl = TextEditingController();
  String _bank = 'decisions';
  Future<List<MemoryHit>>? _future;

  @override
  void initState() {
    super.initState();
    _queryCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _search() {
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _future = widget.apiClient.searchMemory(q, bank: _bank, limit: 20);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SynSurface(
          margin: const EdgeInsets.fromLTRB(
            SynSpacing.xl,
            SynSpacing.lg,
            SynSpacing.xl,
            SynSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryCtrl,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Search past decisions, precedents...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _queryCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _queryCtrl.clear();
                              setState(() => _future = null);
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: SynSpacing.md),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  initialValue: _bank,
                  decoration: const InputDecoration(labelText: 'Bank'),
                  onChanged: (v) {
                    if (v != null) setState(() => _bank = v);
                  },
                  items: const [
                    DropdownMenuItem(
                      value: 'decisions',
                      child: Text('Decisions'),
                    ),
                    DropdownMenuItem(
                      value: 'precedents',
                      child: Text('Precedents'),
                    ),
                    DropdownMenuItem(
                      value: 'councils',
                      child: Text('Councils'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SynSpacing.md),
              FilledButton.icon(
                onPressed: _queryCtrl.text.trim().isEmpty ? null : _search,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Search'),
              ),
            ],
          ),
        ),
        Expanded(child: _resultsView()),
      ],
    );
  }

  Widget _resultsView() {
    if (_future == null) {
      return const SynEmptyState(
        icon: Icons.manage_search,
        title: 'Search memory',
        message:
            'Query stored decisions, precedent notes, and council records.',
      );
    }

    return FutureBuilder<List<MemoryHit>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return SynErrorState(
            title: 'Memory search failed',
            message: snapshot.error.toString(),
            onRetry: _search,
          );
        }
        final hits = snapshot.data ?? [];
        if (hits.isEmpty) {
          return const SynEmptyState(
            icon: Icons.search_off,
            title: 'No matches',
            message: 'Try a broader query or switch the memory bank.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            SynSpacing.xl,
            SynSpacing.sm,
            SynSpacing.xl,
            SynSpacing.xl,
          ),
          itemCount: hits.length,
          separatorBuilder: (_, __) => const SizedBox(height: SynSpacing.sm),
          itemBuilder: (context, i) => _HitTile(hit: hits[i]),
        );
      },
    );
  }
}

class _HitTile extends StatelessWidget {
  final MemoryHit hit;
  const _HitTile({required this.hit});

  @override
  Widget build(BuildContext context) {
    final pct = (hit.score * 100).round();
    Color barColour;
    if (hit.score >= 0.7) {
      barColour = SynColors.green;
    } else if (hit.score >= 0.4) {
      barColour = SynColors.amber;
    } else {
      barColour = SynColors.textFaint;
    }

    return SynSurface(
      padding: const EdgeInsets.all(SynSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                hit.bankId,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: SynColors.textFaint),
              ),
              const Spacer(),
              Text(
                '$pct% match',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: barColour),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: hit.score.clamp(0, 1),
              minHeight: 3,
              backgroundColor: SynColors.surfaceRaised,
              valueColor: AlwaysStoppedAnimation(barColour),
            ),
          ),
          const SizedBox(height: 8),
          Text(hit.content, style: Theme.of(context).textTheme.bodyMedium),
          if (hit.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: hit.tags
                  .map(
                    (t) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: SynColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        t,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
