import 'package:flutter/material.dart';

import '../utils/responsive_helper.dart';

/// Responsive shell wrapper for mobile/tablet/desktop.
///
/// Mobile: AppBar + Drawer.
/// Tablet/Desktop: Sidebar + content.
class AppShell extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? drawer;
  final Widget? sidebar;
  final List<Widget>? actions;
  final bool showTopBar;

  const AppShell({
    super.key,
    required this.title,
    required this.child,
    this.drawer,
    this.sidebar,
    this.actions,
    this.showTopBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);
    final theme = Theme.of(context);

    if (r.isMobile) {
      return Scaffold(
        backgroundColor: theme.colorScheme.background,
        appBar: AppBar(
          title: Text(title),
          elevation: 0,
          backgroundColor: theme.colorScheme.surface,
          actions: actions,
          scrolledUnderElevation: 0,
        ),
        drawer: drawer,
        body: SafeArea(child: child),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Row(
        children: [
          if (sidebar != null) sidebar!,
          Expanded(
            child: Column(
              children: [
                if (showTopBar)
                  _ShellTopBar(
                    title: title,
                    actions: actions,
                  ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellTopBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;

  const _ShellTopBar({
    required this.title,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);
    final theme = Theme.of(context);
    return Container(
      height: r.topBarHeight,
      padding: EdgeInsets.symmetric(horizontal: r.topBarHPad),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.6)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: r.titleFontSize,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}
