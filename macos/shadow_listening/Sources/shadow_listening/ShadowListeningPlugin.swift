import AVFAudio
import Cocoa
import FlutterMacOS
import OSLog

public class ShadowListeningPlugin: NSObject, FlutterPlugin {
  private var micService: MicAudioService?
  private var sysAudioService: SystemAudioService?
  private var audioMixer: AudioMixer?
  private var audioFileWriter: AudioFileWriter?
  private var micVADService: MicVADService?
  private var whisperService: WhisperASRService?
  private var fluidService: FluidASRService?
  private var diarizerService: FluidDiarizerService?
  private var unifiedRecordingService: UnifiedRecordingServiceV2?
  private var micStreamTask: Task<Void, Never>?
  private var sysAudioStreamTask: Task<Void, Never>?
  private var recordingTask: Task<Void, Never>?
  private var recordedFileURL: URL?
  private var selectedASREngine: String = "fluid"
  private let logger = Logger(subsystem: "shadow_listening", category: "Plugin")

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "shadow_listening", binaryMessenger: registrar.messenger)
    let instance = ShadowListeningPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Initialize FlutterBridge for Swift -> Flutter communication
    FlutterBridge.shared.setChannel(channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        Task {
            try await VADService()
        }

    // MARK: - Mic Permission
    case "getMicPermissionStatus":
      result(PermissionService.shared.checkStatus(for: .mic))
    case "requestMicPermission":
      PermissionService.shared.requestAccess(for: .mic) { granted in
        result(granted)
      }

    // MARK: - System Audio Permission
    case "getSysAudioPermissionStatus":
      result(PermissionService.shared.checkStatus(for: .sysAudio))
    case "requestSysAudioPermission":
      PermissionService.shared.requestAccess(for: .sysAudio) { granted in
        result(granted)
      }

    // MARK: - Screen Recording Permission
    case "getScreenRecordingPermissionStatus":
      result(PermissionService.shared.checkStatus(for: .screenRecording))
    case "requestScreenRecordingPermission":
      PermissionService.shared.requestAccess(for: .screenRecording) { granted in
        result(granted)
      }

    // MARK: - Mic Listening
    case "startMicListening":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(false) }
            return
          }

          if self.micService == nil {
            self.micService = MicAudioService()
          }
          if self.audioMixer == nil {
            self.audioMixer = try AudioMixer()
          }
          try self.micService?.startListening()

          // AsyncStream 소비 + AudioMixer로 믹싱
          self.micStreamTask = Task { [weak self] in
            guard let stream = self?.micService?.audioStream,
                  let mixer = self?.audioMixer else { return }
            for await micBuffer in stream {
              // System Audio와 믹싱
              if let mixed = mixer.mix(micBuffer: micBuffer) {
                // TODO: VAD 또는 다음 단계로 전달
                _ = mixed
              }
            }
          }

          self.logger.info("Mic listening started")
          DispatchQueue.main.async { result(true) }
        } catch {
          self?.logger.error("Failed to start mic listening: \(error.localizedDescription)")
          DispatchQueue.main.async { result(false) }
        }
      }

    case "stopMicListening":
      micStreamTask?.cancel()
      micStreamTask = nil
      micService?.stopListening()
      logger.info("Mic listening stopped")
      result(nil)

    case "getMicListeningStatus":
      let status = micService?.state.rawValue ?? "idle"
      result(status)

    // MARK: - Mic + VAD Test (Debug)
    case "startMicWithVAD":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(false) }
            return
          }

          // MicVADService 초기화
          if self.micVADService == nil {
            self.micVADService = MicVADService()
            try await self.micVADService?.initialize()
            self.logger.info("[Test] MicVADService initialized")
          }

          // MicService 초기화
          if self.micService == nil {
            self.micService = MicAudioService()
          }

          // VAD 처리 시작 (시간 0 동기화)
          try await self.micVADService?.startProcessing()
          self.logger.info("[Test] VAD processing started")

          // MicService 시작
          try self.micService?.startListening()
          self.logger.info("[Test] Mic listening started")

          // Mic Audio → VAD only (no mixing, no file writing)
          self.micStreamTask = Task { [weak self] in
            guard let stream = self?.micService?.audioStream else { return }
            for await micBuffer in stream {
              // VAD 처리만
              let prob = try? await self?.micVADService?.processBuffer(micBuffer)
              // 매 버퍼마다 probability 로그 (디버그용)
              if let p = prob {
                self?.logger.debug("[Test] VAD prob: \(String(format: "%.3f", p))")
              }
            }
          }

          self.logger.info("[Test] Mic with VAD started")
          DispatchQueue.main.async { result(true) }
        } catch {
          self?.logger.error("[Test] Failed to start mic with VAD: \(error.localizedDescription)")
          DispatchQueue.main.async { result(false) }
        }
      }

    case "stopMicWithVAD":
      // VAD 결과 로그
      let timestamps = micVADService?.stopProcessing() ?? []
      logger.info("[Test] Stopped with \(timestamps.count) voice segments")

      // Task 정리
      micStreamTask?.cancel()
      micStreamTask = nil

      // Mic 정지
      micService?.stopListening()

      result(nil)

    // MARK: - System Audio Listening
    case "startSysAudioListening":
      do {
        if sysAudioService == nil {
          sysAudioService = SystemAudioService()
        }
        if audioMixer == nil {
          audioMixer = try AudioMixer()
        }
        try sysAudioService?.startListening()

        // AsyncStream 소비 + RingBuffer에 추가
        sysAudioStreamTask = Task { [weak self] in
          guard let stream = self?.sysAudioService?.audioStream,
                let mixer = self?.audioMixer else { return }
          for await buffer in stream {
            // RingBuffer에 추가 (Mic 타이밍에 맞춰 읽힘)
            mixer.enqueueSysAudio(buffer)
          }
        }

        logger.info("System audio listening started")
        result(true)
      } catch {
        logger.error("Failed to start system audio listening: \(error.localizedDescription)")
        result(false)
      }

    case "stopSysAudioListening":
      sysAudioStreamTask?.cancel()
      sysAudioStreamTask = nil
      sysAudioService?.stopListening()
      logger.info("System audio listening stopped")
      result(nil)

    case "getSysAudioListeningStatus":
      let status = sysAudioService?.state.rawValue ?? "idle"
      result(status)

    // MARK: - Combined Recording (Mic + System Audio)
    case "startRecording":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(nil) }
            return
          }

          // AudioMixer 초기화
          if self.audioMixer == nil {
            self.audioMixer = try AudioMixer()
          }

          // AudioFileWriter 초기화
          if self.audioFileWriter == nil {
            self.audioFileWriter = try AudioFileWriter()
          }

          // MicVADService 초기화 (VAD 모델 로드)
          if self.micVADService == nil {
            self.micVADService = MicVADService()
            do {
              try await self.micVADService?.initialize()
            } catch {
              self.logger.warning("VAD initialization failed, proceeding without voice detection: \(error.localizedDescription)")
              self.micVADService = nil
            }
          }

          // MicService 초기화
          if self.micService == nil {
            self.micService = MicAudioService()
          }

          // SystemAudioService 초기화 및 시작
          if self.sysAudioService == nil {
            self.sysAudioService = SystemAudioService()
          }
          try self.sysAudioService?.startListening()

          // 파일 쓰기 시작
          let outputURL = AudioFileWriter.defaultOutputURL(filename: "mixed_audio")
          try self.audioFileWriter?.startWriting(to: outputURL)

          // System Audio → RingBuffer
          self.sysAudioStreamTask = Task { [weak self] in
            guard let stream = self?.sysAudioService?.audioStream,
                  let mixer = self?.audioMixer else { return }
            for await buffer in stream {
              mixer.enqueueSysAudio(buffer)
            }
          }

          // VAD 처리 시작 (시간 0 동기화)
          try? await self.micVADService?.startProcessing()

          // MicService 시작 (첫 버퍼 = 시간 0)
          try self.micService?.startListening()

          // Mic Audio → VAD → Mix → File
          self.recordingTask = Task { [weak self] in
            guard let stream = self?.micService?.audioStream,
                  let mixer = self?.audioMixer,
                  let writer = self?.audioFileWriter else { return }
            for await micBuffer in stream {
              // VAD 처리 (실패해도 녹음 계속)
              try? await self?.micVADService?.processBuffer(micBuffer)

              // Mix + Write
              if let mixed = mixer.mix(micBuffer: micBuffer) {
                writer.write(mixed)
              }
            }
          }

          self.logger.info("Recording started: \(outputURL.lastPathComponent)")
          DispatchQueue.main.async { result(outputURL.path) }
        } catch {
          self?.logger.error("Failed to start recording: \(error.localizedDescription)")
          DispatchQueue.main.async { result(nil) }
        }
      }

    case "stopRecording":
      // VAD 결과 저장 및 로그 출력
      let timestamps = micVADService?.stopProcessing() ?? []
      logger.info("Recording stopped with \(timestamps.count) voice segments")

      // Tasks 정리
      recordingTask?.cancel()
      recordingTask = nil
      sysAudioStreamTask?.cancel()
      sysAudioStreamTask = nil

      // Services 정지
      micService?.stopListening()
      sysAudioService?.stopListening()

      // 파일 쓰기 완료
      audioFileWriter?.stopWriting()

      // Mixer 리셋
      audioMixer?.reset()

      result(nil)

    case "getRecordingStatus":
      let isRecording = audioFileWriter?.isWriting ?? false
      result(isRecording)

    // MARK: - Debug: Individual Recording Tests
    case "startMicOnlyRecording":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(nil) }
            return
          }

          if self.audioFileWriter == nil {
            self.audioFileWriter = try AudioFileWriter()
          }
          if self.micService == nil {
            self.micService = MicAudioService()
          }
          try self.micService?.startListening()

          let outputURL = AudioFileWriter.defaultOutputURL(filename: "mic_only")
          try self.audioFileWriter?.startWriting(to: outputURL)

          self.recordingTask = Task { [weak self] in
            guard let stream = self?.micService?.audioStream,
                  let writer = self?.audioFileWriter else { return }
            for await micBuffer in stream {
              writer.write(micBuffer)
            }
          }

          self.logger.info("Mic-only recording started: \(outputURL.lastPathComponent)")
          DispatchQueue.main.async { result(outputURL.path) }
        } catch {
          self?.logger.error("Failed to start mic-only recording: \(error.localizedDescription)")
          DispatchQueue.main.async { result(nil) }
        }
      }

    case "startSysAudioOnlyRecording":
      do {
        if audioFileWriter == nil {
          audioFileWriter = try AudioFileWriter()
        }
        if sysAudioService == nil {
          sysAudioService = SystemAudioService()
        }
        try sysAudioService?.startListening()

        let outputURL = AudioFileWriter.defaultOutputURL(filename: "sysaudio_only")
        try audioFileWriter?.startWriting(to: outputURL)

        recordingTask = Task { [weak self] in
          guard let stream = self?.sysAudioService?.audioStream,
                let writer = self?.audioFileWriter else { return }
          for await buffer in stream {
            writer.write(buffer)
          }
        }

        logger.info("SysAudio-only recording started: \(outputURL.lastPathComponent)")
        result(outputURL.path)
      } catch {
        logger.error("Failed to start sysaudio-only recording: \(error.localizedDescription)")
        result(nil)
      }

    case "stopIndividualRecording":
      recordingTask?.cancel()
      recordingTask = nil
      micService?.stopListening()
      sysAudioService?.stopListening()
      audioFileWriter?.stopWriting()
      logger.info("Individual recording stopped")
      result(nil)

    // MARK: - Whisper ASR Model Management
    case "loadWhisperModel":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(false) }
            return
          }

          let args = call.arguments as? [String: Any]
          let modelName = args?["modelName"] as? String ?? "ggml-large-v3-turbo-q5_0.bin"

          // 기존 서비스가 있으면 정리
          if self.whisperService != nil {
            self.whisperService?.cleanup()
            self.whisperService = nil
          }

            self.whisperService = WhisperASRService(modelName: modelName, useGPU: true, language: "auto")  // 기본값 "auto" - nullptr로 전달
          try await self.whisperService?.initialize()

          self.logger.info("[Whisper] Model loaded: \(modelName)")
          DispatchQueue.main.async { result(true) }
        } catch {
          self?.logger.error("[Whisper] Load failed: \(error.localizedDescription)")
          DispatchQueue.main.async { result(false) }
        }
      }

    case "unloadWhisperModel":
      // cleanup()은 deinit에서 호출되므로 여기서는 참조만 해제
      whisperService = nil
      logger.info("[Whisper] Model unloaded")
      result(nil)

    case "isWhisperModelLoaded":
      result(whisperService?.isInitialized ?? false)

    case "getWhisperModelInfo":
      if let service = whisperService, service.isInitialized {
        result([
          "modelPath": WhisperASRService.defaultModelPath(modelName: "ggml-large-v3-turbo-q5_0.bin"),
          "isLoaded": true,
          "useGPU": true,
          "language": "en"
        ] as [String: Any])
      } else {
        result(nil)
      }

    // MARK: - Fluid ASR Model Management
    case "loadFluidModel":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(false) }
            return
          }

          let args = call.arguments as? [String: Any]
          let versionStr = args?["version"] as? String ?? "v2"
          let version: FluidASRService.ModelVersion = versionStr == "v3" ? .multilingual : .english

          // 기존 서비스가 있으면 정리
          if self.fluidService != nil {
            self.fluidService?.cleanup()
            self.fluidService = nil
          }

          self.fluidService = FluidASRService(version: version)
          try await self.fluidService?.initialize()

          self.logger.info("[FluidASR] Model loaded: \(version.rawValue)")
          DispatchQueue.main.async { result(true) }
        } catch {
          self?.logger.error("[FluidASR] Load failed: \(error.localizedDescription)")
          DispatchQueue.main.async { result(false) }
        }
      }

    case "unloadFluidModel":
      fluidService?.cleanup()
      fluidService = nil
      logger.info("[FluidASR] Model unloaded")
      result(nil)

    case "isFluidModelLoaded":
      result(fluidService?.isInitialized ?? false)

    case "getFluidModelInfo":
      if let service = fluidService, service.isInitialized {
        result([
          "version": "v2",
          "isLoaded": true
        ] as [String: Any])
      } else {
        result(nil)
      }

    // MARK: - Model Prewarming
    case "preWarmModels":
      Task.detached { [weak self] in
        guard let self = self else {
          DispatchQueue.main.async {
            result(["asr": false, "diarization": false, "vad": false] as [String: Bool])
          }
          return
        }

        let args = call.arguments as? [String: Any]
        let warmASR = args?["asr"] as? Bool ?? true
        let warmDiarization = args?["diarization"] as? Bool ?? true
        let warmVAD = args?["vad"] as? Bool ?? true
        let asrEngine = args?["asrEngine"] as? String ?? "fluid"

        var results: [String: Bool] = [:]

        // Pre-warm VAD (using temporary instance)
        if warmVAD {
          do {
            let tempVAD = VADService()
            try await tempVAD.initialize()
            // VADService has no explicit cleanup(); resources released on deinit
            self.logger.info("[PreWarm] VAD prewarmed successfully")
            results["vad"] = true
          } catch {
            self.logger.error("[PreWarm] VAD prewarm failed: \(error.localizedDescription)")
            results["vad"] = false
          }
        }

        // Pre-warm ASR (using temporary instance)
        if warmASR {
          do {
            if asrEngine == "whisper" {
              let tempWhisper = WhisperASRService(
                modelName: "ggml-large-v3-turbo-q5_0.bin",
                useGPU: true,
                language: "auto"
              )
              try await tempWhisper.initialize()
              tempWhisper.cleanup()
              self.logger.info("[PreWarm] Whisper ASR prewarmed successfully")
            } else {
              let versionStr = args?["asrVersion"] as? String ?? "v2"
              let version: FluidASRService.ModelVersion = versionStr == "v3" ? .multilingual : .english
              let tempFluid = FluidASRService(version: version)
              try await tempFluid.initialize()
              tempFluid.cleanup()
              self.logger.info("[PreWarm] Fluid ASR prewarmed successfully")
            }
            results["asr"] = true
          } catch {
            self.logger.error("[PreWarm] ASR prewarm failed: \(error.localizedDescription)")
            results["asr"] = false
          }
        }

        // Pre-warm Diarization (using temporary instance)
        if warmDiarization {
          do {
            let tempDiarizer = FluidDiarizerService()
            try await tempDiarizer.initialize()
            tempDiarizer.cleanup()
            self.logger.info("[PreWarm] Diarizer prewarmed successfully")
            results["diarization"] = true
          } catch {
            self.logger.error("[PreWarm] Diarizer prewarm failed: \(error.localizedDescription)")
            results["diarization"] = false
          }
        }

        self.logger.info("[PreWarm] Completed: \(results)")
        DispatchQueue.main.async { result(results) }
      }

    // MARK: - Recording with Transcription
    case "startRecordingWithTranscription":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(nil) }
            return
          }

          let args = call.arguments as? [String: Any]
          self.selectedASREngine = args?["asrEngine"] as? String ?? "fluid"

          // AudioMixer 초기화
          if self.audioMixer == nil {
            self.audioMixer = try AudioMixer()
          }

          // AudioFileWriter 초기화
          if self.audioFileWriter == nil {
            self.audioFileWriter = try AudioFileWriter()
          }

          // MicVADService 초기화 (VAD 모델 로드)
          if self.micVADService == nil {
            self.micVADService = MicVADService()
            do {
              try await self.micVADService?.initialize()
            } catch {
              self.logger.warning("[Transcription] VAD init failed: \(error.localizedDescription)")
              self.micVADService = nil
            }
          }

          // MicService 초기화
          if self.micService == nil {
            self.micService = MicAudioService()
          }

          // SystemAudioService 초기화 및 시작
          if self.sysAudioService == nil {
            self.sysAudioService = SystemAudioService()
          }
          try self.sysAudioService?.startListening()

          // 파일 쓰기 시작
          let outputURL = AudioFileWriter.defaultOutputURL(filename: "transcription_audio")
          try self.audioFileWriter?.startWriting(to: outputURL)
          self.recordedFileURL = outputURL

          // System Audio → RingBuffer
          self.sysAudioStreamTask = Task { [weak self] in
            guard let stream = self?.sysAudioService?.audioStream,
                  let mixer = self?.audioMixer else { return }
            for await buffer in stream {
              mixer.enqueueSysAudio(buffer)
            }
          }

          // VAD 처리 시작 (시간 0 동기화)
          try? await self.micVADService?.startProcessing()

          // MicService 시작 (첫 버퍼 = 시간 0)
          try self.micService?.startListening()

          // Mic Audio → VAD → Mix → File
          self.recordingTask = Task { [weak self] in
            guard let stream = self?.micService?.audioStream,
                  let mixer = self?.audioMixer,
                  let writer = self?.audioFileWriter else { return }
            for await micBuffer in stream {
              // VAD 처리 (실패해도 녹음 계속)
              try? await self?.micVADService?.processBuffer(micBuffer)

              // Mix + Write
              if let mixed = mixer.mix(micBuffer: micBuffer) {
                writer.write(mixed)
              }
            }
          }

          self.logger.info("[Transcription] Recording started: \(outputURL.lastPathComponent), ASR: \(self.selectedASREngine)")
          DispatchQueue.main.async { result(outputURL.path) }
        } catch {
          self?.logger.error("[Transcription] Failed to start: \(error.localizedDescription)")
          DispatchQueue.main.async { result(nil) }
        }
      }

    case "stopRecordingWithTranscription":
      Task.detached { [weak self] in
        guard let self = self else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        // 1. VAD 세그먼트 가져오기
        let vadSegments = self.micVADService?.stopProcessing() ?? []
        self.logger.info("[Transcription] VAD detected \(vadSegments.count) segments")

        // 2. 녹음 중지
        self.recordingTask?.cancel()
        self.recordingTask = nil
        self.sysAudioStreamTask?.cancel()
        self.sysAudioStreamTask = nil
        self.micService?.stopListening()
        self.sysAudioService?.stopListening()
        self.audioFileWriter?.stopWriting()
        self.audioMixer?.reset()

        // 3. ASR 서비스 선택
        let asrService: ASRServiceProtocol? =
          self.selectedASREngine == "whisper" ? self.whisperService : self.fluidService

        guard let asr = asrService, asr.isInitialized else {
          self.logger.error("[Transcription] ASR service not loaded (engine: \(self.selectedASREngine))")
          DispatchQueue.main.async { result(nil) }
          return
        }

        guard let fileURL = self.recordedFileURL else {
          self.logger.error("[Transcription] No recorded file URL")
          DispatchQueue.main.async { result(nil) }
          return
        }

        // 4. 각 VAD 세그먼트 전사
        var transcriptions: [[String: Any]] = []

        for segment in vadSegments {
          guard let endTime = segment.endTime else {
            self.logger.debug("[Transcription] Skipping ongoing segment at \(segment.startTime)")
            continue
          }

          do {
            // WAV 파일에서 샘플 추출
            let samples = try self.extractSamples(
              from: fileURL,
              startTime: segment.startTime,
              endTime: endTime
            )

            self.logger.info("[Transcription] Processing segment \(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", endTime))s (\(samples.count) samples)")

            // ASR 전사
            let transcription = try await asr.processSegment(
              samples: samples,
              startTime: segment.startTime,
              endTime: endTime
            )

            transcriptions.append([
              "startTime": transcription.startTime,
              "endTime": transcription.endTime,
              "text": transcription.text,
              "confidence": transcription.confidence
            ])

            self.logger.info("[Transcription] Result: '\(transcription.text)' (conf: \(String(format: "%.2f", transcription.confidence)))")
          } catch {
            self.logger.error("[Transcription] Segment failed: \(error.localizedDescription)")
          }
        }

        self.logger.info("[Transcription] Completed with \(transcriptions.count) transcriptions")
        DispatchQueue.main.async { result(transcriptions) }
      }

    // MARK: - Diarizer Model Management
    case "loadDiarizerModel":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(false) }
            return
          }

          // 기존 서비스가 있으면 정리
          if self.diarizerService != nil {
            self.diarizerService?.cleanup()
            self.diarizerService = nil
          }

          self.diarizerService = FluidDiarizerService()
          try await self.diarizerService?.initialize()

          self.logger.info("[Diarizer] Model loaded successfully")
          DispatchQueue.main.async { result(true) }
        } catch {
          self?.logger.error("[Diarizer] Load failed: \(error.localizedDescription)")
          DispatchQueue.main.async { result(false) }
        }
      }

    case "unloadDiarizerModel":
      diarizerService?.cleanup()
      diarizerService = nil
      logger.info("[Diarizer] Model unloaded")
      result(nil)

    case "unloadModels":
      unloadModels()
      result(nil)

    case "isDiarizerModelLoaded":
      result(diarizerService?.isInitialized ?? false)

    case "getDiarizerModelInfo":
      if let service = diarizerService, service.isInitialized {
        result([
          "modelPath": FluidDiarizerService.modelDirectoryPath(),
          "isLoaded": true,
          "modelsExist": FluidDiarizerService.modelsExist()
        ] as [String: Any])
      } else {
        result([
          "modelPath": FluidDiarizerService.modelDirectoryPath(),
          "isLoaded": false,
          "modelsExist": FluidDiarizerService.modelsExist()
        ] as [String: Any])
      }

    // MARK: - Diarization Processing
    case "processDiarization":
      Task.detached { [weak self] in
        guard let self = self else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        let args = call.arguments as? [String: Any]
        guard let audioFilePath = args?["audioFilePath"] as? String else {
          self.logger.error("[Diarizer] Missing audioFilePath argument")
          DispatchQueue.main.async { result(nil) }
          return
        }

        guard let diarizer = self.diarizerService, diarizer.isInitialized else {
          self.logger.error("[Diarizer] Service not loaded")
          DispatchQueue.main.async { result(nil) }
          return
        }

        let audioURL = URL(fileURLWithPath: audioFilePath)

        guard FileManager.default.fileExists(atPath: audioFilePath) else {
          self.logger.error("[Diarizer] Audio file not found: \(audioFilePath)")
          DispatchQueue.main.async { result(nil) }
          return
        }

        do {
          let diarizationResult = try await diarizer.processFile(audioURL)

          // SpeakerSegment → Dictionary 변환
          let segments: [[String: Any]] = diarizationResult.segments.map { segment in
            [
              "speakerId": segment.speakerId,
              "startTime": segment.startTime,
              "endTime": segment.endTime,
              "confidence": segment.confidence
            ]
          }

          let resultDict: [String: Any] = [
            "segments": segments,
            "speakerCount": diarizationResult.speakerCount,
            "processingTime": diarizationResult.processingTime,
            "audioDuration": diarizationResult.audioDuration,
            "rtfx": diarizationResult.rtfx
          ]

          self.logger.info("[Diarizer] Completed: \(segments.count) segments, \(diarizationResult.speakerCount) speakers")
          DispatchQueue.main.async { result(resultDict) }
        } catch {
          self.logger.error("[Diarizer] Processing failed: \(error.localizedDescription)")
          DispatchQueue.main.async { result(nil) }
        }
      }

    case "resetDiarizer":
      Task.detached { [weak self] in
        await self?.diarizerService?.reset()
        self?.logger.info("[Diarizer] Reset completed")
        DispatchQueue.main.async { result(nil) }
      }

    // MARK: - Streaming Diarization
    case "startRecordingWithDiarization":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(nil) }
            return
          }

          let args = call.arguments as? [String: Any]
          let chunkDuration = args?["chunkDuration"] as? Double ?? 5.0

          // Diarizer 초기화 확인
          guard let diarizer = self.diarizerService, diarizer.isInitialized else {
            self.logger.error("[StreamingDiarization] Diarizer not loaded. Call loadDiarizerModel() first.")
            DispatchQueue.main.async { result(nil) }
            return
          }

          // AudioMixer 초기화
          if self.audioMixer == nil {
            self.audioMixer = try AudioMixer()
          }

          // AudioFileWriter 초기화
          if self.audioFileWriter == nil {
            self.audioFileWriter = try AudioFileWriter()
          }

          // MicService 초기화
          if self.micService == nil {
            self.micService = MicAudioService()
          }

          // SystemAudioService 초기화 및 시작
          if self.sysAudioService == nil {
            self.sysAudioService = SystemAudioService()
          }
          try self.sysAudioService?.startListening()

          // 파일 쓰기 시작
          let outputURL = AudioFileWriter.defaultOutputURL(filename: "diarization_audio")
          try self.audioFileWriter?.startWriting(to: outputURL)
          self.recordedFileURL = outputURL

          // System Audio → RingBuffer
          self.sysAudioStreamTask = Task { [weak self] in
            guard let stream = self?.sysAudioService?.audioStream,
                  let mixer = self?.audioMixer else { return }
            for await buffer in stream {
              mixer.enqueueSysAudio(buffer)
            }
          }

          // Diarization 스트리밍 세션 시작
          await diarizer.startStreamingSession(chunkDuration: chunkDuration)

          // MicService 시작
          try self.micService?.startListening()

          // Mic Audio → Mix → File + Diarization
          self.recordingTask = Task { [weak self] in
            guard let stream = self?.micService?.audioStream,
                  let mixer = self?.audioMixer,
                  let writer = self?.audioFileWriter,
                  let diarizer = self?.diarizerService else { return }

            for await micBuffer in stream {
              // Mix + Write
              if let mixed = mixer.mix(micBuffer: micBuffer) {
                writer.write(mixed)

                // Diarization 처리 (서비스에 위임)
                if let floatData = mixed.floatChannelData?[0] {
                  let samples = Array(UnsafeBufferPointer(
                    start: floatData,
                    count: Int(mixed.frameLength)
                  ))

                  if let newSegments = try? await diarizer.appendSamples(samples) {
                    self?.logger.debug("[StreamingDiarization] +\(newSegments.count) segments")
                  }
                }
              }
            }
          }

          self.logger.info("[StreamingDiarization] Started: chunk=\(chunkDuration)s, file=\(outputURL.lastPathComponent)")
          DispatchQueue.main.async { result(outputURL.path) }
        } catch {
          self?.logger.error("[StreamingDiarization] Failed to start: \(error.localizedDescription)")
          DispatchQueue.main.async { result(nil) }
        }
      }

    case "stopRecordingWithDiarization":
      Task.detached { [weak self] in
        guard let self = self else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        // Tasks 정리
        self.recordingTask?.cancel()
        self.recordingTask = nil
        self.sysAudioStreamTask?.cancel()
        self.sysAudioStreamTask = nil

        // Services 정지
        self.micService?.stopListening()
        self.sysAudioService?.stopListening()
        self.audioFileWriter?.stopWriting()
        self.audioMixer?.reset()

        // Diarization 세션 종료 및 결과 가져오기
        guard let diarizer = self.diarizerService else {
          self.logger.error("[StreamingDiarization] Diarizer not available")
          DispatchQueue.main.async { result(nil) }
          return
        }

        do {
          let allSegments = try await diarizer.finishStreamingSession()

          // SpeakerSegment → Dictionary 변환
          let segments: [[String: Any]] = allSegments.map { segment in
            [
              "speakerId": segment.speakerId,
              "startTime": segment.startTime,
              "endTime": segment.endTime,
              "confidence": segment.confidence
            ]
          }

          let speakerCount = Set(allSegments.map { $0.speakerId }).count

          let resultDict: [String: Any] = [
            "segments": segments,
            "speakerCount": speakerCount,
            "totalDuration": diarizer.currentStreamingTime,
            "audioFilePath": self.recordedFileURL?.path ?? ""
          ]

          self.logger.info("[StreamingDiarization] Completed: \(segments.count) segments, \(speakerCount) speakers")
          DispatchQueue.main.async { result(resultDict) }
        } catch {
          self.logger.error("[StreamingDiarization] Failed to finish: \(error.localizedDescription)")
          DispatchQueue.main.async { result(nil) }
        }
      }

    // MARK: - Unified Recording (ASR + Diarization)
    case "startUnifiedRecording":
      Task.detached { [weak self] in
        do {
          guard let self = self else {
            DispatchQueue.main.async { result(nil) }
            return
          }

          let args = call.arguments as? [String: Any]
          let enableASR = args?["enableASR"] as? Bool ?? true
          let enableDiarization = args?["enableDiarization"] as? Bool ?? true
          let asrEngine = args?["asrEngine"] as? String ?? "fluid"

          // ASR 서비스 선택 (활성화된 경우에만)
          let asrService: ASRServiceProtocol?
          if enableASR {
            if asrEngine == "whisper" {
              guard let whisper = self.whisperService, whisper.isInitialized else {
                self.logger.error("[UnifiedRecording] Whisper model not loaded")
                DispatchQueue.main.async { result(nil) }
                return
              }
              asrService = whisper
            } else {
              guard let fluid = self.fluidService, fluid.isInitialized else {
                self.logger.error("[UnifiedRecording] Fluid ASR model not loaded")
                DispatchQueue.main.async { result(nil) }
                return
              }
              asrService = fluid
            }
          } else {
            asrService = nil
          }

          // Diarizer 확인 (활성화된 경우에만)
          if enableDiarization {
            guard let diarizer = self.diarizerService, diarizer.isInitialized else {
              self.logger.error("[UnifiedRecording] Diarizer model not loaded")
              DispatchQueue.main.async { result(nil) }
              return
            }
          }

          // 서비스 초기화
          if self.unifiedRecordingService == nil {
            self.unifiedRecordingService = UnifiedRecordingServiceV2()
          }

          let config = UnifiedRecordingServiceV2.Config(
            enableASR: enableASR,
            enableDiarization: enableDiarization,
            enableSystemAudio: true,
            asrEngine: asrEngine
          )

          let outputURL = try await self.unifiedRecordingService?.startRecording(
            config: config,
            asrService: asrService,
            diarizerService: self.diarizerService
          )

          self.logger.info("[UnifiedRecording] Started: ASR=\(enableASR), Diarization=\(enableDiarization), engine=\(asrEngine)")
          DispatchQueue.main.async { result(outputURL?.path) }
        } catch {
          self?.logger.error("[UnifiedRecording] Failed to start: \(error.localizedDescription)")
          DispatchQueue.main.async { result(nil) }
        }
      }

    case "stopUnifiedRecording":
      Task.detached { [weak self] in
        guard let self = self,
              let service = self.unifiedRecordingService else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        do {
          let recordingResult = try await service.stopRecording()
          self.logger.info("[UnifiedRecording] Completed: \(recordingResult.transcriptions.count) transcriptions, \(recordingResult.speakerSegments.count) speaker segments")
          DispatchQueue.main.async { result(recordingResult.toDictionary()) }
        } catch {
          self.logger.error("[UnifiedRecording] Failed to stop: \(error.localizedDescription)")
          DispatchQueue.main.async { result(nil) }
        }
      }

    // MARK: - Listening (Recording + Window 통합)

    case "startListening":
      Task.detached { [weak self] in
        guard let self else {
          DispatchQueue.main.async { result(false) }
          return
        }

        let args = call.arguments as? [String: Any]
        let enableASR = args?["enableASR"] as? Bool ?? true
        let enableDiarization = args?["enableDiarization"] as? Bool ?? true
        let asrEngine = args?["asrEngine"] as? String ?? "fluid"
        let sessionId = args?["sessionId"] as? String
        let shouldScreenshotCapture = args?["shouldScreenshotCapture"] as? Bool ?? false

        // 1. 모델 사전 로드 (필요 시)
        if enableASR {
          if asrEngine == "whisper" {
            if self.whisperService == nil || !(self.whisperService?.isInitialized ?? false) {
              self.whisperService = WhisperASRService(
                modelName: "ggml-large-v3-turbo-q5_0.bin",
                useGPU: true, language: "auto"
              )
              do {
                try await self.whisperService?.initialize()
              } catch {
                self.logger.error("[Listening] Whisper ASR init failed: \(error.localizedDescription)")
                FlutterBridge.shared.invokeError(code: .asrInitFailed, message: error.localizedDescription)
                self.whisperService = nil
              }
            }
          } else {
            if self.fluidService == nil || !(self.fluidService?.isInitialized ?? false) {
              self.fluidService = FluidASRService(version: .english)
              do {
                try await self.fluidService?.initialize()
              } catch {
                self.logger.error("[Listening] Fluid ASR init failed: \(error.localizedDescription)")
                FlutterBridge.shared.invokeError(code: .asrInitFailed, message: error.localizedDescription)
                self.fluidService = nil
              }
            }
          }
        }

        if enableDiarization {
          if self.diarizerService == nil || !(self.diarizerService?.isInitialized ?? false) {
            self.diarizerService = FluidDiarizerService()
            do {
              try await self.diarizerService?.initialize()
            } catch {
              self.logger.error("[Listening] Diarizer init failed: \(error.localizedDescription)")
              FlutterBridge.shared.invokeError(code: .diarizerInitFailed, message: error.localizedDescription)
              self.diarizerService = nil
            }
          }
        }

        // 2. Coordinator에 서비스 참조 전달 + 녹음 시작
        if #available(macOS 14.0, *) {
          let coordinator = ListeningCoordinator.shared
          coordinator.asrService = asrEngine == "whisper"
            ? self.whisperService : self.fluidService
          coordinator.diarizerService = self.diarizerService

          let config = UnifiedRecordingServiceV2.Config(
            enableASR: enableASR,
            enableDiarization: enableDiarization,
            enableSystemAudio: true,
            asrEngine: asrEngine,
            sessionId: sessionId
          )
          coordinator.startRecording(config: config)
        }

        // 3. 윈도우 표시 (main thread)
        await MainActor.run {
          let windowConfig = WindowConfiguration(
            identifier: "listening",
            size: CGSize(width: 270, height: 320),
            position: .screen(.bottomRight, offset: CGPoint(x: -20, y: 20)),
            style: .floatingPanel
          )
          WindowManager.shared.showWindow(configuration: windowConfig) {
            ListeningView(shouldScreenshotCapture: shouldScreenshotCapture)
          }
        }

        self.logger.info("[Listening] startListening 완료")
        DispatchQueue.main.async { result(true) }
      }

    case "stopListening":
      Task.detached {
        var recordingResult: UnifiedRecordingResult?
        if #available(macOS 14.0, *) {
          recordingResult = await ListeningCoordinator.shared.stopRecording()
        }

        await MainActor.run {
          WindowManager.shared.closeWindow(identifier: "listening")
        }

        FlutterBridge.shared.invokeListeningEnded(reason: "confirmed")

        if let recordingResult {
          DispatchQueue.main.async { result(recordingResult.toDictionary()) }
        } else {
          DispatchQueue.main.async { result(nil) }
        }
      }

    case "cancelListening":
      Task.detached {
        if #available(macOS 14.0, *) {
          await ListeningCoordinator.shared.cancelRecording()
        }

        await MainActor.run {
          WindowManager.shared.closeWindow(identifier: "listening")
        }

        FlutterBridge.shared.invokeListeningEnded(reason: "cancelled")

        DispatchQueue.main.async { result(nil) }
      }

    // MARK: - Listening Window

    case "showListeningWindow":
      Task { @MainActor in
        let config = WindowConfiguration(
          identifier: "listening",
          size: CGSize(width: 270, height: 320),
          position: .screen(.bottomRight, offset: CGPoint(x: -20, y: 20)),
          style: .floatingPanel
        )
        // ViewModel은 View 내부 @StateObject가 소유 — 윈도우 닫힘 시 자동 해제
        WindowManager.shared.showWindow(configuration: config) {
          ListeningView()
        }
        self.logger.info("[Window] showListeningWindow")
        result(true)
      }

    case "closeListeningWindow":
      Task { @MainActor in
        WindowManager.shared.closeWindow(identifier: "listening")
        self.logger.info("[Window] closeListeningWindow")
        result(nil)
      }

    // MARK: - Window Management

    case "showWindow":
      Task { @MainActor in
        let args = call.arguments as? [String: Any]
        let identifier = args?["identifier"] as? String ?? "default"
        let width = args?["width"] as? Double ?? 240
        let height = args?["height"] as? Double ?? 140
        let positionType = args?["position"] as? String ?? "screenCenter"

        // Parse position
        let position: WindowPosition
        switch positionType {
        case "screenCenter":
          position = .screenCenter
        case "bottomLeft":
          position = .screen(.bottomLeft, offset: CGPoint(x: 20, y: 20))
        case "bottomRight":
          position = .screen(.bottomRight, offset: CGPoint(x: -20, y: 20))
        case "topRight":
          position = .screen(.topRight, offset: CGPoint(x: -20, y: -20))
        case "flutterWindow":
          let anchor = args?["anchor"] as? String ?? "rightCenter"
          let offsetX = args?["offsetX"] as? Double ?? 15
          let offsetY = args?["offsetY"] as? Double ?? 0
          let flutterAnchor: FlutterWindowAnchor = {
            switch anchor {
            case "topLeft": return .topLeft
            case "topRight": return .topRight
            case "bottomLeft": return .bottomLeft
            case "bottomRight": return .bottomRight
            case "leftCenter": return .leftCenter
            case "rightCenter": return .rightCenter
            default: return .rightCenter
            }
          }()
          position = .flutterWindow(flutterAnchor, offset: CGPoint(x: offsetX, y: offsetY))
        default:
          position = .screenCenter
        }

        let config = WindowConfiguration(
          identifier: identifier,
          size: CGSize(width: width, height: height),
          position: position,
          style: .floatingPanel
        )

        WindowManager.shared.showWindow(configuration: config) {
          TestWindowView(identifier: identifier)
        }

        self.logger.info("[Window] showWindow: \(identifier)")
        result(true)
      }

    case "closeWindow":
      Task { @MainActor in
        let args = call.arguments as? [String: Any]
        let identifier = args?["identifier"] as? String ?? "default"

        WindowManager.shared.closeWindow(identifier: identifier)

        self.logger.info("[Window] closeWindow: \(identifier)")
        result(nil)
      }

    case "isWindowVisible":
      let args = call.arguments as? [String: Any]
      let identifier = args?["identifier"] as? String ?? "default"
      let isVisible = WindowManager.shared.isWindowVisible(identifier: identifier)
      result(isVisible)

    case "updateWindowPosition":
      Task { @MainActor in
        let args = call.arguments as? [String: Any]
        let identifier = args?["identifier"] as? String ?? "default"
        let positionType = args?["position"] as? String ?? "screenCenter"

        let position: WindowPosition
        switch positionType {
        case "screenCenter":
          position = .screenCenter
        case "bottomLeft":
          position = .screen(.bottomLeft, offset: CGPoint(x: 20, y: 20))
        case "bottomRight":
          position = .screen(.bottomRight, offset: CGPoint(x: -20, y: 20))
        default:
          position = .screenCenter
        }

        WindowManager.shared.updatePosition(identifier: identifier, position: position)
        result(nil)
      }

    case "getActiveWindows":
      let windows = WindowManager.shared.activeWindowIdentifiers
      result(windows)

    case "enumerateWindows":
      Task {
        let screenshotService = ScreenshotCaptureService()
        let targets = await screenshotService.buildCaptureTargets()

        var windows: [[String: Any]] = []
        var displays: [[String: Any]] = []

        for target in targets {
          switch target {
          case .window:
            windows.append(target.asDictionary())
          case .display:
            displays.append(target.asDictionary())
          case .autoCapture, .noCapture:
            break
          }
        }

        let response: [String: Any] = [
          "windows": windows,
          "displays": displays
        ]

        DispatchQueue.main.async {
          result(response)
        }
      }

    case "updateCaptureTarget":
      guard let args = call.arguments as? [String: Any],
            let targetConfig = args["targetConfig"] as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing targetConfig", details: nil))
        return
      }
      Task {
        guard let type = targetConfig["type"] as? String else {
          DispatchQueue.main.async {
            result(FlutterError(code: "INVALID_TYPE", message: "Missing 'type' in targetConfig", details: nil))
          }
          return
        }

        guard let viewModel = await WindowManager.shared.listeningViewModel else {
          DispatchQueue.main.async {
            result(FlutterError(code: "NO_VIEW_MODEL", message: "ListeningViewModel not available", details: nil))
          }
          return
        }

        let windowID = targetConfig["windowID"] as? Int
        let windowTitle = targetConfig["windowTitle"] as? String
        let displayID = targetConfig["displayID"] as? Int
        let displayName = targetConfig["displayName"] as? String

        guard let foundTarget = await viewModel.updateCaptureTarget(
          type: type,
          windowID: windowID,
          windowTitle: windowTitle,
          displayID: displayID,
          displayName: displayName
        ) else {
          DispatchQueue.main.async {
            result(FlutterError(code: "TARGET_NOT_FOUND", message: "Target not found for type '\(type)'", details: nil))
          }
          return
        }

        self.logger.info("Capture target updated to: \(foundTarget.name)")
        DispatchQueue.main.async {
          result(foundTarget.asDictionary())
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Private Helpers

  /// Unload all ML models (ASR, VAD, Diarizer) to free memory
  private func unloadModels() {
    whisperService?.cleanup()
    whisperService = nil

    fluidService?.cleanup()
    fluidService = nil

    diarizerService?.cleanup()
    diarizerService = nil

    micVADService = nil

    logger.info("[Plugin] All ML models unloaded")
  }

  /// WAV 파일에서 특정 시간 범위의 샘플 추출
  private func extractSamples(from url: URL, startTime: Double, endTime: Double) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let sampleRate = file.processingFormat.sampleRate  // 16000

    let startFrame = AVAudioFramePosition(startTime * sampleRate)
    let frameCount = AVAudioFrameCount((endTime - startTime) * sampleRate)

    // 범위 검증
    guard startFrame >= 0, frameCount > 0 else {
      throw AudioServiceError.invalidBuffer
    }

    file.framePosition = startFrame

    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: file.processingFormat,
      frameCapacity: frameCount
    ) else {
      throw AudioServiceError.bufferCreationFailed
    }

    try file.read(into: buffer, frameCount: frameCount)

    guard let floatData = buffer.floatChannelData?[0] else {
      throw AudioServiceError.invalidBuffer
    }

    return Array(UnsafeBufferPointer(start: floatData, count: Int(buffer.frameLength)))
  }
}
