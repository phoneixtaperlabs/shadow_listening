import OSLog
import SwiftUI

// MARK: - ControlBarButton

/// 컨트롤 바 내부 재사용 버튼
///
/// SF Symbol 아이콘 + 커스텀 탭 영역 + plain 버튼 스타일
struct ControlBarButton: View {
    let systemName: String
    let action: () -> Void
    var color: Color = .text1

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ControlDivider

/// 컨트롤 바 내부 수직 구분선
struct ControlDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderSoft.opacity(0.5))
            .frame(width: 1, height: 16)
    }
}

// MARK: - ListeningControlBar

/// 리스닝 컨트롤 바
///
/// 확장/축소 두 가지 상태를 가진다.
/// - 확장: minimize | close | confirm | waveform
/// - 축소: waveform 아이콘만 표시
/// - 카운트다운: 카운트다운 숫자 + waveform
struct ListeningControlBar: View {
    @EnvironmentObject var viewModel: ListeningViewModel
    @Binding var isExpanded: Bool

    /// 30초 이상 리스닝 후 취소 시 확인 다이얼로그 표시
    @State private var showCancelConfirmation = false

    private let logger = Logger(subsystem: "shadow_listening", category: "ListeningControlBar")

    var body: some View {
        HStack(spacing: 0) {
            if isExpanded {
                expandedControls
            }

            if viewModel.isCountdownActive {
                countdownView
            } else {
                waveformButton
            }
        }
        .padding(.horizontal, isExpanded || viewModel.isCountdownActive ? 8 : 4)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.backgroundHard)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.borderHard, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        .confirmationDialog(
            "Are you sure you want to cancel??",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Yes, delete", role: .destructive) {
                performCancel()
            }
            Button("No, keep listening", role: .cancel) {}
        } message: {
            Text("This will delete all data from the current meeting.")
        }
    }

    // MARK: - Subviews

    /// 카운트다운 숫자 표시
    private var countdownView: some View {
        Text("\(viewModel.countdownNumber)")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundColor(Color.brandSecondary)
            .frame(width: 30, height: 30)
    }

    /// 확장 상태 컨트롤 버튼들
    private var expandedControls: some View {
        HStack(spacing: 6) {
            // 최소화
            ControlBarButton(systemName: "minus") {
                minimizeWindow()
            }

            ControlDivider()

            // 닫기 (취소)
            ControlBarButton(systemName: "xmark") {
                handleCloseRequest()
            }

            ControlDivider()

            // 확인 (완료)
            ControlBarButton(
                systemName: "checkmark",
                action: { performConfirm() },
                color: viewModel.isCountdownActive ? Color.text4 : Color.green
            )
            .disabled(viewModel.isCountdownActive)

            ControlDivider()
        }
    }

    /// 파형 아이콘 (Lottie 대체 — WaveformView 애니메이션)
    /// listening 상태: 실시간 RMS 볼륨 반영, 그 외: 루프 애니메이션
    private var waveformButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Group {
                if viewModel.isListening {
                    WaveformView(rmsLevel: CGFloat(viewModel.currentRMS), size: .xSmall)
                } else {
                    WaveformView(style: .assistantLoop, size: .xSmall)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// 윈도우 최소화
    private func minimizeWindow() {
        logger.info("최소화 버튼 탭")
        WindowManager.shared.getWindow(identifier: "listening")?.miniaturize(nil)
    }

    /// 닫기 요청 처리 — 30초 이상이면 확인 다이얼로그
    private func handleCloseRequest() {
        logger.info("닫기 버튼 탭")

        guard viewModel.isListening,
              let startDate = viewModel.listeningStartDate,
              Date().timeIntervalSince(startDate) >= 30.0 else {
            performCancel()
            return
        }

        // 30초 이상 → 확인 다이얼로그
        showCancelConfirmation = true
    }

    /// 리스닝 취소 — Flutter에 알림만 전송, 비즈니스 로직은 Flutter에서 처리
    private func performCancel() {
        logger.info("리스닝 취소 실행")
        viewModel.cleanupListeningState()
        FlutterBridge.shared.invokeListeningEnded(reason: "cancelled")
    }

    /// 리스닝 확인 (완료) — Flutter에 알림만 전송, 비즈니스 로직은 Flutter에서 처리
    private func performConfirm() {
        logger.info("리스닝 확인 실행")
        viewModel.cleanupListeningState()
        FlutterBridge.shared.invokeListeningEnded(reason: "confirmed")
    }
}
