import Foundation

struct AppSize: Codable {
    let width: Double
    let height: Double
}

struct AppConfig: Codable {
    let id: String
    let name: String
    let kind: String
    let sourceRoot: String?
    let sourceItems: [String]?
    let bundlePath: String?
    let entryPath: String?
    let bridgeHandler: String?
    let storageNamespace: String
    let symbolName: String
    let accentHex: String
    let defaultPopoverSize: AppSize
}

struct RuntimeApp: Codable {
    let id: String
    let name: String
    let kind: String
    let entryPath: String?
    let bridgeHandler: String?
    let storageNamespace: String
    let symbolName: String
    let accentHex: String
    let defaultPopoverSize: AppSize
}

func fail(_ message: String) -> Never {
    fputs("sync-apps: \(message)\n", stderr)
    exit(1)
}

func replaceOnce(_ needle: String, with replacement: String, in text: inout String, appID: String) {
    guard let range = text.range(of: needle) else {
        fail("\(appID) patch target not found")
    }

    text.replaceSubrange(range, with: replacement)
}

func patchPomodewro(at htmlURL: URL) throws {
    var html = try String(contentsOf: htmlURL, encoding: .utf8)

    replaceOnce(
        """
      function postNativeMessage(message) {
        if (!nativeBridgeAvailable()) return false;
        window.webkit.messageHandlers.pomodewroNative.postMessage(message);
        return true;
      }
""",
        with:
        """
      function postNativeMessage(message) {
        if (!nativeBridgeAvailable()) return false;
        window.webkit.messageHandlers.pomodewroNative.postMessage(message);
        return true;
      }

      function selectedAlarmPayload(mode) {
        const soundId = mode === "focus" ? state.selectedFocusSoundId : state.selectedBreakSoundId;
        const custom = state.customSounds.find((sound) => sound.id === soundId);
        if (custom) {
          return { id: soundId, kind: "custom", data: custom.data || "" };
        }

        const native = state.nativeSounds.find((sound) => sound.id === soundId);
        if (native) {
          return { id: soundId, kind: "native", url: native.url || "" };
        }

        return { id: soundId, kind: "generated" };
      }

      function scheduleNativeTimer() {
        if (!state.isRunning || targetEndTime <= 0) return false;
        return postNativeMessage({
          type: "timer.start",
          mode: state.mode,
          targetEndTime,
          alarm: selectedAlarmPayload(state.mode)
        });
      }

      function cancelNativeTimer() {
        postNativeMessage({ type: "timer.cancel" });
      }

      function completeNativeTimer(mode) {
        return postNativeMessage({
          type: "timer.complete",
          mode,
          alarm: selectedAlarmPayload(mode)
        });
      }
""",
        in: &html,
        appID: "pomodewro"
    )

    replaceOnce(
        """
        saveState();
        render();
      }
""",
        with:
        """
        saveState();
        if (state.isRunning) scheduleNativeTimer();
        render();
      }
""",
        in: &html,
        appID: "pomodewro"
    )

    replaceOnce(
        """
        timerId = window.setInterval(tick, 250);
        saveState();
        tick();
      }
""",
        with:
        """
        timerId = window.setInterval(tick, 250);
        saveState();
        scheduleNativeTimer();
        tick();
      }
""",
        in: &html,
        appID: "pomodewro"
    )

    replaceOnce(
        """
        clearInterval(timerId);
        timerId = null;
        saveState();
        render();
      }
""",
        with:
        """
        clearInterval(timerId);
        timerId = null;
        cancelNativeTimer();
        saveState();
        render();
      }
""",
        in: &html,
        appID: "pomodewro"
    )

    replaceOnce(
        """
        clearInterval(timerId);
        timerId = null;
        remainingSeconds = getModeDurationSeconds(state.mode);
        saveState();
        render();
      }
""",
        with:
        """
        clearInterval(timerId);
        timerId = null;
        cancelNativeTimer();
        remainingSeconds = getModeDurationSeconds(state.mode);
        saveState();
        render();
      }
""",
        in: &html,
        appID: "pomodewro"
    )

    replaceOnce(
        """
      function completeTimer() {
""",
        with:
        """
      function completeTimer(alreadyHandledByNative = false) {
""",
        in: &html,
        appID: "pomodewro"
    )

    replaceOnce(
        """
        if (completedMode === "focus") recordFocusSession(completedSeconds);
        try {
          playSelectedSound(completedMode);
        } catch {
          showToast("Could not play alarm");
        }
""",
        with:
        """
        if (completedMode === "focus") recordFocusSession(completedSeconds);
        if (!alreadyHandledByNative) {
          const handledByNative = completeNativeTimer(completedMode);
          if (!handledByNative) {
            try {
              playSelectedSound(completedMode);
            } catch {
              showToast("Could not play alarm");
            }
          }
        }
""",
        in: &html,
        appID: "pomodewro"
    )

    replaceOnce(
        """
        if (remainingSeconds <= 0) {
          completeTimer();
          return true;
        }
""",
        with:
        """
        if (remainingSeconds <= 0) {
          completeTimer(nativeBridgeAvailable());
          return true;
        }
""",
        in: &html,
        appID: "pomodewro"
    )

    replaceOnce(
        """
        timerId = window.setInterval(tick, 250);
        saveState();
        tick();
        return true;
      }
""",
        with:
        """
        timerId = window.setInterval(tick, 250);
        saveState();
        scheduleNativeTimer();
        tick();
        return true;
      }
""",
        in: &html,
        appID: "pomodewro"
    )

    try html.write(to: htmlURL, atomically: true, encoding: .utf8)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fail("usage: sync-apps.swift <project-root> <config-json> <resources-dir>")
}

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
let configURL = URL(fileURLWithPath: arguments[2])
let resourcesURL = URL(fileURLWithPath: arguments[3], isDirectory: true)

do {
    try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

    let data = try Data(contentsOf: configURL)
    let decoder = JSONDecoder()
    let apps = try decoder.decode([AppConfig].self, from: data)
    let bundledAppsURL = resourcesURL.appendingPathComponent("apps", isDirectory: true)

    if fileManager.fileExists(atPath: bundledAppsURL.path) {
        try fileManager.removeItem(at: bundledAppsURL)
    }

    var seenIDs = Set<String>()
    var runtimeApps: [RuntimeApp] = []

    for app in apps {
        guard !app.id.isEmpty else { fail("app id cannot be empty") }
        guard seenIDs.insert(app.id).inserted else { fail("duplicate app id: \(app.id)") }
        guard app.storageNamespace.hasPrefix("deskit.") else {
            fail("\(app.id) storageNamespace must be DeskIt-owned")
        }

        switch app.kind {
        case "web":
            guard let sourceRoot = app.sourceRoot, let sourceItems = app.sourceItems, let bundlePath = app.bundlePath, let entryPath = app.entryPath else {
                fail("\(app.id) web entries require sourceRoot, sourceItems, bundlePath, and entryPath")
            }

            let sourceURL = rootURL.appendingPathComponent(sourceRoot, isDirectory: true).standardizedFileURL
            let destinationURL = resourcesURL.appendingPathComponent(bundlePath, isDirectory: true)

            guard fileManager.fileExists(atPath: sourceURL.path) else {
                fail("\(app.id) source root does not exist: \(sourceURL.path)")
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

            for item in sourceItems {
                let itemSource = sourceURL.appendingPathComponent(item)
                let itemDestination = destinationURL.appendingPathComponent(item)
                guard fileManager.fileExists(atPath: itemSource.path) else {
                    fail("\(app.id) source item does not exist: \(itemSource.path)")
                }
                if fileManager.fileExists(atPath: itemDestination.path) {
                    try fileManager.removeItem(at: itemDestination)
                }
                try fileManager.copyItem(at: itemSource, to: itemDestination)
            }

            let entryURL = resourcesURL.appendingPathComponent(entryPath)
            guard fileManager.fileExists(atPath: entryURL.path) else {
                fail("\(app.id) entryPath does not exist after sync: \(entryURL.path)")
            }

            if app.id == "pomodewro" {
                try patchPomodewro(at: entryURL)
            }

        case "native":
            break

        default:
            fail("\(app.id) has unsupported kind: \(app.kind)")
        }

        runtimeApps.append(RuntimeApp(
            id: app.id,
            name: app.name,
            kind: app.kind,
            entryPath: app.entryPath,
            bridgeHandler: app.bridgeHandler,
            storageNamespace: app.storageNamespace,
            symbolName: app.symbolName,
            accentHex: app.accentHex,
            defaultPopoverSize: app.defaultPopoverSize
        ))
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let runtimeData = try encoder.encode(runtimeApps)
    try runtimeData.write(to: resourcesURL.appendingPathComponent("app-registry.json"), options: .atomic)

    print("Synced \(runtimeApps.count) DeskIt app entries.")
} catch {
    fail(String(describing: error))
}
