//
//  SystemAudioPermissionProvider.swift
//  shadow_listening
//
//  Created by Phoenix on 1/19/26.
//

import Foundation
import AppKit
import os.log

final class SystemAudioPermissionProvider: PermissionProvidable {
    var permissionType: String { "sysAudio" }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.shadow.listening",
        category: String(describing: SystemAudioPermissionProvider.self)
    )

    enum Status: String {
        case unknown
        case denied
        case authorized
    }

    private(set) var status: Status = .unknown

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatus()
        }
        updateStatus()
    }

    func checkStatus() -> Bool {
        updateStatus()
        return status == .authorized
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        logger.debug("requestAccess called")

        guard let request = Self.requestSPI else {
            logger.fault("Request SPI missing")
            completion(false)
            return
        }

        request("kTCCServiceAudioCapture" as CFString, nil) { [weak self] granted in
            guard let self else { return }

            self.logger.info("Request finished with result: \(granted, privacy: .public)")

            if !granted {
                PermissionService.openSystemSettings(for: "screen")
            }

            DispatchQueue.main.async {
                self.status = granted ? .authorized : .denied
                completion(granted)
            }
        }
    }

    private func updateStatus() {
        logger.debug("updateStatus called")

        guard let preflight = Self.preflightSPI else {
            logger.fault("Preflight SPI missing")
            return
        }

        let result = preflight("kTCCServiceAudioCapture" as CFString, nil)

        if result == 1 {
            status = .denied
        } else if result == 0 {
            status = .authorized
        } else {
            status = .unknown
        }
    }

    // MARK: - TCC Private Framework SPI

    private typealias PreflightFuncType = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFuncType = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let apiHandle: UnsafeMutableRawPointer? = {
        let tccPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"
        guard let handle = dlopen(tccPath, RTLD_NOW) else {
            assertionFailure("dlopen failed")
            return nil
        }
        return handle
    }()

    private static let preflightSPI: PreflightFuncType? = {
        guard let apiHandle else { return nil }
        let fnName = "TCCAccessPreflight"
        guard let funcSym = dlsym(apiHandle, fnName) else {
            assertionFailure("Couldn't find symbol")
            return nil
        }
        return unsafeBitCast(funcSym, to: PreflightFuncType.self)
    }()

    private static let requestSPI: RequestFuncType? = {
        guard let apiHandle else { return nil }
        let fnName = "TCCAccessRequest"
        guard let funcSym = dlsym(apiHandle, fnName) else {
            assertionFailure("Couldn't find symbol")
            return nil
        }
        return unsafeBitCast(funcSym, to: RequestFuncType.self)
    }()
}
