import AppKit
import SwiftUI

// MARK: the cat

extension Mood {
    var color: Color {
        switch self {
        case .asleep: return Color(red: 0.55, green: 0.58, blue: 0.66)
        case .calm: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .busy: return Color(red: 0.36, green: 0.62, blue: 0.98)
        case .waiting: return Color(red: 0.96, green: 0.72, blue: 0.27)
        case .upset: return Color(red: 0.94, green: 0.33, blue: 0.33)
        case .happy: return Color(red: 0.36, green: 0.82, blue: 0.55)
        }
    }
    var word: String {
        switch self {
        case .asleep: return "napping"
        case .calm: return "chilling"
        case .busy: return "watching your sessions"
        case .waiting: return "waiting on you"
        case .upset: return "worried"
        case .happy: return "happy"
        }
    }
}

let fur = Color(red: 0.89, green: 0.55, blue: 0.36)
let claudeColor = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)   // Anthropic clay
let codexColor = Color(red: 16 / 255, green: 163 / 255, blue: 127 / 255)    // OpenAI green

let furDark = Color(red: 0.72, green: 0.40, blue: 0.25)
let ink = Color(red: 0.16, green: 0.11, blue: 0.10)

struct Breed {
    var name: String
    var fur: Color, dark: Color, belly: Color
    var eye: Color = ink
    var points: Color? = nil      // siamese: darker ears, mask, tail, paws
    var patch: [Color] = []       // calico patches
    var stripes = false
    var mask: Color? = nil        // pug: black face
}
func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

/// One kind of pet. To add one, copy PetBear.swift (coats, tricks, how it draws), add it to `pets`,
/// and add a case to each drawing switch below (head, tail, kitten).
struct PetKind {
    let name: String              // buddy.json "pet"
    let emoji: String             // on the card's header
    let hello: String             // after "I'm a <coat> now"
    let coats: [Breed]
    let tricks: [Gesture]         // one at random now and then
    var onRed: Gesture? = nil     // when a PR breaks
    var onMerge: Gesture? = nil   // when a session finishes or a PR merges
    var outfit = false            // wears the tracksuit, sneakers and shades ("outfit": "none" turns it off)
    var dances = false            // plays the dance clip on good news
    var chunky = false            // wider legs and body
    var biped = false             // an avatar on two legs, drawn whole by its own file (Avatars.swift)
    var bursts: [Gesture: [String]] = [:]   // its own words or emoji for a trick, instead of the usual ("ROAR!" → "HAI-YA!")
    var carried = Carried()                 // what it says when picked up, and how it lands (Carry.swift)
    let sceneEars: (inout GraphicsContext, _ fur: Color, _ dark: Color) -> Void   // the pet in Burrow's scene
}

/// Where each buddy goes when you send it to its den: "Off to my box for an hour." A new buddy gets "my den" until it has its own.
extension PetKind {
    var den: String {
        ["cat": "my box", "pug": "my kennel", "bear": "my cave", "hero": "patrol", "ninja": "the dojo", "wizard": "my tower",
         "astronaut": "the ship", "robot": "my charging dock", "stitch": "the sea", "chemist": "the lab"][name] ?? "my den"
    }
}

let pets = [catPet, pugPet, bearPet, heroBuddy, ninjaBuddy, wizardBuddy, astronautBuddy, robotBuddy, stitchBuddy, chemistBuddy]
var petKind: PetKind { pets.first { $0.name == pet } ?? catPet }
var breeds: [Breed] { petKind.coats }

// Drawing picks the pet with a switch, not with closures stored in PetKind: SwiftUI can compare a switch's views
// frame to frame; an AnyView from a closure hides the view type, so SwiftUI may rebuild it every frame.
extension Cat {
    @ViewBuilder func tail(wag: Double, asleep: Bool) -> some View {
        switch petKind.name {
        case "pug": pugTail(wag: wag)
        case "bear": bearTail(wag: wag)
        default: catTail(wag: wag, asleep: asleep)
        }
    }
    @ViewBuilder func petHead(s: Double, blink: Bool, asleep: Bool, look: CGSize) -> some View {
        switch petKind.name {
        case "pug": pugHead(blink: blink, asleep: asleep, look: look)
        case "bear": bearHead(s: s, blink: blink, asleep: asleep, look: look)
        default: catHead(blink: blink, asleep: asleep, look: look)
        }
    }
}
/// The small pets that wait for you: ears behind the head, face markings on top.
@ViewBuilder func kittenEars(_ b: Breed) -> some View {
    switch petKind.name {
    case "pug": EmptyView()
    case "bear": bearKittenEars(b)
    default: catKittenEars(b)
    }
}
@ViewBuilder func kittenFace(_ b: Breed) -> some View {
    switch petKind.name {
    case "pug": pugKittenFace(b)
    case "bear": bearKittenFace(b)
    default: EmptyView()
    }
}



enum Gesture: CaseIterable { case none, stretch, yawn, spin, wash, loaf, sneeze, zoomies, knock, hop, shimmy, roar, honey, fish, scratch,
    heroLanding, flyOff, grapple, capeSwirl,   // the caped hero (Costume.swift)
    dhak, dhunuchi, quietDhak, shiuli, diyas, phuljhari, anaar, rangoli, kandil }   // Pujo and Diwali (Festive.swift)

struct Particle: Identifiable { let id = UUID(); let glyph: String; let dx: CGFloat; var fall = false }

struct FloatUp: View {
    let p: Particle
    @State private var gone = false
    var body: some View {
        Text(p.glyph).font(.system(size: p.glyph.count > 2 ? 11 : 14, weight: .heavy, design: .rounded)).foregroundColor(.white).shadow(radius: 1)
            .rotationEffect(.degrees(p.fall && gone ? 160 : 0))
            .offset(x: p.dx + (p.fall && gone ? 18 : 0), y: p.fall ? (gone ? 60 : 30) : (gone ? -60 : -10))
            .opacity(gone ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.3)) { gone = true } }
    }
}

struct Tri: Shape {
    var a: CGPoint, b: CGPoint, c: CGPoint
    func path(in r: CGRect) -> Path { Path { $0.move(to: a); $0.addLine(to: b); $0.addLine(to: c); $0.closeSubpath() } }
}

struct TailShape: Shape {
    var curl: CGFloat
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 20, y: 50))
            p.addQuadCurve(to: CGPoint(x: 6 - curl * 4, y: 22 + curl * 18), control: CGPoint(x: 0, y: 50))
        }
    }
}

/// Bit, drawn facing right in an 84×72 box. The view flips it to face left.
struct Cat: View {
    @ObservedObject var m: Model
    @State private var wobble: CGFloat = 0
    @State private var jump: CGFloat = 0
    @State private var particles: [Particle] = []

    var b: Breed { m.breed }
    var dark: Bool { b.name == "Tuxedo" || b.name == "Midnight" || b.name == "Black pug" || b.name == "Black bear" }
    var faceInk: Color { dark ? Color.white : ink }
    var mood: Mood {
        if m.carry != .none { return m.mood == .asleep ? .calm : m.mood }   // picked up: awake, even from a nap
        return m.squatting ? .asleep : (m.hovering && m.mood == .asleep && !m.snoozed ? .calm : m.mood)
    }
    var held: Bool { m.carry == .held || m.carry == .falling }

    var body: some View {
        TimelineView(.animation(minimumInterval: m.walking || m.zoomies || m.gesture != .none || m.hovering || m.breathing || m.carry != .none ? 1 / walkHz : 1.0)) { t in   // 1 fps when idle: 7.6% → 3% CPU, measured
            let s = (frozenTime ?? t.date.timeIntervalSinceReferenceDate)
            let asleep = mood == .asleep
            let breathe = 1 + (asleep ? 0.05 : 0.025) * sin(s * (asleep ? 1.4 : 2.4))
            let g = m.gesture, gt = (frozenNow ?? Date()).timeIntervalSince(m.gestureAt)
            let flying = hero && (g == .flyOff || g == .grapple)
            let gliding = hero && (m.walking && !m.zoomies || flying)   // the hero glides: feet off the ground, legs tucked
            let hm = wearing != nil || petKind.biped ? costumeMotion(g, gt) : (y: CGFloat(0), squash: CGFloat(1), tilt: 0.0)
            let step = m.walking && !gliding ? sin(s * 12) : 0
            let wagSpeed: Double = m.hovering ? 9 : mood == .busy ? 4 : mood == .upset ? 14 : 2
            let ct = (frozenNow ?? Date()).timeIntervalSince(m.carryAt)   // seconds into the lift, fall or landing
            let land = m.carry == .landed ? ct : -1
            let kind = petKind.name
            // held: the cat's tail sways slowly, the pug's wiggles, the bear's hardly moves
            let wag = held ? sin(s * (kind == "pug" ? 20 : kind == "bear" ? 3 : 1.6)) * (kind == "pug" ? 10 : kind == "bear" ? 4 : 16)
                : asleep ? 0 : sin(s * wagSpeed) * (m.hovering ? 16 : 9)
            let blink = !asleep && Int(s * 10) % 37 == 0
            let k = g == .stretch ? sin(min(gt / 2.4, 1) * .pi) : 0
            let loaf = g == .loaf
            ZStack(alignment: .topTrailing) {
                breathingGuide(s: s).frame(width: 84, height: 72)   // outside the flip, so the words read the right way round
                ZStack {
                  if petKind.biped {
                    avatarBody(AvatarPose(b: b, s: s, step: m.walking && !held ? sin(s * 12) : 0, asleep: asleep, blink: blink, g: g, gt: gt, held: held, land: land))
                    poseLayer.offset(x: -8, y: -7)
                  } else {
                    if hero { cape(s: s, moving: gliding, gt: gt) }
                    tail(wag: wag, asleep: asleep)
                    ForEach(0..<4) { i in
                        // held: the legs hang long; the pug paddles, the bear's spread out
                        let paddle = held && kind == "pug" ? sin(s * 22 + Double(i) * 1.7) * 3 : 0
                        let y = held ? 66 + paddle : asleep ? 64 : 63 + (i % 2 == 0 ? step : -step) * 2
                        Capsule().fill(drip ? ink : (b.points ?? (i % 2 == 0 ? b.dark : b.fur))).frame(width: petKind.chunky ? 10 : 7, height: held ? 15 : asleep || loaf ? 4 : gliding ? 7 : 12)
                            .rotationEffect(.degrees(held && kind == "bear" ? (i < 2 ? 24 : -24) : 0), anchor: .top)
                            .position(x: [22, 32, 46, 56][i], y: y)
                        if drip && !asleep && !loaf {   // sneakers
                            Capsule().fill(Color.white).frame(width: 9, height: 4.5).overlay(Capsule().fill(ink).frame(width: 4, height: 1.1))
                                .position(x: [23, 33, 47, 57][i], y: y + 4.5)
                        }
                    }
                    Ellipse().fill(outfitFill ?? (drip ? ink : b.fur)).frame(width: petKind.chunky ? 60 : 54, height: asleep ? (petKind.chunky ? 30 : 26) : (petKind.chunky ? 35 : 30))
                        .scaleEffect(y: breathe, anchor: .bottom)
                        .position(x: 38, y: asleep ? 54 : 50)
                    if drip {
                        // tracksuit: two white stripes down the side, white waistband, white hood round the neck
                        ForEach(0..<2) { i in Capsule().fill(Color.white).frame(width: 30, height: 1.6).rotationEffect(.degrees(-8)).position(x: 34, y: (asleep ? 47 : 43) + CGFloat(i) * 4) }
                        Capsule().fill(Color.white).frame(width: 34, height: 3).position(x: 40, y: asleep ? 63 : 62)
                        ForEach([55.0, 63.0], id: \.self) { x in Capsule().fill(Color.white).frame(width: 1.6, height: 8).position(x: x, y: asleep ? 60 : 54) }   // hoodie strings
                    } else if outfitFill != nil {
                        outfitTrim(asleep: asleep)
                    } else {
                        markings(asleep: asleep)
                        Ellipse().fill(b.belly.opacity(0.85)).frame(width: 26, height: 10).position(x: 46, y: asleep ? 60 : 58)
                    }
                    if hero && !asleep { emblem() }
                    ZStack {
                        head(s: s, blink: blink, asleep: asleep)
                        if hero { mask(blink: blink, asleep: asleep) }
                        festiveHead()
                        poseLayer
                    }
                    .rotationEffect(.degrees(m.pose == .thinking ? -9 : 0), anchor: UnitPoint(x: 0.7, y: 0.6))
                    .offset(y: asleep ? 10 : 0)
                    if wearing == "durga" || wearing == "diwali" { festiveProps(s: s, gt: gt) }
                  }
                }
                .frame(width: 84, height: 72)
                .shadow(color: .black.opacity(0.45), radius: 0.8)   // outline, so white cats show on white pages
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                .scaleEffect(x: 1 + 0.24 * k, y: 1 - 0.16 * k, anchor: .bottom)
                .offset(y: loaf ? 4 : 0)
                .rotationEffect(.degrees(g == .spin && gt < 1 ? gt * 360 : 0))
                .offset(y: g == .sneeze && gt > 0.7 && gt < 0.9 ? -8 : 0)
                .offset(x: g == .shimmy ? sin(gt * 16) * 3 : 0, y: g == .shimmy ? -abs(sin(gt * 8)) * 3 : 0)
                .rotationEffect(.degrees(g == .shimmy ? sin(gt * 8) * 6 : 0), anchor: .bottom)
                .rotationEffect(.degrees(g == .roar ? -16 * sin(min(gt / 1.8, 1) * .pi) : 0), anchor: UnitPoint(x: 0.3, y: 1))
                .offset(x: g == .scratch ? sin(gt * 6) * 2.5 : 0, y: g == .scratch ? -abs(sin(gt * 6)) * 2 : 0)
                .rotationEffect(.degrees(g == .scratch ? sin(gt * 6) * 4 : 0), anchor: .bottom)
                .scaleEffect(x: 1 / hm.squash * (hm.squash < 1 ? 0.9 : 1), y: hm.squash, anchor: .bottom)
                .rotationEffect(.degrees(hm.tilt + (gliding && !flying ? 8 : 0)), anchor: .center)
                .offset(y: hm.y + (gliding ? -10 + sin(s * 3) * 2 : 0) + (wearing == "durga" && m.walking ? pandalHop(s) : 0))
                .modifier(Held(on: held && !petKind.biped, kind: kind, s: s))
                .modifier(Landing(t: land, kind: kind, biped: petKind.biped))
                .rotationEffect(.degrees(held && kind == "astronaut" ? s * 40 : 0))                                        // no gravity: a slow turn
                .rotationEffect(.degrees(m.carry == .falling && kind == "ninja" ? min(ct / 0.18, 1) * 360 : 0))           // a ball: one flip in the short drop
                .scaleEffect(x: m.facingLeft ? -1 : 1, y: 1)
                .rotationEffect(.degrees(m.swing), anchor: swingAnchor)
                accessory(s: s).frame(width: 84, height: 20).offset(y: -22)
                if m.badge > 0 && !drawingForPhone {   // the phone draws its own, live badge; napping, just a quiet "!"
                    Text(m.snoozed ? "!" : "\(m.badge)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16).background(Circle().fill(Color.red))
                        .offset(x: 2, y: -2)
                }
                ForEach(particles) { FloatUp(p: $0).frame(width: 84) }
            }
            .offset(x: wobble, y: jump + (m.walking ? -abs(step) * 1.5 : 0))
        }
        .frame(width: 84, height: 72)
        .onChange(of: m.shake) { _ in
            withAnimation(.easeInOut(duration: 0.06).repeatCount(7, autoreverses: true)) { wobble = 5 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { wobble = 0 }
        }
        .onChange(of: m.celebrate) { _ in
            burst(["✨", "🎉", "✨", "⭐️"])
            withAnimation(.spring(response: 0.25, dampingFraction: 0.35)) { jump = -22 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { jump = 0 } }
        }
        .onChange(of: m.hearts) { _ in burst(["💖", "💗", "💖"]) }
        .onChange(of: m.leaves) { _ in burst([["🍃"], ["🌸"], ["🍃", "🍂"]].randomElement()!, fall: true) }
        .onAppear {   // lifted out of the card-beside layout: closing the card swaps in a new view that starts already held, so no onChange
            if m.carry == .held, Date().timeIntervalSince(m.carryAt) < 0.5, !petKind.carried.lift.isEmpty { burst(petKind.carried.lift) }
        }
        .onChange(of: m.carry) { c in
            let k = petKind.carried
            switch c {
            case .held: if !k.lift.isEmpty { burst(k.lift) }
            case .landed:
                burst(k.land)
                if k.thud { shakeSoon(after: 0) }
                if let (at, words) = k.later {   // only for this landing: a re-grab and second landing within `at` must not fire it twice
                    let landedAt = m.carryAt
                    DispatchQueue.main.asyncAfter(deadline: .now() + at) { if m.carry == .landed, m.carryAt == landedAt { burst(words) } }
                }
            default: break
            }
        }
        .onChange(of: m.gesture) { g in
            if let words = petKind.bursts[g] { burst(words); return }
            switch g {
            case .sneeze: DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { burst(["achoo!"]) }
            case .knock: burst(["🥛"], fall: true)
            case .zoomies: burst(["💨", "💨"])
            case .spin: burst(["🌀"])
            case .yawn: burst(["yawn"])
            case .wash: burst(["lick lick"])
            case .loaf: burst(["🍞"])
            case .shimmy: burst(["🎵", "🎶"])
            case .roar: burst(["ROAR!"]); shakeSoon()
            case .honey: burst(["🍯", "yum"])
            case .fish: DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burst(["🐟", "💦"]) }
            case .scratch: burst(["scritch"])
            case .heroLanding: DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { burst(["💨", "💥", "💨"]) }; shakeSoon()
            case .capeSwirl: burst(["✨"])
            case .grapple: burst(["🪝"])
            case .flyOff: burst(["💨"])
            case .dhak: DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { burst(["dhyang", "kur kur"]) }
            case .shiuli: burst(["✿", "✿", "✿"], fall: true)
            case .phuljhari: burst(["✦", "✦"])
            case .anaar: DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burst(["phuss"]) }
            case .kandil: burst(["🏮"])
            default: break
            }
        }
    }

    @ViewBuilder func markings(asleep: Bool) -> some View {
        let y: CGFloat = asleep ? 54 : 50
        if b.stripes {
            ForEach(0..<3) { i in Capsule().fill(b.dark).frame(width: 4, height: 13).rotationEffect(.degrees(-12)).position(x: 26 + CGFloat(i) * 9, y: y - 6) }
        }
        if b.patch.count == 2 {
            Ellipse().fill(b.patch[0]).frame(width: 20, height: 14).position(x: 28, y: y - 4)
            Ellipse().fill(b.patch[1]).frame(width: 14, height: 11).position(x: 44, y: y - 8)
        }
    }

    @ViewBuilder func head(s: Double, blink: Bool, asleep: Bool) -> some View {
        petHead(s: s, blink: blink, asleep: asleep, look: lookVector())
    }

    @ViewBuilder func eyes(blink: Bool, asleep: Bool, look: CGSize) -> some View {
        let lick = m.carry == .landed && petKind.name == "cat" && (frozenNow ?? Date()).timeIntervalSince(m.carryAt) > 0.9
        if asleep || (m.hovering && mood == .calm && m.carry == .none) || m.gesture == .yawn || m.gesture == .wash || lick
            || (held && petKind.name == "cat") {   // a cat held by the scruff goes calm
            ForEach([53.0, 67.0], id: \.self) { x in
                Circle().trim(from: asleep ? 0.05 : 0.55, to: asleep ? 0.45 : 0.95)
                    .stroke(faceInk.opacity(0.8), lineWidth: 1.8).frame(width: 8, height: 8).position(x: x, y: 31)
            }
        } else if mood == .happy {
            ForEach([53.0, 67.0], id: \.self) { x in
                Circle().trim(from: 0.55, to: 0.95).stroke(faceInk.opacity(0.85), lineWidth: 2.2).frame(width: 9, height: 9).position(x: x, y: 33)
            }
        } else {
            let big = mood == .waiting || mood == .upset || held   // the pug and the bear: wide-eyed in the air
            ForEach([53.0, 67.0], id: \.self) { x in
                ZStack {
                    Ellipse().fill(b.eye == ink ? ink : b.eye).overlay(Ellipse().fill(ink).frame(width: 3)).frame(width: big ? 9 : 7.5, height: blink ? 1.5 : (big ? 11 : 9))
                    if !blink { Circle().fill(Color.white).frame(width: 3).offset(x: 1.2, y: -2) }
                }
                .position(x: x, y: 31).offset(look)
            }
        }
    }

    @ViewBuilder func accessory(s: Double) -> some View {
        let bob = sin(s * 5) * 2
        switch mood {
        case .upset:
            Text("!").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Mood.upset.color)).offset(x: m.facingLeft ? -18 : 18, y: bob)
        case .waiting:
            Text("?").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(ink)
                .frame(width: 18, height: 18).background(Circle().fill(Mood.waiting.color)).offset(x: m.facingLeft ? -18 : 18, y: bob)
        case .busy:
            HStack(spacing: 3) {
                ForEach(0..<3) { i in Circle().fill(Mood.busy.color).frame(width: 5).opacity(Int(s * 3) % 3 == i ? 1 : 0.35) }
            }
            .padding(.horizontal, 6).padding(.vertical, 4).background(Capsule().fill(Color.white.opacity(0.9)))
            .offset(x: m.facingLeft ? -16 : 16)
        case .asleep:
            Text("z z").font(.system(size: 10 + CGFloat(Int(s) % 3), weight: .heavy)).foregroundColor(.white.opacity(0.9))
                .shadow(radius: 1).offset(x: m.facingLeft ? -22 : 22, y: -CGFloat(Int(s) % 3) * 2)
        default: EmptyView()
        }
    }

    /// The swing turns round the grip, on screen (so it is mirrored when the pet faces left).
    var swingAnchor: UnitPoint {
        let g = gripPoint(biped: petKind.biped)
        return UnitPoint(x: (m.facingLeft ? 84 - g.x : g.x) / 84, y: g.y / 72)
    }

    /// The roar lands a beat after the bear rears up.
    func shakeSoon(after: Double = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            withAnimation(.easeInOut(duration: 0.05).repeatCount(9, autoreverses: true)) { wobble = 3 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { wobble = 0 }
        }
    }

    func burst(_ glyphs: [String], fall: Bool = false) {
        let new = glyphs.enumerated().map { Particle(glyph: $1, dx: CGFloat($0 - glyphs.count / 2) * 14 + (fall ? 26 : 0), fall: fall) }
        particles += new
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { particles.removeAll { p in new.contains { $0.id == p.id } } }
    }

    /// Eyes follow the mouse anywhere on screen.
    func lookVector() -> CGSize {
        if frozenTime != nil { return .zero }   // snapshots: eyes straight ahead, not at wherever your mouse is
        let mouse = NSEvent.mouseLocation
        let c = blobCenter()
        let dx = (mouse.x - c.x) * (m.facingLeft ? -1 : 1), dy = mouse.y - c.y
        let d = max(1, sqrt(dx * dx + dy * dy))
        let k = min(1, d / 200) * 2.5
        return CGSize(width: dx / d * k, height: -dy / d * k)
    }
}

/// An animal held by the scruff: the body hangs and sags, head up. The cat goes limp, the pug wiggles, the heavy bear sags most.
struct Held: ViewModifier {
    let on: Bool, kind: String, s: Double
    func body(content: Content) -> some View {
        let sag = !on ? 1 : kind == "bear" ? 1.12 : kind == "pug" ? 1.04 : 1.08
        let tilt = !on ? 0 : kind == "pug" ? -12 + sin(s * 14) * 5 : kind == "bear" ? -16 : -22
        let g = gripPoint(biped: false)
        content
            .scaleEffect(x: on ? 0.96 : 1, y: sag, anchor: UnitPoint(x: g.x / 84, y: g.y / 72))
            .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: g.x / 84, y: g.y / 72))
    }
}

/// Landing, `t` seconds after the impact (-1: not landing). A squash and a few bounces; then the cat shakes itself,
/// the pug sneezes, the hero holds its crouch.
struct Landing: ViewModifier {
    let t: Double, kind: String, biped: Bool
    func body(content: Content) -> some View {
        let on = t >= 0
        let depth = kind == "pug" ? 0.3 : kind == "bear" ? 0.25 : kind == "astronaut" ? 0.08 : kind == "hero" ? 0 : 0.18
        let hero = kind == "hero" && on ? costumeMotion(.heroLanding, 0.5 + t) : (y: CGFloat(0), squash: CGFloat(1), tilt: 0.0)
        let sq = on ? landSquash(t, depth) * hero.squash : 1
        let shake = on && kind == "cat" && t > 0.4 && t < 0.85 ? sin(t * 40) * 5 : 0
        let sneeze: CGFloat = on && kind == "pug" && t > 0.6 && t < 0.8 ? -8 : 0
        content
            .scaleEffect(x: 1 / sq.squareRoot(), y: sq, anchor: .bottom)
            .rotationEffect(.degrees(shake + hero.tilt), anchor: .bottom)
            .offset(y: sneeze)
    }
}
