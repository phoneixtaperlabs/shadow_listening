/// Machine-readable error codes for listening session errors.
/// Sent to Flutter via FlutterBridge.invokeError() as `onError` events.
enum ListeningErrorCode: String {
    // ASR
    case asrInitFailed = "asr_init_failed"
    case asrProcessingFailed = "asr_processing_failed"

    // VAD
    case vadInitFailed = "vad_init_failed"
    case vadCheckFailed = "vad_check_failed"

    // Diarizer
    case diarizerInitFailed = "diarizer_init_failed"
    case diarizationProcessingFailed = "diarization_processing_failed"

    // Audio / File I/O
    case audioInitFailed = "audio_init_failed"
    case audioWriteFailed = "audio_write_failed"

    // Recording lifecycle
    case recordingStartFailed = "recording_start_failed"
    case recordingStopFailed = "recording_stop_failed"
}
