import 'package:flutter/material.dart';

import '../ui/synapse_tokens.dart';

typedef DirectiveCallback = void Function();

class DirectiveInput extends StatefulWidget {
  final void Function(String text) onSend;
  final DirectiveCallback? onClose;
  final DirectiveCallback? onApprove;
  final void Function(String directive, String? arg)? onDirective;
  final bool readOnly;

  const DirectiveInput({
    super.key,
    required this.onSend,
    this.onClose,
    this.onApprove,
    this.onDirective,
    this.readOnly = false,
  });

  @override
  State<DirectiveInput> createState() => _DirectiveInputState();
}

class _DirectiveInputState extends State<DirectiveInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showDirectives = false;

  static const _directives = [
    _Directive('@close', 'Close the council'),
    _Directive('@approve', 'Approve the council'),
    _Directive('@redirect', 'Redirect to another council'),
    _Directive('@veto', 'Veto the current verdict'),
    _Directive('@add', 'Add a member'),
  ];

  void _handleChanged(String value) {
    final showMenu = value.contains('@') && !value.trimRight().contains(' ');
    if (showMenu != _showDirectives) {
      setState(() => _showDirectives = showMenu);
    }
  }

  void _selectDirective(_Directive directive) {
    _controller.text = directive.command;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() => _showDirectives = false);
    _focusNode.requestFocus();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (text == '@close') {
      widget.onClose?.call();
    } else if (text == '@approve') {
      widget.onApprove?.call();
    } else if (text.startsWith('@')) {
      final parts = text.split(' ');
      widget.onDirective?.call(
        parts[0],
        parts.length > 1 ? parts.sublist(1).join(' ') : null,
      );
    } else {
      widget.onSend(text);
    }

    _controller.clear();
    setState(() => _showDirectives = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showDirectives)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: SynSpacing.md),
            decoration: BoxDecoration(
              color: SynColors.surfaceRaised,
              border: Border.all(color: SynColors.borderStrong),
              borderRadius: BorderRadius.circular(SynRadii.lg),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _directives
                  .map(
                    (d) => InkWell(
                      onTap: () => _selectDirective(d),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SynSpacing.md,
                          vertical: SynSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Text(
                              d.command,
                              style: const TextStyle(
                                color: SynColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: SynSpacing.sm),
                            Text(
                              d.description,
                              style: const TextStyle(
                                color: SynColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(SynSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: _handleChanged,
                  onSubmitted: (_) => _handleSend(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message or @ for directives...',
                    prefixIcon: Icon(Icons.chat_bubble_outline),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                ),
              ),
              const SizedBox(width: SynSpacing.sm),
              IconButton(
                icon: const Icon(Icons.send),
                color: SynColors.primary,
                onPressed: _handleSend,
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Directive {
  final String command;
  final String description;
  const _Directive(this.command, this.description);
}
