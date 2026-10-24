import AppKit
import Combine
import SwiftUI

@MainActor
final class WindowController: ObservableObject {
    private(set) weak var Window: NSWindow?
    @Published private(set) var IsFullscreen = false
    @Published private(set) var IsZoomed = false
    @Published private(set) var IsKey = false
    @Published private(set) var IsBigPicture = false
    private weak var SourceView: WindowDragView?
    private weak var PreviousResponder: NSResponder?
    private var Observers: [NSObjectProtocol] = []
    private var FullscreenPhase: FullscreenTransition?
    private var OwnsFullscreen = false
    private var RestoringFullscreen = false
    private var TransitionWatch: Task<Void, Never>?
    private var TransitionId = UUID()

    private enum FullscreenTransition { case Entering, Exiting }

    deinit {
        TransitionWatch?.cancel()
        for Observer in Observers { NotificationCenter.default.removeObserver(Observer) }
    }

    func Close() { Window?.performClose(nil) }
    func Minimize() { Window?.performMiniaturize(nil) }

    func ToggleZoom() {
        guard let Window, !Window.styleMask.contains(.fullScreen) else { return }
        Window.performZoom(nil)
        Refresh()
    }

    func ToggleFullscreen() {
        guard FullscreenPhase == nil else { return }
        Window?.toggleFullScreen(nil)
    }

    func BeginBigPicture() {
        guard !IsBigPicture else { return }
        IsBigPicture = true
        if FullscreenPhase == .Exiting { RestoringFullscreen = true }
        PreviousResponder = Window?.firstResponder
        Window?.makeFirstResponder(nil)
        EnterBigPictureFullscreen()
    }

    func EndBigPicture() {
        if IsBigPicture { IsBigPicture = false }
        if let PreviousResponder {
            if let View = PreviousResponder as? NSView, View.window === Window {
                Window?.makeFirstResponder(View)
            }
            self.PreviousResponder = nil
        }
        guard OwnsFullscreen, FullscreenPhase == nil else { return }
        guard Window?.styleMask.contains(.fullScreen) == true else {
            OwnsFullscreen = false
            return
        }
        RestoringFullscreen = true
        ChangeFullscreen(.Exiting)
    }

    private func EnterBigPictureFullscreen() {
        guard IsBigPicture, let Window, FullscreenPhase == nil else { return }
        guard !Window.styleMask.contains(.fullScreen) else { return }
        OwnsFullscreen = true
        RestoringFullscreen = false
        ChangeFullscreen(.Entering)
    }

    private func ChangeFullscreen(_ Phase: FullscreenTransition) {
        guard let Window else { return }
        FullscreenPhase = Phase
        WatchTransition(Phase)
        Window.toggleFullScreen(nil)
    }

    private func WatchTransition(_ Phase: FullscreenTransition) {
        TransitionWatch?.cancel()
        let Id = UUID()
        TransitionId = Id
        TransitionWatch = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            guard let self, self.TransitionId == Id, self.FullscreenPhase == Phase else { return }
            let Fullscreen = self.Window?.styleMask.contains(.fullScreen) == true
            if Phase == .Entering && Fullscreen {
                self.FullscreenEntered()
            } else if Phase == .Exiting && !Fullscreen {
                self.FullscreenExited()
            } else {
                self.FullscreenPhase = nil
                self.OwnsFullscreen = false
                self.RestoringFullscreen = false
                self.Refresh()
            }
        }
    }

    private func FullscreenEntered() {
        TransitionWatch?.cancel()
        FullscreenPhase = nil
        if !IsBigPicture && OwnsFullscreen { EndBigPicture() }
    }

    private func FullscreenExited() {
        TransitionWatch?.cancel()
        let WasRestoring = RestoringFullscreen
        FullscreenPhase = nil
        RestoringFullscreen = false
        OwnsFullscreen = false
        if WasRestoring && IsBigPicture {
            EnterBigPictureFullscreen()
        } else if IsBigPicture {
            EndBigPicture()
        }
    }

    fileprivate func Bind(_ NewWindow: NSWindow?, From View: WindowDragView) {
        guard let NewWindow else { Detach(View); return }
        SourceView = View
        guard Window !== NewWindow else { return }
        RemoveObservers()
        Window = NewWindow
        var Style = NewWindow.styleMask
        Style.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        if NewWindow.styleMask != Style { NewWindow.styleMask = Style }
        var Behavior = NewWindow.collectionBehavior
        Behavior.remove([.fullScreenAuxiliary, .fullScreenNone])
        Behavior.insert(.fullScreenPrimary)
        if NewWindow.collectionBehavior != Behavior { NewWindow.collectionBehavior = Behavior }
        NewWindow.titleVisibility = .hidden
        NewWindow.titlebarAppearsTransparent = true
        NewWindow.titlebarSeparatorStyle = .none
        NewWindow.toolbar = nil
        NewWindow.isMovableByWindowBackground = false
        Observe(NewWindow)
        Refresh()
        Task { @MainActor [weak self] in self?.EnterBigPictureFullscreen() }
    }

    fileprivate func Detach(_ View: WindowDragView) {
        guard SourceView === View else { return }
        RemoveObservers()
        TransitionWatch?.cancel()
        FullscreenPhase = nil
        OwnsFullscreen = false
        RestoringFullscreen = false
        PreviousResponder = nil
        SourceView = nil
        Window = nil
        PublishState()
        Task { @MainActor [weak self] in
            guard let self, self.Window == nil else { return }
            if self.IsBigPicture { self.IsBigPicture = false }
        }
    }

    fileprivate func DoubleClick() {
        let Preference = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")?.lowercased()
        if Preference == "none" { return }
        if Preference == "minimize" || Preference == nil && UserDefaults.standard.bool(forKey: "AppleMiniaturizeOnDoubleClick") {
            Minimize()
        } else {
            ToggleZoom()
        }
    }

    private func Observe(_ ObservedWindow: NSWindow) {
        let Names: [Notification.Name] = [
            NSWindow.didResizeNotification, NSWindow.didMoveNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
            NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification
        ]
        for Name in Names {
            let Observer = NotificationCenter.default.addObserver(forName: Name, object: ObservedWindow, queue: .main) { [weak self, weak ObservedWindow] _ in
                Task { @MainActor in
                    guard let self, let ObservedWindow, self.Window === ObservedWindow else { return }
                    if Name == NSWindow.willEnterFullScreenNotification {
                        self.FullscreenPhase = .Entering
                        self.WatchTransition(.Entering)
                    } else if Name == NSWindow.didEnterFullScreenNotification {
                        self.FullscreenEntered()
                    } else if Name == NSWindow.willExitFullScreenNotification {
                        self.FullscreenPhase = .Exiting
                        self.WatchTransition(.Exiting)
                        if !self.RestoringFullscreen && self.IsBigPicture {
                            self.OwnsFullscreen = false
                            self.EndBigPicture()
                        }
                    } else if Name == NSWindow.didExitFullScreenNotification {
                        self.FullscreenExited()
                    }
                    self.Refresh()
                }
            }
            Observers.append(Observer)
        }
    }

    private func Refresh() {
        guard let Window else { return }
        for Button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let NativeButton = Window.standardWindowButton(Button) {
                NativeButton.isHidden = true
                NativeButton.setAccessibilityElement(false)
                NativeButton.setAccessibilityHidden(true)
            }
        }
        PublishState()
    }

    private func PublishState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let Fullscreen = self.Window?.styleMask.contains(.fullScreen) ?? false
            let Zoomed = self.Window?.isZoomed ?? false
            let Key = self.Window?.isKeyWindow ?? false
            if self.IsFullscreen != Fullscreen { self.IsFullscreen = Fullscreen }
            if self.IsZoomed != Zoomed { self.IsZoomed = Zoomed }
            if self.IsKey != Key { self.IsKey = Key }
        }
    }

    private func RemoveObservers() {
        for Observer in Observers { NotificationCenter.default.removeObserver(Observer) }
        Observers.removeAll()
    }
}

struct WindowDragArea: NSViewRepresentable {
    let Controller: WindowController

    func makeNSView(context Context: Context) -> WindowDragView {
        let View = WindowDragView(frame: .zero)
        View.Controller = Controller
        return View
    }

    func updateNSView(_ View: WindowDragView, context Context: Context) {
        if View.Controller !== Controller {
            View.Controller?.Detach(View)
            View.Controller = Controller
        }
        Controller.Bind(View.window, From: View)
    }

    static func dismantleNSView(_ View: WindowDragView, coordinator Coordinator: ()) {
        View.Controller?.Detach(View)
        View.Controller = nil
    }
}

final class WindowDragView: NSView {
    weak var Controller: WindowController?
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for Event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Controller?.Bind(window, From: self)
    }

    override func mouseDown(with Event: NSEvent) {
        guard let Window = window else { return }
        Controller?.Bind(Window, From: self)
        if Event.clickCount == 2 {
            Controller?.DoubleClick()
        } else {
            Window.performDrag(with: Event)
        }
    }
}
