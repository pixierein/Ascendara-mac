import AppKit
import Combine
import SwiftUI

@MainActor
final class BigPictureFocus: ObservableObject {
    @Published private(set) var Frame: CGRect?
    private weak var Area: BigPictureFocusView?
    private weak var TargetWindow: NSWindow?
    private weak var SheetRing: BigPictureFocusRing?
    private var Selected: FocusTarget?
    private var ScrollElements: [NSAccessibilityProtocol] = []
    private var ScrollTask: Task<Void, Never>?

    private struct FocusTarget {
        let Element: NSAccessibilityProtocol
        let Rect: CGRect
        let Role: NSAccessibility.Role
    }

    @MainActor private struct FocusScope {
        let Window: NSWindow
        let View: NSView
        let IsSheet: Bool
        var Bounds: CGRect { View.bounds }
        var ScreenBounds: CGRect { Window.convertToScreen(View.convert(View.bounds, to: nil)) }
    }

    var HasSheet: Bool { Scope()?.IsSheet == true }

    deinit { ScrollTask?.cancel() }

    func Reset() {
        ScrollTask?.cancel()
        ScrollTask = nil
        Selected = nil
        ScrollElements.removeAll()
        TargetWindow = nil
        SheetRing?.removeFromSuperview()
        SheetRing = nil
        if Frame != nil { Frame = nil }
    }

    func Handle(_ Action: BigPictureAction) -> Bool {
        guard let Scope = Scope(), Scope.Window.isKeyWindow, NSApp.modalWindow == nil else { return false }
        if TargetWindow !== Scope.Window {
            Reset()
            TargetWindow = Scope.Window
        }
        if Scope.IsSheet {
            if Action == .Back { return CancelSheet(Scope) }
            if [.Menu, .PreviousPage, .NextPage].contains(Action) { return true }
        }
        guard [.Left, .Right, .Up, .Down, .Activate].contains(Action) else { return false }
        if ScrollTask != nil { return true }
        let Targets = Scan(Scope)
        let Current = Targets.first { Target in
            guard let Selected else { return false }
            return Target.Element === Selected.Element
        }
        guard let Current else {
            guard let First = Targets.first else { return Scroll(Action, In: Scope, From: nil) }
            Select(First, In: Scope)
            return true
        }
        Select(Current, In: Scope)
        if Action == .Activate { return Activate(Current, In: Scope) }
        if Current.Role == .slider || Current.Role == .incrementor {
            if Action == .Right, Current.Element.accessibilityPerformIncrement() { return true }
            if Action == .Left, Current.Element.accessibilityPerformDecrement() { return true }
        }
        if let Next = Nearest(Targets, From: Current, Toward: Action) {
            Select(Next, In: Scope)
            return true
        }
        return Scroll(Action, In: Scope, From: Current.Rect)
    }

    fileprivate func Bind(_ View: BigPictureFocusView) {
        guard Area !== View else { return }
        Area = View
    }

    fileprivate func Detach(_ View: BigPictureFocusView) {
        guard Area === View else { return }
        Area = nil
        Task { @MainActor [weak self] in
            guard let self, self.Area == nil else { return }
            self.Reset()
        }
    }

    fileprivate func RefreshFrame() {
        guard let Scope = Scope(), let Selected, Scope.Window === TargetWindow else { return }
        let Rect = LocalRect(Selected.Element.accessibilityFrame(), In: Scope).intersection(Scope.Bounds)
        guard !Rect.isNull, Rect.width > 2, Rect.height > 2, !Selected.Element.isAccessibilityHidden() else {
            Publish(nil, In: Scope)
            return
        }
        Publish(Rect, In: Scope)
    }

    private func Scope() -> FocusScope? {
        guard let Area, let Window = Area.window else { return nil }
        var Active = Window
        while let Sheet = Active.attachedSheet {
            if Sheet is NSSavePanel { return nil }
            Active = Sheet
        }
        guard let Content = Active.contentView else { return nil }
        return FocusScope(Window: Active, View: Active === Window ? Area : Content, IsSheet: Active !== Window)
    }

    private func LocalRect(_ ScreenRect: CGRect, In Scope: FocusScope) -> CGRect {
        let Rect = Scope.View.convert(Scope.Window.convertFromScreen(ScreenRect), from: nil)
        guard !Scope.View.isFlipped else { return Rect }
        return CGRect(x: Rect.minX, y: Scope.Bounds.minY + Scope.Bounds.maxY - Rect.maxY,
                      width: Rect.width, height: Rect.height)
    }

    private func Scan(_ Scope: FocusScope) -> [FocusTarget] {
        ScrollElements.removeAll()
        let Roles: Set<NSAccessibility.Role> = [.button, .checkBox, .radioButton, .textField, .textArea,
                                               .comboBox, .popUpButton, .menuButton, .slider, .link,
                                               .incrementor, .disclosureTriangle]
        var Queue: [(NSAccessibilityProtocol, CGRect, Int)] = [(Scope.Window, Scope.ScreenBounds, 0)]
        var Seen: Set<ObjectIdentifier> = []
        var Targets: [FocusTarget] = []
        var Index = 0
        while Index < Queue.count && Index < 2_000 {
            let (Element, Clip, Depth) = Queue[Index]
            Index += 1
            guard Seen.insert(ObjectIdentifier(Element)).inserted, Depth < 32,
                  !Element.isAccessibilityHidden() else { continue }
            if let View = Element as? NSView, View.isHiddenOrHasHiddenAncestor { continue }
            let Role = Element.accessibilityRole()
            let ScreenRect = Element.accessibilityFrame()
            let ValidRect = ScreenRect.origin.x.isFinite && ScreenRect.origin.y.isFinite &&
                            ScreenRect.width.isFinite && ScreenRect.height.isFinite &&
                            ScreenRect.width > 2 && ScreenRect.height > 2
            var ChildClip = Clip
            if Role == .scrollArea, ValidRect {
                ChildClip = Clip.intersection(ScreenRect)
                if ChildClip.isNull { continue }
                ScrollElements.append(Element)
            }
            if let Role, Roles.contains(Role), ValidRect, Element.isAccessibilityEnabled() {
                let Visible = ScreenRect.intersection(Clip)
                if !Visible.isNull, Visible.width > 6, Visible.height > 6 {
                    Targets.append(FocusTarget(Element: Element, Rect: LocalRect(Visible, In: Scope), Role: Role))
                }
            }
            let Children = Element.accessibilityChildren() ?? []
            for Child in Children.prefix(max(0, 2_000 - Queue.count)) {
                if let Child = Child as? NSAccessibilityProtocol { Queue.append((Child, ChildClip, Depth + 1)) }
            }
        }
        return Targets.sorted {
            if abs($0.Rect.minY - $1.Rect.minY) > 8 { return $0.Rect.minY < $1.Rect.minY }
            return $0.Rect.minX < $1.Rect.minX
        }
    }

    private func Nearest(_ Targets: [FocusTarget], From Current: FocusTarget, Toward Action: BigPictureAction) -> FocusTarget? {
        let Horizontal = Action == .Left || Action == .Right
        let Sign: CGFloat = Action == .Left || Action == .Up ? -1 : 1
        let Candidates = Targets.compactMap { Target -> (FocusTarget, CGFloat)? in
            guard Target.Element !== Current.Element else { return nil }
            let X = Target.Rect.midX - Current.Rect.midX
            let Y = Target.Rect.midY - Current.Rect.midY
            let Forward = (Horizontal ? X : Y) * Sign
            let Sideways = abs(Horizontal ? Y : X)
            let Tolerance = Horizontal ? max(Current.Rect.height, Target.Rect.height) : max(Current.Rect.width, Target.Rect.width)
            guard Forward > 2, Sideways <= max(Forward * 1.5, Tolerance) else { return nil }
            return (Target, Forward + Sideways * 2.5)
        }
        return Candidates.min { $0.1 < $1.1 }?.0
    }

    private func Select(_ Target: FocusTarget, In Scope: FocusScope) {
        Selected = Target
        Publish(Target.Rect, In: Scope)
    }

    private func Publish(_ Rect: CGRect?, In Scope: FocusScope) {
        if Scope.IsSheet {
            if Frame != nil { Frame = nil }
            let Ring: BigPictureFocusRing
            if let Existing = SheetRing, Existing.superview === Scope.View {
                Ring = Existing
            } else {
                SheetRing?.removeFromSuperview()
                Ring = BigPictureFocusRing(frame: Scope.View.bounds)
                Ring.autoresizingMask = [.width, .height]
                Ring.setAccessibilityElement(false)
                Ring.setAccessibilityHidden(true)
                Scope.View.addSubview(Ring, positioned: .above, relativeTo: nil)
                SheetRing = Ring
            }
            Ring.FocusFrame = Rect
            Ring.needsDisplay = true
        } else {
            SheetRing?.removeFromSuperview()
            SheetRing = nil
            if Frame != Rect { Frame = Rect }
        }
    }

    private func Activate(_ Target: FocusTarget, In Scope: FocusScope) -> Bool {
        if [.textField, .textArea, .comboBox].contains(Target.Role) {
            Target.Element.setAccessibilityFocused(true)
            if let View = Target.Element as? NSView { _ = Scope.Window.makeFirstResponder(View) }
            return Target.Element.isAccessibilityFocused() || (Scope.Window.firstResponder as? NSTextView)?.isEditable == true
        }
        if Target.Element.accessibilityPerformPress() { return true }
        if [.popUpButton, .menuButton].contains(Target.Role) { return Target.Element.accessibilityPerformShowMenu() }
        return false
    }

    private func CancelSheet(_ Scope: FocusScope) -> Bool {
        if Scope.Window.accessibilityPerformCancel() { return true }
        if let Event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: Scope.Window.windowNumber,
                                       context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                       isARepeat: false, keyCode: 53) {
            if Scope.Window.performKeyEquivalent(with: Event) { return true }
        }
        for Target in Scan(Scope) where Target.Role == .button {
            let Label = (Target.Element.accessibilityLabel() ?? Target.Element.accessibilityTitle() ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["cancel", "close", "done"].contains(Label), Target.Element.accessibilityPerformPress() { return true }
        }
        return true
    }

    private func Scroll(_ Action: BigPictureAction, In Scope: FocusScope, From Rect: CGRect?) -> Bool {
        guard [.Left, .Right, .Up, .Down].contains(Action), let Content = Scope.Window.contentView else { return false }
        let Horizontal = Action == .Left || Action == .Right
        let Forward = Action == .Right || Action == .Down
        let LocalPoint = Rect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: Scope.Bounds.midX, y: Scope.Bounds.midY)
        let ViewPoint = Scope.View.isFlipped ? LocalPoint : CGPoint(x: LocalPoint.x, y: Scope.Bounds.minY + Scope.Bounds.maxY - LocalPoint.y)
        let WindowPoint = Scope.View.convert(ViewPoint, to: nil)
        let HitPoint = Content.superview?.convert(WindowPoint, from: nil) ?? WindowPoint
        let Hit = Content.hitTest(HitPoint)
        var Queue: [NSView] = [Content]
        var ScrollViews: [(NSScrollView, CGRect)] = []
        var Index = 0
        while Index < Queue.count && Index < 1_000 {
            let View = Queue[Index]
            Index += 1
            guard !View.isHiddenOrHasHiddenAncestor else { continue }
            if let Scroll = View as? NSScrollView, let Document = Scroll.documentView {
                let Exposed = ScrollElements.contains { $0 === Scroll }
                let UnderFocus = Hit === Scroll || Hit?.isDescendant(of: Scroll) == true
                let Visible = LocalRect(NSAccessibility.screenRect(fromView: Scroll, rect: Scroll.bounds), In: Scope).intersection(Scope.Bounds)
                let CanScroll = Horizontal ? Document.bounds.width > Scroll.contentView.bounds.width + 1 : Document.bounds.height > Scroll.contentView.bounds.height + 1
                if Exposed || UnderFocus, CanScroll, !Visible.isNull, Visible.width > 20, Visible.height > 20 {
                    ScrollViews.append((Scroll, Visible))
                }
            }
            Queue.append(contentsOf: View.subviews.prefix(max(0, 1_000 - Queue.count)))
        }
        let Point = Rect.map { CGPoint(x: $0.midX, y: $0.midY) }
        ScrollViews.sort { Left, Right in
            let LeftContains = Point.map { Left.1.contains($0) } ?? false
            let RightContains = Point.map { Right.1.contains($0) } ?? false
            if LeftContains != RightContains { return LeftContains }
            return Left.1.width * Left.1.height < Right.1.width * Right.1.height
        }
        for (Scroll, _) in ScrollViews {
            guard let Document = Scroll.documentView else { continue }
            let Clip = Scroll.contentView
            var Proposed = Clip.bounds
            let Step = max(80, (Horizontal ? Proposed.width : Proposed.height) * 0.55)
            if Horizontal {
                Proposed.origin.x += Forward ? Step : -Step
            } else {
                Proposed.origin.y += Forward == Document.isFlipped ? Step : -Step
            }
            let Constrained = Clip.constrainBoundsRect(Proposed)
            guard abs(Constrained.minX - Clip.bounds.minX) + abs(Constrained.minY - Clip.bounds.minY) > 1 else { continue }
            Clip.scroll(to: Constrained.origin)
            Scroll.reflectScrolledClipView(Clip)
            SelectAfterScroll(In: Scope, Near: Rect)
            return true
        }
        for Element in ScrollElements {
            let Bar = Horizontal ? Element.accessibilityHorizontalScrollBar() : Element.accessibilityVerticalScrollBar()
            guard let Bar = Bar as? NSAccessibilityProtocol else { continue }
            if Forward ? Bar.accessibilityPerformIncrement() : Bar.accessibilityPerformDecrement() {
                SelectAfterScroll(In: Scope, Near: Rect)
                return true
            }
        }
        return false
    }

    private func SelectAfterScroll(In Scope: FocusScope, Near Rect: CGRect?) {
        ScrollTask?.cancel()
        ScrollTask = Task { @MainActor [weak self, weak Window = Scope.Window] in
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            guard let self else { return }
            self.ScrollTask = nil
            guard let Current = self.Scope(), Current.Window === Window else { return }
            let Targets = self.Scan(Current)
            let Next = Rect.flatMap { Rect in
                Targets.min {
                    abs($0.Rect.midY - Rect.midY) + abs($0.Rect.midX - Rect.midX) <
                    abs($1.Rect.midY - Rect.midY) + abs($1.Rect.midX - Rect.midX)
                }
            } ?? Targets.first
            if let Next { self.Select(Next, In: Current) } else { self.Publish(nil, In: Current) }
        }
    }
}

struct BigPictureFocusArea: NSViewRepresentable {
    let Controller: BigPictureFocus

    func makeNSView(context Context: Context) -> BigPictureFocusView {
        let View = BigPictureFocusView(frame: .zero)
        View.Controller = Controller
        View.setAccessibilityElement(false)
        View.setAccessibilityHidden(true)
        Controller.Bind(View)
        return View
    }

    func updateNSView(_ View: BigPictureFocusView, context Context: Context) {
        if View.Controller !== Controller {
            View.Controller?.Detach(View)
            View.Controller = Controller
        }
        Controller.Bind(View)
    }

    static func dismantleNSView(_ View: BigPictureFocusView, coordinator Coordinator: ()) {
        View.Controller?.Detach(View)
        View.Controller = nil
    }
}

final class BigPictureFocusView: NSView {
    weak var Controller: BigPictureFocus?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ Point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        Task { @MainActor [weak self] in self?.Controller?.RefreshFrame() }
    }
}

private final class BigPictureFocusRing: NSView {
    var FocusFrame: CGRect?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ Point: NSPoint) -> NSView? { nil }
    override func draw(_ DirtyRect: NSRect) {
        guard let FocusFrame else { return }
        NSColor.controlAccentColor.setStroke()
        let Path = NSBezierPath(roundedRect: FocusFrame.insetBy(dx: -3, dy: -3), xRadius: 7, yRadius: 7)
        Path.lineWidth = 3
        Path.stroke()
    }
}
