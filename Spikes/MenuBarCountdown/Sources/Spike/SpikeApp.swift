import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

// Phase 0 spike. Three questions (D-25, D-24):
//  1. Does a MenuBarExtra label keep updating? (compared with an NSStatusItem side by side)
//  2. Does a non-activating NSPanel accept typing over a full-screen app via a global hotkey (⌃⌥Space)?
//  3. Can a sandboxed app see lock/unlock and read idle time?
// Every observation goes to the popover log and to spike.log in the sandbox container.

@MainActor
final class SpikeLog: ObservableObject {
    static let shared = SpikeLog()
    @Published var lines: [String] = []
    @Published var tick = 0
    let fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "spike.log")

    func add(_ text: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(text)"
        lines.append(line)
        if lines.count > 200 { lines.removeFirst() }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((line + "\n").utf8).write(to: fileURL)
        }
    }
}

@main
struct SpikeApp: App {
    @NSApplicationDelegateAdaptor(SpikeDelegate.self) var delegate
    @ObservedObject var log = SpikeLog.shared

    var body: some Scene {
        // Label updated from a @Published counter every 10 s (the real app needs once a minute).
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 6) {
                Text("ExecFn Phase 0 spike").font(.headline)
                Text("Press ⌃⌥Space for the capture panel. Lock the screen and leave the Mac idle for >1 min to test presence.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.lines.enumerated().reversed()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                .frame(height: 260)
                Text("Log file: \(log.fileURL.path)").font(.caption2).textSelection(.enabled)
                Button("Quit spike") { NSApp.terminate(nil) }
            }
            .padding(12)
            .frame(width: 440)
        } label: {
            Text("MBE \(log.tick)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class SpikeDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var panel: CapturePanel?
    var timer: Timer?
    var hotKeyRef: EventHotKeyRef?
    var lastIdleBucket = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        let log = SpikeLog.shared
        log.add("launched; sandboxed=\(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "NSI 0"

        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { self.everyTenSeconds() }
        }

        observePresence()
        registerHotKey()
        log.add("ready: watch 'MBE n' and 'NSI n' in the menu bar — both should count up every 10 s")
    }

    func everyTenSeconds() {
        let log = SpikeLog.shared
        log.tick += 1
        statusItem?.button?.title = "NSI \(log.tick)"
        if log.tick % 6 == 0 { log.add("tick \(log.tick) (labels should both read \(log.tick))") }

        // kCGAnyInputEventType = ~0
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let bucket = idle >= 60 ? 1 : 0
        if bucket != lastIdleBucket {
            log.add(String(format: "idle seconds readable: %.0f s%@", idle, bucket == 1 ? " (idle ≥ 60 s)" : ""))
            lastIdleBucket = bucket
        }
    }

    func observePresence() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            ws.addObserver(forName: name, object: nil, queue: .main) { note in
                let n = note.name.rawValue
                MainActor.assumeIsolated { SpikeLog.shared.add("workspace: \(n)") }
            }
        }
        let dist = DistributedNotificationCenter.default()
        for raw in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked",
                    "com.apple.screensaver.didstart", "com.apple.screensaver.didstop"] {
            dist.addObserver(forName: Notification.Name(raw), object: nil, queue: .main) { note in
                let n = note.name.rawValue
                MainActor.assumeIsolated { SpikeLog.shared.add("distributed: \(n)") }
            }
        }
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { SpikeDelegate.current?.toggleCapture() } }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x45584546), id: 1) // 'EXEF'
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        SpikeDelegate.current = self
        SpikeLog.shared.add("hotkey ⌃⌥Space registered: \(status == noErr ? "yes" : "no (\(status))")")
    }

    static var current: SpikeDelegate?

    func toggleCapture() {
        if panel == nil { panel = CapturePanel() }
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.present()
            SpikeLog.shared.add("panel shown; frontmost app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"), spike active=\(NSApp.isActive)")
        }
    }
}

final class CapturePanel: NSPanel {
    private let field = NSTextField()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 64),
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
        field.placeholderString = "Type a task and press Return (Esc closes)"
        field.font = .systemFont(ofSize: 20)
        field.target = self
        field.action = #selector(submit)
        field.frame = NSRect(x: 16, y: 14, width: 488, height: 32)
        contentView?.addSubview(field)
    }

    override var canBecomeKey: Bool { true }

    func present() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - 200))
        }
        field.stringValue = ""
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    @objc private func submit() {
        let text = field.stringValue
        MainActor.assumeIsolated {
            SpikeLog.shared.add("captured \"\(text)\" — typing works; frontmost still: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        }
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
