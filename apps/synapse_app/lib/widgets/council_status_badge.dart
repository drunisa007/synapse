import 'package:flutter/material.dart';

import '../ui/synapse_tokens.dart';

class CouncilStatusBadge extends StatelessWidget {
  final String status;

  const CouncilStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final style = synStatusStyle(status);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: SynSpacing.sm),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.1),
        border: Border.all(color: style.color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(SynRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 13, color: style.color),
          const SizedBox(width: SynSpacing.xs),
          Text(
            style.label,
            style: TextStyle(
              color: style.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
