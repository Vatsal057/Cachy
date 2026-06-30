/// Root navigation shell — responsive.
/// < 600 dp : floating pill bottom nav (mobile / Android).
/// ≥ 600 dp : glass side rail, compact; ≥ 1100 dp : extended with labels.
/// Phosphor icons: regular inactive, fill active.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../features/actions/views/actions_screen.dart';
import '../features/capture/views/capture_sheet.dart';
import '../features/catalog/views/catalog_screen.dart';
import '../features/collections/views/collections_screen.dart';
import '../features/library/views/library_screen.dart';
import '../features/profile/views/profile_screen.dart';
import 'brand.dart';
import 'theme.dart';
import 'widgets/glass.dart';

// ── Shared nav definitions ─────────────────────────────────────────────────── //

class _NavDef {
  const _NavDef({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final PhosphorIconData icon;
  final PhosphorIconData activeIcon;
  final String label;
}

const _navItems = [
  _NavDef(icon: PhosphorIconsRegular.house,      activeIcon: PhosphorIconsFill.house,      label: 'HOME'),
  _NavDef(icon: PhosphorIconsRegular.books,      activeIcon: PhosphorIconsFill.books,      label: 'LIBRARY'),
  _NavDef(icon: PhosphorIconsRegular.folder,     activeIcon: PhosphorIconsFill.folder,     label: 'FOLDERS'),
  _NavDef(icon: PhosphorIconsRegular.listChecks, activeIcon: PhosphorIconsFill.listChecks, label: 'TO-DO'),
  _NavDef(icon: PhosphorIconsRegular.user,       activeIcon: PhosphorIconsFill.user,       label: 'YOU'),
];

// ── Shell ──────────────────────────────────────────────────────────────────── //

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    LibraryScreen(),
    CatalogScreen(),
    CollectionsScreen(),
    ActionsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => showCaptureSheet(context),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => showCaptureSheet(context),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () => _select(0),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => _select(0),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () => _select(1),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => _select(1),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () => _select(2),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => _select(2),
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () => _select(3),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => _select(3),
        const SingleActivator(LogicalKeyboardKey.digit5, meta: true): () => _select(4),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () => _select(4),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (_, constraints) => constraints.maxWidth >= Insets.desktop
              ? _desktopShell(context)
              : _mobileShell(context),
        ),
      ),
    );
  }

  Widget _mobileShell(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          IndexedStack(index: _index, children: _screens),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _CaptureButton(
        onTap: () => showCaptureSheet(context),
      ),
      bottomNavigationBar: _GlassNav(index: _index, onSelect: _select),
    );
  }

  Widget _desktopShell(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          Positioned.fill(
            child: Row(
              children: [
                _GlassRail(
                  index: _index,
                  onSelect: _select,
                  onCapture: () => showCaptureSheet(context),
                ),
                Expanded(
                  child: IndexedStack(index: _index, children: _screens),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }
}

// ── Desktop glass side rail ────────────────────────────────────────────────── //

class _GlassRail extends StatelessWidget {
  const _GlassRail({
    required this.index,
    required this.onSelect,
    required this.onCapture,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final extended = width >= 1100;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Brand.glassFill(b),
            border: Border(
              right: BorderSide(color: Brand.glassBorder(b), width: 0.8),
            ),
          ),
          child: SafeArea(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: index,
              onDestinationSelected: onSelect,
              extended: extended,
              minWidth: 72,
              minExtendedWidth: 180,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.selected,
              selectedIconTheme: IconThemeData(color: scheme.primary),
              unselectedIconTheme:
                  IconThemeData(color: scheme.onSurfaceVariant),
              selectedLabelTextStyle: Brand.label(
                size: 10,
                color: scheme.primary,
                weight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
              unselectedLabelTextStyle: Brand.label(
                size: 10,
                color: scheme.onSurfaceVariant,
                weight: FontWeight.w500,
                letterSpacing: 0.7,
              ),
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                child: _CaptureButton(onTap: onCapture),
              ),
              destinations: [
                for (final item in _navItems)
                  NavigationRailDestination(
                    icon: PhosphorIcon(item.icon, size: 22),
                    selectedIcon: PhosphorIcon(item.activeIcon, size: 22),
                    label: Text(item.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mobile floating pill nav ───────────────────────────────────────────────── //

class _GlassNav extends StatelessWidget {
  const _GlassNav({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.13),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.07),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Brand.glassFill(b),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Brand.glassBorder(b), width: 0.8),
              ),
              child: SizedBox(
                height: 64,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _navItems.length; i++)
                      Expanded(
                        child: _NavBtn(
                          def: _navItems[i],
                          selected: index == i,
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.def,
    required this.selected,
    required this.onTap,
  });
  final _NavDef def;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.10 : 1.0,
              duration: Motion.fast,
              curve: Motion.spring,
              child: PhosphorIcon(
                selected ? def.activeIcon : def.icon,
                size: 22,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              def.label,
              style: Brand.label(
                size: 9,
                color: color,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Capture button (shared: FAB on mobile, rail leading on desktop) ─────────── //

class _CaptureButton extends StatefulWidget {
  const _CaptureButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.08 : 1.0,
          duration: Motion.fast,
          curve: Motion.spring,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: _hovered ? 0.45 : 0.28),
                  blurRadius: _hovered ? 44 : 36,
                  spreadRadius: _hovered ? 8 : 6,
                ),
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: PhosphorIcon(
              PhosphorIconsRegular.plus,
              color: scheme.onPrimary,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
