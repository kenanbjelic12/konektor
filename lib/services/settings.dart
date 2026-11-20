import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Server address and token, saved on this device only.
class Settings {
  const Settings({required this.apiUrl, required this.token});

  final String apiUrl;
  final String token;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'settings.json'));
  }

  static Future<Settings?> load() async {
    try {
      final json = jsonDecode(
        await (await _file()).readAsString(),
      ) as Map<String, dynamic>;
      final url = json['apiUrl'] as String? ?? '';
      final token = json['token'] as String? ?? '';
      if (url.isEmpty || token.isEmpty) return null;
      return Settings(apiUrl: url, token: token);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'apiUrl': apiUrl, 'token': token}));
  }
}
