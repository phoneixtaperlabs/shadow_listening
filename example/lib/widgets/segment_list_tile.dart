import 'package:flutter/material.dart';

const List<Color> speakerColors = [
  Colors.blue,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.red,
  Colors.teal,
];

Color getSpeakerColor(String speakerId) {
  final colorIndex = int.tryParse(speakerId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  return speakerColors[colorIndex % speakerColors.length];
}

class TranscriptionSegmentTile extends StatelessWidget {
  final String text;
  final double startTime;
  final double endTime;
  final double confidence;

  const TranscriptionSegmentTile({
    super.key,
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });

  factory TranscriptionSegmentTile.fromMap(Map<String, dynamic> data) {
    return TranscriptionSegmentTile(
      text: data['text']?.toString() ?? '',
      startTime: (data['startTime'] as num?)?.toDouble() ?? 0,
      endTime: (data['endTime'] as num?)?.toDouble() ?? 0,
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        text.isNotEmpty ? text : '(empty)',
        style: TextStyle(
          fontSize: 14,
          color: text.isNotEmpty ? Colors.black : Colors.grey,
        ),
      ),
      subtitle: Text(
        '${startTime.toStringAsFixed(2)}s - ${endTime.toStringAsFixed(2)}s | conf: ${(confidence * 100).toStringAsFixed(0)}%',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      dense: true,
    );
  }
}

class SpeakerSegmentTile extends StatelessWidget {
  final String speakerId;
  final double startTime;
  final double endTime;
  final double confidence;

  const SpeakerSegmentTile({
    super.key,
    required this.speakerId,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });

  factory SpeakerSegmentTile.fromMap(Map<String, dynamic> data) {
    return SpeakerSegmentTile(
      speakerId: data['speakerId']?.toString() ?? 'Unknown',
      startTime: (data['startTime'] as num?)?.toDouble() ?? 0,
      endTime: (data['endTime'] as num?)?.toDouble() ?? 0,
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = getSpeakerColor(speakerId);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.2),
        radius: 16,
        child: Text(
          speakerId.replaceAll('Speaker_', 'S'),
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        speakerId,
        style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${startTime.toStringAsFixed(2)}s - ${endTime.toStringAsFixed(2)}s | conf: ${(confidence * 100).toStringAsFixed(0)}%',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      dense: true,
    );
  }
}

class SegmentListContainer extends StatelessWidget {
  final List<dynamic> segments;
  final Widget Function(BuildContext, int) itemBuilder;

  const SegmentListContainer({
    super.key,
    required this.segments,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: segments.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade300),
        itemBuilder: itemBuilder,
      ),
    );
  }
}
