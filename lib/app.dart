import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'data/settings.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// Root widget: wires the [AppState] (settings + story engine) into the tree
/// and picks the theme.
class StoryloomApp extends StatefulWidget {
  const StoryloomApp({super.key});

  @override
  State<StoryloomApp> createState() => _StoryloomAppState();
}

class _StoryloomAppState extends State<StoryloomApp> {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = AppState(store: SettingsStore());
    _appState.init();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'Storyloom',
            debugShowCheckedModeBanner: false,
            theme: state.settings.darkMode ? AppTheme.dark() : AppTheme.light(),
            home: state.initError != null
                ? _InitError(error: state.initError!)
                : const HomePage(),
          );
        },
      ),
    );
  }
}

class _InitError extends StatelessWidget {
  const _InitError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('Storyloom could not start', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(error, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}