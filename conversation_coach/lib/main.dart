import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'ui/root_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConversationCoachApp());
}

class ConversationCoachApp extends StatelessWidget {
  const ConversationCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'Conversation Coach',
        debugShowCheckedModeBanner: false,
        theme: CoachTheme.light(),
        home: const _Bootstrap(),
      ),
    );
  }
}

/// Shows a splash until the encrypted store is open and templates are seeded.
class _Bootstrap extends StatelessWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.ready) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq, size: 48),
              SizedBox(height: 16),
              Text('Conversation Coach'),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    return const RootShell();
  }
}
