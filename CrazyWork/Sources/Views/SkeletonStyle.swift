import SwiftUI

/// Overlay color palette, persisted via `@AppStorage` (String-backed).
enum SkeletonColor: String, CaseIterable {
    case green, blue, pink, white, orange

    var color: Color {
        switch self {
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .white: return .white
        case .orange: return .orange
        }
    }

    var label: String { rawValue.capitalized }
}

/// Overlay line/dot thickness, persisted via `@AppStorage` (String-backed).
enum SkeletonThickness: String, CaseIterable {
    case thin, medium, thick

    var lineWidth: CGFloat {
        switch self {
        case .thin: return 2
        case .medium: return 3
        case .thick: return 5
        }
    }

    var dotRadius: CGFloat {
        switch self {
        case .thin: return 3
        case .medium: return 4
        case .thick: return 6
        }
    }

    var label: String { rawValue.capitalized }
}

/// A one-tap overlay look. Applying a preset writes the four `@AppStorage` keys.
struct OverlayPreset: Identifiable {
    let id: String          // also the display name
    let color: SkeletonColor
    let thickness: SkeletonThickness
    let showJoints: Bool
    let showSkeleton: Bool

    static let all: [OverlayPreset] = [
        OverlayPreset(id: "Classic", color: .green, thickness: .medium, showJoints: true,  showSkeleton: true),
        OverlayPreset(id: "Neon",    color: .pink,  thickness: .thick,  showJoints: true,  showSkeleton: true),
        OverlayPreset(id: "Minimal", color: .white, thickness: .thin,   showJoints: false, showSkeleton: true),
        OverlayPreset(id: "Hidden",  color: .green, thickness: .medium, showJoints: true,  showSkeleton: false),
    ]
}
