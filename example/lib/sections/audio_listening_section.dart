import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/status_badge.dart';

class AudioListeningSection extends StatelessWidget {
  const AudioListeningSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const Text('Audio Listening', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _ListeningRow(
          title: 'Mic Listening',
          status: state.micListeningStatus,
          onStart: state.micListeningStatus == 'listening' ? null : () => state.startMicListening(),
          onStop: state.micListeningStatus != 'listening' ? null : () => state.stopMicListening(),
        ),
        const SizedBox(height: 16),
        _ListeningRow(
          title: 'System Audio Listening',
          status: state.sysAudioListeningStatus,
          onStart: state.sysAudioListeningStatus == 'listening' ? null : () => state.startSysAudioListening(),
          onStop: state.sysAudioListeningStatus != 'listening' ? null : () => state.stopSysAudioListening(),
        ),
      ],
    );
  }
}

class _ListeningRow extends StatelessWidget {
  final String title;
  final String status;
  final VoidCallback? onStart;
  final VoidCallback? onStop;

  const _ListeningRow({
    required this.title,
    required this.status,
    this.onStart,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            StatusBadge.listening(status: status),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: onStart,
                child: const Text('Start'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: onStop,
                child: const Text('Stop'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
