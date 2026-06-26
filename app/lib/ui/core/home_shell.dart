/// Root navigation shell: five top-level spaces + floating Capture button.
/// Nav bar is frosted glass (BackdropFilter) so content scrolls through it.
/// Phosphor icons: regular weight inactive, fill active.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../features/actions/views/actions_screen.dart';
import '../features/capture/views/capture_sheet.dart';
import '../features/catalog/views/catalog_screen.dart';
import '../features/collections/views/collections_screen.dart';
import '../features/library/views/library_screen.dart';
import '../features/profile/views/profile_screen.dart';
import 'brand.dart';
import 'theme.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          LibraryScreen(),
          CatalogScreen(),
          CollectionsScreen(),
          ActionsScreen(),
          ProfileScreen(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _CaptureButton(
        onTap: () => showCaptureSheet(context),
      ),
      bottomNavigationBar: _GlassNav(
        index: _index,
        onSelect: _select,
      ),
    );
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }
}

// ── Glass nav bar ─────────────────────────────────────────────────────────── //

class _GlassNav extends StatelessWidget {
  const _GlassNav({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    _NavDef(
      icon: PhosphorIconsRegular.house,
      activeIcon: PhosphorIconsFill.house,
      label: 'HOME',
    ),
    _NavDef(
      icon: PhosphorIconsRegular.books,
      activeIcon: PhosphorIconsFill.books,
      label: 'LIBRARY',
    ),
    _NavDef(
      icon: PhosphorIconsRegular.folder,
      activeIcon: PhosphorIconsFill.folder,
      label: 'FOLDERS',
    ),
    _NavDef(
      icon: PhosphorIconsRegular.listChecks,
      activeIcon: PhosphorIconsFill.listChecks,
      label: 'TO-DO',
    ),
    _NavDef(
      icon: PhosphorIconsRegular.user,
      activeIcon: PhosphorIconsFill.user,
      label: 'YOU',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Brand.glassFill(b),
            border: Border(
              top: BorderSide(
                color: Brand.glassBorder(b),
                width: 0.8,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: _NavBtn(
                        def: _items[i],
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
    );
  }
}

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
    final color =
        selected ? scheme.primary : scheme.onSurfaceVariant;

    return GestureDetector(
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
    );
  }
}

// ── Capture FAB ───────────────────────────────────────────────────────────── //

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
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
    );
  }
}
