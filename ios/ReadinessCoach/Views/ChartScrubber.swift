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

/// Pins vertical ScrollView content width. Does NOT walk up and clamp ancestor
/// scrollers — that was killing the section-pager swipe gesture.
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

enum ScrollLockBootstrap {
    static func apply() {
        // Leave horizontal paging alone so section swipe works.
        UIScrollView.appearance().isDirectionalLockEnabled = true
    }
}

enum ChartStyle {
    static let smooth: InterpolationMethod = .catmullRom
}
