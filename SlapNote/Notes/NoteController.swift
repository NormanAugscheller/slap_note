import AppKit
import SlapNoteCore

protocol NoteControllerDelegate: AnyObject {
    var settings: AppSettings { get }
    func noteDidChange(_ note: NoteController)
    func noteRequestsDiscard(_ note: NoteController)
    func noteRequestsReminderPicker(_ note: NoteController)
    func noteWillBeginEditing(_ note: NoteController)
    func noteDidEndEditing(_ note: NoteController)
    func noteWasInteractedWith(_ note: NoteController)
    /// The user dragged the note to a new place.
    func noteDidMove(_ note: NoteController)
    /// Called on Esc in placement mode.
    func noteRequestsCancelPlacement(_ note: NoteController)
}

/// One note on screen: its window, view, record and all interactions of a stuck note.
final class NoteController: NSObject, NSTextViewDelegate, NoteMouseHandling {
    enum Mode: Equatable {
        case placement
        case stuck
        case editing
        case leaving
    }

    private(set) var record: NoteRecord
    let window: NotePanel
    let view: NoteView
    weak var delegate: NoteControllerDelegate?
    private(set) var mode: Mode
    /// Displayed size (manual size plus auto-grow).
    private(set) var displayedSize: CGSize
    private(set) var curl: Double = 0
    var isHovered = false
    var isAttentionActive: Bool { attentionTimer != nil }

    private var dragStart: NSPoint?
    private var windowOriginAtDragStart: NSPoint = .zero
    private var didDrag = false
    private var lastStrikeToggle: (line: Int, time: TimeInterval)?
    private var attentionTimer: Timer?
    private var curlAnimation: Timer?
    private var currentRotation: CGFloat = 0

    init(record: NoteRecord, mode: Mode, delegate: NoteControllerDelegate) {
        self.record = record
        self.mode = mode
        self.delegate = delegate
        displayedSize = record.manualSize
        view = NoteView(frame: CGRect(origin: .zero, size: record.manualSize).insetBy(dx: -NoteView.margin, dy: -NoteView.margin))
        window = NotePanel(contentRect: view.frame)
        super.init()
        window.contentView = view
        view.mouseHandler = self
        view.textView.delegate = self
        view.textView.onCancel = { [weak self] in self?.handleEscape() }
        window.keyEquivalentHandler = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        view.textView.string = record.text
        currentRotation = mode == .placement ? 0 : CGFloat(record.rotation)
        applyAppearance()
        relayout(anchor: .center)
    }

    var settings: AppSettings { delegate?.settings ?? AppSettings.shared }

    // MARK: Geometry

    enum Anchor { case center, top }

    var noteCenter: CGPoint {
        CGPoint(x: window.frame.midX, y: window.frame.midY)
    }

    /// Note rect in screen coordinates.
    var noteFrame: CGRect {
        window.frame.insetBy(dx: NoteView.margin, dy: NoteView.margin)
    }

    func setNoteCenter(_ center: CGPoint) {
        let w = displayedSize.width + 2 * NoteView.margin
        let h = displayedSize.height + 2 * NoteView.margin
        window.setFrameOrigin(NSPoint(x: (center.x - w / 2).rounded(), y: (center.y - h / 2).rounded()))
    }

    private var visibleScreenHeight: CGFloat {
        (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
    }

    /// Recomputes the auto-grow height and lays everything out.
    func relayout(anchor: Anchor) {
        let oldFrame = noteFrame
        let textWidth = NoteView.textRect(in: CGRect(origin: .zero, size: record.manualSize), shape: record.shape,
                                          hasReminder: record.reminder != nil).width
        let textHeight = measureTextHeight(width: textWidth)
        let reminderSpace = record.reminder != nil ? NoteView.reminderLabelHeight : 0
        let grow = AutoGrow.displayedHeight(manualHeight: CGFloat(record.height), textHeight: textHeight + reminderSpace,
                                            shape: record.shape, padding: NoteView.textPadding,
                                            visibleScreenHeight: visibleScreenHeight)
        displayedSize = CGSize(width: CGFloat(record.width), height: grow.height)
        view.scrollView.hasVerticalScroller = grow.needsInternalScrolling

        let w = displayedSize.width + 2 * NoteView.margin
        let h = displayedSize.height + 2 * NoteView.margin
        var origin: NSPoint
        switch anchor {
        case .center:
            origin = NSPoint(x: oldFrame.midX - w / 2, y: oldFrame.midY - h / 2)
        case .top:
            origin = NSPoint(x: oldFrame.midX - w / 2, y: oldFrame.maxY + NoteView.margin - h)
        }
        if mode != .placement, let screen = window.screen ?? NSScreen.main {
            // Keep a growing stuck note on screen.
            let center = DisplayResolver.clampCenter(CGPoint(x: origin.x + w / 2, y: origin.y + h / 2),
                                                     size: displayedSize, into: screen.visibleFrame)
            origin = NSPoint(x: center.x - w / 2, y: center.y - h / 2)
        }
        window.setFrame(NSRect(x: origin.x.rounded(), y: origin.y.rounded(), width: w, height: h), display: true)
        view.frame = NSRect(x: 0, y: 0, width: w, height: h)
        view.layout(noteSize: displayedSize, shape: record.shape, hasReminder: record.reminder != nil)
        view.paper.configure(shapePath: record.shape.path(in: view.paper.bounds), color: record.color,
                             texture: settings.paperTexture, curl: curl)
        applyRotation(currentRotation)
    }

    private func measureTextHeight(width: CGFloat) -> CGFloat {
        guard let container = view.textView.textContainer, let layout = view.textView.layoutManager else { return 0 }
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        var height = layout.usedRect(for: container).height
        if layout.extraLineFragmentTextContainer != nil {
            height = max(height, layout.extraLineFragmentRect.maxY)
        }
        let font = settings.font(scale: CGFloat(record.fontScale))
        return max(height, ceil(font.ascender - font.descender + font.leading)) + 2
    }

    func applyRotation(_ degrees: CGFloat) {
        currentRotation = degrees
        guard let layer = view.body.layer else { return }
        Motion.setWithoutAnimation {
            layer.transform = Motion.transform(for: layer, rotation: degrees)
        }
    }

    // MARK: Appearance

    /// Applies font, color, alignment, spacing and strike-through from settings and record.
    func applyAppearance() {
        let tv = view.textView
        let font = settings.font(scale: CGFloat(record.fontScale))
        let color = settings.textColor(for: record.color)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = settings.alignment.nsAlignment
        paragraph.lineSpacing = CGFloat(settings.lineSpacing)
        tv.font = font
        tv.textColor = color
        tv.insertionPointColor = color
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        tv.selectedTextAttributes = [.backgroundColor: NSColor(white: 0, alpha: 0.15)]
        view.reminderLabel.textColor = color.withAlphaComponent(0.75)
        applyStrikeAttributes()
        updateReminderLabel()
    }

    func applyStrikeAttributes() {
        guard let storage = view.textView.textStorage else { return }
        let font = settings.font(scale: CGFloat(record.fontScale))
        let color = settings.textColor(for: record.color)
        let paragraph = (view.textView.defaultParagraphStyle ?? NSParagraphStyle.default)
        let struck = Set(record.struckLines)
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: color, .paragraphStyle: paragraph], range: full)
        for (index, range) in StrikeMapper.lineRanges(of: storage.string).enumerated() where struck.contains(index) && range.length > 0 {
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .strikethroughColor: color.withAlphaComponent(0.7),
                                   .foregroundColor: color.withAlphaComponent(0.5)], range: range)
        }
        storage.endEditing()
    }

    func updateReminderLabel() {
        if let r = record.reminder {
            view.reminderLabel.stringValue = ReminderSchedule.label(for: r.date, now: Date())
            view.reminderLabel.isHidden = false
            view.reminderLabel.setAccessibilityLabel("Reminder \(view.reminderLabel.stringValue)")
        } else {
            view.reminderLabel.isHidden = true
        }
    }

    // MARK: Record mutations

    func setStyle(_ style: NoteStyle, keepSize: Bool) {
        let shapeChanged = style.shape != record.shape
        record.style = style
        if shapeChanged && !keepSize {
            record.manualSize = NoteGeometry.size(switchingTo: style.shape, from: record.manualSize)
        }
        applyAppearance()
        relayout(anchor: .center)
    }

    func applyResize(factor: CGFloat, mode resizeMode: ResizeMode) {
        let before = record.manualSize
        let result = NoteGeometry.resize(size: record.manualSize, fontScale: CGFloat(record.fontScale), factor: factor, mode: resizeMode)
        record.manualSize = result.size
        record.fontScale = Double(result.fontScale)
        if resizeMode == .proportional { applyAppearance() }
        relayout(anchor: .center)
        if result.hitLimit {
            let grew = result.size.width >= before.width && result.size.height >= before.height && factor > 1
            NoteAnimator.limitBump(view, grew: grew)
        }
    }

    func setReminder(_ reminder: ReminderRecord?) {
        record.reminder = reminder
        record.touch()
        updateReminderLabel()
        relayout(anchor: .top)
        stopAttention()
        delegate?.noteDidChange(self)
    }

    /// macOS accepted the scheduled notification for the reminder at `date` (ignored if it changed since).
    func markReminderScheduled(for date: Date) {
        guard var r = record.reminder, r.date == date, !r.scheduledWithSystem, !r.fired else { return }
        r.scheduledWithSystem = true
        record.reminder = r
        delegate?.noteDidChange(self)
    }

    func markReminderFired() {
        guard var r = record.reminder else { return }
        r.fired = true
        r.acknowledged = false
        record.reminder = r
        delegate?.noteDidChange(self)
    }

    /// Stores the position (display + relative center) and rotation after slapping or moving.
    func updatePosition(_ position: DisplayPosition) {
        record.position = position
    }

    func setRotation(_ degrees: Double) {
        record.rotation = degrees
    }

    func touch() {
        record.touch()
        if curl > 0 { setCurl(0, animated: true) }
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        switch newMode {
        case .placement, .editing:
            view.textInteractionEnabled = true
        case .stuck, .leaving:
            view.textInteractionEnabled = false
        }
    }

    // MARK: Curl (aging)

    func setCurl(_ target: Double, animated: Bool) {
        curlAnimation?.invalidate()
        curlAnimation = nil
        guard abs(target - curl) > 0.001 else { return }
        if !animated || Motion.reduced {
            curl = target
            view.paper.configure(shapePath: record.shape.path(in: view.paper.bounds), color: record.color,
                                 texture: settings.paperTexture, curl: curl)
            return
        }
        let start = curl
        let begin = CACurrentMediaTime()
        let duration = 0.45
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                let p = min((CACurrentMediaTime() - begin) / duration, 1)
                let eased = 1 - pow(1 - p, 3)
                self.curl = start + (target - start) * eased
                Motion.setWithoutAnimation {
                    self.view.paper.applyCurl(shapePath: self.record.shape.path(in: self.view.paper.bounds), curl: self.curl)
                }
                if p >= 1 {
                    t.invalidate()
                    self.curlAnimation = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        curlAnimation = timer
    }

    // MARK: Reminder attention

    func startAttention() {
        guard attentionTimer == nil else { return }
        NoteAnimator.attention(view, baseRotation: currentRotation)
        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                NoteAnimator.attention(self.view, baseRotation: self.currentRotation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        attentionTimer = timer
    }

    func stopAttention() {
        attentionTimer?.invalidate()
        attentionTimer = nil
    }

    /// Called when the user interacts with the note; acknowledges a due reminder.
    private func interacted() {
        if isAttentionActive || (record.reminder?.fired == true && record.reminder?.acknowledged == false) {
            stopAttention()
            if var r = record.reminder {
                r.acknowledged = true
                record.reminder = r
            }
        }
        delegate?.noteWasInteractedWith(self)
    }

    // MARK: Editing

    func beginEditing(at windowPoint: NSPoint?) {
        guard mode == .stuck else { return }
        if isHovered {
            isHovered = false
            NoteAnimator.hover(view, on: false)
        }
        delegate?.noteWillBeginEditing(self)
        setMode(.editing)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view.textView)
        if let p = windowPoint {
            let local = view.textViewPoint(fromWindow: p, rotation: currentRotation)
            let index = view.textView.characterIndexForInsertion(at: local)
            view.textView.setSelectedRange(NSRange(location: min(index, (view.textView.string as NSString).length), length: 0))
        } else {
            view.textView.setSelectedRange(NSRange(location: (view.textView.string as NSString).length, length: 0))
        }
    }

    func endEditing() {
        guard mode == .editing else { return }
        view.textView.setSelectedRange(NSRange(location: 0, length: 0))
        window.makeFirstResponder(nil)
        setMode(.stuck)
        window.resignKey()
        delegate?.noteDidEndEditing(self)
    }

    private func handleEscape() {
        switch mode {
        case .editing: endEditing()
        case .placement: delegate?.noteRequestsCancelPlacement(self)
        default: break
        }
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "t",
           mode == .placement || mode == .editing {
            delegate?.noteRequestsReminderPicker(self)
            return true
        }
        return false
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        let newText = view.textView.string
        guard newText != record.text else { return }
        let remapped = StrikeMapper.remap(struck: Set(record.struckLines), from: record.text, to: newText)
        record.text = newText
        record.struckLines = remapped.sorted()
        if mode == .editing { touch() } else { record.modified = Date() }
        applyStrikeAttributes()
        relayout(anchor: mode == .placement ? .center : .top)
        delegate?.noteDidChange(self)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            handleEscape()
            return true
        }
        return false
    }

    // MARK: NoteMouseHandling (stuck mode)

    func noteMouseEntered() {
        guard mode == .stuck, !isHovered, dragStart == nil else { return }
        isHovered = true
        NoteAnimator.hover(view, on: true)
    }

    func noteMouseExited() {
        guard isHovered, dragStart == nil else { return }
        isHovered = false
        NoteAnimator.hover(view, on: false)
    }

    func noteMouseDown(_ event: NSEvent) {
        guard mode == .stuck else { return }
        if event.clickCount >= 2 {
            // Undo the strike toggle of the first click of this double click.
            if let last = lastStrikeToggle, event.timestamp - last.time <= NSEvent.doubleClickInterval {
                record.struckLines = StrikeMapper.toggle(last.line, in: Set(record.struckLines)).sorted()
                applyStrikeAttributes()
            }
            lastStrikeToggle = nil
            dragStart = nil
            interacted()
            beginEditing(at: event.locationInWindow)
            return
        }
        dragStart = NSEvent.mouseLocation
        windowOriginAtDragStart = window.frame.origin
        didDrag = false
    }

    func noteMouseDragged(_ event: NSEvent) {
        guard mode == .stuck, let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !didDrag && hypot(dx, dy) < 4 { return }
        if !didDrag {
            didDrag = true
            if isHovered { NoteAnimator.hover(view, on: false) }
        }
        window.setFrameOrigin(NSPoint(x: windowOriginAtDragStart.x + dx, y: windowOriginAtDragStart.y + dy))
    }

    func noteMouseUp(_ event: NSEvent) {
        guard mode == .stuck, dragStart != nil else { return }
        dragStart = nil
        if didDrag {
            didDrag = false
            interacted()
            touch()
            delegate?.noteDidMove(self)
            if isHovered { NoteAnimator.hover(view, on: true) }
            return
        }
        if event.clickCount == 1 { toggleStrike(at: event) }
    }

    func noteRightMouseDown(_ event: NSEvent) {
        guard mode == .stuck || mode == .editing else { return }
        delegate?.noteRequestsDiscard(self)
    }

    private func toggleStrike(at event: NSEvent) {
        let tv = view.textView
        guard let layout = tv.layoutManager, let container = tv.textContainer else { return }
        let p = view.textViewPoint(fromWindow: event.locationInWindow, rotation: currentRotation)
        let length = (tv.string as NSString).length
        interacted()
        guard length > 0 else { return }
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: p, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        guard p.y >= lineRect.minY - 2, p.y <= lineRect.maxY + 2 else { return }
        let charIndex = layout.characterIndexForGlyph(at: glyph)
        let line = StrikeMapper.lineIndex(forUTF16Offset: charIndex, in: tv.string)
        let ranges = StrikeMapper.lineRanges(of: tv.string)
        guard line < ranges.count, ranges[line].length > 0 else { return }
        record.struckLines = StrikeMapper.toggle(line, in: Set(record.struckLines)).sorted()
        lastStrikeToggle = (line, event.timestamp)
        applyStrikeAttributes()
        touch()
        delegate?.noteDidChange(self)
    }

    // MARK: Teardown

    func close() {
        stopAttention()
        curlAnimation?.invalidate()
        curlAnimation = nil
        view.mouseHandler = nil
        view.textView.delegate = nil
        window.keyEquivalentHandler = nil
        window.orderOut(nil)
        window.close()
    }
}
