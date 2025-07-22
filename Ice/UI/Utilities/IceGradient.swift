//
//  IceGradient.swift
//  Ice
//

import SwiftUI

// MARK: - IceGradient

/// A custom gradient.
struct IceGradient: Codable, Hashable {
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
    func withAlpha(_ alpha: CGFloat) -> IceGradient {
        let newStops = stops.map { $0.withAlpha(alpha) }
        return IceGradient(stops: newStops)
    }

    mutating func distributeStops() {
        guard !stops.isEmpty else {
            return
        }
        if stops.count == 1 {
            stops[0].location = 0.5
        } else {
            let last = CGFloat(stops.count - 1)
            let newStops = stops.lazy
                .sorted { $0.location < $1.location }
                .enumerated()
                .map { n, stop in
                    stop.withLocation(CGFloat(n) / last)
                }
            stops = newStops
        }
    }
}

// MARK: IceGradient Static Members
extension IceGradient {
    /// The default menu bar tint gradient.
    static let defaultMenuBarTint = IceGradient(stops: [
        ColorStop.white(location: 0),
        ColorStop.black(location: 1),
    ])
}

// MARK: - IceGradient.ColorStop

extension IceGradient {
    /// A color stop in a gradient.
    struct ColorStop: Hashable {
        /// The stop's color.
        var color: CGColor
        /// The stop's relative location in a gradient.
        var location: CGFloat

        /// Returns a stop with the given color and location.
        static func stop(_ color: CGColor, location: CGFloat) -> ColorStop {
            ColorStop(color: color, location: location)
        }

        /// Returns a stop with a white color suitable for use in a gradient.
        static func white(location: CGFloat) -> ColorStop {
            let srgbWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            return ColorStop(color: srgbWhite, location: location)
        }

        /// Returns a stop with a black color suitable for use in a gradient.
        static func black(location: CGFloat) -> ColorStop {
            let srgbBlack = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            return ColorStop(color: srgbBlack, location: location)
        }

        /// Returns a copy of the stop with the given alpha value.
        func withAlpha(_ alpha: CGFloat) -> ColorStop {
            let newColor = color.copy(alpha: alpha) ?? color
            return ColorStop(color: newColor, location: location)
        }

        /// Returns a copy of the stop with the given location.
        func withLocation(_ location: CGFloat) -> ColorStop {
            ColorStop(color: color, location: location)
        }
    }
}

// MARK: IceGradient.ColorStop: Codable
extension IceGradient.ColorStop: Codable {
    private enum CodingKeys: CodingKey {
        case color
        case location
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.color = try container.decode(IceColor.self, forKey: .color).cgColor
        self.location = try container.decode(CGFloat.self, forKey: .location)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(IceColor(cgColor: color), forKey: .color)
        try container.encode(location, forKey: .location)
    }
}
