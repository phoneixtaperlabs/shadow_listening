import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'shadow_listening_method_channel.dart';

abstract class ShadowListeningPlatform extends PlatformInterface {
  /// Constructs a ShadowListeningPlatform.
  ShadowListeningPlatform() : super(token: _token);

  static final Object _token = Object();

  static ShadowListeningPlatform _instance = MethodChannelShadowListening();

  /// The default instance of [ShadowListeningPlatform] to use.
  ///
  /// Defaults to [MethodChannelShadowListening].
  static ShadowListeningPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ShadowListeningPlatform] when
  /// they register themselves.
  static set instance(ShadowListeningPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> getMicPermissionStatus() {
    throw UnimplementedError('getMicPermissionStatus() has not been implemented.');
  }

  Future<bool> requestMicPermission() {
    throw UnimplementedError('requestMicPermission() has not been implemented.');
  }

  Future<bool> getSysAudioPermissionStatus() {
    throw UnimplementedError('getSysAudioPermissionStatus() has not been implemented.');
  }

  Future<bool> requestSysAudioPermission() {
    throw UnimplementedError('requestSysAudioPermission() has not been implemented.');
  }

  Future<bool> getScreenRecordingPermissionStatus() {
    throw UnimplementedError('getScreenRecordingPermissionStatus() has not been implemented.');
  }

  Future<bool> requestScreenRecordingPermission() {
    throw UnimplementedError('requestScreenRecordingPermission() has not been implemented.');
  }

  // MARK: - Mic Listening
  Future<bool> startMicListening() {
    throw UnimplementedError('startMicListening() has not been implemented.');
  }

  Future<void> stopMicListening() {
    throw UnimplementedError('stopMicListening() has not been implemented.');
  }

  Future<String> getMicListeningStatus() {
    throw UnimplementedError('getMicListeningStatus() has not been implemented.');
  }

  // MARK: - System Audio Listening
  Future<bool> startSysAudioListening() {
    throw UnimplementedError('startSysAudioListening() has not been implemented.');
  }

  Future<void> stopSysAudioListening() {
    throw UnimplementedError('stopSysAudioListening() has not been implemented.');
  }

  Future<String> getSysAudioListeningStatus() {
    throw UnimplementedError('getSysAudioListeningStatus() has not been implemented.');
  }

  // MARK: - Combined Recording
  Future<String?> startRecording() {
    throw UnimplementedError('startRecording() has not been implemented.');
  }

  Future<void> stopRecording() {
    throw UnimplementedError('stopRecording() has not been implemented.');
  }

  Future<bool> getRecordingStatus() {
    throw UnimplementedError('getRecordingStatus() has not been implemented.');
  }

  // MARK: - Debug: Individual Recording
  Future<String?> startMicOnlyRecording() {
    throw UnimplementedError('startMicOnlyRecording() has not been implemented.');
  }

  Future<String?> startSysAudioOnlyRecording() {
    throw UnimplementedError('startSysAudioOnlyRecording() has not been implemented.');
  }

  Future<void> stopIndividualRecording() {
    throw UnimplementedError('stopIndividualRecording() has not been implemented.');
  }

  // MARK: - Debug: Mic + VAD Test
  Future<bool> startMicWithVAD() {
    throw UnimplementedError('startMicWithVAD() has not been implemented.');
  }

  Future<void> stopMicWithVAD() {
    throw UnimplementedError('stopMicWithVAD() has not been implemented.');
  }

  // MARK: - Whisper ASR Model Management
  Future<bool> loadWhisperModel({String? modelName}) {
    throw UnimplementedError('loadWhisperModel() has not been implemented.');
  }

  Future<void> unloadWhisperModel() {
    throw UnimplementedError('unloadWhisperModel() has not been implemented.');
  }

  Future<bool> isWhisperModelLoaded() {
    throw UnimplementedError('isWhisperModelLoaded() has not been implemented.');
  }

  Future<Map<String, dynamic>?> getWhisperModelInfo() {
    throw UnimplementedError('getWhisperModelInfo() has not been implemented.');
  }

  // MARK: - Fluid ASR Model Management
  Future<bool> loadFluidModel({String? version}) {
    throw UnimplementedError('loadFluidModel() has not been implemented.');
  }

  Future<void> unloadFluidModel() {
    throw UnimplementedError('unloadFluidModel() has not been implemented.');
  }

  Future<bool> isFluidModelLoaded() {
    throw UnimplementedError('isFluidModelLoaded() has not been implemented.');
  }

  Future<Map<String, dynamic>?> getFluidModelInfo() {
    throw UnimplementedError('getFluidModelInfo() has not been implemented.');
  }

  // MARK: - Model Prewarming
  Future<Map<String, bool>> preWarmModels({bool asr = true, bool diarization = true, bool vad = true, String? asrEngine}) {
    throw UnimplementedError('preWarmModels() has not been implemented.');
  }

  // MARK: - Recording with Transcription
  Future<String?> startRecordingWithTranscription({String? asrEngine}) {
    throw UnimplementedError('startRecordingWithTranscription() has not been implemented.');
  }

  Future<List<Map<String, dynamic>>?> stopRecordingWithTranscription() {
    throw UnimplementedError('stopRecordingWithTranscription() has not been implemented.');
  }

  // MARK: - Diarizer Model Management
  Future<bool> loadDiarizerModel() {
    throw UnimplementedError('loadDiarizerModel() has not been implemented.');
  }

  Future<void> unloadDiarizerModel() {
    throw UnimplementedError('unloadDiarizerModel() has not been implemented.');
  }

  /// Unload all ML models (ASR, VAD, Diarizer) to free memory
  Future<void> unloadModels() {
    throw UnimplementedError('unloadModels() has not been implemented.');
  }

  Future<bool> isDiarizerModelLoaded() {
    throw UnimplementedError('isDiarizerModelLoaded() has not been implemented.');
  }

  Future<Map<String, dynamic>?> getDiarizerModelInfo() {
    throw UnimplementedError('getDiarizerModelInfo() has not been implemented.');
  }

  // MARK: - Diarization Processing
  Future<Map<String, dynamic>?> processDiarization(String audioFilePath) {
    throw UnimplementedError('processDiarization() has not been implemented.');
  }

  Future<void> resetDiarizer() {
    throw UnimplementedError('resetDiarizer() has not been implemented.');
  }

  // MARK: - Streaming Diarization
  Future<String?> startRecordingWithDiarization({double chunkDuration = 5.0}) {
    throw UnimplementedError('startRecordingWithDiarization() has not been implemented.');
  }

  Future<Map<String, dynamic>?> stopRecordingWithDiarization() {
    throw UnimplementedError('stopRecordingWithDiarization() has not been implemented.');
  }

  // MARK: - Unified Recording (ASR + Diarization)
  Future<String?> startUnifiedRecording({bool enableASR = true, bool enableDiarization = true, String asrEngine = 'fluid'}) {
    throw UnimplementedError('startUnifiedRecording() has not been implemented.');
  }

  Future<Map<String, dynamic>?> stopUnifiedRecording() {
    throw UnimplementedError('stopUnifiedRecording() has not been implemented.');
  }

  // MARK: - Native Event Handler (Swift -> Flutter)

  /// Set handler for receiving native (Swift) calls
  ///
  /// The handler receives method calls from Swift with the following methods:
  /// - `onChunkProcessed`: Chunk processing result containing:
  ///   - `chunkIndex`: int - Chunk index (0-based)
  ///   - `startTime`: double - Chunk start time in seconds
  ///   - `endTime`: double - Chunk end time in seconds
  ///   - `micVADSegments`: List<Map> - User speech segments [{startTime, endTime}]
  ///   - `transcription`: Map? - ASR result {text, startTime, endTime, confidence}
  ///   - `diarizations`: List<Map> - Speaker segments [{speakerId, startTime, endTime, confidence}]
  void setNativeCallHandler(Future<dynamic> Function(MethodCall call)? handler) {
    throw UnimplementedError('setNativeCallHandler() has not been implemented.');
  }

  // MARK: - Listening (Recording + Window 통합)

  /// 리스닝 시작 (모델 로딩 + 녹음 시작 + 윈도우 표시)
  Future<bool> startListening({
    bool enableASR = true,
    bool enableDiarization = true,
    String asrEngine = 'fluid',
    String? sessionId,
    bool shouldScreenshotCapture = false,
  }) {
    throw UnimplementedError('startListening() has not been implemented.');
  }

  /// 리스닝 중지 (녹음 결과 반환 + 윈도우 닫기)
  Future<Map<String, dynamic>?> stopListening() {
    throw UnimplementedError('stopListening() has not been implemented.');
  }

  /// 리스닝 취소 (녹음 결과 폐기 + 윈도우 닫기)
  Future<void> cancelListening() {
    throw UnimplementedError('cancelListening() has not been implemented.');
  }

  // MARK: - Listening Window

  Future<bool> showListeningWindow() {
    throw UnimplementedError('showListeningWindow() has not been implemented.');
  }

  Future<void> closeListeningWindow() {
    throw UnimplementedError('closeListeningWindow() has not been implemented.');
  }

  // MARK: - Window Management

  Future<bool> showWindow({
    String identifier = 'default',
    double width = 240,
    double height = 140,
    String position = 'screenCenter',
    String? anchor,
    double? offsetX,
    double? offsetY,
  }) {
    throw UnimplementedError('showWindow() has not been implemented.');
  }

  Future<void> closeWindow({String identifier = 'default'}) {
    throw UnimplementedError('closeWindow() has not been implemented.');
  }

  Future<bool> isWindowVisible({String identifier = 'default'}) {
    throw UnimplementedError('isWindowVisible() has not been implemented.');
  }

  Future<void> updateWindowPosition({String identifier = 'default', required String position}) {
    throw UnimplementedError('updateWindowPosition() has not been implemented.');
  }

  Future<List<String>> getActiveWindows() {
    throw UnimplementedError('getActiveWindows() has not been implemented.');
  }

  // MARK: - Capture Target Enumeration

  Future<Map<String, dynamic>> enumerateWindows() {
    throw UnimplementedError('enumerateWindows() has not been implemented.');
  }

  Future<dynamic> updateCaptureTarget(Map<String, dynamic> targetConfig) {
    throw UnimplementedError('updateCaptureTarget() has not been implemented.');
  }
}
