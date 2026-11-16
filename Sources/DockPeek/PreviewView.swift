import AppKit
import SwiftUI

@MainActor
final class PreviewModel: ObservableObject {
    @Published var appName = ""
    @Published var appIcon: NSImage?
    @Published var windows: [WindowEntry] = []
    @Published var vertical = false
    @Published var thumbnailMaxSize = CGSize(width: 240, height: 160)

    var onSelect: ((WindowEntry) -> Void)?
    var onClose: ((WindowEntry) -> Void)?
}

struct PreviewView: View {
    @ObservedObject var model: PreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = model.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(model.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)

            let layout = model.vertical
                ? AnyLayout(VStackLayout(spacing: 4))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 4))
            layout {
                ForEach(model.windows) { entry in
                    WindowCard(
                        entry: entry,
                        maxSize: model.thumbnailMaxSize,
                        placeholder: model.appIcon,
                        onSelect: { model.onSelect?(entry) },
                        onClose: { model.onClose?(entry) }
                    )
                }
            }
        }
        .padding(10)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
    }
}

private struct WindowCard: View {
    let entry: WindowEntry
    let maxSize: CGSize
    let placeholder: NSImage?
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    private var thumbSize: CGSize {
        let ratio = min(maxSize.width / max(entry.size.width, 1), maxSize.height / max(entry.size.height, 1))
        return CGSize(width: max(entry.size.width * ratio, 80), height: max(entry.size.height * ratio, 50))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)

                if hovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Close Window")
                    .padding(4)
                }
            }

            HStack(spacing: 4) {
                if entry.isMinimized {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 10))
                        .help("Minimized or hidden")
                }
                Text(entry.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: thumbSize.width)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? Color.accentColor.opacity(0.35) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = entry.thumbnail {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                Color.primary.opacity(0.08)
                if let placeholder {
                    Image(nsImage: placeholder).resizable().frame(width: 40, height: 40).opacity(0.7)
                }
            }
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Hosting view that accepts the first click even though the panel never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
