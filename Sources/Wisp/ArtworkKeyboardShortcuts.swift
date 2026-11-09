import AppKit
import SwiftUI

/// Keyboard actions belong only to this artwork sheet. Text fields retain their
/// ordinary Paste behavior, and file panels or other windows are never intercepted.
@MainActor
struct ArtworkKeyboardShortcuts: NSViewRepresentable {
    var enabled: Bool
    var paste: () -> Void
    var upload: () -> Void
    var search: () -> Void

    init(enabled: Bool, paste: @escaping () -> Void, upload: @escaping () -> Void,
         search: @escaping () -> Void) {
        self.enabled = enabled; self.paste = paste; self.upload = upload; self.search = search
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ArtworkShortcutHostView {
        let view = ArtworkShortcutHostView()
        view.windowChanged = { [weak coordinator = context.coordinator] view in coordinator?.attach(to: view) }
        configure(context.coordinator)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: ArtworkShortcutHostView, context: Context) {
        configure(context.coordinator)
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: ArtworkShortcutHostView, coordinator: Coordinator) {
        nsView.windowChanged = nil
        coordinator.detach()
    }

    private func configure(_ coordinator: Coordinator) {
        coordinator.configure(enabled: enabled, paste: paste, upload: upload, search: search)
    }

    enum Action: Equatable { case paste, upload, search }

    /// The same decision is exercised by isolated AppKit window/event fixtures.
    static func action(for event: NSEvent, hostWindow: NSWindow?, keyWindow: NSWindow?,
                       enabled: Bool) -> Action? {
        guard enabled, event.type == .keyDown, !event.isARepeat,
              let hostWindow, event.window === hostWindow, keyWindow === hostWindow,
              hostWindow.attachedSheet == nil else { return nil }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "v" {
            if let text = hostWindow.firstResponder as? NSTextView, text.isEditable { return nil }
            if let field = hostWindow.firstResponder as? NSTextField, field.isEditable { return nil }
            return .paste
        }
        if modifiers == .command, key == "o" { return .upload }
        if modifiers == [.command, .shift], key == "f" { return .search }
        return nil
    }

    @MainActor
    final class Coordinator {
        private weak var hostView: NSView?
        private var monitor: Any?
        private var enabled = false
        private var paste: () -> Void = {}
        private var upload: () -> Void = {}
        private var search: () -> Void = {}
        var isMonitoring: Bool { monitor != nil }

        func configure(enabled: Bool, paste: @escaping () -> Void, upload: @escaping () -> Void,
                       search: @escaping () -> Void) {
            self.enabled = enabled; self.paste = paste; self.upload = upload; self.search = search
            refreshMonitor()
        }

        func attach(to view: NSView) {
            hostView = view
            refreshMonitor()
        }

        func detach() {
            hostView = nil
            removeMonitor()
        }

        private func refreshMonitor() {
            guard enabled, hostView?.window != nil else { removeMonitor(); return }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown,
                handler: eventHandler(keyWindow: { NSApp.keyWindow }))
        }

        /// The monitor and isolated window fixtures use this identical handler.
        func eventHandler(keyWindow: @escaping () -> NSWindow?) -> (NSEvent) -> NSEvent? {
            { [weak self] event in
                guard let self else { return event }
                return self.process(event, keyWindow: keyWindow())
            }
        }

        /// Direct event dispatch is testable without posting events to an app or
        /// touching a clipboard; the real monitor supplies NSApp.keyWindow.
        func process(_ event: NSEvent, keyWindow: NSWindow?) -> NSEvent? {
            guard let action = ArtworkKeyboardShortcuts.action(for: event, hostWindow: hostView?.window,
                keyWindow: keyWindow, enabled: enabled) else { return event }
            switch action {
            case .paste: paste()
            case .upload: upload()
            case .search: search()
            }
            return nil
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

@MainActor
final class ArtworkShortcutHostView: NSView {
    var windowChanged: ((NSView) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowChanged?(self)
    }
}
