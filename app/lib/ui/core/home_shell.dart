/// Root navigation shell: five top-level spaces — Library (your cards), To-do
/// (actions followed off reels), Catalog (referenced artifacts), Chat (ask AI),
/// You (stats + settings) — with a floating corner Capture button. An IndexedStack
/// keeps each tab's state alive. Editorial chrome: a flat bar with a hairline
/// top rule, ink/rust icons, and mono labels.
library;

import 'package:flutter/material.dart';

import '../features/actions/views/actions_screen.dart';
import '../features/capture/views/capture_sheet.dart';
import '../features/catalog/views/catalog_screen.dart';
import '../features/library/views/library_chat_screen.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          LibraryScreen(),
          ActionsScreen(),
          CatalogScreen(),
          LibraryChatScreen(),
          ProfileScreen(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _CaptureButton(onTap: () => showCaptureSheet(context)),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: BottomAppBar(
          height: 66,
          color: scheme.surface,
          elevation: 0,
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.collections_bookmark_outlined,
                activeIcon: Icons.collections_bookmark_rounded,
                label: 'LIBRARY',
                selected: _index == 0,
                onTap: () => _select(0),
              ),
              _NavItem(
                icon: Icons.checklist_rounded,
                activeIcon: Icons.checklist_rounded,
                label: 'TO-DO',
                selected: _index == 1,
                onTap: () => _select(1),
              ),
              _NavItem(
                icon: Icons.category_outlined,
                activeIcon: Icons.category_rounded,
                label: 'CATALOG',
                selected: _index == 2,
                onTap: () => _select(2),
              ),
              _NavItem(
                icon: Icons.forum_outlined,
                activeIcon: Icons.forum_rounded,
                label: 'CHAT',
                selected: _index == 3,
                onTap: () => _select(3),
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'YOU',
                selected: _index == 4,
                onTap: () => _select(4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 3),
          boxShadow: Brand.softShadow(opacity: 0.18, blur: 14, y: 5),
        ),
        child: Icon(Icons.add_rounded, color: scheme.onPrimary, size: 30),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.12 : 1.0,
              duration: Motion.fast,
              curve: Motion.spring,
              child: Icon(selected ? activeIcon : icon, color: color, size: 23),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: Brand.label(
                size: 9,
                color: color,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
