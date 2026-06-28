import SwiftUI

struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).typography(Typography.captionMd).foregroundStyle(Palette.body)
            .padding(.vertical, 1).padding(.horizontal, Spacing.sm).frame(minHeight: 20)
            .background(LinearGradient(colors: [Palette.keyBgStart, Palette.keyBgEnd],
                                       startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: Radii.xs).stroke(Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radii.xs))
    }
}
