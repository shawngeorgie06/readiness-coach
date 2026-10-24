import SwiftUI
import UIKit
import Charts

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

/// Parent-owned selection keeps its source zone even while the chart is absent.
struct ChartDaySelection {
    private var storedDate: Date?
    private var sourceTimeZone: TimeZone

    init(date: Date? = nil, timeZone: TimeZone = .current) {
        storedDate = date
        sourceTimeZone = timeZone
    }

    var date: Date? {
        get { resolved() }
        set {
            storedDate = newValue
            sourceTimeZone = .current
        }
    }

    func resolved(timeZone: TimeZone = .current) -> Date? {
        ChartDate.rebase(storedDate, from: sourceTimeZone, to: timeZone)
    }
}

struct ChartDayScrubOverlay: View {
    let proxy: ChartProxy
    let dates: [Date]
    @Binding var selection: Date?

    var body: some View {
        DayScrubRecognizer { select(at: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            // The parent binding resolves the same day in the new zone; writing it
            // back updates parent state so marks and readouts redraw together.
            let resolvedSelection = selection
            selection = resolvedSelection
        }
    }

    private func select(at x: CGFloat) {
        guard let raw: Date = proxy.value(atX: x),
              let snapped = nearestDate(raw, in: dates),
              snapped != selection
        else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { selection = snapped }
    }
}

/// Tap, touch and hold, or a sideways drag picks a day; a vertical drag
/// belongs to the page. These are UIKit recognizers because a SwiftUI
/// gesture on scroll content keeps the touch from the enclosing scroll view,
/// whatever its priority or composition.
struct DayScrubRecognizer: UIViewRepresentable {
    let onSelect: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onSelect = onSelect
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSelect: (CGFloat) -> Void
        let tap = UITapGestureRecognizer()
        let hold = UILongPressGestureRecognizer()
        let pan = UIPanGestureRecognizer()

        init(onSelect: @escaping (CGFloat) -> Void) {
            self.onSelect = onSelect
            super.init()
            hold.minimumPressDuration = 0.25
            for recognizer in [tap, hold, pan] as [UIGestureRecognizer] {
                recognizer.addTarget(self, action: #selector(handle(_:)))
                recognizer.delegate = self
            }
        }

        func install(on view: UIView) {
            for recognizer in [tap, hold, pan] as [UIGestureRecognizer] { view.addGestureRecognizer(recognizer) }
        }

        @objc private func handle(_ recognizer: UIGestureRecognizer) {
            // A hold marks its day once; moving afterwards is the pan's or the page's.
            let active: Bool = switch recognizer.state {
            case .began: true
            case .changed: recognizer !== hold
            case .ended: recognizer === tap
            default: false
            }
            if active { onSelect(recognizer.location(in: recognizer.view).x) }
        }

        /// The pan starts only for a mostly sideways movement.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard recognizer === pan else { return true }
            let translation = pan.translation(in: pan.view)
            let movement = translation == .zero ? pan.velocity(in: pan.view) : translation
            return ScrubIntent.isSideways(movement)
        }

        /// The hold never takes the touch away from the page or the pan.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            recognizer === hold || other === hold
        }

        /// The page's scroll waits for the pan to decline, so a vertical drag
        /// still scrolls and a sideways one scrubs without moving the page.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            recognizer === pan && other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

enum ScrubIntent {
    static func isSideways(_ movement: CGPoint) -> Bool {
        abs(movement.x) > abs(movement.y)
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

enum ChartStyle {
    static let smooth: InterpolationMethod = .catmullRom
}
