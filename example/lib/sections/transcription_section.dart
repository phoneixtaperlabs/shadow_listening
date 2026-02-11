import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/segment_list_tile.dart';
import '../widgets/status_badge.dart';

class TranscriptionSection extends StatelessWidget {
  const TranscriptionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final bool modelNotLoaded = (state.selectedASREngine == 'fluid' && !state.fluidModelLoaded) ||
        (state.selectedASREngine == 'whisper' && !state.whisperModelLoaded);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Recording with Transcription',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Record audio and transcribe using VAD + ASR',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('ASR Engine:', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 16),
            ChoiceChip(
              label: const Text('Fluid'),
              selected: state.selectedASREngine == 'fluid',
              onSelected: state.isRecording
                  ? null
                  : (selected) {
                      if (selected) state.setSelectedASREngine('fluid');
                    },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Whisper'),
              selected: state.selectedASREngine == 'whisper',
              onSelected: state.isRecording
                  ? null
                  : (selected) {
                      if (selected) state.setSelectedASREngine('whisper');
                    },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (modelNotLoaded)
          _ModelWarning(
            message: 'Load ${state.selectedASREngine == 'fluid' ? 'Fluid' : 'Whisper'} model first!',
          ),
        Row(
          children: [
            const Text('Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            StatusBadge.transcription(
              isTranscribing: state.isTranscribing,
              isRecording: state.isRecording,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                onPressed: (state.isRecording || state.isTranscribing || modelNotLoaded)
                    ? null
                    : () => state.startRecordingWithTranscription(),
                child: const Text('Start Recording'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: (!state.isRecording || state.isTranscribing)
                    ? null
                    : () => state.stopRecordingWithTranscription(),
                child: Text(state.isTranscribing ? 'Processing...' : 'Stop & Transcribe'),
              ),
            ),
          ],
        ),
        if (state.transcriptionResults != null && state.transcriptionResults!.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Results:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentListContainer(
            segments: state.transcriptionResults!,
            itemBuilder: (context, index) {
              return TranscriptionSegmentTile.fromMap(state.transcriptionResults![index]);
            },
          ),
        ],
        if (state.transcriptionResults != null && state.transcriptionResults!.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No speech detected (VAD found 0 segments)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _ModelWarning extends StatelessWidget {
  final String message;

  const _ModelWarning({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          Text(message, style: const TextStyle(color: Colors.orange, fontSize: 12)),
        ],
      ),
    );
  }
}
