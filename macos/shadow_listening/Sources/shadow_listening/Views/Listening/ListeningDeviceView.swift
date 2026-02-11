import SwiftUI

/// 현재 기본 입력 디바이스를 표시하는 뷰
///
/// 마이크 아이콘과 디바이스 이름을 표시한다.
struct ListeningDeviceView: View {
    @EnvironmentObject var viewModel: ListeningViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(Color.text1)
            Text(viewModel.defaultInputDeviceName)
                .foregroundStyle(Color.text1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
