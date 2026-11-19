import SwiftUI
import AppKit
import CodeMirror
import WebKit

/// SwiftUI wrapper around CodeMirror (WebKit-based) editor.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    var minHeight: CGFloat = 0
    var colors: DesignSystem.ColorPalette?

    @Environment(\.colorScheme) var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CodeMirrorContainerView {
        let container = CodeMirrorContainerView(minHeight: minHeight)
        context.coordinator.attach(webView: container.webView)
        configure(container.webView, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: CodeMirrorContainerView, context: Context) {
        if nsView.minHeight != minHeight { nsView.minHeight = minHeight }
        context.coordinator.parent = self
        context.coordinator.attach(webView: nsView.webView)
        

        configure(nsView.webView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: CodeMirrorContainerView, coordinator: Coordinator) {
        coordinator.detach(webView: nsView.webView)
        nsView.cleanup()
    }

    private func configure(_ webView: CodeMirrorWebView, coordinator: Coordinator) {
        coordinator.syncConfiguration(
            webView: webView,
            text: text,
            isEditable: isEditable,
            isDarkMode: colorScheme == .dark,
            appearance: CodeEditorAppearance(colors: colors ?? DesignSystem.Colors.palette(colorScheme))
        )
    }
}

// MARK: - Coordinator

final class Coordinator: NSObject, CodeMirrorWebViewDelegate {
    var parent: CodeEditorView
    private var isSyncingFromParent = false
    private var lastAppliedText: String = ""
    private var didConfigureEditor = false
    private var lastFontSize: Int?
    private var lastReadonly: Bool?
    private var lastDarkMode: Bool?
    private var lastAppearance: CodeEditorAppearance?
    private var isEditorLoaded = false
    private weak var registeredWebView: CodeMirrorWebView?

    init(parent: CodeEditorView) {
        self.parent = parent
    }

    func attach(webView: CodeMirrorWebView) {
        if registeredWebView !== webView {
            if let registeredWebView {
                CodeMirrorShortcutCenter.shared.unregister(webView: registeredWebView)
            }
            CodeMirrorShortcutCenter.shared.register(webView: webView)
            registeredWebView = webView
            didConfigureEditor = false
            lastFontSize = nil
            lastReadonly = nil
            lastDarkMode = nil
            lastAppearance = nil
            isEditorLoaded = false
        }
        
        webView.delegate = self
    }

    func detach(webView: CodeMirrorWebView) {
        if registeredWebView === webView {
            CodeMirrorShortcutCenter.shared.unregister(webView: webView)
            registeredWebView = nil
        }
        if webView.delegate === self {
            webView.delegate = nil
        }
    }

    deinit {
        if let registeredWebView {
            CodeMirrorShortcutCenter.shared.unregister(webView: registeredWebView)
        }
    }

    func syncConfiguration(
        webView: CodeMirrorWebView,
        text: String,
        isEditable: Bool,
        isDarkMode: Bool,
        appearance: CodeEditorAppearance
    ) {
        if !didConfigureEditor {
            webView.setLineWrapping(true)
            webView.setTabInsertsSpaces(true)
            webView.setMimeType("application/json")
            didConfigureEditor = true
        }

        let fontSize = Int(DesignSystem.Metrics.font(13).rounded())
        if lastFontSize != fontSize {
            webView.setFontSize(fontSize)
            lastFontSize = fontSize
        }
        if lastReadonly != !isEditable {
            webView.setReadonly(!isEditable)
            lastReadonly = !isEditable
        }
        if lastDarkMode != isDarkMode {
            webView.setDarkTheme(isDarkMode)
            lastDarkMode = isDarkMode
        }
        if isEditorLoaded, lastAppearance != appearance {
            lastAppearance = appearance
            webView.webview.callAsyncJavaScript(
                """
                let style = document.getElementById('frtm-editor-theme');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'frtm-editor-theme';
                    document.head.appendChild(style);
                }
                style.textContent = css;
                """,
                arguments: ["css": appearance.css], in: nil, in: .page
            ) { result in
                if case let .failure(error) = result {
                    NSLog("CodeMirror theme failed: \(error.localizedDescription)")
                }
            }
        }

        if lastAppliedText != text {
            isSyncingFromParent = true
            lastAppliedText = text
            webView.setContent(text, beautifyMode: .none)
        }
    }

    // MARK: CodeMirrorWebViewDelegate

    func codeMirrorViewDidLoadSuccess(_ sender: CodeMirrorWebView) {
        isEditorLoaded = true
        lastAppearance = nil
        syncConfiguration(
            webView: sender,
            text: parent.text,
            isEditable: parent.isEditable,
            isDarkMode: parent.colorScheme == .dark,
            appearance: CodeEditorAppearance(colors: parent.colors ?? DesignSystem.Colors.palette(parent.colorScheme))
        )
    }

    func codeMirrorViewDidLoadError(_ sender: CodeMirrorWebView, error: Error) {
        NSLog("CodeMirror load failed: \(error.localizedDescription)")
    }

    func codeMirrorViewDidChangeContent(_ sender: CodeMirrorWebView, content: String) {
        // Read-only previews never write JavaScript callbacks back into SwiftUI state.
        // A delayed callback may belong to the previously selected request.
        guard parent.isEditable else {
            isSyncingFromParent = false
            return
        }
        if isSyncingFromParent {
            isSyncingFromParent = false
            return
        }

        guard parent.text != content else { return }
        DispatchQueue.main.async {
            self.lastAppliedText = content
            self.parent.text = content
        }
    }
}

// MARK: - Container view to control intrinsic height

final class CodeMirrorContainerView: NSView {
    let webView: CodeMirrorWebView
    var minHeight: CGFloat {
        didSet {
            heightConstraint?.constant = minHeight
            invalidateIntrinsicContentSize()
        }
    }
    private var heightConstraint: NSLayoutConstraint?

    init(minHeight: CGFloat) {
        self.minHeight = minHeight
        self.webView = CodeMirrorWebView()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: minHeight)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        heightConstraint = webView.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint!
        ])
    }

    func cleanup() {
        guard let wkWebView = findWKWebView(in: webView) else { return }
        let controller = wkWebView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "codeMirrorDidReady")
        controller.removeScriptMessageHandler(forName: "codeMirrorTextContentDidChange")
        wkWebView.navigationDelegate = nil
        wkWebView.uiDelegate = nil
        wkWebView.stopLoading()
        wkWebView.loadHTMLString("", baseURL: nil)
    }

    private func findWKWebView(in view: NSView) -> WKWebView? {
        if let wkWebView = view as? WKWebView {
            return wkWebView
        }
        for subview in view.subviews {
            if let match = findWKWebView(in: subview) {
                return match
            }
        }
        return nil
    }
}

/// Native, selectable body preview with the standard macOS find bar.
struct NativeBodyTextView: NSViewRepresentable {
    let text: String
    let colors: DesignSystem.ColorPalette

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = NativeBodyTextContentView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.usesFindBar = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize: DesignSystem.Metrics.font(13), weight: .regular)
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        view.textColor = NSColor(colors.textPrimary)
        view.font = .monospacedSystemFont(ofSize: DesignSystem.Metrics.font(13), weight: .regular)
        if view.string != text {
            view.string = text
            view.scrollToBeginningOfDocument(nil)
        }
    }
}

final class NativeBodyTextContentView: NSTextView {}

struct JSONFoldRange: Equatable, Sendable {
    let start: Int
    let end: Int

    static func find(in text: String) -> [JSONFoldRange] {
        var stack: [Int] = []
        var ranges: [JSONFoldRange] = []
        var inString = false
        var escaped = false
        for (offset, character) in text.utf16.enumerated() {
            if Task.isCancelled { return [] }
            if inString {
                if escaped { escaped = false }
                else if character == 92 { escaped = true }
                else if character == 34 { inString = false }
            } else if character == 34 {
                inString = true
            } else if character == 123 || character == 91 {
                stack.append(offset)
            } else if character == 125 || character == 93, let start = stack.popLast() {
                if offset > start + 1 { ranges.append(JSONFoldRange(start: start, end: offset)) }
            }
        }
        return ranges.sorted { $0.start < $1.start }
    }
}

final class NativeJSONTextView: NSTextView {
    var originalText = ""
    var sourceOffsets: [Int] = []

    override func copy(_ sender: Any?) {
        guard let copied = selectedOriginalText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copied, forType: .string)
    }

    func selectedOriginalText() -> String? {
        let selection = selectedRange()
        guard selection.length > 0, selection.location != NSNotFound,
              NSMaxRange(selection) < sourceOffsets.count else { return nil }
        let start = sourceOffsets[selection.location]
        let end = sourceOffsets[NSMaxRange(selection)]
        guard end > start else { return nil }
        return (originalText as NSString).substring(with: NSRange(location: start, length: end - start))
    }
}

struct NativeJSONBodyView: NSViewRepresentable {
    let text: String
    let ranges: [JSONFoldRange]
    let colors: DesignSystem.ColorPalette

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = NativeJSONTextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.usesFindBar = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.drawsBackground = false
        view.delegate = context.coordinator
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NativeJSONTextView else { return }
        context.coordinator.update(view: view, text: text, ranges: ranges, color: NSColor(colors.textPrimary), accent: NSColor(colors.accent))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var source = ""
        private var ranges: [JSONFoldRange] = []
        private var folded: Set<Int> = []
        private var color = NSColor.textColor
        private var accent = NSColor.controlAccentColor

        func update(view: NativeJSONTextView, text: String, ranges: [JSONFoldRange], color: NSColor, accent: NSColor) {
            let sourceChanged = source != text
            guard sourceChanged || self.ranges != ranges || self.color != color || self.accent != accent else { return }
            if sourceChanged { folded.removeAll() }
            source = text
            self.ranges = ranges
            self.color = color
            self.accent = accent
            render(view)
            if sourceChanged { view.scrollToBeginningOfDocument(nil) }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let textView = textView as? NativeJSONTextView,
                  let url = link as? URL, url.scheme == "frtm-json-fold", let start = Int(url.host ?? "") else { return false }
            if folded.contains(start) { folded.remove(start) } else { folded.insert(start) }
            render(textView)
            textView.scrollRangeToVisible(NSRange(location: min(charIndex, textView.string.utf16.count), length: 0))
            return true
        }

        private func render(_ view: NativeJSONTextView) {
            let font = NSFont.monospacedSystemFont(ofSize: DesignSystem.Metrics.font(13), weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let output = NSMutableAttributedString(string: "")
            let original = source as NSString
            var cursor = 0
            var offsets = [0]
            func appendSource(from start: Int, to end: Int) {
                guard end > start else { return }
                output.append(NSAttributedString(string: original.substring(with: NSRange(location: start, length: end - start)), attributes: attributes))
                offsets.append(contentsOf: (start + 1)...end)
            }
            for range in ranges {
                guard range.start >= cursor, range.end < original.length else { continue }
                appendSource(from: cursor, to: range.start)
                if let url = URL(string: "frtm-json-fold://\(range.start)") {
                    output.append(NSAttributedString(string: folded.contains(range.start) ? "▸" : "▾", attributes: [.font: font, .foregroundColor: accent, .link: url]))
                    offsets.append(range.start)
                }
                if folded.contains(range.start) {
                    appendSource(from: range.start, to: range.start + 1)
                    output.append(NSAttributedString(string: "…", attributes: attributes))
                    offsets.append(range.end)
                    cursor = range.end
                } else {
                    cursor = range.start
                }
            }
            appendSource(from: cursor, to: original.length)
            view.originalText = source
            view.sourceOffsets = offsets
            view.linkTextAttributes = [.foregroundColor: accent, .underlineStyle: 0]
            view.textStorage?.setAttributedString(output)
        }
    }
}
