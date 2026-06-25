/// Root navigation shell: four top-level spaces — Library (your cards), Graph
/// (how they connect), Chat (ask AI), You (stats + settings) — with a prominent center
/// Capture button, the app's hero action. An IndexedStack keeps each tab's state alive.
library;

import 'package:flutter/material.dart';

import '../features/actions/views/actions_screen.dart';
import '../features/capture/views/capture_sheet.dart';
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
          LibraryChatScreen(),
          ProfileScreen(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _CaptureButton(onTap: () => showCaptureSheet(context)),
      bottomNavigationBar: BottomAppBar(
        height: 64,
        color: scheme.surface,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.video_library_outlined,
              activeIcon: Icons.video_library_rounded,
              label: 'Library',
              selected: _index == 0,
              onTap: () => _select(0),
            ),
            _NavItem(
              icon: Icons.checklist_rounded,
              activeIcon: Icons.checklist_rounded,
              label: 'To-do',
              selected: _index == 1,
              onTap: () => _select(1),
            ),
            const SizedBox(width: 72), // notch gap for the Capture button
            _NavItem(
              icon: Icons.forum_outlined,
              activeIcon: Icons.forum_rounded,
              label: 'Chat',
              selected: _index == 2,
              onTap: () => _select(2),
            ),
            _NavItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'You',
              selected: _index == 3,
              onTap: () => _select(3),
            ),
          ],
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          gradient: Brand.gradient,
          shape: BoxShape.circle,
          boxShadow: Brand.glow(opacity: 0.5, blur: 22, y: 8),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
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
    final color = selected ? Brand.violet : scheme.onSurfaceVariant;
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
              child: Icon(selected ? activeIcon : icon, color: color, size: 24),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
