import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/consent_scripts.dart';
import '../core/pricing.dart';
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
          _SectionHeader('Spending budget', Icons.account_balance_wallet_outlined),
          _BudgetSection(state: state),
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

/// Prepaid spend budget (F-MOD-06). The user tops up a deposit and each
/// analysed session draws its estimated cost down until a top-up is needed.
/// There is no payment processor — in the bring-your-own-key model the user
/// pays their providers directly; this is a personal spend meter.
class _BudgetSection extends StatelessWidget {
  final AppState state;
  const _BudgetSection({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.budgetEnabled) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('No prepaid budget set',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              const Text(
                'Set a deposit to cap your spend. Each analysed session draws '
                'down its estimated provider cost; recording is paused when the '
                'deposit runs out until you top up.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _addDeposit(context),
                icon: const Icon(Icons.add_card),
                label: const Text('Set a deposit'),
              ),
            ],
          ),
        ),
      );
    }

    final remaining = state.budgetRemaining;
    final fraction =
        state.budgetDeposit == 0 ? 0.0 : (remaining / state.budgetDeposit);
    final Color barColor = state.budgetExhausted
        ? const Color(0xFFB44A3F)
        : state.budgetLow
            ? const Color(0xFFD98E2B)
            : const Color(0xFF2E7D5B);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Remaining',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const Spacer(),
                Text(
                  Pricing.formatUsd(remaining),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 18, color: barColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Colors.black12,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Spent ${Pricing.formatUsd(state.budgetSpent)} of '
              '${Pricing.formatUsd(state.budgetDeposit)} deposited',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (state.budgetExhausted)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Budget used up — top up to record another session.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB44A3F),
                      fontWeight: FontWeight.w500),
                ),
              )
            else if (state.budgetLow)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Running low — consider topping up soon.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFD98E2B)),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => _addDeposit(context),
                  icon: const Icon(Icons.add_card),
                  label: const Text('Top up'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _confirmReset(context),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addDeposit(BuildContext context) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(state.budgetEnabled ? 'Top up deposit' : 'Set a deposit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: '\$',
                hintText: '10.00',
                labelText: 'Amount (USD)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'A personal prepaid cap. Each analysed session draws down its '
              'estimated provider cost. No payment is taken — you pay your '
              'providers directly.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text.trim())),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (amount != null && amount > 0) {
      await state.addDeposit(amount);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Added ${Pricing.formatUsd(amount)} to your deposit.')));
      }
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset budget?'),
        content: const Text(
            'Clears the deposit and spend back to zero. The spend meter is '
            'turned off until you set a new deposit.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) {
      await state.resetBudget();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Budget reset.')));
      }
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
            subtitle: const Text(
                'Uses a sample transcript — does not transcribe your audio.'),
          ),
          RadioListTile<String>(
            value: 'cloud',
            groupValue: state.transcriptionEngineKind,
            onChanged: (v) => state.setTranscriptionEngine(v!),
            title: const Text('Cloud — Whisper (transcribes your recording)'),
            subtitle: const Text(
                'Audio is sent to OpenAI Whisper — opt-in. Needs an OpenAI key.'),
          ),
          if (state.transcriptionEngineKind == 'cloud') _asrKeyRow(context),
        ],
      ),
    );
  }

  Widget _asrKeyRow(BuildContext context) {
    return FutureBuilder<bool>(
      future: state.hasAsrKey(),
      builder: (context, snap) {
        final hasKey = snap.data ?? false;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
          child: Row(
            children: [
              Icon(hasKey ? Icons.key : Icons.key_off,
                  size: 16,
                  color: hasKey
                      ? const Color(0xFF2E7D5B)
                      : const Color(0xFFB44A3F)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasKey
                      ? 'OpenAI key set · ${state.asrModel}'
                      : 'No OpenAI key — will use the demo transcript until set',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => _editAsrKey(context),
                child: Text(hasKey ? 'Update key' : 'Add key'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editAsrKey(BuildContext context) async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('OpenAI API key (Whisper)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'sk-…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Used only to transcribe your recording via OpenAI Whisper. '
              'Stored in the OS keystore, never in plaintext. Separate from '
              'your Anthropic analysis key.',
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
      await state.setAsrKey(key);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('OpenAI key saved — cloud transcription is on.')));
      }
    }
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
