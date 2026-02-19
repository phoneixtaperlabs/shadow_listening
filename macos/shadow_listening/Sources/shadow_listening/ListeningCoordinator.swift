import Foundation
import OSLog

/// 리스닝 녹음 상태
enum ListeningRecordingState: Equatable {
    case idle
    case preparing        // 모델 로딩 + 서비스 초기화
    case recording        // 녹음 활성
    case stopping         // 녹음 중지 중 (결과 처리)
    case error(String)    // 에러
}

/// 리스닝 세션 녹음 라이프사이클 코디네이터
///
/// Plugin이 소유하는 서비스들과 ViewModel 간의 통신 브릿지.
/// 녹음 서비스(UnifiedRecordingServiceV2)를 off-main-thread로 관리하고,
/// 상태 변경을 @Published로 발행하여 ViewModel이 관찰.
///
/// ## 소유 구조
/// ```
/// ShadowListeningPlugin (앱 수명)
///   ├── strong → fluidService, diarizerService (ML 모델)
///   └── 접근 → ListeningCoordinator.shared
///
/// ListeningCoordinator.shared (singleton)
///   ├── weak → asrService (Plugin 소유)
///   ├── weak → diarizerService (Plugin 소유)
///   └── strong → recordingService (세션별 생성, cleanup 시 nil)
///
/// ListeningView → @StateObject ListeningViewModel
///   └── 읽기 → ListeningCoordinator.shared (Combine 구독)
/// ```
@available(macOS 14.0, *)
final class ListeningCoordinator: ObservableObject {

    static let shared = ListeningCoordinator()

    // MARK: - Published State

    @MainActor @Published private(set) var recordingState: ListeningRecordingState = .idle
    @MainActor @Published private(set) var currentRMS: Float = 0

    // MARK: - Services (Plugin이 주입 — weak 참조)

    weak var asrService: (any ASRServiceProtocol)?
    weak var diarizerService: FluidDiarizerService?

    // MARK: - Private

    private var recordingService: UnifiedRecordingServiceV2?
    private let logger = Logger(subsystem: "shadow_listening", category: "ListeningCoordinator")

    private init() {}

    // MARK: - Recording Lifecycle

    /// 녹음 시작 — Plugin이 호출 (off-main-thread에서 실행)
    func startRecording(config: UnifiedRecordingServiceV2.Config) {
        Task.detached { [weak self] in
            guard let self else { return }
            await MainActor.run { self.recordingState = .preparing }

            do {
                let service = UnifiedRecordingServiceV2()
                self.recordingService = service

                // RMS 콜백 설정 → @Published로 발행
                service.onRMSUpdate = { [weak self] rms in
                    Task { @MainActor [weak self] in
                        self?.currentRMS = rms
                    }
                }

                _ = try await service.startRecording(
                    config: config,
                    asrService: self.asrService,
                    diarizerService: self.diarizerService
                )

                await MainActor.run { self.recordingState = .recording }
                self.logger.info("[Coordinator] 녹음 시작됨")
            } catch {
                
                self.logger.error("[Coordinator] 녹음 시작 실패: \(error.localizedDescription)")
                FlutterBridge.shared.invokeError(code: .recordingStartFailed, message: error.localizedDescription)
                await MainActor.run { self.recordingState = .error(error.localizedDescription) }
            }
        }
    }

    /// 녹음 중지 (확인) — 결과 반환
    func stopRecording() async -> UnifiedRecordingResult? {
        guard let service = recordingService else { return nil }

        let currentState = await MainActor.run { recordingState }
        guard currentState != .stopping else {
            logger.info("[Coordinator] stopRecording ignored — already stopping")
            return nil
        }

        await MainActor.run { recordingState = .stopping }

        do {
            let result = try await service.stopRecording()
            await MainActor.run { recordingState = .idle }
            cleanup()
            logger.info("[Coordinator] 녹음 중지 완료")
            return result
        } catch {
            logger.error("[Coordinator] 녹음 중지 실패: \(error.localizedDescription)")
            FlutterBridge.shared.invokeError(code: .recordingStopFailed, message: error.localizedDescription)
            await MainActor.run { recordingState = .idle }
            cleanup()
            return nil
        }
    }

    /// 녹음 취소 — 결과 폐기
    func cancelRecording() async {
        guard recordingService != nil else {
            logger.info("[Coordinator] cancelRecording ignored — no active recording")
            return
        }

        logger.info("[Coordinator] 녹음 취소")
        await recordingService?.cancelRecording()
        await MainActor.run { recordingState = .idle }
        cleanup()
    }

    private func cleanup() {
        recordingService = nil
        Task { @MainActor [weak self] in
            self?.currentRMS = 0
        }
    }
}
