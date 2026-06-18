import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../audio/audio_capture.dart';
import '../core/app_state.dart';
import '../core/consent_scripts.dart';
import '../data/models/consent_record.dart';
import '../data/models/goal.dart';
import '../data/models/session.dart';
import 'live_recording_screen.dart';

/// New session: goal & context picker → mic & language picker → consent step
/// (Design §6.1). Goal selection is two taps; consent is mandatory in-flow.
class NewSessionScreen extends StatefulWidget {
  const NewSessionScreen({super.key});

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  final _uuid = const Uuid();
  final _capture = AudioCapture();
  final _contextController = TextEditingController();

  Goal? _goal;
  String _language = 'en';
  List<MicInput> _inputs = [];
  MicInput? _selectedInput;
  MicTestResult? _micTest;
  bool _testing = false;
  ConsentMethod _consentMethod = ConsentMethod.self;
  bool _consentConfirmed = false;

  @override
  void initState() {
    super.initState();
    _language = context.read<AppState>().language;
    _loadInputs();
  }

  Future<void> _loadInputs() async {
    // Trigger the runtime mic-permission request up front.
    await _capture.hasPermission();
    var inputs = <MicInput>[];
    try {
      inputs = await _capture.listInputs();
    } catch (_) {
      // Some platforms/emulators don't enumerate inputs — fall back below.
    }
    if (!mounted) return;
    // Always offer a usable default so recording is never blocked, even when
    // enumeration returns nothing (common on emulators / before permission).
    const fallback = MicInput(id: 'default', label: 'Default microphone');
    final list = inputs.isEmpty ? [fallback] : inputs;
    setState(() {
      _inputs = list;
      _selectedInput =
          list.firstWhere((d) => d.isUsb, orElse: () => list.first);
    });
  }

  Future<void> _runMicTest() async {
    final device = _selectedInput;
    if (device == null) return;
    setState(() => _testing = true);
    try {
      final result = await _capture.testInput(device);
      if (mounted) setState(() => _micTest = result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Mic test failed — check permissions / device.')));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _contextController.dispose();
    _capture.dispose();
    super.dispose();
  }

  bool get _canStart =>
      _goal != null && _selectedInput != null && _consentConfirmed;

  Future<void> _start() async {
    final state = context.read<AppState>();

    // Prepaid budget gate (F-MOD-06): block when the deposit is used up.
    if (state.budgetExhausted) {
      final topUp = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Top up to keep recording'),
          content: const Text(
              'Your prepaid budget is used up. Top up your deposit in '
              'Settings → Spending budget to record another session.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Go to Settings')),
          ],
        ),
      );
      if (topUp == true && mounted) {
        // Pop back so the user can reach the Settings tab.
        Navigator.of(context).pop();
      }
      return;
    }

    final goal = _goal!;
    final session = Session(
      id: 'sess-${_uuid.v4()}',
      userId: 'me',
      title: '${goal.name} · ${_dateLabel()}',
      createdAt: DateTime.now(),
      durationSec: 0,
      language: _language,
      goalId: goal.id,
      context: _contextController.text.trim(),
      consentRecorded: true,
      status: SessionStatus.recording,
    );
    await state.repo.upsertSession(session);
    await state.repo.upsertConsent(ConsentRecord(
      id: 'con-${_uuid.v4()}',
      sessionId: session.id,
      method: _consentMethod,
      jurisdictionNote: ConsentScripts.jurisdictionNote(_language),
      timestamp: DateTime.now(),
    ));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LiveRecordingScreen(
        session: session,
        device: _selectedInput!,
      ),
    ));
  }

  String _dateLabel() {
    final n = DateTime.now();
    return '${n.day}/${n.month}';
  }

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<AppState>().goals;
    return Scaffold(
      appBar: AppBar(title: const Text('New session')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('1 · Goal & context', Icons.flag_outlined),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in goals)
                ChoiceChip(
                  label: Text(g.name),
                  selected: _goal?.id == g.id,
                  onSelected: (_) => setState(() => _goal = g),
                ),
            ],
          ),
          if (_goal != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_goal!.description,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _contextController,
            decoration: const InputDecoration(
              labelText: 'Context (optional) — who & why',
              border: OutlineInputBorder(),
              hintText: 'e.g. First call with Acme Co. about their reporting',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          _SectionTitle('2 · Mic & language', Icons.settings_voice_outlined),
          if (_inputs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                    'No input devices yet. Grant microphone permission, or '
                    'plug in a USB-C mic (the DJI Mic is the reference device).'),
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedInput?.id,
              decoration: const InputDecoration(
                  labelText: 'Input device', border: OutlineInputBorder()),
              items: [
                for (final d in _inputs)
                  DropdownMenuItem(
                    value: d.id,
                    child: Text(d.isUsb ? '${d.label}  · USB-C' : d.label),
                  ),
              ],
              onChanged: (id) => setState(() {
                _selectedInput = _inputs.firstWhere((d) => d.id == id);
                _micTest = null;
              }),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _runMicTest,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.graphic_eq),
                label: const Text('Test mic'),
              ),
              const SizedBox(width: 12),
              if (_micTest != null) Expanded(child: _micTestSummary()),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _language,
            decoration: const InputDecoration(
                labelText: 'Conversation language',
                border: OutlineInputBorder()),
            items: [
              for (final e in ConsentScripts.languageNames.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _language = v ?? 'en'),
          ),
          const SizedBox(height: 24),
          _SectionTitle('3 · Consent', Icons.verified_user_outlined),
          Card(
            color: const Color(0xFFF0F5F4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Read this aloud before recording:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('“${ConsentScripts.script(_language)}”',
                      style: const TextStyle(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 12),
                  Text(ConsentScripts.jurisdictionNote(_language),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          SegmentedButton<ConsentMethod>(
            segments: const [
              ButtonSegment(
                  value: ConsentMethod.self,
                  label: Text('I confirmed'),
                  icon: Icon(Icons.check)),
              ButtonSegment(
                  value: ConsentMethod.inAudio,
                  label: Text('Captured in audio'),
                  icon: Icon(Icons.record_voice_over)),
            ],
            selected: {_consentMethod},
            onSelectionChanged: (s) =>
                setState(() => _consentMethod = s.first),
          ),
          CheckboxListTile(
            value: _consentConfirmed,
            onChanged: (v) => setState(() => _consentConfirmed = v ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text(
                'Everyone present has agreed to be recorded.'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: _canStart ? _start : null,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Start recording'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Recording is never hidden — a clear indicator shows while live.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _micTestSummary() {
    final t = _micTest!;
    final level = (t.peakLevel * 100).round();
    return Text(
      '${t.sampleRate ~/ 1000} kHz · ${t.channels}ch · peak $level%'
      '${t.isLowQuality ? '  ⚠ low quality' : t.isUsb ? '  ✓ USB-C' : ''}',
      style: TextStyle(
        fontSize: 12,
        color: t.isLowQuality ? const Color(0xFFB44A3F) : Colors.black87,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SectionTitle(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
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
