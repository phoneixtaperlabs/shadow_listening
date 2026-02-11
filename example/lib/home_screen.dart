import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'sections/audio_listening_section.dart';
import 'sections/diarization_section.dart';
import 'sections/models_section.dart';
import 'sections/permissions_section.dart';
import 'sections/recording_section.dart';
import 'sections/transcription_section.dart';
import 'sections/listening_section.dart';
import 'sections/unified_section.dart';
import 'sections/window_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().checkAllPermissionStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Shadow Listening')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Running on: ${state.platformVersion}'),
            const SizedBox(height: 8),
            Text(
              'Result: ${state.permissionResult}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const PermissionsSection(),
            const AudioListeningSection(),
            const RecordingSection(),
            const ModelsSection(),
            const TranscriptionSection(),
            const DiarizationSection(),
            const UnifiedSection(),
            const ListeningSection(),
            const WindowSection(),
          ],
        ),
      ),
    );
  }
}
