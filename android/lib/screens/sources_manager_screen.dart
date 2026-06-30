import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/config_source.dart';
import '../services/source_storage.dart';
import '../theme/app_theme.dart';

/// A standalone page for managing subscription sources: view built-in
/// presets (read-only) and add/edit/delete user-defined sources with
/// their own alias. Reached from the options menu.
class SourcesManagerScreen extends StatefulWidget {
  const SourcesManagerScreen({super.key});

  @override
  State<SourcesManagerScreen> createState() => _SourcesManagerScreenState();
}

class _SourcesManagerScreenState extends State<SourcesManagerScreen> {
  List<ConfigSource> _userSources = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sources = await SourceStorage.loadUserSources();
    if (!mounted) return;
    setState(() {
      _userSources = sources;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await SourceStorage.saveUserSources(_userSources);
  }

  void _addOrEdit({ConfigSource? existing}) async {
    final result = await showModalBottomSheet<ConfigSource>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SourceEditSheet(existing: existing),
    );
    if (result == null) return;

    setState(() {
      if (existing != null) {
        final idx = _userSources.indexWhere((s) => s.id == existing.id);
        if (idx >= 0) _userSources[idx] = result;
      } else {
        _userSources.add(result);
      }
    });
    await _save();
  }

  void _delete(ConfigSource source) async {
    setState(() => _userSources.removeWhere((s) => s.id == source.id));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ext = Theme.of(context).extension<ProxySmithColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sourcesManagerTitle),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.sourcesBuiltInLabel,
                  style: TextStyle(fontSize: 11, color: ext.mutedText, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ...kBuiltInSources.map((s) => _sourceTile(s, ext, editable: false)),
                const SizedBox(height: 20),
                Text(
                  l10n.sourcesCustomLabel,
                  style: TextStyle(fontSize: 11, color: ext.mutedText, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                if (_userSources.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        l10n.sourcesEmptyHint,
                        style: TextStyle(color: ext.mutedText, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ..._userSources.map((s) => _sourceTile(s, ext, editable: true)),
                const SizedBox(height: 72), // room for the FAB
              ],
            ),
    );
  }

  Widget _sourceTile(ConfigSource source, ProxySmithColors ext, {required bool editable}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(source.label, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          source.url ?? '',
          style: TextStyle(fontSize: 11, color: ext.mutedText, fontFamily: 'monospace'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: editable
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _addOrEdit(existing: source),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onPressed: () => _delete(source),
                  ),
                ],
              )
            : const Icon(Icons.lock_outline_rounded, size: 16),
      ),
    );
  }
}

class _SourceEditSheet extends StatefulWidget {
  final ConfigSource? existing;
  const _SourceEditSheet({this.existing});

  @override
  State<_SourceEditSheet> createState() => _SourceEditSheetState();
}

class _SourceEditSheetState extends State<_SourceEditSheet> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.existing?.label ?? '');
    _urlCtrl = TextEditingController(text: widget.existing?.url ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _labelCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (label.isEmpty || url.isEmpty) return;

    final source = ConfigSource(
      label: label,
      url: url,
      isUserDefined: true,
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
    );
    Navigator.of(context).pop(source);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEdit ? l10n.sourcesEditTitle : l10n.sourcesAddTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _labelCtrl,
            decoration: InputDecoration(
              labelText: l10n.sourcesAliasLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: l10n.sourcesUrlLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: Text(isEdit ? l10n.sourcesSaveButton : l10n.sourcesAddButton),
          ),
        ],
      ),
    );
  }
}
