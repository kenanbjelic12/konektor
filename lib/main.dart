import 'package:flutter/material.dart';

import 'screens/files_screen.dart';
import 'screens/setup_screen.dart';
import 'services/settings.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(KonektorApp(initialSettings: await Settings.load()));
}

class KonektorApp extends StatefulWidget {
  const KonektorApp({super.key, this.initialSettings});

  final Settings? initialSettings;

  @override
  State<KonektorApp> createState() => _KonektorAppState();
}

class _KonektorAppState extends State<KonektorApp> {
  late Settings? _settings = widget.initialSettings;

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return MaterialApp(
      title: 'Konektor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: settings == null
          ? SetupScreen(onSaved: (s) => setState(() => _settings = s))
          : FilesScreen(
              key: ValueKey(settings),
              storage: StorageService(
                apiUrl: settings.apiUrl,
                token: settings.token,
              ),
              onOpenSettings: (context) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SetupScreen(
                    initial: settings,
                    onSaved: (s) {
                      Navigator.of(context).pop();
                      setState(() => _settings = s);
                    },
                  ),
                ),
              ),
            ),
    );
  }
}
