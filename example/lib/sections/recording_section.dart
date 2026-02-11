import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/status_badge.dart';

class RecordingSection extends StatelessWidget {
  const RecordingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Combined Recording (Mic + System Audio)',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Recording', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            StatusBadge.recording(isRecording: state.isRecording),
          ],
        ),
        const SizedBox(height: 8),
        if (state.recordingFilePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'File: ${state.recordingFilePath!.split('/').last}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: state.isRecording ? null : () => state.startRecording(),
                child: const Text('Start Recording'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: !state.isRecording ? null : () => state.stopRecording(),
                child: const Text('Stop Recording'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Debug: Individual Recording Tests',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Test each source separately to identify noise source',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: state.isRecording ? null : () => state.startMicOnlyRecording(),
                child: const Text('Mic Only'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: state.isRecording ? null : () => state.startSysAudioOnlyRecording(),
                child: const Text('SysAudio Only'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: !state.isRecording ? null : () => state.stopIndividualRecording(),
                child: const Text('Stop'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Debug: Mic + VAD Test',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Test VAD with mic input only (check Console.app for logs)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
                onPressed: state.isRecording ? null : () => state.startMicWithVAD(),
                child: const Text('Start Mic+VAD'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: !state.isRecording ? null : () => state.stopMicWithVAD(),
                child: const Text('Stop Mic+VAD'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
