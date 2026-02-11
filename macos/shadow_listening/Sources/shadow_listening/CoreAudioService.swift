import CoreAudio
import Foundation
import OSLog

/// CoreAudio 디바이스 정보
struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
}

/// CoreAudio 서비스 에러 정의
enum CoreAudioServiceError: Error, LocalizedError {
    /// 프로퍼티 조회 실패
    case propertyQueryFailed(selector: AudioObjectPropertySelector, status: OSStatus)

    /// 리스너 등록 실패
    case listenerRegistrationFailed(selector: AudioObjectPropertySelector, status: OSStatus)

    /// 이미 모니터링 중
    case alreadyMonitoring

    var errorDescription: String? {
        switch self {
        case .propertyQueryFailed(let selector, let status):
            return "CoreAudio property query failed (selector: \(selector), status: \(status))"
        case .listenerRegistrationFailed(let selector, let status):
            return "CoreAudio listener registration failed (selector: \(selector), status: \(status))"
        case .alreadyMonitoring:
            return "CoreAudio device monitoring is already active"
        }
    }
}

/// CoreAudio 디바이스 모니터링 서비스
///
/// 시스템 오디오 디바이스 목록 조회, 기본 입출력 디바이스 감지,
/// 디바이스 변경 이벤트 모니터링을 담당한다.
final class CoreAudioService {

    // MARK: - Properties

    /// 현재 기본 입력 디바이스 ID
    private(set) var defaultInputDevice: AudioDeviceID?

    /// 현재 기본 출력 디바이스 ID
    private(set) var defaultOutputDevice: AudioDeviceID?

    /// 현재 감지된 입력 디바이스 목록
    private(set) var inputDevices: [AudioDevice] = []

    /// 모니터링 활성화 여부
    private(set) var isMonitoring: Bool = false

    /// 디바이스 변경 시 호출되는 콜백
    var onDevicesChanged: (() -> Void)?

    private let logger = Logger(subsystem: "shadow_listening", category: "CoreAudioService")

    // MARK: - Listener

    /// 모니터링 대상 프로퍼티 셀렉터 목록
    private static let monitoredSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioHardwarePropertyDevices,
    ]

    /// 디바이스 변경 리스너 블록
    ///
    /// lazy var로 선언하여 self 캡처 시점을 초기화 이후로 보장한다.
    private lazy var propertyListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.fetchCurrentAudioDevices()
    }

    // MARK: - Initialization

    init() {
        logger.info("CoreAudioService 초기화")
    }

    deinit {
        stopMonitoring()
        logger.info("CoreAudioService 해제")
    }

    // MARK: - Public Methods

    /// 디바이스 모니터링 시작
    ///
    /// 현재 디바이스 상태를 즉시 조회한 후 변경 리스너를 등록한다.
    /// - Throws: `CoreAudioServiceError.alreadyMonitoring` - 이미 모니터링 중인 경우
    /// - Throws: `CoreAudioServiceError.listenerRegistrationFailed` - 리스너 등록 실패
    func startMonitoring() throws {
        guard !isMonitoring else {
            throw CoreAudioServiceError.alreadyMonitoring
        }

        fetchCurrentAudioDevices()

        var registeredSelectors: [AudioObjectPropertySelector] = []

        for selector in Self.monitoredSelectors {
            var address = Self.globalPropertyAddress(selector: selector)
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                propertyListenerBlock
            )
            guard status == noErr else {
                // 이미 등록된 리스너 정리
                for registered in registeredSelectors {
                    var addr = Self.globalPropertyAddress(selector: registered)
                    AudioObjectRemovePropertyListenerBlock(
                        AudioObjectID(kAudioObjectSystemObject),
                        &addr,
                        DispatchQueue.main,
                        propertyListenerBlock
                    )
                }
                throw CoreAudioServiceError.listenerRegistrationFailed(
                    selector: selector, status: status
                )
            }
            registeredSelectors.append(selector)
        }

        isMonitoring = true
        logger.info("디바이스 모니터링 시작")
    }

    /// 디바이스 모니터링 중지
    ///
    /// 등록된 모든 리스너를 해제한다.
    /// 모니터링 중이 아닌 경우 아무 작업도 수행하지 않는다.
    func stopMonitoring() {
        guard isMonitoring else { return }

        for selector in Self.monitoredSelectors {
            var address = Self.globalPropertyAddress(selector: selector)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                propertyListenerBlock
            )
        }

        isMonitoring = false
        logger.info("디바이스 모니터링 중지")
    }

    /// 기본 입력 디바이스 변경
    ///
    /// - Parameter deviceID: 설정할 디바이스 ID
    /// - Returns: 변경 성공 여부
    func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var mutableDeviceID = deviceID
        var address = Self.globalPropertyAddress(
            selector: kAudioHardwarePropertyDefaultInputDevice
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
        if status != noErr {
            logger.error("기본 입력 디바이스 변경 실패 (status: \(status))")
        }
        return status == noErr
    }

    /// 이름으로 입력 디바이스 ID 조회
    ///
    /// - Parameter name: 디바이스 이름
    /// - Returns: 일치하는 디바이스 ID, 없으면 nil
    func getInputDeviceID(fromName name: String) -> AudioDeviceID? {
        return inputDevices.first(where: { $0.name == name })?.id
    }

    // MARK: - Private: Device Fetching

    /// 현재 디바이스 상태 전체 갱신
    private func fetchCurrentAudioDevices() {
        fetchDefaultDevices()
        fetchInputDevices()
        onDevicesChanged?()
    }

    /// 기본 입출력 디바이스 갱신
    private func fetchDefaultDevices() {
        defaultInputDevice = getDefaultDevice(
            selector: kAudioHardwarePropertyDefaultInputDevice
        )
        defaultOutputDevice = getDefaultDevice(
            selector: kAudioHardwarePropertyDefaultOutputDevice
        )
    }

    /// 입력 디바이스 목록 갱신
    private func fetchInputDevices() {
        inputDevices = retrieveAllInputDevices()
    }

    /// 기본 디바이스 ID 조회
    private func getDefaultDevice(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.globalPropertyAddress(selector: selector)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        if status != noErr {
            logger.warning("기본 디바이스 조회 실패 (selector: \(selector), status: \(status))")
            return nil
        }
        return deviceID
    }

    // MARK: - Private: Device Enumeration

    /// 전체 입력 디바이스 목록 조회
    private func retrieveAllInputDevices() -> [AudioDevice] {
        var address = Self.globalPropertyAddress(selector: kAudioHardwarePropertyDevices)
        var dataSize: UInt32 = 0

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        )
        guard status == noErr else {
            logger.warning("디바이스 목록 크기 조회 실패 (status: \(status))")
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = Array(repeating: AudioDeviceID(), count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &audioDevices
        )
        guard status == noErr else {
            logger.warning("디바이스 목록 조회 실패 (status: \(status))")
            return []
        }

        return audioDevices
            .filter { isInputDevice(deviceID: $0) && shouldIncludeDevice(deviceID: $0) }
            .map { AudioDevice(id: $0, name: getDeviceName(deviceID: $0)) }
    }

    /// 입력 스트림 보유 여부 확인
    private func isInputDevice(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    /// 가상/집계 디바이스 필터링
    ///
    /// Aggregate 및 Virtual 타입 디바이스를 제외한다.
    private func shouldIncludeDevice(deviceID: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = Self.globalPropertyAddress(selector: kAudioDevicePropertyTransportType)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType)
        guard status == noErr else { return true }

        if transportType == kAudioDeviceTransportTypeAggregate
            || transportType == kAudioDeviceTransportTypeVirtual
        {
            return false
        }
        return true
    }

    /// 디바이스 이름 조회 (CFString 기반)
    private func getDeviceName(deviceID: AudioDeviceID) -> String {
        var address = Self.globalPropertyAddress(
            selector: kAudioDevicePropertyDeviceNameCFString
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr else {
            logger.warning("디바이스 이름 조회 실패 (deviceID: \(deviceID), status: \(status))")
            return "Unknown Device"
        }
        return name as String
    }

    // MARK: - Private: Helpers

    /// 글로벌 스코프 프로퍼티 주소 생성
    private static func globalPropertyAddress(
        selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
