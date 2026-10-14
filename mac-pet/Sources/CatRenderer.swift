// Рисует кота по его внешности (CatLook) и текущей позе (CatPose).
// Используется и для котов на экране, и для превью в окне настройки.

import AppKit

enum PetState {
    case idle, walk, sleep, jump, happy, eat, held, hiss
}

// По какой поверхности сейчас ходит кот
enum Surface {
    case floor, leftWall, rightWall, ceiling
}

struct CatPose {
    var state: PetState
    var time: Double
    var facingRight: Bool
    var surface: Surface
    var onGround: Bool
    var lookX: CGFloat
    var lookY: CGFloat
    var blinking: Bool
}

@MainActor
enum CatRenderer {
    static let ink = NSColor(calibratedWhite: 0.15, alpha: 1)
    static let pink = NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.68, alpha: 1)
    static let darkPatch = NSColor(calibratedWhite: 0.2, alpha: 1)
    static let gold = NSColor(calibratedRed: 0.91, green: 0.73, blue: 0.14, alpha: 1)

    static func outlined(_ path: NSBezierPath, _ color: NSColor, width: CGFloat = 2) {
        color.setFill()
        path.fill()
        ink.setStroke()
        path.lineWidth = width
        path.stroke()
    }

    static func triangle(_ pts: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: pts[0])
        path.line(to: pts[1])
        path.line(to: pts[2])
        path.close()
        return path
    }

    static func line(_ from: NSPoint, _ to: NSPoint, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.move(to: from)
        path.line(to: to)
        color.setStroke()
        path.stroke()
    }

    // Рисует что-то внутри фигуры, не вылезая за её края
    static func clipped(to path: NSBezierPath, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
    }

    static func draw(look: CatLook, pose p: CatPose, in bounds: NSRect, baseY: CGFloat = 4, zoom: CGFloat = 1) {
        let t = p.time
        let walking = p.state == .walk
        let sleeping = p.state == .sleep
        let held = p.state == .held
        let hissing = p.state == .hiss

        let fur = look.fur.ns
        let accent = look.patternColor.ns
        let belly = look.belly.ns
        let pointed = look.pattern == .pointed

        // На стенах и потолке поворачиваем кота лапами к краю экрана
        let angle: CGFloat
        switch p.surface {
        case .floor: angle = 0
        case .leftWall: angle = -90
        case .rightWall: angle = 90
        case .ceiling: angle = 180
        }

        let s = look.size.scale * zoom
        NSGraphicsContext.saveGraphicsState()
        let tr = NSAffineTransform()
        tr.translateX(by: bounds.midX, yBy: bounds.midY)
        tr.rotate(byDegrees: angle)
        tr.translateX(by: -bounds.midX, yBy: -bounds.midY)
        tr.translateX(by: bounds.midX, yBy: baseY)
        tr.scaleX(by: (p.facingRight ? 1 : -1) * s, yBy: s)
        tr.concat()

        let wide = look.size.widthFactor
        let tall = look.size.heightFactor

        if p.onGround && p.surface == .floor {
            NSColor(calibratedWhite: 0, alpha: 0.18).setFill()
            oval(0, 0, 76 * wide, 8).fill()
        }

        let bob: CGFloat = walking ? CGFloat(abs(sin(t * 10))) * 2 : CGFloat(sin(t * (sleeping ? 2 : 3)))
        let r: CGFloat = 17 * look.size.headFactor
        let k = r / 17
        let bodyRect: NSRect
        let head: NSPoint
        if sleeping {
            bodyRect = NSRect(x: -34 * wide, y: 0, width: 64 * wide, height: (28 + bob) * tall)
            head = NSPoint(x: 22 * wide, y: 18 * tall + bob)
        } else {
            bodyRect = NSRect(x: -32 * wide, y: 10 + bob, width: 60 * wide, height: 30 * tall)
            head = NSPoint(x: 26 * wide, y: 40 + bob + (tall - 1) * 30)
        }
        func hp(_ dx: CGFloat, _ dy: CGFloat) -> NSPoint {
            NSPoint(x: head.x + dx * k, y: head.y + dy * k)
        }

        // Хвост
        let tail = NSBezierPath()
        tail.lineCapStyle = .round
        let L = CGFloat(look.tail)
        if sleeping {
            tail.move(to: NSPoint(x: -30 * wide, y: 10))
            tail.curve(to: NSPoint(x: 4, y: 2), controlPoint1: NSPoint(x: -50 * wide, y: -2), controlPoint2: NSPoint(x: -20 * wide, y: -6))
        } else {
            let sway = CGFloat(sin(t * (p.state == .happy ? 14 : (hissing ? 20 : 3)))) * (hissing ? 3 : 8)
            let start = NSPoint(x: -28 * wide, y: 24 + bob)
            tail.move(to: start)
            tail.curve(to: NSPoint(x: start.x + (-16 + sway * 0.3) * L, y: start.y + (36 + sway * 0.4) * L),
                       controlPoint1: NSPoint(x: start.x - 22 * L, y: start.y + 2 * L),
                       controlPoint2: NSPoint(x: start.x + (-10 + sway) * L, y: start.y + 24 * L))
        }
        let tailWidth: CGFloat = hissing ? 11 : 6.5
        ink.setStroke()
        tail.lineWidth = tailWidth + 3.5
        tail.stroke()
        (pointed ? accent : fur).setStroke()
        tail.lineWidth = tailWidth
        tail.stroke()
        if look.pattern == .stripes && !sleeping {
            accent.setStroke()
            tail.lineWidth = tailWidth
            let dash: [CGFloat] = [3, 7]
            tail.setLineDash(dash, count: 2, phase: 0)
            tail.lineCapStyle = .butt
            tail.stroke()
        }

        // Лапы
        if !sleeping {
            let phase = walking ? CGFloat(sin(t * 12)) : 0
            let legs: [(CGFloat, CGFloat)] = [(-24, phase), (-12, -phase), (6, -phase), (17, phase)]
            for (x, lift) in legs {
                let bottom: CGFloat = held ? -4 : max(0, lift * 4)
                let top = bodyRect.minY + 8
                let leg = NSBezierPath(roundedRect: NSRect(x: x * wide, y: bottom, width: 9, height: top - bottom),
                                       xRadius: 4.5, yRadius: 4.5)
                outlined(leg, pointed ? accent : fur)
                if look.pattern == .tuxedo {
                    clipped(to: leg) {
                        belly.setFill()
                        NSRect(x: x * wide, y: bottom, width: 9, height: 6).fill()
                    }
                    ink.setStroke()
                    leg.stroke()
                }
            }
        }

        // Тело и узор на нём
        let body = NSBezierPath(ovalIn: bodyRect)
        outlined(body, fur)
        let w = bodyRect.width
        let h = bodyRect.height
        clipped(to: body) {
            belly.setFill()
            oval(bodyRect.midX + w * 0.1, bodyRect.minY, w * 0.7, h * 0.7).fill()
            switch look.pattern {
            case .spots:
                accent.setFill()
                oval(bodyRect.minX + w * 0.3, bodyRect.minY + h * 0.7, 13, 9).fill()
                oval(bodyRect.minX + w * 0.6, bodyRect.minY + h * 0.78, 10, 8).fill()
                oval(bodyRect.minX + w * 0.15, bodyRect.minY + h * 0.4, 8, 7).fill()
            case .calico:
                accent.setFill()
                oval(bodyRect.minX + w * 0.25, bodyRect.minY + h * 0.65, w * 0.45, h * 0.8).fill()
                darkPatch.setFill()
                oval(bodyRect.minX + w * 0.68, bodyRect.minY + h * 0.75, w * 0.3, h * 0.6).fill()
            case .tuxedo:
                belly.setFill()
                oval(bodyRect.minX + w * 0.75, bodyRect.minY + h * 0.3, w * 0.55, h * 0.9).fill()
            case .solid, .stripes, .pointed:
                break
            }
        }
        ink.setStroke()
        body.lineWidth = 2
        body.stroke()
        if look.pattern == .stripes {
            for i in 0..<3 {
                let x = bodyRect.minX + 16 * wide + CGFloat(i) * 10 * wide
                line(NSPoint(x: x, y: bodyRect.maxY - 2), NSPoint(x: x + 3, y: bodyRect.maxY - 9), width: 3, color: accent)
            }
        }

        // Уши
        let earFill = pointed ? accent : fur
        let ears: [[NSPoint]]
        switch look.ears {
        case .pointy, .round:
            ears = [[hp(-15, 6), hp(-11, 22), hp(-2, 14)], [hp(3, 14), hp(12, 22), hp(15, 5)]]
        case .folded:
            ears = [[hp(-15, 9), hp(-6, 17), hp(-3, 13)], [hp(4, 14), hp(13, 17), hp(15, 8)]]
        }
        for (i, ear) in ears.enumerated() {
            let path: NSBezierPath
            if look.ears == .round {
                path = NSBezierPath()
                path.move(to: ear[0])
                path.curve(to: ear[2],
                           controlPoint1: NSPoint(x: ear[1].x - 6 * k, y: ear[1].y + 2 * k),
                           controlPoint2: NSPoint(x: ear[1].x + 6 * k, y: ear[1].y + 2 * k))
                path.close()
            } else {
                path = triangle(ear)
            }
            let color = (look.pattern == .calico && i == 0) ? darkPatch : earFill
            outlined(path, color)
            if look.ears != .folded {
                let cx = (ear[0].x + ear[1].x + ear[2].x) / 3
                let cy = (ear[0].y + ear[1].y + ear[2].y) / 3
                let inner = ear.map { NSPoint(x: cx + ($0.x - cx) * 0.5, y: cy + ($0.y - cy) * 0.5) }
                pink.setFill()
                triangle(inner).fill()
            }
        }

        // Голова и узор на ней
        let headPath = NSBezierPath(ovalIn: NSRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2))
        outlined(headPath, fur)
        clipped(to: headPath) {
            switch look.pattern {
            case .pointed:
                accent.withAlphaComponent(0.85).setFill()
                oval(hp(9, -4).x, hp(9, -4).y, 24 * k, 19 * k).fill()
            case .calico:
                darkPatch.setFill()
                oval(hp(-14, 6).x, hp(-14, 6).y, 18 * k, 22 * k).fill()
                accent.setFill()
                oval(hp(4, 16).x, hp(4, 16).y, 16 * k, 12 * k).fill()
            case .tuxedo:
                belly.setFill()
                oval(hp(9, -8).x, hp(9, -8).y, 22 * k, 14 * k).fill()
            case .spots:
                accent.setFill()
                oval(hp(-8, 8).x, hp(-8, 8).y, 7 * k, 6 * k).fill()
            case .solid, .stripes:
                break
            }
        }
        ink.setStroke()
        headPath.lineWidth = 2
        headPath.stroke()
        if look.pattern == .stripes {
            line(hp(-5, 14), hp(-4, 9), width: 2, color: accent)
            line(hp(0, 15.5), hp(0, 10), width: 2, color: accent)
            line(hp(5, 14), hp(4, 9), width: 2, color: accent)
        }

        // Глаза
        let closed = sleeping || p.state == .happy || p.state == .eat || p.blinking
        // Взгляд из экранных координат в координаты повёрнутого кота
        let rad = angle * .pi / 180
        let lx = (p.lookX * cos(rad) + p.lookY * sin(rad)) * (p.facingRight ? 1 : -1)
        let ly = -p.lookX * sin(rad) + p.lookY * cos(rad)
        let eyeCenters = [hp(-3, 2), hp(8, 2)]
        for e in eyeCenters {
            let ex = e.x
            let ey = e.y
            if hissing {
                line(NSPoint(x: ex - 3.5 * k, y: ey + 1.5 * k), NSPoint(x: ex + 3.5 * k, y: ey - 0.5 * k), width: 2, color: ink)
            } else if closed {
                let lid = NSBezierPath()
                lid.lineWidth = 2
                lid.lineCapStyle = .round
                if sleeping {
                    lid.move(to: NSPoint(x: ex - 3 * k, y: ey))
                    lid.curve(to: NSPoint(x: ex + 3 * k, y: ey),
                              controlPoint1: NSPoint(x: ex - k, y: ey - 3 * k),
                              controlPoint2: NSPoint(x: ex + k, y: ey - 3 * k))
                } else {
                    lid.move(to: NSPoint(x: ex - 3 * k, y: ey - k))
                    lid.line(to: NSPoint(x: ex, y: ey + 2 * k))
                    lid.line(to: NSPoint(x: ex + 3 * k, y: ey - k))
                }
                ink.setStroke()
                lid.stroke()
            } else {
                let size: CGFloat = (held ? 8.5 : 7) * k
                outlined(oval(ex + lx * 0.4, ey + ly * 0.4, size, size + k), look.eyes.ns, width: 1)
                ink.setFill()
                oval(ex + lx, ey + ly, 2.6 * k, (held ? 6 : 5) * k).fill()
                NSColor.white.setFill()
                oval(ex + lx + 1, ey + ly + 1.6 * k, 1.8 * k, 1.8 * k).fill()
            }
        }

        // Румянец
        if p.state == .happy || p.state == .eat {
            pink.withAlphaComponent(0.55).setFill()
            oval(hp(-7.5, -6).x, hp(-7.5, -6).y, 7 * k, 4 * k).fill()
            oval(hp(11.5, -6).x, hp(11.5, -6).y, 7 * k, 4 * k).fill()
        }

        // Нос и рот
        let n = hp(13, -3)
        pink.setFill()
        triangle([NSPoint(x: n.x - 2, y: n.y + 1.5), NSPoint(x: n.x + 2, y: n.y + 1.5), NSPoint(x: n.x, y: n.y - 1.5)]).fill()
        if p.state == .eat || held || hissing {
            let open = p.state == .eat ? 2 + CGFloat(abs(sin(t * 12))) * 3 : 4
            outlined(NSBezierPath(ovalIn: NSRect(x: n.x - 2.5, y: n.y - 4 - open, width: 5, height: open)), pink, width: 1.5)
        } else {
            let mouth = NSBezierPath()
            mouth.lineWidth = 1.3
            mouth.move(to: NSPoint(x: n.x - 3.5, y: n.y - 3.5))
            mouth.curve(to: NSPoint(x: n.x, y: n.y - 2.5), controlPoint1: NSPoint(x: n.x - 2.5, y: n.y - 5.5), controlPoint2: NSPoint(x: n.x - 0.5, y: n.y - 5))
            mouth.curve(to: NSPoint(x: n.x + 3.5, y: n.y - 3.5), controlPoint1: NSPoint(x: n.x + 0.5, y: n.y - 5), controlPoint2: NSPoint(x: n.x + 2.5, y: n.y - 5.5))
            ink.setStroke()
            mouth.stroke()
        }

        // Усы
        let whiskerColor = look.fur.r + look.fur.g + look.fur.b < 0.9
            ? NSColor(calibratedWhite: 0.85, alpha: 0.8)
            : ink.withAlphaComponent(0.6)
        for (from, to) in [
            (NSPoint(x: n.x + 1, y: n.y - 2), NSPoint(x: n.x + 13, y: n.y)),
            (NSPoint(x: n.x + 1, y: n.y - 3), NSPoint(x: n.x + 13, y: n.y - 5)),
            (hp(-8, -5), hp(-20, -3)),
            (hp(-8, -6), hp(-20, -8)),
        ] {
            line(from, to, width: 1, color: whiskerColor)
        }

        drawAccessory(look, head: head, k: k, eyes: eyeCenters, hp: hp)

        NSGraphicsContext.restoreGraphicsState()
    }

    static func drawAccessory(_ look: CatLook, head: NSPoint, k: CGFloat, eyes: [NSPoint], hp: (CGFloat, CGFloat) -> NSPoint) {
        let color = look.accessoryColor.ns
        switch look.accessory {
        case .none:
            break
        case .bow:
            let c = hp(-10, 14)
            outlined(triangle([c, NSPoint(x: c.x - 7 * k, y: c.y + 5 * k), NSPoint(x: c.x - 7 * k, y: c.y - 4 * k)]), color, width: 1.2)
            outlined(triangle([c, NSPoint(x: c.x + 7 * k, y: c.y + 5 * k), NSPoint(x: c.x + 7 * k, y: c.y - 4 * k)]), color, width: 1.2)
            outlined(oval(c.x, c.y, 4 * k, 4 * k), color, width: 1.2)
        case .collar:
            line(hp(-15, -12), hp(5, -17), width: 4.5, color: CatRenderer.ink)
            line(hp(-15, -12), hp(5, -17), width: 3, color: color)
            let b = hp(-4, -19)
            outlined(oval(b.x, b.y, 5.5 * k, 5.5 * k), gold, width: 1)
        case .hat:
            outlined(triangle([hp(-10, 12), hp(7, 16), hp(-5, 34)]), color, width: 1.5)
            let tip = hp(-5, 34)
            outlined(oval(tip.x, tip.y, 6 * k, 6 * k), .white, width: 1.2)
        case .glasses:
            for e in eyes {
                let lens = oval(e.x, e.y, 10 * k, 10 * k)
                NSColor.white.withAlphaComponent(0.2).setFill()
                lens.fill()
                color.setStroke()
                lens.lineWidth = 1.6
                lens.stroke()
            }
            line(NSPoint(x: eyes[0].x + 5 * k, y: eyes[0].y), NSPoint(x: eyes[1].x - 5 * k, y: eyes[1].y), width: 1.6, color: color)
            line(NSPoint(x: eyes[0].x - 5 * k, y: eyes[0].y + k), hp(-15, 5), width: 1.6, color: color)
        case .crown:
            let crown = NSBezierPath()
            let pts = [hp(-10, 13), hp(-11, 23), hp(-5, 18), hp(0, 25), hp(5, 18), hp(11, 23), hp(10, 13)]
            crown.move(to: pts[0])
            for pt in pts.dropFirst() { crown.line(to: pt) }
            crown.close()
            outlined(crown, color, width: 1.3)
            let gem = hp(0, 16.5)
            outlined(oval(gem.x, gem.y, 3.5 * k, 3.5 * k), NSColor.systemRed, width: 0.8)
        case .scarf:
            line(hp(-15, -12), hp(6, -17), width: 8, color: CatRenderer.ink)
            line(hp(-15, -12), hp(6, -17), width: 6, color: color)
            line(hp(-8, -15), hp(-12, -29), width: 7, color: CatRenderer.ink)
            line(hp(-8, -15), hp(-12, -29), width: 5, color: color)
        }
    }
}
