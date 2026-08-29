import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/consent_scripts.dart';

/// Settings (v2 — fully on-device). On-device model management, privacy & data,
/// goals & rubrics, and language. There are no API keys or cloud toggles:
/// analysis and transcription both run locally and nothing leaves the device.
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
          _SectionHeader('On-device models', Icons.memory),
          _OnDeviceSection(state: state),
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

/// On-device model management: the analysis model (Gemma) is downloaded on
/// demand; the transcription model (Whisper) downloads automatically the first
/// time you record.
class _OnDeviceSection extends StatelessWidget {
  final AppState state;
  const _OnDeviceSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final downloading = state.gemmaDownloadPercent != null;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Card(
          color: const Color(0xFFF0F5F4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Everything runs on your device. No API keys, no accounts, '
                    'and no audio or transcript ever leaves the phone.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Analysis model.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Analysis model — Gemma 3 1B',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (state.gemmaInstalled && !downloading)
                      const Icon(Icons.check_circle,
                          color: Color(0xFF2E7D5B), size: 20),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  state.gemmaInstalled
                      ? 'Installed · ready for on-device analysis'
                      : 'About 0.5 GB. Required before conversations can be '
                          'analysed on-device. Download over Wi-Fi.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (downloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (state.gemmaDownloadPercent ?? 0) / 100,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Downloading… ${state.gemmaDownloadPercent}%',
                      style: Theme.of(context).textTheme.bodySmall),
                ] else if (state.gemmaInstalled)
                  OutlinedButton.icon(
                    onPressed: () => _confirmRemove(context),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove model'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => state.installGemma(),
                    icon: const Icon(Icons.download),
                    label: const Text('Download analysis model'),
                  ),
              ],
            ),
          ),
        ),
        // Transcription model.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transcription model — Whisper base',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'About 140 MB. Downloads automatically the first time you '
                  'record, then transcribes every conversation on-device.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove analysis model?'),
        content: const Text(
            'Frees up storage. You can download it again anytime, but you '
            'won\'t be able to analyse conversations until you do.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await state.removeGemma();
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
            subtitle:
                const Text('Permanently delete all sessions and audio.'),
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
            'This permanently deletes every session, recording, transcript '
            'and analysis. Deletion is real and cannot be undone. Your '
            'downloaded models are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFB44A3F)),
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
              'Each goal maps to a weighted rubric the analysis scores against.',
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
