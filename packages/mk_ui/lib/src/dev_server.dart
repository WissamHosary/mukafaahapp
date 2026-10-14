import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Small "Server: …" link shown only in test builds. Lets the tester point
/// the app at the PC's current Wi-Fi address without rebuilding the app.
class MkDevServerButton extends StatefulWidget {
  const MkDevServerButton({
    required this.load,
    required this.save,
    this.onDark = true,
    super.key,
  });

  /// Returns the address currently in use.
  final Future<String> Function() load;

  /// Saves an address and returns whether the server answered.
  final Future<bool> Function(String address) save;
  final bool onDark;

  @override
  State<MkDevServerButton> createState() => _MkDevServerButtonState();
}

class _MkDevServerButtonState extends State<MkDevServerButton> {
  String? _current;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final v = await widget.load();
    if (mounted) setState(() => _current = v);
  }

  String _short(String url) => url.replaceFirst(RegExp('^https?://'), '');

  Future<void> _edit() async {
    final ctl = TextEditingController(text: _current == null ? '' : _short(_current!));
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Type your laptop's Wi-Fi address (from ipconfig), e.g. 192.168.1.5"),
            const SizedBox(height: MkSpace.md),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: '192.168.1.5:3000'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (value == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Checking the server...')));
    final ok = await widget.save(value);
    await _refresh();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Connected to ${_short(_current ?? value)}'
                : "Can't reach ${_short(_current ?? value)} - check the address, the Wi-Fi and the PC firewall",
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.onDark ? Colors.white70 : Colors.black54;
    return Center(
      child: TextButton.icon(
        onPressed: _edit,
        icon: Icon(Icons.dns_rounded, size: 16, color: color),
        label: Text(
          'Server: ${_current == null ? '...' : _short(_current!)}',
          style: TextStyle(color: color, fontSize: 12),
        ),
      ),
    );
  }
}
