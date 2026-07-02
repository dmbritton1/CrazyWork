import SwiftUI
import Charts

/// A titled card for Swift Charts with the system's axis chrome: hairline
/// grid lines and quiet ash value labels. All trend/summary charts route
/// through this so every chart in the app carries the same voice.
struct ChartCard<Content: View>: View {
    let title: String
    var height: CGFloat = 160
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title).typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
            content
                .frame(height: height)
                .chartXAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(Palette.hairline)
                        AxisValueLabel()
                            .foregroundStyle(Palette.ash)
                            .font(Typography.font(Typography.captionSm))
                    }
                }
                .chartYAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(Palette.hairline)
                        AxisValueLabel()
                            .foregroundStyle(Palette.ash)
                            .font(Typography.font(Typography.captionSm))
                    }
                }
        }
        .card()
    }
}

/// The vertical wash under a trend line — the strand's color dissolving into
/// the canvas, echoing how the hero band's strands fade out.
extension LinearGradient {
    static func trendFill(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)],
                       startPoint: .top, endPoint: .bottom)
    }
}
