import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/model_card.dart';

class ModelsSection extends StatelessWidget {
  const ModelsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModelCard(
          title: 'Whisper Model Test',
          subtitle: 'Test Whisper model load/unload (check Console.app for logs)',
          isLoaded: state.whisperModelLoaded,
          isLoading: state.whisperLoading,
          buttonColor: Colors.teal,
          infoWidget: state.whisperModelInfo != null
              ? WhisperModelInfo(info: state.whisperModelInfo!)
              : null,
          onLoad: () => state.loadWhisperModel(),
          onUnload: () => state.unloadWhisperModel(),
          onCheck: () => state.checkWhisperModel(),
        ),
        ModelCard(
          title: 'Fluid ASR Model Test',
          subtitle: 'Test Parakeet TDT CoreML model (v2 English-only)',
          isLoaded: state.fluidModelLoaded,
          isLoading: state.fluidLoading,
          buttonColor: Colors.indigo,
          infoWidget: state.fluidModelInfo != null
              ? FluidModelInfo(info: state.fluidModelInfo!)
              : null,
          onLoad: () => state.loadFluidModel(),
          onUnload: () => state.unloadFluidModel(),
          onCheck: () => state.checkFluidModel(),
        ),
      ],
    );
  }
}
