import SwiftUI
import Charts
import UIKit

func nearestDate(_ target: Date?, in dates: [Date]) -> Date? {
    guard let target else { return nil }
    return dates.min(by: {
        abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target))
    })
}

struct ScrubReadout: View {
    let date: Date
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(date, format: .dateTime.month().day())
                .font(.caption2.weight(.semibold))
            ForEach(lines, id: \.self) { Text($0).font(.caption2) }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct ScrubDetailBanner: View {
    let date: Date?
    let placeholder: String
    let lines: [String]
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date {
                Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                }
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 4)
    }
}

struct ChartDayScrubOverlay: View {
    let proxy: ChartProxy
    let dates: [Date]
    @Binding var selection: Date?

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let raw: Date = proxy.value(atX: value.location.x),
                                  let snapped = nearestDate(raw, in: dates)
                            else { return }
                            if snapped != selection {
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) { selection = snapped }
                            }
                        }
                )
        }
    }
}

extension View {
    func verticalScrollLocked() -> some View {
        self
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .clipped()
    }

    func pageWidthLocked() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}

/// Vertical-only page scroll. Pins content width to the viewport so Charts / wide
/// layouts can’t grow `contentSize` and let the page rubber-band left/right.
struct VerticalPageScroll<Content: View>: View {
    var onRefresh: (() async -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scroll = ScrollView(.vertical, showsIndicators: true) {
                content
                    .frame(width: geo.size.width, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(HorizontalScrollKiller())

            if let onRefresh {
                scroll.refreshable { await onRefresh() }
            } else {
                scroll
            }
        }
    }
}

/// Walks up to the hosting UIScrollView and keeps contentSize.width == bounds.width.
private struct HorizontalScrollKiller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            Self.lock(from: uiView)
        }
    }

    private static func lock(from view: UIView) {
        var node: UIView? = view
        while let current = node {
            if let scroll = current as? UIScrollView {
                scroll.alwaysBounceHorizontal = false
                scroll.isDirectionalLockEnabled = true
                scroll.showsHorizontalScrollIndicator = false
                if scroll.contentSize.width > scroll.bounds.width, scroll.bounds.width > 0 {
                    scroll.contentSize.width = scroll.bounds.width
                }
                return
            }
            node = current.superview
        }
    }
}

enum ScrollLockBootstrap {
    static func apply() {
        UIScrollView.appearance().alwaysBounceHorizontal = false
        UIScrollView.appearance().isDirectionalLockEnabled = true
    }
}

enum ChartStyle {
    static let smooth: InterpolationMethod = .catmullRom
}
