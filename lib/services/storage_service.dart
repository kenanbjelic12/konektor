import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One file stored in the cloud.
class CloudFile {
  CloudFile({required this.name, this.size, this.updatedAt});

  final String name;
  final int? size;
  final DateTime? updatedAt;
}

/// Called with bytes done so far and the total (null when unknown).
typedef ProgressCallback = void Function(int done, int? total);

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

  /// Uploads [length] bytes from [data] as [name]. A cloud file with the
  /// same name is replaced. [onProgress] gets the bytes sent so far.
  Future<void> upload({
    required String name,
    required int length,
    required Stream<List<int>> data,
    ProgressCallback? onProgress,
  }) async {
    var sent = 0;
    final counted = data.map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent, length);
      return chunk;
    });
    final req = http.MultipartRequest('POST', _uri('upload'))
      ..headers.addAll(_headers)
      ..fields['name'] = name
      ..files.add(http.MultipartFile('file', counted, length, filename: name));
    final res = await _client.send(req);
    _check(res.statusCode, await res.stream.bytesToString());
  }

  /// Streams a cloud file straight to [target] on disk.
  /// [onProgress] gets the bytes received so far and the total size.
  Future<void> download(
    String name,
    File target, {
    ProgressCallback? onProgress,
  }) async {
    final req = http.Request('GET', _uri('download', name))
      ..headers.addAll(_headers);
    final res = await _client
        .send(req)
        .timeout(
          _stallTimeout,
          onTimeout: () => throw StorageException(
            'The server did not answer within ${_stallTimeout.inSeconds} s.',
          ),
        );
    if (res.statusCode != 200) {
      _check(res.statusCode, await res.stream.bytesToString());
    }
    final total = res.contentLength;
    var received = 0;
    onProgress?.call(0, total);
    final sink = target.openWrite();
    try {
      await res.stream
          .timeout(
            _stallTimeout,
            onTimeout: (sink) => sink.addError(
              StorageException(
                'Download stopped: no data for ${_stallTimeout.inSeconds} s.',
              ),
            ),
          )
          .map((chunk) {
            received += chunk.length;
            onProgress?.call(received, total);
            return chunk;
          })
          .pipe(sink);
      if (total != null && received != total) {
        throw StorageException(
          'Download incomplete: got $received of $total bytes.',
        );
      }
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  static const _stallTimeout = Duration(seconds: 30);

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
        (status == 404
            ? 'api.php was not found at ${_api.origin}${_api.path} (404). '
                  'Check that api.php is in that folder on your hosting.'
            : 'Server answered $status. Check the server address.');
    throw StorageException(message);
  }
}
