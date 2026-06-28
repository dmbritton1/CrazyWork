import SwiftUI
import UIKit

enum InterTier { case body, display }

enum Typography {
    struct Token {
        let size: CGFloat
        let weight: UIFont.Weight
        let leading: CGFloat
        let tracking: CGFloat
        let tier: InterTier
    }

    static let displayXl    = Token(size: 64, weight: .semibold, leading: 1.1,  tracking: 0,   tier: .display)
    static let displayLg    = Token(size: 56, weight: .medium,   leading: 1.17, tracking: 0.2, tier: .display)
    static let headingXl    = Token(size: 24, weight: .medium,   leading: 1.6,  tracking: 0.2, tier: .body)
    static let headingLg    = Token(size: 22, weight: .medium,   leading: 1.15, tracking: 0,   tier: .body)
    static let headingMd    = Token(size: 20, weight: .medium,   leading: 1.4,  tracking: 0.2, tier: .body)
    static let headingSm    = Token(size: 18, weight: .medium,   leading: 1.4,  tracking: 0.2, tier: .body)
    static let bodyLg       = Token(size: 18, weight: .regular,  leading: 1.6,  tracking: 0,   tier: .body)
    static let bodyMd       = Token(size: 16, weight: .regular,  leading: 1.6,  tracking: 0,   tier: .body)
    static let bodyStrong   = Token(size: 16, weight: .medium,   leading: 1.4,  tracking: 0.2, tier: .body)
    static let bodySm       = Token(size: 14, weight: .regular,  leading: 1.6,  tracking: 0,   tier: .body)
    static let bodySmStrong = Token(size: 14, weight: .medium,   leading: 1.6,  tracking: 0.2, tier: .body)
    static let captionMd    = Token(size: 13, weight: .regular,  leading: 1.4,  tracking: 0.1, tier: .body)
    static let captionSm    = Token(size: 12, weight: .regular,  leading: 1.5,  tracking: 0.4, tier: .body)
    static let linkMd       = Token(size: 16, weight: .medium,   leading: 1.4,  tracking: 0.3, tier: .body)
    static let buttonMd     = Token(size: 14, weight: .medium,   leading: 1.6,  tracking: 0.2, tier: .body)

    static func uiFont(size: CGFloat, weight: UIFont.Weight, tier: InterTier) -> UIFont {
        let name: String
        switch weight {
        case .semibold, .bold: name = "Inter-SemiBold"
        case .medium:          name = "Inter-Medium"
        default:               name = "Inter-Regular"
        }
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        var feats: [[UIFontDescriptor.FeatureKey: Int]] = [
            [.type: kStylisticAlternativesType, .selector: 6] // ss03
        ]
        if tier == .display {
            feats.append([.type: kStylisticAlternativesType, .selector: 4])  // ss02
            feats.append([.type: kStylisticAlternativesType, .selector: 16]) // ss08
            feats.append([.type: kLigaturesType, .selector: kCommonLigaturesOffSelector])
        }
        let desc = base.fontDescriptor.addingAttributes([.featureSettings: feats])
        return UIFont(descriptor: desc, size: size)
    }

    static func font(_ t: Token) -> Font { Font(uiFont(size: t.size, weight: t.weight, tier: t.tier)) }
}

struct TypographyStyle: ViewModifier {
    let t: Typography.Token
    func body(content: Content) -> some View {
        content
            .font(Typography.font(t))
            .tracking(t.tracking)
            .lineSpacing(t.size * (t.leading - 1))
    }
}

extension View {
    func typography(_ t: Typography.Token) -> some View { modifier(TypographyStyle(t: t)) }
}
