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

@objc(ShareViewController)
final class ShareViewController: NSViewController {
    private var host: NSHostingController<ShareRootView>?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 360))
        preferredContentSize = NSSize(width: 380, height: 360)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = NSHostingController(rootView: ShareRootView(context: extensionContext))
        self.host = host
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.width, .height]
        view.addSubview(host.view)
    }
}
#endif
