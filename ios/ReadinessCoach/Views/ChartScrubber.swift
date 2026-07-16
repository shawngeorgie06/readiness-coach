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

    /// Pins a continuous UIKit clamp that zeros horizontal offset and content width.
    func killHorizontalScroll() -> some View {
        self.background(HorizontalScrollKiller())
    }
}

/// Vertical ScrollView whose content is forced to the viewport width so children
/// cannot grow `contentSize` sideways. Used by Today (unique wide chrome/shadows).
struct WidthPinnedVerticalScroll<Content: View>: View {
    var onRefresh: (() async -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scroll = ScrollView(.vertical, showsIndicators: true) {
                content
                    .frame(width: geo.size.width, alignment: .topLeading)
                    .clipped()
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .killHorizontalScroll()

            Group {
                if let onRefresh {
                    scroll.refreshable { await onRefresh() }
                } else {
                    scroll
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Continuously clamps every ancestor UIScrollView: no horizontal bounce, content
/// width == bounds width, contentOffset.x == 0. Survives SwiftUI re-layouts that
/// briefly re-widen contentSize (shadows / GeometryReader / refreshable).
struct HorizontalScrollKiller: UIViewRepresentable {
    func makeUIView(context: Context) -> ClampHostView {
        ClampHostView()
    }

    func updateUIView(_ uiView: ClampHostView, context: Context) {
        uiView.clampNow()
    }
}

final class ClampHostView: UIView {
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            clampNow()
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clampNow()
    }

    @objc private func tick() { clampNow() }

    func clampNow() {
        var node: UIView? = self
        while let current = node {
            if let scroll = current as? UIScrollView {
                Self.lock(scroll)
            }
            node = current.superview
        }
    }

    private static func lock(_ scroll: UIScrollView) {
        // Never clamp the section pager (multi-page horizontal) or UIKit paging scrollers.
        if scroll.isPagingEnabled { return }
        if scroll.contentSize.width >= max(scroll.bounds.width, 1) * 1.8 { return }
        // Nested intentional horizontal chip/carousels keep their own width.
        if scroll.contentSize.width > scroll.bounds.width + 1,
           abs(scroll.contentSize.height - scroll.bounds.height) < 1 {
            return
        }
        scroll.alwaysBounceHorizontal = false
        scroll.isDirectionalLockEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        let width = scroll.bounds.width
        guard width > 0 else { return }
        if scroll.contentSize.width > width + 0.5 {
            scroll.contentSize.width = width
        }
        if abs(scroll.contentOffset.x) > 0.05 {
            scroll.contentOffset.x = 0
        }
    }
}

enum ScrollLockBootstrap {
    static func apply() {
        // Directional lock only — do NOT zero alwaysBounceHorizontal globally;
        // that breaks the page-style TabView used to swipe between sections.
        UIScrollView.appearance().isDirectionalLockEnabled = true
    }
}

enum ChartStyle {
    static let smooth: InterpolationMethod = .catmullRom
}
