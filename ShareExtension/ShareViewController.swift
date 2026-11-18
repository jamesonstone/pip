import SwiftUI

#if os(iOS)
import UIKit

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        let host = UIHostingController(rootView: ShareRootView(context: extensionContext))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}
#else
import AppKit

final class FocusableHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
}

@objc(ShareViewController)
final class ShareViewController: NSViewController {
    private var hostView: FocusableHostingView<ShareRootView>?
    private let focusTrigger = ShareFocusTrigger()
    private var appliedHeight: CGFloat = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        preferredContentSize = NSSize(width: 400, height: 300)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let hostView = FocusableHostingView(rootView: ShareRootView(
            context: extensionContext,
            onContentHeight: { [weak self] height in
                DispatchQueue.main.async {
                    self?.applyContentHeight(height)
                }
            },
            focusTrigger: focusTrigger
        ))
        self.hostView = hostView
        hostView.frame = view.bounds
        hostView.autoresizingMask = [.width, .height]
        view.addSubview(hostView)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(hostView)
        focusTrigger.ready = true
    }

    private func applyContentHeight(_ height: CGFloat) {
        let next = min(max(ceil(height), 220), 560)
        guard abs(next - appliedHeight) > 1 else { return }
        appliedHeight = next
        preferredContentSize = NSSize(width: 400, height: next)
    }
}
#endif
