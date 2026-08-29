import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../data/models/qa.dart';

/// Ask this conversation (Design §6.7 / F-QA-01/02/04) — a chat box scoped to
/// the single session, grounded in its transcript and analysis. Answers cite
/// timestamps; the assistant says plainly when something is not present rather
/// than inventing an answer.
class AskView extends StatefulWidget {
  final String sessionId;
  const AskView({super.key, required this.sessionId});

  @override
  State<AskView> createState() => _AskViewState();
}

class _AskViewState extends State<AskView> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<QAMessage> _messages = [];
  bool _sending = false;

  // Always-relevant fallbacks; refined from the analysis in [_load].
  List<String> _suggestions = const [
    'Summarise the key points.',
    'What did I do well?',
    'What could I do differently next time?',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final msgs = await state.qaService.history(widget.sessionId);
    // Seed the example chips from this conversation's analysis so they're
    // relevant, not generic placeholders.
    final analysis = await state.repo.analysisForSession(widget.sessionId);
    final derived = <String>[];
    if (analysis != null) {
      for (final q in analysis.openQuestions.take(2)) {
        final t = q.trim();
        if (t.isNotEmpty) derived.add(t.endsWith('?') ? t : '$t?');
      }
      for (final topic in analysis.topics.take(2)) {
        final t = topic.trim();
        if (t.isNotEmpty) derived.add('What was said about ${t.toLowerCase()}?');
      }
    }
    derived.add('What could I do differently next time?');
    if (mounted) {
      setState(() {
        _messages = msgs;
        _suggestions = derived.take(4).toList();
      });
    }
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _sending) return;
    _controller.clear();
    setState(() => _sending = true);
    final state = context.read<AppState>();
    try {
      await state.qaService.ask(
        sessionId: widget.sessionId,
        question: q,
        providerConfig: state.preferredProvider,
      );
      await _load();
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _empty()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) => _Bubble(message: _messages[i]),
                ),
        ),
        if (_sending) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Ask about this conversation…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : () => _send(_controller.text),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Icon(Icons.forum_outlined,
            size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Ask anything about this conversation. Answers are grounded in the '
          'transcript and cite the moments they rely on.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        for (final s in _suggestions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: OutlinedButton(
              onPressed: () => _send(s),
              child: Align(alignment: Alignment.centerLeft, child: Text(s)),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final QAMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == QARole.user;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text,
                style: TextStyle(
                    color: isUser ? Colors.white : Colors.black87)),
            if (message.citations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final c in message.citations)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(c.timestampLabel(),
                          style: const TextStyle(fontSize: 11)),
                      avatar: const Icon(Icons.schedule, size: 14),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
