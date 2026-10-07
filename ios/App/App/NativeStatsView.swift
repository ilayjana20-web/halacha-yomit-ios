import SwiftUI

/// Real native Liquid Glass sheet replacing the HTML #statsOverlay on iOS (see openStats() in
/// www/index.html / make_www.py). Presented via MainContainerViewController.presentStats(_:)
/// in LiquidGlassChrome.swift. Pure display — the numbers themselves are computed in JS
/// (statsNumbersForNative(), the exact same arithmetic renderStats() uses for its HTML rings)
/// and handed in once when the sheet opens; there is nothing here to write back.
///
/// Deliberately shows only the three rings (year 1, year 2, total) — no streak flame box, per
/// the user's own instruction to leave that one as HTML for now.
struct StatsTrack {
    let done: Int
    let total: Int
    var pct: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

struct NativeStatsView: View {
    let year1: StatsTrack
    let year2: StatsTrack
    let grand: StatsTrack
    let onClose: () -> Void

    @State private var animate = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    ProgressRing(label: "סה״כ", track: grand, diameter: 150, lineWidth: 13, animate: animate)
                    HStack(spacing: 20) {
                        ProgressRing(label: "שנה א׳", track: year1, diameter: 100, lineWidth: 9, animate: animate)
                        ProgressRing(label: "שנה ב׳", track: year2, diameter: 100, lineWidth: 9, animate: animate)
                    }
                    if grand.done == 0 {
                        Text("עוד לא סימנת הלכות כנלמדות. כל הלכה שתסמן תופיע כאן.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("ההתקדמות שלי")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור", action: onClose)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            // Starts fully hidden then animates to the real fill on the next runloop tick —
            // same "force a before-state, then animate to the after-state" trick the web
            // version's own ring fill-in uses (see statRing()'s comment in www/index.html).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.6)) { animate = true }
            }
        }
    }
}

private struct ProgressRing: View {
    let label: String
    let track: StatsTrack
    let diameter: CGFloat
    let lineWidth: CGFloat
    let animate: Bool

    private var pctText: String {
        let pct = Int((track.pct * 100).rounded())
        if track.done > 0 && pct == 0 { return "פחות מאחוז" }
        return "\(pct)%"
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: animate ? track.pct : 0)
                    .stroke(
                        Color(red: 0.749, green: 0.584, blue: 0.188),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(track.done)")
                        .font(.system(size: diameter * 0.26, weight: .bold))
                    Text("מתוך \(track.total)")
                        .font(.system(size: diameter * 0.11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: diameter, height: diameter)
            Text(label).font(.subheadline).fontWeight(.semibold)
            Text(pctText).font(.caption).foregroundStyle(.secondary)
        }
    }
}
