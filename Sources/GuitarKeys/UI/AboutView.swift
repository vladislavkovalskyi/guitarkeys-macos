import SwiftUI
/// О программе: кто автор и где его найти.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @UIState private var appeared = false

    private let github = URL(string: "https://github.com/vladislavkovalskyi")!
    private let telegram = URL(string: "https://t.me/yxuxo")!
    private let repository = URL(string: "https://github.com/vladislavkovalskyi/guitarkeys-macos")!

    private var version: String {
        let bundle = Bundle.main.infoDictionary
        return (bundle?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            links
        }
        .frame(width: 340)
        .background {
            AmbientBackground(root: 9, energy: appeared ? 0.4 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { appeared = true }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "guitars.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.5), radius: appeared ? 18 : 0)
                .scaleEffect(appeared ? 1 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: appeared)

            Text("GuitarKeys")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(L.t("about.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(L.t("about.version", version))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)

            Text(L.t("about.madeWith"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.easeOut(duration: 0.45), value: appeared)
    }

    private var links: some View {
        VStack(spacing: 8) {
            row(title: L.t("about.author"), value: "Vladislav Kovalskyi", symbol: "person.fill", url: nil)
            row(title: L.t("about.github"), value: "@vladislavkovalskyi",
                symbol: "chevron.left.forwardslash.chevron.right", url: github)
            row(title: L.t("about.telegram"), value: "@yxuxo", symbol: "paperplane.fill", url: telegram)

            Button {
                openLink(repository)
            } label: {
                Text("guitarkeys-macos")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.glass)
            .padding(.top, 4)
        }
        .padding(20)
    }

    private func row(title: String, value: String, symbol: String, url: URL?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(url == nil ? .primary : Theme.accent)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
        .onTapGesture {
            if let url { openLink(url) }
        }
        .help(url?.absoluteString ?? "")
    }

    private func openLink(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
