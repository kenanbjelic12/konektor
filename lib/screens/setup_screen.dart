import 'package:flutter/material.dart';

import '../services/settings.dart';
import '../services/storage_service.dart';

/// Asks for the server address and token, checks them, and saves them.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.initial, required this.onSaved});

  final Settings? initial;
  final ValueChanged<Settings> onSaved;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final _url = TextEditingController(text: widget.initial?.apiUrl ?? '');
  late final _token = TextEditingController(text: widget.initial?.token ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    var url = _url.text.trim();
    if (!url.startsWith('http')) url = 'https://$url';
    if (!url.endsWith('.php')) {
      url = '${url.replaceAll(RegExp(r'/+$'), '')}/api.php';
    }
    final settings = Settings(apiUrl: url, token: _token.text.trim());
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // A list request proves both the address and the token are right.
      await StorageService(
        apiUrl: settings.apiUrl,
        token: settings.token,
      ).list();
      await settings.save();
      widget.onSaved(settings);
    } catch (e) {
      setState(() => _error = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.initial == null
          ? null
          : AppBar(title: const Text('Server settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.cloud_sync,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Konektor',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: 'Server address',
                    hintText: 'https://yourdomain.com/konektor',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _token,
                  decoration: const InputDecoration(
                    labelText: 'Token (from config.php)',
                  ),
                  obscureText: true,
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: const Text('Connect'),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
