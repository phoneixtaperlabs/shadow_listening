import Foundation
import AppKit
import CoreGraphics

final class ScreenRecordingPermissionProvider: PermissionProvidable {
    var permissionType: String { "screenRecording" }

    func checkStatus() -> Bool {
        // 먼저 CGPreflightScreenCaptureAccess로 체크
        let preflightResult = CGPreflightScreenCaptureAccess()
        if preflightResult {
            return true
        }
        // 추가로 실제 윈도우 접근 가능 여부 체크
        return canRecordScreen()
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        // CGRequestScreenCaptureAccess는 권한 다이얼로그를 표시
        // 이 함수는 즉시 반환되고, 사용자가 설정에서 권한을 부여해야 함
        let granted = CGRequestScreenCaptureAccess()

        if !granted {
            PermissionService.openSystemSettings(for: "screen")
        }

        // 권한 요청 후 상태 반환
        DispatchQueue.main.async {
            completion(granted)
        }
    }

    // MARK: - Window List 기반 실시간 체크

    private func canRecordScreen() -> Bool {
        let runningApplication = NSRunningApplication.current
        let processIdentifier = runningApplication.processIdentifier

        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: AnyObject]] else {
            return false
        }

        for window in windows {
            guard let windowProcessIdentifier = (window[String(kCGWindowOwnerPID)] as? Int).flatMap(pid_t.init) else {
                continue
            }

            // 현재 프로세스 소유 윈도우는 스킵
            if windowProcessIdentifier == processIdentifier {
                continue
            }

            guard let windowRunningApplication = NSRunningApplication(processIdentifier: windowProcessIdentifier) else {
                continue
            }

            // 윈도우 이름에 접근 가능하면 권한이 있는 것
            if window[String(kCGWindowName)] as? String != nil {
                // Dock은 제외 (데스크탑 배경 제공)
                if windowRunningApplication.executableURL?.lastPathComponent == "Dock" {
                    continue
                }
                return true
            }
        }

        return false
    }
}
