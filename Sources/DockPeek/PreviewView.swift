import AppKit
import SwiftUI

@MainActor
final class PreviewModel: ObservableObject {
    @Published var appName = ""
    @Published var appIcon: NSImage?
    @Published var windows: [WindowEntry] = []
    @Published var vertical = false
    @Published var thumbnailMaxSize = CGSize(width: 240, height: 160)
    /// The side the tail points out of (towards the Dock) and where along that side its tip is, measured
    /// from the left (bottom Dock) or the top (side Dock) of the preview.
    @Published var tailEdge: PreviewTail.Edge = .bottom
    @Published var tailPosition: CGFloat?

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
        // Room for the tail on the Dock side.
        .padding(model.tailEdge.paddingEdge, PreviewTail.length)
        .background(
            // Opaque and dark (the panel always uses the dark appearance): the Dock's app-name label under
            // it must not show through.
            PreviewBubble(edge: model.tailEdge, position: model.tailPosition)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .fixedSize()
    }
}

enum PreviewTail {
    /// How far the tail sticks out of the preview, and its width at the base.
    static let length: CGFloat = 8
    static let width: CGFloat = 20

    enum Edge {
        case bottom, left, right

        var paddingEdge: SwiftUI.Edge.Set {
            switch self {
            case .bottom: return .bottom
            case .left: return .leading
            case .right: return .trailing
            }
        }
    }
}

/// Rounded rectangle with a small tail pointing at the Dock icon, like the Dock's own name label.
private struct PreviewBubble: Shape {
    let edge: PreviewTail.Edge
    let position: CGFloat?
    private let radius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let length = PreviewTail.length, half = PreviewTail.width / 2
        var body = rect
        switch edge {
        case .bottom: body.size.height -= length
        case .left: body.origin.x += length; body.size.width -= length
        case .right: body.size.width -= length
        }
        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)

        // Keep the tail clear of the rounded corners.
        func clamped(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            min(max(value, low + radius + half), high - radius - half)
        }
        var tail = Path()
        switch edge {
        case .bottom:
            let x = clamped(position ?? body.midX, body.minX, body.maxX)
            tail.move(to: CGPoint(x: x - half, y: body.maxY - 1))
            tail.addLine(to: CGPoint(x: x, y: rect.maxY))
            tail.addLine(to: CGPoint(x: x + half, y: body.maxY - 1))
        case .left:
            let y = clamped(position ?? body.midY, body.minY, body.maxY)
            tail.move(to: CGPoint(x: body.minX + 1, y: y - half))
            tail.addLine(to: CGPoint(x: rect.minX, y: y))
            tail.addLine(to: CGPoint(x: body.minX + 1, y: y + half))
        case .right:
            let y = clamped(position ?? body.midY, body.minY, body.maxY)
            tail.move(to: CGPoint(x: body.maxX - 1, y: y - half))
            tail.addLine(to: CGPoint(x: rect.maxX, y: y))
            tail.addLine(to: CGPoint(x: body.maxX - 1, y: y + half))
        }
        tail.closeSubpath()
        path.addPath(tail)
        return path
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


/// Hosting view that accepts the first click even though the panel never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
