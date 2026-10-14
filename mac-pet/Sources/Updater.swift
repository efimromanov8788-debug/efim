// Обновление прямо из программы: проверяет последний релиз на GitHub,
// скачивает его, заменяет себя и перезапускается.

import AppKit

@MainActor
final class Updater {
    static let latestRelease = URL(string: "https://api.github.com/repos/efimromanov8788-debug/efim/releases/latest")!

    var latestVersion: String?
    var downloadURL: URL?
    var installing = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var updateAvailable: Bool {
        guard let latest = latestVersion, downloadURL != nil else { return false }
        return Self.isNewer(latest, than: currentVersion)
    }

    static func numbers(_ version: String) -> [Int] {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = numbers(a)
        let y = numbers(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let assets: [Asset]
    }

    // Возвращает true, если нашлась версия новее установленной
    func check() async -> Bool {
        var request = URLRequest(url: Self.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        guard let response = try? await URLSession.shared.data(for: request),
              let release = try? JSONDecoder().decode(Release.self, from: response.0)
        else { return false }
        latestVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        if let asset = release.assets.first(where: { $0.name == "Murka.zip" }) {
            downloadURL = URL(string: asset.browser_download_url)
        }
        return updateAvailable
    }

    enum UpdateError: Error {
        case translocated, broken
    }

    // Скачивает новую версию и ставит её на место текущей после выхода из программы
    func install(beforeQuit: () -> Void) async throws {
        guard let url = downloadURL else { throw UpdateError.broken }
        let target = Bundle.main.bundleURL
        // macOS запускает программы из «Загрузок» из временной копии — её заменить нельзя
        if target.path.contains("/AppTranslocation/") { throw UpdateError.translocated }

        installing = true
        defer { installing = false }

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("murka-update-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let (downloaded, _) = try await URLSession.shared.download(from: url)
        let zip = dir.appendingPathComponent("Murka.zip")
        try fm.moveItem(at: downloaded, to: zip)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, dir.path]
        try unzip.run()
        unzip.waitUntilExit()
        let newApp = dir.appendingPathComponent("Murka.app")
        guard unzip.terminationStatus == 0, fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/Murka").path)
        else { throw UpdateError.broken }

        // Небольшой скрипт дождётся, пока мы закроемся, заменит программу и запустит новую
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(target.path)"
        mv "\(newApp.path)" "\(target.path)"
        xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null
        open "\(target.path)"
        rm -rf "\(dir.path)"
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script]
        try helper.run()

        beforeQuit()
        NSApp.terminate(nil)
    }
}
