import 'package:flutter/material.dart';

import '../calendar/calendar_page.dart';
import '../home/home_page.dart';
import '../settings/settings_page.dart';

/// 地区設定が済んだあとの本体。ホーム・カレンダー・設定の3タブ。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [HomePage(), CalendarPage(), SettingsPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack にしてカレンダーの表示月をタブ移動で失わないようにする。
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'カレンダー',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
