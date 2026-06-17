import 'package:flutter/material.dart';

import '../ui/synapse_tokens.dart';
import 'markdown_text.dart';

class VerdictCard extends StatelessWidget {
  final String? verdict;
  final double? consensusScore;
  final String? confidenceLabel;
  final bool dissentDetected;

  const VerdictCard({
    super.key,
    this.verdict,
    this.consensusScore,
    this.confidenceLabel,
    this.dissentDetected = false,
  });

  Color _scoreColor(double score) {
    if (score >= 0.7) return Colors.green;
    if (score >= 0.4) return Colors.amber;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.gavel, color: Color(0xFF6366F1), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Verdict',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF6366F1),
                  ),
                ),
                if (confidenceLabel != null) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      confidenceLabel!,
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ],
              ],
            ),
            if (verdict != null) ...[
              const SizedBox(height: 8),
              SynMarkdownText(data: verdict!, fontSize: 14),
            ],
            if (consensusScore != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Consensus',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: consensusScore!.clamp(0.0, 1.0),
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _scoreColor(consensusScore!),
                      ),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(consensusScore! * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: _scoreColor(consensusScore!),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            if (dissentDetected) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SynColors.amber.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: SynColors.amber, width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber, color: SynColors.amber, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Dissent detected',
                      style: TextStyle(color: SynColors.amber, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
