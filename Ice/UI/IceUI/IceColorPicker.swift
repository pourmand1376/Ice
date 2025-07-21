//
//  IceColorPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct IceColorPicker: View {
    typealias Style = NSColorWell.Style
    typealias Mode = NSColorPanel.Mode

    private final class Coordinator {
        @Binding var selection: CGColor

        let mode: Mode?
        let supportsOpacity: Bool
        private var cancellables = Set<AnyCancellable>()

        init(selection: Binding<CGColor>, mode: Mode?, supportsOpacity: Bool) {
            self._selection = selection
            self.mode = mode
            self.supportsOpacity = supportsOpacity
        }

        @MainActor
        func configure(with colorWell: NSColorWell) {
            var c = Set<AnyCancellable>()

            colorWell.publisher(for: \.color)
                .removeDuplicates()
                .sink { [weak self, weak colorWell] color in
                    guard let self, let colorWell else {
                        return
                    }
                    guard colorWell.isActive else {
                        return
                    }
                    if supportsOpacity {
                        guard NSColorPanel.shared.showsAlpha else {
                            if let color = NSColor(cgColor: selection) {
                                colorWell.color = color
                            }
                            return
                        }
                    }
                    if selection != color.cgColor {
                        selection = color.cgColor
                    }
                }
                .store(in: &c)

            NSColorPanel.shared.publisher(for: \.isVisible)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak colorWell] isVisible in
                    guard let self, let colorWell else {
                        return
                    }
                    guard isVisible, colorWell.isActive else {
                        return
                    }
                    NSColorPanel.shared.showsAlpha = supportsOpacity
                    NSColorPanel.shared.color = colorWell.color
                    if let mode {
                        NSColorPanel.shared.mode = mode
                    }
                    if let window = colorWell.window {
                        NSColorPanel.shared.level = window.level + 1
                    }
                    if NSColorPanel.shared.frame.origin == .zero {
                        NSColorPanel.shared.center()
                    }
                }
                .store(in: &c)

            NSColorPanel.shared.publisher(for: \.level)
                .receive(on: DispatchQueue.main)
                .sink { [weak colorWell] level in
                    guard let colorWell, colorWell.isActive else {
                        return
                    }
                    guard let window = colorWell.window, level != window.level + 1 else {
                        return
                    }
                    NSColorPanel.shared.level = window.level + 1
                }
                .store(in: &c)

            cancellables = c
        }
    }

    private struct Representable: NSViewRepresentable {
        @Binding var selection: CGColor

        let style: Style
        let mode: Mode?
        let supportsOpacity: Bool

        func makeNSView(context: Context) -> NSColorWell {
            let colorWell = NSColorWell(style: style)
            context.coordinator.configure(with: colorWell)
            return colorWell
        }

        func updateNSView(_ nsView: NSColorWell, context: Context) {
            if let color = NSColor(cgColor: selection), nsView.color != color {
                nsView.color = color
            }
            if nsView.colorWellStyle != style {
                nsView.colorWellStyle = style
            }
        }

        func makeCoordinator() -> Coordinator {
            return Coordinator(selection: $selection, mode: mode, supportsOpacity: supportsOpacity)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSColorWell, context: Context) -> CGSize? {
            switch nsView.controlSize {
            case .extraLarge:
                CGSize(width: 64, height: 34)
            case .large:
                CGSize(width: 55, height: 30)
            case .regular:
                CGSize(width: 44, height: 24)
            case .small:
                CGSize(width: 33, height: 18)
            case .mini:
                CGSize(width: 29, height: 16)
            @unknown default:
                nsView.intrinsicContentSize
            }
        }
    }

    @Environment(\.isEnabled) private var isEnabled
    @Binding var selection: CGColor

    let style: Style
    let mode: Mode?
    let supportsOpacity: Bool

    init(selection: Binding<CGColor>, style: Style = .minimal, mode: Mode? = nil, supportsOpacity: Bool = true) {
        self._selection = selection
        self.style = style
        self.mode = mode
        self.supportsOpacity = supportsOpacity
    }

    var body: some View {
        Representable(selection: $selection, style: style, mode: mode, supportsOpacity: supportsOpacity)
            .allowsHitTesting(isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
    }
}
