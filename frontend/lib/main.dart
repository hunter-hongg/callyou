import 'package:flutter/material.dart';

import 'api_client.dart';
import 'screens/login_page.dart';
import 'theme.dart';

void main() {
  runApp(CallYouApp(api: ApiClient()));
}

class CallYouApp extends StatelessWidget {
  const CallYouApp({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CallYou 课堂',
      debugShowCheckedModeBanner: false,
      theme: buildCallYouTheme(),
      home: LoginPage(api: api),
    );
  }
}
