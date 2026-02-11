import Foundation
import AVFoundation

final class MicPermissionProvider: PermissionProvidable {
    var permissionType: String { "microphone" }

    func checkStatus() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }

        case .denied, .restricted:
            PermissionService.openSystemSettings(for: "microphone")
            completion(false)

        @unknown default:
            completion(false)
        }
    }
}
