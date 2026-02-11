import AVFAudio
import OSLog

/// Mic Audio와 System Audio를 실시간으로 믹싱하는 서비스
///
/// - Mic Audio: 기준 타이밍으로 사용
/// - System Audio: RingBuffer를 통해 타이밍 불일치 흡수
@available(macOS 13.0, iOS 16.0, *)
final class AudioMixer {

    // MARK: - Properties

    /// System Audio용 RingBuffer (약 2초 @ 16kHz = 32768 samples)
    private let sysAudioBuffer: AtomicRingBuffer

    /// 출력 포맷 (16kHz mono Float32)
    private let outputFormat: AVAudioFormat

    /// 믹싱 비율 (0.0 ~ 1.0)
    /// - micGain: 마이크 볼륨
    /// - sysGain: 시스템 오디오 볼륨
    var micGain: Float = 1.0
    var sysGain: Float = 1.0

    /// 로깅
    private let logger = Logger(subsystem: "shadow_listening", category: "AudioMixer")

    // MARK: - Initialization

    init() throws {
        // RingBuffer: 32768 samples ≈ 2초 @ 16kHz
        self.sysAudioBuffer = AtomicRingBuffer(capacity: 32768)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.outputFormat = format

        logger.info("AudioMixer initialized (buffer: 32768 samples, ~2s @ 16kHz)")
    }

    // MARK: - System Audio Input

    /// System Audio 버퍼를 RingBuffer에 추가
    func enqueueSysAudio(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        sysAudioBuffer.write(floatData, count: frameCount)
    }

    // MARK: - Mixing

    /// Mic 버퍼와 RingBuffer의 System Audio를 믹싱
    /// - Parameter micBuffer: 마이크 오디오 버퍼 (기준 타이밍)
    /// - Returns: 믹싱된 오디오 버퍼, 실패 시 nil
    func mix(micBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let micData = micBuffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(micBuffer.frameLength)

        // 출력 버퍼 생성
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }
        outputBuffer.frameLength = AVAudioFrameCount(frameCount)

        guard let outputData = outputBuffer.floatChannelData?[0] else { return nil }

        // System Audio 읽기 (Mic과 동일한 프레임 수)
        let sysAudioSamples = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        defer { sysAudioSamples.deallocate() }

        let readCount = sysAudioBuffer.read(sysAudioSamples, count: frameCount)

        // 믹싱: 단순히 같은 인덱스끼리 더함
        if readCount > 0 {
            for i in 0..<frameCount {
                let mixed = micData[i] * micGain + sysAudioSamples[i] * sysGain
                outputData[i] = max(-1.0, min(1.0, mixed))
            }
        } else {
            // System Audio 없으면 Mic만 출력
            for i in 0..<frameCount {
                outputData[i] = max(-1.0, min(1.0, micData[i] * micGain))
            }
        }

        return outputBuffer
    }

    /// Mic 버퍼만 반환 (System Audio 없이)
    func passThroughMic(_ micBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let micData = micBuffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(micBuffer.frameLength)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }
        outputBuffer.frameLength = AVAudioFrameCount(frameCount)

        if let outputData = outputBuffer.floatChannelData?[0] {
            memcpy(outputData, micData, frameCount * MemoryLayout<Float>.size)
        }

        return outputBuffer
    }

    // MARK: - Status

    /// RingBuffer에 쌓인 System Audio 샘플 수
    var sysAudioAvailable: Int {
        sysAudioBuffer.availableToRead
    }

    /// RingBuffer 초기화
    func reset() {
        sysAudioBuffer.reset()
        logger.info("AudioMixer reset")
    }
}
