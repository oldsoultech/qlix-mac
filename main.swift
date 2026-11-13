import Cocoa
import WebKit

// MARK: - Configuration

let appName = "Qlix"
let startURL = URL(string: "https://oldsoultech.github.io/Qlix/")!

/// Hosts that stay inside the app window. Anything else opens in the default browser.
/// Add more here if the site uses e.g. an OAuth login host.
let allowedHosts: Set<String> = ["oldsoultech.github.io"]

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {

    var window: NSWindow!
    var webView: WKWebView!
    var titleObservation: NSKeyValueObservation?
    var downloadDestination: URL?

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()               // persists cookies/localStorage between launches
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.autoresizingMask = [.width, .height]

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appName
        window.minSize = NSSize(width: 480, height: 360)
        window.contentView = webView
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MainWindow")          // remembers size/position
        window.makeKeyAndOrderFront(nil)

        // Window title follows the page title
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            if let t = wv.title, !t.isEmpty { self.window.title = t } else { self.window.title = appName }
        }

        webView.load(URLRequest(url: startURL))
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Helpers

    private func isInternal(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        if ["about", "blob", "data", "file"].contains(scheme) { return true }
        guard let host = url.host?.lowercased() else { return true }
        return allowedHosts.contains(host)
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "http" && scheme != "https" && !["about", "blob", "data", "file"].contains(scheme) {
            // mailto:, tel:, custom app schemes...
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        if !isInternal(url) && (navigationAction.targetFrame?.isMainFrame ?? true) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showOfflinePage(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showOfflinePage(error)
    }

    private func showOfflinePage(_ error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }
        let html = """
        <html><head><meta name="color-scheme" content="light dark">
        <style>body{font-family:-apple-system,sans-serif;display:flex;height:100vh;margin:0;
        align-items:center;justify-content:center;text-align:center}
        a{display:inline-block;margin-top:16px;padding:8px 18px;border-radius:8px;
        background:#0a84ff;color:#fff;text-decoration:none}</style></head>
        <body><div><h2>Can’t reach \(appName)</h2>
        <p>\(ns.localizedDescription)</p>
        <a href="\(startURL.absoluteString)">Try Again</a></div></body></html>
        """
        webView.loadHTMLString(html, baseURL: startURL)
    }

    // MARK: Downloads

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let fm = FileManager.default
        let dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = dir.appendingPathComponent(suggestedFilename)
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var i = 1
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            i += 1
        }
        downloadDestination = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let dest = downloadDestination {
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let alert = NSAlert()
        alert.messageText = "Download failed"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    // MARK: UI delegate (popups, dialogs, file picker, camera/mic)

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target="_blank" / window.open
        if let url = navigationAction.request.url {
            if isInternal(url) {
                webView.load(navigationAction.request)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) {
            completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(allowedHosts.contains(origin.host.lowercased()) ? .grant : .deny)
    }

    // MARK: Menu actions

    @objc func goBack()        { webView.goBack() }
    @objc func goForward()     { webView.goForward() }
    @objc func goHome()        { webView.load(URLRequest(url: startURL)) }
    @objc func reload()        { webView.reload() }
    @objc func hardReload()    { webView.reloadFromOrigin() }
    @objc func zoomIn()        { webView.pageZoom = min(webView.pageZoom + 0.1, 3.0) }
    @objc func zoomOut()       { webView.pageZoom = max(webView.pageZoom - 0.1, 0.3) }
    @objc func zoomReset()     { webView.pageZoom = 1.0 }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .credits: NSAttributedString(string: startURL.absoluteString)
        ])
    }

    // MARK: Menu bar

    private func buildMenu() {
        let main = NSMenu()

        func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                 _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            menu.addItem(item)
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem()
            main.addItem(item)
            let m = NSMenu(title: title)
            item.submenu = m
            return m
        }

        // App menu
        let app = submenu(appName)
        add(app, "About \(appName)", #selector(showAbout), target: self)
        app.addItem(.separator())
        add(app, "Hide \(appName)", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit \(appName)", #selector(NSApplication.terminate(_:)), "q")

        // Edit menu
        let edit = submenu("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")

        // View menu
        let view = submenu("View")
        add(view, "Reload", #selector(reload), "r", target: self)
        add(view, "Reload From Origin", #selector(hardReload), "r", [.command, .shift], target: self)
        view.addItem(.separator())
        add(view, "Actual Size", #selector(zoomReset), "0", target: self)
        add(view, "Zoom In", #selector(zoomIn), "+", target: self)
        add(view, "Zoom Out", #selector(zoomOut), "-", target: self)
        view.addItem(.separator())
        add(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        // Navigate menu
        let nav = submenu("Navigate")
        add(nav, "Back", #selector(goBack), "[", target: self)
        add(nav, "Forward", #selector(goForward), "]", target: self)
        add(nav, "Home", #selector(goHome), "h", [.command, .shift], target: self)

        // Window menu
        let win = submenu("Window")
        add(win, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(win, "Zoom", #selector(NSWindow.performZoom(_:)))
        win.addItem(.separator())
        add(win, "Close", #selector(NSWindow.performClose(_:)), "w")
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }
}

// MARK: - Entry point

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
