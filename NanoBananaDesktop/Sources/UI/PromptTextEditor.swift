import AppKit
import SwiftUI

enum PromptDropTarget: Equatable {
    case attachments
    case convertToPrompt
}

struct PromptTextEditor: NSViewRepresentable {
    static let textInsetX: CGFloat = 12
    static let textInsetY: CGFloat = 12

    @Binding var text: String
    @Binding var mentionToInsert: String?
    var onFilesDropped: ([URL], PromptDropTarget) -> Void
    var onDropTargetChanged: (PromptDropTarget?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = DropAwareTextView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 190),
            textContainer: textContainer
        )
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.string = text
        textView.textContainerInset = NSSize(width: Self.textInsetX, height: Self.textInsetY)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.onFilesDropped = { urls, target in
            DispatchQueue.main.async {
                context.coordinator.parent.onFilesDropped(urls, target)
            }
        }
        textView.onDropTargetChanged = { target in
            DispatchQueue.main.async {
                context.coordinator.parent.onDropTargetChanged(target)
            }
        }

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        if textView.string != text {
            let currentSelection = textView.selectedRange()
            textView.string = text
            let boundedLocation = min(currentSelection.location, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: boundedLocation, length: 0))
        }

        if let mention = mentionToInsert {
            context.coordinator.insertMention(mention, into: textView)
            mentionToInsert = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextEditor
        weak var textView: NSTextView?

        init(parent: PromptTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            parent.text = textView.string
        }

        func insertMention(_ mention: String, into textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            let nsText = textView.string as NSString
            var insertion = mention

            if shouldInsertLeadingSpace(text: nsText, selectedRange: selectedRange) {
                insertion = " " + insertion
            }
            if shouldInsertTrailingSpace(text: nsText, selectedRange: selectedRange) {
                insertion += " "
            }

            textView.insertText(insertion, replacementRange: selectedRange)
            parent.text = textView.string
            _ = textView.window?.makeFirstResponder(textView)
        }

        private func shouldInsertLeadingSpace(text: NSString, selectedRange: NSRange) -> Bool {
            guard selectedRange.location > 0 else {
                return false
            }
            let previousCharacter = text.substring(with: NSRange(location: selectedRange.location - 1, length: 1))
            return previousCharacter.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        }

        private func shouldInsertTrailingSpace(text: NSString, selectedRange: NSRange) -> Bool {
            if selectedRange.location >= text.length {
                return true
            }

            let nextCharacter = text.substring(with: NSRange(location: selectedRange.location, length: 1))
            return nextCharacter.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        }
    }
}

final class DropAwareTextView: NSTextView {
    var onFilesDropped: (([URL], PromptDropTarget) -> Void)?
    var onDropTargetChanged: ((PromptDropTarget?) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedFileURLs(from: sender).isEmpty {
            return super.draggingEntered(sender)
        }
        onDropTargetChanged?(dropTarget(from: sender))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedFileURLs(from: sender).isEmpty {
            return super.draggingUpdated(sender)
        }
        onDropTargetChanged?(dropTarget(from: sender))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTargetChanged?(nil)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if droppedFileURLs(from: sender).isEmpty {
            return super.prepareForDragOperation(sender)
        }
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedFileURLs(from: sender)
        guard !urls.isEmpty else {
            return super.performDragOperation(sender)
        }
        let target = dropTarget(from: sender)
        onFilesDropped?(urls, target)
        onDropTargetChanged?(nil)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDropTargetChanged?(nil)
        super.concludeDragOperation(sender)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .fileURL || type.rawValue == NSPasteboard.PasteboardType.URL.rawValue {
            return false
        }
        return super.readSelection(from: pboard, type: type)
    }

    private func droppedFileURLs(from draggingInfo: NSDraggingInfo) -> [URL] {
        let pasteboard = draggingInfo.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return []
        }
        return urls
    }

    private func dropTarget(from draggingInfo: NSDraggingInfo) -> PromptDropTarget {
        let windowPoint = draggingInfo.draggingLocation
        let localPoint = convert(windowPoint, from: nil)
        // NSTextView is flipped on macOS, so Y grows downward.
        // We route drops in the bottom 30% of the *visible* area to image->prompt flow.
        let visible = visibleRect
        let convertThresholdY = visible.minY + (visible.height * 0.70)
        return localPoint.y >= convertThresholdY ? .convertToPrompt : .attachments
    }
}
