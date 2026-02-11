import AVFAudio
import AudioToolbox
import OSLog

/// 마이크 오디오 캡처 서비스
///
/// VoiceProcessingIO AudioUnit을 사용하여 마이크 입력을 캡처.
/// AEC(Acoustic Echo Cancellation) 기능 포함.
final class MicAudioService: AudioListenable {

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

    // MARK: - Audio Unit

    private var audioUnit: AudioUnit?
    private var graph: AUGraph?

    private let logger = Logger(subsystem: "shadow_listening", category: "MicAudioService")

    /// 출력 샘플레이트 (16kHz for ASR)
    private let outputSampleRate: Float64 = 16000

    /// 캡처 샘플레이트 (VoiceProcessingIO 기본값)
    private let captureSampleRate: Float64 = 48000

    /// 스트림 포맷 (Int16, mono)
    private var streamDescription: AudioStreamBasicDescription

    /// AVAudioConverter for resampling (48kHz → 16kHz)
    private var resampleConverter: AVAudioConverter?

    /// 캡처 Float 포맷 (48kHz mono Float32)
    private var captureFloatFormat: AVAudioFormat?

    /// 출력 포맷 (16kHz mono Float32)
    private var outputFormat: AVAudioFormat?

    /// AEC 활성화 여부
    var enableAEC: Bool = true

    /// 마지막 로그 시간 (1초 간격 로그용)
    private var lastLogTime: CFAbsoluteTime = 0

    // MARK: - Initialization

    init() {
        self.streamDescription = Self.createStreamDescription(sampleRate: captureSampleRate)
    }

    deinit {
        stopListening()
    }

    // MARK: - Public Methods

    func startListening() throws {
        guard state == .idle || state == .stopped else {
            throw AudioServiceError.invalidStateTransition(from: state, to: "listening")
        }

        // 출력 포맷 설정 및 AVAudioConverter 초기화
        try setupOutputFormat()

        // AUGraph 및 AudioUnit 설정
        try createAUGraph()
        try configureAudioUnit()
        try configureAEC(enable: enableAEC)

        try startGraph()

        state = .listening
        logger.info("MicAudioService started listening")
    }

    func stopListening() {
        guard state == .listening || state == .paused else { return }

        cleanupAudioResources()

        continuation?.finish()
        continuation = nil
        _audioStream = nil

        state = .stopped
        logger.info("MicAudioService stopped listening")
    }

    func pauseListening() {
        guard state == .listening else { return }
        state = .paused
        logger.info("MicAudioService paused")
    }

    func resumeListening() {
        guard state == .paused else { return }
        state = .listening
        logger.info("MicAudioService resumed")
    }

    // MARK: - Audio Setup

    private static func createStreamDescription(sampleRate: Float64) -> AudioStreamBasicDescription {
        var desc = AudioStreamBasicDescription()
        desc.mSampleRate = sampleRate
        desc.mFormatID = kAudioFormatLinearPCM
        desc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        desc.mFramesPerPacket = 1
        desc.mChannelsPerFrame = 1
        desc.mBitsPerChannel = 16
        desc.mBytesPerPacket = 2
        desc.mBytesPerFrame = 2
        return desc
    }

    private func setupOutputFormat() throws {
        // 캡처 Float 포맷 (48kHz mono Float32)
        guard let floatFormat = AVAudioFormat(
            standardFormatWithSampleRate: captureSampleRate,
            channels: 1
        ) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.captureFloatFormat = floatFormat

        // 출력 포맷 (16kHz mono Float32)
        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: outputSampleRate,
            channels: 1
        ) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.outputFormat = outputFormat

        // AVAudioConverter 초기화 (48kHz → 16kHz)
        guard let converter = AVAudioConverter(from: floatFormat, to: outputFormat) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.resampleConverter = converter

        logger.info("Output format configured: \(self.captureSampleRate)Hz → \(self.outputSampleRate)Hz (AVAudioConverter)")
    }

    private func createAUGraph() throws {
        var status = NewAUGraph(&graph)
        guard status == noErr, let graph = graph else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        var componentDesc = AudioComponentDescription()
        componentDesc.componentType = kAudioUnitType_Output
        componentDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO
        componentDesc.componentManufacturer = kAudioUnitManufacturer_Apple

        var node: AUNode = 0
        status = AUGraphAddNode(graph, &componentDesc, &node)
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        status = AUGraphOpen(graph)
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        status = AUGraphNodeInfo(graph, node, &componentDesc, &audioUnit)
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }
    }

    private func configureAudioUnit() throws {
        guard let audioUnit = audioUnit else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }

        let bus0Output: AudioUnitElement = 0
        let bus1Input: AudioUnitElement = 1

        // 입력 활성화 (마이크)
        var enableInput: UInt32 = 1
        var status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            bus1Input,
            &enableInput,
            UInt32(MemoryLayout.size(ofValue: enableInput))
        )
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        // 출력 비활성화 (스피커로 보내지 않음)
        var enableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            bus0Output,
            &enableOutput,
            UInt32(MemoryLayout.size(ofValue: enableOutput))
        )
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        // 스트림 포맷 설정 (bus 1 input - 마이크에서 받는 포맷)
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            bus1Input,
            &streamDescription,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        // 스트림 포맷 설정 (bus 0 output - 스피커로 보내는 포맷, 비활성화되어도 필요)
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            bus0Output,
            &streamDescription,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        // Input callback 설정
        var callbackStruct = AURenderCallbackStruct(
            inputProc: micInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Input,
            bus1Input,
            &callbackStruct,
            UInt32(MemoryLayout.size(ofValue: callbackStruct))
        )
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }
    }

    private func configureAEC(enable: Bool) throws {
        guard let audioUnit = audioUnit else { return }

        var bypassVoiceProcessing: UInt32 = enable ? 0 : 1
        var status = AudioUnitSetProperty(
            audioUnit,
            kAUVoiceIOProperty_BypassVoiceProcessing,
            kAudioUnitScope_Global,
            0,
            &bypassVoiceProcessing,
            UInt32(MemoryLayout.size(ofValue: bypassVoiceProcessing))
        )
        if status != noErr {
            logger.warning("Failed to configure AEC: \(status)")
        }

        // Ducking 비활성화 - 시스템 오디오 아티팩트 방지
        if #available(macOS 14.0, *) {
            var duckingConfig = AUVoiceIOOtherAudioDuckingConfiguration(
                mEnableAdvancedDucking: false,
                mDuckingLevel: .min
            )
            status = AudioUnitSetProperty(
                audioUnit,
                kAUVoiceIOProperty_OtherAudioDuckingConfiguration,
                kAudioUnitScope_Global,
                0,
                &duckingConfig,
                UInt32(MemoryLayout<AUVoiceIOOtherAudioDuckingConfiguration>.size)
            )
            if status != noErr {
                logger.warning("Failed to configure ducking: \(status)")
            }
        }

        // AGC(자동 이득 제어) 비활성화 - 시스템 오디오 재생 시 아티팩트 방지
        var enableAGC: UInt32 = 0
        status = AudioUnitSetProperty(
            audioUnit,
            kAUVoiceIOProperty_VoiceProcessingEnableAGC,
            kAudioUnitScope_Global,
            0,
            &enableAGC,
            UInt32(MemoryLayout.size(ofValue: enableAGC))
        )
        if status != noErr {
            logger.warning("Failed to disable AGC: \(status)")
        }
    }

    private func startGraph() throws {
        guard let graph = graph else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }

        var status = AUGraphInitialize(graph)
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        status = AUGraphStart(graph)
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        guard let audioUnit = audioUnit else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }

        status = AudioOutputUnitStart(audioUnit)
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }
    }

    private func cleanupAudioResources() {
        let graphToDispose = graph
        let audioUnitToStop = audioUnit

        graph = nil
        audioUnit = nil
        captureFloatFormat = nil
        outputFormat = nil
        resampleConverter = nil

        DispatchQueue.global(qos: .utility).async { [weak self] in
            if let audioUnit = audioUnitToStop {
                AudioOutputUnitStop(audioUnit)
                AudioUnitUninitialize(audioUnit)
            }

            if let graph = graphToDispose {
                AUGraphStop(graph)
                AUGraphUninitialize(graph)
                DisposeAUGraph(graph)
            }

            self?.logger.debug("Audio resources cleaned up")
        }
    }

    // MARK: - Audio Processing (Synchronous AVAudioConverter)

    fileprivate func processAudioBuffer(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber: UInt32,
        inNumberFrames: UInt32
    ) {
        guard state == .listening,
              let audioUnit = audioUnit,
              let floatFormat = captureFloatFormat,
              let outputFormat = outputFormat,
              let converter = resampleConverter else { return }

        // 버퍼 할당 및 렌더링
        let bufferSize = inNumberFrames * UInt32(MemoryLayout<Int16>.size)
        let bufferData = UnsafeMutableRawPointer.allocate(
            byteCount: Int(bufferSize),
            alignment: MemoryLayout<Int16>.alignment
        )
        defer { bufferData.deallocate() }

        var audioBuffer = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: bufferSize,
            mData: bufferData
        )
        var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)

        let status = AudioUnitRender(
            audioUnit,
            ioActionFlags,
            inTimeStamp,
            1,
            inNumberFrames,
            &bufferList
        )
        guard status == noErr else { return }

        // Int16 → Float 변환 (48kHz)
        guard let floatBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: inNumberFrames) else { return }
        floatBuffer.frameLength = inNumberFrames

        let int16Ptr = bufferData.assumingMemoryBound(to: Int16.self)
        guard let floatPtr = floatBuffer.floatChannelData?[0] else { return }

        for i in 0..<Int(inNumberFrames) {
            floatPtr[i] = Float(int16Ptr[i]) / 32768.0
        }

        // AVAudioConverter로 리샘플링 (48kHz → 16kHz) - 동기 처리
        let ratio = outputSampleRate / captureSampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inNumberFrames) * ratio)

        guard let resampledBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var hasData = true
        var callbackCount = 0  // 진단: 콜백 호출 횟수 추적
        let conversionStatus = converter.convert(to: resampledBuffer, error: &error) { inNumPackets, outStatus in
            callbackCount += 1
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return floatBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        guard conversionStatus != .error, error == nil else {
            logger.error("[Mic Resample] Conversion error: \(error?.localizedDescription ?? "unknown")")
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
        if currentTime - lastLogTime >= 1.0 {
            lastLogTime = currentTime
            if let floatData = resampledBuffer.floatChannelData?[0] {
                let count = Int(resampledBuffer.frameLength)
                let samplePreview = (0..<min(5, count)).map { String(format: "%.4f", floatData[$0]) }.joined(separator: ", ")
                logger.info("[MicAudioService] Buffer: frames=\(count), samples=[\(samplePreview)]")
            }
        }

        // 외부 스트림으로 전달 (이미 16kHz로 리샘플링됨)
        continuation?.yield(resampledBuffer)
    }
}

// MARK: - Audio Callback

private func micInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let service = Unmanaged<MicAudioService>.fromOpaque(inRefCon).takeUnretainedValue()
    service.processAudioBuffer(
        ioActionFlags: ioActionFlags,
        inTimeStamp: inTimeStamp,
        inBusNumber: inBusNumber,
        inNumberFrames: inNumberFrames
    )
    return noErr
}
