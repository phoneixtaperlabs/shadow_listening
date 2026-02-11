import AVFAudio
import AudioToolbox
import CoreAudio
import OSLog

/// 시스템 오디오 캡처 서비스
///
/// macOS Process Tap을 사용하여 시스템 오디오를 캡처.
/// Aggregate Device를 통해 오디오 스트림에 접근.
final class SystemAudioService: AudioListenable {

    // MARK: - AudioListenable

    private(set) var state: AudioStreamState = .idle

    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var _audioStream: AsyncStream<AVAudioPCMBuffer>?

    var audioStream: AsyncStream<AVAudioPCMBuffer> {
        if let existing = _audioStream {
            return existing
        }
        let stream = AsyncStream<AVAudioPCMBuffer> { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                // Stream terminated
            }
        }
        _audioStream = stream
        return stream
    }

    // MARK: - System Audio Tap

    private var tap: AudioObjectID = 0
    private var aggregateDevice: AudioObjectID = 0
    private var procID: AudioDeviceIOProcID?
    private var tapStreamDescription = AudioStreamBasicDescription()

    private let logger = Logger(subsystem: "shadow_listening", category: "SystemAudioService")

    /// 출력 샘플레이트 (16kHz for ASR)
    private let outputSampleRate: Float64 = 16000

    /// AVAudioConverter for resampling (tap format → 16kHz mono Float32)
    private var resampleConverter: AVAudioConverter?

    /// 입력 포맷 (Tap에서 받는 포맷)
    private var inputFormat: AVAudioFormat?

    /// 출력 포맷 (16kHz mono Float32)
    private var outputFormat: AVAudioFormat?

    /// 마지막 로그 시간 (1초 간격 로그용)
    private var lastLogTime: CFAbsoluteTime = 0

    // MARK: - Initialization

    deinit {
        stopListening()
    }

    // MARK: - Public Methods

    func startListening() throws {
        guard state == .idle || state == .stopped else {
            throw AudioServiceError.invalidStateTransition(from: state, to: "listening")
        }

        // Process Tap 생성
        try createProcessTap()

        // Aggregate Device 생성
        try createAggregateDevice()

        // 출력 포맷 설정 및 AVAudioConverter 초기화
        try setupOutputFormat()

        // IOProc 시작
        try startIOProc()

        state = .listening
        logger.info("SystemAudioService started listening")
    }

    func stopListening() {
        guard state == .listening || state == .paused else { return }

        cleanupResources()

        continuation?.finish()
        continuation = nil
        _audioStream = nil

        state = .stopped
        logger.info("SystemAudioService stopped listening")
    }

    func pauseListening() {
        guard state == .listening else { return }
        state = .paused
        logger.info("SystemAudioService paused")
    }

    func resumeListening() {
        guard state == .paused else { return }
        state = .listening
        logger.info("SystemAudioService resumed")
    }

    // MARK: - Process Tap Setup

    private func createProcessTap() throws {
        let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "SystemAudioServiceTap"
        tapDescription.isPrivate = false
        tapDescription.muteBehavior = .unmuted
        tapDescription.isMixdown = false
        tapDescription.isMono = true
        tapDescription.isExclusive = true
        tapDescription.processes = []

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        self.tap = tapID
        logger.info("Process Tap created: \(tapID)")
    }

    private func createAggregateDevice() throws {
        guard tap != 0 else {
            throw AudioServiceError.deviceNotAvailable
        }

        let tapUID = getTapUID(tapID: tap)
        let uniqueID = UUID().uuidString
        let aggregateDeviceName = "SystemAudioServiceDevice_\(uniqueID)"

        let deviceDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: false,
                    kAudioSubTapUIDKey: tapUID as String
                ]
            ]
        ]

        var aggregateDeviceID: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(
            deviceDescription as CFDictionary,
            &aggregateDeviceID
        )

        guard status == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            tap = 0
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        self.aggregateDevice = aggregateDeviceID

        // Tap을 Aggregate Device에 추가
        updateAggregateDeviceTapList(aggregateID: aggregateDeviceID, tapUID: tapUID)

        // Tap의 오디오 포맷 가져오기
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let formatStatus = AudioObjectGetPropertyData(
            tap,
            &address,
            0,
            nil,
            &size,
            &tapStreamDescription
        )

        guard formatStatus == noErr else {
            cleanupResources()
            throw AudioServiceError.audioUnitInitializationFailed(formatStatus)
        }

        logger.info("Aggregate Device created. Tap format: \(self.tapStreamDescription.mSampleRate)Hz, \(self.tapStreamDescription.mChannelsPerFrame)ch")
    }

    private func setupOutputFormat() throws {
        // 입력 포맷 (Tap에서 받는 포맷)
        guard let inputFormat = AVAudioFormat(streamDescription: &tapStreamDescription) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.inputFormat = inputFormat

        // 출력 포맷 (16kHz mono Float32)
        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: outputSampleRate,
            channels: 1
        ) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.outputFormat = outputFormat

        // AVAudioConverter 초기화
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.resampleConverter = converter

        logger.info("Output format configured: \(self.tapStreamDescription.mSampleRate)Hz → 16kHz mono Float32 (AVAudioConverter)")
    }

    private func startIOProc() throws {
        guard let inputFormat = self.inputFormat,
              let outputFormat = self.outputFormat,
              let converter = self.resampleConverter else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }

        let inputSampleRate = tapStreamDescription.mSampleRate
        let outputSampleRate = self.outputSampleRate

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDevice, nil) { [weak self] _, inData, _, _, _ in
            guard let self = self, self.state == .listening else { return }

            // 입력 버퍼 생성 (Tap 데이터 복사)
            guard let tempBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                bufferListNoCopy: inData,
                deallocator: nil
            ) else { return }

            tempBuffer.frameLength = tempBuffer.frameCapacity
            let inNumberFrames = tempBuffer.frameLength

            guard let ownedBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inNumberFrames) else { return }
            ownedBuffer.frameLength = inNumberFrames
            self.copyAudioBuffer(from: tempBuffer, to: ownedBuffer)

            // AVAudioConverter로 리샘플링 - 동기 처리
            let ratio = outputSampleRate / inputSampleRate
            let outputFrameCount = AVAudioFrameCount(Double(inNumberFrames) * ratio)

            guard let resampledBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            var hasData = true
            var callbackCount = 0  // 진단: 콜백 호출 횟수 추적
            let conversionStatus = converter.convert(to: resampledBuffer, error: &error) { _, outStatus in
                callbackCount += 1
                if hasData {
                    hasData = false
                    outStatus.pointee = .haveData
                    return ownedBuffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }

            guard conversionStatus != .error, error == nil else {
                self.logger.error("[Sys Resample] Conversion error: \(error?.localizedDescription ?? "unknown")")
                return
            }

            // 프레임 수 정규화: AVAudioConverter 출력이 예상과 다를 수 있음
            // Mic/System 싱크를 위해 항상 예상 프레임 수로 맞춤
            if resampledBuffer.frameLength != outputFrameCount {
                if resampledBuffer.frameLength < outputFrameCount {
                    // 부족하면 마지막 샘플로 패딩
                    if let floatPtr = resampledBuffer.floatChannelData?[0], resampledBuffer.frameLength > 0 {
                        let lastSample = floatPtr[Int(resampledBuffer.frameLength) - 1]
                        for i in Int(resampledBuffer.frameLength)..<Int(outputFrameCount) {
                            floatPtr[i] = lastSample
                        }
                    }
                    resampledBuffer.frameLength = outputFrameCount
                } else {
                    // 초과하면 자름
                    resampledBuffer.frameLength = outputFrameCount
                }
            }

            // 1초 간격 로그
            let currentTime = CFAbsoluteTimeGetCurrent()
            if currentTime - self.lastLogTime >= 1.0 {
                self.lastLogTime = currentTime
                if let floatData = resampledBuffer.floatChannelData?[0] {
                    let count = Int(resampledBuffer.frameLength)
                    let samplePreview = (0..<min(5, count)).map { String(format: "%.4f", floatData[$0]) }.joined(separator: ", ")
                    self.logger.info("[SystemAudioService] Buffer: frames=\(count), samples=[\(samplePreview)]")
                }
            }

            // 외부 스트림으로 전달 (이미 16kHz로 리샘플링됨)
            self.continuation?.yield(resampledBuffer)
        }

        guard status == noErr, let procID = procID else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        self.procID = procID

        let startStatus = AudioDeviceStart(aggregateDevice, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateDevice, procID)
            self.procID = nil
            throw AudioServiceError.audioUnitInitializationFailed(startStatus)
        }

        logger.info("IOProc started")
    }

    // MARK: - Audio Buffer Copy

    private func copyAudioBuffer(from source: AVAudioPCMBuffer, to destination: AVAudioPCMBuffer) {
        let srcList = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer<AudioBufferList>(mutating: source.audioBufferList)
        )
        let dstList = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer<AudioBufferList>(mutating: destination.audioBufferList)
        )
        let bufferCount = min(srcList.count, dstList.count)

        for index in 0..<bufferCount {
            let src = srcList[index]
            if let srcData = src.mData, let dstData = dstList[index].mData {
                let byteCount = min(Int(src.mDataByteSize), Int(dstList[index].mDataByteSize))
                memcpy(dstData, srcData, byteCount)
                dstList[index].mDataByteSize = src.mDataByteSize
            }
        }
    }

    // MARK: - Cleanup

    private func cleanupResources() {
        let procIDToDestroy = procID
        let aggregateDeviceToDestroy = aggregateDevice
        let tapToDestroy = tap

        procID = nil
        aggregateDevice = 0
        tap = 0
        inputFormat = nil
        outputFormat = nil
        resampleConverter = nil

        DispatchQueue.global(qos: .utility).async { [weak self] in
            if let procID = procIDToDestroy, aggregateDeviceToDestroy != 0 {
                AudioDeviceStop(aggregateDeviceToDestroy, procID)
                AudioDeviceDestroyIOProcID(aggregateDeviceToDestroy, procID)
            }

            if aggregateDeviceToDestroy != 0 {
                AudioHardwareDestroyAggregateDevice(aggregateDeviceToDestroy)
            }

            if tapToDestroy != 0 {
                AudioHardwareDestroyProcessTap(tapToDestroy)
            }

            self?.logger.debug("System audio resources cleaned up")
        }
    }

    // MARK: - Helper Methods

    private func getTapUID(tapID: AudioObjectID) -> CFString {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize = UInt32(MemoryLayout<CFString>.stride)
        var tapUID: CFString = "" as CFString

        _ = withUnsafeMutablePointer(to: &tapUID) { tapUID in
            AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, tapUID)
        }

        return tapUID
    }

    private func updateAggregateDeviceTapList(aggregateID: AudioObjectID, tapUID: CFString) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0

        AudioObjectGetPropertyDataSize(aggregateID, &propertyAddress, 0, nil, &propertySize)

        var list: CFArray?
        withUnsafeMutablePointer(to: &list) { list in
            AudioObjectGetPropertyData(aggregateID, &propertyAddress, 0, nil, &propertySize, list)
        }

        if var listAsArray = list as? [CFString] {
            if !listAsArray.contains(tapUID) {
                listAsArray.append(tapUID)
                propertySize += UInt32(MemoryLayout<CFString>.stride)

                list = listAsArray as CFArray
                withUnsafeMutablePointer(to: &list) { list in
                    AudioObjectSetPropertyData(aggregateID, &propertyAddress, 0, nil, propertySize, list)
                }
            }
        }
    }
}
