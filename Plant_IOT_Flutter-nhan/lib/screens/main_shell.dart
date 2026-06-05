import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/garden_provider.dart';
import 'analytics_screen.dart';
import 'chat_screen.dart';
import 'control_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _pages = <Widget>[
    DashboardScreen(),
    ControlScreen(),
    ChatScreen(),
    AnalyticsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == 3) {
            context.read<GardenProvider>().refreshWaterTodayCount();
          }
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration: Duration.zero,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined, size: 20),
            selectedIcon: Icon(Icons.grid_view_rounded, size: 20),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined, size: 20),
            selectedIcon: Icon(Icons.tune_rounded, size: 20),
            label: 'Điều khiển',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined, size: 20),
            selectedIcon: Icon(Icons.smart_toy_rounded, size: 20),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined, size: 20),
            selectedIcon: Icon(Icons.show_chart_rounded, size: 20),
            label: 'Biểu đồ',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, size: 20),
            selectedIcon: Icon(Icons.settings_rounded, size: 20),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}
