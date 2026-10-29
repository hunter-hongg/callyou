class BackendConfig {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:40128',
  );

  static String get baseUrl => _baseUrl.replaceFirst(RegExp(r'/+$'), '');
}
