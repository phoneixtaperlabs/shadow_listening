import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'shadow_listening_platform_interface.dart';

/// An implementation of [ShadowListeningPlatform] that uses method channels.
class MethodChannelShadowListening extends ShadowListeningPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('shadow_listening');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> getMicPermissionStatus() async {
    final status = await methodChannel.invokeMethod<bool>('getMicPermissionStatus');
    return status ?? false;
  }

  @override
  Future<bool> requestMicPermission() async {
    final granted = await methodChannel.invokeMethod<bool>('requestMicPermission');
    return granted ?? false;
  }

  @override
  Future<bool> getSysAudioPermissionStatus() async {
    final status = await methodChannel.invokeMethod<bool>('getSysAudioPermissionStatus');
    return status ?? false;
  }

  @override
  Future<bool> requestSysAudioPermission() async {
    final granted = await methodChannel.invokeMethod<bool>('requestSysAudioPermission');
    return granted ?? false;
  }

  @override
  Future<bool> getScreenRecordingPermissionStatus() async {
    final status = await methodChannel.invokeMethod<bool>('getScreenRecordingPermissionStatus');
    return status ?? false;
  }

  @override
  Future<bool> requestScreenRecordingPermission() async {
    final granted = await methodChannel.invokeMethod<bool>('requestScreenRecordingPermission');
    return granted ?? false;
  }

  // MARK: - Mic Listening
  @override
  Future<bool> startMicListening() async {
    final success = await methodChannel.invokeMethod<bool>('startMicListening');
    return success ?? false;
  }

  @override
  Future<void> stopMicListening() async {
    await methodChannel.invokeMethod<void>('stopMicListening');
  }

  @override
  Future<String> getMicListeningStatus() async {
    final status = await methodChannel.invokeMethod<String>('getMicListeningStatus');
    return status ?? 'idle';
  }

  // MARK: - System Audio Listening
  @override
  Future<bool> startSysAudioListening() async {
    final success = await methodChannel.invokeMethod<bool>('startSysAudioListening');
    return success ?? false;
  }

  @override
  Future<void> stopSysAudioListening() async {
    await methodChannel.invokeMethod<void>('stopSysAudioListening');
  }

  @override
  Future<String> getSysAudioListeningStatus() async {
    final status = await methodChannel.invokeMethod<String>('getSysAudioListeningStatus');
    return status ?? 'idle';
  }

  // MARK: - Combined Recording
  @override
  Future<String?> startRecording() async {
    final filePath = await methodChannel.invokeMethod<String>('startRecording');
    return filePath;
  }

  @override
  Future<void> stopRecording() async {
    await methodChannel.invokeMethod<void>('stopRecording');
  }

  @override
  Future<bool> getRecordingStatus() async {
    final isRecording = await methodChannel.invokeMethod<bool>('getRecordingStatus');
    return isRecording ?? false;
  }

  // MARK: - Debug: Individual Recording
  @override
  Future<String?> startMicOnlyRecording() async {
    final filePath = await methodChannel.invokeMethod<String>('startMicOnlyRecording');
    return filePath;
  }

  @override
  Future<String?> startSysAudioOnlyRecording() async {
    final filePath = await methodChannel.invokeMethod<String>('startSysAudioOnlyRecording');
    return filePath;
  }

  @override
  Future<void> stopIndividualRecording() async {
    await methodChannel.invokeMethod<void>('stopIndividualRecording');
  }

  // MARK: - Debug: Mic + VAD Test
  @override
  Future<bool> startMicWithVAD() async {
    final success = await methodChannel.invokeMethod<bool>('startMicWithVAD');
    return success ?? false;
  }

  @override
  Future<void> stopMicWithVAD() async {
    await methodChannel.invokeMethod<void>('stopMicWithVAD');
  }

  // MARK: - Whisper ASR Model Management
  @override
  Future<bool> loadWhisperModel({String? modelName}) async {
    final success = await methodChannel.invokeMethod<bool>(
      'loadWhisperModel',
      {'modelName': modelName},
    );
    return success ?? false;
  }

  @override
  Future<void> unloadWhisperModel() async {
    await methodChannel.invokeMethod<void>('unloadWhisperModel');
  }

  @override
  Future<bool> isWhisperModelLoaded() async {
    final loaded = await methodChannel.invokeMethod<bool>('isWhisperModelLoaded');
    return loaded ?? false;
  }

  @override
  Future<Map<String, dynamic>?> getWhisperModelInfo() async {
    final info = await methodChannel.invokeMethod<Map<Object?, Object?>>('getWhisperModelInfo');
    if (info == null) return null;
    return info.map((key, value) => MapEntry(key.toString(), value));
  }

  // MARK: - Fluid ASR Model Management
  @override
  Future<bool> loadFluidModel({String? version}) async {
    final success = await methodChannel.invokeMethod<bool>(
      'loadFluidModel',
      {'version': version},
    );
    return success ?? false;
  }

  @override
  Future<void> unloadFluidModel() async {
    await methodChannel.invokeMethod<void>('unloadFluidModel');
  }

  @override
  Future<bool> isFluidModelLoaded() async {
    final loaded = await methodChannel.invokeMethod<bool>('isFluidModelLoaded');
    return loaded ?? false;
  }

  @override
  Future<Map<String, dynamic>?> getFluidModelInfo() async {
    final info = await methodChannel.invokeMethod<Map<Object?, Object?>>('getFluidModelInfo');
    if (info == null) return null;
    return info.map((key, value) => MapEntry(key.toString(), value));
  }

  // MARK: - Recording with Transcription
  @override
  Future<String?> startRecordingWithTranscription({String? asrEngine}) async {
    final filePath = await methodChannel.invokeMethod<String>(
      'startRecordingWithTranscription',
      {'asrEngine': asrEngine ?? 'fluid'},
    );
    return filePath;
  }

  @override
  Future<List<Map<String, dynamic>>?> stopRecordingWithTranscription() async {
    final result = await methodChannel.invokeMethod<List<Object?>>('stopRecordingWithTranscription');
    if (result == null) return null;
    return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // MARK: - Diarizer Model Management
  @override
  Future<bool> loadDiarizerModel() async {
    final success = await methodChannel.invokeMethod<bool>('loadDiarizerModel');
    return success ?? false;
  }

  @override
  Future<void> unloadDiarizerModel() async {
    await methodChannel.invokeMethod<void>('unloadDiarizerModel');
  }

  @override
  Future<bool> isDiarizerModelLoaded() async {
    final loaded = await methodChannel.invokeMethod<bool>('isDiarizerModelLoaded');
    return loaded ?? false;
  }

  @override
  Future<Map<String, dynamic>?> getDiarizerModelInfo() async {
    final info = await methodChannel.invokeMethod<Map<Object?, Object?>>('getDiarizerModelInfo');
    if (info == null) return null;
    return info.map((key, value) => MapEntry(key.toString(), value));
  }

  // MARK: - Diarization Processing
  @override
  Future<Map<String, dynamic>?> processDiarization(String audioFilePath) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'processDiarization',
      {'audioFilePath': audioFilePath},
    );
    if (result == null) return null;

    // Convert nested segments list
    final segments = (result['segments'] as List<Object?>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return {
      'segments': segments,
      'speakerCount': result['speakerCount'],
      'processingTime': result['processingTime'],
      'audioDuration': result['audioDuration'],
      'rtfx': result['rtfx'],
    };
  }

  @override
  Future<void> resetDiarizer() async {
    await methodChannel.invokeMethod<void>('resetDiarizer');
  }

  // MARK: - Streaming Diarization
  @override
  Future<String?> startRecordingWithDiarization({double chunkDuration = 5.0}) async {
    final filePath = await methodChannel.invokeMethod<String>(
      'startRecordingWithDiarization',
      {'chunkDuration': chunkDuration},
    );
    return filePath;
  }

  @override
  Future<Map<String, dynamic>?> stopRecordingWithDiarization() async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'stopRecordingWithDiarization',
    );
    if (result == null) return null;

    final segments = (result['segments'] as List<Object?>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return {
      'segments': segments,
      'speakerCount': result['speakerCount'],
      'totalDuration': result['totalDuration'],
      'audioFilePath': result['audioFilePath'],
    };
  }

  // MARK: - Unified Recording (ASR + Diarization)
  @override
  Future<String?> startUnifiedRecording({
    bool enableASR = true,
    bool enableDiarization = true,
    String asrEngine = 'fluid',
  }) async {
    final filePath = await methodChannel.invokeMethod<String>(
      'startUnifiedRecording',
      {
        'enableASR': enableASR,
        'enableDiarization': enableDiarization,
        'asrEngine': asrEngine,
      },
    );
    return filePath;
  }

  @override
  Future<Map<String, dynamic>?> stopUnifiedRecording() async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'stopUnifiedRecording',
    );
    if (result == null) return null;

    final transcriptions = (result['transcriptions'] as List<Object?>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final speakerSegments = (result['speakerSegments'] as List<Object?>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return {
      'audioFilePath': result['audioFilePath'],
      'transcriptions': transcriptions,
      'speakerSegments': speakerSegments,
      'speakerCount': result['speakerCount'],
      'totalDuration': result['totalDuration'],
    };
  }

  // MARK: - Native Event Handler (Swift -> Flutter)

  @override
  void setNativeCallHandler(Future<dynamic> Function(MethodCall call)? handler) {
    if (handler != null) {
      methodChannel.setMethodCallHandler((call) async {
        return await handler(call);
      });
    } else {
      methodChannel.setMethodCallHandler(null);
    }
  }

  // MARK: - Listening (Recording + Window 통합)

  @override
  Future<bool> startListening({
    bool enableASR = true,
    bool enableDiarization = true,
    String asrEngine = 'fluid',
    String? sessionId,
    bool shouldScreenshotCapture = false,
  }) async {
    final success = await methodChannel.invokeMethod<bool>(
      'startListening',
      {
        'enableASR': enableASR,
        'enableDiarization': enableDiarization,
        'asrEngine': asrEngine,
        'shouldScreenshotCapture': shouldScreenshotCapture,
        if (sessionId != null) 'sessionId': sessionId,
      },
    );
    return success ?? false;
  }

  @override
  Future<Map<String, dynamic>?> stopListening() async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'stopListening',
    );
    if (result == null) return null;

    final transcriptions = (result['transcriptions'] as List<Object?>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final speakerSegments = (result['speakerSegments'] as List<Object?>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return {
      'audioFilePath': result['audioFilePath'],
      'transcriptions': transcriptions,
      'speakerSegments': speakerSegments,
      'speakerCount': result['speakerCount'],
      'totalDuration': result['totalDuration'],
    };
  }

  @override
  Future<void> cancelListening() async {
    await methodChannel.invokeMethod<void>('cancelListening');
  }

  // MARK: - Listening Window

  @override
  Future<bool> showListeningWindow() async {
    final success = await methodChannel.invokeMethod<bool>('showListeningWindow');
    return success ?? false;
  }

  @override
  Future<void> closeListeningWindow() async {
    await methodChannel.invokeMethod<void>('closeListeningWindow');
  }

  // MARK: - Window Management

  @override
  Future<bool> showWindow({
    String identifier = 'default',
    double width = 240,
    double height = 140,
    String position = 'screenCenter',
    String? anchor,
    double? offsetX,
    double? offsetY,
  }) async {
    final success = await methodChannel.invokeMethod<bool>(
      'showWindow',
      {
        'identifier': identifier,
        'width': width,
        'height': height,
        'position': position,
        if (anchor != null) 'anchor': anchor,
        if (offsetX != null) 'offsetX': offsetX,
        if (offsetY != null) 'offsetY': offsetY,
      },
    );
    return success ?? false;
  }

  @override
  Future<void> closeWindow({String identifier = 'default'}) async {
    await methodChannel.invokeMethod<void>(
      'closeWindow',
      {'identifier': identifier},
    );
  }

  @override
  Future<bool> isWindowVisible({String identifier = 'default'}) async {
    final visible = await methodChannel.invokeMethod<bool>(
      'isWindowVisible',
      {'identifier': identifier},
    );
    return visible ?? false;
  }

  @override
  Future<void> updateWindowPosition({
    String identifier = 'default',
    required String position,
  }) async {
    await methodChannel.invokeMethod<void>(
      'updateWindowPosition',
      {
        'identifier': identifier,
        'position': position,
      },
    );
  }

  @override
  Future<List<String>> getActiveWindows() async {
    final windows = await methodChannel.invokeMethod<List<Object?>>('getActiveWindows');
    if (windows == null) return [];
    return windows.map((e) => e.toString()).toList();
  }
}
