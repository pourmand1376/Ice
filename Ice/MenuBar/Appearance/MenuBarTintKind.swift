//
//  MenuBarTintKind.swift
//  Ice
//

import SwiftUI

/// A type that specifies how the menu bar is tinted.
enum MenuBarTintKind: Int, CaseIterable, Codable, Identifiable {
    /// The menu bar is not tinted.
    case noTint = 0
    /// The menu bar is tinted with a solid color.
    case solid = 1
    /// The menu bar is tinted with a gradient.
    case gradient = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .noTint: "No Tint"
        case .solid: "Solid"
        case .gradient: "Gradient"
        }
    }

    /// A SwiftUI representation of the kind.
    @ViewBuilder
    func swiftUIView(with configuration: MenuBarAppearancePartialConfiguration) -> some View {
        switch self {
        case .noTint:
            EmptyView()
        case .solid:
            Color(cgColor: configuration.tintColor)
        case .gradient:
            configuration.tintGradient.swiftUIView
        }
    }
}
