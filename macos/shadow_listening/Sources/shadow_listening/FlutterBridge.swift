import FlutterMacOS
import OSLog

/// FlutterBridge Singleton
///
/// Swift -> Flutter 방향의 MethodChannel 호출을 담당합니다.
/// 5초 청크 단위로 처리된 결과(MicVAD, Transcription, Diarization)를 Flutter로 전달합니다.
///
/// ## Thread Safety
/// 모든 `invoke*` 메서드는 자동으로 main thread로 dispatch됩니다.
/// 백그라운드 스레드(오디오 처리 등)에서 호출해도 안전합니다.
///
/// ## Usage
/// ```swift
/// // Plugin 등록 시 채널 설정
/// FlutterBridge.shared.setChannel(channel)
///
/// // 청크 처리 결과 통합 전송
/// FlutterBridge.shared.invokeOnChunkProcessed(
///     chunkIndex: 0,
///     startTime: 0.0,
///     endTime: 5.0,
///     micVADSegment: (startTime: 0.5, endTime: 2.3),
///     transcription: (text: "Hello", startTime: 0.0, endTime: 5.0, confidence: 0.95),
///     diarizations: [(speakerId: "Speaker_0", startTime: 0.0, endTime: 2.5, confidence: 0.9)]
/// )
/// ```
final class FlutterBridge {

    // MARK: - Singleton

    static let shared = FlutterBridge()

    private init() {
        logger.info("FlutterBridge initialized")
    }

    // MARK: - Properties

    /// Strong reference - channel lives for app lifetime, no retain cycle risk
    private var channel: FlutterMethodChannel?

    private let logger = Logger(subsystem: "shadow_listening", category: "FlutterBridge")

    /// Check if bridge is ready to send events
    var isReady: Bool {
        return channel != nil
    }

    // MARK: - Setup

    /// Set the method channel reference
    /// Call this in ShadowListeningPlugin.register()
    func setChannel(_ channel: FlutterMethodChannel) {
        self.channel = channel
        logger.info("FlutterBridge channel set")
    }

    /// Clear the channel reference
    /// Call this when plugin is detached
    func clearChannel() {
        self.channel = nil
        logger.info("FlutterBridge channel cleared")
    }

    // MARK: - Chunk Result Data Types

    /// MicVAD 세그먼트 (내가 말한 구간)
    struct MicVADSegmentData {
        let startTime: Double
        let endTime: Double

        func toDictionary() -> [String: Any] {
            return [
                "startTime": startTime,
                "endTime": endTime
            ]
        }
    }

    /// ASR 전사 결과
    struct TranscriptionData {
        let text: String
        let startTime: Double
        let endTime: Double
        let confidence: Float

        func toDictionary() -> [String: Any] {
            return [
                "text": text,
                "startTime": startTime,
                "endTime": endTime,
                "confidence": confidence
            ]
        }
    }

    /// 화자 분리 세그먼트
    struct DiarizationData {
        let speakerId: String
        let startTime: Double
        let endTime: Double
        let confidence: Float

        func toDictionary() -> [String: Any] {
            return [
                "speakerId": speakerId,
                "startTime": startTime,
                "endTime": endTime,
                "confidence": confidence
            ]
        }
    }

    // MARK: - Event Methods

    /// Send chunk processing result to Flutter
    ///
    /// 5초 청크 처리 완료 시 MicVAD, Transcription, Diarization 결과를 통합하여 전송합니다.
    ///
    /// - Parameters:
    ///   - chunkIndex: 청크 인덱스 (0부터 시작)
    ///   - startTime: 청크 시작 시간 (초)
    ///   - endTime: 청크 종료 시간 (초)
    ///   - micVADSegments: 내가 말한 구간들 (없으면 빈 배열)
    ///   - transcription: ASR 전사 결과 (없으면 nil)
    ///   - diarizations: 화자 분리 세그먼트들 (없으면 빈 배열)
    func invokeOnChunkProcessed(
        chunkIndex: Int,
        startTime: Double,
        endTime: Double,
        micVADSegments: [MicVADSegmentData],
        transcription: TranscriptionData?,
        diarizations: [DiarizationData],
        isFinalChunk: Bool = false,
        sessionId: String? = nil
    ) {
        var arguments: [String: Any] = [
            "chunkIndex": chunkIndex,
            "startTime": startTime,
            "endTime": endTime,
            "micVADSegments": micVADSegments.map { $0.toDictionary() },
            "diarizations": diarizations.map { $0.toDictionary() },
            "isFinalChunk": isFinalChunk
        ]

        if let sessionId = sessionId {
            arguments["sessionId"] = sessionId
        }

        if let transcription = transcription {
            arguments["transcription"] = transcription.toDictionary()
        }

        invokeMethod("onChunkProcessed", arguments: arguments)

        logger.info("[FlutterBridge] onChunkProcessed: chunk#\(chunkIndex) (\(String(format: "%.1f", startTime))s-\(String(format: "%.1f", endTime))s) - MicVAD:\(micVADSegments.count), Trans:\(transcription != nil ? 1 : 0), Diar:\(diarizations.count), final:\(isFinalChunk)")
    }

    // MARK: - Window Events

    /// Send window event to Flutter
    ///
    /// WindowManager에서 윈도우 상태 변경 시 Flutter로 이벤트를 전송합니다.
    ///
    /// - Parameter event: 윈도우 이벤트 dictionary (event, windowId, 추가 데이터)
    func invokeWindowEvent(_ event: [String: Any]) {
        invokeMethod("onWindowEvent", arguments: event)

        let eventType = event["event"] as? String ?? "unknown"
        let windowId = event["windowId"] as? String ?? "unknown"
        logger.info("[FlutterBridge] onWindowEvent: \(eventType) for window '\(windowId)'")
    }

    // MARK: - Listening Events

    /// 리스닝 종료 이유를 Flutter로 전송
    ///
    /// - Parameter reason: 종료 이유 ("cancelled" 또는 "confirmed")
    func invokeListeningEnded(reason: String) {
        let arguments: [String: Any] = [
            "reason": reason,
            "windowId": "listening"
        ]
        invokeMethod("onListeningEnded", arguments: arguments)
        logger.info("[FlutterBridge] onListeningEnded: \(reason)")
    }

    /// 대면 미팅 토글 변경을 Flutter로 전송
    func invokeInPersonMeetingChanged(isInPersonMeeting: Bool) {
        let arguments: [String: Any] = ["isInPersonMeeting": isInPersonMeeting]
        invokeMethod("onInPersonMeetingChanged", arguments: arguments)
        logger.info("[FlutterBridge] onInPersonMeetingChanged: \(isInPersonMeeting)")
    }

    // MARK: - Error Events

    /// Send error event to Flutter during listening session
    func invokeError(code: ListeningErrorCode, message: String) {
        let arguments: [String: Any] = [
            "code": code.rawValue,
            "message": message,
        ]
        invokeMethod("onError", arguments: arguments)
        logger.error("[FlutterBridge] onError: \(code.rawValue) - \(message)")
    }

    // MARK: - Capture Target Events

    /// 캡처 타겟 선택을 Flutter로 전송
    func invokeCaptureTargetSelected(_ data: [String: Any]) {
        invokeMethod("onCaptureTargetSelected", arguments: data)
        let name = data["name"] as? String ?? "unknown"
        logger.info("[FlutterBridge] onCaptureTargetSelected: \(name)")
    }

    // MARK: - Private Helpers

    /// Thread-safe method invocation
    /// Dispatches to main thread if not already on it
    private func invokeMethod(_ method: String, arguments: Any?) {
        guard let channel = channel else {
            logger.warning("[FlutterBridge] Channel not set, dropping \(method)")
            return
        }

        logger.info("[FlutterBridge] invokeMethod: \(method) (isMainThread: \(Thread.isMainThread))")

        // Flutter method channel calls must be on main thread
        if Thread.isMainThread {
            channel.invokeMethod(method, arguments: arguments)
            logger.info("[FlutterBridge] invoked \(method) on main thread")
        } else {
            DispatchQueue.main.async { [weak channel, weak self] in
                channel?.invokeMethod(method, arguments: arguments)
                self?.logger.info("[FlutterBridge] invoked \(method) via dispatch to main")
            }
        }
    }
}
