import AppKit
import ApplicationServices

/// AppDelegate is intentionally thin. All real logic lives in
/// `DoubleTapDetector`, `Selection`, `Picker`, and `RefinerHelper`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let helper: RefinerHelper
    private let appDir: String
    private var detector: DoubleTapDetector!
    private var menuBar: MenuBar!
    private var preferences: PreferencesWindowController!
    private var onboarding: OnboardingWindowController?
    private var dictationOverlay: DictationOverlay!
    private var isProcessing = false
    private var lastRefinedText: String?

    init(helper: RefinerHelper, appDir: String) {
        self.helper = helper
        self.appDir = appDir
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        StandardMenu.install()

        Modes.load(appDir: appDir)
        preferences = PreferencesWindowController(appDir: appDir, helper: helper)
        menuBar = MenuBar(prefsController: preferences)
        dictationOverlay = DictationOverlay()

        detector = DoubleTapDetector { [weak self] in
            self?.trigger()
        }
        detector.install()

        let trusted = AXIsProcessTrusted()
        log("Accessibility trust: \(trusted ? "YES" : "NO — toggle this binary off/on in System Settings → Privacy & Security → Accessibility")")
        log("Loaded \(Modes.all.count) modes from disk")
        log("Penny native daemon running. Double-tap Right Option over selected text to refine.")

        if OnboardingWindowController.shouldShow() {
            log("First run detected — showing onboarding window")
            onboarding = OnboardingWindowController(prefsController: preferences)
            onboarding?.showWindow(nil)
        }
    }

    /// Entry point fired by the double-tap detector.
    private func trigger() {
        guard !isProcessing else { return }
        isProcessing = true

        // Get every Penny-owned window out of the way before we start. If the
        // user left Preferences or Onboarding open, the paste back to the
        // source app would land in the wrong place once they reached for
        // a Penny window. Hiding them also dismisses any open menu bar
        // dropdown so it can't compete with the picker.
        menuBar?.dismissMenu()
        hideOurWindows()

        let sourceApp = NSWorkspace.shared.frontmostApplication
        log("Trigger from \(sourceApp?.localizedName ?? "unknown")")

        // Path A: Accessibility direct read+write. Works in native Cocoa apps.
        if
            let element = Selection.focusedElement(),
            let selected = Selection.readSelectedText(from: element),
            !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            log("Accessibility selection read (\(selected.count) chars)")
            presentPicker(for: selected, focusedElement: element, sourceApp: sourceApp)
            return
        }

        // Path B: clipboard. We synthesize ⌘C and gate on the pasteboard's
        // change counter so stale clipboard content can't masquerade as a
        // fresh selection.
        Clipboard.grabSelection { [weak self] text in
            guard let self else { return }
            guard let text else {
                self.fail("Couldn't read your selection", detail: "Highlight text, press ⌘C, then double-tap Right Option again.")
                return
            }
            self.presentPicker(for: text, focusedElement: nil, sourceApp: sourceApp)
        }
    }

    private func presentPicker(for text: String, focusedElement: AXUIElement?, sourceApp: NSRunningApplication?) {
        guard let choice = Picker.chooseMode() else {
            log("Picker cancelled")
            isProcessing = false
            return
        }

        log("Selected mode \(choice.mode.id) (\(choice.mode.name))")
        Picker.showStatus("Refining · \(choice.mode.name)")
        refine(text: text, choice: choice, focusedElement: focusedElement, sourceApp: sourceApp)
    }

    private func refine(text: String, choice: PickerChoice, focusedElement: AXUIElement?, sourceApp: NSRunningApplication?) {
        DispatchQueue.global(qos: .userInitiated).async { [helper] in
            let result = helper.run(text: text, mode: choice.mode.id, customPrompt: choice.customPrompt)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Picker.closeStatus()
                defer { self.isProcessing = false }

                switch result {
                case .failure(let error):
                    log("Refiner helper failed: \(error)")
                    self.fail("Penny error", detail: error)

                case .success(let refined):
                    let trimmed = refined.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        self.fail("Empty response", detail: "The original text was preserved.")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        return
                    }

                    // "No change needed" path. The mode prompts deliberately
                    // return the input verbatim when an edit isn't warranted
                    // — pasting identical text would be pointless and risks
                    // disturbing the user's caret position. Compare with
                    // whitespace trim so trailing newline differences don't
                    // count as changes.
                    let originalTrimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed == originalTrimmed {
                        log("Model returned input unchanged — showing no-change toast")
                        Picker.showToast("✓ No change needed")
                        return
                    }

                    self.lastRefinedText = refined

                    if let focusedElement, Selection.writeSelectedText(refined, to: focusedElement) {
                        log("Replaced selection via Accessibility")
                        return
                    }

                    log("Accessibility replacement unavailable; pasting via clipboard")
                    Clipboard.paste(refined, into: sourceApp)
                    Picker.showToast("✓ Pasted")
                }
            }
        }
    }

    private func fail(_ title: String, detail: String) {
        Picker.showToast(title, duration: 1.6)
        log("\(title): \(detail)")
        isProcessing = false
    }

    /// Order-out any Penny window that could steal focus from the source app
    /// while we're in the middle of a refinement. Calling `orderOut` keeps
    /// the window controller alive so the user can re-open the window later
    /// from the menu bar without losing state.
    private func hideOurWindows() {
        preferences?.window?.orderOut(nil)
        onboarding?.window?.orderOut(nil)
    }
}

// When running inside a real .app bundle (the production install at
// /Applications/Penny.app), all resources live in Contents/Resources.
// When running as a bare CLI for dev (`./PennyNative <repo> <python>`),
// the two arguments override.
let args = CommandLine.arguments
let appDir: String
let pythonPath: String
if let resources = Bundle.main.resourcePath,
   FileManager.default.fileExists(atPath: "\(resources)/refiner_cli.py") {
    appDir = resources
    pythonPath = "\(NSHomeDirectory())/.penny/env/bin/python3"
} else if args.count > 2 {
    appDir = args[1]
    pythonPath = args[2]
} else {
    appDir = FileManager.default.currentDirectoryPath
    pythonPath = "\(NSHomeDirectory())/.penny/env/bin/python3"
}

// Singleton check: macOS Launch Services normally activates the existing
// instance instead of spawning a duplicate, but launchd + a manual launch
// can race. If another copy of this bundle is already running, exit quietly.
if let bundleId = Bundle.main.bundleIdentifier {
    let others = NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == bundleId && $0.processIdentifier != getpid()
    }
    if !others.isEmpty {
        log("Another instance (pid=\(others.first!.processIdentifier)) is already running. Exiting.")
        exit(0)
    }
}

let scriptPath = "\(appDir)/refiner_cli.py"
let helper = RefinerHelper(pythonPath: pythonPath, scriptPath: scriptPath)
let app = NSApplication.shared

// Hold the delegate strongly. `NSApp.delegate` is `weak` in AppKit, so a
// local `let` here can be released by the optimizer the moment we hand it
// off, leaving `applicationDidFinishLaunching` to never fire. Park it in a
// module-level container.
enum DelegateBox {
    static var instance: AppDelegate?
}
DelegateBox.instance = AppDelegate(helper: helper, appDir: appDir)
app.delegate = DelegateBox.instance
app.run()
