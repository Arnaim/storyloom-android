import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/database.dart';
import '../data/settings.dart';
import '../data/story_export.dart';
import '../engine/gemini_api.dart';
import '../models/story.dart';

/// Settings: API key, model, generation sliders, memory, appearance, data.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings _draft;
  late final TextEditingController _keyController;
  late final TextEditingController _modelController;
  bool _testing = false;
  String? _testResult;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _draft = _clone(app.settings);
    _keyController = TextEditingController(text: _draft.apiKey);
    _modelController = TextEditingController(text: _draft.model);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  static AppSettings _clone(AppSettings s) => AppSettings(
        apiKey: s.apiKey,
        model: s.model,
        temperature: s.temperature,
        maxOutputTokens: s.maxOutputTokens,
        contextMessages: s.contextMessages,
        autoMemory: s.autoMemory,
        summarizeEveryTurns: s.summarizeEveryTurns,
        maxSuggestions: s.maxSuggestions,
        darkMode: s.darkMode,
      );

  void _set(void Function(AppSettings) mutate) {
    setState(() => mutate(_draft));
  }

  bool _isKnownModel(String model) {
    if (_draft.providerType == 'gemini') {
      return supportedGeminiModels.contains(model);
    } else if (_draft.providerType == 'openrouter') {
      return supportedOpenRouterModels.contains(model);
    } else if (_draft.providerType == 'groq') {
      return supportedGroqModels.contains(model);
    } else if (_draft.providerType == 'deepseek') {
      return supportedDeepseekModels.contains(model);
    }
    return false;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context.read<AppState>().saveSettings(_draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _testResult = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved.')));
    Navigator.of(context).pop();
  }

  Future<void> _testConnection() async {
    final key = _draft.apiKey.trim();
    if (key.isEmpty) {
      setState(() => _testResult = 'Enter an API key first.');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final tmp = GeminiService(settings: _draft);
    try {
      final result = await tmp.testConnection();
      if (!mounted) return;
      setState(() => _testResult = result);
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _testResult = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _section(
            'API Provider',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: DropdownButtonFormField<String>(
                  initialValue: supportedProviders.contains(_draft.providerType)
                      ? _draft.providerType
                      : 'gemini',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Provider',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final p in supportedProviders)
                      DropdownMenuItem(
                        value: p,
                        child: Text(providerLabel(p)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    _set((s) {
                      s.providerType = v;
                      // Reset model to first in the new provider's list
                      if (v == 'gemini') {
                        s.model = supportedGeminiModels.first;
                      } else if (v == 'openrouter') {
                        s.model = supportedOpenRouterModels.first;
                      } else if (v == 'groq') {
                        s.model = supportedGroqModels.first;
                      } else if (v == 'deepseek') {
                        s.model = supportedDeepseekModels.first;
                      } else {
                        s.model = '';
                      }
                      _modelController.text = s.model;
                    });
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('API key'),
                subtitle: Text(_draft.apiKey.isNotEmpty
                    ? 'Stored securely on this device (${_draft.apiKey.length} chars)'
                    : 'Not configured yet'),
                trailing: TextButton(
                  onPressed: () => _showKeyDialog(),
                  child: const Text('Change'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _statusChip(),
              ),
              if (_testResult != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testResult!.startsWith('Connected')
                          ? Colors.greenAccent
                          : Theme.of(context).colorScheme.error,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.tonalIcon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_testing ? 'Testing…' : 'Test connection'),
                ),
              ),
              if (_draft.apiKey.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        _keyController.clear();
                        _set((s) => s.apiKey = '');
                        setState(() => _testResult = null);
                      },
                      child: const Text('Remove API key'),
                    ),
                  ),
                ),
            ],
          ),
          _section(
            'Model',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: DropdownButtonFormField<String>(
                  initialValue: _isKnownModel(_draft.model) ? _draft.model : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    if (_draft.providerType == 'gemini')
                      for (final m in supportedGeminiModels)
                        DropdownMenuItem(value: m, child: Text(m))
                    else if (_draft.providerType == 'openrouter')
                      for (final m in supportedOpenRouterModels)
                        DropdownMenuItem(value: m, child: Text(m))
                    else if (_draft.providerType == 'groq')
                      for (final m in supportedGroqModels)
                        DropdownMenuItem(value: m, child: Text(m))
                    else if (_draft.providerType == 'deepseek')
                      for (final m in supportedDeepseekModels)
                        DropdownMenuItem(value: m, child: Text(m))
                    else
                      const DropdownMenuItem(
                          value: null,
                          child: Text('Custom provider — type below')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      _set((s) => s.model = v);
                      _modelController.text = v;
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model ID (or custom)',
                    hintText: 'e.g. gemini-3.5-flash, openrouter/llama-3.3-70b-versatile',
                  ),
                  onChanged: (v) => _set((s) => s.model = v.trim()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  _draft.providerType == 'gemini'
                      ? 'Using Google Gemini — get a key at aistudio.google.com/app/apikey'
                      : _draft.providerType == 'openrouter'
                          ? 'Using OpenRouter — get a free key at openrouter.ai/keys'
                          : _draft.providerType == 'groq'
                              ? 'Using Groq — get a free key at console.groq.com'
                              : _draft.providerType == 'deepseek'
                                  ? 'Using DeepSeek — get a key at platform.deepseek.com'
                                  : 'Using Custom API — configure base URL above',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          _section(
            'Generation',
            children: [
              _slider(
                label: 'Temperature',
                value: _draft.temperature,
                min: 0,
                max: 1.2,
                divisions: 24,
                display: _draft.temperature.toStringAsFixed(2),
                onChanged: (v) => _set((s) => s.temperature = v),
              ),
              _slider(
                label: 'Max output tokens',
                value: _draft.maxOutputTokens.toDouble(),
                min: 256,
                max: 2048,
                divisions: 14,
                display: '${_draft.maxOutputTokens} tokens',
                onChanged: (v) => _set((s) => s.maxOutputTokens = v.round()),
              ),
              _slider(
                label: 'Context messages sent',
                value: _draft.contextMessages.toDouble(),
                min: 4,
                max: 40,
                divisions: 18,
                display: '${_draft.contextMessages}',
                onChanged: (v) => _set((s) => s.contextMessages = v.round()),
              ),
            ],
          ),
          _section(
            'Memory',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.psychology_outlined),
                title: const Text('Auto memory'),
                subtitle: const Text('Extract facts & update the summary automatically'),
                value: _draft.autoMemory,
                onChanged: (v) => _set((s) => s.autoMemory = v),
              ),
              _slider(
                label: 'Summarize every',
                value: _draft.summarizeEveryTurns.toDouble(),
                min: 4,
                max: 30,
                divisions: 13,
                display: '${_draft.summarizeEveryTurns} turns',
                onChanged: (v) =>
                    _set((s) => s.summarizeEveryTurns = v.round().clamp(4, 30)),
              ),
              _slider(
                label: 'Max suggested actions',
                value: _draft.maxSuggestions.toDouble(),
                min: 0,
                max: 4,
                divisions: 4,
                display: '${_draft.maxSuggestions}',
                onChanged: (v) => _set((s) => s.maxSuggestions = v.round()),
              ),
            ],
          ),
          _section(
            'Appearance',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Dark mode'),
                value: _draft.darkMode,
                onChanged: (v) => _set((s) => s.darkMode = v),
              ),
            ],
          ),
          _section(
            'Data Management',
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Export a story'),
                subtitle: const Text('Copy story JSON to clipboard'),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final stories = await AppDatabase.instance.listStories();
                  if (!mounted) return;
                  if (stories.isEmpty) {
                    messenger.showSnackBar(const SnackBar(content: Text('No stories to export.')));
                    return;
                  }

                  final selected = await showDialog<Story>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('Select a story to export'),
                      children: stories.map((s) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, s),
                        child: Text(s.title),
                      )).toList(),
                    ),
                  );
                  if (selected == null) return;

                  try {
                    final json = await StoryExportService.instance.exportStoryJson(selected.id);
                    await Clipboard.setData(ClipboardData(text: json));
                    if (!mounted) return;
                    messenger.showSnackBar(const SnackBar(content: Text('Copied story JSON to clipboard.')));
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('Import data'),
                subtitle: const Text('Paste story JSON to restore'),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final key = TextEditingController();
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Import story JSON'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: TextField(
                          controller: key,
                          decoration: const InputDecoration(hintText: 'Paste story JSON here'),
                          maxLines: 10,
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        FilledButton(
                          onPressed: () async {
                            final json = key.text.trim();
                            if (json.isEmpty) return;
                            try {
                              final result = await StoryExportService.instance.importFromJson(json);
                              if (!mounted) return;
                              messenger.showSnackBar(SnackBar(content: Text(result)));
                              Navigator.pop(ctx);
                            } catch (e) {
                              if (!mounted) return;
                              messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
                            }
                          },
                          child: const Text('Import'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save settings'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip() {
    final ok = _draft.apiKey.trim().isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final color = ok ? Colors.greenAccent : scheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(
          ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          ok ? 'Connected' : 'Not connected',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(display,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _section(String title, {required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        ...children,
        const Divider(height: 24),
      ],
    );
  }

  void _showKeyDialog() {
    final key = TextEditingController(text: _keyController.text);
    var hidden = true;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(providerLabel(_draft.providerType) + ' API key'),
          content: TextField(
            controller: key,
            obscureText: hidden,
            decoration: InputDecoration(
              hintText: providerKeyHint(_draft.providerType),
              suffixIcon: IconButton(
                icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => hidden = !hidden),
              ),
            ),
            onSubmitted: (_) => Navigator.pop(context),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = key.text.trim();
                _keyController.text = v;
                _set((s) {
                  s.apiKey = v;
                  // Auto-detect provider from key prefix if not already set to that provider
                  final detected = detectProviderFromKey(v);
                  if (detected != null && detected != s.providerType) {
                    s.providerType = detected;
                    // Reset model to default for the detected provider
                    if (detected == 'gemini') {
                      s.model = supportedGeminiModels.first;
                    } else if (detected == 'openrouter') {
                      s.model = supportedOpenRouterModels.first;
                    } else if (detected == 'groq') {
                      s.model = supportedGroqModels.first;
                    } else if (detected == 'deepseek') {
                      s.model = supportedDeepseekModels.first;
                    }
                    _modelController.text = s.model;
                  }
                });
                setState(() => _testResult = null);
                Navigator.pop(context);
              },
              child: const Text('Save key'),
            ),
          ],
        ),
      ),
    );
  }
}