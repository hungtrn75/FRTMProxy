import SwiftUI

struct FlowInspectorPanel: View, Equatable {
    let flow: MitmFlow
    let colors: DesignSystem.ColorPalette
    let onMapLocal: () -> Void
    let onCopyUrl: () -> Void
    let onCopyCurl: () -> Void
    let onCopyBody: () -> Void
    let isRequestBreakpointEnabled: Bool
    let isResponseBreakpointEnabled: Bool
    let onToggleBreakpoint: ((FlowBreakpointPhase, Bool) -> Void)?
    let layoutScale = DesignSystem.Metrics.scale

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.flow == rhs.flow && lhs.colors == rhs.colors && lhs.layoutScale == rhs.layoutScale
            && lhs.isRequestBreakpointEnabled == rhs.isRequestBreakpointEnabled
            && lhs.isResponseBreakpointEnabled == rhs.isResponseBreakpointEnabled
    }

    var body: some View {
        GeometryReader { geometry in
        FlowSplitInspector(
            flow: flow,
            colors: colors,
            onMapLocal: onMapLocal,
            onCopyUrl: onCopyUrl,
            onCopyCurl: onCopyCurl,
            onCopyBody: onCopyBody,
            isRequestBreakpointEnabled: isRequestBreakpointEnabled,
            isResponseBreakpointEnabled: isResponseBreakpointEnabled,
            onToggleBreakpoint: onToggleBreakpoint
        )
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: geometry.size.width, height: geometry.size.height)
        .background(colors.surface)
        }
    }
}
