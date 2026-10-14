// Один кот на экране: своё прозрачное окно, поведение по характеру,
// прогулки по полу, окнам, стенам и потолку.

import AppKit

enum WallGoal {
    case none, ceiling, floor
}

enum Action {
    case walk, sleep, hop, windowJump, climb, approach, idle, walkOff
}

struct Heart {
    var x: CGFloat
    var y: CGFloat
    var life: Double
}

@MainActor
final class PetController: NSObject {
    static let size = NSSize(width: 170, height: 150)
    let W: CGFloat = 170
    let gravity: CGFloat = 1800
    // Расстояние от низа окна кота до лап
    let footInset: CGFloat = 3

    unowned let app: AppController
    var config: CatConfig {
        didSet { view.needsDisplay = true }
    }
    var traits: Traits { config.personality.traits }
    var phrases: Phrases { config.personality.phrases }

    let window: NSWindow
    let view: PetView

    // Состояние кота
    var state: PetState = .idle
    var surface: Surface = .floor
    var stateTime: Double = 0
    var stateDuration: Double = 3
    var time: Double = 0
    var dt: CGFloat = 0
    var facingRight = true
    var targetX: CGFloat = 0
    var targetY: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var onGround = true
    var hunger: Double = 0.3
    var followCursor = false
    var pendingClimb = false
    var pendingGreet = false
    // Крепкий сон: кот спит, пока по нему не кликнут, и не просыпается сам
    var deepSleep = false {
        didSet { if oldValue != deepSleep { app.saveSleeping() } }
    }
    var wallGoal: WallGoal = .none
    var walkAfterLanding: CGFloat?
    var bubble: String?
    var bubbleUntil: Double = 0
    var hearts: [Heart] = []
    var nextBlink: Double = 3
    var blinkUntil: Double = 0
    var lastHungryMessage: Double = -100
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0

    // Окно, на котором стоим
    var standingOn: Int?
    var standingMinX: CGFloat = 0

    // Перетаскивание мышью
    var dragStartMouse = NSPoint.zero
    var dragStartOrigin = NSPoint.zero
    var dragged = false

    var pose: CatPose {
        CatPose(state: state, time: time, facingRight: facingRight, surface: surface, onGround: onGround,
                lookX: lookX, lookY: lookY, blinking: time < blinkUntil)
    }

    init(config: CatConfig, app: AppController, startX: CGFloat?) {
        self.config = config
        self.app = app
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = startX ?? CGFloat.random(in: area.minX...max(area.minX, area.maxX - Self.size.width))
        let origin = NSPoint(x: x, y: area.minY)
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
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = view
        view.pet = self
        targetX = origin.x
        time = Double.random(in: 0...10)
        lastHungryMessage = time - 100
        setState(.idle)
    }

    func show() {
        window.orderFrontRegardless()
        if !deepSleep { say(config.line(phrases.greet), 4) }
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    func line(_ list: [String], _ fallback: String = "Мяу!") -> String {
        config.line(list.randomElement() ?? fallback)
    }

    // MARK: - Меню кота

    func makeMenu() -> NSMenu {
        let m = NSMenu(title: config.name)
        let full = Int(((1 - hunger) * 5).rounded())
        let hungerItem = NSMenuItem(title: "Сытость: " + String(repeating: "●", count: full) + String(repeating: "○", count: 5 - full),
                                    action: nil, keyEquivalent: "")
        hungerItem.isEnabled = false
        m.addItem(hungerItem)
        let character = NSMenuItem(title: "Характер: " + config.personality.title, action: nil, keyEquivalent: "")
        character.isEnabled = false
        m.addItem(character)
        m.addItem(.separator())
        m.addItem(item("Покормить 🐟", #selector(feed)))
        m.addItem(item("Погладить", #selector(petMenu)))
        m.addItem(item("Позвать к курсору", #selector(callHere)))
        if deepSleep {
            m.addItem(item("Разбудить ☀️", #selector(petMenu)))
        } else {
            m.addItem(item("Уложить спать до клика 💤", #selector(sleepNow)))
        }
        let follow = item("Ходить за курсором", #selector(toggleFollow))
        follow.state = followCursor ? .on : .off
        m.addItem(follow)
        m.addItem(.separator())
        m.addItem(item("Настроить внешность и характер…", #selector(customize)))
        m.addItem(item("Отпустить погулять (убрать с экрана)", #selector(remove)))
        return m
    }

    func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc func feed() {
        hunger = 0
        setState(.eat)
        say(line(phrases.eat, "Ням-ням!"))
    }

    @objc func petMenu() { pet() }

    @objc func callHere() {
        let x = NSEvent.mouseLocation.x - W / 2
        say("Бегу!", 2)
        if surface != .floor {
            dropToFloor()
            walkAfterLanding = x
        } else {
            targetX = x
            setState(.walk)
        }
    }

    @objc func sleepNow() {
        goToSleep(quiet: false)
    }

    // Уснуть до клика. Со стены или потолка кот сначала спрыгивает вниз
    func goToSleep(quiet: Bool) {
        if surface != .floor {
            surface = .floor
            vx = 0
            vy = 0
            standingOn = nil
        }
        followCursor = false
        setState(.sleep, duration: .infinity)
        deepSleep = true
        if !quiet { say("Спокойной ночи… Разбуди меня кликом 💤", 3) }
    }

    @objc func toggleFollow() {
        followCursor.toggle()
        if followCursor && surface != .floor { dropToFloor() }
        if !followCursor && state == .walk { setState(.idle) }
        say(followCursor ? "Иду за тобой!" : "Гуляю сам" + (config.female ? "а" : "") + " по себе", 2)
    }

    @objc func customize() {
        app.openEditor(for: config.id)
    }

    @objc func remove() {
        app.removeCat(config.id)
    }

    // MARK: - Поведение

    func setState(_ s: PetState, duration: Double? = nil) {
        state = s
        stateTime = 0
        if s != .sleep && deepSleep { deepSleep = false }
        pendingClimb = false
        pendingGreet = false
        wallGoal = .none
        switch s {
        case .idle: stateDuration = duration ?? Double.random(in: traits.idleTime)
        case .sleep: stateDuration = duration ?? Double.random(in: traits.sleepTime)
        case .happy: stateDuration = duration ?? 1.5
        case .hiss: stateDuration = duration ?? 1.3
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

    // Отпустить стену или потолок и упасть вниз
    func dropToFloor() {
        surface = .floor
        vx = 0
        vy = 0
        standingOn = nil
        if state != .sleep { setState(.jump) }
    }

    func addHearts(_ count: Int) {
        for i in 0..<count {
            hearts.append(Heart(
                x: W / 2 + CGFloat.random(in: -35...35),
                y: 70 + CGFloat(i) * 7,
                life: 1.1 + Double(i) * 0.08
            ))
        }
    }

    func pet() {
        if state == .sleep {
            setState(.idle)
            say(line(phrases.wake))
            return
        }
        if Double.random(in: 0..<1) < traits.hissChance {
            setState(.hiss)
            say(line(phrases.hiss, "Ш-ш-ш!"), 2)
            return
        }
        setState(.happy)
        say(line(phrases.pet))
        if surface == .floor && onGround { vy = 260 }
        addHearts(traits.hearts)
    }

    func pick(_ options: [(Action, Double)]) -> Action {
        let total = options.reduce(0) { $0 + max(0, $1.1) }
        guard total > 0 else { return .idle }
        var r = Double.random(in: 0..<total)
        for (action, weight) in options where weight > 0 {
            if r < weight { return action }
            r -= weight
        }
        return options.last?.0 ?? .idle
    }

    func chooseNext(origin: NSPoint, area: NSRect, minX: CGFloat, maxX: CGFloat) {
        let tr = traits
        let adventures = app.adventures
        let canSleep = hunger < 0.75
        let mouseX = NSEvent.mouseLocation.x

        // Стоим на окне: гуляем по нему, иногда до края и вниз
        if adventures, let id = standingOn, let w = app.windows.first(where: { $0.id == id }) {
            let action = pick([
                (.walk, tr.walk), (.walkOff, tr.walk * 0.35), (.windowJump, tr.windowJump * 0.6),
                (.sleep, canSleep ? tr.sleep : 0), (.approach, tr.approach * 0.5), (.idle, tr.idle),
            ])
            switch action {
            case .walk:
                let lo = max(w.rect.minX - W / 2 + 15, minX)
                let hi = min(w.rect.maxX - W / 2 - 15, maxX)
                targetX = hi > lo ? CGFloat.random(in: lo...hi) : origin.x
                setState(.walk)
            case .walkOff:
                targetX = Bool.random() ? w.rect.minX - W : w.rect.maxX
                setState(.walk)
            case .windowJump:
                if !tryJumpToWindow(origin: origin, area: area) { setState(.idle) }
            case .sleep:
                setState(.sleep)
            case .approach:
                approach(mouseX)
            default:
                setState(.idle)
            }
            return
        }

        let action = pick([
            (.walk, tr.walk), (.sleep, canSleep ? tr.sleep : 0), (.hop, tr.hop),
            (.windowJump, adventures ? tr.windowJump : 0), (.climb, adventures ? tr.climb : 0),
            (.approach, tr.approach), (.idle, tr.idle),
        ])
        switch action {
        case .walk, .walkOff:
            targetX = CGFloat.random(in: minX...max(minX, maxX))
            setState(.walk)
        case .windowJump:
            if !tryJumpToWindow(origin: origin, area: area) {
                targetX = CGFloat.random(in: minX...max(minX, maxX))
                setState(.walk)
            }
        case .climb:
            targetX = origin.x - minX < maxX - origin.x ? minX : maxX
            setState(.walk)
            pendingClimb = true
        case .sleep:
            setState(.sleep)
        case .hop:
            jump()
        case .approach:
            approach(mouseX)
        case .idle:
            setState(.idle)
        }
    }

    // Подойти к курсору и поздороваться
    func approach(_ mouseX: CGFloat) {
        targetX = mouseX - W / 2
        setState(.walk)
        pendingGreet = true
    }

    // MARK: - Окна других программ

    func isTopVisible(_ index: Int, x: CGFloat) -> Bool {
        let windows = app.windows
        let top = windows[index].rect.maxY
        return !windows[..<index].contains { $0.rect.contains(NSPoint(x: x, y: top + 2)) }
    }

    // Самая высокая опора под лапами: край окна или низ экрана
    func ground(at cx: CGFloat, feet: CGFloat, area: NSRect) -> (y: CGFloat, id: Int?) {
        var best: (y: CGFloat, id: Int?) = (area.minY, nil)
        guard app.adventures else { return best }
        for (i, w) in app.windows.enumerated() {
            let top = w.rect.maxY
            guard cx > w.rect.minX + 8, cx < w.rect.maxX - 8,
                  top > area.minY + 20, top < area.maxY - 100,
                  top > best.y else { continue }
            // Если окно, на котором сидим, подвинули вверх, едем вместе с ним
            let riding = w.id == standingOn
            guard top <= feet + 1 || (riding && top <= feet + 200) else { continue }
            guard isTopVisible(i, x: cx) else { continue }
            best = (top, w.id)
        }
        return best
    }

    // Запрыгнуть на одно из окон повыше
    func tryJumpToWindow(origin: NSPoint, area: NSRect) -> Bool {
        let feet = origin.y + footInset
        let cx = origin.x + W / 2
        var options: [(x: CGFloat, y: CGFloat)] = []
        for (i, w) in app.windows.enumerated() {
            let top = w.rect.maxY
            let height = top - feet
            guard height > 40, height < 380, top < area.maxY - 100 else { continue }
            let lo = max(w.rect.minX + 40, area.minX + W / 2)
            let hi = min(w.rect.maxX - 40, area.maxX - W / 2)
            guard hi - lo > 40 else { continue }
            let x = CGFloat.random(in: lo...hi)
            guard abs(x - cx) < 700, isTopVisible(i, x: x) else { continue }
            options.append((x: x, y: top))
        }
        guard let target = options.randomElement() else { return false }

        let overshoot: CGFloat = 40
        let v = sqrt(2 * gravity * (target.y - feet + overshoot))
        let flightTime = v / gravity + sqrt(2 * overshoot / gravity)
        vy = v
        vx = (target.x - cx) / flightTime
        facingRight = vx >= 0
        setState(.jump)
        say("Хоп!", 1)
        return true
    }

    // MARK: - Стены и потолок

    func startClimb(left: Bool, origin: inout NSPoint, area: NSRect) {
        surface = left ? .leftWall : .rightWall
        origin.x = left ? area.minX - 11 : area.maxX - W + 11
        origin.y = area.minY + 5
        targetY = CGFloat.random(in: (area.minY + 60)...max(area.minY + 61, area.maxY - 140))
        setState(.walk)
        say("Полезу-ка наверх!", 2)
    }

    func enterCeiling(fromLeft: Bool, origin: inout NSPoint, area: NSRect) {
        surface = .ceiling
        origin.y = area.maxY - 147
        origin.x = fromLeft ? area.minX : area.maxX - W
        targetX = CGFloat.random(in: area.minX...max(area.minX, area.maxX - W))
        setState(.walk)
        say("Я на потолке! 🙃", 2)
    }

    func jumpOffWall(left: Bool, origin: inout NSPoint, area: NSRect) {
        surface = .floor
        origin.x = left ? area.minX : area.maxX - W
        vx = left ? 220 : -220
        vy = 350
        facingRight = left
        standingOn = nil
        setState(.jump)
        say("Прыг!", 1)
    }

    func updateWall(_ origin: inout NSPoint, area: NSRect) {
        let left = surface == .leftWall
        origin.x = left ? area.minX - 11 : area.maxX - W + 11
        let lowY = area.minY + 5
        let topY = max(lowY, area.maxY - 140)

        switch state {
        case .walk:
            let d = targetY - origin.y
            if abs(d) < 2 {
                let goal = wallGoal
                setState(.idle)
                switch goal {
                case .ceiling:
                    enterCeiling(fromLeft: left, origin: &origin, area: area)
                    return
                case .floor:
                    surface = .floor
                    origin.x = left ? area.minX : area.maxX - W
                    origin.y = area.minY
                    facingRight = left
                    return
                case .none:
                    break
                }
            } else {
                let up = d > 0
                facingRight = left ? !up : up
                origin.y += min(abs(d), 55 * traits.speed * dt) * (up ? 1 : -1)
            }
        case .idle:
            if stateTime > stateDuration {
                let r = Double.random(in: 0..<1)
                if r < 0.35 {
                    targetY = CGFloat.random(in: lowY...topY)
                    setState(.walk)
                } else if r < 0.6 {
                    targetY = topY
                    setState(.walk)
                    wallGoal = .ceiling
                } else if r < 0.8 {
                    targetY = lowY
                    setState(.walk)
                    wallGoal = .floor
                } else {
                    jumpOffWall(left: left, origin: &origin, area: area)
                    return
                }
            }
        case .happy, .eat, .hiss:
            if stateTime > stateDuration { setState(.idle) }
        case .sleep, .jump, .held:
            dropToFloor()
            return
        }
        origin.y = min(max(origin.y, lowY), topY)
    }

    func updateCeiling(_ origin: inout NSPoint, area: NSRect, minX: CGFloat, maxX: CGFloat) {
        origin.y = area.maxY - 147
        switch state {
        case .walk:
            let d = targetX - origin.x
            if abs(d) < 2 {
                setState(.idle)
            } else {
                facingRight = d < 0
                origin.x += min(abs(d), 50 * traits.speed * dt) * (d > 0 ? 1 : -1)
            }
        case .idle:
            if stateTime > stateDuration {
                if Bool.random() {
                    targetX = CGFloat.random(in: minX...max(minX, maxX))
                    setState(.walk)
                } else {
                    dropToFloor()
                    say("Уииии!", 1.5)
                    return
                }
            }
        case .happy, .eat, .hiss:
            if stateTime > stateDuration { setState(.idle) }
        case .sleep, .jump, .held:
            dropToFloor()
            return
        }
        origin.x = min(max(origin.x, minX), maxX)
    }

    // MARK: - Пол и окна

    func updateFloor(_ origin: inout NSPoint, area: NSRect, minX: CGFloat, maxX: CGFloat, mouse: NSPoint, dx: CGFloat) {
        // Окно, на котором сидим, сдвинули вбок: едем вместе с ним
        if let id = standingOn, let w = app.windows.first(where: { $0.id == id }) {
            origin.x += w.rect.minX - standingMinX
            standingMinX = w.rect.minX
        }

        let feet = origin.y + footInset
        let g = ground(at: origin.x + W / 2, feet: feet, area: area)

        if feet > g.y + 0.5 || vy > 0 {
            if onGround && vy <= 0 && feet - g.y > 15 && state != .jump && state != .held {
                say("Ой!", 1.5)
            }
            onGround = false
            standingOn = nil
            vy -= gravity * dt
            origin.y += vy * dt
            origin.x += vx * dt
            if origin.y + footInset <= g.y && vy <= 0 {
                origin.y = g.y - footInset
                vy = 0
            }
        } else {
            origin.y = g.y - footInset
            vy = 0
            vx = 0
            onGround = true
            if standingOn != g.id {
                standingOn = g.id
                standingMinX = app.windows.first { $0.id == g.id }?.rect.minX ?? 0
            }
            if state == .jump {
                setState(.idle)
                if let x = walkAfterLanding {
                    walkAfterLanding = nil
                    targetX = x
                    setState(.walk)
                }
            }
        }

        if followCursor && onGround && (state == .idle || state == .walk) {
            let tx = min(max(mouse.x - W / 2, minX), maxX)
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
            if !followCursor && onGround && stateTime > stateDuration {
                chooseNext(origin: origin, area: area, minX: minX, maxX: maxX)
            }
        case .walk:
            targetX = min(max(targetX, minX), maxX)
            let speed: CGFloat = followCursor ? 150 : 70 * traits.speed
            let d = targetX - origin.x
            if abs(d) < 2 {
                let climb = pendingClimb && onGround && standingOn == nil
                let greet = pendingGreet
                setState(.idle)
                if climb {
                    let left = origin.x - minX < maxX - origin.x
                    startClimb(left: left, origin: &origin, area: area)
                    return
                }
                if greet {
                    if abs(dx) > 10 { facingRight = dx > 0 }
                    say(line(phrases.approach))
                    if traits.hearts >= 3 {
                        setState(.happy)
                        addHearts(2)
                    }
                }
            } else {
                facingRight = d > 0
                origin.x += min(abs(d), speed * dt) * (d > 0 ? 1 : -1)
            }
        case .sleep:
            if !deepSleep && stateTime > stateDuration {
                setState(.idle)
                say("Потягушки~", 2)
            }
        case .happy, .eat, .hiss:
            if stateTime > stateDuration { setState(.idle) }
        case .jump, .held:
            break
        }

        origin.x = min(max(origin.x, minX), maxX)
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
            surface = .floor
            standingOn = nil
            setState(.held)
            say(line(phrases.drag), 2)
        }
        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    func mouseUp() {
        if dragged {
            dragged = false
            vx = 0
            vy = 0
            onGround = false
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

    func tick(_ step: Double) {
        dt = CGFloat(step)
        time += step
        stateTime += step
        // Во сне кот голодает вдвое медленнее
        let hungerRate = state == .sleep ? 0.5 : 1
        hunger = min(1, hunger + step * hungerRate / (traits.hungerMinutes * 60))

        let area = currentArea
        let minX = area.minX
        let maxX = area.maxX - W
        var origin = window.frame.origin

        // Глаза следят за курсором
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - (origin.x + W / 2)
        let dy = mouse.y - (origin.y + 45)
        let dist = max(1, hypot(dx, dy))
        lookX = dx / dist * 1.8
        lookY = dy / dist * 1.8

        if blinkUntil < time && time > nextBlink {
            blinkUntil = time + 0.15
            nextBlink = time + Double.random(in: 2...6)
        }

        if state != .held {
            switch surface {
            case .floor:
                updateFloor(&origin, area: area, minX: minX, maxX: maxX, mouse: mouse, dx: dx)
            case .leftWall, .rightWall:
                updateWall(&origin, area: area)
            case .ceiling:
                updateCeiling(&origin, area: area, minX: minX, maxX: maxX)
            }
            window.setFrameOrigin(origin)
        }

        // Напоминает о еде не чаще раза в 10 минут
        if hunger > 0.75 && state != .sleep && time - lastHungryMessage > 600 {
            lastHungryMessage = time
            say(line(phrases.hungry), 4)
        }

        if bubble != nil && time > bubbleUntil { bubble = nil }

        for i in hearts.indices {
            hearts[i].y += 40 * dt
            hearts[i].life -= step
        }
        hearts.removeAll { $0.life <= 0 }

        view.needsDisplay = true
    }
}

// MARK: - Окно кота

@MainActor
final class PetView: NSView {
    weak var pet: PetController?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pet?.mouseDown() }
    override func mouseDragged(with event: NSEvent) { pet?.mouseDragged() }
    override func mouseUp(with event: NSEvent) { pet?.mouseUp() }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = pet?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        guard let p = pet else { return }
        CatRenderer.draw(look: p.config.look, pose: p.pose, in: bounds)
        drawZzz(p)
        drawHearts(p)
        drawBubble(p)
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
        // Под потолком облачко рисуем снизу, иначе оно закроет кота
        let onCeiling = p.surface == .ceiling
        let box = NSRect(x: (bounds.width - w) / 2, y: onCeiling ? 10 : bounds.height - h - 4, width: w, height: h)

        let shape = NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9)
        let tail = onCeiling
            ? CatRenderer.triangle([NSPoint(x: box.midX - 6, y: box.maxY - 1), NSPoint(x: box.midX + 6, y: box.maxY - 1), NSPoint(x: box.midX, y: box.maxY + 7)])
            : CatRenderer.triangle([NSPoint(x: box.midX - 6, y: box.minY + 1), NSPoint(x: box.midX + 6, y: box.minY + 1), NSPoint(x: box.midX, y: box.minY - 7)])
        NSColor.white.withAlphaComponent(0.96).setFill()
        shape.fill()
        tail.fill()
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        s.draw(with: box.insetBy(dx: 8, dy: 5), options: [.usesLineFragmentOrigin])
    }
}
