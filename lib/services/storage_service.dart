import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// One file stored in the cloud.
class CloudFile {
  CloudFile({required this.name, this.size, this.updatedAt});

  final String name;
  final int? size;
  final DateTime? updatedAt;
}

class StorageException implements Exception {
  StorageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Manual upload / download against the Konektor PHP API (server/api.php)
/// running on your web hosting.
class StorageService {
  StorageService({required String apiUrl, required this.token})
    : _api = Uri.parse(apiUrl);

  final Uri _api;
  final String token;
  final http.Client _client = http.Client();

  Map<String, String> get _headers => {'X-Konektor-Token': token};

  Uri _uri(String action, [String? name]) =>
      _api.replace(queryParameters: {'action': action, 'name': ?name});

  Future<List<CloudFile>> list() async {
    final res = await _client.get(_uri('list'), headers: _headers);
    final body = _check(res.statusCode, res.body);
    final files = (body['files'] as List).cast<Map<String, dynamic>>();
    final result =
        files
            .map(
              (f) => CloudFile(
                name: f['name'] as String,
                size: (f['size'] as num?)?.toInt(),
                updatedAt: f['modified'] == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(
                        (f['modified'] as num).toInt() * 1000,
                      ),
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return result;
  }

  /// Uploads a local file. A cloud file with the same name is replaced.
  Future<void> upload(File file) async {
    final req = http.MultipartRequest('POST', _uri('upload'))
      ..headers.addAll(_headers)
      ..fields['name'] = p.basename(file.path)
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final res = await _client.send(req);
    _check(res.statusCode, await res.stream.bytesToString());
  }

  /// Streams a cloud file straight to [target] on disk.
  Future<void> download(String name, File target) async {
    final req = http.Request('GET', _uri('download', name))
      ..headers.addAll(_headers);
    final res = await _client.send(req);
    if (res.statusCode != 200) {
      _check(res.statusCode, await res.stream.bytesToString());
    }
    final sink = target.openWrite();
    try {
      await res.stream.pipe(sink);
    } catch (_) {
      await sink.close();
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  Future<void> delete(String name) async {
    final res = await _client.post(_uri('delete', name), headers: _headers);
    _check(res.statusCode, res.body);
  }

  Map<String, dynamic> _check(int status, String body) {
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}
    if (status == 200 && json != null) return json;
    final message =
        json?['error'] as String? ??
        'Server answered $status. Check the API address in config.json.';
    throw StorageException(message);
  }
}
