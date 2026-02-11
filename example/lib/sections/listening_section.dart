import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/status_badge.dart';

class ListeningSection extends StatelessWidget {
  const ListeningSection({super.key});

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
          'Listening',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          'One-click: model loading + recording + native window',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        _ConfigurationSection(state: state),
        _ListeningControls(state: state),
        _RealtimeResults(state: state),
        _FinalResults(state: state),
      ],
    );
  }
}

class _ConfigurationSection extends StatelessWidget {
  final AppState state;

  const _ConfigurationSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Switch(
              value: state.listeningEnableASR,
              onChanged:
                  state.isListening ? null : (value) => state.setListeningEnableASR(value),
            ),
            const Text('ASR'),
            const SizedBox(width: 16),
            if (state.listeningEnableASR)
              DropdownButton<String>(
                value: state.listeningASREngine,
                items: const [
                  DropdownMenuItem(value: 'fluid', child: Text('Fluid')),
                  DropdownMenuItem(value: 'whisper', child: Text('Whisper')),
                ],
                onChanged:
                    state.isListening ? null : (value) => state.setListeningASREngine(value!),
              ),
          ],
        ),
        Row(
          children: [
            Switch(
              value: state.listeningEnableDiarization,
              onChanged: state.isListening
                  ? null
                  : (value) => state.setListeningEnableDiarization(value),
            ),
            const Text('Diarization'),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ListeningControls extends StatelessWidget {
  final AppState state;

  const _ListeningControls({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            StatusBadge.recording(isRecording: state.isListening),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                onPressed: state.isListening ? null : () => state.startListening(),
                child: const Text('Start Listening'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: !state.isListening ? null : () => state.stopListeningFromFlutter(),
                child: const Text('Stop Listening'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Models auto-loaded. Cancel via native ControlBar (xmark).',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _RealtimeResults extends StatelessWidget {
  final AppState state;

  const _RealtimeResults({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.isListening || state.realtimeChunks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              'Real-time Results',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${state.realtimeChunks.length} chunks',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.teal.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: state.realtimeChunks.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade300),
            itemBuilder: (context, index) {
              final chunk = state.realtimeChunks[state.realtimeChunks.length - 1 - index];
              final chunkIndex = chunk['chunkIndex'] as int;
              final startTime = chunk['startTime'] as double;
              final endTime = chunk['endTime'] as double;
              final transcription = chunk['transcription'] as Map<String, dynamic>?;
              final diarizations = chunk['diarizations'] as List<Map<String, dynamic>>;

              return ListTile(
                dense: true,
                title: Text(
                  transcription != null ? transcription['text']?.toString() ?? '' : '(no speech)',
                  style: TextStyle(
                    fontSize: 13,
                    color: transcription != null ? Colors.black : Colors.grey,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Chunk #$chunkIndex (${startTime.toStringAsFixed(1)}s-${endTime.toStringAsFixed(1)}s) | Speakers: ${diarizations.map((d) => d['speakerId']).toSet().join(', ')}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FinalResults extends StatelessWidget {
  final AppState state;

  const _FinalResults({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.listeningResult == null) {
      return const SizedBox.shrink();
    }

    final result = state.listeningResult!;
    final totalDuration = result['totalDuration'] as num?;
    final speakerCount = result['speakerCount'];
    final transcriptions = result['transcriptions'] as List? ?? [];
    final speakerSegments = result['speakerSegments'] as List? ?? [];
    final audioFilePath = result['audioFilePath'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Duration: ${totalDuration?.toStringAsFixed(1)}s | Speakers: $speakerCount',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              if (audioFilePath != null)
                Text(
                  'File: ${audioFilePath.split('/').last}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              Text(
                '${transcriptions.length} transcriptions, ${speakerSegments.length} speaker segments',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
