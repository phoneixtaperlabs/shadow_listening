import CoreAudio
import SwiftUI

/// 단일 디바이스 항목 뷰
struct DeviceItemView: View {
    let device: AudioDevice
    let isSelected: Bool

    var body: some View {
        Text(device.name)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundColor(isSelected ? Color.brandSecondary : Color.text2)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 입력 디바이스 목록을 표시하고 선택할 수 있는 뷰
struct ListeningDeviceListView: View {
    @EnvironmentObject var viewModel: ListeningViewModel
    @State private var selectedDeviceId: AudioDeviceID?

    // 목 데이터
    private static let mockDevices: [AudioDevice] = [
        AudioDevice(id: 9001, name: "Mock USB Microphone"),
        AudioDevice(id: 9002, name: "Mock Bluetooth Headset"),
        AudioDevice(id: 9003, name: "Mock Studio Condenser"),
        AudioDevice(id: 9004, name: "Mock Wireless Mic"),
        AudioDevice(id: 9005, name: "Mock HDMI Audio Input"),
    ]

    private var allDevices: [AudioDevice] {
        viewModel.inputDevices + Self.mockDevices
    }

    var body: some View {
        ScrollView {
            ForEach(viewModel.inputDevices) { device in
                DeviceItemView(
                    device: device,
                    isSelected: device.id == selectedDeviceId
                )
                .onTapGesture {
                    selectedDeviceId = device.id
                    viewModel.setDefaultAudioInputDevice(with: device.name)
                }
                .frame(maxWidth: .infinity, maxHeight: 25, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(CGFloat(viewModel.inputDevices.count) * 25, 100))
        .onChange(of: viewModel.defaultInputDevice) { _, newDeviceID in
            selectedDeviceId = newDeviceID
        }
        .onAppear {
            selectedDeviceId = viewModel.defaultInputDevice
        }
    }
}
