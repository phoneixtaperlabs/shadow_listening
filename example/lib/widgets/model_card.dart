import 'package:flutter/material.dart';

import 'status_badge.dart';

class ModelCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isLoaded;
  final bool isLoading;
  final Map<String, dynamic>? modelInfo;
  final Widget? infoWidget;
  final Color buttonColor;
  final VoidCallback? onLoad;
  final VoidCallback? onUnload;
  final VoidCallback onCheck;

  const ModelCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isLoaded,
    required this.isLoading,
    this.modelInfo,
    this.infoWidget,
    required this.buttonColor,
    this.onLoad,
    this.onUnload,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              title.replaceAll(' Test', ''),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            StatusBadge.model(isLoaded: isLoaded, isLoading: isLoading),
          ],
        ),
        const SizedBox(height: 8),
        if (infoWidget != null) infoWidget!,
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: (isLoading || isLoaded) ? null : onLoad,
                child: const Text('Load Model'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: (!isLoaded || isLoading) ? null : onUnload,
                child: const Text('Unload Model'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: onCheck,
                child: const Text('Check'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class WhisperModelInfo extends StatelessWidget {
  final Map<String, dynamic> info;

  const WhisperModelInfo({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Path: ${info['modelPath']?.toString().split('/').last ?? 'N/A'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            'GPU: ${info['useGPU'] ?? false}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            'Language: ${info['language'] ?? 'N/A'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class FluidModelInfo extends StatelessWidget {
  final Map<String, dynamic> info;

  const FluidModelInfo({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version: ${info['version'] ?? 'N/A'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class DiarizerModelInfo extends StatelessWidget {
  final Map<String, dynamic> info;

  const DiarizerModelInfo({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Path: ${info['modelPath']?.toString().split('/').last ?? 'N/A'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            'Models Exist: ${info['modelsExist'] ?? false}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
