import AVFAudio
import OSLog
import whisper

// MARK: - WhisperASRService

/// Whisper.cpp 기반 ASR 서비스
///
/// OpenAI Whisper 모델을 whisper.cpp C 라이브러리를 통해 사용합니다.
/// Metal GPU 가속을 지원합니다.
///
/// ## 추상화 개념 (FluidASRService와 동일)
/// 1. **모델 로드**: whisper_init_from_file_with_params()
/// 2. **오디오 피드**: 16kHz mono Float32 샘플
/// 3. **전사 결과**: whisper_full() → segments → TranscriptionSegment
///
/// ## 지원 모델
/// - GGML 포맷 모델 파일 (예: ggml-large-v3-turbo-q5_0.bin)
/// - Metal GPU 가속 지원
///
/// ## 사용 예시
/// ```swift
/// let service = WhisperASRService(modelPath: "/path/to/ggml-model.bin")
/// try await service.initialize()
/// let result = try await service.processSegment(samples: audioSamples, startTime: 0, endTime: 5)
/// print(result.text)
/// ```
final class WhisperASRService: ASRServiceProtocol {

    // MARK: - Types

    /// Whisper 전사 결과 세그먼트 (내부용)
    struct WhisperSegment {
        let text: String
        let startTime: Double
        let endTime: Double
    }

    /// 토큰 타이밍 정보 (상세 분석용)
    struct WhisperToken {
        let text: String
        let startTime: Double
        let endTime: Double
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "shadow_listening", category: "WhisperASR")

    /// 모델 파일 경로
    private let modelPath: String

    /// whisper_context 포인터
    private var context: OpaquePointer?

    /// whisper_state 포인터 (스트리밍용)
    private var state: OpaquePointer?

    /// Metal GPU 사용 여부
    private let useGPU: Bool

    /// 언어 설정 ("auto", "en", "ko" 등)
    private let language: String

    /// 초기화 완료 여부
    private(set) var isInitialized: Bool = false

    /// 누적된 전사 결과
    private var transcriptionSegments: [TranscriptionSegment] = []

    /// 샘플레이트 (Whisper는 16kHz 사용)
    private let sampleRate: Double = 16000

    /// 최소 처리 오디오 길이 (초)
    private let minAudioDuration: Double = 0.5

    // MARK: - Initialization

    /// WhisperASRService 초기화
    /// - Parameters:
    ///   - modelPath: GGML 모델 파일 경로
    ///   - useGPU: Metal GPU 가속 사용 여부 (기본값: true)
    ///   - language: 언어 코드 ("auto", "en", "ko" 등, 기본값: "auto")
    init(modelPath: String, useGPU: Bool = true, language: String = "auto") {
        self.modelPath = modelPath
        self.useGPU = useGPU
        self.language = language
        logger.info("WhisperASRService created (GPU: \(useGPU), lang: \(language))")
    }

    /// 기본 모델 경로로 초기화 (shared 디렉토리)
    /// - Parameters:
    ///   - modelName: 모델 파일명 (예: "ggml-large-v3-turbo-q5_0.bin")
    ///   - useGPU: Metal GPU 가속 사용 여부
    ///   - language: 언어 코드
    convenience init(modelName: String, useGPU: Bool = true, language: String = "auto") {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let modelPath = appSupport
            .appendingPathComponent("com.taperlabs.shadow")
            .appendingPathComponent("shared")
            .appendingPathComponent(modelName)
            .path

        self.init(modelPath: modelPath, useGPU: useGPU, language: language)
    }

    deinit {
        cleanup()
    }

    // MARK: - ASRServiceProtocol Implementation

    /// 모델 로드 및 초기화
    ///
    /// whisper_init_from_file_with_params()를 호출하여 컨텍스트를 생성합니다.
    /// Metal GPU 가속이 활성화됩니다.
    func initialize() async throws {
        guard !isInitialized else {
            logger.info("WhisperASRService already initialized")
            return
        }

        logger.info("Initializing WhisperASRService...")
        logger.info("Model path: \(self.modelPath)")

        // 모델 파일 존재 확인
        guard FileManager.default.fileExists(atPath: modelPath) else {
            logger.error("Whisper model not found at: \(self.modelPath)")
            throw ASRServiceError.modelNotFound(path: modelPath)
        }

        // 컨텍스트 파라미터 설정
        var cparams = whisper_context_default_params()
        cparams.use_gpu = useGPU
        cparams.gpu_device = 0  // 기본 GPU

        // 모델 로드
        let ctx = modelPath.withCString { cPath in
            return whisper_init_from_file_with_params(cPath, cparams)
        }

        guard let ctx = ctx else {
            logger.error("Failed to initialize Whisper context")
            throw ASRServiceError.modelLoadFailed(
                NSError(domain: "WhisperASR", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to initialize Whisper context from: \(modelPath)"
                ])
            )
        }

        self.context = ctx
        isInitialized = true
        logger.info("WhisperASRService ready (GPU: \(self.useGPU))")
    }

    /// 오디오 샘플 배열로 전사
    ///
    /// whisper_full()을 호출하여 전체 오디오를 전사합니다.
    ///
    /// - Parameters:
    ///   - samples: 16kHz mono Float32 오디오 샘플
    ///   - startTime: 세그먼트 시작 시간 (녹음 기준, 초)
    ///   - endTime: 세그먼트 종료 시간 (녹음 기준, 초)
    /// - Returns: 전사 결과
    func processSegment(
        samples: [Float],
        startTime: Double,
        endTime: Double
    ) async throws -> TranscriptionSegment {
        guard isInitialized, let context = context else {
            throw ASRServiceError.notInitialized
        }

        let duration = endTime - startTime

        // 최소 길이 체크
        guard duration >= minAudioDuration else {
            logger.debug("Segment too short (\(String(format: "%.2f", duration))s), returning empty")
            return TranscriptionSegment(
                text: "",
                startTime: startTime,
                endTime: endTime,
                confidence: 0,
                isFinal: true
            )
        }

        logger.info("[Whisper] Transcribing: \(String(format: "%.2f", startTime))s - \(String(format: "%.2f", endTime))s (\(samples.count) samples)")

        // 전사 파라미터 설정
        var wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

        // Whisper 세그먼트 결과를 저장할 배열
        var whisperSegments: [WhisperSegment] = []
        var processingError: Error?

        // 언어 설정: 항상 withCString으로 전달 ("auto" 문자열 포함)
        language.withCString { lang in
            wparams.language = lang
            wparams.detect_language = (language == "")
            wparams.print_progress = false
            wparams.print_realtime = false
            wparams.translate = false
            wparams.token_timestamps = true
            wparams.no_timestamps = false
//            wparams.split_on_word = true
//            wparams.max_tokens = 1

            // 전사 실행
            let result = whisper_full(context, wparams, samples, Int32(samples.count))

            if result != 0 {
                logger.error("[Whisper] whisper_full failed with code: \(result)")
                processingError = ASRServiceError.processingFailed(
                    NSError(domain: "WhisperASR", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Whisper transcription failed with code: \(result)"
                    ])
                )
                return
            }

            // 결과 세그먼트 추출 (Whisper 타임스탬프를 절대 시간으로 변환)
            let nSegments = whisper_full_n_segments(context)
            logger.info("[Whisper] nSegments: \(nSegments)")

            for i in 0..<nSegments {
                if let cString = whisper_full_get_segment_text(context, Int32(i)) {
                    let rawText = String(cString: cString)
                    let segmentText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                    logger.info("[Whisper] Segment \(i) raw: '\(rawText)' → trimmed: '\(segmentText)'")

                    // Whisper 상대 타임스탬프 (10ms 단위)
                    let t0 = whisper_full_get_segment_t0(context, Int32(i))
                    let t1 = whisper_full_get_segment_t1(context, Int32(i))

                    // 원본 값 디버그 로그
                    logger.info("[Whisper] Raw timestamp: t0=\(t0), t1=\(t1) (startTime=\(String(format: "%.2f", startTime)))")

                    // 절대 시간으로 변환 (startTime + Whisper 상대 시간)
                    let absoluteStart = startTime + (Double(t0) * 0.01)
                    let absoluteEnd = startTime + (Double(t1) * 0.01)

                    logger.info("[Whisper] Segment \(i): \(String(format: "%.2f", absoluteStart))s - \(String(format: "%.2f", absoluteEnd))s: \(segmentText)")

                    if !segmentText.isEmpty {
                        whisperSegments.append(WhisperSegment(
                            text: segmentText,
                            startTime: absoluteStart,
                            endTime: absoluteEnd
                        ))
                    }
                }
            }
        }

        // 에러 체크
        if let error = processingError {
            throw error
        }

        // Whisper 세그먼트를 TranscriptionSegment로 변환하여 저장
        for whisperSeg in whisperSegments {
            let segment = TranscriptionSegment(
                text: whisperSeg.text,
                startTime: whisperSeg.startTime,
                endTime: whisperSeg.endTime,
                confidence: 1.0,  // Whisper doesn't provide confidence scores
                isFinal: true
            )
            transcriptionSegments.append(segment)
        }

        // 반환용 세그먼트 생성 (전체 텍스트 합침, 정확한 시작/종료 시간 사용)
        let fullText = whisperSegments.map { $0.text }.joined(separator: " ")
        let segmentStartTime = whisperSegments.first?.startTime ?? startTime
        let segmentEndTime = whisperSegments.last?.endTime ?? endTime

        let segment = TranscriptionSegment(
            text: fullText,
            startTime: segmentStartTime,
            endTime: segmentEndTime,
            confidence: 1.0,
            isFinal: true
        )

        logger.info("[Whisper] Result: '\(segment.text)' (\(String(format: "%.2f", segmentStartTime))s - \(String(format: "%.2f", segmentEndTime))s)")

        return segment
    }

    /// State 기반 전사 (스트리밍 컨텍스트 유지)
    ///
    /// whisper_full_with_state()를 사용하여 상태를 유지하며 전사합니다.
    /// 연속적인 오디오 스트림 처리에 유용합니다.
    func processSegmentWithState(
        samples: [Float],
        startTime: Double,
        endTime: Double,
        logTokens: Bool = false
    ) async throws -> TranscriptionSegment {
        guard isInitialized, let context = context else {
            throw ASRServiceError.notInitialized
        }

        // State 초기화 (없으면 생성)
        if state == nil {
            state = whisper_init_state(context)
            if state == nil {
                logger.error("[Whisper] Failed to initialize state")
                throw ASRServiceError.processingFailed(
                    NSError(domain: "WhisperASR", code: -3, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to initialize Whisper state"
                    ])
                )
            }
        }

        guard let state = state else {
            throw ASRServiceError.notInitialized
        }

        let duration = endTime - startTime

        guard duration >= minAudioDuration else {
            return TranscriptionSegment(
                text: "",
                startTime: startTime,
                endTime: endTime,
                confidence: 0,
                isFinal: true
            )
        }

        logger.info("[Whisper] Transcribing with state: \(String(format: "%.2f", startTime))s - \(String(format: "%.2f", endTime))s")

        var wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

        // Whisper 세그먼트 결과를 저장할 배열
        var whisperSegments: [WhisperSegment] = []
        var processingError: Error?

        // 언어 설정: 항상 withCString으로 전달 ("auto" 문자열 포함)
        language.withCString { lang in
            wparams.language = lang
            wparams.detect_language = (language == "")
            wparams.print_progress = false
            wparams.print_realtime = false
            wparams.translate = false
            wparams.token_timestamps = true
            wparams.no_timestamps = false
//            wparams.split_on_word = true
//            wparams.max_tokens = 1

            let result = whisper_full_with_state(context, state, wparams, samples, Int32(samples.count))

            if result != 0 {
                logger.error("[Whisper] whisper_full_with_state failed")
                processingError = ASRServiceError.processingFailed(
                    NSError(domain: "WhisperASR", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Whisper transcription failed"
                    ])
                )
                return
            }

            // 결과 세그먼트 추출 (Whisper 타임스탬프를 절대 시간으로 변환)
            let nSegments = whisper_full_n_segments_from_state(state)
            logger.info("[Whisper] nSegments: \(nSegments)")

            for i in 0..<nSegments {
                if let cString = whisper_full_get_segment_text_from_state(state, Int32(i)) {
                    let rawText = String(cString: cString)
                    let segmentText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                    logger.info("[Whisper] Segment \(i) raw: '\(rawText)' → trimmed: '\(segmentText)'")

                    // Whisper 상대 타임스탬프 (10ms 단위)
                    let t0 = whisper_full_get_segment_t0_from_state(state, Int32(i))
                    let t1 = whisper_full_get_segment_t1_from_state(state, Int32(i))

                    // 원본 값 디버그 로그
                    logger.info("[Whisper] Raw timestamp: t0=\(t0), t1=\(t1) (startTime=\(String(format: "%.2f", startTime)))")

                    // 절대 시간으로 변환 (startTime + Whisper 상대 시간)
                    let absoluteStart = startTime + (Double(t0) * 0.01)
                    let absoluteEnd = startTime + (Double(t1) * 0.01)

                    logger.info("[Whisper] Segment \(i): \(String(format: "%.2f", absoluteStart))s - \(String(format: "%.2f", absoluteEnd))s: \(segmentText)")

                    if !segmentText.isEmpty {
                        whisperSegments.append(WhisperSegment(
                            text: segmentText,
                            startTime: absoluteStart,
                            endTime: absoluteEnd
                        ))
                    }
                }
            }
        }

        // 에러 체크
        if let error = processingError {
            throw error
        }

        // Whisper 세그먼트를 TranscriptionSegment로 변환하여 저장
        for whisperSeg in whisperSegments {
            let segment = TranscriptionSegment(
                text: whisperSeg.text,
                startTime: whisperSeg.startTime,
                endTime: whisperSeg.endTime,
                confidence: 1.0,
                isFinal: true
            )
            transcriptionSegments.append(segment)
        }

        // 반환용 세그먼트 생성 (전체 텍스트 합침, 정확한 시작/종료 시간 사용)
        let fullText = whisperSegments.map { $0.text }.joined(separator: " ")
        let segmentStartTime = whisperSegments.first?.startTime ?? startTime
        let segmentEndTime = whisperSegments.last?.endTime ?? endTime

        let segment = TranscriptionSegment(
            text: fullText,
            startTime: segmentStartTime,
            endTime: segmentEndTime,
            confidence: 1.0,
            isFinal: true
        )

        return segment
    }

    func reset() async {
        transcriptionSegments.removeAll()
        resetStreamingState()
        logger.info("[Whisper] Service reset")
    }

    func finalize() async throws -> [TranscriptionSegment] {
        logger.info("[Whisper] Finalized with \(self.transcriptionSegments.count) segments")
        return transcriptionSegments
    }

    func getTranscriptions() -> [TranscriptionSegment] {
        return transcriptionSegments
    }

    // MARK: - State Management

    /// 스트리밍 상태 리셋
    func resetStreamingState() {
        if let state = state {
            whisper_free_state(state)
            self.state = nil
            logger.info("[Whisper] State reset")
        }
    }

    // MARK: - Resource Management

    /// 리소스 정리
    func cleanup() {
        if let state = state {
            whisper_free_state(state)
            self.state = nil
        }
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
        isInitialized = false
        transcriptionSegments.removeAll()
        logger.info("[Whisper] Resources cleaned up")
    }

    // MARK: - Static Helpers

    /// 기본 모델 경로 반환 (shared 디렉토리)
    static func defaultModelPath(modelName: String) -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return appSupport
            .appendingPathComponent("com.taperlabs.shadow")
            .appendingPathComponent("shared")
            .appendingPathComponent(modelName)
            .path
    }

    /// 모델 파일 존재 여부 확인
    static func modelExists(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    /// shared 디렉토리 내 모델 파일 존재 여부 확인
    static func modelExists(modelName: String) -> Bool {
        return modelExists(at: defaultModelPath(modelName: modelName))
    }
}
