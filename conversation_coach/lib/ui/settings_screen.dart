import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/consent_scripts.dart';
import '../data/models/provider_config.dart';
import '../llm/llm_provider.dart';

/// Settings (Design §6.8): model & provider, transcription engine, privacy &
/// data, goals & rubrics. Model, language, retention and what is sent to the
/// cloud are all user controls with sensible defaults (Design principle 6).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('Model & provider', Icons.smart_toy_outlined),
          const _ProviderSection(),
          const SizedBox(height: 24),
          _SectionHeader('Transcription engine', Icons.transcribe_outlined),
          _TranscriptionSection(state: state),
          const SizedBox(height: 24),
          _SectionHeader('Privacy & data', Icons.lock_outline),
          _PrivacySection(state: state),
          const SizedBox(height: 24),
          _SectionHeader('Goals & rubrics', Icons.flag_outlined),
          _GoalsSection(state: state),
          const SizedBox(height: 24),
          _SectionHeader('Language', Icons.translate),
          _LanguageSection(state: state),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ProviderSection extends StatelessWidget {
  const _ProviderSection();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(
      children: [
        FutureBuilder<bool>(
          future: state.isFallbackActive(),
          builder: (context, snap) {
            if (snap.data != true) return const SizedBox.shrink();
            return Card(
              color: const Color(0xFFFDF6E3),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.offline_bolt_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Running on the built-in offline demo because '
                        '${state.preferredProvider.provider.displayName} has no key. '
                        'Your choice is remembered — add a key below to switch back.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        for (final config in state.providerConfigs)
          _ProviderTile(config: config),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => state.revertToClaudeDefault(),
          icon: const Icon(Icons.restore),
          label: const Text('Restore Claude default'),
        ),
      ],
    );
  }
}

class _ProviderTile extends StatelessWidget {
  final ProviderConfig config;
  const _ProviderTile({required this.config});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isSelected = state.preferredProviderId == config.id;
    final needsKey = config.provider == ProviderKind.anthropic ||
        config.provider == ProviderKind.openaiCompatible;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Radio<String>(
                  value: config.id,
                  groupValue: state.preferredProviderId,
                  onChanged: (v) => state.selectProvider(v!),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(config.provider.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(config.model,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (isSelected)
                  const Chip(
                    label: Text('Active', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (needsKey)
              FutureBuilder<bool>(
                future: state.hasApiKey(config),
                builder: (context, snap) {
                  final hasKey = snap.data ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Row(
                      children: [
                        Icon(hasKey ? Icons.key : Icons.key_off,
                            size: 16,
                            color: hasKey
                                ? const Color(0xFF2E7D5B)
                                : Colors.black45),
                        const SizedBox(width: 6),
                        Text(hasKey ? 'API key set' : 'No API key',
                            style: Theme.of(context).textTheme.bodySmall),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _editKey(context, state, config),
                          child: Text(hasKey ? 'Update key' : 'Add key'),
                        ),
                        TextButton(
                          onPressed: () => _test(context, state, config),
                          child: const Text('Test'),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editKey(
      BuildContext context, AppState state, ProviderConfig config) async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${config.provider.displayName} API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Paste your API key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Stored only in the OS keystore (Keychain / Android Keystore), '
              'never in plaintext.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (key != null && key.isNotEmpty) {
      await state.setApiKey(config, key);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Key saved. Provider is live again.')));
      }
    }
  }

  Future<void> _test(
      BuildContext context, AppState state, ProviderConfig config) async {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Testing connection…')));
    final provider = await state.providerRegistry.build(config);
    final ValidationResult result = await provider.validate();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor:
              result.ok ? const Color(0xFF2E7D5B) : const Color(0xFFB44A3F),
        ),
      );
    }
  }
}

class _TranscriptionSection extends StatelessWidget {
  final AppState state;
  const _TranscriptionSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          RadioListTile<String>(
            value: 'demo',
            groupValue: state.transcriptionEngineKind,
            onChanged: (v) => state.setTranscriptionEngine(v!),
            title: const Text('On-device demo (private, offline)'),
            subtitle: const Text('No audio leaves your device.'),
          ),
          RadioListTile<String>(
            value: 'cloud',
            groupValue: state.transcriptionEngineKind,
            onChanged: (v) => state.setTranscriptionEngine(v!),
            title: const Text('Cloud (higher accuracy, diarization)'),
            subtitle: const Text(
                'Audio is sent to your configured provider — opt-in.'),
          ),
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  final AppState state;
  const _PrivacySection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('Auto-delete audio after',
                            style: TextStyle(fontWeight: FontWeight.w500))),
                    Text(state.retentionAudioDays == 0
                        ? 'Never'
                        : '${state.retentionAudioDays} days'),
                  ],
                ),
                Slider(
                  value: state.retentionAudioDays.toDouble(),
                  min: 0,
                  max: 90,
                  divisions: 18,
                  label: state.retentionAudioDays == 0
                      ? 'Never'
                      : '${state.retentionAudioDays}d',
                  onChanged: (v) => state.setRetentionAudioDays(v.round()),
                ),
                const Text(
                  'Transcripts and analysis are kept; only the audio file is '
                  'purged.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        Card(
          color: const Color(0xFFFDF1EE),
          child: ListTile(
            leading: const Icon(Icons.delete_forever, color: Color(0xFFB44A3F)),
            title: const Text('Wipe everything'),
            subtitle: const Text(
                'Permanently delete all sessions, audio and keys.'),
            onTap: () => _confirmWipe(context),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Wipe everything?'),
        content: const Text(
            'This permanently deletes every session, recording, transcript, '
            'analysis and stored key. Deletion is real and cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB44A3F)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wipe everything'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().wipeEverything();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All data wiped.')));
      }
    }
  }
}

class _GoalsSection extends StatelessWidget {
  final AppState state;
  const _GoalsSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${state.goals.length} goal templates available',
                style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final g in state.goals) Chip(label: Text(g.name)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Each goal maps to a weighted rubric the analysis scores against. '
              'Custom rubric editing is on the roadmap (Phase 2).',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSection extends StatelessWidget {
  final AppState state;
  const _LanguageSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButtonFormField<String>(
          value: state.language,
          decoration: const InputDecoration(
              labelText: 'Default conversation language',
              border: InputBorder.none),
          items: [
            for (final e in ConsentScripts.languageNames.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => state.setLanguage(v ?? 'en'),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SectionHeader(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
