import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/segment_list_tile.dart';
import '../widgets/status_badge.dart';

class UnifiedSection extends StatelessWidget {
  const UnifiedSection({super.key});

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
          'Unified Recording',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          'ASR + Diarization with VAD filtering',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        _ModelWarnings(state: state),
        _ConfigurationSection(state: state),
        _RecordingControls(state: state),
        _RealtimeResults(state: state),
        _FinalResults(state: state),
      ],
    );
  }
}

class _ModelWarnings extends StatelessWidget {
  final AppState state;

  const _ModelWarnings({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!state.fluidModelLoaded && !state.whisperModelLoaded)
          _WarningBanner(
            message: 'Load ASR model (Fluid or Whisper) for transcription!',
          ),
        if (!state.diarizerModelLoaded)
          _WarningBanner(
            message: 'Load Diarizer model for speaker detection!',
          ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;

  const _WarningBanner({required this.message});

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
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        ],
      ),
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
        const Text(
          'Configuration',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(
              value: state.unifiedEnableASR,
              onChanged: state.isUnifiedRecording
                  ? null
                  : (value) => state.setUnifiedEnableASR(value),
            ),
            const Text('Enable ASR (Transcription)'),
            const SizedBox(width: 16),
            if (state.unifiedEnableASR)
              DropdownButton<String>(
                value: state.unifiedASREngine,
                items: const [
                  DropdownMenuItem(value: 'fluid', child: Text('Fluid')),
                  DropdownMenuItem(value: 'whisper', child: Text('Whisper')),
                ],
                onChanged: state.isUnifiedRecording
                    ? null
                    : (value) => state.setUnifiedASREngine(value!),
              ),
          ],
        ),
        Row(
          children: [
            Switch(
              value: state.unifiedEnableDiarization,
              onChanged: state.isUnifiedRecording
                  ? null
                  : (value) => state.setUnifiedEnableDiarization(value),
            ),
            const Text('Enable Diarization (Speaker Detection)'),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _RecordingControls extends StatelessWidget {
  final AppState state;

  const _RecordingControls({required this.state});

  bool _canStartRecording() {
    if (state.isUnifiedRecording) return false;
    if (!state.unifiedEnableASR && !state.unifiedEnableDiarization) return false;
    if (state.unifiedEnableASR && !state.fluidModelLoaded && !state.whisperModelLoaded) {
      return false;
    }
    if (state.unifiedEnableASR &&
        state.unifiedASREngine == 'fluid' &&
        !state.fluidModelLoaded) {
      return false;
    }
    if (state.unifiedEnableASR &&
        state.unifiedASREngine == 'whisper' &&
        !state.whisperModelLoaded) {
      return false;
    }
    if (state.unifiedEnableDiarization && !state.diarizerModelLoaded) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            StatusBadge.recording(isRecording: state.isUnifiedRecording),
          ],
        ),
        const SizedBox(height: 8),
        if (state.unifiedRecordingFilePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'File: ${state.unifiedRecordingFilePath!.split('/').last}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                onPressed: _canStartRecording() ? () => state.startUnifiedRecording() : null,
                child: const Text('Start Recording'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed:
                    !state.isUnifiedRecording ? null : () => state.stopUnifiedRecording(),
                child: const Text('Stop Recording'),
              ),
            ),
          ],
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
    if (!state.isUnifiedRecording || state.realtimeChunks.isEmpty) {
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
                color: Colors.green,
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
            border: Border.all(color: Colors.green.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: state.realtimeChunks.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade300),
            itemBuilder: (context, index) {
              final chunk =
                  state.realtimeChunks[state.realtimeChunks.length - 1 - index];
              final chunkIndex = chunk['chunkIndex'] as int;
              final startTime = chunk['startTime'] as double;
              final endTime = chunk['endTime'] as double;
              final transcription = chunk['transcription'] as Map<String, dynamic>?;
              final diarizations = chunk['diarizations'] as List<Map<String, dynamic>>;

              return ListTile(
                dense: true,
                title: Text(
                  transcription != null
                      ? transcription['text']?.toString() ?? ''
                      : '(no speech)',
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
    if (state.unifiedRecordingResult == null) {
      return const SizedBox.shrink();
    }

    final result = state.unifiedRecordingResult!;
    final transcriptions = result['transcriptions'] as List? ?? [];
    final speakerSegments = result['speakerSegments'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        _ResultSummary(result: result),
        if (transcriptions.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Transcriptions:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentListContainer(
            segments: transcriptions,
            itemBuilder: (context, index) {
              return TranscriptionSegmentTile.fromMap(
                  transcriptions[index] as Map<String, dynamic>);
            },
          ),
        ],
        if (speakerSegments.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Speaker Segments:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentListContainer(
            segments: speakerSegments,
            itemBuilder: (context, index) {
              return SpeakerSegmentTile.fromMap(
                  speakerSegments[index] as Map<String, dynamic>);
            },
          ),
        ],
        if (transcriptions.isEmpty && speakerSegments.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No speech detected in recording',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ResultSummary extends StatelessWidget {
  final Map<String, dynamic> result;

  const _ResultSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final totalDuration = result['totalDuration'] as num?;
    final speakerCount = result['speakerCount'];
    final audioFilePath = result['audioFilePath'] as String?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurple.shade200),
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
        ],
      ),
    );
  }
}
