import SwiftUI

/// Simple test view for validating WindowManager functionality
struct TestWindowView: View {
    let identifier: String

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Circle()
                    .fill(Color.brandSecondary)
                    .frame(width: 10, height: 10)

                Text("Test Window")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.text1)

                Spacer()
            }

            // Content
            Text("Window ID: \(identifier)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color.text3)

            // Close button
            Button(action: {
                Task { @MainActor in
                    WindowManager.shared.closeWindow(identifier: identifier)
                }
            }) {
                Text("Close Window")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.text1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.brandPrimary)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 240, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundHard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.borderHard, lineWidth: 1)
                )
        )
    }
}

#Preview {
    TestWindowView(identifier: "preview")
}
