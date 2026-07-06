import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct WebModuleView: NSViewRepresentable {
    let app: DeskItAppEntry

    func makeCoordinator() -> WebModuleCoordinator {
        WebModuleCoordinator(app: app)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(storageNamespaceScript(for: app))
        configuration.userContentController.add(context.coordinator, name: "deskitNative")

        if let handler = app.bridgeHandler {
            configuration.userContentController.add(context.coordinator, name: handler)
        }

        if app.id == "pomodewro" {
            configuration.setURLSchemeHandler(context.coordinator.soundSchemeHandler, forURLScheme: "pomodewro-sound")
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.load()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private func storageNamespaceScript(for app: DeskItAppEntry) -> WKUserScript {
        let namespace = javaScriptString(app.storageNamespace)
        let appID = javaScriptString(app.id)
        let source = """
        (function() {
          const namespace = \(namespace);
          const nativeStorage = window.localStorage;
          const proto = Storage.prototype;
          const rawGetItem = proto.getItem;
          const rawSetItem = proto.setItem;
          const rawRemoveItem = proto.removeItem;
          const rawClear = proto.clear;
          const rawKey = proto.key;
          const ownKey = (key) => String(key).startsWith(namespace) ? String(key) : namespace + String(key);
          const scopedKeys = () => {
            const keys = [];
            for (let index = 0; index < nativeStorage.length; index += 1) {
              const key = rawKey.call(nativeStorage, index);
              if (key && key.startsWith(namespace)) keys.push(key);
            }
            return keys;
          };
          const scopedStorage = {
            getItem(key) { return rawGetItem.call(nativeStorage, ownKey(key)); },
            setItem(key, value) { rawSetItem.call(nativeStorage, ownKey(key), String(value)); },
            removeItem(key) { rawRemoveItem.call(nativeStorage, ownKey(key)); },
            clear() { scopedKeys().forEach((key) => rawRemoveItem.call(nativeStorage, key)); },
            key(index) {
              const key = scopedKeys()[index] || null;
              return key ? key.slice(namespace.length) : null;
            },
            get length() { return scopedKeys().length; }
          };
          try {
            proto.getItem = function(key) {
              return this === nativeStorage ? rawGetItem.call(this, ownKey(key)) : rawGetItem.call(this, key);
            };
            proto.setItem = function(key, value) {
              return this === nativeStorage ? rawSetItem.call(this, ownKey(key), String(value)) : rawSetItem.call(this, key, value);
            };
            proto.removeItem = function(key) {
              return this === nativeStorage ? rawRemoveItem.call(this, ownKey(key)) : rawRemoveItem.call(this, key);
            };
            proto.clear = function() {
              if (this !== nativeStorage) return rawClear.call(this);
              scopedKeys().forEach((key) => rawRemoveItem.call(this, key));
            };
            proto.key = function(index) {
              if (this !== nativeStorage) return rawKey.call(this, index);
              const key = scopedKeys()[index] || null;
              return key ? key.slice(namespace.length) : null;
            };
          } catch (error) {}
          try {
            Object.defineProperty(window, 'localStorage', { value: scopedStorage, configurable: false });
          } catch (error) {}
          window.DESKIT_APP = Object.freeze({ id: \(appID), storageNamespace: namespace });
        })();
        """

        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    private func javaScriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }

        return json
    }
}

final class WebModuleCoordinator: NSObject, WKUIDelegate, WKScriptMessageHandler {
    let app: DeskItAppEntry
    let soundStore: SoundStore
    lazy var soundSchemeHandler = SoundSchemeHandler(store: soundStore)
    weak var webView: WKWebView?
    private var didLoad = false

    init(app: DeskItAppEntry) {
        self.app = app
        self.soundStore = SoundStore(appID: app.id)
    }

    func load() {
        guard !didLoad else { return }
        didLoad = true

        guard let entryPath = app.entryPath,
              let resourceURL = Bundle.main.resourceURL else {
            loadMissing("Missing entry path for \(app.name)")
            return
        }

        let htmlURL = resourceURL.appendingPathComponent(entryPath)
        guard FileManager.default.fileExists(atPath: htmlURL.path) else {
            loadMissing("Missing \(entryPath)")
            return
        }

        let readAccessURL = htmlURL.deletingLastPathComponent()
        webView?.loadFileURL(htmlURL, allowingReadAccessTo: readAccessURL)
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.begin { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        switch message.name {
        case "pomodewroNative":
            handlePomodewro(type: type, body: body)
        case "dewdropsNative":
            handleDewdrops(type: type, body: body)
        case "dewQRaftNative":
            handleDewQRaft(type: type, body: body)
        case "deskitNative":
            handleDeskItNative(type: type, body: body)
        default:
            break
        }
    }

    private func handlePomodewro(type: String, body: [String: Any]) {
        switch type {
        case "timer.start":
            PomodewroTimerService.shared.schedule(from: body)
        case "timer.cancel":
            PomodewroTimerService.shared.cancel()
        case "timer.complete":
            PomodewroTimerService.shared.completeNow(from: body)
        case "importSound":
            importSound()
        case "clearSounds":
            clearStoredSounds()
        default:
            break
        }
    }

    private func handleDewdrops(type: String, body: [String: Any]) {
        switch type {
        case "copy":
            guard let text = body["text"] as? String else { return }
            copyText(text)
            callJavaScript("dewdropsNativeCopied")
        default:
            break
        }
    }

    private func handleDewQRaft(type: String, body: [String: Any]) {
        switch type {
        case "copyPng":
            guard let base64 = body["base64"] as? String, let data = Data(base64Encoded: base64) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
            callDewQRaftDone("PNG copied")
        case "copyText":
            guard let text = body["text"] as? String else { return }
            copyText(text)
            callDewQRaftDone((body["label"] as? String) ?? "Copied")
        case "save":
            saveDewQRaftFile(from: body)
        default:
            break
        }
    }

    private func handleDeskItNative(type: String, body: [String: Any]) {
        switch type {
        case "copy":
            guard let text = body["text"] as? String else { return }
            copyText(text)
        default:
            break
        }
    }

    private func importSound() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Pomodewro sound"
        panel.prompt = "Add Sound"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .audio,
            UTType(filenameExtension: "mp3"),
            UTType(filenameExtension: "m4a"),
            UTType(filenameExtension: "aac"),
            UTType(filenameExtension: "wav"),
            UTType(filenameExtension: "aiff"),
            UTType(filenameExtension: "aif"),
            UTType(filenameExtension: "mp4")
        ].compactMap { $0 }

        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let sourceURL = panel.url else { return }

            do {
                let sound = try self.soundStore.importSound(from: sourceURL)
                self.callJavaScript("pomodewroNativeSoundImported", payload: ["id": sound.id, "name": sound.name, "url": sound.url])
            } catch {
                self.callJavaScript("pomodewroNativeSoundImportFailed", payload: ["message": "Could not save sound"])
            }
        }
    }

    private func clearStoredSounds() {
        do {
            try soundStore.clear()
            callJavaScript("pomodewroNativeSoundsCleared")
        } catch {
            callJavaScript("pomodewroNativeSoundImportFailed", payload: ["message": "Could not clear audio"])
        }
    }

    private func saveDewQRaftFile(from body: [String: Any]) {
        let fileName = (body["fileName"] as? String) ?? "dewqraft-code"
        let mime = (body["mime"] as? String) ?? "application/octet-stream"
        let data: Data

        if let base64 = body["base64"] as? String, let decoded = Data(base64Encoded: base64) {
            data = decoded
        } else if let text = body["text"] as? String, let encoded = text.data(using: .utf8) {
            data = encoded
        } else {
            callDewQRaftDone("Nothing to save")
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = allowedTypes(for: mime)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try data.write(to: url, options: .atomic)
                self?.callDewQRaftDone("Saved")
            } catch {
                self?.callDewQRaftDone("Save failed")
            }
        }
    }

    private func allowedTypes(for mime: String) -> [UTType] {
        switch mime {
        case "image/png":
            return [.png]
        case "image/svg+xml":
            return [UTType(filenameExtension: "svg") ?? .data]
        default:
            return [.data]
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func callDewQRaftDone(_ message: String) {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("window.dewQRaftNativeDone && window.dewQRaftNativeDone('\(escaped)');")
    }

    private func callJavaScript(_ name: String, payload: [String: String] = [:]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        webView?.evaluateJavaScript("window['\(name)'] && window['\(name)'](\(json));")
    }

    private func loadMissing(_ message: String) {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        webView?.loadHTMLString("<body style='font:14px -apple-system;background:#f5f5f5;color:#222;padding:24px'>\(escaped)</body>", baseURL: nil)
    }
}

struct NativeSound {
    let id: String
    let name: String
    let url: String
}

final class SoundStore {
    private let appID: String
    private let fileManager = FileManager.default

    init(appID: String) {
        self.appID = appID
    }

    private var directory: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("DeskIt/\(appID)/Sounds", isDirectory: true)
    }

    func importSound(from sourceURL: URL) throws -> NativeSound {
        let hasSecurityAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let id = "native-sound-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6).lowercased())"
        let fileExtension = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension.lowercased()
        let destinationURL = directory.appendingPathComponent("\(id).\(fileExtension)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let rawName = sourceURL.deletingPathExtension().lastPathComponent
        let name = String((rawName.isEmpty ? "Custom" : rawName).prefix(24))
        return NativeSound(id: id, name: name, url: "pomodewro-sound://\(id)")
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    func fileURL(for id: String) -> URL? {
        guard id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        return files.first { $0.deletingPathExtension().lastPathComponent == id }
    }
}

final class SoundSchemeHandler: NSObject, WKURLSchemeHandler {
    private let store: SoundStore

    init(store: SoundStore) {
        self.store = store
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let host = urlSchemeTask.request.url?.host,
              let fileURL = store.fileURL(for: host) else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mime = mimeType(for: fileURL.pathExtension)
            let response = URLResponse(url: urlSchemeTask.request.url ?? fileURL, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "wav":
            return "audio/wav"
        case "aiff", "aif":
            return "audio/aiff"
        default:
            return "application/octet-stream"
        }
    }
}

final class PomodewroTimerService: NSObject, NSSoundDelegate {
    static let shared = PomodewroTimerService()

    private let soundStore = SoundStore(appID: "pomodewro")
    private var timer: Timer?
    private var activeSound: NSSound?
    private var scheduledAlarm: [String: Any]?

    func schedule(from body: [String: Any]) {
        cancel()

        guard let targetEndTime = body["targetEndTime"] as? Double else {
            return
        }

        scheduledAlarm = body["alarm"] as? [String: Any]
        let fireDate = Date(timeIntervalSince1970: targetEndTime / 1000)
        let interval = max(0, fireDate.timeIntervalSinceNow)

        let newTimer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.fireScheduledAlarm()
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        scheduledAlarm = nil
    }

    func completeNow(from body: [String: Any]) {
        timer?.invalidate()
        timer = nil
        scheduledAlarm = nil
        playAlarm(body["alarm"] as? [String: Any])
    }

    private func fireScheduledAlarm() {
        timer?.invalidate()
        timer = nil
        let alarm = scheduledAlarm
        scheduledAlarm = nil
        playAlarm(alarm)
    }

    private func playAlarm(_ alarm: [String: Any]?) {
        guard let alarm else {
            playGeneratedAlarm()
            return
        }

        switch alarm["kind"] as? String {
        case "native":
            if playNativeAlarm(from: alarm["url"] as? String) {
                return
            }
        case "custom":
            if playCustomAlarm(from: alarm["data"] as? String) {
                return
            }
        default:
            break
        }

        playGeneratedAlarm()
    }

    private func playNativeAlarm(from urlString: String?) -> Bool {
        guard let urlString,
              let url = URL(string: urlString),
              let id = url.host,
              let fileURL = soundStore.fileURL(for: id),
              let sound = NSSound(contentsOf: fileURL, byReference: false) else {
            return false
        }

        play(sound)
        return true
    }

    private func playCustomAlarm(from dataURL: String?) -> Bool {
        guard let dataURL,
              let commaIndex = dataURL.firstIndex(of: ",") else {
            return false
        }

        let payload = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: payload),
              let sound = NSSound(data: data) else {
            return false
        }

        play(sound)
        return true
    }

    private func playGeneratedAlarm() {
        if let sound = NSSound(named: NSSound.Name("Glass")) ?? NSSound(named: NSSound.Name("Ping")) {
            play(sound)
        } else {
            NSSound.beep()
        }
    }

    private func play(_ sound: NSSound) {
        activeSound?.stop()
        activeSound = sound
        sound.delegate = self
        sound.volume = 0.78
        sound.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak sound] in
            guard let self, self.activeSound === sound else { return }
            self.activeSound = nil
        }
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        if activeSound === sound {
            activeSound = nil
        }
    }
}
