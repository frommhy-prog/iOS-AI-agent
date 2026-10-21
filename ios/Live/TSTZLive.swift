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
            // 锁屏与通知中心的实时活动：深海蓝底，左边品牌标志，右边金色倒计时
            HStack(spacing: 12) {
                BrandMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(ctx.state.subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let e = ctx.state.end {
                    Countdown(end: e)
                        .font(.title2.bold())
                        .foregroundStyle(BrandPalette.gold)
                        .frame(width: 96, alignment: .trailing)
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.04, green: 0.09, blue: 0.22))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BrandMark(size: 38)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let e = ctx.state.end {
                        Countdown(end: e)
                            .font(.title3.bold())
                            .foregroundStyle(BrandPalette.gold)
                            .frame(width: 84, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ctx.state.title).font(.headline).lineLimit(1)
                        Text(ctx.state.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                BrandGlyph(size: 22)
            } compactTrailing: {
                if let e = ctx.state.end {
                    Countdown(end: e).foregroundStyle(BrandPalette.gold).frame(width: 52)
                } else {
                    Image(systemName: "ellipsis").foregroundStyle(BrandPalette.gold)
                }
            } minimal: {
                BrandGlyph(size: 20)
            }
            .keylineTint(BrandPalette.gold)
        }
    }
}

@main
struct TSTZLiveBundle: WidgetBundle {
    var body: some Widget { TSTZLiveActivity() }
}
