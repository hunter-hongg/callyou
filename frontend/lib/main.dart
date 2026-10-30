import 'package:flutter/material.dart';

import 'api_client.dart';
import 'desktop_tray.dart';
import 'screens/login_page.dart';
import 'theme.dart';

const _appTitle = 'CallYou 课堂';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await installDesktopTray(title: _appTitle);
  runApp(CallYouApp(api: ApiClient()));
}

class CallYouApp extends StatelessWidget {
  const CallYouApp({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildCallYouTheme(),
      home: LoginPage(api: api),
    );
  }
}
