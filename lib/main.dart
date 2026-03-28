import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/analytics_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/garden_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';
import 'sqlite_ffi_stub.dart' if (dart.library.io) 'sqlite_ffi_io.dart'
    as sqlite_ffi;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  sqlite_ffi.configureSqliteFfi();
  runApp(const SmartGardenApp());
}

class SmartGardenApp extends StatelessWidget {
  const SmartGardenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationsProvider()..load(),
        ),
        ChangeNotifierProxyProvider<SettingsProvider, GardenProvider>(
          create: (_) => GardenProvider(),
          update: (_, settings, previous) {
            final g = previous ?? GardenProvider();
            g.attachSettings(settings);
            return g;
          },
        ),
        ChangeNotifierProxyProvider<SettingsProvider, ChatProvider>(
          create: (_) => ChatProvider(),
          update: (_, settings, previous) {
            final c = previous ?? ChatProvider();
            c.attachSettings(settings);
            return c;
          },
        ),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
      ],
      child: MaterialApp(
        title: 'Smart Garden',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const MainShell(),
      ),
    );
  }
}
