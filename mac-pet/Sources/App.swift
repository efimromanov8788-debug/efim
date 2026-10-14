// Мурка и компания — настольные коты для macOS.
// Главный контроллер: строка меню, список котов, общий игровой цикл,
// поиск окон других программ и окно настройки.

import AppKit
import ServiceManagement
import SwiftUI

// Окно другой программы, по верхнему краю которого можно ходить
struct SeenWindow {
    let id: Int
    let rect: NSRect
}

@MainActor
final class AppController: NSObject, NSMenuDelegate, NSWindowDelegate {
    static let maxCats = 8

    var cats: [PetController] = []
    var statusItem: NSStatusItem!
    var timer: Timer?
    var lastTick = ProcessInfo.processInfo.systemUptime
    var time: Double = 0

    var windows: [SeenWindow] = []
    var lastWindowScan: Double = -1

    let updater = Updater()
    let clipboard = ClipboardHistory()
    var lastClipboardPoll: Double = 0
    var lastCopyComment: Double = -1e9
    var lastUpdateCheck: Double = -1e9

    var editorWindow: NSWindow?
    var editorOriginal: CatConfig?

    var adventures: Bool = UserDefaults.standard.object(forKey: "adventures") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(adventures, forKey: "adventures")
            if !adventures {
                for cat in cats where cat.surface != .floor { cat.dropToFloor() }
            }
        }
    }

    func start() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"
        statusItem.menu = menu

        loading = true
        let configs = CatStore.load()
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        for (i, config) in configs.enumerated() {
            let step = (area.width - PetController.size.width) / CGFloat(configs.count + 1)
            spawn(config, startX: area.minX + step * CGFloat(i + 1))
        }
        loading = false

        let t = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t

        clipboard.registerHotKey()
        NotificationCenter.default.addObserver(self, selector: #selector(showClipboardAtCursor),
                                               name: .murkaClipboardHotKey, object: nil)
    }

    @discardableResult
    func spawn(_ config: CatConfig, startX: CGFloat? = nil) -> PetController {
        let cat = PetController(config: config, app: self, startX: startX)
        cats.append(cat)
        if sleepingIDs.contains(config.id.uuidString) { cat.goToSleep(quiet: true) }
        cat.show()
        return cat
    }

    // Кто спит до клика — запоминаем, чтобы после перезапуска коты продолжили спать
    var sleepingIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "sleepingCats") ?? [])

    var loading = false

    func saveSleeping() {
        guard !loading else { return }
        sleepingIDs = Set(cats.filter { $0.deepSleep }.map { $0.config.id.uuidString })
        UserDefaults.standard.set(Array(sleepingIDs), forKey: "sleepingCats")
    }

    func save() {
        CatStore.save(cats.map { $0.config })
    }

    func cat(_ id: UUID) -> PetController? {
        cats.first { $0.config.id == id }
    }

    func addCat(_ config: CatConfig) {
        guard cats.count < Self.maxCats else {
            cats.first?.say("Нас и так много! 🐾", 3)
            return
        }
        spawn(config)
        save()
    }

    func removeCat(_ id: UUID) {
        guard let cat = cat(id) else { return }
        guard cats.count > 1 else {
            cat.say("Я тебя не оставлю! ❤", 3)
            return
        }
        if editorOriginal?.id == id { editorWindow?.close() }
        cat.close()
        cats.removeAll { $0 === cat }
        save()
        saveSleeping()
    }

    // MARK: - Меню в строке меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for cat in cats {
            let item = NSMenuItem(title: "🐱 " + cat.config.name, action: nil, keyEquivalent: "")
            item.submenu = cat.makeMenu()
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let add = NSMenuItem(title: "Добавить кота", action: nil, keyEquivalent: "")
        let addMenu = NSMenu()
        for (i, preset) in Presets.all.enumerated() {
            let item = NSMenuItem(title: "\(preset.name) — \(preset.personality.title.lowercased())",
                                  action: #selector(addPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            addMenu.addItem(item)
        }
        addMenu.addItem(.separator())
        addMenu.addItem(item("Создать своего…", #selector(createCustom)))
        add.submenu = addMenu
        add.isEnabled = cats.count < Self.maxCats
        menu.addItem(add)

        menu.addItem(item("Покормить всех 🐟", #selector(feedAll)))
        if cats.allSatisfy({ $0.deepSleep }) {
            menu.addItem(item("Разбудить всех ☀️", #selector(wakeAll)))
        } else {
            menu.addItem(item("Уложить всех спать 💤", #selector(sleepAll)))
        }
        let clip = NSMenuItem(title: "📋 Буфер обмена   ⌃⌥V", action: nil, keyEquivalent: "")
        clip.submenu = makeClipboardMenu(withSettings: true)
        menu.addItem(clip)
        let adv = item("Лазать по окнам и стенам", #selector(toggleAdventures))
        adv.state = adventures ? .on : .off
        menu.addItem(adv)
        menu.addItem(.separator())

        if updater.installing {
            let busy = NSMenuItem(title: "Скачиваю обновление…", action: nil, keyEquivalent: "")
            busy.isEnabled = false
            menu.addItem(busy)
        } else if updater.updateAvailable, let v = updater.latestVersion {
            menu.addItem(item("⬆️ Обновить до версии \(v)", #selector(installUpdate)))
        } else {
            menu.addItem(item("Проверить обновления", #selector(checkUpdatesManually)))
        }
        let version = NSMenuItem(title: "Версия \(updater.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let login = item("Запускать при входе в систему", #selector(toggleLogin))
        if #available(macOS 13.0, *) {
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }
        menu.addItem(item("Выйти", #selector(quit)))
    }

    func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc func addPreset(_ sender: NSMenuItem) {
        guard Presets.all.indices.contains(sender.tag) else { return }
        addCat(Presets.all[sender.tag].copy())
    }

    @objc func createCustom() {
        var fresh = Presets.all.randomElement()!.copy()
        fresh.name = "Новый котик"
        fresh.female = false
        showEditor(config: fresh, isNew: true)
    }

    @objc func feedAll() {
        for cat in cats { cat.feed() }
    }

    @objc func sleepAll() {
        for cat in cats where !cat.deepSleep { cat.goToSleep(quiet: false) }
    }

    @objc func wakeAll() {
        for cat in cats where cat.deepSleep { cat.pet() }
    }

    @objc func toggleAdventures() {
        adventures.toggle()
    }

    @objc func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            cats.first?.say("Не получилось 😿", 3)
        }
    }

    // MARK: - Буфер обмена

    func makeClipboardMenu(withSettings: Bool) -> NSMenu {
        let m = NSMenu(title: "Буфер обмена")
        if !clipboard.enabled {
            let off = NSMenuItem(title: "Кот не запоминает скопированное", action: nil, keyEquivalent: "")
            off.isEnabled = false
            m.addItem(off)
        } else if clipboard.items.isEmpty {
            let empty = NSMenuItem(title: "Пока ничего не скопировано", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            m.addItem(empty)
        } else {
            let hint = NSMenuItem(title: "Нажми — и вставляй через ⌘V", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            m.addItem(hint)
            for (i, text) in clipboard.items.enumerated() {
                let it = item(ClipboardHistory.title(text), #selector(copyClip(_:)))
                it.representedObject = text
                it.toolTip = String(text.prefix(500))
                if i < 9 { it.keyEquivalent = String(i + 1) }
                it.keyEquivalentModifierMask = []
                m.addItem(it)
            }
        }
        m.addItem(.separator())
        if clipboard.enabled && !clipboard.items.isEmpty {
            m.addItem(item("Очистить историю", #selector(clearClipboard)))
        }
        if withSettings {
            let toggle = item("Запоминать скопированное", #selector(toggleClipboard))
            toggle.state = clipboard.enabled ? .on : .off
            m.addItem(toggle)
        }
        return m
    }

    @objc func copyClip(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        clipboard.copy(text)
        if let cat = cats.randomElement() {
            cat.say(cat.config.line("Скопировал{а}! Вставляй ⌘V 📋"), 2.5)
        }
    }

    @objc func clearClipboard() {
        clipboard.clear()
        cats.first?.say("Всё забыл" + ((cats.first?.config.female ?? false) ? "а" : "") + "! 🧹", 2)
    }

    @objc func toggleClipboard() {
        clipboard.enabled.toggle()
    }

    // ⌃⌥V: показать историю прямо у курсора, не отбирая фокус у текущей программы
    @objc func showClipboardAtCursor() {
        let m = makeClipboardMenu(withSettings: false)
        m.popUp(positioning: m.items.first(where: { $0.isEnabled }), at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Обновления

    func checkForUpdates(manual: Bool) {
        lastUpdateCheck = time
        Task { @MainActor in
            let found = await updater.check()
            if found, let v = updater.latestVersion {
                cats.first?.say("Вышла новая версия \(v)! Обнови меня через 🐱 в строке меню ⬆️", 6)
            } else if manual {
                cats.first?.say(updater.latestVersion == nil ? "Не получилось проверить 😿 Нет интернета?" : "У меня самая новая версия ✓", 4)
            }
        }
    }

    @objc func checkUpdatesManually() {
        checkForUpdates(manual: true)
    }

    @objc func installUpdate() {
        cats.first?.say("Скачиваю обновление… ⬇️", 10)
        Task { @MainActor in
            do {
                try await updater.install(beforeQuit: { save() })
            } catch Updater.UpdateError.translocated {
                cats.first?.say("Сначала перетащи меня в «Программы», а потом обнови", 6)
            } catch {
                cats.first?.say("Не получилось обновиться 😿 Попробуй позже", 5)
            }
        }
    }

    @objc func quit() {
        save()
        NSApp.terminate(nil)
    }

    // MARK: - Окно настройки

    func openEditor(for id: UUID) {
        guard let cat = cat(id) else { return }
        showEditor(config: cat.config, isNew: false)
    }

    func showEditor(config: CatConfig, isNew: Bool) {
        // Если уже открыто окно для другого кота — откатываем его несохранённые изменения
        closeEditor(revert: true)
        editorOriginal = isNew ? nil : config

        let model = CatEditorModel(config: config, isNew: isNew)
        model.onChange = { [weak self] c in
            // Изменения сразу видны на коте, который уже гуляет по экрану
            if !isNew { self?.cat(c.id)?.config = c }
        }
        model.onSave = { [weak self] c in
            guard let self else { return }
            if isNew {
                self.addCat(c)
            } else {
                self.cat(c.id)?.config = c
                self.cat(c.id)?.say(c.line("Теперь я {name}! ❤"), 3)
                self.save()
            }
            self.editorOriginal = nil
            self.closeEditor(revert: false)
        }
        model.onCancel = { [weak self] in
            self?.closeEditor(revert: true)
        }

        let host = NSHostingController(rootView: CatEditorView(model: model))
        let w = NSWindow(contentViewController: host)
        w.title = isNew ? "Новый кот" : "Настройка: \(config.name)"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        editorWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func closeEditor(revert: Bool) {
        if revert, let original = editorOriginal {
            cat(original.id)?.config = original
        }
        editorOriginal = nil
        let w = editorWindow
        editorWindow = nil
        w?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === editorWindow else { return }
        // Закрыли крестиком — изменения не сохраняем
        if let original = editorOriginal {
            cat(original.id)?.config = original
        }
        editorOriginal = nil
        editorWindow = nil
    }

    // MARK: - Окна других программ

    func scanWindows() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        var found: [SeenWindow] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int) != myPID,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.1 { continue }
            if b.width < 120 || b.height < 60 { continue }
            // У CoreGraphics ось Y идёт сверху вниз от главного экрана, у AppKit — снизу вверх
            found.append(SeenWindow(id: id, rect: NSRect(x: b.minX, y: primaryHeight - b.maxY, width: b.width, height: b.height)))
        }
        windows = found
    }

    // MARK: - Игровой цикл

    @objc func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let step = min(0.05, now - lastTick)
        lastTick = now
        time += step

        if adventures && time - lastWindowScan > 0.25 {
            lastWindowScan = time
            scanWindows()
        }
        for cat in cats { cat.tick(step) }

        // Дважды в секунду смотрим, не скопировали ли что-то новое
        if time - lastClipboardPoll > 0.5 {
            lastClipboardPoll = time
            if clipboard.poll() != nil, time - lastCopyComment > 120, Double.random(in: 0..<1) < 0.3,
               let cat = cats.randomElement(), cat.state != .sleep {
                lastCopyComment = time
                cat.say(cat.config.line("Запомнил{а} 📋"), 1.5)
            }
        }

        // Проверяем обновления через 10 секунд после запуска и потом раз в 12 часов
        if time > 10 && time - lastUpdateCheck > 12 * 3600 && !updater.installing {
            checkForUpdates(manual: false)
        }
    }
}

// MARK: - Запуск

@main
enum MurkaApp {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            IconRenderer.render(to: args[i + 1])
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = AppController()
        controller.start()
        withExtendedLifetime(controller) {
            app.run()
        }
    }
}
