import Charts
import SwiftUI

/// Usage statistics from the stats ledger — they survive deleting recordings.
struct InsightsView: View {
    @ObservedObject private var analytics = AnalyticsStore.shared
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                HStack(alignment: .top, spacing: 14) {
                    TimeSavedHero(snapshot: analytics.snapshot, rangeSaved: analytics.summary.estimatedTimeSaved, range: analytics.range)
                        .frame(maxWidth: .infinity)
                    totalTile("mic", "Recordings", analytics.snapshot.totalRecordings.formatted(), nil,
                              "\(analytics.snapshot.todayRecordings) today")
                    totalTile("textformat", "Words", analytics.snapshot.totalWords.formatted(), nil,
                              "\(analytics.snapshot.todayWords.formatted()) today")
                    totalTile("timer", "Recorded", DurationText.minutes(analytics.snapshot.totalDuration), "min",
                              "\(DurationText.minutes(analytics.snapshot.todayDuration)) min today")
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 14) {
                    ActivityCard(analytics: analytics)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 14) {
                        AppShareCard(shares: analytics.appShares, streak: analytics.currentStreak, best: analytics.bestStreak)
                        PaceCard(snapshot: analytics.snapshot, speedup: analytics.speedupOverTyping)
                    }
                    .frame(width: 300)
                }
            }
            .padding(24)
        }
        .onAppear { analytics.refresh() }
        .sheet(isPresented: $confirmReset) {
            ConfirmDialog(
                icon: "chart.bar.xaxis",
                tint: DL.warn,
                title: "Reset all statistics?",
                message: "Totals and the activity graph go back to zero. Your recordings and transcripts are not affected.",
                confirmTitle: "Reset Statistics",
                onCancel: { confirmReset = false },
                onConfirm: {
                    analytics.resetStatistics()
                    confirmReset = false
                }
            )
            .daylight()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Insights").font(DL.display(28)).foregroundStyle(DL.ink)
                Text("Kept even when you delete recordings · typing estimate \(Int(AnalyticsSnapshot.typingWordsPerMinute)) wpm")
                    .font(DL.text(12.5))
                    .foregroundStyle(DL.faint)
            }
            Spacer()
            DLSegmented(selection: $analytics.range, options: AnalyticsRange.allCases.map { ($0, $0.label) })
            Button {
                analytics.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.dlIcon(size: 30))
            .help("Refresh analytics")
            Button {
                confirmReset = true
            } label: {
                Label("Reset statistics…", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.dlDangerSoft)
            .labelStyle(CompactLabelStyle())
            .help("Reset statistics")
        }
    }

    private func totalTile(_ icon: String, _ label: String, _ value: String, _ unit: String?, _ detail: String) -> some View {
        StatTile(icon: icon, label: label, value: value, unit: unit, detail: detail)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hero

private struct TimeSavedHero: View {
    let snapshot: AnalyticsSnapshot
    let rangeSaved: TimeInterval
    let range: AnalyticsRange
    @Environment(\.dlAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").font(.system(size: 11))
                Text("Time saved, all time").font(DL.text(12, .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            Text(DurationText.long(snapshot.estimatedTimeSaved))
                .font(DL.display(32, .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(DurationText.long(snapshot.todayEstimatedTimeSaved)) today · \(DurationText.long(rangeSaved)) in the last \(range.days) days")
                .font(DL.text(11.5))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accent.gradient)
                Circle().fill(.white.opacity(0.08)).frame(width: 180).offset(x: 50, y: -40)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .shadow(color: accent.color.opacity(0.3), radius: 12, y: 5)
    }
}

// MARK: - Activity

private struct ActivityCard: View {
    @ObservedObject var analytics: AnalyticsStore
    @Environment(\.dlAccent) private var accent

    var body: some View {
        let summary = analytics.summary
        let series = analytics.series
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Words per day").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                Spacer()
                Text("Today ").font(DL.text(12)).foregroundStyle(DL.faint)
                    + Text(analytics.snapshot.todayWords.formatted()).font(DL.mono(12, .semibold)).foregroundStyle(accent.color)
            }
            HStack(spacing: 26) {
                summaryItem("Words", summary.words.formatted())
                summaryItem("Recordings", summary.recordings.formatted())
                summaryItem("Time saved", DurationText.long(summary.estimatedTimeSaved))
                summaryItem("Active days", "\(summary.activeDays)/\(analytics.range.days)")
            }
            if series.allSatisfy({ $0.words == 0 }) {
                Text("No activity in this range yet")
                    .font(DL.text(13))
                    .foregroundStyle(DL.faint)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(RoundedRectangle(cornerRadius: 12).fill(DL.well.opacity(0.6)))
            } else {
                Chart(series) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Words", day.words)
                    )
                    .foregroundStyle(Calendar.current.isDateInToday(day.date) ? accent.color : accent.color.opacity(0.3))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: axisStride)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(DL.mono(9.5, .regular))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(DL.line)
                        AxisValueLabel().font(DL.mono(9.5, .regular))
                    }
                }
                .frame(minHeight: 240)
            }
        }
        .padding(18)
        .dlCard(radius: 16)
    }

    private var axisStride: Int {
        switch analytics.range {
        case .week: return 1
        case .month: return 7
        case .quarter: return 15
        }
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(DL.text(11.5)).foregroundStyle(DL.faint)
            Text(value).font(DL.display(16, .bold)).foregroundStyle(DL.ink)
        }
    }
}

// MARK: - Side cards

private struct AppShareCard: View {
    let shares: [(name: String, share: Double)]
    let streak: Int
    let best: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where you dictate").font(DL.text(14, .semibold)).foregroundStyle(DL.ink)
            if shares.isEmpty {
                Text("Dictate into an app and it shows up here.")
                    .font(DL.text(12)).foregroundStyle(DL.faint)
            } else {
                ForEach(shares, id: \.name) { item in
                    HStack(spacing: 10) {
                        Circle().fill(color(for: item.name)).frame(width: 7, height: 7)
                        Text(item.name).font(DL.text(12.5)).foregroundStyle(DL.ink2).frame(width: 72, alignment: .leading).lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DL.well)
                                Capsule().fill(color(for: item.name)).frame(width: max(4, geo.size.width * item.share))
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int((item.share * 100).rounded()))%")
                            .font(DL.mono(10.5, .medium)).foregroundStyle(DL.faint)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            DLDivider()
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(DL.star)
                Text(streak == 1 ? "1-day streak" : "\(streak)-day streak").font(DL.text(12.5, .semibold)).foregroundStyle(DL.ink)
                Text("· best \(best) day\(best == 1 ? "" : "s")").font(DL.text(12)).foregroundStyle(DL.faint)
            }
        }
        .padding(16)
        .dlCard(radius: 16)
    }

    private func color(for name: String) -> Color {
        name == "Other" ? DL.faint : AppColors.color(for: name)
    }
}

private struct PaceCard: View {
    let snapshot: AnalyticsSnapshot
    let speedup: Double

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your pace").font(DL.text(11.5)).foregroundStyle(DL.faint)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", snapshot.averageWordsPerMinute)).font(DL.display(22)).foregroundStyle(DL.ink)
                    Text("wpm").font(DL.text(11.5)).foregroundStyle(DL.faint)
                }
                if speedup > 0 {
                    Text(String(format: "%.1f× faster than typing", speedup))
                        .font(DL.text(11.5, .semibold)).foregroundStyle(DL.ok)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("Avg. per recording").font(DL.text(11.5)).foregroundStyle(DL.faint)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", snapshot.averageWordsPerRecording)).font(DL.display(22)).foregroundStyle(DL.ink)
                    Text("words").font(DL.text(11.5)).foregroundStyle(DL.faint)
                }
                if snapshot.totalRecordings > 0 {
                    Text("about \(Int((snapshot.totalDuration / Double(snapshot.totalRecordings)).rounded())) s of speech")
                        .font(DL.text(11.5)).foregroundStyle(DL.sub)
                }
            }
        }
        .padding(16)
        .dlCard(radius: 16)
    }
}
