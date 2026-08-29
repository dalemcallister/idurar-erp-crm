import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../data/models/provider_config.dart';
import 'new_session_screen.dart';

/// Home / Record — the home screen's primary action is Record (Design
/// principle 1: one tap to record).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation Coach')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text('Your pocket communication coach',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Record a real conversation, set a goal, and get an '
                'evidence-backed read on how it went — then ask it anything.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 40),
              Center(
                child: _RecordButton(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const NewSessionScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(child: Text('Tap to start a new session')),
              const Spacer(),
              const _FallbackBanner(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RecordButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary,
          boxShadow: [
            BoxShadow(
                color: scheme.primary.withValues(alpha: 0.3),
                blurRadius: 24,
                spreadRadius: 4),
          ],
        ),
        child: const Icon(Icons.mic, color: Colors.white, size: 64),
      ),
    );
  }
}

/// Surfaces — non-intrusively — when the app will use the offline demo provider
/// because the preferred provider has no key yet. Reassures the user their real
/// configuration is remembered and revertable.
class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return FutureBuilder<bool>(
      future: state.isFallbackActive(),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Card(
          color: const Color(0xFFFDF6E3),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.offline_bolt_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Using the built-in offline demo analysis. Download the '
                    'on-device analysis model in Settings → On-device models '
                    'for real, private analysis.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
