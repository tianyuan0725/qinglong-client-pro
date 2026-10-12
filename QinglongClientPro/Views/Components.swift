import SwiftUI

/// Full-screen busy overlay used while a mutation is in flight.
struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            ProgressView()
                .padding(22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// Small colored status/category pill.
struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Auto-dismissing toast for transient operation errors.
struct ErrorToastModifier: ViewModifier {
    @Binding var error: String?
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if visible, let msg = error {
                    Text(msg)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.red)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }
            }
            .onChange(of: error) { _ in
                if error != nil {
                    withAnimation { visible = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { visible = false }
                        error = nil
                    }
                }
            }
    }
}

extension View {
    func errorToast(_ error: Binding<String?>) -> some View {
        modifier(ErrorToastModifier(error: error))
    }
}

/// Truncates a long secret value to dots unless revealed.
func masked(_ value: String, revealed: Bool) -> String {
    if revealed { return value }
    if value.isEmpty { return "（空）" }
    let head = value.prefix(3)
    let tail = value.suffix(3)
    return "\(head)••••••\(tail)"
}
