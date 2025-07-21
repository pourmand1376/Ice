//
//  CustomGradient.swift
//  Ice
//

import SwiftUI

// MARK: - CustomGradient

/// A custom gradient for use with an ``IceGradientPicker``.
struct CustomGradient: Codable, Hashable {
    /// The color stops in the gradient.
    var stops: [ColorStop]

    /// A Cocoa representation of the gradient.
    var nsGradient: NSGradient? {
        var colors = [NSColor]()
        var locations = [CGFloat]()
        for stop in stops {
            guard let color = NSColor(cgColor: stop.color) else {
                continue
            }
            colors.append(color)
            locations.append(stop.location)
        }
        return NSGradient(colors: colors, atLocations: &locations, colorSpace: .sRGB)
    }

    /// A SwiftUI representation of the gradient.
    var swiftUIView: some View {
        GeometryReader { geometry in
            if stops.isEmpty {
                Color.clear
            } else {
                Image(nsImage: NSImage(size: geometry.size, flipped: false) { bounds in
                    guard let nsGradient else {
                        return false
                    }
                    nsGradient.draw(in: bounds, angle: 0)
                    return true
                })
            }
        }
    }

    /// Creates a gradient with the given array of color stops.
    ///
    /// - Parameter stops: An array of color stops.
    init(stops: [ColorStop] = []) {
        self.stops = stops
    }

    /// Returns the color at the given location in the gradient.
    ///
    /// - Parameter location: A value between 0 and 1 representing
    ///   the location of the color that should be returned.
    func color(at location: CGFloat) -> CGColor? {
        guard
            let nsColor = nsGradient?.interpolatedColor(atLocation: location),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        return nsColor.cgColor.converted(to: colorSpace, intent: .defaultIntent, options: nil)
    }

    /// Returns a copy of the gradient with the given alpha value.
    func withAlphaComponent(_ alpha: CGFloat) -> CustomGradient {
        var copy = self
        copy.stops = copy.stops.map { stop in
            stop.withAlphaComponent(alpha) ?? stop
        }
        return copy
    }
}

extension CustomGradient {
    /// The default menu bar tint gradient.
    static let defaultMenuBarTint = CustomGradient(stops: [
        ColorStop(
            color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            location: 0
        ),
        ColorStop(
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
            location: 1
        ),
    ])
}

// MARK: - ColorStop

/// A color stop in a gradient.
struct ColorStop: Hashable {
    /// The color of the stop.
    var color: CGColor
    /// The location of the stop relative to its gradient.
    var location: CGFloat

    /// Returns a copy of the color stop with the given alpha value.
    func withAlphaComponent(_ alpha: CGFloat) -> ColorStop? {
        guard let newColor = color.copy(alpha: alpha) else {
            return nil
        }
        return ColorStop(color: newColor, location: location)
    }
}

extension ColorStop: Codable {
    private enum CodingKeys: CodingKey {
        case color
        case location
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.color = try container.decode(CodableColor.self, forKey: .color).cgColor
        self.location = try container.decode(CGFloat.self, forKey: .location)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CodableColor(cgColor: color), forKey: .color)
        try container.encode(location, forKey: .location)
    }
}
