import BaronCore

/// Step 1: `AXSelectedText` on the focused element.
public struct AXTextRetriever: TextRetriever {
    public let step = RetrievalStep.axText
    let element: AXElement

    public init(element: AXElement) {
        self.element = element
    }

    public func retrieve() async -> String? {
        SelectedTextReader.selectedText(of: element)
    }
}

/// Step 2: the web page's selected text-marker range. Chrome builds its tree lazily,
/// so this retries up to 6 times over 300 ms.
public struct AXWebRetriever: TextRetriever {
    public static let attempts = 6
    public static let window = Duration.milliseconds(300)

    public let step = RetrievalStep.axWeb
    let element: AXElement

    public init(element: AXElement) {
        self.element = element
    }

    public func retrieve() async -> String? {
        await retry(attempts: Self.attempts, within: Self.window) {
            WebSelectionReader.selectedRange(near: element).flatMap {
                WebSelectionReader.string(for: $0.range, in: $0.owner)
            }
        }
    }
}

/// Steps 3 and 4: make the app copy, through its Edit menu or ⌘C (via SelectedTextKit).
public struct CopyRetriever: TextRetriever {
    public let step: RetrievalStep
    let method: CopyReader.Method

    public init(method: CopyReader.Method) {
        self.method = method
        self.step = method == .menu ? .menuCopy : .keyCopy
    }

    public func retrieve() async -> String? {
        await CopyReader.copySelection(using: method)
    }
}

extension RetrievalChain {
    /// The standard four-step chain for a focused element (or only the copy steps when there is none).
    public static func standard(for element: AXElement?) -> RetrievalChain {
        var retrievers: [any TextRetriever] = [CopyRetriever(method: .menu), CopyRetriever(method: .keyboard)]
        if let element {
            retrievers += [AXTextRetriever(element: element), AXWebRetriever(element: element)]
        }
        return RetrievalChain(retrievers: retrievers)
    }
}
