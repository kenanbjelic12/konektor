import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/storage_service.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({
    super.key,
    required this.storage,
    required this.onOpenSettings,
  });

  final StorageService storage;
  final void Function(BuildContext context) onOpenSettings;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  StorageService get _storage => widget.storage;
  List<CloudFile> _files = [];
  bool _loading = true;
  String? _status;

  /// 0..1 while a transfer is running, null when its size is unknown.
  double? _progress;
  String _progressText = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final files = await _storage.list();
      if (mounted) setState(() => _files = files);
    } catch (e) {
      _showError('Could not load files: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startTransfer(String status) => setState(() {
    _status = status;
    _progress = 0;
    _progressText = '';
  });

  void _endTransfer() {
    if (mounted) setState(() => _status = null);
  }

  /// Progress callback that only rebuilds when the shown percent changes.
  void _onProgress(int done, int? total) {
    if (!mounted) return;
    final value = total == null || total == 0 ? null : done / total;
    final text = total == null
        ? _formatSize(done)
        : '${_formatSize(done)} of ${_formatSize(total)}';
    if (value != null &&
        _progress != null &&
        (value * 100).floor() == (_progress! * 100).floor() &&
        value < 1) {
      return;
    }
    setState(() {
      _progress = value;
      _progressText = text;
    });
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose files to upload',
    );
    if (picked.isEmpty) return;
    for (var i = 0; i < picked.length; i++) {
      final file = picked[i];
      final count = picked.length > 1 ? ' (${i + 1} of ${picked.length})' : '';
      _startTransfer('Uploading ${file.name}$count');
      try {
        final length = await file.length();
        if (length == null) throw StorageException('Cannot read file size');
        await _storage.upload(
          name: file.name,
          length: length,
          data: file.readAsByteStream(),
          onProgress: _onProgress,
        );
      } catch (e) {
        _showError('Upload failed for ${file.name}: $e');
      }
    }
    _endTransfer();
    await _refresh();
  }

  /// Folder chosen for the last download, reused as the next starting point.
  String? _lastFolder;

  Future<void> _download(CloudFile file) async {
    final String folder;
    if (Platform.isAndroid) {
      folder = await _androidDownloadFolder() ?? '';
    } else {
      final folderUri = await FilePicker.pickDirectory(
        dialogTitle: 'Choose where to save ${file.name}',
        initialDirectory: _lastFolder,
      );
      if (folderUri == null || folderUri.scheme != 'file') return;
      folder = folderUri.toFilePath();
      _lastFolder = folder;
    }
    _startTransfer('Downloading ${file.name}');
    try {
      if (folder.isEmpty) {
        // Older Android: download to a temp file, then let the system
        // "save as" dialog put it where the user wants.
        final temp = File(p.join(Directory.systemTemp.path, file.name));
        await _storage.download(file.name, temp, onProgress: _onProgress);
        final saved = await FilePicker.saveFile(
          fileName: file.name,
          bytes: await temp.readAsBytes(),
        );
        await temp.delete();
        if (saved != null) _showMessage('Saved ${file.name}');
      } else {
        final target = File(_uniquePath(folder, file.name));
        await _storage.download(file.name, target, onProgress: _onProgress);
        _showMessage('Saved to ${target.path}');
      }
    } catch (e) {
      _showError('Download failed: $e');
    } finally {
      _endTransfer();
    }
  }

  /// Download/Konektor on the phone's shared storage. Android 11+ lets apps
  /// create files there without any permission. Returns null if not possible.
  static Future<String?> _androidDownloadFolder() async {
    try {
      final dir = Directory('/storage/emulated/0/Download/Konektor');
      await dir.create(recursive: true);
      final probe = File(p.join(dir.path, '.konektor-write-test'));
      await probe.writeAsString('ok');
      await probe.delete();
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  /// "report.pdf" becomes "report (1).pdf" if the folder already has one.
  static String _uniquePath(String folder, String name) {
    var candidate = p.join(folder, name);
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    for (var i = 1; File(candidate).existsSync(); i++) {
      candidate = p.join(folder, '$base ($i)$ext');
    }
    return candidate;
  }

  Future<void> _delete(CloudFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('${file.name} will be removed from the cloud.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _storage.delete(file.name);
      await _refresh();
    } catch (e) {
      _showError('Delete failed: $e');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _status != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konektor'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading || busy ? null : _refresh,
          ),
          IconButton(
            tooltip: 'Server settings',
            icon: const Icon(Icons.settings),
            onPressed: () => widget.onOpenSettings(context),
          ),
        ],
        bottom: !busy && _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : _upload,
        icon: const Icon(Icons.upload),
        label: const Text('Upload'),
      ),
      body: Column(
        children: [
          if (_status != null) _buildTransferCard(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildTransferCard() {
    final percent = _progress == null
        ? ''
        : '${(_progress! * 100).clamp(0, 100).toStringAsFixed(0)}%';
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_status!, overflow: TextOverflow.ellipsis),
                ),
                Text(percent, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            if (_progressText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_progressText, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_files.isEmpty) {
      return Center(
        child: Text(
          _loading ? 'Loading...' : 'No files yet. Press Upload to add some.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _files.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final f = _files[i];
        return ListTile(
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(f.name),
          subtitle: Text(
            [
              if (f.size != null) _formatSize(f.size!),
              if (f.updatedAt != null) _formatDate(f.updatedAt!.toLocal()),
            ].join('  ·  '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download),
                onPressed: _status != null ? null : () => _download(f),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _status != null ? null : () => _delete(f),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
