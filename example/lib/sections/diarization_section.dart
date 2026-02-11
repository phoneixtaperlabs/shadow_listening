import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/model_card.dart';
import '../widgets/segment_list_tile.dart';
import '../widgets/status_badge.dart';

class DiarizationSection extends StatelessWidget {
  const DiarizationSection({super.key});

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
          'Speaker Diarization',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Identify "who spoke when" using pyannote + WeSpeaker models',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        _DiarizerModelSection(state: state),
        const SizedBox(height: 16),
        _DiarizationProcessSection(state: state),
        _StreamingDiarizationSection(state: state),
      ],
    );
  }
}

class _DiarizerModelSection extends StatelessWidget {
  final AppState state;

  const _DiarizerModelSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Diarizer Model',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            StatusBadge.model(
              isLoaded: state.diarizerModelLoaded,
              isLoading: state.diarizerLoading,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (state.diarizerModelInfo != null)
          DiarizerModelInfo(info: state.diarizerModelInfo!),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white,
                ),
                onPressed: (state.diarizerLoading || state.diarizerModelLoaded)
                    ? null
                    : () => state.loadDiarizerModel(),
                child: const Text('Load Model'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: (!state.diarizerModelLoaded || state.diarizerLoading)
                    ? null
                    : () => state.unloadDiarizerModel(),
                child: const Text('Unload Model'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => state.checkDiarizerModel(),
                child: const Text('Check'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DiarizationProcessSection extends StatelessWidget {
  final AppState state;

  const _DiarizationProcessSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Process Audio File',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (!state.diarizerModelLoaded) const _DiarizerModelWarning(),
        Row(
          children: [
            const Text('Status', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            StatusBadge.processing(isProcessing: state.isDiarizing),
          ],
        ),
        const SizedBox(height: 8),
        if (state.recordingFilePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Last recorded file: ${state.recordingFilePath!.split('/').last}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: (!state.diarizerModelLoaded ||
                        state.isDiarizing ||
                        state.recordingFilePath == null)
                    ? null
                    : () => state.processDiarization(),
                child: const Text('Process Last Recording'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: !state.diarizerModelLoaded ? null : () => state.resetDiarizer(),
                child: const Text('Reset Diarizer'),
              ),
            ),
          ],
        ),
        if (state.diarizationResult != null) ...[
          const SizedBox(height: 16),
          _DiarizationResultSummary(result: state.diarizationResult!, color: Colors.cyan),
          const SizedBox(height: 8),
          const Text('Speaker Segments:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentListContainer(
            segments: state.diarizationResult!['segments'] as List? ?? [],
            itemBuilder: (context, index) {
              final segments = state.diarizationResult!['segments'] as List;
              return SpeakerSegmentTile.fromMap(segments[index] as Map<String, dynamic>);
            },
          ),
        ],
      ],
    );
  }
}

class _StreamingDiarizationSection extends StatelessWidget {
  final AppState state;

  const _StreamingDiarizationSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Streaming Diarization',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Real-time speaker diarization during recording',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        if (!state.diarizerModelLoaded) const _DiarizerModelWarning(),
        Row(
          children: [
            const Text('Chunk Duration:', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Text(
              '${state.streamingChunkDuration.toStringAsFixed(1)}s',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: state.streamingChunkDuration,
          min: 3.0,
          max: 10.0,
          divisions: 14,
          label: '${state.streamingChunkDuration.toStringAsFixed(1)}s',
          onChanged: state.isStreamingDiarization
              ? null
              : (value) => state.setStreamingChunkDuration(value),
        ),
        Text(
          'Smaller = lower latency, Larger = better accuracy',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            StatusBadge.recording(isRecording: state.isStreamingDiarization),
          ],
        ),
        const SizedBox(height: 8),
        if (state.streamingDiarizationFilePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'File: ${state.streamingDiarizationFilePath!.split('/').last}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  foregroundColor: Colors.white,
                ),
                onPressed: (!state.diarizerModelLoaded || state.isStreamingDiarization)
                    ? null
                    : () => state.startRecordingWithDiarization(),
                child: const Text('Start Recording'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: !state.isStreamingDiarization
                    ? null
                    : () => state.stopRecordingWithDiarization(),
                child: const Text('Stop Recording'),
              ),
            ),
          ],
        ),
        if (state.streamingDiarizationResult != null) ...[
          const SizedBox(height: 16),
          _DiarizationResultSummary(
            result: state.streamingDiarizationResult!,
            color: Colors.pink,
            showFile: true,
          ),
          const SizedBox(height: 8),
          const Text('Speaker Segments:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentListContainer(
            segments: state.streamingDiarizationResult!['segments'] as List? ?? [],
            itemBuilder: (context, index) {
              final segments = state.streamingDiarizationResult!['segments'] as List;
              return SpeakerSegmentTile.fromMap(segments[index] as Map<String, dynamic>);
            },
          ),
        ],
        if (state.streamingDiarizationResult != null &&
            (state.streamingDiarizationResult!['segments'] as List?)?.isEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No speakers detected',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _DiarizerModelWarning extends StatelessWidget {
  const _DiarizerModelWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning, color: Colors.orange, size: 16),
          SizedBox(width: 8),
          Text(
            'Load Diarizer model first!',
            style: TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DiarizationResultSummary extends StatelessWidget {
  final Map<String, dynamic> result;
  final Color color;
  final bool showFile;

  const _DiarizationResultSummary({
    required this.result,
    required this.color,
    this.showFile = false,
  });

  @override
  Widget build(BuildContext context) {
    final speakerCount = result['speakerCount'];
    final totalDuration = result['totalDuration'] ?? result['audioDuration'];
    final rtfx = result['rtfx'];
    final processingTime = result['processingTime'];
    final audioFilePath = result['audioFilePath'] as String?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Speakers: $speakerCount | '
            'Duration: ${(totalDuration as num?)?.toStringAsFixed(1)}s'
            '${rtfx != null ? ' | RTFx: ${(rtfx as num?)?.toStringAsFixed(1)}' : ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          if (processingTime != null)
            Text(
              'Processing time: ${(processingTime as num?)?.toStringAsFixed(2)}s',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          if (showFile && audioFilePath != null)
            Text(
              'File: ${audioFilePath.split('/').last}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }
}
