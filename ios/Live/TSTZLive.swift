import WidgetKit
import SwiftUI
import ActivityKit

struct Countdown: View {
    let end: Date
    var body: some View {
        let s = Date.now
        Text(timerInterval: s...max(end, s.addingTimeInterval(1)), countsDown: true)
            .monospacedDigit()
    }
}

struct TSTZLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BotActivityAttributes.self) { ctx in
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.state.title).font(.headline)
                    Text(ctx.state.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let e = ctx.state.end {
                    Countdown(end: e).font(.title2.bold()).frame(width: 96, alignment: .trailing)
                }
            }
            .padding(16)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles").font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let e = ctx.state.end {
                        Countdown(end: e).font(.title3.bold()).frame(width: 84, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ctx.state.title).font(.headline)
                        Text(ctx.state.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                if let e = ctx.state.end {
                    Countdown(end: e).frame(width: 52)
                } else {
                    Image(systemName: "ellipsis")
                }
            } minimal: {
                Image(systemName: "sparkles")
            }
        }
    }
}

@main
struct TSTZLiveBundle: WidgetBundle {
    var body: some Widget { TSTZLiveActivity() }
}
