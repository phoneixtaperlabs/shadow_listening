import SwiftUI

/// 단일 캡처 타겟 항목 뷰
struct CaptureTargetItemView: View {
    let target: CaptureTarget
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let appIcon = target.appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: target.iconSystemName)
                        .foregroundColor(isSelected ? .brandSecondary : .text2)
                        .frame(width: 16, height: 16)
                }
            }
            Text(target.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isSelected ? .brandSecondary : .text2)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 캡처 타겟 목록을 표시하고 선택할 수 있는 뷰
///
/// `ListeningDeviceListView`와 동일 패턴: ScrollView + ForEach + onTap 선택.
struct CaptureTargetListView: View {
    @EnvironmentObject var viewModel: ListeningViewModel
    @State private var selectedTargetId: String?

    var body: some View {
        ScrollView {
            ForEach(viewModel.captureTargets) { target in
                CaptureTargetItemView(
                    target: target,
                    isSelected: target.id == selectedTargetId
                )
                .onTapGesture {
                    selectedTargetId = target.id
                    viewModel.selectCaptureTarget(target)
                }
                .frame(maxWidth: .infinity, maxHeight: 25, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(CGFloat(viewModel.captureTargets.count) * 25, 120))
        .onChange(of: viewModel.selectedCaptureTarget) { _, newTarget in
            selectedTargetId = newTarget?.id
        }
        .onAppear {
            selectedTargetId = viewModel.selectedCaptureTarget?.id
            Task { await viewModel.fetchCaptureTargets() }
        }
    }
}
