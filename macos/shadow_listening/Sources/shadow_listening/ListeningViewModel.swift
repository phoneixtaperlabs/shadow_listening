import Combine
import CoreAudio
import CoreGraphics
import Foundation
import OSLog

/// 리스닝 상태
enum ListeningState {
    case idle       // 대기
    case countdown  // 카운트다운 (3-2-1)
    case listening  // 리스닝 활성
}

/// Listening 윈도우의 ViewModel (디바이스 관리 + 리스닝 제어)
///
/// CoreAudioService의 디바이스 데이터를 SwiftUI에 전파하고,
/// 카운트다운 → 리스닝 상태 전환 및 사용자 입력을 처리한다.
@MainActor
final class ListeningViewModel: ObservableObject {

    // MARK: - Published (View 바인딩용)

    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var defaultInputDevice: AudioDeviceID?
    @Published private(set) var listeningState: ListeningState = .idle
    @Published private(set) var countdownNumber: Int = 3
    @Published private(set) var captureTargets: [CaptureTarget] = []
    @Published var selectedCaptureTarget: CaptureTarget?
    @Published private(set) var currentRMS: Float = 0
    @Published var isInPersonMeeting: Bool = false

    /// 현재 기본 입력 디바이스 이름 (파생 값)
    var defaultInputDeviceName: String {
        guard let deviceID = defaultInputDevice else { return "No Device" }
        return inputDevices.first(where: { $0.id == deviceID })?.name ?? "Unknown Device"
    }

    /// 카운트다운 활성 여부 (파생 값)
    var isCountdownActive: Bool { listeningState == .countdown }

    /// 리스닝 활성 여부 (파생 값)
    var isListening: Bool { listeningState == .listening }

    /// 녹음 활성 여부 (Coordinator에서 읽음)
    @available(macOS 14.0, *)
    var isRecording: Bool {
        ListeningCoordinator.shared.recordingState == .recording
    }

    // MARK: - Private State

    /// 리스닝 시작 시각 (확인 다이얼로그 30초 판단용)
    private(set) var listeningStartDate: Date?

    /// 카운트다운 타이머 — deinit에서 반드시 invalidate
    private var countdownTimer: Timer?

    // MARK: - Services

    private let audioService: CoreAudioService
    private let captureService: ScreenshotCaptureService
    private let logger = Logger(subsystem: "shadow_listening", category: "ListeningViewModel")
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        shouldScreenshotCapture: Bool = false,
        audioService: CoreAudioService = CoreAudioService(),
        captureService: ScreenshotCaptureService = ScreenshotCaptureService()
    ) {
        self.audioService = audioService
        self.captureService = captureService
        // [weak self] 필수 — ViewModel → Service → 콜백 → ViewModel 순환 참조 방지
        self.audioService.onDevicesChanged = { [weak self] in
            self?.syncFromService()
        }
        selectedCaptureTarget = shouldScreenshotCapture ? .autoCapture(nil) : .noCapture

        // Coordinator 상태 관찰 — 녹음 에러 시 리스닝 상태 리셋
        if #available(macOS 14.0, *) {
            ListeningCoordinator.shared.$recordingState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    if case .error(let message) = state {
                        self?.logger.error("녹음 에러: \(message)")
                        self?.cleanupListeningState()
                    }
                }
                .store(in: &cancellables)

            ListeningCoordinator.shared.$currentRMS
                .receive(on: DispatchQueue.main)
                .sink { [weak self] rms in
                    self?.currentRMS = rms
                }
                .store(in: &cancellables)
        }

        logger.info("ListeningViewModel 초기화")
    }

    deinit {
        countdownTimer?.invalidate()
        cancellables.removeAll()
        audioService.stopMonitoring()
        logger.info("ListeningViewModel 해제")
    }

    // MARK: - Device Lifecycle

    /// 디바이스 모니터링 시작 및 초기 데이터 동기화
    func startDeviceMonitoring() {
        do {
            try audioService.startMonitoring()
        } catch {
            logger.error("디바이스 모니터링 시작 실패: \(error.localizedDescription)")
        }
        syncFromService()
    }

    /// 디바이스 모니터링 중지
    func stopDeviceMonitoring() {
        audioService.stopMonitoring()
    }

    // MARK: - Device Actions

    /// 이름으로 기본 입력 디바이스 변경
    func setDefaultAudioInputDevice(with name: String) {
        guard let deviceID = audioService.getInputDeviceID(fromName: name) else {
            logger.warning("디바이스를 찾을 수 없음: \(name)")
            return
        }
        if audioService.setDefaultInputDevice(deviceID) {
            logger.info("기본 입력 디바이스 변경: \(name)")
        }
    }

    // MARK: - Listening Control

    /// 카운트다운 시작 → 완료 후 리스닝 상태 전환
    func startCountdownRecording() {
        guard listeningState == .idle else {
            logger.warning("startCountdownRecording 호출 무시 — 현재 상태: \(String(describing: self.listeningState))")
            return
        }

        listeningState = .countdown
        countdownNumber = 3
        logger.info("카운트다운 시작")

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.countdownNumber -= 1

                if self.countdownNumber <= 0 {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.transitionToListening()
                }
            }
        }
    }

    /// 리스닝 취소 (cancel 버튼) — 상태를 idle로 리셋, 녹음 결과 폐기
    func cancelListening() {
        logger.info("리스닝 취소")
        cleanupListeningState()
        if #available(macOS 14.0, *) {
            Task { await ListeningCoordinator.shared.cancelRecording() }
        }
    }

    /// 리스닝 중지 (confirm/done 버튼) — 녹음 결과 반환 후 idle로
    func stopListening() {
        logger.info("리스닝 중지 (확인)")
        cleanupListeningState()
        if #available(macOS 14.0, *) {
            Task {
                _ = await ListeningCoordinator.shared.stopRecording()
                // 청크 결과는 onChunkProcessed로 실시간 전송됨
                // stopRecording의 최종 결과는 Flutter stopListening에서 처리
            }
        }
    }

    // MARK: - Capture Target

    /// 캡처 타겟 목록 갱신 (ScreenshotCaptureService에서 실제 데이터 조회)
    func fetchCaptureTargets() async {
        captureTargets = await captureService.buildCaptureTargets()
        logger.info("캡처 타겟 \(self.captureTargets.count)개 로드")
    }

    /// 캡처 타겟 선택 처리
    func selectCaptureTarget(_ target: CaptureTarget) {
        selectedCaptureTarget = target
        FlutterBridge.shared.invokeCaptureTargetSelected(target.asDictionary())
        logger.info("캡처 타겟 선택: \(target.name)")
    }

    /// Flutter에서 캡처 타겟 업데이트 요청 처리
    /// - Parameters:
    ///   - type: 캡처 타겟 타입 ("noCapture", "autoCapture", "window", "display")
    ///   - windowID: 윈도우 ID (정확 매칭)
    ///   - windowTitle: 윈도우 제목 (부분 매칭, 대소문자 무시)
    ///   - displayID: 디스플레이 ID (정확 매칭)
    ///   - displayName: 디스플레이 이름 (부분 매칭, 대소문자 무시)
    /// - Returns: 매칭된 CaptureTarget, 없으면 nil
    func updateCaptureTarget(
        type: String,
        windowID: Int? = nil,
        windowTitle: String? = nil,
        displayID: Int? = nil,
        displayName: String? = nil
    ) async -> CaptureTarget? {
        await fetchCaptureTargets()

        switch type {
        case "noCapture":
            selectedCaptureTarget = .noCapture
            return .noCapture

        case "autoCapture":
            if windowID != nil || windowTitle != nil {
                for target in captureTargets {
                    if case .window(let info) = target {
                        if let id = windowID, info.windowID == CGWindowID(id) {
                            let t = CaptureTarget.autoCapture(info)
                            selectedCaptureTarget = t
                            return t
                        } else if let title = windowTitle,
                                  info.title.lowercased().contains(title.lowercased()) {
                            let t = CaptureTarget.autoCapture(info)
                            selectedCaptureTarget = t
                            return t
                        }
                    }
                }
                return nil
            } else {
                selectedCaptureTarget = .autoCapture(nil)
                return .autoCapture(nil)
            }

        case "window":
            for target in captureTargets {
                if case .window(let info) = target {
                    if let id = windowID, info.windowID == CGWindowID(id) {
                        selectedCaptureTarget = target
                        return target
                    } else if let title = windowTitle,
                              info.title.lowercased().contains(title.lowercased()) {
                        selectedCaptureTarget = target
                        return target
                    }
                }
            }
            return nil

        case "display":
            for target in captureTargets {
                if case .display(let info) = target {
                    if let id = displayID, info.displayID == id {
                        selectedCaptureTarget = target
                        return target
                    } else if let name = displayName,
                              info.localizedName.lowercased().contains(name.lowercased()) {
                        selectedCaptureTarget = target
                        return target
                    }
                }
            }
            return nil

        default:
            return nil
        }
    }

    // MARK: - Private

    /// 카운트다운 완료 → 리스닝 활성 전환
    private func transitionToListening() {
        listeningState = .listening
        listeningStartDate = Date()
        logger.info("리스닝 상태 전환 — 녹음은 Coordinator에서 이미 진행 중")
    }

    /// 리스닝 상태 완전 정리
    private func cleanupListeningState() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        listeningState = .idle
        countdownNumber = 3
        listeningStartDate = nil
    }

    /// CoreAudioService → ViewModel 데이터 동기화
    private func syncFromService() {
        inputDevices = audioService.inputDevices
        defaultInputDevice = audioService.defaultInputDevice
    }
}
