import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Global ⌃⌥Space via Carbon `RegisterEventHotKey` (works in the sandbox, no permissions; Phase 0).
/// Rebinding (KeyboardShortcuts) can replace this later without touching callers.
@MainActor
final class HotkeyService {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var action: (@MainActor () -> Void)?

    func register(_ action: @escaping @MainActor () -> Void) -> Bool {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotkeyService.action?() } }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x45584546), id: 1) // 'EXEF'
        let status = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(controlKey | optionKey), id,
            GetApplicationEventTarget(), 0, &ref
        )
        return status == noErr
    }
}

/// Floating, non-activating: typing works over full-screen apps without bringing ExecFn forward.
@MainActor
final class CapturePanelController {
    private var panel: CapturePanel?
    private let onSubmit: (String) -> Bool

    init(onSubmit: @escaping (String) -> Bool) {
        self.onSubmit = onSubmit
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        let panel = self.panel ?? CapturePanel(onSubmit: onSubmit)
        self.panel = panel
        panel.present()
    }
}

final class CapturePanel: NSPanel {
    private let model: CaptureFieldModel

    init(onSubmit: @escaping (String) -> Bool) {
        let model = CaptureFieldModel()
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 64),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        model.submit = { [weak self] text in
            guard onSubmit(text) else { return }
            self?.model.confirmation = String(localized: "Added to Inbox")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.orderOut(nil) }
        }
        model.cancel = { [weak self] in self?.orderOut(nil) }
        contentView = NSHostingView(rootView: CaptureField(model: model))
    }

    override var canBecomeKey: Bool { true }

    func present() {
        model.text = ""
        model.confirmation = nil
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - f.height * 0.25))
        }
        makeKeyAndOrderFront(nil)
        model.focusToken += 1
    }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor
@Observable
final class CaptureFieldModel {
    var text = ""
    var confirmation: String?
    var focusToken = 0
    var submit: (String) -> Void = { _ in }
    var cancel: () -> Void = {}
}

struct CaptureField: View {
    @Bindable var model: CaptureFieldModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.confirmation == nil ? "plus.circle" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            if let confirmation = model.confirmation {
                Text(confirmation).font(.title3)
                Spacer()
            } else {
                TextField("What's on your mind? Return adds it to the Inbox", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
                    .onSubmit { model.submit(model.text) }
                    .onExitCommand { model.cancel() }
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 560, height: 64)
        .onChange(of: model.focusToken) { focused = true }
        .onAppear { focused = true }
    }
}
