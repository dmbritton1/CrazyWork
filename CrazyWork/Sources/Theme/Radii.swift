import CoreGraphics

/// Border-radius scale (DESIGN.md). Clusters 4–16px; `full` is a pill.
enum Radii {
    static let none: CGFloat = 0
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 16
    static let full: CGFloat = 9999
}
