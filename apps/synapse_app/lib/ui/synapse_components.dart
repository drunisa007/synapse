import 'package:flutter/material.dart';

import 'synapse_tokens.dart';

class SynSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? color;
  final BorderSide? side;
  final bool selected;
  final VoidCallback? onTap;

  const SynSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SynSpacing.lg),
    this.margin,
    this.width,
    this.height,
    this.color,
    this.side,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderSide =
        side ??
        BorderSide(
          color: selected
              ? SynColors.primary.withValues(alpha: 0.7)
              : SynColors.border,
        );
    final surface = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? SynColors.surface,
        borderRadius: BorderRadius.circular(SynRadii.lg),
        border: Border.all(color: borderSide.color, width: borderSide.width),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return surface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SynRadii.lg),
          child: surface,
        ),
      ),
    );
  }
}

class SynIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  const SynIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? SynColors.primaryStrong
        : SynColors.surfaceRaised;
    final foreground = selected ? Colors.white : SynColors.textMuted;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: SizedBox.square(
        dimension: 34,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          color: foreground,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: background,
            disabledBackgroundColor: SynColors.surfaceMuted,
            disabledForegroundColor: SynColors.textFaint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SynRadii.md),
              side: const BorderSide(color: SynColors.border),
            ),
          ),
        ),
      ),
    );
  }
}

class SynEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const SynEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(SynSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: SynColors.textFaint),
              const SizedBox(height: SynSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: SynSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: SynColors.textMuted),
              ),
              if (action != null) ...[
                const SizedBox(height: SynSpacing.xl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SynErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const SynErrorState({
    super.key,
    this.title = 'Something failed',
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SynSurface(
          color: SynColors.red.withValues(alpha: 0.08),
          side: BorderSide(color: SynColors.red.withValues(alpha: 0.42)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 38, color: SynColors.red),
              const SizedBox(height: SynSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: SynSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: SynColors.textMuted),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: SynSpacing.lg),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SynNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final Widget? action;

  const SynNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color = SynColors.cyan,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return SynSurface(
      color: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.36)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
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
          if (action != null) ...[
            const SizedBox(width: SynSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

class SynMetaRow extends StatelessWidget {
  final String label;
  final String value;

  const SynMetaRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: SynColors.textFaint),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
