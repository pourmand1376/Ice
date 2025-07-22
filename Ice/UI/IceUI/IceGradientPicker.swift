//
//  IceGradientPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct IceGradientPicker: View {
    @Environment(\.isEnabled) private var isEnabled

    @Binding var gradient: IceGradient
    @State private var selection: Int?
    @State private var lastUpdated: Int?
    @State private var window: NSWindow?
    @State private var isActive = false
    @State private var cancellables = Set<AnyCancellable>()

    let mode: NSColorPanel.Mode?
    let supportsOpacity: Bool

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .circular)
        }
    }

    /// Creates a new gradient picker.
    ///
    /// - Parameters:
    ///   - gradient: A binding to a gradient.
    ///   - mode: The mode that the color panel should take on when
    ///     picking a color for the gradient.
    ///   - supportsOpacity: A Boolean value indicating whether the
    ///     picker should support opacity.
    init(
        gradient: Binding<IceGradient>,
        mode: NSColorPanel.Mode? = nil,
        supportsOpacity: Bool
    ) {
        self._gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.mode = mode
    }

    var body: some View {
        gradient.swiftUIView
            .clipShape(borderShape)
            .overlay {
                borderView
            }
            .frame(width: 200, height: 20)
            .overlay {
                GeometryReader { geometry in
                    selectionReader(geometry: geometry)
                    insertionReader(geometry: geometry)
                    handles(geometry: geometry)
                }
                .padding(.horizontal, 4)
            }
            .foregroundStyle(.tertiary)
            .shadow(radius: 2)
            .onWindowChange(update: $window)
            .onTapGesture(count: 2) {
                gradient.distributeStops()
            }
            .onKeyDown(key: .delete) {
                deleteSelectedStop()
            }
            .onKeyDown(key: .escape) {
                selection = nil
            }
            .onChange(of: gradient) { oldValue, newValue in
                gradientChanged(from: oldValue, to: newValue)
            }
            .onChange(of: selection) { oldValue, newValue in
                selectionChanged(from: oldValue, to: newValue)
            }
            .compositingGroup()
            .allowsHitTesting(isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
    }

    @ViewBuilder
    private var borderView: some View {
        borderShape
            .strokeBorder()
            .overlay {
                centerTickMark
            }
    }

    @ViewBuilder
    private var centerTickMark: some View {
        Rectangle()
            .frame(width: 1, height: 6)
    }

    @ViewBuilder
    private func selectionReader(geometry: GeometryProxy) -> some View {
        Color.clear
            .localEventMonitor(mask: .leftMouseDown) { [weak window] event in
                var location = event.locationInWindow

                guard
                    let window,
                    window === event.window,
                    window.contentLayoutRect.contains(location)
                else {
                    return event
                }

                // Flip the location to match SwiftUI's coordinate space.
                location.y = window.frame.height - location.y

                if !geometry.frame(in: .global).contains(location) {
                    selection = nil
                }

                return event
            }
    }

    @ViewBuilder
    private func insertionReader(geometry: GeometryProxy) -> some View {
        Color.clear
            .contentShape(borderShape)
            .onTapGesture { location in
                let frame = geometry.frame(in: .local)
                insertStop(at: (location.x / frame.width), select: true)
            }
    }

    @ViewBuilder
    private func handles(geometry: GeometryProxy) -> some View {
        ForEach(gradient.stops.indices, id: \.self) { index in
            IceGradientPickerHandle(
                gradient: $gradient,
                selection: $selection,
                lastUpdated: $lastUpdated,
                index: index,
                geometry: geometry
            )
        }
    }

    /// Inserts a new stop with the appropriate color at the given location
    /// in the gradient.
    private func insertStop(at location: CGFloat, select: Bool) {
        var location = location.clamped(to: 0...1)
        if abs(location - 0.5) <= 0.02 {
            location = 0.5
        }
        if let color = gradient.color(at: location) {
            gradient.stops.append(.stop(color, location: location))
        } else {
            gradient.stops.append(.black(location: location))
        }
        if select, let index = gradient.stops.indices.last {
            DispatchQueue.main.async {
                self.selection = index
            }
        }
    }

    private func gradientChanged(from oldValue: IceGradient, to newValue: IceGradient) {
        guard oldValue != newValue else {
            return
        }
        if newValue.stops.isEmpty {
            gradient = oldValue
        }
    }

    private func selectionChanged(from oldValue: Int?, to newValue: Int?) {
        guard oldValue != newValue else {
            return
        }
        if newValue != nil {
            activate()
        } else {
            deactivate()
        }
    }

    private func activate() {
        guard !isActive else {
            return
        }

        defer {
            isActive = true
        }

        NSColorPanel.shared.orderFrontRegardless()

        var c = Set<AnyCancellable>()

        NSColorPanel.shared.publisher(for: \.color)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { color in
                guard
                    isActive,
                    NSColorPanel.shared.isVisible,
                    let selection,
                    gradient.stops.indices.contains(selection),
                    gradient.stops[selection].color != color.cgColor
                else {
                    return
                }
                gradient.stops[selection].color = color.cgColor
            }
            .store(in: &c)

        NSColorPanel.shared.publisher(for: \.isVisible)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak window] isVisible in
                guard isVisible, isActive else {
                    selection = nil
                    return
                }
                guard
                    let selection,
                    gradient.stops.indices.contains(selection)
                else {
                    return
                }
                if NSColorPanel.shared.showsAlpha != supportsOpacity {
                    NSColorPanel.shared.showsAlpha = supportsOpacity
                }
                if
                    let color = NSColor(cgColor: gradient.stops[selection].color),
                    NSColorPanel.shared.color != color
                {
                    NSColorPanel.shared.color = color
                }
                if let mode, NSColorPanel.shared.mode != mode {
                    NSColorPanel.shared.mode = mode
                }
                if
                    let level = window.flatMap({ $0.level + 1 }),
                    NSColorPanel.shared.level != level
                {
                    NSColorPanel.shared.level = level
                }
                if NSColorPanel.shared.frame.origin == .zero {
                    NSColorPanel.shared.center()
                }
            }
            .store(in: &c)

        NSColorPanel.shared.publisher(for: \.level)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak window] _ in
                guard let window, isActive else {
                    return
                }
                if NSColorPanel.shared.level < window.level {
                    NSColorPanel.shared.level = window.level
                }
            }
            .store(in: &c)

        cancellables = c
    }

    private func deactivate() {
        guard isActive else {
            return
        }

        defer {
            isActive = false
        }

        NSColorPanel.shared.close()

        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()
    }

    private func deleteSelectedStop() {
        guard
            let index = selection.take(),
            gradient.stops.indices.contains(index)
        else {
            return
        }
        gradient.stops.remove(at: index)
    }
}

private struct IceGradientPickerHandle: View {
    @Binding var gradient: IceGradient
    @Binding var selection: Int?
    @Binding var lastUpdated: Int?

    let index: Int
    let geometry: GeometryProxy

    private var isSelected: Bool {
        index == selection
    }

    private var isLastUpdated: Bool {
        index == lastUpdated
    }

    private var location: CGFloat {
        gradient.stops[index].location
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            Capsule(style: .continuous)
        } else {
            Capsule(style: .circular)
        }
    }

    var body: some View {
        handleView
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        update(with: value.location.x, shouldSnap: abs(value.velocity.width) <= 75)
                    }
                    .onEnded { value in
                        update(with: value.location.x, shouldSnap: true)
                    }
            )
            .onTapGesture {
                selection = isSelected ? nil : index
            }
            .onKeyPress(.space) {
                selection = isSelected ? nil : index
                return .handled
            }
            .onChange(of: isSelected) { _, newValue in
                if newValue {
                    lastUpdated = index
                }
            }
    }

    @ViewBuilder
    private var handleView: some View {
        if gradient.stops.indices.contains(index) {
            borderShape
                .fill(Color(cgColor: gradient.stops[index].color))
                .strokeBorder(isSelected ? .primary : .tertiary, lineWidth: isSelected ? 1.5 : 1)
                .contentShape([.interaction, .focusEffect], borderShape)
                .frame(width: 10, height: 26)
                .position(
                    x: geometry.size.width * location,
                    y: geometry.size.height / 2
                )
                .zIndex(isLastUpdated ? 2 : location)
        }
    }

    private func update(with location: CGFloat, shouldSnap: Bool) {
        guard gradient.stops.indices.contains(index) else {
            return
        }
        let newLocation = (location / geometry.size.width).clamped(to: 0...1)
        if shouldSnap && abs(newLocation - 0.5) <= 0.02 {
            gradient.stops[index].location = 0.5
        } else {
            gradient.stops[index].location = newLocation
        }
        lastUpdated = index
    }
}
