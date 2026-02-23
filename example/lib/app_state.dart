import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shadow_listening/shadow_listening.dart';

class AppState extends ChangeNotifier {
  final ShadowListening _plugin = ShadowListening();

  // Platform version
  String platformVersion = 'Unknown';
  String permissionResult = '';

  // Permission state
  bool micAllowed = false;
  bool sysAudioAllowed = false;
  bool screenRecordingAllowed = false;

  // Listening state
  String micListeningStatus = 'idle';
  String sysAudioListeningStatus = 'idle';

  // Recording state
  bool isRecording = false;
  String? recordingFilePath;

  // Whisper Model state
  bool whisperModelLoaded = false;
  bool whisperLoading = false;
  Map<String, dynamic>? whisperModelInfo;

  // Fluid ASR Model state
  bool fluidModelLoaded = false;
  bool fluidLoading = false;
  Map<String, dynamic>? fluidModelInfo;

  // Diarizer Model state
  bool diarizerModelLoaded = false;
  bool diarizerLoading = false;
  Map<String, dynamic>? diarizerModelInfo;

  // Model Prewarming state
  bool isPreWarming = false;
  Map<String, bool>? preWarmResult;

  // Transcription state
  bool isTranscribing = false;
  String selectedASREngine = 'fluid';
  List<Map<String, dynamic>>? transcriptionResults;

  // Diarization state
  bool isDiarizing = false;
  Map<String, dynamic>? diarizationResult;

  // Streaming Diarization state
  bool isStreamingDiarization = false;
  double streamingChunkDuration = 5.0;
  String? streamingDiarizationFilePath;
  Map<String, dynamic>? streamingDiarizationResult;

  // Unified Recording state
  bool isUnifiedRecording = false;
  bool unifiedEnableASR = true;
  bool unifiedEnableDiarization = true;
  String unifiedASREngine = 'fluid';
  String? unifiedRecordingFilePath;
  Map<String, dynamic>? unifiedRecordingResult;

  // Real-time chunk results from native
  List<Map<String, dynamic>> realtimeChunks = [];

  // Window state
  List<String> activeWindows = [];
  List<Map<String, dynamic>> windowEvents = [];

  // Listening state (Recording + Window 통합)
  bool isListening = false;
  bool listeningEnableASR = true;
  bool listeningEnableDiarization = true;
  String listeningASREngine = 'fluid';
  Map<String, dynamic>? listeningResult;

  // Capture target state
  Map<String, dynamic>? selectedCaptureTarget;

  ShadowListening get plugin => _plugin;

  void init() {
    debugPrint('hello world');
    initPlatformState();
    checkAllPermissionStatus();
    _setupNativeCallHandler();
    preWarmModels();
  }

  void _setupNativeCallHandler() {
    debugPrint('[Native] Setting up native call handler...');
    _plugin.setNativeCallHandler(_handleNativeCall);
    debugPrint('[Native] Native call handler set');
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    debugPrint('[Native] _handleNativeCall received: ${call.method}');

    if (call.method == 'onWindowEvent') {
      final event = Map<String, dynamic>.from(call.arguments as Map);
      debugPrint('[Native] Window event: ${event['event']} - ${event['windowId']}');
      windowEvents.insert(0, {...event, 'timestamp': DateTime.now().toIso8601String()});
      if (windowEvents.length > 20) windowEvents.removeLast();
      await refreshActiveWindows();
      notifyListeners();
      return null;
    }

    if (call.method == 'onCaptureTargetSelected') {
      final data = Map<String, dynamic>.from(call.arguments as Map);
      final type = data['type'] as String;
      debugPrint('[Native] Capture target selected: type=$type');
      debugPrint('[Native]   Full data: $data');
      selectedCaptureTarget = data;
      windowEvents.insert(0, {
        'event': 'captureTargetSelected',
        'type': type,
        'name': data['title'] ?? data['localizedName'] ?? type,
        'timestamp': DateTime.now().toIso8601String(),
      });
      if (windowEvents.length > 20) windowEvents.removeLast();
      notifyListeners();
      return null;
    }

    if (call.method == 'onListeningEnded') {
      final data = Map<String, dynamic>.from(call.arguments as Map);
      final reason = data['reason'] as String;
      final windowId = data['windowId'] as String;
      debugPrint('[Native] Listening ended: reason=$reason, windowId=$windowId');

      // ControlBar에서 cancel/confirm 시 Flutter 측 상태도 업데이트
      isListening = false;
      permissionResult = 'Listening ended ($reason)';

      windowEvents.insert(0, {'event': 'listeningEnded', 'reason': reason, 'windowId': windowId, 'timestamp': DateTime.now().toIso8601String()});
      if (windowEvents.length > 20) windowEvents.removeLast();
      await refreshActiveWindows();
      notifyListeners();
      return null;
    }

    if (call.method == 'onInPersonMeetingChanged') {
      final data = Map<String, dynamic>.from(call.arguments as Map);
      final isInPersonMeeting = data['isInPersonMeeting'] as bool;
      debugPrint('[Native] In-person meeting toggled: $isInPersonMeeting');
      return null;
    }

    if (call.method == 'onChunkProcessed') {
      final args = Map<String, dynamic>.from(call.arguments as Map);

      final chunkIndex = args['chunkIndex'] as int;
      final startTime = args['startTime'] as double;
      final endTime = args['endTime'] as double;
      final isFinalChunk = args['isFinalChunk'] as bool? ?? false;

      final micVADSegments = (args['micVADSegments'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final transcription = args['transcription'] != null ? Map<String, dynamic>.from(args['transcription'] as Map) : null;

      final diarizations = (args['diarizations'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      debugPrint('[Native] Chunk #$chunkIndex: ${startTime}s - ${endTime}s${isFinalChunk ? ' (FINAL)' : ''}');
      if (micVADSegments.isNotEmpty) {
        debugPrint('[Native]   MicVAD: ${micVADSegments.length} segments');
      }
      if (transcription != null) {
        debugPrint('[Native]   Transcription: ${transcription['text']}');
      }
      if (diarizations.isNotEmpty) {
        for (final d in diarizations) {
          debugPrint('[Native]   ${d['speakerId']}: ${d['startTime']}s - ${d['endTime']}s');
        }
      }

      realtimeChunks.add({
        'chunkIndex': chunkIndex,
        'startTime': startTime,
        'endTime': endTime,
        'isFinalChunk': isFinalChunk,
        'micVADSegments': micVADSegments,
        'transcription': transcription,
        'diarizations': diarizations,
      });
      notifyListeners();
    }

    if (call.method == 'onError') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final code = args['code'] as String;
      final message = args['message'] as String;
      debugPrint('[Native] ERROR: code=$code, message=$message');
      notifyListeners();
      return null;
    }

    return null;
  }

  Future<void> initPlatformState() async {
    try {
      platformVersion = await _plugin.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }
    notifyListeners();
  }

  Future<void> checkAllPermissionStatus() async {
    final mic = await _plugin.getMicPermissionStatus();
    final sysAudio = await _plugin.getSysAudioPermissionStatus();
    final screen = await _plugin.getScreenRecordingPermissionStatus();
    micAllowed = mic;
    sysAudioAllowed = sysAudio;
    screenRecordingAllowed = screen;
    notifyListeners();
  }

  Future<void> updateListeningStatus() async {
    final micStatus = await _plugin.getMicListeningStatus();
    final sysAudioStatus = await _plugin.getSysAudioListeningStatus();
    micListeningStatus = micStatus;
    sysAudioListeningStatus = sysAudioStatus;
    notifyListeners();
  }

  Future<void> checkPermission(String type) async {
    bool status;
    switch (type) {
      case 'mic':
        status = await _plugin.getMicPermissionStatus();
        break;
      case 'sysAudio':
        status = await _plugin.getSysAudioPermissionStatus();
        break;
      case 'screen':
        status = await _plugin.getScreenRecordingPermissionStatus();
        break;
      default:
        status = false;
    }
    permissionResult = '$type status: $status';
    notifyListeners();
  }

  Future<void> requestPermission(String type) async {
    bool granted;
    switch (type) {
      case 'mic':
        granted = await _plugin.requestMicPermission();
        break;
      case 'sysAudio':
        granted = await _plugin.requestSysAudioPermission();
        break;
      case 'screen':
        granted = await _plugin.requestScreenRecordingPermission();
        break;
      default:
        granted = false;
    }
    permissionResult = '$type request: $granted';
    notifyListeners();
  }

  // Mic Listening
  Future<void> startMicListening() async {
    final success = await _plugin.startMicListening();
    permissionResult = 'Mic start: $success';
    await updateListeningStatus();
  }

  Future<void> stopMicListening() async {
    await _plugin.stopMicListening();
    permissionResult = 'Mic stopped';
    await updateListeningStatus();
  }

  // System Audio Listening
  Future<void> startSysAudioListening() async {
    final success = await _plugin.startSysAudioListening();
    permissionResult = 'System audio start: $success';
    await updateListeningStatus();
  }

  Future<void> stopSysAudioListening() async {
    await _plugin.stopSysAudioListening();
    permissionResult = 'System audio stopped';
    await updateListeningStatus();
  }

  // Combined Recording
  Future<void> startRecording() async {
    final filePath = await _plugin.startRecording();
    isRecording = filePath != null;
    recordingFilePath = filePath;
    permissionResult = filePath != null ? 'Recording started' : 'Recording failed';
    notifyListeners();
  }

  Future<void> stopRecording() async {
    await _plugin.stopRecording();
    isRecording = false;
    permissionResult = 'Recording stopped: ${recordingFilePath?.split('/').last}';
    notifyListeners();
  }

  // Individual Recording Tests
  Future<void> startMicOnlyRecording() async {
    final filePath = await _plugin.startMicOnlyRecording();
    isRecording = filePath != null;
    recordingFilePath = filePath;
    permissionResult = filePath != null ? 'Mic-only recording started' : 'Failed';
    notifyListeners();
  }

  Future<void> startSysAudioOnlyRecording() async {
    final filePath = await _plugin.startSysAudioOnlyRecording();
    isRecording = filePath != null;
    recordingFilePath = filePath;
    permissionResult = filePath != null ? 'SysAudio-only recording started' : 'Failed';
    notifyListeners();
  }

  Future<void> stopIndividualRecording() async {
    await _plugin.stopIndividualRecording();
    isRecording = false;
    permissionResult = 'Stopped: ${recordingFilePath?.split('/').last}';
    notifyListeners();
  }

  // Mic + VAD Test
  Future<void> startMicWithVAD() async {
    final success = await _plugin.startMicWithVAD();
    isRecording = success;
    permissionResult = success ? 'Mic+VAD started (check Console.app)' : 'Failed';
    notifyListeners();
  }

  Future<void> stopMicWithVAD() async {
    await _plugin.stopMicWithVAD();
    isRecording = false;
    permissionResult = 'Mic+VAD stopped (check Console.app for results)';
    notifyListeners();
  }

  // Whisper Model
  Future<void> loadWhisperModel() async {
    whisperLoading = true;
    permissionResult = 'Loading Whisper model...';
    notifyListeners();

    final success = await _plugin.loadWhisperModel();
    final info = success ? await _plugin.getWhisperModelInfo() : null;

    whisperLoading = false;
    whisperModelLoaded = success;
    whisperModelInfo = info;
    permissionResult = success ? 'Whisper model loaded!' : 'Failed to load Whisper model';
    notifyListeners();
  }

  Future<void> unloadWhisperModel() async {
    await _plugin.unloadWhisperModel();
    whisperModelLoaded = false;
    whisperModelInfo = null;
    permissionResult = 'Whisper model unloaded';
    notifyListeners();
  }

  Future<void> checkWhisperModel() async {
    final loaded = await _plugin.isWhisperModelLoaded();
    final info = loaded ? await _plugin.getWhisperModelInfo() : null;
    whisperModelLoaded = loaded;
    whisperModelInfo = info;
    permissionResult = 'Whisper loaded: $loaded';
    notifyListeners();
  }

  // Fluid Model
  Future<void> loadFluidModel() async {
    fluidLoading = true;
    permissionResult = 'Loading Fluid ASR model...';
    notifyListeners();

    final success = await _plugin.loadFluidModel(version: 'v2');
    final info = success ? await _plugin.getFluidModelInfo() : null;

    fluidLoading = false;
    fluidModelLoaded = success;
    fluidModelInfo = info;
    permissionResult = success ? 'Fluid ASR model loaded!' : 'Failed to load Fluid ASR model';
    notifyListeners();
  }

  Future<void> unloadFluidModel() async {
    await _plugin.unloadFluidModel();
    fluidModelLoaded = false;
    fluidModelInfo = null;
    permissionResult = 'Fluid ASR model unloaded';
    notifyListeners();
  }

  Future<void> checkFluidModel() async {
    final loaded = await _plugin.isFluidModelLoaded();
    final info = loaded ? await _plugin.getFluidModelInfo() : null;
    fluidModelLoaded = loaded;
    fluidModelInfo = info;
    permissionResult = 'Fluid ASR loaded: $loaded';
    notifyListeners();
  }

  // Diarizer Model
  Future<void> loadDiarizerModel() async {
    diarizerLoading = true;
    permissionResult = 'Loading Diarizer model...';
    notifyListeners();

    final success = await _plugin.loadDiarizerModel();
    final info = success ? await _plugin.getDiarizerModelInfo() : null;

    diarizerLoading = false;
    diarizerModelLoaded = success;
    diarizerModelInfo = info;
    permissionResult = success ? 'Diarizer model loaded!' : 'Failed to load Diarizer model';
    notifyListeners();
  }

  Future<void> unloadDiarizerModel() async {
    await _plugin.unloadDiarizerModel();
    diarizerModelLoaded = false;
    diarizerModelInfo = null;
    permissionResult = 'Diarizer model unloaded';
    notifyListeners();
  }

  Future<void> checkDiarizerModel() async {
    final loaded = await _plugin.isDiarizerModelLoaded();
    final info = await _plugin.getDiarizerModelInfo();
    diarizerModelLoaded = loaded;
    diarizerModelInfo = info;
    permissionResult = 'Diarizer loaded: $loaded';
    notifyListeners();
  }

  // Model Prewarming
  Future<void> preWarmModels({bool asr = true, bool diarization = true, bool vad = true, String asrEngine = 'fluid'}) async {
    isPreWarming = true;
    preWarmResult = null;
    permissionResult = 'Pre-warming models...';
    notifyListeners();

    final result = await _plugin.preWarmModels(asr: asr, diarization: diarization, vad: vad, asrEngine: asrEngine);

    isPreWarming = false;
    preWarmResult = result;
    final succeeded = result.entries.where((e) => e.value).map((e) => e.key).toList();
    final failed = result.entries.where((e) => !e.value).map((e) => e.key).toList();
    permissionResult =
        'PreWarm done: ${succeeded.isNotEmpty ? "OK: ${succeeded.join(", ")}" : ""}${failed.isNotEmpty ? " Failed: ${failed.join(", ")}" : ""}';
    notifyListeners();
  }

  // Recording with Transcription
  Future<void> startRecordingWithTranscription() async {
    final filePath = await _plugin.startRecordingWithTranscription(asrEngine: selectedASREngine);
    isRecording = filePath != null;
    recordingFilePath = filePath;
    transcriptionResults = null;
    permissionResult = filePath != null ? 'Recording started (speak now...)' : 'Failed to start recording';
    notifyListeners();
  }

  Future<void> stopRecordingWithTranscription() async {
    isTranscribing = true;
    permissionResult = 'Transcribing...';
    notifyListeners();

    final results = await _plugin.stopRecordingWithTranscription();

    isRecording = false;
    isTranscribing = false;
    transcriptionResults = results;
    permissionResult = results != null ? 'Transcription complete: ${results.length} segments' : 'Transcription failed';
    notifyListeners();
  }

  void setSelectedASREngine(String engine) {
    selectedASREngine = engine;
    notifyListeners();
  }

  // Diarization Processing
  Future<void> processDiarization() async {
    if (recordingFilePath == null) return;

    isDiarizing = true;
    diarizationResult = null;
    permissionResult = 'Processing diarization...';
    notifyListeners();

    final result = await _plugin.processDiarization(recordingFilePath!);

    isDiarizing = false;
    diarizationResult = result;
    permissionResult = result != null ? 'Diarization complete: ${result['speakerCount']} speakers found' : 'Diarization failed';
    notifyListeners();
  }

  Future<void> resetDiarizer() async {
    await _plugin.resetDiarizer();
    diarizationResult = null;
    permissionResult = 'Diarizer reset (speaker IDs cleared)';
    notifyListeners();
  }

  // Streaming Diarization
  void setStreamingChunkDuration(double duration) {
    streamingChunkDuration = duration;
    notifyListeners();
  }

  Future<void> startRecordingWithDiarization() async {
    final filePath = await _plugin.startRecordingWithDiarization(chunkDuration: streamingChunkDuration);
    isStreamingDiarization = filePath != null;
    streamingDiarizationFilePath = filePath;
    streamingDiarizationResult = null;
    permissionResult = filePath != null ? 'Streaming diarization started (speak now...)' : 'Failed to start streaming diarization';
    notifyListeners();
  }

  Future<void> stopRecordingWithDiarization() async {
    permissionResult = 'Stopping and processing...';
    notifyListeners();

    final result = await _plugin.stopRecordingWithDiarization();

    isStreamingDiarization = false;
    streamingDiarizationResult = result;
    permissionResult = result != null ? 'Streaming diarization complete: ${result['speakerCount']} speakers' : 'Streaming diarization failed';
    notifyListeners();
  }

  // Unified Recording
  void setUnifiedEnableASR(bool value) {
    unifiedEnableASR = value;
    notifyListeners();
  }

  void setUnifiedEnableDiarization(bool value) {
    unifiedEnableDiarization = value;
    notifyListeners();
  }

  void setUnifiedASREngine(String engine) {
    unifiedASREngine = engine;
    notifyListeners();
  }

  Future<void> startUnifiedRecording() async {
    final filePath = await _plugin.startUnifiedRecording(
      enableASR: unifiedEnableASR,
      enableDiarization: unifiedEnableDiarization,
      asrEngine: unifiedASREngine,
    );
    isUnifiedRecording = filePath != null;
    unifiedRecordingFilePath = filePath;
    unifiedRecordingResult = null;
    realtimeChunks.clear();
    permissionResult = filePath != null ? 'Unified recording started (speak now...)' : 'Failed to start unified recording';
    notifyListeners();
  }

  Future<void> stopUnifiedRecording() async {
    permissionResult = 'Stopping and processing...';
    notifyListeners();

    final result = await _plugin.stopUnifiedRecording();

    isUnifiedRecording = false;
    unifiedRecordingResult = result;
    if (result != null) {
      final transcriptionCount = (result['transcriptions'] as List?)?.length ?? 0;
      final speakerCount = result['speakerCount'] ?? 0;
      permissionResult = 'Unified recording complete: $transcriptionCount transcriptions, $speakerCount speakers';
    } else {
      permissionResult = 'Unified recording failed';
    }
    notifyListeners();
  }

  // Listening (Recording + Window 통합)
  void setListeningEnableASR(bool value) {
    listeningEnableASR = value;
    notifyListeners();
  }

  void setListeningEnableDiarization(bool value) {
    listeningEnableDiarization = value;
    notifyListeners();
  }

  void setListeningASREngine(String engine) {
    listeningASREngine = engine;
    notifyListeners();
  }

  Future<void> startListening() async {
    realtimeChunks.clear();
    listeningResult = null;
    isListening = true;
    permissionResult = 'Starting listening (loading models + recording)...';
    notifyListeners();

    final success = await _plugin.startListening(
      enableASR: listeningEnableASR,
      enableDiarization: listeningEnableDiarization,
      asrEngine: listeningASREngine,
      sessionId: 'abcdefghijklmnop',
      shouldScreenshotCapture: true,
    );

    if (!success) {
      isListening = false;
      permissionResult = 'Failed to start listening';
    } else {
      permissionResult = 'Listening started';
    }
    notifyListeners();
  }

  Future<void> stopListeningFromFlutter() async {
    debugPrint("stopListening Called");
    permissionResult = 'Stopping listening...';
    notifyListeners();

    final result = await _plugin.stopListening();
    await _plugin.unloadModels(); // CRASH TEST: reproduce main app behavior

    isListening = false;
    listeningResult = result;
    if (result != null) {
      final transcriptionCount = (result['transcriptions'] as List?)?.length ?? 0;
      final speakerCount = result['speakerCount'] ?? 0;
      permissionResult = 'Listening complete: $transcriptionCount transcriptions, $speakerCount speakers';
    } else {
      permissionResult = 'Listening stopped (no results)';
    }
    notifyListeners();
  }

  /// CRASH TEST: Cancel listening without awaiting, then immediately unload models
  Future<void> cancelAndUnloadListening() async {
    permissionResult = 'Cancel + Unload (crash test)...';
    notifyListeners();
    // Fire cancel without awaiting — then immediately unload
    _plugin.cancelListening(); // no await!
    await _plugin.unloadModels();
    isListening = false;
    permissionResult = 'Cancel + Unload done (if no crash)';
    notifyListeners();
  }

  // Listening Window
  Future<void> showListeningWindow() async {
    final success = await _plugin.showListeningWindow();
    permissionResult = success ? 'Listening window shown' : 'Failed to show listening window';
    await refreshActiveWindows();
    notifyListeners();
  }

  Future<void> closeListeningWindow() async {
    await _plugin.closeListeningWindow();
    permissionResult = 'Listening window closed';
    await refreshActiveWindows();
    notifyListeners();
  }

  // Window Management
  Future<void> showTestWindow({
    String identifier = 'test',
    double width = 240,
    double height = 140,
    String position = 'screenCenter',
    String? anchor,
    double offsetX = 15,
    double offsetY = 0,
  }) async {
    final success = await _plugin.showWindow(
      identifier: identifier,
      width: width,
      height: height,
      position: position,
      anchor: anchor,
      offsetX: offsetX,
      offsetY: offsetY,
    );
    permissionResult = success ? 'Window "$identifier" shown' : 'Failed to show window';
    await refreshActiveWindows();
    notifyListeners();
  }

  Future<void> closeTestWindow(String identifier) async {
    await _plugin.closeWindow(identifier: identifier);
    permissionResult = 'Window "$identifier" closed';
    await refreshActiveWindows();
    notifyListeners();
  }

  Future<void> closeAllTestWindows() async {
    for (final id in List<String>.from(activeWindows)) {
      await _plugin.closeWindow(identifier: id);
    }
    permissionResult = 'All windows closed';
    await refreshActiveWindows();
    notifyListeners();
  }

  Future<void> updateTestWindowPosition(String identifier, String position) async {
    await _plugin.updateWindowPosition(identifier: identifier, position: position);
    permissionResult = 'Window "$identifier" moved to $position';
    notifyListeners();
  }

  Future<void> refreshActiveWindows() async {
    activeWindows = await _plugin.getActiveWindows();
    notifyListeners();
  }

  void clearWindowEvents() {
    windowEvents.clear();
    notifyListeners();
  }

  // Screenshot / Capture Target
  List<Map<String, dynamic>> enumeratedWindows = [];
  List<Map<String, dynamic>> enumeratedDisplays = [];
  String? updateCaptureTargetResult;

  Future<void> enumerateWindows() async {
    permissionResult = 'Enumerating windows...';
    notifyListeners();

    try {
      final result = await _plugin.enumerateWindows();
      enumeratedWindows = (result['windows'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      enumeratedDisplays = (result['displays'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      permissionResult = 'Found ${enumeratedWindows.length} windows, ${enumeratedDisplays.length} displays';
      debugPrint('[enumerateWindows] windows: $enumeratedWindows');
      debugPrint('[enumerateWindows] displays: $enumeratedDisplays');
    } catch (e) {
      permissionResult = 'enumerateWindows failed: $e';
      debugPrint('[enumerateWindows] error: $e');
    }
    notifyListeners();
  }

  Future<void> updateCaptureTarget(Map<String, dynamic> targetConfig) async {
    permissionResult = 'Updating capture target: ${targetConfig['type']}...';
    notifyListeners();

    try {
      final result = await _plugin.updateCaptureTarget(targetConfig);
      updateCaptureTargetResult = result?.toString();
      permissionResult = 'Capture target updated: ${targetConfig['type']}';
      debugPrint('[updateCaptureTarget] result: $result');
    } on PlatformException catch (e) {
      updateCaptureTargetResult = null;
      permissionResult = 'updateCaptureTarget failed: ${e.code} - ${e.message}';
      debugPrint('[updateCaptureTarget] error: ${e.code} - ${e.message}');
    }
    notifyListeners();
  }
}
