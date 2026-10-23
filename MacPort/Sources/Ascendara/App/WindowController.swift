import AppKit
import Combine
import SwiftUI

@MainActor
final class WindowController: ObservableObject {
    private(set) weak var Window: NSWindow?
    @Published private(set) var IsFullscreen = false
    @Published private(set) var IsZoomed = false
    @Published private(set) var IsKey = false
    private weak var SourceView: WindowDragView?
    private var Observers: [NSObjectProtocol] = []

    deinit {
        for Observer in Observers { NotificationCenter.default.removeObserver(Observer) }
    }

    func Close() { Window?.performClose(nil) }
    func Minimize() { Window?.performMiniaturize(nil) }

    func ToggleZoom() {
        guard let Window, !Window.styleMask.contains(.fullScreen) else { return }
        Window.performZoom(nil)
        Refresh()
    }

    func ToggleFullscreen() { Window?.toggleFullScreen(nil) }

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
    }

    fileprivate func Detach(_ View: WindowDragView) {
        guard SourceView === View else { return }
        RemoveObservers()
        SourceView = nil
        Window = nil
        PublishState()
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
            NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification
        ]
        for Name in Names {
            let Observer = NotificationCenter.default.addObserver(forName: Name, object: ObservedWindow, queue: .main) { [weak self, weak ObservedWindow] _ in
                Task { @MainActor in
                    guard let self, let ObservedWindow, self.Window === ObservedWindow else { return }
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
