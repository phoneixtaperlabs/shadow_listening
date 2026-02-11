import SwiftUI

/// 현재 선택된 캡처 타겟을 표시하는 뷰
///
/// 아이콘 + 타겟 이름. `ListeningDeviceView`와 동일 패턴.
struct CaptureTargetView: View {
    @EnvironmentObject var viewModel: ListeningViewModel

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let appIcon = viewModel.selectedCaptureTarget?.appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: viewModel.selectedCaptureTarget?.iconSystemName ?? "xmark.circle")
                        .foregroundStyle(Color.text1)
                        .frame(width: 16, height: 16)
                }
            }
            Text(viewModel.selectedCaptureTarget?.name ?? "No capture")
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.text1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
