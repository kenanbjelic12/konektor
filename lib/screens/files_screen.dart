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

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose files to upload',
    );
    final paths = picked.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    for (var i = 0; i < paths.length; i++) {
      final file = File(paths[i]);
      setState(
        () => _status =
            'Uploading ${file.uri.pathSegments.last} (${i + 1} of ${paths.length})',
      );
      try {
        await _storage.upload(file);
      } catch (e) {
        _showError('Upload failed for ${file.uri.pathSegments.last}: $e');
      }
    }
    setState(() => _status = null);
    await _refresh();
  }

  /// Folder chosen for the last download, reused as the next starting point.
  String? _lastFolder;

  Future<void> _download(CloudFile file) async {
    final folderUri = await FilePicker.pickDirectory(
      dialogTitle: 'Choose where to save ${file.name}',
      initialDirectory: _lastFolder,
    );
    if (folderUri == null || folderUri.scheme != 'file') return;
    final folder = folderUri.toFilePath();
    _lastFolder = folder;
    final target = File(_uniquePath(folder, file.name));
    setState(() => _status = 'Downloading ${file.name}');
    try {
      await _storage.download(file.name, target);
      _showMessage('Saved to ${target.path}');
    } catch (e) {
      _showError('Download failed: $e');
    } finally {
      if (mounted) setState(() => _status = null);
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
        bottom: busy || _loading
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
          if (_status != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_status!)),
          Expanded(child: _buildList()),
        ],
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
