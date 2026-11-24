import SwiftUI
// FlyHarp's palette, made smutty and velvety: deep plum ground, pink and amber light, cream ink.
enum Theme {
    static let ground = Color(red: 0.07, green: 0.016, blue: 0.047)
    static let velvet = Color(red: 0.16, green: 0.04, blue: 0.11)
    static let pink = Color(red: 1.0, green: 0.41, blue: 0.73)
    static let amber = Color(red: 1.0, green: 0.71, blue: 0.28)
    static let cream = Color(red: 0.95, green: 0.89, blue: 0.83)
    static let muted = Color(red: 0.73, green: 0.59, blue: 0.65)
    static let teal = Color(red: 0.31, green: 0.70, blue: 0.64)
    static func serif(_ s: CGFloat) -> Font { .system(size: s, weight: .regular, design: .serif) }
}
