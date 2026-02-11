//
//  UnifiedAudioService.swift
//  shadow_listening
//
//  Unified audio capture service combining Mic + System audio.
//  Uses VoiceProcessingIO for mic (with AEC) and Process Tap for system audio.
//  Mixes at 48kHz, resamples to 16kHz for ASR output.
//

import AVFAudio
import AudioToolbox
import CoreAudio
import OSLog

// MARK: - UnifiedAudioService

/// Unified audio capture service combining microphone and system audio.
///
/// Architecture:
/// - Mic: VoiceProcessingIO AudioUnit (48kHz Int16 mono)
/// - System: Process Tap + Aggregate Device (native rate, decimated to 48kHz)
/// - Mixing: At 48kHz in Mic callback (same frame count via RingBuffer)
/// - Output: Resampled to 16kHz mono Float32 via AVAudioConverter
///
/// Usage:
/// ```swift
/// let service = UnifiedAudioService()
/// try service.startListening()
/// for await buffer in service.audioStream {
///     // Process 16kHz mono Float32 buffer
/// }
/// service.stopListening()
/// ```
@available(macOS 14.0, *)
final class UnifiedAudioService: AudioListenable {

    // MARK: - AudioListenable Protocol

    private(set) var state: AudioStreamState = .idle

    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var _audioStream: AsyncStream<AVAudioPCMBuffer>?

    // Mic-only stream (VAD용)
    private var micOnlyContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var _micOnlyStream: AsyncStream<AVAudioPCMBuffer>?

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

    /// Mic-only 16kHz stream (믹싱 전, VAD용)
    var micOnlyStream: AsyncStream<AVAudioPCMBuffer> {
        if let existing = _micOnlyStream {
            return existing
        }
        let stream = AsyncStream<AVAudioPCMBuffer> { [weak self] continuation in
            self?.micOnlyContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                // Stream terminated
            }
        }
        _micOnlyStream = stream
        return stream
    }

    // MARK: - Configuration

    /// Capture sample rate (VoiceProcessingIO operates at 48kHz)
    private let captureSampleRate: Float64 = 48000

    /// Output sample rate for ASR (16kHz standard)
    private let outputSampleRate: Float64 = 16000

    /// Enable system audio mixing (set before startListening)
    var enableSystemAudioMixing: Bool = true

    /// Mic gain for mixing (0.0 - 1.0)
    var micGain: Float = 1.0

    /// System audio gain for mixing (0.0 - 1.0)
    var sysGain: Float = 1.0

    // MARK: - Mic Audio Components

    private var audioUnit: AudioUnit?
    private var graph: AUGraph?
    private var micStreamDescription: AudioStreamBasicDescription

    // MARK: - System Audio Components

    private var tap: AudioObjectID = 0
    private var aggregateDevice: AudioObjectID = 0
    private var procID: AudioDeviceIOProcID?
    private var tapStreamDescription = AudioStreamBasicDescription()

    /// System audio RingBuffer (48kHz samples for mixing)
    private let systemRingBuffer = AtomicRingBuffer(capacity: 65536)  // ~1.4s @ 48kHz

    /// System audio resampler (Tap rate → 48kHz)
    private var systemResampleConverter: AVAudioConverter?
    private var systemInputFormat: AVAudioFormat?
    private var systemOutputFormat: AVAudioFormat?

    // MARK: - Resampling Components

    private var captureFloatFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var resampleConverter: AVAudioConverter?

    /// Mic-only 리샘플러 (48kHz → 16kHz)
    private var micOnlyResampleConverter: AVAudioConverter?

    // MARK: - Logging

    private let logger = Logger(subsystem: "shadow_listening", category: "UnifiedAudioService")
    private var lastLogTime: CFAbsoluteTime = 0

    // MARK: - Initialization

    init() {
        self.micStreamDescription = Self.createMicStreamDescription(sampleRate: captureSampleRate)
    }

    deinit {
        stopListening()
    }

    // MARK: - AudioListenable Methods

    func startListening() throws {
        guard state == .idle || state == .stopped else {
            throw AudioServiceError.invalidStateTransition(from: state, to: "listening")
        }

        // Setup resampling (48kHz -> 16kHz)
        try setupResamplingFormats()

        // Setup system audio first (if enabled)
        if enableSystemAudioMixing {
            try setupSystemAudio()
        }

        // Setup and start mic audio
        try setupMicAudio()
        try startMicGraph()

        // Reset system buffer after mic starts (sync point)
        systemRingBuffer.reset()

        state = .listening
        logger.info("UnifiedAudioService started (sysAudio=\(self.enableSystemAudioMixing))")
    }

    func stopListening() {
        guard state == .listening || state == .paused else { return }

        cleanupMicAudio()
        cleanupSystemAudio()

        continuation?.finish()
        continuation = nil
        _audioStream = nil

        micOnlyContinuation?.finish()
        micOnlyContinuation = nil
        _micOnlyStream = nil

        captureFloatFormat = nil
        outputFormat = nil
        resampleConverter = nil
        micOnlyResampleConverter = nil

        state = .stopped
        logger.info("UnifiedAudioService stopped")
    }

    func pauseListening() {
        guard state == .listening else { return }
        state = .paused
        logger.info("UnifiedAudioService paused")
    }

    func resumeListening() {
        guard state == .paused else { return }
        state = .listening
        logger.info("UnifiedAudioService resumed")
    }

    // MARK: - Audio Format Setup

    private static func createMicStreamDescription(sampleRate: Float64) -> AudioStreamBasicDescription {
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

    private func setupResamplingFormats() throws {
        // Capture format: 48kHz mono Float32
        guard let floatFormat = AVAudioFormat(
            standardFormatWithSampleRate: captureSampleRate,
            channels: 1
        ) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.captureFloatFormat = floatFormat

        // Output format: 16kHz mono Float32
        guard let outFormat = AVAudioFormat(
            standardFormatWithSampleRate: outputSampleRate,
            channels: 1
        ) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.outputFormat = outFormat

        // AVAudioConverter for 48kHz -> 16kHz (mixed audio)
        guard let converter = AVAudioConverter(from: floatFormat, to: outFormat) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.resampleConverter = converter

        // Mic-only resampler (48kHz -> 16kHz) - 별도 인스턴스로 독립적 상태 유지
        guard let micOnlyConverter = AVAudioConverter(from: floatFormat, to: outFormat) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.micOnlyResampleConverter = micOnlyConverter

        logger.info("Resampling configured: \(self.captureSampleRate)Hz -> \(self.outputSampleRate)Hz (mixed + micOnly)")
    }

    // MARK: - Mic Audio Setup (VoiceProcessingIO)

    private func setupMicAudio() throws {
        // Create AUGraph
        var status = NewAUGraph(&graph)
        guard status == noErr, let graph = graph else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        // Add VoiceProcessingIO node
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

        try configureMicAudioUnit()
        try configureMicAEC()
    }

    private func configureMicAudioUnit() throws {
        guard let audioUnit = audioUnit else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }

        let bus0Output: AudioUnitElement = 0
        let bus1Input: AudioUnitElement = 1

        // Enable input (microphone)
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

        // Disable output (no speaker playback)
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

        // Set stream format (bus 1 input - mic format)
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            bus1Input,
            &micStreamDescription,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        // Set stream format (bus 0 output - required even if disabled)
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            bus0Output,
            &micStreamDescription,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }

        // Set input callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: unifiedMicInputCallback,
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

    private func configureMicAEC() throws {
        guard let audioUnit = audioUnit else { return }

        // Enable voice processing (AEC)
        var bypassVoiceProcessing: UInt32 = 0  // 0 = enabled
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

        // Disable ducking to prevent system audio artifacts
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

        // Disable AGC to prevent artifacts during system audio playback
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

    private func startMicGraph() throws {
        guard let graph = graph, let audioUnit = audioUnit else {
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

        status = AudioOutputUnitStart(audioUnit)
        guard status == noErr else {
            throw AudioServiceError.audioUnitInitializationFailed(status)
        }
    }

    private func cleanupMicAudio() {
        let graphToDispose = graph
        let audioUnitToStop = audioUnit

        graph = nil
        audioUnit = nil

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

            self?.logger.debug("Mic audio resources cleaned up")
        }
    }

    // MARK: - System Audio Setup (Process Tap)

    private func setupSystemAudio() throws {
        try createProcessTap()
        try createAggregateDevice()
        try startSystemIOProc()
    }

    private func createProcessTap() throws {
        let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "UnifiedAudioServiceTap"
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
        let aggregateDeviceName = "UnifiedAudioDevice_\(uniqueID)"

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

        // Add tap to aggregate device
        updateAggregateDeviceTapList(aggregateID: aggregateDeviceID, tapUID: tapUID)

        // Get tap's audio format
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
            cleanupSystemAudio()
            throw AudioServiceError.audioUnitInitializationFailed(formatStatus)
        }

        // Setup system audio resampler (Tap rate → 48kHz)
        let tapRate = tapStreamDescription.mSampleRate

        guard let inputFormat = AVAudioFormat(streamDescription: &tapStreamDescription) else {
            cleanupSystemAudio()
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.systemInputFormat = inputFormat

        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: captureSampleRate,
            channels: 1
        ) else {
            cleanupSystemAudio()
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.systemOutputFormat = outputFormat

        // Create converter if tap rate differs from 48kHz
        if tapRate != captureSampleRate {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                cleanupSystemAudio()
                throw AudioServiceError.audioUnitInitializationFailed(-1)
            }
            self.systemResampleConverter = converter
            logger.info("Aggregate Device created. Tap: \(tapRate)Hz → resampling to 48kHz")
        } else {
            self.systemResampleConverter = nil
            logger.info("Aggregate Device created. Tap: \(tapRate)Hz (native 48kHz, no resampling)")
        }
    }

    private func startSystemIOProc() throws {
        var procID: AudioDeviceIOProcID?
        var localStreamDescription = self.tapStreamDescription
        let targetSampleRate = self.captureSampleRate
        let ringBuffer = self.systemRingBuffer

        // Capture resampler components for the IOProc closure
        let converter = self.systemResampleConverter
        let inputFormat = self.systemInputFormat
        let outputFormat = self.systemOutputFormat

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDevice, nil) { _, inData, _, _, _ in
            // Create AVAudioFormat from tap stream description
            guard let format = AVAudioFormat(streamDescription: &localStreamDescription) else { return }

            // Create AVAudioPCMBuffer from the buffer list (read-only approach)
            guard let tempBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: inData,
                deallocator: nil
            ) else { return }

            tempBuffer.frameLength = tempBuffer.frameCapacity
            let frameLength = Int(tempBuffer.frameLength)
            let tapSampleRate = localStreamDescription.mSampleRate

            // Resample to 48kHz if needed
            if let converter = converter,
               let inputFormat = inputFormat,
               let outputFormat = outputFormat,
               tapSampleRate != targetSampleRate {

                // Calculate output frame count
                let ratio = targetSampleRate / tapSampleRate
                let outputFrameCount = AVAudioFrameCount(Double(frameLength) * ratio)

                guard let resampledBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: outputFrameCount
                ) else { return }

                // Copy input buffer (converter may modify it)
                guard let ownedBuffer = AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    frameCapacity: tempBuffer.frameLength
                ) else { return }
                ownedBuffer.frameLength = tempBuffer.frameLength

                if let srcData = tempBuffer.floatChannelData?[0],
                   let dstData = ownedBuffer.floatChannelData?[0] {
                    memcpy(dstData, srcData, frameLength * MemoryLayout<Float>.size)
                }

                var error: NSError?
                var hasData = true
                converter.convert(to: resampledBuffer, error: &error) { _, outStatus in
                    if hasData {
                        hasData = false
                        outStatus.pointee = .haveData
                        return ownedBuffer
                    } else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                }

                // Write resampled 48kHz samples to RingBuffer
                if let floatData = resampledBuffer.floatChannelData?[0] {
                    ringBuffer.write(floatData, count: Int(resampledBuffer.frameLength))
                }
            } else {
                // Already 48kHz - write directly
                if let floatData = tempBuffer.floatChannelData?[0] {
                    ringBuffer.write(floatData, count: frameLength)
                }
            }
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

        logger.info("System audio IOProc started")
    }

    private func cleanupSystemAudio() {
        let procIDToDestroy = procID
        let aggregateDeviceToDestroy = aggregateDevice
        let tapToDestroy = tap

        procID = nil
        aggregateDevice = 0
        tap = 0
        systemRingBuffer.reset()
        systemResampleConverter = nil
        systemInputFormat = nil
        systemOutputFormat = nil

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

    // MARK: - Audio Processing (Mic Callback)

    fileprivate func processMicCallback(
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

        // Allocate buffer for mic render
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

        // Convert Int16 to Float (48kHz)
        guard let micFloatBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: inNumberFrames) else { return }
        micFloatBuffer.frameLength = inNumberFrames

        let int16Ptr = bufferData.assumingMemoryBound(to: Int16.self)
        guard let micFloatPtr = micFloatBuffer.floatChannelData?[0] else { return }

        for i in 0..<Int(inNumberFrames) {
            micFloatPtr[i] = Float(int16Ptr[i]) / 32768.0
        }

        // Mic-only 16kHz 출력 (VAD용) - 믹싱 전에 처리
        let ratio = outputSampleRate / captureSampleRate
        if let micOnlyConverter = micOnlyResampleConverter {
            let micOnlyOutputFrameCount = AVAudioFrameCount(Double(inNumberFrames) * ratio)

            if let micOnlyResampledBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: micOnlyOutputFrameCount
            ) {
                // micFloatBuffer 복사 (converter가 소비하므로)
                guard let micFloatBufferCopy = AVAudioPCMBuffer(
                    pcmFormat: floatFormat,
                    frameCapacity: inNumberFrames
                ) else { return }
                micFloatBufferCopy.frameLength = inNumberFrames

                if let srcPtr = micFloatBuffer.floatChannelData?[0],
                   let dstPtr = micFloatBufferCopy.floatChannelData?[0] {
                    memcpy(dstPtr, srcPtr, Int(inNumberFrames) * MemoryLayout<Float>.size)
                }

                var micOnlyError: NSError?
                var micOnlyHasData = true
                let micOnlyStatus = micOnlyConverter.convert(to: micOnlyResampledBuffer, error: &micOnlyError) { _, outStatus in
                    if micOnlyHasData {
                        micOnlyHasData = false
                        outStatus.pointee = .haveData
                        return micFloatBufferCopy
                    } else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                }

                if micOnlyStatus != .error, micOnlyError == nil, micOnlyResampledBuffer.frameLength > 0 {
                    micOnlyContinuation?.yield(micOnlyResampledBuffer)
                }
            }
        }

        // Mix with system audio at 48kHz
        let mixedFloatBuffer: AVAudioPCMBuffer
        if enableSystemAudioMixing {
            guard let mixed = mixWithSystemAudio(micBuffer: micFloatBuffer) else { return }
            mixedFloatBuffer = mixed
        } else {
            mixedFloatBuffer = micFloatBuffer
        }

        // Resample from 48kHz to 16kHz (ratio already calculated above)
        let outputFrameCount = AVAudioFrameCount(Double(inNumberFrames) * ratio)

        guard let resampledBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var hasData = true
        let conversionStatus = converter.convert(to: resampledBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return mixedFloatBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        guard conversionStatus != .error, error == nil else {
            logger.error("Resampling error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        // Normalize frame count for consistent output
        if resampledBuffer.frameLength != outputFrameCount {
            if resampledBuffer.frameLength < outputFrameCount {
                // Pad with silence (0.0) instead of last sample to avoid repetition artifacts
                if let floatPtr = resampledBuffer.floatChannelData?[0] {
                    for i in Int(resampledBuffer.frameLength)..<Int(outputFrameCount) {
                        floatPtr[i] = 0.0
                    }
                }
                resampledBuffer.frameLength = outputFrameCount
            } else {
                // Trim excess
                resampledBuffer.frameLength = outputFrameCount
            }
        }

        // Debug logging (1 second interval)
        let currentTime = CFAbsoluteTimeGetCurrent()
        if currentTime - lastLogTime >= 1.0 {
            lastLogTime = currentTime
            let bufferLevel = systemRingBuffer.availableToRead
            logger.info("[UnifiedAudio] Output: \(resampledBuffer.frameLength) frames, sysBuffer: \(bufferLevel)")
        }

        // Yield to stream
        continuation?.yield(resampledBuffer)
    }

    /// Mix mic buffer with system audio from RingBuffer at 48kHz
    private func mixWithSystemAudio(micBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let micData = micBuffer.floatChannelData?[0],
              let floatFormat = captureFloatFormat else { return nil }

        let frameCount = Int(micBuffer.frameLength)

        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: floatFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }
        outputBuffer.frameLength = AVAudioFrameCount(frameCount)

        guard let outputData = outputBuffer.floatChannelData?[0] else { return nil }

        // Read system audio (same frame count as mic)
        let sysAudioSamples = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        defer { sysAudioSamples.deallocate() }

        let readCount = systemRingBuffer.read(sysAudioSamples, count: frameCount)

        // Mix
        if readCount > 0 {
            for i in 0..<frameCount {
                let mixed = micData[i] * micGain + sysAudioSamples[i] * sysGain
                outputData[i] = max(-1.0, min(1.0, mixed))
            }
        } else {
            // No system audio - passthrough mic only
            for i in 0..<frameCount {
                outputData[i] = max(-1.0, min(1.0, micData[i] * micGain))
            }
        }

        return outputBuffer
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

// MARK: - Mic Input Callback

private func unifiedMicInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let service = Unmanaged<UnifiedAudioService>.fromOpaque(inRefCon).takeUnretainedValue()
    service.processMicCallback(
        ioActionFlags: ioActionFlags,
        inTimeStamp: inTimeStamp,
        inBusNumber: inBusNumber,
        inNumberFrames: inNumberFrames
    )
    return noErr
}
