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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sourcesDeleteTitle),
        content: Text(l10n.sourcesDeleteBody(source.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelSelection),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.sourcesDeleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final index = _userSources.indexWhere((item) => item.id == source.id);
    if (index < 0) return;
    setState(() => _userSources.removeAt(index));
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.sourcesDeleted(source.label)),
        action: SnackBarAction(
          label: l10n.undoButton,
          onPressed: () {
            setState(
              () => _userSources.insert(
                index.clamp(0, _userSources.length),
                source,
              ),
            );
            _save();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ext = Theme.of(context).extension<ProxySmithColors>()!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sourcesManagerTitle), elevation: 0),
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
                  style: TextStyle(
                    fontSize: 11,
                    color: ext.mutedText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ...kBuiltInSources.map(
                  (s) => _sourceTile(s, ext, editable: false),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.sourcesCustomLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: ext.mutedText,
                    fontWeight: FontWeight.w500,
                  ),
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
                  ..._userSources.map(
                    (s) => _sourceTile(s, ext, editable: true),
                  ),
                const SizedBox(height: 72), // room for the FAB
              ],
            ),
    );
  }

  Widget _sourceTile(
    ConfigSource source,
    ProxySmithColors ext, {
    required bool editable,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(source.label, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          source.url ?? '',
          style: TextStyle(
            fontSize: 11,
            color: ext.mutedText,
            fontFamily: 'monospace',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: editable
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: AppLocalizations.of(context).sourcesEditTitle,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _addOrEdit(existing: source),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context).sourcesDeleteButton,
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
  bool _submitted = false;

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
    final parsed = Uri.tryParse(url);
    if (label.isEmpty ||
        parsed == null ||
        parsed.host.isEmpty ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      setState(() => _submitted = true);
      return;
    }

    final source = ConfigSource(
      label: label,
      url: url,
      isUserDefined: true,
      id:
          widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
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
              errorText: _submitted && _labelCtrl.text.trim().isEmpty
                  ? l10n.sourcesNameRequired
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: l10n.sourcesUrlLabel,
              errorText: _submitted && !_validUrl(_urlCtrl.text)
                  ? l10n.sourcesUrlInvalid
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: Text(
              isEdit ? l10n.sourcesSaveButton : l10n.sourcesAddButton,
            ),
          ),
        ],
      ),
    );
  }

  bool _validUrl(String value) {
    final parsed = Uri.tryParse(value.trim());
    return parsed != null &&
        parsed.host.isNotEmpty &&
        (parsed.scheme == 'http' || parsed.scheme == 'https');
  }
}
