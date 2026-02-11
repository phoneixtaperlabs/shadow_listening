import SwiftUI

struct CustomSwitchToggleStyle: ToggleStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            let trackWidth: CGFloat = 26
            let trackHeight: CGFloat = 16
            let knobSize: CGFloat = 10
            let strokeLineWidth: CGFloat = 1.5
            let extraPadding: CGFloat = 2

            let halfInnerWidth = (trackWidth - strokeLineWidth) / 2
            let baseOffset = halfInnerWidth - (knobSize / 2)
            let effectiveOffset = baseOffset - extraPadding

            ZStack {
                Capsule()
                    .fill(configuration.isOn ? tint : Color.backgroundAppBody)
                    .frame(width: trackWidth, height: trackHeight)

                Capsule()
                    .strokeBorder(Color.borderSoft, lineWidth: strokeLineWidth)
                    .frame(width: trackWidth, height: trackHeight)

                Circle()
                    .fill(Color.borderSoft)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: configuration.isOn ? effectiveOffset : -effectiveOffset)
                    .animation(.spring(), value: configuration.isOn)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

struct InPersonMeetingToggleView: View {
    @Binding var isInPersonMeeting: Bool

    var body: some View {
        HStack {
            Text("Mark as in-person meeting")
                .foregroundColor(.text3)
                .font(.system(size: 13))

            Spacer()
                .frame(maxWidth: 23)

            Toggle("", isOn: $isInPersonMeeting)
                .toggleStyle(CustomSwitchToggleStyle(tint: Color.brandPrimary))
                .labelsHidden()
        }
        .onChange(of: isInPersonMeeting) { _, newValue in
            FlutterBridge.shared.invokeInPersonMeetingChanged(isInPersonMeeting: newValue)
        }
    }
}
