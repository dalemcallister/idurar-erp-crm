import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'progress_screen.dart';
import 'sessions_list_screen.dart';
import 'settings_screen.dart';

/// The five top-level areas (Design §5). Record is always one tap from the Home
/// tab, which is the default landing tab.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _tabs = [
    HomeScreen(),
    SessionsListScreen(),
    ProgressScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic),
              label: 'Record'),
          NavigationDestination(
              icon: Icon(Icons.list_alt), label: 'Sessions'),
          NavigationDestination(
              icon: Icon(Icons.trending_up), label: 'Progress'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
