import 'package:flutter/services.dart';

import 'shadow_listening_platform_interface.dart';

class ShadowListening {
  Future<String?> getPlatformVersion() {
    return ShadowListeningPlatform.instance.getPlatformVersion();
  }

  Future<bool> getMicPermissionStatus() {
    return ShadowListeningPlatform.instance.getMicPermissionStatus();
  }

  Future<bool> requestMicPermission() {
    return ShadowListeningPlatform.instance.requestMicPermission();
  }

  Future<bool> getSysAudioPermissionStatus() {
    return ShadowListeningPlatform.instance.getSysAudioPermissionStatus();
  }

  Future<bool> requestSysAudioPermission() {
    return ShadowListeningPlatform.instance.requestSysAudioPermission();
  }

  Future<bool> getScreenRecordingPermissionStatus() {
    return ShadowListeningPlatform.instance.getScreenRecordingPermissionStatus();
  }

  Future<bool> requestScreenRecordingPermission() {
    return ShadowListeningPlatform.instance.requestScreenRecordingPermission();
  }

  // MARK: - Mic Listening
  Future<bool> startMicListening() {
    return ShadowListeningPlatform.instance.startMicListening();
  }

  Future<void> stopMicListening() {
    return ShadowListeningPlatform.instance.stopMicListening();
  }

  Future<String> getMicListeningStatus() {
    return ShadowListeningPlatform.instance.getMicListeningStatus();
  }

  // MARK: - System Audio Listening
  Future<bool> startSysAudioListening() {
    return ShadowListeningPlatform.instance.startSysAudioListening();
  }

  Future<void> stopSysAudioListening() {
    return ShadowListeningPlatform.instance.stopSysAudioListening();
  }

  Future<String> getSysAudioListeningStatus() {
    return ShadowListeningPlatform.instance.getSysAudioListeningStatus();
  }

  // MARK: - Combined Recording (Mic + System Audio)
  /// Mic과 System Audio를 동시에 시작하고 믹싱된 오디오를 WAV 파일로 저장
  /// 성공 시 파일 경로 반환, 실패 시 null
  Future<String?> startRecording() {
    return ShadowListeningPlatform.instance.startRecording();
  }

  Future<void> stopRecording() {
    return ShadowListeningPlatform.instance.stopRecording();
  }

  Future<bool> getRecordingStatus() {
    return ShadowListeningPlatform.instance.getRecordingStatus();
  }

  // MARK: - Debug: Individual Recording Tests
  Future<String?> startMicOnlyRecording() {
    return ShadowListeningPlatform.instance.startMicOnlyRecording();
  }

  Future<String?> startSysAudioOnlyRecording() {
    return ShadowListeningPlatform.instance.startSysAudioOnlyRecording();
  }

  Future<void> stopIndividualRecording() {
    return ShadowListeningPlatform.instance.stopIndividualRecording();
  }

  // MARK: - Debug: Mic + VAD Test
  Future<bool> startMicWithVAD() {
    return ShadowListeningPlatform.instance.startMicWithVAD();
  }

  Future<void> stopMicWithVAD() {
    return ShadowListeningPlatform.instance.stopMicWithVAD();
  }

  // MARK: - Whisper ASR Model Management
  /// Load Whisper model into memory
  /// [modelName] defaults to "ggml-large-v3-turbo-q5_0.bin"
  Future<bool> loadWhisperModel({String? modelName}) {
    return ShadowListeningPlatform.instance.loadWhisperModel(modelName: modelName);
  }

  /// Unload Whisper model and free memory
  Future<void> unloadWhisperModel() {
    return ShadowListeningPlatform.instance.unloadWhisperModel();
  }

  /// Check if Whisper model is currently loaded
  Future<bool> isWhisperModelLoaded() {
    return ShadowListeningPlatform.instance.isWhisperModelLoaded();
  }

  /// Get Whisper model info (path, GPU status, language)
  /// Returns null if model is not loaded
  Future<Map<String, dynamic>?> getWhisperModelInfo() {
    return ShadowListeningPlatform.instance.getWhisperModelInfo();
  }

  // MARK: - Fluid ASR Model Management
  /// Load Fluid ASR model into memory
  /// [version] can be "v2" (English-only) or "v3" (multilingual), defaults to "v2"
  Future<bool> loadFluidModel({String? version}) {
    return ShadowListeningPlatform.instance.loadFluidModel(version: version);
  }

  /// Unload Fluid ASR model and free memory
  Future<void> unloadFluidModel() {
    return ShadowListeningPlatform.instance.unloadFluidModel();
  }

  /// Check if Fluid ASR model is currently loaded
  Future<bool> isFluidModelLoaded() {
    return ShadowListeningPlatform.instance.isFluidModelLoaded();
  }

  /// Get Fluid ASR model info (version, path)
  /// Returns null if model is not loaded
  Future<Map<String, dynamic>?> getFluidModelInfo() {
    return ShadowListeningPlatform.instance.getFluidModelInfo();
  }

  // MARK: - Model Prewarming

  /// Pre-warm ML models to trigger CoreML compilation caching
  ///
  /// Loads each requested model into a temporary instance and immediately
  /// discards it. This creates cached compiled CoreML models, making
  /// subsequent real model loads significantly faster.
  ///
  /// Does not affect any currently loaded models.
  ///
  /// [asr] Whether to prewarm the ASR model (default: true)
  /// [diarization] Whether to prewarm the diarization model (default: true)
  /// [vad] Whether to prewarm the VAD model (default: true)
  /// [asrEngine] ASR engine to prewarm: 'whisper' or 'fluid' (default: 'fluid')
  ///
  /// Returns a map indicating per-model success/failure:
  /// ```dart
  /// {'asr': true, 'diarization': true, 'vad': false}
  /// ```
  Future<Map<String, bool>> preWarmModels({
    bool asr = true,
    bool diarization = true,
    bool vad = true,
    String asrEngine = 'fluid',
  }) {
    return ShadowListeningPlatform.instance.preWarmModels(
      asr: asr,
      diarization: diarization,
      vad: vad,
      asrEngine: asrEngine,
    );
  }

  // MARK: - Recording with Transcription
  /// Start recording with transcription
  /// [asrEngine] can be 'whisper' or 'fluid' (default)
  /// Returns file path on success, null on failure
  Future<String?> startRecordingWithTranscription({String? asrEngine}) {
    return ShadowListeningPlatform.instance
        .startRecordingWithTranscription(asrEngine: asrEngine);
  }

  /// Stop recording and get transcription results
  /// Returns list of transcription segments with startTime, endTime, text, confidence
  Future<List<Map<String, dynamic>>?> stopRecordingWithTranscription() {
    return ShadowListeningPlatform.instance.stopRecordingWithTranscription();
  }

  // MARK: - Diarizer Model Management

  /// Load diarizer model into memory
  /// Models are loaded from ~/Library/Application Support/com.taperlabs.shadow/shared/speaker-diarization-coreml/
  /// Required model files:
  ///   - pyannote_segmentation.mlmodelc (VAD + segmentation)
  ///   - wespeaker_v2.mlmodelc (speaker embedding)
  Future<bool> loadDiarizerModel() {
    return ShadowListeningPlatform.instance.loadDiarizerModel();
  }

  /// Unload diarizer model and free memory
  Future<void> unloadDiarizerModel() {
    return ShadowListeningPlatform.instance.unloadDiarizerModel();
  }

  /// Unload all ML models (ASR, VAD, Diarizer) to free memory.
  /// Call after listening ends to release resources.
  Future<void> unloadModels() {
    return ShadowListeningPlatform.instance.unloadModels();
  }

  /// Check if diarizer model is currently loaded
  Future<bool> isDiarizerModelLoaded() {
    return ShadowListeningPlatform.instance.isDiarizerModelLoaded();
  }

  /// Get diarizer model info (path, loaded status, models exist)
  Future<Map<String, dynamic>?> getDiarizerModelInfo() {
    return ShadowListeningPlatform.instance.getDiarizerModelInfo();
  }

  // MARK: - Diarization Processing

  /// Process an audio file for speaker diarization
  ///
  /// [audioFilePath] Path to the audio file (WAV, M4A, MP3, etc.)
  ///
  /// Returns a map containing:
  ///   - segments: List of speaker segments with speakerId, startTime, endTime, confidence
  ///   - speakerCount: Number of unique speakers detected
  ///   - processingTime: Time taken to process (seconds)
  ///   - audioDuration: Duration of the audio (seconds)
  ///   - rtfx: Real-time factor (audio duration / processing time)
  ///
  /// Returns null on error.
  ///
  /// Note: Audio must be at least 3 seconds long for diarization.
  /// 10+ seconds recommended for best accuracy.
  ///
  /// Example:
  /// ```dart
  /// final result = await shadowListening.processDiarization('/path/to/audio.wav');
  /// if (result != null) {
  ///   final segments = result['segments'] as List<Map<String, dynamic>>;
  ///   for (final segment in segments) {
  ///     print('${segment['speakerId']}: ${segment['startTime']}s - ${segment['endTime']}s');
  ///   }
  /// }
  /// ```
  Future<Map<String, dynamic>?> processDiarization(String audioFilePath) {
    return ShadowListeningPlatform.instance.processDiarization(audioFilePath);
  }

  /// Reset diarizer state (clears speaker tracking)
  /// Call this when starting a new session to reset speaker IDs
  Future<void> resetDiarizer() {
    return ShadowListeningPlatform.instance.resetDiarizer();
  }

  // MARK: - Streaming Diarization

  /// Start recording with real-time speaker diarization
  ///
  /// [chunkDuration] Duration of each audio chunk for diarization (default: 5.0 seconds)
  /// Minimum: 3.0 seconds, Recommended: 5.0-10.0 seconds for best accuracy
  ///
  /// Returns file path on success, null on failure
  ///
  /// Note: Diarizer model must be loaded first with loadDiarizerModel()
  ///
  /// Example:
  /// ```dart
  /// await shadowListening.loadDiarizerModel();
  /// final filePath = await shadowListening.startRecordingWithDiarization(chunkDuration: 5.0);
  /// // ... record for some time ...
  /// final result = await shadowListening.stopRecordingWithDiarization();
  /// ```
  Future<String?> startRecordingWithDiarization({double chunkDuration = 5.0}) {
    return ShadowListeningPlatform.instance
        .startRecordingWithDiarization(chunkDuration: chunkDuration);
  }

  /// Stop recording and get accumulated diarization results
  ///
  /// Returns a map containing:
  ///   - segments: List of speaker segments with speakerId, startTime, endTime, confidence
  ///   - speakerCount: Number of unique speakers detected
  ///   - totalDuration: Total recording duration (seconds)
  ///   - audioFilePath: Path to the recorded audio file
  ///
  /// Returns null on error
  Future<Map<String, dynamic>?> stopRecordingWithDiarization() {
    return ShadowListeningPlatform.instance.stopRecordingWithDiarization();
  }

  // MARK: - Unified Recording (ASR + Diarization)

  /// Start unified recording with ASR and/or Diarization
  ///
  /// Records audio while simultaneously processing it through VAD filtering,
  /// then sends speech segments to ASR and Diarization in parallel.
  ///
  /// [enableASR] Enable speech-to-text transcription (default: true)
  /// [enableDiarization] Enable speaker diarization (default: true)
  /// [asrEngine] ASR engine to use: 'whisper' or 'fluid' (default: 'fluid')
  ///
  /// Returns file path on success, null on failure
  ///
  /// Note: Required models must be loaded first:
  /// - For ASR: loadWhisperModel() or loadFluidModel()
  /// - For Diarization: loadDiarizerModel()
  ///
  /// Processing flow:
  /// 1. Mic + System Audio → AudioMixer → Single Stream
  /// 2. 5-second chunks → VAD check (30% speech threshold)
  /// 3. Speech chunks → ASR + Diarizer (parallel)
  ///
  /// Example:
  /// ```dart
  /// // Load required models
  /// await shadowListening.loadFluidModel();
  /// await shadowListening.loadDiarizerModel();
  ///
  /// // Start unified recording
  /// final filePath = await shadowListening.startUnifiedRecording(
  ///   enableASR: true,
  ///   enableDiarization: true,
  ///   asrEngine: 'fluid',
  /// );
  ///
  /// // Record for some time...
  ///
  /// // Stop and get results
  /// final result = await shadowListening.stopUnifiedRecording();
  /// if (result != null) {
  ///   print('Transcriptions: ${result['transcriptions']}');
  ///   print('Speakers: ${result['speakerSegments']}');
  ///   print('Speaker count: ${result['speakerCount']}');
  /// }
  /// ```
  Future<String?> startUnifiedRecording({
    bool enableASR = true,
    bool enableDiarization = true,
    String asrEngine = 'fluid',
  }) {
    return ShadowListeningPlatform.instance.startUnifiedRecording(
      enableASR: enableASR,
      enableDiarization: enableDiarization,
      asrEngine: asrEngine,
    );
  }

  /// Stop unified recording and get all results
  ///
  /// Returns a map containing:
  ///   - audioFilePath: Path to the recorded audio file
  ///   - transcriptions: List of transcription segments
  ///     - text: Transcribed text
  ///     - startTime: Start time in seconds
  ///     - endTime: End time in seconds
  ///     - confidence: Confidence score (0.0-1.0)
  ///   - speakerSegments: List of speaker segments
  ///     - speakerId: Speaker identifier (e.g., "Speaker_0")
  ///     - startTime: Start time in seconds
  ///     - endTime: End time in seconds
  ///     - confidence: Confidence score (0.0-1.0)
  ///   - speakerCount: Number of unique speakers detected
  ///   - totalDuration: Total recording duration (seconds)
  ///
  /// Returns null on error
  Future<Map<String, dynamic>?> stopUnifiedRecording() {
    return ShadowListeningPlatform.instance.stopUnifiedRecording();
  }

  // MARK: - Native Event Handler (Swift -> Flutter)

  /// Set handler for receiving real-time events from native (Swift) side
  ///
  /// Events are received during unified recording via `onChunkProcessed`:
  ///
  /// ```dart
  /// shadowListening.setNativeCallHandler((call) async {
  ///   if (call.method == 'onChunkProcessed') {
  ///     final args = Map<String, dynamic>.from(call.arguments as Map);
  ///
  ///     // Chunk info
  ///     final chunkIndex = args['chunkIndex'] as int;
  ///     final startTime = args['startTime'] as double;
  ///     final endTime = args['endTime'] as double;
  ///
  ///     // MicVAD segments (user speech)
  ///     final micVADSegments = (args['micVADSegments'] as List)
  ///         .map((e) => Map<String, dynamic>.from(e as Map))
  ///         .toList();
  ///
  ///     // SysVAD segments (other person speech via system audio)
  ///     final sysVADSegments = (args['sysVADSegments'] as List)
  ///         .map((e) => Map<String, dynamic>.from(e as Map))
  ///         .toList();
  ///
  ///     // Transcription (may be null)
  ///     final transcription = args['transcription'] != null
  ///         ? Map<String, dynamic>.from(args['transcription'] as Map)
  ///         : null;
  ///
  ///     // Diarization segments
  ///     final diarizations = (args['diarizations'] as List)
  ///         .map((e) => Map<String, dynamic>.from(e as Map))
  ///         .toList();
  ///
  ///     print('Chunk #$chunkIndex: ${startTime}s - ${endTime}s');
  ///     if (transcription != null) {
  ///       print('  Text: ${transcription['text']}');
  ///     }
  ///     for (final d in diarizations) {
  ///       print('  ${d['speakerId']}: ${d['startTime']}s - ${d['endTime']}s');
  ///     }
  ///   }
  ///   return null;
  /// });
  /// ```
  void setNativeCallHandler(Future<dynamic> Function(MethodCall call)? handler) {
    ShadowListeningPlatform.instance.setNativeCallHandler(handler);
  }

  // MARK: - Listening (Recording + Window 통합)

  /// 리스닝 시작 (모델 사전 로드 + 녹음 시작 + 윈도우 표시)
  ///
  /// [enableASR] ASR 전사 활성화 (default: true)
  /// [enableDiarization] 화자 분리 활성화 (default: true)
  /// [asrEngine] ASR 엔진: 'whisper' 또는 'fluid' (default: 'fluid')
  ///
  /// 내부 흐름:
  /// 1. 필요한 ML 모델 사전 로드 (ASR, Diarizer)
  /// 2. 오디오 캡처 시작 (VoiceProcessingIO 웜업)
  /// 3. Listening 윈도우 표시 → 카운트다운 3-2-1 → 리스닝 상태
  ///
  /// 실시간 결과는 `onChunkProcessed` 이벤트로 전달됨 (5초 청크 단위)
  Future<bool> startListening({
    bool enableASR = true,
    bool enableDiarization = true,
    String asrEngine = 'fluid',
    String? sessionId,
    bool shouldScreenshotCapture = false,
  }) {
    return ShadowListeningPlatform.instance.startListening(
      enableASR: enableASR,
      enableDiarization: enableDiarization,
      asrEngine: asrEngine,
      sessionId: sessionId,
      shouldScreenshotCapture: shouldScreenshotCapture,
    );
  }

  /// 리스닝 중지 (녹음 결과 반환 + 윈도우 닫기)
  ///
  /// Returns a map containing:
  ///   - audioFilePath: 녹음 파일 경로
  ///   - transcriptions: ASR 전사 세그먼트 목록
  ///   - speakerSegments: 화자 세그먼트 목록
  ///   - speakerCount: 고유 화자 수
  ///   - totalDuration: 총 녹음 시간 (초)
  ///
  /// Returns null on error
  Future<Map<String, dynamic>?> stopListening() {
    return ShadowListeningPlatform.instance.stopListening();
  }

  /// 리스닝 취소 (녹음 결과 폐기 + 윈도우 닫기)
  Future<void> cancelListening() {
    return ShadowListeningPlatform.instance.cancelListening();
  }

  // MARK: - Listening Window

  /// 디바이스 선택 Listening 윈도우 표시
  Future<bool> showListeningWindow() {
    return ShadowListeningPlatform.instance.showListeningWindow();
  }

  /// Listening 윈도우 닫기
  Future<void> closeListeningWindow() {
    return ShadowListeningPlatform.instance.closeListeningWindow();
  }

  // MARK: - Window Management

  /// Show a native SwiftUI window
  ///
  /// [identifier] Unique identifier for the window (default: 'default')
  /// [width] Window width in points (default: 240)
  /// [height] Window height in points (default: 140)
  /// [position] Position preset: 'screenCenter', 'bottomLeft', 'bottomRight', 'topRight', 'flutterWindow'
  /// [anchor] For flutterWindow position: 'topLeft', 'topRight', 'bottomLeft', 'bottomRight', 'leftCenter', 'rightCenter'
  /// [offsetX] Horizontal offset from anchor point (default: 15)
  /// [offsetY] Vertical offset from anchor point (default: 0)
  ///
  /// Returns true on success
  ///
  /// Example:
  /// ```dart
  /// // Show window at screen center
  /// await shadowListening.showWindow(identifier: 'test', position: 'screenCenter');
  ///
  /// // Show window next to Flutter window
  /// await shadowListening.showWindow(
  ///   identifier: 'floating',
  ///   position: 'flutterWindow',
  ///   anchor: 'rightCenter',
  ///   offsetX: 20,
  /// );
  /// ```
  Future<bool> showWindow({
    String identifier = 'default',
    double width = 240,
    double height = 140,
    String position = 'screenCenter',
    String? anchor,
    double? offsetX,
    double? offsetY,
  }) {
    return ShadowListeningPlatform.instance.showWindow(
      identifier: identifier,
      width: width,
      height: height,
      position: position,
      anchor: anchor,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  /// Close a native window by identifier
  ///
  /// [identifier] The window identifier to close (default: 'default')
  Future<void> closeWindow({String identifier = 'default'}) {
    return ShadowListeningPlatform.instance.closeWindow(identifier: identifier);
  }

  /// Check if a window is currently visible
  ///
  /// [identifier] The window identifier to check (default: 'default')
  ///
  /// Returns true if the window exists and is visible
  Future<bool> isWindowVisible({String identifier = 'default'}) {
    return ShadowListeningPlatform.instance.isWindowVisible(identifier: identifier);
  }

  /// Update window position
  ///
  /// [identifier] The window identifier to update (default: 'default')
  /// [position] New position preset
  Future<void> updateWindowPosition({
    String identifier = 'default',
    required String position,
  }) {
    return ShadowListeningPlatform.instance.updateWindowPosition(
      identifier: identifier,
      position: position,
    );
  }

  /// Get list of all active window identifiers
  Future<List<String>> getActiveWindows() {
    return ShadowListeningPlatform.instance.getActiveWindows();
  }

  // MARK: - Capture Target Enumeration

  /// Enumerate available capture targets (windows and displays).
  ///
  /// Returns a map containing:
  ///   - windows: List of window dictionaries with type, windowID, title, appName, bundleID, x, y, width, height, isOnScreen, isActive
  ///   - displays: List of display dictionaries with type, displayID, localizedName, x, y, width, height
  Future<Map<String, dynamic>> enumerateWindows() {
    return ShadowListeningPlatform.instance.enumerateWindows();
  }

  /// Update the native Listening UI's selected capture target.
  ///
  /// [targetConfig] must contain a 'type' key ('noCapture', 'autoCapture', 'window', 'display')
  /// and optional search params: windowID, windowTitle, displayID, displayName.
  Future<dynamic> updateCaptureTarget(Map<String, dynamic> targetConfig) {
    return ShadowListeningPlatform.instance.updateCaptureTarget(targetConfig);
  }
}
