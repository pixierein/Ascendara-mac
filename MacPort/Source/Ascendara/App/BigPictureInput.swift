import AppKit
import Combine
import GameController

enum BigPictureAction { case Left, Right, Up, Down, Activate, Back, Menu, PreviousPage, NextPage }

@MainActor
final class BigPictureInput: ObservableObject {
    private weak var Window: NSWindow?
    private var Action: ((BigPictureAction) -> Bool)?
    private var EventMonitor: Any?
    private var Observers: [NSObjectProtocol] = []
    private var ControllerCleanup: [ObjectIdentifier: () -> Void] = [:]
    private var ControllerSources: [ObjectIdentifier: [ObjectIdentifier]] = [:]
    private var Directions: [ObjectIdentifier: BigPictureAction] = [:]
    private var TrackingMenus: Set<ObjectIdentifier> = []
    private var HeldSource: ObjectIdentifier?
    private var RepeatTask: Task<Void, Never>?
    private var Generation = UUID()

    deinit {
        RepeatTask?.cancel()
        if let EventMonitor { NSEvent.removeMonitor(EventMonitor) }
        for Observer in Observers { NotificationCenter.default.removeObserver(Observer) }
        for Cleanup in ControllerCleanup.values { Cleanup() }
    }

    func Start(Window: NSWindow?, Action: @escaping (BigPictureAction) -> Bool) {
        if let Window, self.Window === Window, EventMonitor != nil {
            self.Action = Action
            return
        }
        Stop()
        guard let Window else { return }
        self.Window = Window
        self.Action = Action
        EventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] Event in
            let Handled = MainActor.assumeIsolated { self?.HandleKey(Event) ?? false }
            return Handled ? nil : Event
        }
        let Connected = NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] Notification in
            guard let Controller = Notification.object as? GCController else { return }
            Task { @MainActor in self?.Connect(Controller) }
        }
        let Disconnected = NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] Notification in
            guard let Controller = Notification.object as? GCController else { return }
            Task { @MainActor in self?.Disconnect(Controller) }
        }
        let Resigned = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: Window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ReleaseDirections() }
        }
        let MenuOpened = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] Notification in
            guard let Menu = Notification.object as? NSMenu else { return }
            MainActor.assumeIsolated {
                guard let self, self.CanHandle else { return }
                self.TrackingMenus.insert(ObjectIdentifier(Menu))
                self.ReleaseDirections()
            }
        }
        let MenuClosed = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] Notification in
            guard let Menu = Notification.object as? NSMenu else { return }
            MainActor.assumeIsolated { _ = self?.TrackingMenus.remove(ObjectIdentifier(Menu)) }
        }
        Observers = [Connected, Disconnected, Resigned, MenuOpened, MenuClosed]
        for Controller in GCController.controllers() { Connect(Controller) }
    }

    func Stop() {
        Generation = UUID()
        ReleaseDirections()
        if let EventMonitor { NSEvent.removeMonitor(EventMonitor) }
        EventMonitor = nil
        for Observer in Observers { NotificationCenter.default.removeObserver(Observer) }
        Observers.removeAll()
        for Cleanup in ControllerCleanup.values { Cleanup() }
        ControllerCleanup.removeAll()
        ControllerSources.removeAll()
        TrackingMenus.removeAll()
        Window = nil
        Action = nil
    }

    private var CanHandle: Bool {
        Action != nil && NSApp.isActive && ActiveWindow?.isKeyWindow == true && NSApp.modalWindow == nil
    }

    private var ActiveWindow: NSWindow? {
        guard var Active = Window else { return nil }
        while let Sheet = Active.attachedSheet {
            if Sheet is NSSavePanel { return nil }
            Active = Sheet
        }
        return Active
    }

    private var IsEditing: Bool {
        (ActiveWindow?.firstResponder as? NSTextView)?.isEditable == true
    }

    private func HandleKey(_ Event: NSEvent) -> Bool {
        guard CanHandle, TrackingMenus.isEmpty, Event.window === ActiveWindow,
              Event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        if IsEditing {
            guard Event.keyCode == 53 else { return false }
            if !Event.isARepeat { ActiveWindow?.makeFirstResponder(nil) }
            return true
        }
        let Requested: BigPictureAction
        switch Event.keyCode {
        case 123: Requested = .Left
        case 124: Requested = .Right
        case 126: Requested = .Up
        case 125: Requested = .Down
        case 36, 76:
            if Event.isARepeat { return true }
            Requested = .Activate
        case 53:
            if Event.isARepeat { return true }
            Requested = .Back
        case 48:
            if Event.isARepeat { return true }
            Requested = .Menu
        default: return false
        }
        return Action?(Requested) ?? false
    }

    private func Perform(_ Requested: BigPictureAction) -> Bool {
        guard CanHandle else { return false }
        if !TrackingMenus.isEmpty { return NavigateMenu(Requested) }
        if IsEditing {
            if Requested == .Back { ActiveWindow?.makeFirstResponder(nil); return true }
            guard Requested == .Menu else { return false }
            ActiveWindow?.makeFirstResponder(nil)
        }
        return Action?(Requested) ?? false
    }

    private func NavigateMenu(_ Requested: BigPictureAction) -> Bool {
        guard let Window = ActiveWindow else { return false }
        let Key: (UInt16, String)
        switch Requested {
        case .Left: Key = (123, "\u{f702}")
        case .Right: Key = (124, "\u{f703}")
        case .Up: Key = (126, "\u{f700}")
        case .Down: Key = (125, "\u{f701}")
        case .Activate: Key = (36, "\r")
        case .Back, .Menu: Key = (53, "\u{1b}")
        default: return false
        }
        for Type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let Event = NSEvent.keyEvent(with: Type, location: .zero, modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: Window.windowNumber, context: nil,
                                               characters: Key.1, charactersIgnoringModifiers: Key.1,
                                               isARepeat: false, keyCode: Key.0) else { return false }
            NSApp.postEvent(Event, atStart: false)
        }
        return true
    }

    private func Connect(_ Controller: GCController) {
        guard Window != nil, Action != nil else { return }
        let Id = ObjectIdentifier(Controller)
        guard ControllerCleanup[Id] == nil else { return }
        let CurrentGeneration = Generation
        var Cleanup: [() -> Void] = []
        var Sources: [ObjectIdentifier] = []

        func BindDirection(_ Pad: GCControllerDirectionPad) {
            let Source = ObjectIdentifier(Pad)
            Sources.append(Source)
            let Previous = Pad.valueChangedHandler
            Pad.valueChangedHandler = { [weak self] Pad, X, Y in
                Task { @MainActor in
                    guard let self, self.Generation == CurrentGeneration else {
                        Previous?(Pad, X, Y)
                        return
                    }
                    guard self.CanHandle else {
                        self.ReleaseDirections()
                        Previous?(Pad, X, Y)
                        return
                    }
                    self.Move(Source: Source, X: X, Y: Y)
                }
            }
            Cleanup.append { Pad.valueChangedHandler = Previous }
        }

        func BindButton(_ Button: GCControllerButtonInput, To Action: BigPictureAction) {
            let Previous = Button.pressedChangedHandler
            Button.pressedChangedHandler = { [weak self] Button, Value, Pressed in
                Task { @MainActor in
                    guard let self, self.Generation == CurrentGeneration, self.CanHandle else {
                        Previous?(Button, Value, Pressed)
                        return
                    }
                    if Pressed, !self.Perform(Action) { Previous?(Button, Value, Pressed) }
                }
            }
            Cleanup.append { Button.pressedChangedHandler = Previous }
        }

        if let Pad = Controller.extendedGamepad {
            BindDirection(Pad.dpad)
            BindDirection(Pad.leftThumbstick)
            BindButton(Pad.buttonA, To: .Activate)
            BindButton(Pad.buttonB, To: .Back)
            BindButton(Pad.buttonMenu, To: .Menu)
            BindButton(Pad.leftShoulder, To: .PreviousPage)
            BindButton(Pad.rightShoulder, To: .NextPage)
        } else if let Pad = Controller.microGamepad {
            BindDirection(Pad.dpad)
            BindButton(Pad.buttonA, To: .Activate)
            BindButton(Pad.buttonX, To: .Back)
            BindButton(Pad.buttonMenu, To: .Menu)
        }
        ControllerCleanup[Id] = { for Restore in Cleanup { Restore() } }
        ControllerSources[Id] = Sources
    }

    private func Disconnect(_ Controller: GCController) {
        let Id = ObjectIdentifier(Controller)
        ControllerCleanup.removeValue(forKey: Id)?()
        for Source in ControllerSources.removeValue(forKey: Id) ?? [] {
            Directions.removeValue(forKey: Source)
            if HeldSource == Source {
                RepeatTask?.cancel()
                RepeatTask = nil
                HeldSource = nil
            }
        }
    }

    private func Move(Source: ObjectIdentifier, X: Float, Y: Float) {
        let Previous = Directions[Source]
        let Magnitude = max(abs(X), abs(Y))
        let Direction: BigPictureAction?
        if Magnitude < 0.35 {
            Direction = nil
        } else if Magnitude < 0.55 {
            Direction = Previous
        } else if abs(X) >= abs(Y) {
            Direction = X > 0 ? .Right : .Left
        } else {
            Direction = Y > 0 ? .Up : .Down
        }
        guard Previous != Direction else { return }
        Directions[Source] = Direction
        guard let Direction else {
            if HeldSource == Source {
                RepeatTask?.cancel()
                RepeatTask = nil
                HeldSource = nil
            }
            return
        }
        RepeatTask?.cancel()
        HeldSource = Source
        _ = Perform(Direction)
        RepeatTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 360_000_000) } catch { return }
            while !Task.isCancelled {
                guard let self, self.CanHandle, self.HeldSource == Source, self.Directions[Source] == Direction else { return }
                _ = self.Perform(Direction)
                do { try await Task.sleep(nanoseconds: 140_000_000) } catch { return }
            }
        }
    }

    private func ReleaseDirections() {
        RepeatTask?.cancel()
        RepeatTask = nil
        HeldSource = nil
        Directions.removeAll()
    }
}
