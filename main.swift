import Cocoa
import SwiftUI
import CoreGraphics
import ApplicationServices
import ServiceManagement
import Combine

// MARK: - Trigger Modifier & Wheel Action Models

enum TriggerModifier: String, CaseIterable, Identifiable {
    case option  = "option"
    case control = "control"
    case command = "command"
    case shift   = "shift"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .option:  return "Option (⌥)"
        case .control: return "Control (⌃)"
        case .command: return "Command (⌘)"
        case .shift:   return "Shift (⇧)"
        }
    }

    var shortSymbol: String {
        switch self {
        case .option:  return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        case .shift:   return "⇧"
        }
    }

    var cgEventFlag: CGEventFlags {
        switch self {
        case .option:  return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        case .shift:   return .maskShift
        }
    }

    var virtualKeyCode: CGKeyCode {
        switch self {
        case .option:  return 0x3A // kVK_Option (58)
        case .control: return 0x3B // kVK_Control (59)
        case .command: return 0x37 // kVK_Command (55)
        case .shift:   return 0x38 // kVK_Shift (56)
        }
    }
}

enum FCPWheelAction {
    case timelineZoom
    case clipHeight

    var title: String {
        switch self {
        case .timelineZoom: return "Timeline Zoom"
        case .clipHeight:   return "Clip Height"
        }
    }

    var shortcutBadge: String {
        switch self {
        case .timelineZoom: return "⌘= / ⌘-"
        case .clipHeight:   return "⇧⌘= / ⇧⌘-"
        }
    }
}

// MARK: - Persistent Settings Store

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let bundleIdentifier = "com.mriynick.FCP-MX-Scroll"
    static let appName = "FCP-MX-Scroll"
    static let version = "2.1.0"

    static let targetBundleIDs: Set<String> = [
        "com.apple.FinalCut",
        "com.apple.FinalCutApp",
        "com.apple.FinalCutTrial"
    ]

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "isEnabled")
            ScrollInterceptor.shared.resetAccumulators()
            onStatusBarStateChange?()
        }
    }

    @Published var modifierKeyRaw: String {
        didSet {
            defaults.set(modifierKeyRaw, forKey: "modifierKey")
            ScrollInterceptor.shared.resetAccumulators()
        }
    }

    @Published var mainWheelSensitivity: Double {
        didSet {
            defaults.set(mainWheelSensitivity, forKey: "mainWheelSensitivity")
        }
    }

    @Published var sideWheelSensitivity: Double {
        didSet {
            defaults.set(sideWheelSensitivity, forKey: "sideWheelSensitivity")
        }
    }

    @Published var swapWheels: Bool {
        didSet {
            defaults.set(swapWheels, forKey: "swapWheels")
            ScrollInterceptor.shared.resetAccumulators()
        }
    }

    @Published var invertMainWheel: Bool {
        didSet {
            defaults.set(invertMainWheel, forKey: "invertMainWheel")
        }
    }

    @Published var invertSideWheel: Bool {
        didSet {
            defaults.set(invertSideWheel, forKey: "invertSideWheel")
        }
    }

    @Published var jumpToStartOnReturn: Bool {
        didSet {
            defaults.set(jumpToStartOnReturn, forKey: "jumpToStartOnReturn")
        }
    }

    @Published var launchAtLogin: Bool = false
    @Published var isAccessibilityGranted: Bool = false
    @Published var isEventTapActive: Bool = false
    @Published var isFinalCutFrontmost: Bool = false

    var onStatusBarStateChange: (() -> Void)?

    var triggerModifier: TriggerModifier {
        get { TriggerModifier(rawValue: modifierKeyRaw) ?? .option }
        set { modifierKeyRaw = newValue.rawValue }
    }

    var mainWheelAction: FCPWheelAction {
        swapWheels ? .clipHeight : .timelineZoom
    }

    var sideWheelAction: FCPWheelAction {
        swapWheels ? .timelineZoom : .clipHeight
    }

    /// Maps the 1.0...10.0 sensitivity slider to normalized point thresholds.
    /// Higher sensitivity -> smaller point threshold (more steps per rotation).
    /// Tuned specifically for MX Master 3S main MagSpeed wheel & side horizontal thumb wheel.
    var mainWheelThreshold: Double {
        let clamped = min(max(mainWheelSensitivity, 1.0), 10.0)
        // At default 5.0 -> 9.0 normalized points (~1 physical ratchet notch)
        // At 10.0 -> 2.1 points; At 1.0 -> 28.0 points
        return max(1.5, 9.0 * pow(1.33, 5.0 - clamped))
    }

    var sideWheelThreshold: Double {
        let clamped = min(max(sideWheelSensitivity, 1.0), 10.0)
        // At default 5.0 -> 7.0 normalized points for smooth thumb-wheel stepping
        // At 10.0 -> 1.6 points; At 1.0 -> 22.0 points
        return max(1.2, 7.0 * pow(1.33, 5.0 - clamped))
    }

    private init() {
        if defaults.object(forKey: "isEnabled") == nil {
            defaults.set(true, forKey: "isEnabled")
        }
        if defaults.object(forKey: "modifierKey") == nil {
            defaults.set(TriggerModifier.option.rawValue, forKey: "modifierKey")
        }
        if defaults.object(forKey: "mainWheelSensitivity") == nil {
            defaults.set(5.0, forKey: "mainWheelSensitivity")
        }
        if defaults.object(forKey: "sideWheelSensitivity") == nil {
            defaults.set(5.0, forKey: "sideWheelSensitivity")
        }
        if defaults.object(forKey: "swapWheels") == nil {
            defaults.set(false, forKey: "swapWheels")
        }
        if defaults.object(forKey: "jumpToStartOnReturn") == nil {
            defaults.set(true, forKey: "jumpToStartOnReturn")
        }

        self.isEnabled = defaults.bool(forKey: "isEnabled")
        self.modifierKeyRaw = defaults.string(forKey: "modifierKey") ?? TriggerModifier.option.rawValue
        let mainSens = defaults.double(forKey: "mainWheelSensitivity")
        self.mainWheelSensitivity = mainSens > 0 ? mainSens : 5.0
        let sideSens = defaults.double(forKey: "sideWheelSensitivity")
        self.sideWheelSensitivity = sideSens > 0 ? sideSens : 5.0
        self.swapWheels = defaults.bool(forKey: "swapWheels")
        self.invertMainWheel = defaults.bool(forKey: "invertMainWheel")
        self.invertSideWheel = defaults.bool(forKey: "invertSideWheel")
        self.jumpToStartOnReturn = defaults.bool(forKey: "jumpToStartOnReturn")

        refreshLaunchAtLoginStatus()
    }

    func resetToDefaults() {
        isEnabled = true
        modifierKeyRaw = TriggerModifier.option.rawValue
        mainWheelSensitivity = 5.0
        sideWheelSensitivity = 5.0
        swapWheels = false
        invertMainWheel = false
        invertSideWheel = false
        jumpToStartOnReturn = true
    }

    // MARK: Launch at Login (SMAppService.mainApp)

    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAgentCleanup.removeLegacyKeepAliveAgent()
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            if enabled {
                LaunchAgentCleanup.installRunAtLoadFallback()
            } else {
                LaunchAgentCleanup.removeLegacyKeepAliveAgent()
            }
        }
        refreshLaunchAtLoginStatus()
        if enabled && !launchAtLogin && FileManager.default.fileExists(atPath: LaunchAgentCleanup.launchAgentURL.path) {
            launchAtLogin = true
        }
    }

    func ensureInitialLoginRegistration() {
        LaunchAgentCleanup.removeLegacyKeepAliveAgent()
        if defaults.object(forKey: "hasConfiguredLoginItem") == nil {
            defaults.set(true, forKey: "hasConfiguredLoginItem")
            setLaunchAtLogin(true)
        } else {
            refreshLaunchAtLoginStatus()
        }
    }

    static func isFinalCutApp(_ app: NSRunningApplication?) -> Bool {
        guard let app = app else { return false }
        if let bundleID = app.bundleIdentifier {
            if targetBundleIDs.contains(bundleID) || bundleID.hasPrefix("com.apple.FinalCut") {
                return true
            }
        }
        if let name = app.localizedName, name.hasPrefix("Final Cut Pro") {
            return true
        }
        if let execURL = app.executableURL, execURL.lastPathComponent == "Final Cut Pro" {
            return true
        }
        return false
    }
}

// MARK: - Legacy LaunchAgent Cleanup

enum LaunchAgentCleanup {
    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(SettingsStore.bundleIdentifier).plist")
    }

    static func removeLegacyKeepAliveAgent() {
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try? FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    static func installRunAtLoadFallback() {
        let standardPath = "/Applications/\(SettingsStore.appName).app/Contents/MacOS/\(SettingsStore.appName)"
        let execPath = FileManager.default.fileExists(atPath: standardPath)
            ? standardPath
            : (Bundle.main.executablePath ?? standardPath)
        let plistDict: [String: Any] = [
            "Label": SettingsStore.bundleIdentifier,
            "ProgramArguments": [execPath],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        let dir = launchAgentURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0) {
            try? data.write(to: launchAgentURL, options: .atomic)
        }
    }
}

// MARK: - Accessibility Focus & Text-Editing Detector (Collision Protection)

enum TextInputCollisionGuard {
    /// Roles that indicate the user is actively interacting with a text field, editor, search box, or dialog
    private static let textEditingRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField",
        "AXWebArea"
    ]

    private static let modalWindowRoles: Set<String> = [
        "AXSheet",
        "AXDialog"
    ]

    /// Returns `true` if the user is currently typing in a text field, title editor, inspector field,
    /// renaming an item, or interacting with a modal sheet/dialog in Final Cut Pro.
    static func isTextEditingOrModalActive() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // 1. Check if a modal sheet or dialog window is active (so Return confirms dialogs normally)
        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
           let focusedWindow = focusedWindowRef {
            let winElement = focusedWindow as! AXUIElement
            if let role = copyStringAttribute(winElement, kAXRoleAttribute),
               modalWindowRoles.contains(role) {
                return true
            }
            if let subrole = copyStringAttribute(winElement, kAXSubroleAttribute),
               (subrole == "AXDialog" || subrole == "AXSystemDialog") {
                return true
            }
        }

        // 2. Obtain the currently focused UI element
        var focusedRef: CFTypeRef?
        var err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        if err != .success || focusedRef == nil {
            let systemWide = AXUIElementCreateSystemWide()
            err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        }

        guard err == .success, let unwrappedFocused = focusedRef else {
            // If we cannot inspect the focused element, err on the side of working in the timeline
            // only if Accessibility is trusted; if not trusted, pass through safely.
            return !AXIsProcessTrusted()
        }

        var currentElement: AXUIElement? = (unwrappedFocused as! AXUIElement)
        var depth = 0

        // Inspect the focused element and up to 2 ancestor levels (e.g. text cell inside table/outline row)
        while let element = currentElement, depth < 3 {
            if isElementTextEditable(element, isDirectFocus: depth == 0) {
                return true
            }

            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef {
                currentElement = (parent as! AXUIElement)
            } else {
                currentElement = nil
            }
            depth += 1
        }

        return false
    }

    private static func isElementTextEditable(_ element: AXUIElement, isDirectFocus: Bool) -> Bool {
        let role = copyStringAttribute(element, kAXRoleAttribute) ?? ""
        if textEditingRoles.contains(role) {
            return true
        }
        if modalWindowRoles.contains(role) {
            return true
        }

        if let subrole = copyStringAttribute(element, kAXSubroleAttribute) {
            if subrole.contains("TextField") || subrole.contains("SearchField") || subrole.contains("Dialog") {
                return true
            }
        }

        // Check explicit AXEditable attribute (used by Final Cut Pro Title/Text Canvas & Inspector fields)
        var editableRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableRef) == .success,
           let isEditable = editableRef as? Bool, isEditable {
            return true
        }

        if isDirectFocus {
            // If the directly focused element has an active text insertion caret (kAXSelectedTextRangeAttribute)
            // or is an editable AXStaticText (e.g. inline clip rename in Browser/Timeline), treat as text editing.
            var selectedRangeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
               selectedRangeRef != nil {
                return true
            }

            if role == "AXStaticText" {
                var settable = DarwinBoolean(false)
                if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
                   settable.boolValue {
                    return true
                }
            }
        }

        return false
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let str = valueRef as? String else {
            return nil
        }
        return str
    }
}

// MARK: - Scroll & Key Event Interceptor Engine

final class ScrollInterceptor {
    static let shared = ScrollInterceptor()

    /// Virtual Key Codes (<Carbon/HIToolbox/Events.h>)
    private static let kVK_UpArrow: CGKeyCode          = 0x7E // 126
    private static let kVK_DownArrow: CGKeyCode        = 0x7D // 125
    private static let kVK_ANSI_Equal: CGKeyCode       = 0x18 // 24 ('=' / '+')
    private static let kVK_ANSI_Minus: CGKeyCode       = 0x1B // 27 ('-' / '_')
    private static let kVK_Return: CGKeyCode           = 0x24 // 36 (Return)
    private static let kVK_ANSI_KeypadEnter: CGKeyCode = 0x4C // 76 (Keypad Enter)
    private static let kVK_Home: CGKeyCode             = 0x73 // 115 (Fn + Left Arrow / Home)
    private static let kVK_Command: CGKeyCode          = 0x37 // 55
    private static let kVK_Shift: CGKeyCode            = 0x38 // 56

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var monitorTimer: Timer?

    /// Cached frontmost state updated via NSWorkspace notifications
    private var cachedIsFinalCutActive: Bool = false

    /// High-resolution scroll accumulators (MX Master 3S Main & Side wheels)
    private var accMainY: Double = 0.0
    private var accSideX: Double = 0.0
    private var lastScrollTimeY: TimeInterval = 0.0
    private var lastScrollTimeX: TimeInterval = 0.0
    private var lastFireTimeY: TimeInterval = 0.0
    private var lastFireTimeX: TimeInterval = 0.0

    /// Tracks whether we consumed a Return/Enter keyDown so its matching keyUp is also consumed cleanly
    private var consumedReturnKeyDown: Bool = false

    private let idleResetTimeout: TimeInterval = 0.250

    private init() {
        updateFrontmostApp(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleAppActivation(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            ?? NSWorkspace.shared.frontmostApplication
        updateFrontmostApp(app)
    }

    private func updateFrontmostApp(_ app: NSRunningApplication?) {
        let isFCP = SettingsStore.isFinalCutApp(app)
        cachedIsFinalCutActive = isFCP
        if Thread.isMainThread {
            SettingsStore.shared.isFinalCutFrontmost = isFCP
        } else {
            DispatchQueue.main.async {
                SettingsStore.shared.isFinalCutFrontmost = isFCP
            }
        }
        if !isFCP {
            resetAccumulators()
            consumedReturnKeyDown = false
        }
    }

    private func checkIsFinalCutFrontmost() -> Bool {
        if cachedIsFinalCutActive {
            return true
        }
        if SettingsStore.isFinalCutApp(NSWorkspace.shared.frontmostApplication) {
            cachedIsFinalCutActive = true
            return true
        }
        return false
    }

    func resetAccumulators() {
        accMainY = 0.0
        accSideX = 0.0
    }

    private func persistDiagnosticStatus(trusted: Bool, tapActive: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(trusted, forKey: "StatusTrusted")
        defaults.set(tapActive, forKey: "StatusTapActive")
        defaults.set(Int(ProcessInfo.processInfo.processIdentifier), forKey: "StatusPID")
    }

    // MARK: Accessibility & Event Tap Lifecycle

    func start() {
        let trusted = AXIsProcessTrusted()
        if trusted {
            _ = installEventTap()
        } else {
            requestAccessibilityAndReload(openSettings: false)
        }
        updatePublishedTrustState()

        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkHealthAndTrust()
        }
    }

    func requestAccessibilityAndReload(openSettings: Bool = true) {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted && openSettings {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }

        reloadEventTap()
    }

    func reloadEventTap() {
        teardownEventTap()
        if AXIsProcessTrusted() {
            _ = installEventTap()
        }
        updatePublishedTrustState()
    }

    private func checkHealthAndTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted && eventTap == nil {
            _ = installEventTap()
        } else if !trusted && eventTap != nil {
            teardownEventTap()
        } else if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        updatePublishedTrustState()
    }

    private func updatePublishedTrustState() {
        let trusted = AXIsProcessTrusted()
        let tapActive = (eventTap != nil) && (eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false)
        persistDiagnosticStatus(trusted: trusted, tapActive: tapActive)

        let store = SettingsStore.shared
        if store.isAccessibilityGranted != trusted || store.isEventTapActive != tapActive {
            store.isAccessibilityGranted = trusted
            store.isEventTapActive = tapActive
            store.onStatusBarStateChange?()
        }
    }

    private func teardownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    @discardableResult
    private func installEventTap() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = CGEventMask(
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) ?? CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: userInfo
        )

        guard let createdTap = tap else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)

        self.eventTap = createdTap
        self.runLoopSource = source
        return true
    }

    // MARK: Master CGEventTap Dispatcher

    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            resetAccumulators()
            return Unmanaged.passUnretained(event)
        }

        let store = SettingsStore.shared
        guard store.isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .scrollWheel:
            return handleScrollWheelEvent(event, store: store)
        case .keyDown, .keyUp:
            return handleKeyboardEvent(event, type: type, store: store)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: Return / Enter -> Jump to Start (Fn + Left Arrow / Home)

    private func handleKeyboardEvent(
        _ event: CGEvent,
        type: CGEventType,
        store: SettingsStore
    ) -> Unmanaged<CGEvent>? {
        guard store.jumpToStartOnReturn else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == Self.kVK_Return || keyCode == Self.kVK_ANSI_KeypadEnter else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            if consumedReturnKeyDown {
                consumedReturnKeyDown = false
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Ignore if any primary modifier (Command, Option, Control, Shift) is held
        let primaryModifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
        guard event.flags.intersection(primaryModifiers).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        // Only intercept when Final Cut Pro is frontmost
        guard checkIsFinalCutFrontmost() else {
            return Unmanaged.passUnretained(event)
        }

        // Collision protection: pass Return/Enter through untouched if editing text or in a modal dialog
        if TextInputCollisionGuard.isTextEditingOrModalActive() {
            return Unmanaged.passUnretained(event)
        }

        consumedReturnKeyDown = true

        // Only trigger once on initial key press (skip key auto-repeats)
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isAutorepeat {
            synthesizeHomeKey()
        }

        return nil
    }

    private func synthesizeHomeKey() {
        guard let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.kVK_Home, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.kVK_Home, keyDown: false) else {
            return
        }

        // Home (Fn + Left Arrow, keyCode 115) carries .maskSecondaryFn on macOS
        keyDown.flags = [.maskSecondaryFn]
        keyUp.flags = [.maskSecondaryFn]

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    // MARK: Scroll Interception (MX Master 3S Main & Side Wheels)

    private func handleScrollWheelEvent(
        _ event: CGEvent,
        store: SettingsStore
    ) -> Unmanaged<CGEvent>? {
        // Tier 1 Fast-Path: Check if the user's chosen Trigger Modifier is held
        let requiredModifier = store.triggerModifier
        let targetFlag = requiredModifier.cgEventFlag
        let primaryModifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]

        var activeMods = event.flags.intersection(primaryModifiers)
        if activeMods.isEmpty {
            let sessionFlags = CGEventSource.flagsState(.combinedSessionState)
            activeMods = sessionFlags.intersection(primaryModifiers)
        }

        guard activeMods == targetFlag else {
            resetAccumulators()
            return Unmanaged.passUnretained(event)
        }

        // Tier 2 Fast-Path: Activate ONLY when Final Cut Pro is frontmost
        guard checkIsFinalCutFrontmost() else {
            return Unmanaged.passUnretained(event)
        }

        // Extract normalized point deltas for Axis 1 (Main Vertical Wheel) and Axis 2 (Side Thumb Wheel)
        // Notes on CoreGraphics units:
        // - `PointDeltaAxis` (getIntegerValueField) is in integer points/pixels (~10 pt per line)
        // - `FixedPtDeltaAxis` (getDoubleValueField) is in 16.16 fixed-point lines -> multiply by 10.0 to convert to points!
        // - `DeltaAxis` (getIntegerValueField) is in integer lines -> multiply by 10.0 to convert to points!
        var dy = extractNormalizedPoints(
            event: event,
            ptField: .scrollWheelEventPointDeltaAxis1,
            fixedField: .scrollWheelEventFixedPtDeltaAxis1,
            lineField: .scrollWheelEventDeltaAxis1
        )
        var dx = extractNormalizedPoints(
            event: event,
            ptField: .scrollWheelEventPointDeltaAxis2,
            fixedField: .scrollWheelEventFixedPtDeltaAxis2,
            lineField: .scrollWheelEventDeltaAxis2
        )

        if store.invertMainWheel { dy = -dy }
        if store.invertSideWheel { dx = -dx }

        let now = CFAbsoluteTimeGetCurrent()

        if abs(dy) >= abs(dx) && abs(dy) > 0.001 {
            processWheelDelta(
                delta: dy,
                now: now,
                accumulator: &accMainY,
                lastScrollTime: &lastScrollTimeY,
                lastFireTime: &lastFireTimeY,
                threshold: store.mainWheelThreshold,
                action: store.mainWheelAction,
                heldModifier: requiredModifier
            )
        } else if abs(dx) > 0.001 {
            processWheelDelta(
                delta: dx,
                now: now,
                accumulator: &accSideX,
                lastScrollTime: &lastScrollTimeX,
                lastFireTime: &lastFireTimeX,
                threshold: store.sideWheelThreshold,
                action: store.sideWheelAction,
                heldModifier: requiredModifier
            )
        }

        // Always consume modified scroll events in Final Cut Pro so the timeline never scrolls simultaneously
        return nil
    }

    private func extractNormalizedPoints(
        event: CGEvent,
        ptField: CGEventField,
        fixedField: CGEventField,
        lineField: CGEventField
    ) -> Double {
        let ptPixels = Double(event.getIntegerValueField(ptField))
        let fixedPoints = event.getDoubleValueField(fixedField) * 10.0
        let linePoints = Double(event.getIntegerValueField(lineField)) * 10.0

        // Choose the highest-precision non-zero representation in normalized point units (10 pt = 1 line)
        let bestContinuous = (abs(fixedPoints) >= abs(ptPixels)) ? fixedPoints : ptPixels
        if abs(bestContinuous) > 0.01 {
            return bestContinuous
        }
        if abs(linePoints) > 0.01 {
            return linePoints
        }
        return 0.0
    }

    private func processWheelDelta(
        delta: Double,
        now: TimeInterval,
        accumulator: inout Double,
        lastScrollTime: inout TimeInterval,
        lastFireTime: inout TimeInterval,
        threshold: Double,
        action: FCPWheelAction,
        heldModifier: TriggerModifier
    ) {
        let isNewGesture = (now - lastScrollTime) > idleResetTimeout
        let isDirectionReversed = (accumulator != 0 && (accumulator > 0) != (delta > 0))
        lastScrollTime = now

        // Rate-limit cooldown prevents single-notch smooth-scroll bursts from double-stepping
        // and keeps continuous scrolling smooth without flooding Final Cut Pro.
        let cooldown: TimeInterval = (action == .clipHeight) ? 0.065 : 0.045
        if (now - lastFireTime) < cooldown && !isDirectionReversed {
            // Drain residual smooth-scroll tail ticks from the notch that just fired
            return
        }

        if isNewGesture || isDirectionReversed {
            // Prime a fresh scroll gesture so the very first physical notch/thumb-nudge
            // responds promptly while still scaling with the sensitivity slider.
            let primeBoost = min(threshold * 0.55, 4.5)
            accumulator = delta + copysign(primeBoost, delta)
        } else {
            accumulator += delta
        }

        guard abs(accumulator) >= threshold else { return }

        lastFireTime = now
        let isPositive = (accumulator > 0)
        triggerAction(action, positiveDirection: isPositive, heldModifier: heldModifier)

        // Reset accumulator to 0 after each fired shortcut so trailing sub-packets of a
        // single notch never carry over into an unintended double-step.
        accumulator = 0.0
    }

    private func triggerAction(_ action: FCPWheelAction, positiveDirection: Bool, heldModifier: TriggerModifier) {
        switch action {
        case .timelineZoom:
            if positiveDirection {
                // Zoom In: Command + =
                synthesizeKeyShortcut(
                    keyCode: Self.kVK_ANSI_Equal,
                    modifiers: [.maskCommand],
                    isArrowKey: false,
                    heldModifier: heldModifier
                )
            } else {
                // Zoom Out: Command + -
                synthesizeKeyShortcut(
                    keyCode: Self.kVK_ANSI_Minus,
                    modifiers: [.maskCommand],
                    isArrowKey: false,
                    heldModifier: heldModifier
                )
            }
        case .clipHeight:
            if positiveDirection {
                // Increase Clip Height: Command + Shift + = (0x18)
                synthesizeKeyShortcut(
                    keyCode: Self.kVK_ANSI_Equal,
                    modifiers: [.maskCommand, .maskShift],
                    isArrowKey: false,
                    heldModifier: heldModifier
                )
            } else {
                // Decrease Clip Height: Command + Shift + - (0x1B)
                synthesizeKeyShortcut(
                    keyCode: Self.kVK_ANSI_Minus,
                    modifiers: [.maskCommand, .maskShift],
                    isArrowKey: false,
                    heldModifier: heldModifier
                )
            }
        }
    }

    // MARK: Keyboard Shortcut Synthesis (Full Modifier Transition + Arrow Flags)

    private func synthesizeKeyShortcut(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        isArrowKey: Bool,
        heldModifier: TriggerModifier
    ) {
        guard let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        var currentFlags: CGEventFlags = []

        // 1. Release the physically held trigger modifier if it is not part of the target shortcut
        if !modifiers.contains(heldModifier.cgEventFlag) {
            postFlagsChanged(source: source, virtualKey: heldModifier.virtualKeyCode, flags: currentFlags)
        } else {
            currentFlags.insert(heldModifier.cgEventFlag)
        }

        // 2. Press Command (0x37) if required
        if modifiers.contains(.maskCommand) && !currentFlags.contains(.maskCommand) {
            currentFlags.insert(.maskCommand)
            postFlagsChanged(source: source, virtualKey: Self.kVK_Command, flags: currentFlags)
        }

        // 3. Press Shift (0x38) if required (essential for Command + Shift + Up/Down Arrow Clip Height!)
        if modifiers.contains(.maskShift) && !currentFlags.contains(.maskShift) {
            currentFlags.insert(.maskShift)
            postFlagsChanged(source: source, virtualKey: Self.kVK_Shift, flags: currentFlags)
        }

        // 4. Construct exact key flags (including .maskNumericPad & .maskSecondaryFn for Arrow keys)
        var keyFlags = modifiers
        if isArrowKey {
            keyFlags.insert([.maskNumericPad, .maskSecondaryFn])
        }
        keyDown.flags = keyFlags
        keyUp.flags = keyFlags

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        // 5. Release Shift (0x38) if it was pressed synthetically
        if modifiers.contains(.maskShift) && heldModifier != .shift {
            currentFlags.remove(.maskShift)
            postFlagsChanged(source: source, virtualKey: Self.kVK_Shift, flags: currentFlags)
        }

        // 6. Release Command (0x37) if it was pressed synthetically
        if modifiers.contains(.maskCommand) && heldModifier != .command {
            currentFlags.remove(.maskCommand)
            postFlagsChanged(source: source, virtualKey: Self.kVK_Command, flags: currentFlags)
        }

        // 7. Restore the physically held trigger modifier so continuous scrolling keeps working
        if !currentFlags.contains(heldModifier.cgEventFlag) {
            postFlagsChanged(source: source, virtualKey: heldModifier.virtualKeyCode, flags: heldModifier.cgEventFlag)
        }
    }

    private func postFlagsChanged(source: CGEventSource, virtualKey: CGKeyCode, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true) else {
            return
        }
        event.type = .flagsChanged
        event.flags = flags
        event.post(tap: .cgSessionEventTap)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let interceptor = Unmanaged<ScrollInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    return interceptor.handleEvent(proxy: proxy, type: type, event: event)
}

// MARK: - Compact SwiftUI Menu Bar Settings View

struct SettingsPopoverView: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Header & Master Enable/Disable Switch
            HStack(spacing: 9) {
                Image(systemName: store.isEnabled ? "computermouse.fill" : "computermouse")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(store.isEnabled ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("FCP MX Scroll")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(statusSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $store.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            // 2. Live Accessibility Status Indicator & Reload Button
            HStack(spacing: 7) {
                Circle()
                    .fill(store.isAccessibilityGranted && store.isEventTapActive ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)

                Text(store.isAccessibilityGranted ? "Accessibility: Granted" : "Accessibility: Not Granted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(store.isAccessibilityGranted ? .primary : .orange)

                Spacer()

                Button(action: {
                    ScrollInterceptor.shared.requestAccessibilityAndReload(openSettings: !store.isAccessibilityGranted)
                }) {
                    Text(store.isAccessibilityGranted ? "Reload Tap" : "Grant Access")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            // 3. Compact Native Dropdown Modifier Key Picker & Swap Wheels Toggle
            HStack(spacing: 8) {
                Text("Trigger Modifier")
                    .font(.system(size: 11.5, weight: .medium))

                Spacer()

                Picker("", selection: Binding(
                    get: { store.triggerModifier },
                    set: { store.triggerModifier = $0 }
                )) {
                    ForEach(TriggerModifier.allCases) { mod in
                        Text(mod.menuTitle).tag(mod)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 130)
            }

            Divider()

            // 4. Wheel Mapping & Sensitivity Cards
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Wheel Mapping & Sensitivity")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("Swap Main & Side Wheels", isOn: $store.swapWheels)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, weight: .medium))
                }

                wheelControlCard(
                    wheelTitle: "\(store.triggerModifier.shortSymbol) + Main Wheel (Vertical)",
                    action: store.mainWheelAction,
                    sensitivity: $store.mainWheelSensitivity,
                    invertBinding: $store.invertMainWheel
                )

                wheelControlCard(
                    wheelTitle: "\(store.triggerModifier.shortSymbol) + Side Wheel (Thumb)",
                    action: store.sideWheelAction,
                    sensitivity: $store.sideWheelSensitivity,
                    invertBinding: $store.invertSideWheel
                )
            }

            Divider()

            // 5. Logic Pro Style Return / Enter -> Jump to Start of Timeline
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Jump to Start on Return / Enter (Logic Pro style)", isOn: $store.jumpToStartOnReturn)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5, weight: .medium))
                Text("Sends Fn + ← (Home) in timeline; disabled while editing text")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.leading, 18)
            }

            Divider()

            // 6. Launch at Login & Footer Controls
            HStack {
                Toggle("Launch at Login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

                Spacer()

                Button("Reset") {
                    store.resetToDefaults()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("q", modifiers: [.command])
            }
        }
        .padding(12)
        .frame(width: 325)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            store.refreshLaunchAtLoginStatus()
        }
    }

    private var statusSubtitle: String {
        if !store.isEnabled {
            return "Paused — All events pass through"
        }
        if !store.isAccessibilityGranted {
            return "Waiting for Accessibility permission"
        }
        return "Active only in Final Cut Pro"
    }

    @ViewBuilder
    private func wheelControlCard(
        wheelTitle: String,
        action: FCPWheelAction,
        sensitivity: Binding<Double>,
        invertBinding: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(wheelTitle)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(action.title) (\(action.shortcutBadge))")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            HStack(spacing: 6) {
                Text("Sensitivity")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Slider(value: sensitivity, in: 1.0...10.0, step: 0.5)
                    .controlSize(.mini)
                Text(String(format: "%.1f", sensitivity.wrappedValue))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .trailing)
                Toggle("Invert", isOn: invertBinding)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - Menu Bar Controller & App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var activityToken: NSObjectProtocol?
    private var globalClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Real-time CGEventTap scroll and shortcut interception for Final Cut Pro"
        )

        SettingsStore.shared.ensureInitialLoginRegistration()
        setupStatusBarAndPopover()

        SettingsStore.shared.onStatusBarStateChange = { [weak self] in
            self?.updateStatusBarIcon()
        }

        ScrollInterceptor.shared.start()
        updateStatusBarIcon()
    }

    private func setupStatusBarAndPopover() {
        let hostingController = NSHostingController(rootView: SettingsPopoverView())
        hostingController.sizingOptions = [.preferredContentSize]

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "FCP MX Scroll — Final Cut Pro Helper"
        }
        self.statusItem = item
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        let store = SettingsStore.shared
        let symbolName: String
        if !store.isEnabled {
            symbolName = "computermouse"
        } else if !store.isAccessibilityGranted {
            symbolName = "exclamationmark.triangle"
        } else {
            symbolName = "computermouse.fill"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "FCP MX Scroll") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "FCP"
        }
        button.alphaValue = store.isEnabled ? 1.0 : 0.55
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            SettingsStore.shared.refreshLaunchAtLoginStatus()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()

            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}

// MARK: - Single-Instance & CLI Entry Point

private func terminateExistingInstances() {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: SettingsStore.bundleIdentifier)
    for app in running where app.processIdentifier != currentPID {
        app.terminate()
    }
}

private func handleCommandLineArgs() {
    let args = CommandLine.arguments
    guard args.count > 1 else { return }

    switch args[1] {
    case "--version", "-v":
        print("\(SettingsStore.appName) \(SettingsStore.version)")
        exit(0)
    case "--apply-icon":
        // Helper: FCP-MX-Scroll --apply-icon <icnsPath> <targetPath1> [<targetPath2> ...]
        guard args.count >= 4, let iconImage = NSImage(contentsOfFile: args[2]) else {
            fputs("Usage: --apply-icon <icnsPath> <targetPath...>\n", stderr)
            exit(1)
        }
        for targetPath in args.dropFirst(3) {
            let ok = NSWorkspace.shared.setIcon(iconImage, forFile: targetPath, options: [])
            print("Applied custom icon to \(targetPath): \(ok ? "OK" : "FAILED")")
        }
        exit(0)
    case "--status":
        let defaults = UserDefaults.standard
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: SettingsStore.bundleIdentifier)
        let isRunning = !running.isEmpty
        let trusted = AXIsProcessTrusted() || (isRunning && defaults.bool(forKey: "StatusTrusted"))
        let tapActive = isRunning && defaults.bool(forKey: "StatusTapActive")
        let fcpApps = NSWorkspace.shared.runningApplications.filter { SettingsStore.isFinalCutApp($0) }
        let store = SettingsStore.shared
        print("\(SettingsStore.appName) v\(SettingsStore.version)")
        print("  Enabled               : \(store.isEnabled ? "YES" : "NO")")
        print("  Accessibility Trusted : \(trusted ? "YES" : "NO (click menu bar icon -> Grant Access)")")
        print("  CGEventTap Active     : \(tapActive ? "YES" : "NO")")
        print("  Trigger Modifier      : \(store.triggerModifier.menuTitle)")
        print("  Swap Wheels           : \(store.swapWheels ? "ON" : "OFF")")
        print("  Main Wheel Action     : \(store.mainWheelAction.title) (\(store.mainWheelAction.shortcutBadge)) [Sensitivity: \(store.mainWheelSensitivity)]")
        print("  Side Wheel Action     : \(store.sideWheelAction.title) (\(store.sideWheelAction.shortcutBadge)) [Sensitivity: \(store.sideWheelSensitivity)]")
        print("  Return Jump to Start  : \(store.jumpToStartOnReturn ? "ON (Fn + Left Arrow / Home)" : "OFF")")
        print("  Launch at Login       : \(store.launchAtLogin ? "YES" : "NO")")
        print("  Running Instances     : \(running.map { $0.processIdentifier })")
        print("  Detected Running FCP  : \(fcpApps.map { "\($0.localizedName ?? "FCP") (\($0.bundleIdentifier ?? "?"))" })")
        exit(0)
    default:
        break
    }
}

handleCommandLineArgs()
terminateExistingInstances()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
