import SwiftUI

/// 디바이스 관리 테스트용 컨테이너 뷰
///
/// @StateObject로 ViewModel을 소유하여 윈도우 닫힘 시 전체 체인 해제를 보장한다.
/// WindowManager → NSHostingView → 이 뷰 → @StateObject ViewModel → CoreAudioService
struct ListeningDeviceTestView: View {
    // @StateObject — 이 View가 ViewModel의 유일한 소유자
    // View 파괴 시 ViewModel.deinit → CoreAudioService.stopMonitoring() → 리스너 해제
    @StateObject private var viewModel = ListeningViewModel()
    @State private var isControlBarExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CaptureTargetListView()

            Divider()

            CaptureTargetView()

            Divider()

            ListeningDeviceListView()

            Divider()

            ListeningDeviceView()

            Divider()

            // 컨트롤 바 (임시 배치 — ListeningView 생성 시 이동 예정)
            HStack {
                Spacer()
                ListeningControlBar(isExpanded: $isControlBarExpanded)
                Spacer()
            }

            // 카운트다운 시작 테스트 버튼 (디버그용)
            if viewModel.listeningState == .idle {
                Button("Start Countdown") {
                    viewModel.startCountdownRecording()
                }
                .buttonStyle(.plain)
                .foregroundColor(Color.brandSecondary)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .environmentObject(viewModel)
        .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundHard)
                .stroke(Color.borderHard, lineWidth: 1)
        )
        .onAppear {
            viewModel.startDeviceMonitoring()
        }
        .onDisappear {
            viewModel.stopDeviceMonitoring()
        }
    }
}
