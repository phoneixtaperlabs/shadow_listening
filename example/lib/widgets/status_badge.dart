import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  factory StatusBadge.permission({
    required bool allowed,
  }) {
    return StatusBadge(
      label: allowed ? 'Allowed' : 'Denied',
      color: allowed ? Colors.green : Colors.red,
    );
  }

  factory StatusBadge.recording({
    required bool isRecording,
    String? recordingLabel,
    String? stoppedLabel,
  }) {
    return StatusBadge(
      label: isRecording ? (recordingLabel ?? 'Recording...') : (stoppedLabel ?? 'Stopped'),
      color: isRecording ? Colors.red : Colors.grey,
    );
  }

  factory StatusBadge.listening({
    required String status,
  }) {
    return StatusBadge(
      label: status,
      color: status == 'listening' ? Colors.green : Colors.grey,
    );
  }

  factory StatusBadge.model({
    required bool isLoaded,
    required bool isLoading,
  }) {
    Color badgeColor;
    String badgeLabel;
    if (isLoading) {
      badgeColor = Colors.orange;
      badgeLabel = 'Loading...';
    } else if (isLoaded) {
      badgeColor = Colors.green;
      badgeLabel = 'Loaded';
    } else {
      badgeColor = Colors.grey;
      badgeLabel = 'Not Loaded';
    }
    return StatusBadge(
      label: badgeLabel,
      color: badgeColor,
    );
  }

  factory StatusBadge.processing({
    required bool isProcessing,
    String? processingLabel,
    String? idleLabel,
  }) {
    return StatusBadge(
      label: isProcessing ? (processingLabel ?? 'Processing...') : (idleLabel ?? 'Idle'),
      color: isProcessing ? Colors.orange : Colors.grey,
    );
  }

  factory StatusBadge.transcription({
    required bool isTranscribing,
    required bool isRecording,
  }) {
    Color badgeColor;
    String badgeLabel;
    if (isTranscribing) {
      badgeColor = Colors.orange;
      badgeLabel = 'Transcribing...';
    } else if (isRecording) {
      badgeColor = Colors.red;
      badgeLabel = 'Recording...';
    } else {
      badgeColor = Colors.grey;
      badgeLabel = 'Idle';
    }
    return StatusBadge(
      label: badgeLabel,
      color: badgeColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
