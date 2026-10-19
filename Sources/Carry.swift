import AppKit
import SwiftUI

// MARK: lift, carry, drop: pick Buddy up with the mouse, carry it (it swings behind the pointer), let go (it drops a little, where it is, and lands)
// Each pet has its own lift and landing (its PetKind's lift words, landing words and landing time; the poses are in Pet.swift
// for the animals and in each avatar's file). The window grows while Buddy is held, so a swing or a burst is never cut off.

enum Carry { case none, held, falling, landed }

/// One pet's lift and landing: its words, and how long the landing lasts before it walks again.
struct Carried {
    var lift: [String] = []                 // said when picked up
    var land: [String] = ["💨"]              // at the impact
    var later: (at: Double, words: [String])? = nil   // a beat after the impact
    var landTime = 1.2
    var thud = false                        // heavy: the floor shakes
    var floaty = false                      // low gravity: it falls slowly
}

/// The body hanging from the grab point. Degrees: positive turns clockwise, so the body swings left (it lags behind a drag to the right).
struct Swing: Equatable { var angle = 0.0, speed = 0.0 }

/// One step of the swing: a loose spring that pulls the body toward the angle the drag's speed gives it, so it lags, overshoots and settles.
func swingStep(_ w: Swing, vx: Double, dt: Double) -> Swing {
    let target = 35 * tanh(vx / 1200), k = 8.0, damping = 0.22
    var n = w
    n.speed += (k * k * (target - n.angle) - 2 * damping * k * n.speed) * dt
    n.angle += n.speed * dt
    if abs(n.angle) > 40 { n.angle = n.angle > 0 ? 40 : -40; n.speed = 0 }
    return n
}

/// One step of the fall; `landed` once it reaches the floor, where it stops.
func fallStep(y: Double, vy: Double, floor: Double, dt: Double, gravity: Double = 2600) -> (y: Double, vy: Double, landed: Bool) {
    let v = vy - gravity * dt, ny = y + v * dt
    return ny <= floor ? (floor, 0, true) : (ny, v, false)
}

/// How far a pet drops when you let go of it: a short drop where it is, not all the way down.
let dropHeight = 40.0

/// Where a pet let go at `y` lands: a short drop, but never through the screen's floor.
func landingY(from y: Double, floor: Double) -> Double { max(y - dropHeight, floor) }

/// The screen (its visible frame) to land on: the one under the pointer, else the one straight below or above it, else the nearest.
func floorBelow(_ p: CGPoint, in frames: [CGRect]) -> CGRect? {
    if let f = frames.first(where: { $0.contains(p) }) { return f }
    func gap(_ f: CGRect) -> CGFloat { hypot(max(f.minX - p.x, 0, p.x - f.maxX), max(f.minY - p.y, 0, p.y - f.maxY)) }
    return frames.filter { p.x >= $0.minX && p.x < $0.maxX }.min { gap($0) < gap($1) } ?? frames.min { gap($0) < gap($1) }
}

/// How far a landing squashes the body: hard at the impact, then a few small bounces. 1 = no squash.
func landSquash(_ t: Double, _ depth: Double) -> CGFloat { CGFloat(1 - depth * exp(-t * 6) * cos(t * 16)) }

extension Model {
    /// Picked up: everything else stops (walk, trick, card, nap on a window).
    func lift() {
        carry = .held; carryAt = Date(); swing = 0
        if showCard { showCard = false; showStale = false; hoverEnded() }
        walking = false; zoomies = false; gesture = .none; squatting = false
    }
    func drop() { carry = .falling; carryAt = Date() }
    func land() { carry = .landed; carryAt = Date() }
}

/// The window while Buddy is held: big enough for the swing and the bursts. The pet's 84×72 box sits at `carryBox` in it (from the bottom left).
let carrySize = NSSize(width: 200, height: 220)
let carryBox = CGPoint(x: 58, y: 68)

/// Where Buddy is held, in its 84×72 box facing right, from the top left: the scruff for animals, the top of the back for avatars.
func gripPoint(biped: Bool) -> CGPoint { biped ? CGPoint(x: 46, y: 12) : CGPoint(x: 48, y: 18) }

/// What the window remembers while Buddy is held or falls.
struct Hold {
    var grip: CGPoint        // where the pointer took hold, in the box (from the bottom left)
    var at = Date()
    var lastX: CGFloat
    var vx = 0.0
    var swing = Swing()
    var vy = 0.0
    var landY = 0.0          // where the drop ends, set when you let go
    var timer: Timer?        // its own 30 Hz clock: the usual timers pause while the mouse button is down
}

extension AppDelegate {
    /// The pet's 84×72 box on screen.
    var petBox: CGRect {
        let f = panel.frame
        if hold != nil { return CGRect(x: f.minX + carryBox.x, y: f.minY + carryBox.y, width: 84, height: 72) }
        let p = petFrame
        return CGRect(x: p.minX + 8, y: p.minY + 8, width: 84, height: 72)
    }

    /// The pointer drags Buddy (the first call picks it up), or lets go.
    func carry(_ dragging: Bool) {
        if !dragging { letGo(); return }
        if model.carry != .held { grab() }
        place()
    }

    func grab() {
        let box = petBox, mouse = NSEvent.mouseLocation
        log("lift \(petKind.name) at \(Int(mouse.x)),\(Int(mouse.y)) from \(model.carry)")
        hold?.timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in _ = self?.carryTick() }
        RunLoop.main.add(t, forMode: .common)   // .common includes the mouse-tracking mode a drag runs in
        hold = Hold(grip: CGPoint(x: mouse.x - box.minX, y: mouse.y - box.minY), lastX: box.minX, timer: t)
        flightFloor = nil; heroLater = nil; target = nil
        petSpot = nil; placed = nil; cardRect = nil; model.cardBeside = false; model.petLift = 0   // the card closes: forget where it stood
        panel.level = .floating   // down from a nap on a window
        model.lift()
        panel.setFrame(NSRect(x: box.minX - carryBox.x, y: box.minY - carryBox.y, width: carrySize.width, height: carrySize.height), display: true)
        if litter.isVisible { litter.orderOut(nil) }
    }

    /// Hang the pet from the pointer. In the first 0.2 s the hold slides from where you clicked to the scruff, so it looks picked up.
    func place() {
        guard let h = hold else { return }
        let mouse = NSEvent.mouseLocation, k = ease(Date().timeIntervalSince(h.at) / 0.2)
        var g = gripPoint(biped: petKind.biped)
        if model.facingLeft { g.x = 84 - g.x }
        let to = CGPoint(x: g.x, y: 72 - g.y)
        let off = CGPoint(x: h.grip.x + (to.x - h.grip.x) * k, y: h.grip.y + (to.y - h.grip.y) * k)
        panel.setFrameOrigin(NSPoint(x: mouse.x - off.x - carryBox.x, y: mouse.y - off.y - carryBox.y))
    }

    func letGo() {
        guard hold != nil, model.carry == .held else { return }
        log("drop \(petKind.name) at \(Int(petBox.minX)),\(Int(petBox.minY))")
        let box = petBox
        let floor = floorBelow(CGPoint(x: box.midX, y: box.minY), in: NSScreen.screens.map(\.visibleFrame)) ?? screen
        hold?.vy = 0
        hold?.landY = landingY(from: box.minY, floor: floor.minY + 8)
        model.drop()
    }

    /// 30 times a second while held, falling or landing (on the hold's own timer). True while it has the window.
    func carryTick() -> Bool {
        guard var h = hold else { return false }
        let m = model, dt = 1.0 / 30
        switch m.carry {
        case .held:
            if NSEvent.pressedMouseButtons & 1 == 0 { letGo(); return true }   // the button came up but the drag never ended (a cancelled gesture); return, or `hold = h` below undoes letGo's landing height
            place()
            let x = petBox.minX
            h.vx = h.vx * 0.5 + Double(x - h.lastX) / dt * 0.5   // smoothed: the pointer moves in jumps
            h.lastX = x
            h.swing = swingStep(h.swing, vx: h.vx, dt: dt)
        case .falling:
            let box = petBox
            let screens = NSScreen.screens.map(\.visibleFrame)
            let floor = floorBelow(CGPoint(x: box.midX, y: box.minY), in: screens) ?? screen
            let x = min(max(box.minX, floor.minX), floor.maxX - box.width)   // fall onto the screen, not past its edge
            let step = fallStep(y: box.minY, vy: h.vy, floor: max(h.landY, floor.minY + 8), dt: dt, gravity: petKind.carried.floaty ? 500 : 2600)
            h.vy = step.vy
            h.swing = swingStep(h.swing, vx: 0, dt: dt)
            panel.setFrameOrigin(NSPoint(x: x - carryBox.x, y: step.y - carryBox.y))
            if step.landed { log("landed \(petKind.name) at y \(Int(step.y))"); h.swing = Swing(); m.land() }
        case .landed:
            if Date().timeIntervalSince(m.carryAt) > petKind.carried.landTime { putDown(); return true }
        case .none:
            putDown(); return true
        }
        hold = h
        if abs(m.swing - h.swing.angle) > 0.2 { m.swing = h.swing.angle }
        return true
    }

    /// Back to the small window, the pet where it landed. It walks from here.
    func putDown() {
        let box = petBox
        hold?.timer?.invalidate()
        hold = nil
        model.carry = .none; model.swing = 0
        if model.hovering && !box.contains(NSEvent.mouseLocation) { model.hovering = false }   // so it walks again
        panel.setFrame(NSRect(x: box.minX - 8, y: box.minY - 8, width: small.width, height: small.height), display: true)
        homeY = panel.frame.minY
        model.leftSide = panel.frame.midX < screen.midX
        model.onExpandChange?()   // a bubble that came while it was held
    }

    private func log(_ s: String) { if CommandLine.arguments.contains("--carry-log") { FileHandle.standardError.write("carry: \(s)\n".data(using: .utf8)!) } }
}
