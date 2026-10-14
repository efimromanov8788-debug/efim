// Мурка — настольный питомец для macOS.
// Прозрачное окно поверх всех окон, котёнок гуляет над Dock,
// следит глазами за курсором, спит, просит есть и радуется, когда его гладят.

import AppKit
import ServiceManagement

enum PetState {
    case idle, walk, sleep, jump, happy, eat, held
}

struct Heart {
    var x: CGFloat
    var y: CGFloat
    var life: Double
}

@MainActor
final class PetController: NSObject, NSMenuDelegate {
    static let size = NSSize(width: 170, height: 150)

    let window: NSWindow
    let view: PetView
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var followItem: NSMenuItem!
    var hungerItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var timer: Timer?
    var lastTick = ProcessInfo.processInfo.systemUptime

    // Состояние питомца
    var state: PetState = .idle
    var stateTime: Double = 0
    var stateDuration: Double = 3
    var time: Double = 0
    var facingRight = true
    var targetX: CGFloat = 0
    var vy: CGFloat = 0
    var onGround = true
    var hunger: Double = 0.3
    var followCursor = false
    var bubble: String?
    var bubbleUntil: Double = 0
    var hearts: [Heart] = []
    var nextBlink: Double = 3
    var blinkUntil: Double = 0
    var lastHungryMessage: Double = -100
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0

    // Перетаскивание мышью
    var dragStartMouse = NSPoint.zero
    var dragStartOrigin = NSPoint.zero
    var dragged = false

    let petPhrases = [
        "Мяу!", "Мрр~", "Погладь ещё!", "Я тебя люблю ❤", "Мур-мур-мур",
        "Ты сегодня молодец!", "Пора сделать перерыв?", "Мяу? 🐾",
    ]

    init(screen: NSScreen?) {
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: area.midX - Self.size.width / 2, y: area.minY)
        window = NSWindow(
            contentRect: NSRect(origin: origin, size: Self.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        view = PetView(frame: NSRect(origin: .zero, size: Self.size))
        super.init()

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = view
        view.pet = self
        targetX = origin.x

        buildMenu()
    }

    func start() {
        window.orderFrontRegardless()
        let t = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        say("Привет! Я Мурка 🐱", 4)
    }

    // MARK: - Меню

    func buildMenu() {
        let m = NSMenu()
        m.delegate = self

        hungerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hungerItem.isEnabled = false
        m.addItem(hungerItem)
        m.addItem(.separator())

        m.addItem(item("Покормить 🐟", #selector(feed)))
        m.addItem(item("Погладить", #selector(petMenu)))
        m.addItem(item("Позвать к курсору", #selector(callHere)))
        m.addItem(item("Уложить спать", #selector(sleepNow)))
        followItem = item("Ходить за курсором", #selector(toggleFollow))
        m.addItem(followItem)
        m.addItem(.separator())

        loginItem = item("Запускать при входе в систему", #selector(toggleLogin))
        m.addItem(loginItem)
        m.addItem(item("Выйти", #selector(quit)))

        menu = m
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"
        statusItem.menu = m
    }

    func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    func menuWillOpen(_ menu: NSMenu) {
        let full = Int(((1 - hunger) * 5).rounded())
        hungerItem.title = "Сытость: " + String(repeating: "●", count: full) + String(repeating: "○", count: 5 - full)
        followItem.state = followCursor ? .on : .off
        if #available(macOS 13.0, *) {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            loginItem.isHidden = true
        }
    }

    @objc func feed() {
        hunger = 0
        setState(.eat)
        say("Ням-ням! 🐟 Спасибо!")
    }

    @objc func petMenu() { pet() }

    @objc func callHere() {
        targetX = NSEvent.mouseLocation.x - Self.size.width / 2
        setState(.walk)
        say("Бегу!", 2)
    }

    @objc func sleepNow() {
        setState(.sleep, duration: 60)
        say("Спокойной ночи…", 2)
    }

    @objc func toggleFollow() {
        followCursor.toggle()
        if !followCursor && state == .walk { setState(.idle) }
        say(followCursor ? "Иду за тобой!" : "Гуляю сама по себе", 2)
    }

    @objc func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                say("Ладно, буду ждать, когда позовёшь", 3)
            } else {
                try SMAppService.mainApp.register()
                say("Буду встречать тебя каждый день!", 3)
            }
        } catch {
            say("Не получилось 😿", 3)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Поведение

    func setState(_ s: PetState, duration: Double? = nil) {
        state = s
        stateTime = 0
        switch s {
        case .idle: stateDuration = duration ?? Double.random(in: 2...5)
        case .sleep: stateDuration = duration ?? Double.random(in: 12...30)
        case .happy: stateDuration = duration ?? 1.5
        case .eat: stateDuration = duration ?? 2.5
        default: stateDuration = duration ?? 0
        }
    }

    func say(_ text: String, _ seconds: Double = 3) {
        bubble = text
        bubbleUntil = time + seconds
    }

    func jump(_ power: CGFloat = 520) {
        vy = power
        setState(.jump)
    }

    func pet() {
        if state == .sleep {
            setState(.idle)
            say("Мрр? Я спала…")
            return
        }
        setState(.happy)
        say(petPhrases.randomElement() ?? "Мяу!")
        vy = 260
        for i in 0..<3 {
            hearts.append(Heart(
                x: Self.size.width / 2 + CGFloat.random(in: -30...30),
                y: 70 + CGFloat(i) * 8,
                life: 1.3
            ))
        }
    }

    func chooseNext(minX: CGFloat, maxX: CGFloat) {
        let r = Double.random(in: 0..<1)
        if r < 0.55 {
            targetX = CGFloat.random(in: minX...max(minX, maxX))
            setState(.walk)
        } else if r < 0.7 && hunger < 0.75 {
            setState(.sleep)
        } else if r < 0.8 {
            jump()
        } else {
            setState(.idle)
        }
    }

    // MARK: - Мышь

    func mouseDown() {
        dragged = false
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window.frame.origin
    }

    func mouseDragged() {
        let m = NSEvent.mouseLocation
        let dx = m.x - dragStartMouse.x
        let dy = m.y - dragStartMouse.y
        if !dragged {
            if hypot(dx, dy) < 4 { return }
            dragged = true
            setState(.held)
            say("Ай! Поставь меня!", 2)
        }
        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    func mouseUp() {
        if dragged {
            dragged = false
            vy = 0
            setState(.jump)
            say("Уф!", 1.5)
        } else {
            pet()
        }
    }

    // MARK: - Игровой цикл

    var currentArea: NSRect {
        let c = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(c) } ?? window.screen ?? NSScreen.main
        return screen?.visibleFrame ?? window.frame
    }

    @objc func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, now - lastTick)
        lastTick = now
        time += dt
        stateTime += dt
        hunger = min(1, hunger + dt / 900)

        let area = currentArea
        let floorY = area.minY
        let minX = area.minX
        let maxX = area.maxX - Self.size.width
        var origin = window.frame.origin

        // Глаза следят за курсором
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - (origin.x + Self.size.width / 2)
        let dy = mouse.y - (origin.y + 45)
        let dist = max(1, hypot(dx, dy))
        lookX = dx / dist * 1.8
        lookY = dy / dist * 1.8

        if blinkUntil < time && time > nextBlink {
            blinkUntil = time + 0.15
            nextBlink = time + Double.random(in: 2...6)
        }

        if state != .held {
            // Гравитация
            if origin.y > floorY + 0.5 || vy > 0 {
                onGround = false
                vy -= 1800 * CGFloat(dt)
                origin.y += vy * CGFloat(dt)
                if origin.y <= floorY {
                    origin.y = floorY
                    vy = 0
                }
            } else {
                origin.y = floorY
                vy = 0
                onGround = true
                if state == .jump { setState(.idle) }
            }

            if followCursor && (state == .idle || state == .walk) {
                let tx = min(max(mouse.x - Self.size.width / 2, minX), maxX)
                if abs(tx - origin.x) > 30 {
                    targetX = tx
                    if state != .walk { setState(.walk) }
                } else if state == .walk {
                    setState(.idle)
                }
            }

            switch state {
            case .idle:
                if abs(dx) > 40 { facingRight = dx > 0 }
                if !followCursor && stateTime > stateDuration {
                    chooseNext(minX: minX, maxX: maxX)
                }
            case .walk:
                let speed: CGFloat = followCursor ? 150 : 70
                let d = targetX - origin.x
                if abs(d) < 2 {
                    setState(.idle)
                } else {
                    facingRight = d > 0
                    origin.x += min(abs(d), speed * CGFloat(dt)) * (d > 0 ? 1 : -1)
                }
            case .sleep:
                if stateTime > stateDuration {
                    setState(.idle)
                    say("Потягушки~", 2)
                }
            case .happy, .eat:
                if stateTime > stateDuration { setState(.idle) }
            case .jump, .held:
                break
            }

            origin.x = min(max(origin.x, minX), maxX)
            window.setFrameOrigin(origin)
        }

        if hunger > 0.75 && state != .sleep && time - lastHungryMessage > 45 {
            lastHungryMessage = time
            say("Я голодная… покорми меня 🐟", 4)
        }

        if bubble != nil && time > bubbleUntil { bubble = nil }

        for i in hearts.indices {
            hearts[i].y += 40 * CGFloat(dt)
            hearts[i].life -= dt
        }
        hearts.removeAll { $0.life <= 0 }

        view.needsDisplay = true
    }
}

// MARK: - Отрисовка

@MainActor
final class PetView: NSView {
    weak var pet: PetController?

    let fur = NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.27, alpha: 1)
    let furDark = NSColor(calibratedRed: 0.85, green: 0.43, blue: 0.14, alpha: 1)
    let pink = NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.68, alpha: 1)
    let ink = NSColor(calibratedWhite: 0.15, alpha: 1)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pet?.mouseDown() }
    override func mouseDragged(with event: NSEvent) { pet?.mouseDragged() }
    override func mouseUp(with event: NSEvent) { pet?.mouseUp() }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = pet?.menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        guard let p = pet else { return }
        drawCat(p)
        drawZzz(p)
        drawHearts(p)
        drawBubble(p)
    }

    func outlined(_ path: NSBezierPath, _ color: NSColor) {
        color.setFill()
        path.fill()
        ink.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    func drawCat(_ p: PetController) {
        let t = p.time
        let walking = p.state == .walk
        let sleeping = p.state == .sleep
        let held = p.state == .held

        if p.onGround {
            NSColor(calibratedWhite: 0, alpha: 0.18).setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.midX - 38, y: 0, width: 76, height: 8)).fill()
        }

        NSGraphicsContext.saveGraphicsState()
        let tr = NSAffineTransform()
        tr.translateX(by: bounds.midX, yBy: 4)
        tr.scaleX(by: p.facingRight ? 1 : -1, yBy: 1)
        tr.concat()

        let bob: CGFloat = walking ? CGFloat(abs(sin(t * 10))) * 2 : CGFloat(sin(t * (sleeping ? 2 : 3)))
        let bodyRect: NSRect
        let head: NSPoint
        let r: CGFloat = 17
        if sleeping {
            bodyRect = NSRect(x: -34, y: 0, width: 64, height: 28 + bob)
            head = NSPoint(x: 22, y: 18 + bob)
        } else {
            bodyRect = NSRect(x: -32, y: 10 + bob, width: 60, height: 30)
            head = NSPoint(x: 26, y: 40 + bob)
        }

        // Хвост
        let tail = NSBezierPath()
        tail.lineCapStyle = .round
        if sleeping {
            tail.move(to: NSPoint(x: -30, y: 10))
            tail.curve(to: NSPoint(x: 4, y: 2), controlPoint1: NSPoint(x: -50, y: -2), controlPoint2: NSPoint(x: -20, y: -6))
        } else {
            let sway = CGFloat(sin(t * (p.state == .happy ? 14 : 3))) * 8
            tail.move(to: NSPoint(x: -28, y: 24 + bob))
            tail.curve(to: NSPoint(x: -44 + sway * 0.3, y: 60 + sway * 0.4),
                       controlPoint1: NSPoint(x: -50, y: 26 + bob),
                       controlPoint2: NSPoint(x: -38 + sway, y: 48))
        }
        ink.setStroke()
        tail.lineWidth = 10
        tail.stroke()
        fur.setStroke()
        tail.lineWidth = 6.5
        tail.stroke()

        // Лапы
        if !sleeping {
            let phase = walking ? CGFloat(sin(t * 12)) : 0
            let legs: [(CGFloat, CGFloat)] = [(-24, phase), (-12, -phase), (6, -phase), (17, phase)]
            for (x, lift) in legs {
                let bottom: CGFloat = held ? -4 : max(0, lift * 4)
                let top = bodyRect.minY + 8
                let leg = NSBezierPath(roundedRect: NSRect(x: x, y: bottom, width: 9, height: top - bottom),
                                       xRadius: 4.5, yRadius: 4.5)
                outlined(leg, fur)
            }
        }

        // Тело и полоски
        outlined(NSBezierPath(ovalIn: bodyRect), fur)
        let stripes = NSBezierPath()
        stripes.lineWidth = 3
        stripes.lineCapStyle = .round
        for i in 0..<3 {
            let x = bodyRect.minX + 16 + CGFloat(i) * 10
            stripes.move(to: NSPoint(x: x, y: bodyRect.maxY - 2))
            stripes.line(to: NSPoint(x: x + 3, y: bodyRect.maxY - 9))
        }
        furDark.setStroke()
        stripes.stroke()

        // Уши
        for ear in [
            [NSPoint(x: head.x - 15, y: head.y + 6), NSPoint(x: head.x - 11, y: head.y + 22), NSPoint(x: head.x - 2, y: head.y + 14)],
            [NSPoint(x: head.x + 3, y: head.y + 14), NSPoint(x: head.x + 12, y: head.y + 22), NSPoint(x: head.x + 15, y: head.y + 5)],
        ] {
            outlined(triangle(ear), fur)
            let cx = (ear[0].x + ear[1].x + ear[2].x) / 3
            let cy = (ear[0].y + ear[1].y + ear[2].y) / 3
            let inner = ear.map { NSPoint(x: cx + ($0.x - cx) * 0.5, y: cy + ($0.y - cy) * 0.5) }
            pink.setFill()
            triangle(inner).fill()
        }

        // Голова
        outlined(NSBezierPath(ovalIn: NSRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)), fur)

        // Глаза
        let closed = sleeping || p.state == .happy || p.state == .eat || p.time < p.blinkUntil
        let lx = p.lookX * (p.facingRight ? 1 : -1)
        let ly = p.lookY
        for ex in [head.x - 3, head.x + 8] {
            let ey = head.y + 2
            if closed {
                let lid = NSBezierPath()
                lid.lineWidth = 2
                lid.lineCapStyle = .round
                if sleeping {
                    lid.move(to: NSPoint(x: ex - 3, y: ey))
                    lid.curve(to: NSPoint(x: ex + 3, y: ey), controlPoint1: NSPoint(x: ex - 1, y: ey - 3), controlPoint2: NSPoint(x: ex + 1, y: ey - 3))
                } else {
                    lid.move(to: NSPoint(x: ex - 3, y: ey - 1))
                    lid.line(to: NSPoint(x: ex, y: ey + 2))
                    lid.line(to: NSPoint(x: ex + 3, y: ey - 1))
                }
                ink.setStroke()
                lid.stroke()
            } else {
                let size: CGFloat = held ? 8 : 6
                ink.setFill()
                NSBezierPath(ovalIn: NSRect(x: ex - size / 2 + lx, y: ey - size / 2 - 0.5 + ly, width: size, height: size + 1)).fill()
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: ex - 1 + lx, y: ey + 0.5 + ly, width: 2.2, height: 2.2)).fill()
            }
        }

        // Румянец
        if p.state == .happy || p.state == .eat {
            pink.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: NSRect(x: head.x - 11, y: head.y - 8, width: 7, height: 4)).fill()
            NSBezierPath(ovalIn: NSRect(x: head.x + 8, y: head.y - 8, width: 7, height: 4)).fill()
        }

        // Нос и рот
        let nx = head.x + 13
        let ny = head.y - 3
        pink.setFill()
        triangle([NSPoint(x: nx - 2, y: ny + 1.5), NSPoint(x: nx + 2, y: ny + 1.5), NSPoint(x: nx, y: ny - 1.5)]).fill()
        if p.state == .eat || held {
            let open = p.state == .eat ? 2 + CGFloat(abs(sin(t * 12))) * 3 : 4
            outlined(NSBezierPath(ovalIn: NSRect(x: nx - 2.5, y: ny - 4 - open, width: 5, height: open)), pink)
        } else {
            let mouth = NSBezierPath()
            mouth.lineWidth = 1.3
            mouth.move(to: NSPoint(x: nx - 3.5, y: ny - 3.5))
            mouth.curve(to: NSPoint(x: nx, y: ny - 2.5), controlPoint1: NSPoint(x: nx - 2.5, y: ny - 5.5), controlPoint2: NSPoint(x: nx - 0.5, y: ny - 5))
            mouth.curve(to: NSPoint(x: nx + 3.5, y: ny - 3.5), controlPoint1: NSPoint(x: nx + 0.5, y: ny - 5), controlPoint2: NSPoint(x: nx + 2.5, y: ny - 5.5))
            ink.setStroke()
            mouth.stroke()
        }

        // Усы
        let whiskers = NSBezierPath()
        whiskers.lineWidth = 1
        for (from, to) in [
            (NSPoint(x: nx + 1, y: ny - 2), NSPoint(x: nx + 13, y: ny)),
            (NSPoint(x: nx + 1, y: ny - 3), NSPoint(x: nx + 13, y: ny - 5)),
            (NSPoint(x: head.x - 8, y: ny - 2), NSPoint(x: head.x - 20, y: ny)),
            (NSPoint(x: head.x - 8, y: ny - 3), NSPoint(x: head.x - 20, y: ny - 5)),
        ] {
            whiskers.move(to: from)
            whiskers.line(to: to)
        }
        ink.withAlphaComponent(0.6).setStroke()
        whiskers.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }

    func triangle(_ pts: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: pts[0])
        path.line(to: pts[1])
        path.line(to: pts[2])
        path.close()
        return path
    }

    func drawZzz(_ p: PetController) {
        guard p.state == .sleep else { return }
        for i in 0..<3 {
            let phase = CGFloat((p.time * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1))
            let x = bounds.midX + (p.facingRight ? 18 : -30) + phase * 18
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 10 + phase * 8),
                .foregroundColor: NSColor.systemBlue.withAlphaComponent(1 - phase),
            ]
            NSAttributedString(string: "z", attributes: attrs).draw(at: NSPoint(x: x, y: 40 + phase * 45))
        }
    }

    func drawHearts(_ p: PetController) {
        for h in p.hearts {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.systemPink.withAlphaComponent(CGFloat(min(1, h.life))),
            ]
            NSAttributedString(string: "♥", attributes: attrs).draw(at: NSPoint(x: h.x, y: h.y))
        }
    }

    func drawBubble(_ p: PetController) {
        guard let text = p.bubble else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let textRect = s.boundingRect(with: NSSize(width: bounds.width - 24, height: 60), options: [.usesLineFragmentOrigin])
        let w = ceil(textRect.width) + 16
        let h = ceil(textRect.height) + 10
        let box = NSRect(x: (bounds.width - w) / 2, y: bounds.height - h - 4, width: w, height: h)

        let shape = NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9)
        let tail = triangle([NSPoint(x: box.midX - 6, y: box.minY + 1), NSPoint(x: box.midX + 6, y: box.minY + 1), NSPoint(x: box.midX, y: box.minY - 7)])
        NSColor.white.withAlphaComponent(0.96).setFill()
        shape.fill()
        tail.fill()
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        s.draw(with: box.insetBy(dx: 8, dy: 5), options: [.usesLineFragmentOrigin])
    }
}

// MARK: - Запуск

@main
enum MurkaApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let pet = PetController(screen: NSScreen.main)
        pet.start()
        withExtendedLifetime(pet) {
            app.run()
        }
    }
}
