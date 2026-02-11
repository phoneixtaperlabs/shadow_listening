import AVFoundation
import OSLog

/// 16kHz mono Float32 오디오를 AAC M4A 파일로 저장하는 서비스
final class AudioFileWriter {

    // MARK: - Properties

    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private let inputFormat: AVAudioFormat
    private var sourceFormatDescription: CMAudioFormatDescription?
    private let logger = Logger(subsystem: "shadow_listening", category: "AudioFileWriter")

    private(set) var isWriting: Bool = false
    private(set) var totalFramesWritten: Int64 = 0

    /// 버퍼 대기열 (isReadyForMoreMediaData가 false일 때 큐잉)
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private let maxPendingBuffers = 100  // 약 0.5초 분량 @ 16kHz

    /// 현재 세션의 시작 시간
    private var sessionStartTime: CMTime = .zero

    /// AAC 인코더 비트레이트 (32kbps - 16kHz 모노 음성에 적합)
    private let bitRate: Int = 32000

    // MARK: - Initialization

    init() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: true  // AAC 인코더 호환을 위해 interleaved
        ) else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.inputFormat = format

        // 소스 포맷 설명 생성 (Float32 PCM)
        var asbd = format.streamDescription.pointee
        var formatDesc: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard status == noErr, let desc = formatDesc else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }
        self.sourceFormatDescription = desc
    }

    // MARK: - Public Methods

    /// 녹음 시작 - 새 M4A 파일 생성
    /// - Parameter url: 저장할 파일 경로 (.m4a 확장자)
    func startWriting(to url: URL) throws {
        guard !isWriting else {
            logger.warning("Already writing to a file")
            return
        }

        // 기존 파일 삭제
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // AVAssetWriter 생성 (M4A 컨테이너)
        assetWriter = try AVAssetWriter(url: url, fileType: .m4a)

        // AAC 인코딩 설정
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate
        ]

        audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings,
            sourceFormatHint: sourceFormatDescription
        )
        audioInput?.expectsMediaDataInRealTime = true

        guard let assetWriter = assetWriter,
              let audioInput = audioInput else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }

        if assetWriter.canAdd(audioInput) {
            assetWriter.add(audioInput)
        } else {
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }

        // 쓰기 시작
        guard assetWriter.startWriting() else {
            if let error = assetWriter.error {
                logger.error("Failed to start writing: \(error.localizedDescription)")
            }
            throw AudioServiceError.audioUnitInitializationFailed(-1)
        }

        sessionStartTime = .zero
        assetWriter.startSession(atSourceTime: sessionStartTime)

        isWriting = true
        totalFramesWritten = 0
        pendingBuffers.removeAll()
        logger.info("Started writing AAC to: \(url.lastPathComponent) (\(self.bitRate / 1000)kbps)")
    }

    /// 오디오 버퍼 쓰기
    /// - Parameter buffer: 16kHz mono Float32 버퍼
    func write(_ buffer: AVAudioPCMBuffer) {
        guard isWriting, let audioInput = audioInput else { return }

        // 대기 중인 버퍼 먼저 처리
        while !pendingBuffers.isEmpty && audioInput.isReadyForMoreMediaData {
            let pending = pendingBuffers.removeFirst()
            writeBuffer(pending, to: audioInput)
        }

        // 현재 버퍼 쓰기 시도
        if audioInput.isReadyForMoreMediaData {
            writeBuffer(buffer, to: audioInput)
        } else {
            // 큐에 추가 (최대 개수 제한)
            if pendingBuffers.count < maxPendingBuffers {
                pendingBuffers.append(buffer)
                logger.debug("Buffer queued (pending: \(self.pendingBuffers.count))")
            } else {
                logger.warning("Buffer dropped - queue full (\(self.maxPendingBuffers))")
            }
        }
    }

    /// 버퍼를 실제로 파일에 쓰기
    private func writeBuffer(_ buffer: AVAudioPCMBuffer, to audioInput: AVAssetWriterInput) {
        guard let sampleBuffer = createSampleBuffer(from: buffer) else {
            logger.warning("Failed to create CMSampleBuffer")
            return
        }

        if audioInput.append(sampleBuffer) {
            totalFramesWritten += Int64(buffer.frameLength)
        }
    }

    /// 녹음 중지 - 파일 닫기
    func stopWriting() {
        guard isWriting else { return }

        // 즉시 새로운 write() 호출 차단
        isWriting = false

        // Flush pending buffers
        if let audioInput = audioInput {
            let pendingCount = pendingBuffers.count
            if pendingCount > 0 {
                logger.info("Flushing \(pendingCount) pending buffers...")
            }

            while !pendingBuffers.isEmpty {
                // 최대 100ms 대기
                var waitCount = 0
                while !audioInput.isReadyForMoreMediaData && waitCount < 10 {
                    Thread.sleep(forTimeInterval: 0.01)
                    waitCount += 1
                }

                if audioInput.isReadyForMoreMediaData {
                    let pending = pendingBuffers.removeFirst()
                    writeBuffer(pending, to: audioInput)
                } else {
                    logger.warning("Could not flush \(self.pendingBuffers.count) pending buffers - encoder not ready")
                    break
                }
            }
        }

        let duration = Double(totalFramesWritten) / 16000.0
        logger.info("Stopping... Total frames: \(self.totalFramesWritten), duration: \(String(format: "%.2f", duration))s")

        audioInput?.markAsFinished()

        // 비동기 완료 - 동기적으로 대기
        let semaphore = DispatchSemaphore(value: 0)
        assetWriter?.finishWriting { [weak self] in
            if let error = self?.assetWriter?.error {
                self?.logger.error("Finish writing error: \(error.localizedDescription)")
            } else {
                self?.logger.info("AAC file saved successfully")
            }
            semaphore.signal()
        }

        // 최대 5초 대기
        _ = semaphore.wait(timeout: .now() + 5)

        assetWriter = nil
        audioInput = nil
        // isWriting = false 이미 함수 시작에서 설정됨
        pendingBuffers.removeAll()
    }

    // MARK: - Helpers

    /// AVAudioPCMBuffer → CMSampleBuffer 변환
    private func createSampleBuffer(from buffer: AVAudioPCMBuffer) -> CMSampleBuffer? {
        let frameCount = buffer.frameLength
        guard frameCount > 0 else { return nil }

        // 현재 타임스탬프 계산
        let presentationTime = CMTime(
            value: totalFramesWritten,
            timescale: CMTimeScale(inputFormat.sampleRate)
        )

        // AudioStreamBasicDescription
        var asbd = inputFormat.streamDescription.pointee

        // CMAudioFormatDescription 생성
        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let formatDesc = formatDescription else {
            return nil
        }

        // CMSampleBuffer 생성
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(inputFormat.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        // AudioBufferList에서 데이터 복사
        let audioBufferList = buffer.audioBufferList
        let dataSize = Int(audioBufferList.pointee.mBuffers.mDataByteSize)

        guard let data = audioBufferList.pointee.mBuffers.mData else {
            return nil
        }

        // CMBlockBuffer 생성
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard blockStatus == kCMBlockBufferNoErr, let block = blockBuffer else {
            return nil
        }

        // 데이터 복사
        let copyStatus = CMBlockBufferReplaceDataBytes(
            with: data,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )

        guard copyStatus == kCMBlockBufferNoErr else {
            return nil
        }

        // CMSampleBuffer 생성
        let sampleStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(frameCount),
            presentationTimeStamp: presentationTime,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr else {
            return nil
        }

        return sampleBuffer
    }

    /// Application Support 디렉토리 경로
    private static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("com.taperlabs.shadow")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 기본 저장 경로 생성 (타임스탬프 포함)
    static func defaultOutputURL(filename: String = "mixed_audio") -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return appSupportDirectory.appendingPathComponent("\(filename)_\(timestamp).m4a")
    }

    /// 정확한 파일명으로 저장 경로 생성 (타임스탬프 없음)
    static func outputURL(exactFilename: String) -> URL {
        return appSupportDirectory.appendingPathComponent("\(exactFilename).m4a")
    }
}
