import SwiftUI
import OSLog

/// 리스닝 윈도우의 메인 뷰
///
/// 상단: 설정 패널 (디바이스 목록 + 현재 디바이스)
/// 하단: 컨트롤 바 (카운트다운, 최소화/취소/확인, 파형 아이콘)
///
/// ## 메모리 소유권
/// `@StateObject`로 ViewModel을 소유 — 윈도우 닫힘 시 전체 체인 해제.
/// ```
/// WindowManager → NSWindow → NSHostingView → ListeningView
///   → @StateObject ViewModel → CoreAudioService
/// ```
struct ListeningView: View {
    @StateObject private var viewModel: ListeningViewModel
    @State private var showDevices = false
    @State private var showCaptureTargets = false
    @State private var isControlBarExpanded = false
    @State private var initialLoad = true

    /// auto-collapse 취소용 작업
    @State private var autoCollapseTask: DispatchWorkItem?

    init(shouldScreenshotCapture: Bool = false) {
        _viewModel = StateObject(wrappedValue: ListeningViewModel(shouldScreenshotCapture: shouldScreenshotCapture))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 15) {
            // 설정 패널
            settingsPanel
                .opacity(isControlBarExpanded ? 1 : 0)
                .animation(.easeInOut, value: isControlBarExpanded)

            // 컨트롤 바
            ListeningControlBar(isExpanded: $isControlBarExpanded)
                .onHover { hovering in
                    if hovering {
                        autoCollapseTask?.cancel()
                        autoCollapseTask = nil
                        if initialLoad { initialLoad = false }
                    }

                    guard !initialLoad else { return }

                    withAnimation {
                        if !isControlBarExpanded && hovering {
                            showDevices = false
                            showCaptureTargets = false
                            isControlBarExpanded = true
                        }
                    }
                }
        }
        .environmentObject(viewModel)
        .padding(EdgeInsets(top: 15, leading: 0, bottom: 5, trailing: 3))
        .onAppear {
            WindowManager.shared.listeningViewModel = viewModel
            viewModel.startDeviceMonitoring()
            viewModel.startCountdownRecording()
            isControlBarExpanded = true

            let task = DispatchWorkItem {
                withAnimation {
                    initialLoad = false
                    isControlBarExpanded = false
                }
            }
            autoCollapseTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
        }
        .onDisappear {
            autoCollapseTask?.cancel()
            autoCollapseTask = nil
            viewModel.stopDeviceMonitoring()
        }
        .onHover { hovering in
            if hovering {
                autoCollapseTask?.cancel()
                autoCollapseTask = nil
                if initialLoad { initialLoad = false }
            }

            if isControlBarExpanded {
                withAnimation {
                    isControlBarExpanded = hovering
                    if !isControlBarExpanded {
                        showDevices = false
                        showCaptureTargets = false
                    }
                }
            }
        }
        .background(.clear)
    }

    // MARK: - Subviews

    /// 설정 패널: 캡처 타겟 + 디바이스
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 대면 미팅 토글
            InPersonMeetingToggleView(isInPersonMeeting: $viewModel.isInPersonMeeting)

            Divider()

            // 캡처 타겟 목록 (탭으로 토글)
            if showCaptureTargets && isControlBarExpanded {
                CaptureTargetListView()

                Divider()
            }

            // 현재 캡처 타겟 표시 (탭하면 목록 토글)
            CaptureTargetView()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { showCaptureTargets.toggle() }
                }
                .opacity(isControlBarExpanded ? 1 : 0)

            Divider()

            // 디바이스 목록 (탭으로 토글)
            if showDevices && isControlBarExpanded {
                ListeningDeviceListView()

                Divider()
            }

            // 현재 디바이스 표시 (탭하면 목록 토글)
            ListeningDeviceView()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { showDevices.toggle() }
                }
                .opacity(isControlBarExpanded ? 1 : 0)
        }
        .frame(width: 220)
        .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundHard)
                .stroke(Color.borderHard, lineWidth: 1)
        )
    }
}
