import 'package:flutter/material.dart';

class ConflictBanner extends StatefulWidget {
  final Map<String, dynamic>? conflictMetadata;
  final String councilStatus;
  final VoidCallback? onApprove;

  const ConflictBanner({
    super.key,
    this.conflictMetadata,
    required this.councilStatus,
    this.onApprove,
  });

  @override
  State<ConflictBanner> createState() => _ConflictBannerState();
}

class _ConflictBannerState extends State<ConflictBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(20),
        border: Border.all(color: Colors.amber, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    color: Colors.amber,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Conflict detected with prior decision',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.conflictMetadata != null)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.amber,
                      size: 18,
                    ),
                  if (widget.councilStatus == 'pending_approval' &&
                      widget.onApprove != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: widget.onApprove,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.amber,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Approve'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && widget.conflictMetadata != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.conflictMetadata!.entries
                    .map(
                      (e) => Text(
                        '${e.key}: ${e.value}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
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
