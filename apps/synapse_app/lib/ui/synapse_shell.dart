import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'synapse_components.dart';
import 'synapse_navigation_history.dart';
import 'synapse_tokens.dart';

enum SynapseNavItem {
  councils,
  chat,
  memory,
  analytics,
  notifications,
  settings,
}

class SynapseWorkspaceFrame extends StatelessWidget {
  final SynapseNavItem selected;
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onBack;

  const SynapseWorkspaceFrame({
    super.key,
    required this.selected,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    if (_WorkspaceChromeScope.isMounted(context)) {
      return Column(
        children: [
          _TopBar(
            title: title,
            subtitle: subtitle,
            actions: actions,
            onBack: onBack,
            showProductMark: false,
          ),
          Expanded(
            child: Container(color: SynColors.appBgAlt, child: body),
          ),
        ],
      );
    }

    final size = MediaQuery.of(context).size;
    final compact = size.width < 760;
    final desktopChrome = Platform.isMacOS || Platform.isWindows;

    return Scaffold(
      backgroundColor: SynColors.appBg,
      body: SafeArea(
        child: Column(
          children: [
            if (desktopChrome) const _WindowTitleBar(),
            _TopBar(
              title: title,
              subtitle: subtitle,
              actions: actions,
              onBack: onBack,
              showProductMark: !desktopChrome,
            ),
            Expanded(
              child: Row(
                children: [
                  if (!compact) _Sidebar(selected: selected),
                  Expanded(
                    child: Container(color: SynColors.appBgAlt, child: body),
                  ),
                ],
              ),
            ),
            if (compact) _BottomNav(selected: selected),
          ],
        ),
      ),
    );
  }
}

class SynapseWorkspaceRoot extends StatelessWidget {
  final SynapseNavItem selected;
  final Widget child;

  const SynapseWorkspaceRoot({
    super.key,
    required this.selected,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final compact = size.width < 760;
    final desktopChrome = Platform.isMacOS || Platform.isWindows;

    return Scaffold(
      backgroundColor: SynColors.appBg,
      body: SafeArea(
        child: Column(
          children: [
            if (desktopChrome) const _WindowTitleBar(),
            Expanded(
              child: Row(
                children: [
                  if (!compact) _Sidebar(selected: selected),
                  Expanded(
                    child: _WorkspaceChromeScope(
                      child: Container(color: SynColors.appBgAlt, child: child),
                    ),
                  ),
                ],
              ),
            ),
            if (compact) _BottomNav(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceChromeScope extends InheritedWidget {
  const _WorkspaceChromeScope({required super.child});

  static bool isMounted(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WorkspaceChromeScope>() !=
      null;

  @override
  bool updateShouldNotify(_WorkspaceChromeScope oldWidget) => false;
}

class _TopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool showProductMark;

  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.onBack,
    required this.showProductMark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: SynColors.chrome,
        border: Border(bottom: BorderSide(color: SynColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: SynSpacing.lg),
      child: Row(
        children: [
          if (onBack != null) ...[
            SynIconButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              onPressed: onBack,
            ),
            const SizedBox(width: SynSpacing.md),
          ],
          if (showProductMark) ...[
            const _ProductMark(),
            const SizedBox(width: SynSpacing.lg),
            Container(width: 1, height: 24, color: SynColors.border),
            const SizedBox(width: SynSpacing.lg),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: SynSpacing.xxs),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: SynColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: SynSpacing.md),
          ...actions,
        ],
      ),
    );
  }
}

class _WindowTitleBar extends StatelessWidget {
  const _WindowTitleBar();

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: SynColors.appBg,
        border: Border(bottom: BorderSide(color: SynColors.border)),
      ),
      child: Row(
        children: [
          if (isMac) const SizedBox(width: 74),
          const _HistoryControls(),
          const SizedBox(width: SynSpacing.sm),
          const _WindowProductMark(),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: _toggleMaximize,
              child: const DragToMoveArea(
                child: SizedBox.expand(
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Synapse',
                      style: TextStyle(
                        color: SynColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (Platform.isWindows) const _WindowCaptionControls(),
          if (isMac) const SizedBox(width: SynSpacing.lg),
        ],
      ),
    );
  }

  static Future<void> _toggleMaximize() async {
    final isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }
}

class _HistoryControls extends StatelessWidget {
  const _HistoryControls();

  @override
  Widget build(BuildContext context) {
    final history = SynapseNavigationHistory.instance;
    return AnimatedBuilder(
      animation: history,
      builder: (context, _) {
        final router = GoRouter.of(context);
        return Row(
          children: [
            _WindowIconButton(
              icon: Icons.arrow_back_ios_new,
              tooltip: 'Back',
              onPressed: history.canGoBack
                  ? () => history.goBack(router)
                  : null,
            ),
            const SizedBox(width: SynSpacing.xs),
            _WindowIconButton(
              icon: Icons.arrow_forward_ios,
              tooltip: 'Forward',
              onPressed: history.canGoForward
                  ? () => history.goForward(router)
                  : null,
            ),
          ],
        );
      },
    );
  }
}

class _WindowProductMark extends StatelessWidget {
  const _WindowProductMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: SynColors.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(SynRadii.sm),
            border: Border.all(
              color: SynColors.primary.withValues(alpha: 0.32),
            ),
          ),
          child: const Icon(Icons.hub, size: 14, color: SynColors.primary),
        ),
        const SizedBox(width: SynSpacing.sm),
        Text(
          'Synapse',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: SynColors.text,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _WindowIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _WindowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 26,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 13),
          color: SynColors.textMuted,
          disabledColor: SynColors.textFaint.withValues(alpha: 0.45),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            hoverColor: SynColors.surfaceRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SynRadii.sm),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowCaptionControls extends StatefulWidget {
  const _WindowCaptionControls();

  @override
  State<_WindowCaptionControls> createState() => _WindowCaptionControlsState();
}

class _WindowCaptionControlsState extends State<_WindowCaptionControls>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() {});

  @override
  void onWindowUnmaximize() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        WindowCaptionButton.minimize(
          brightness: Brightness.dark,
          onPressed: () => windowManager.minimize(),
        ),
        FutureBuilder<bool>(
          future: windowManager.isMaximized(),
          builder: (context, snapshot) {
            if (snapshot.data == true) {
              return WindowCaptionButton.unmaximize(
                brightness: Brightness.dark,
                onPressed: () => windowManager.unmaximize(),
              );
            }
            return WindowCaptionButton.maximize(
              brightness: Brightness.dark,
              onPressed: () => windowManager.maximize(),
            );
          },
        ),
        WindowCaptionButton.close(
          brightness: Brightness.dark,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _ProductMark extends StatelessWidget {
  const _ProductMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: SynColors.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(SynRadii.md),
            border: Border.all(
              color: SynColors.primary.withValues(alpha: 0.34),
            ),
          ),
          child: const Icon(Icons.hub, size: 18, color: SynColors.primary),
        ),
        const SizedBox(width: SynSpacing.sm),
        Text('Synapse', style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  final SynapseNavItem selected;

  const _Sidebar({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: const BoxDecoration(
        color: SynColors.sidebar,
        border: Border(right: BorderSide(color: SynColors.border)),
      ),
      padding: const EdgeInsets.all(SynSpacing.md),
      child: Column(
        children: [
          _NavButton(
            item: SynapseNavItem.councils,
            selected: selected,
            icon: Icons.account_tree_outlined,
            label: 'Councils',
            route: '/councils',
          ),
          _NavButton(
            item: SynapseNavItem.chat,
            selected: selected,
            icon: Icons.forum_outlined,
            label: 'Assistant',
            route: '/chat/sessions',
          ),
          _NavButton(
            item: SynapseNavItem.memory,
            selected: selected,
            icon: Icons.storage_outlined,
            label: 'Memory',
            route: '/memory',
          ),
          _NavButton(
            item: SynapseNavItem.analytics,
            selected: selected,
            icon: Icons.analytics_outlined,
            label: 'Analytics',
            route: '/analytics',
          ),
          _NavButton(
            item: SynapseNavItem.notifications,
            selected: selected,
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            route: '/notifications',
          ),
          const Spacer(),
          _NavButton(
            item: SynapseNavItem.settings,
            selected: selected,
            icon: Icons.settings_outlined,
            label: 'Settings',
            route: '/settings',
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final SynapseNavItem selected;

  const _BottomNav({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: SynColors.chrome,
        border: Border(top: BorderSide(color: SynColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: SynSpacing.sm),
      child: Row(
        children: [
          _BottomNavButton(
            item: SynapseNavItem.councils,
            selected: selected,
            icon: Icons.account_tree_outlined,
            route: '/councils',
          ),
          _BottomNavButton(
            item: SynapseNavItem.chat,
            selected: selected,
            icon: Icons.forum_outlined,
            route: '/chat/sessions',
          ),
          _BottomNavButton(
            item: SynapseNavItem.memory,
            selected: selected,
            icon: Icons.storage_outlined,
            route: '/memory',
          ),
          _BottomNavButton(
            item: SynapseNavItem.settings,
            selected: selected,
            icon: Icons.settings_outlined,
            route: '/settings',
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final SynapseNavItem item;
  final SynapseNavItem selected;
  final IconData icon;
  final String label;
  final String route;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.icon,
    required this.label,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final active = item == selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: SynSpacing.xs),
      child: Material(
        color: active
            ? SynColors.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(SynRadii.lg),
        child: InkWell(
          onTap: active ? null : () => context.go(route),
          borderRadius: BorderRadius.circular(SynRadii.lg),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: SynSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SynRadii.lg),
              border: active
                  ? Border.all(color: SynColors.primary.withValues(alpha: 0.28))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: active ? SynColors.primary : SynColors.textMuted,
                ),
                const SizedBox(width: SynSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: active ? SynColors.text : SynColors.textMuted,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  final SynapseNavItem item;
  final SynapseNavItem selected;
  final IconData icon;
  final String route;

  const _BottomNavButton({
    required this.item,
    required this.selected,
    required this.icon,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final active = item == selected;
    return Expanded(
      child: IconButton(
        onPressed: active ? null : () => context.go(route),
        icon: Icon(icon, size: 20),
        color: active ? SynColors.primary : SynColors.textMuted,
      ),
    );
  }
}
