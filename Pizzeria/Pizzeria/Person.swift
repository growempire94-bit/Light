import SceneKit
import UIKit
import simd

/// A procedurally built, skinned human (one continuous mesh on an 18-bone skeleton)
/// with procedural animation: walking, idling, working, sweeping, carrying, sitting and eating.
final class PersonNode {
    enum Outfit { case casual, apron, cashier, courier, cleaner, promoter }

    let node = SCNNode()
    private let skeleton = SCNNode()
    private var bones: [SCNNode] = []
    private let outfit: Outfit
    private let box: SCNNode
    private var prop: SCNNode?
    private var phase: Float = Float.random(in: 0...6)
    private var workPhase: Float = Float.random(in: 0...6)
    private var targetYaw: Float = 0
    private var yaw: Float = 0
    private var hasYaw = false
    private(set) var isSitting = false
    private var eatTimer: Float = Float.random(in: 2...6)

    // Bone indices.
    private enum B {
        static let root = 0, hips = 1, spine = 2, chest = 3, neck = 4, head = 5
        static let upperArmL = 6, foreArmL = 7, handL = 8, upperArmR = 9, foreArmR = 10, handR = 11
        static let thighL = 12, shinL = 13, footL = 14, thighR = 15, shinR = 16, footR = 17
        static let count = 18
    }

    private static let parents = [-1, 0, 1, 2, 3, 4, 3, 6, 7, 3, 9, 10, 1, 12, 13, 1, 15, 16]

    // MARK: palettes (muted, realistic)

    static let skinTones: [SIMD3<Float>] = [
        SIMD3(0.92, 0.76, 0.64), SIMD3(0.87, 0.69, 0.56), SIMD3(0.80, 0.61, 0.48),
        SIMD3(0.70, 0.52, 0.40), SIMD3(0.55, 0.39, 0.29), SIMD3(0.40, 0.28, 0.21),
    ]
    static let tops: [SIMD3<Float>] = [
        SIMD3(0.10, 0.11, 0.13), SIMD3(0.20, 0.22, 0.26), SIMD3(0.45, 0.46, 0.48), SIMD3(0.78, 0.77, 0.74),
        SIMD3(0.20, 0.27, 0.20), SIMD3(0.36, 0.12, 0.12), SIMD3(0.16, 0.22, 0.36), SIMD3(0.52, 0.42, 0.30),
        SIMD3(0.88, 0.88, 0.86), SIMD3(0.55, 0.20, 0.25), SIMD3(0.30, 0.36, 0.42), SIMD3(0.62, 0.55, 0.42),
    ]
    static let pants: [SIMD3<Float>] = [
        SIMD3(0.14, 0.19, 0.30), SIMD3(0.20, 0.27, 0.40), SIMD3(0.09, 0.09, 0.10), SIMD3(0.30, 0.30, 0.31),
        SIMD3(0.36, 0.32, 0.25), SIMD3(0.18, 0.17, 0.15),
    ]
    static let hairs: [SIMD3<Float>] = [
        SIMD3(0.06, 0.05, 0.04), SIMD3(0.16, 0.10, 0.06), SIMD3(0.30, 0.20, 0.12), SIMD3(0.52, 0.38, 0.22),
        SIMD3(0.70, 0.58, 0.40), SIMD3(0.55, 0.54, 0.52), SIMD3(0.35, 0.34, 0.33),
    ]
    static let shoes: [SIMD3<Float>] = [
        SIMD3(0.05, 0.05, 0.05), SIMD3(0.85, 0.85, 0.83), SIMD3(0.25, 0.16, 0.10), SIMD3(0.12, 0.12, 0.14),
    ]

    private static let material: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor.white
        m.roughness.contents = 0.78
        m.metalness.contents = 0.0
        return m
    }()

    // MARK: init

    init(outfit: Outfit = .casual, seed: Int = Int.random(in: 0...1_000_000)) {
        self.outfit = outfit
        var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: seed))
        let female = rng.bool(0.5)
        let look = Look.random(outfit: outfit, female: female, rng: &rng)

        box = PersonNode.makeBox()
        node.addChildNode(skeleton)
        let height = Float(rng.range(female ? 0.93 : 0.98, female ? 1.01 : 1.07))
        skeleton.scale = SCNVector3(height, height, height)

        let bind = PersonNode.bindPositions(female: female, build: look.build)
        for i in 0..<B.count {
            let b = SCNNode()
            let p = PersonNode.parents[i]
            let rel = p < 0 ? bind[i] : bind[i] - bind[p]
            b.simdPosition = rel
            bones.append(b)
            if p < 0 { skeleton.addChildNode(b) } else { bones[p].addChildNode(b) }
        }

        let mesh = PersonNode.buildMesh(bind: bind, look: look, female: female)
        let geo = SCNGeometry(sources: [mesh.pos, mesh.nrm, mesh.col], elements: [mesh.element])
        geo.firstMaterial = PersonNode.material
        let inverse = bind.map { p -> NSValue in
            NSValue(scnMatrix4: SCNMatrix4MakeTranslation(-p.x, -p.y, -p.z))
        }
        let skinner = SCNSkinner(baseGeometry: geo, bones: bones, boneInverseBindTransforms: inverse,
                                 boneWeights: mesh.weights, boneIndices: mesh.indices)
        let skin = SCNNode(geometry: geo)
        skin.skinner = skinner
        skinner.skeleton = bones[B.root]
        skeleton.addChildNode(skin)

        // Accessories rigidly attached to bones.
        for acc in look.accessories(rng: &rng) {
            bones[acc.bone].addChildNode(acc.node)
        }
        bones[B.chest].addChildNode(box)
        box.position = SCNVector3(0, 0.0, 0.33)
        box.isHidden = true

        if outfit == .cleaner {
            // Broom held in front: the handle top rests near the hands, the head sweeps the floor ahead.
            let broom = Assets.model("plastic_broom")
            broom.eulerAngles = SCNVector3(0, Float.pi, 0)
            let pivot = SCNNode()
            pivot.position = SCNVector3(0.1, 0, 0.2)
            pivot.addChildNode(broom)
            bones[B.root].addChildNode(pivot)
            prop = pivot
        }
        if outfit == .promoter {
            let flyers = SCNNode(geometry: SCNBox(width: 0.16, height: 0.012, length: 0.22, chamferRadius: 0.002))
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1)
            m.roughness.contents = 0.6
            flyers.geometry?.firstMaterial = m
            flyers.position = SCNVector3(0, -0.06, 0.05)
            bones[B.handL].addChildNode(flyers)
        }

        node.enumerateHierarchy { n, _ in n.castsShadow = true }
        pose(Pose())
    }

    // MARK: public API (used by Engine)

    var carrying: Bool {
        get { !box.isHidden }
        set { box.isHidden = !newValue }
    }

    func face(_ dir: SIMD3<Float>) {
        guard dir.x * dir.x + dir.z * dir.z > 1e-5 else { return }
        targetYaw = atan2(dir.x, dir.z)
        if !hasYaw {
            hasYaw = true
            yaw = targetYaw
            node.eulerAngles.y = yaw
        }
    }

    func faceToward(_ p: SIMD3<Float>) {
        face(p - node.simdPosition)
    }

    /// `moving` = walking speed in m/s (0 = standing).
    func animate(dt: Float, moving: Float, working: Bool) {
        // Smooth turning.
        var d = targetYaw - yaw
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        let turn = min(abs(d), dt * 9)
        yaw += d > 0 ? turn : -turn
        node.eulerAngles.y = yaw

        var p = Pose()
        if isSitting {
            sittingPose(&p, dt: dt)
            pose(p)
            return
        }
        if moving > 0.01 {
            phase += dt * moving / 1.35 * 2 * .pi
            walkPose(&p, amplitude: min(1, 0.55 + moving * 0.35))
        } else {
            phase += dt * 1.3
            workPhase += dt * (working ? 6.5 : 1)
            idlePose(&p, working: working)
        }
        if carrying {
            p.upperArm = (-0.62, -0.62)
            p.foreArm = (-1.05, -1.05)
            p.armOut = (0.12, 0.12)
        }
        pose(p)
    }

    func sit(_ on: Bool) {
        isSitting = on
        var p = Pose()
        if on { sittingPose(&p, dt: 0) }
        pose(p)
    }

    // MARK: animation

    private struct Pose {
        var hipsY: Float = 0
        var hipsPitch: Float = 0
        var spinePitch: Float = 0
        var spineYaw: Float = 0
        var chestPitch: Float = 0
        var headPitch: Float = 0
        var headYaw: Float = 0
        var upperArm: (Float, Float) = (0.02, 0.02)
        var armOut: (Float, Float) = (0.06, 0.06)
        var foreArm: (Float, Float) = (-0.12, -0.12)
        var thigh: (Float, Float) = (0, 0)
        var shin: (Float, Float) = (0, 0)
        var foot: (Float, Float) = (0, 0)
    }

    private func walkPose(_ p: inout Pose, amplitude a: Float) {
        let s = sin(phase), c = cos(phase)
        let thighA: Float = 0.42 * a
        p.thigh = (-thighA * s, thighA * s)
        // Knee flexes while the leg swings forward.
        let swingL = max(0, c), swingR = max(0, -c)
        p.shin = (0.08 + 0.75 * a * swingL * swingL, 0.08 + 0.75 * a * swingR * swingR)
        p.foot = (-(p.thigh.0 + p.shin.0) * 0.7, -(p.thigh.1 + p.shin.1) * 0.7)
        p.hipsY = -0.028 * a * (1 - abs(c))
        p.spineYaw = 0.07 * a * s
        p.spinePitch = 0.04
        p.upperArm = (0.32 * a * s, -0.32 * a * s)
        p.foreArm = (-0.22 - 0.25 * a * max(0, -s), -0.22 - 0.25 * a * max(0, s))
        p.armOut = (0.07, 0.07)
    }

    private func idlePose(_ p: inout Pose, working: Bool) {
        let breathe = sin(phase)
        p.chestPitch = 0.01 * breathe
        p.headYaw = 0.12 * sin(phase * 0.23)
        switch outfit {
        case .apron where working, .cashier where working:
            let w = workPhase
            p.spinePitch = 0.14
            p.headPitch = 0.3
            p.upperArm = (-0.55 + 0.12 * sin(w), -0.55 + 0.12 * sin(w + 2.1))
            p.foreArm = (-0.95 + 0.25 * sin(w + 0.8), -0.95 + 0.25 * sin(w + 2.9))
            p.armOut = (0.05, 0.05)
        case .cleaner:
            let w = workPhase * 0.55
            p.spinePitch = 0.18
            p.spineYaw = 0.22 * sin(w)
            p.headPitch = 0.25
            p.upperArm = (-0.45, -0.25)
            p.foreArm = (-0.7, -0.55)
            p.armOut = (-0.05, 0.12)
        case .promoter:
            let offer = max(0, sin(workPhase * 0.4))
            p.upperArm = (-0.6, -0.15 - 0.9 * offer)
            p.foreArm = (-1.1, -0.2 - 0.3 * offer)
            p.headYaw = 0.35 * sin(workPhase * 0.3)
        default:
            p.upperArm = (0.02 + 0.02 * breathe, 0.02 - 0.02 * breathe)
        }
    }

    private func sittingPose(_ p: inout Pose, dt: Float) {
        p.hipsY = -0.40
        p.thigh = (-1.5, -1.5)
        p.shin = (1.45, 1.45)
        p.foot = (0.05, 0.05)
        p.spinePitch = 0.08
        p.upperArm = (-0.42, -0.42)
        p.foreArm = (-1.05, -1.05)
        p.armOut = (0.1, 0.1)
        p.headPitch = 0.15
        eatTimer -= dt
        if eatTimer < 0 {
            // Bring a slice to the mouth for a moment.
            let t = min(1, -eatTimer / 0.5) * min(1, max(0, (1.6 + eatTimer) / 0.5))
            p.upperArm.1 = -0.42 - 0.5 * t
            p.foreArm.1 = -1.05 - 0.95 * t
            p.headPitch = 0.15 - 0.15 * t
            if eatTimer < -1.6 { eatTimer = Float.random(in: 3...7) }
        }
    }

    private func pose(_ p: Pose) {
        bones[B.hips].simdPosition = SIMD3(0, bindHipsY + p.hipsY, 0)
        bones[B.hips].eulerAngles = SCNVector3(p.hipsPitch, 0, 0)
        bones[B.spine].eulerAngles = SCNVector3(p.spinePitch, p.spineYaw, 0)
        bones[B.chest].eulerAngles = SCNVector3(p.chestPitch, p.spineYaw * 0.5, 0)
        bones[B.head].eulerAngles = SCNVector3(p.headPitch, p.headYaw, 0)
        bones[B.upperArmL].eulerAngles = SCNVector3(p.upperArm.0, 0, -p.armOut.0)
        bones[B.upperArmR].eulerAngles = SCNVector3(p.upperArm.1, 0, p.armOut.1)
        bones[B.foreArmL].eulerAngles = SCNVector3(p.foreArm.0, 0, 0)
        bones[B.foreArmR].eulerAngles = SCNVector3(p.foreArm.1, 0, 0)
        bones[B.thighL].eulerAngles = SCNVector3(p.thigh.0, 0, 0)
        bones[B.thighR].eulerAngles = SCNVector3(p.thigh.1, 0, 0)
        bones[B.shinL].eulerAngles = SCNVector3(p.shin.0, 0, 0)
        bones[B.shinR].eulerAngles = SCNVector3(p.shin.1, 0, 0)
        bones[B.footL].eulerAngles = SCNVector3(p.foot.0, 0, 0)
        bones[B.footR].eulerAngles = SCNVector3(p.foot.1, 0, 0)
        prop?.eulerAngles = SCNVector3(0, p.spineYaw * 1.4, 0)
    }

    private lazy var bindHipsY: Float = bones[B.hips].simdPosition.y

    // MARK: skeleton

    private static func bindPositions(female: Bool, build: Float) -> [SIMD3<Float>] {
        let sh: Float = female ? 0.168 : 0.19
        let hip: Float = female ? 0.092 : 0.088
        var b = [SIMD3<Float>](repeating: .zero, count: B.count)
        b[B.root] = SIMD3(0, 0, 0)
        b[B.hips] = SIMD3(0, 0.93, 0)
        b[B.spine] = SIMD3(0, 1.06, 0)
        b[B.chest] = SIMD3(0, 1.24, 0)
        b[B.neck] = SIMD3(0, 1.46, -0.01)
        b[B.head] = SIMD3(0, 1.56, 0)
        b[B.upperArmL] = SIMD3(-sh - 0.01 * build, 1.405, -0.01)
        b[B.foreArmL] = SIMD3(-sh - 0.025 - 0.01 * build, 1.125, -0.01)
        b[B.handL] = SIMD3(-sh - 0.03 - 0.01 * build, 0.875, 0.0)
        b[B.upperArmR] = SIMD3(-b[B.upperArmL].x, b[B.upperArmL].y, b[B.upperArmL].z)
        b[B.foreArmR] = SIMD3(-b[B.foreArmL].x, b[B.foreArmL].y, b[B.foreArmL].z)
        b[B.handR] = SIMD3(-b[B.handL].x, b[B.handL].y, b[B.handL].z)
        b[B.thighL] = SIMD3(-hip, 0.9, 0)
        b[B.shinL] = SIMD3(-hip + 0.005, 0.49, 0.005)
        b[B.footL] = SIMD3(-hip + 0.01, 0.085, -0.01)
        b[B.thighR] = SIMD3(hip, 0.9, 0)
        b[B.shinR] = SIMD3(hip - 0.005, 0.49, 0.005)
        b[B.footR] = SIMD3(hip - 0.01, 0.085, -0.01)
        return b
    }

    // MARK: appearance

    private struct Look {
        var skin: SIMD3<Float>
        var top: SIMD3<Float>
        var pants: SIMD3<Float>
        var shoes: SIMD3<Float>
        var hair: SIMD3<Float>
        var sleeves: Float        // 0 = short sleeve, 1 = long sleeve
        var hairStyle: Int        // 0 bald, 1 short, 2 long, 3 bun
        var build: Float          // 0 slim … 1 heavy
        var apron: SIMD3<Float>?
        var cap: SIMD3<Float>?
        var backpack: SIMD3<Float>?
        var jacketLength: Float   // extra torso cloth below the waist (coats)
        var female = false

        static func random(outfit: Outfit, female: Bool, rng: inout SeededRandom) -> Look {
            func pick(_ a: [SIMD3<Float>]) -> SIMD3<Float> { a[rng.int(a.count)] }
            var l = Look(skin: pick(PersonNode.skinTones.prefix(4).map { $0 } + (rng.bool(0.15) ? Array(PersonNode.skinTones.suffix(2)) : [])),
                         top: pick(PersonNode.tops), pants: pick(PersonNode.pants), shoes: pick(PersonNode.shoes),
                         hair: pick(PersonNode.hairs), sleeves: rng.bool(0.7) ? 1 : 0,
                         hairStyle: female ? (rng.bool(0.65) ? 2 : 3) : (rng.bool(0.12) ? 0 : 1),
                         build: Float(rng.range(0, 1)) * Float(rng.range(0.3, 1)),
                         apron: nil, cap: nil, backpack: nil, jacketLength: rng.bool(0.25) ? Float(rng.range(0.08, 0.22)) : 0,
                         female: female)
            switch outfit {
            case .casual: break
            case .apron:
                l.top = SIMD3(0.92, 0.91, 0.89)
                l.sleeves = 0
                l.pants = SIMD3(0.09, 0.09, 0.10)
                l.apron = SIMD3(0.12, 0.12, 0.13)
                l.cap = SIMD3(0.10, 0.10, 0.11)
                l.jacketLength = 0
                l.shoes = SIMD3(0.05, 0.05, 0.05)
            case .cashier:
                l.top = SIMD3(0.10, 0.10, 0.11)
                l.sleeves = 0
                l.pants = SIMD3(0.09, 0.09, 0.10)
                l.apron = SIMD3(0.55, 0.12, 0.10)
                l.cap = SIMD3(0.55, 0.12, 0.10)
                l.jacketLength = 0
            case .courier:
                l.top = SIMD3(0.16, 0.42, 0.20)
                l.sleeves = 1
                l.backpack = SIMD3(0.16, 0.42, 0.20)
                l.jacketLength = 0.1
                l.pants = SIMD3(0.09, 0.09, 0.10)
            case .cleaner:
                l.top = SIMD3(0.20, 0.33, 0.52)
                l.sleeves = 0
                l.pants = SIMD3(0.20, 0.33, 0.52)
                l.jacketLength = 0.25
                l.hairStyle = 3
            case .promoter:
                l.top = SIMD3(0.95, 0.55, 0.08)
                l.sleeves = 1
                l.jacketLength = 0.05
            }
            return l
        }

        struct Accessory { let bone: Int; let node: SCNNode }

        private static func mat(_ c: SIMD3<Float>, rough: CGFloat = 0.8) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
            m.roughness.contents = rough
            return m
        }

        func accessories(rng: inout SeededRandom) -> [Accessory] {
            var out: [Accessory] = []
            // Face: eyes, brows and mouth (relative to the head bone at y 1.56).
            let eye = Look.mat(SIMD3(0.06, 0.05, 0.05), rough: 0.25)
            let brow = Look.mat(hair * 0.7, rough: 0.8)
            let lips = Look.mat(SIMD3(skin.x * 0.75, skin.y * 0.5, skin.z * 0.48), rough: 0.6)
            for sx in [Float(-1), Float(1)] {
                let e = SCNNode(geometry: SCNSphere(radius: 0.0105))
                e.geometry?.firstMaterial = eye
                e.position = SCNVector3(sx * 0.03, 0.116, 0.095)
                e.scale = SCNVector3(1, 0.8, 0.6)
                out.append(Accessory(bone: B.head, node: e))
                let b = SCNNode(geometry: SCNBox(width: 0.03, height: 0.0065, length: 0.008, chamferRadius: 0.002))
                b.geometry?.firstMaterial = brow
                b.position = SCNVector3(sx * 0.031, 0.136, 0.097)
                b.eulerAngles.z = sx * -0.12
                out.append(Accessory(bone: B.head, node: b))
            }
            let mouth = SCNNode(geometry: SCNBox(width: 0.03, height: 0.006, length: 0.006, chamferRadius: 0.002))
            mouth.geometry?.firstMaterial = lips
            mouth.position = SCNVector3(0, 0.066, 0.093)
            out.append(Accessory(bone: B.head, node: mouth))
            if let c = cap {
                let capNode = SCNNode(geometry: SCNSphere(radius: 0.1))
                capNode.geometry?.firstMaterial = Look.mat(c)
                capNode.scale = SCNVector3(0.98, 0.55, 1.05)
                capNode.position = SCNVector3(0, 0.155, -0.005)
                let visor = SCNNode(geometry: SCNCylinder(radius: 0.075, height: 0.008))
                visor.geometry?.firstMaterial = Look.mat(c)
                visor.scale = SCNVector3(1, 1, 0.75)
                visor.position = SCNVector3(0, 0.13, 0.085)
                visor.eulerAngles.x = 0.12
                out.append(Accessory(bone: B.head, node: capNode))
                out.append(Accessory(bone: B.head, node: visor))
            }
            if let c = backpack {
                let bag = SCNNode(geometry: SCNBox(width: 0.40, height: 0.42, length: 0.30, chamferRadius: 0.04))
                bag.geometry?.firstMaterial = Look.mat(c, rough: 0.55)
                bag.position = SCNVector3(0, 0.04, -0.27)
                out.append(Accessory(bone: B.chest, node: bag))
            }
            if let c = apron {
                let a = SCNNode(geometry: SCNBox(width: 0.32, height: 0.62, length: 0.012, chamferRadius: 0.004))
                a.geometry?.firstMaterial = Look.mat(c, rough: 0.9)
                a.position = SCNVector3(0, -0.12, 0.118)
                out.append(Accessory(bone: B.hips, node: a))
                let bib = SCNNode(geometry: SCNBox(width: 0.24, height: 0.26, length: 0.012, chamferRadius: 0.004))
                bib.geometry?.firstMaterial = Look.mat(c, rough: 0.9)
                bib.position = SCNVector3(0, 0.07, female ? 0.156 : 0.13)
                out.append(Accessory(bone: B.chest, node: bib))
            }
            return out
        }
    }

    // MARK: mesh

    private struct Mesh {
        let pos: SCNGeometrySource
        let nrm: SCNGeometrySource
        let col: SCNGeometrySource
        let weights: SCNGeometrySource
        let indices: SCNGeometrySource
        let element: SCNGeometryElement
    }

    private struct Builder {
        var p: [SIMD3<Float>] = []
        var c: [SIMD4<Float>] = []
        var bi: [SIMD2<UInt16>] = []
        var bw: [SIMD2<Float>] = []
        var tri: [UInt16] = []

        mutating func v(_ pos: SIMD3<Float>, _ col: SIMD3<Float>, _ b0: Int, _ b1: Int, _ w1: Float) -> UInt16 {
            p.append(pos)
            // Palette colours are sRGB; vertex colours are used as linear values.
            c.append(SIMD4(pow(col.x, 2.2), pow(col.y, 2.2), pow(col.z, 2.2), 1))
            bi.append(SIMD2(UInt16(b0), UInt16(b1)))
            bw.append(SIMD2(1 - w1, w1))
            return UInt16(p.count - 1)
        }

        mutating func face(_ a: UInt16, _ b: UInt16, _ c: UInt16, outward: SIMD3<Float>) {
            let n = simd_cross(p[Int(b)] - p[Int(a)], p[Int(c)] - p[Int(a)])
            if simd_dot(n, outward) >= 0 { tri += [a, b, c] } else { tri += [a, c, b] }
        }
    }

    struct Ring {
        var c: SIMD3<Float>
        var rx: Float
        var ry: Float          // the second radius (z for vertical tubes, y for horizontal ones)
        var b0: Int
        var b1: Int = 0
        var w: Float = 0
        var color: SIMD3<Float>
        var front: Float = 0   // extra bulge toward +z (chest, toes)
    }

    /// Tube of rings. `vertical` rings lie in the XZ plane, otherwise in the XY plane (feet).
    private static func tube(_ b: inout Builder, _ rings: [Ring], seg: Int, vertical: Bool = true, capStart: Bool = false, capEnd: Bool = false) {
        var idx: [[UInt16]] = []
        for r in rings {
            var row: [UInt16] = []
            for k in 0..<seg {
                let a = Float(k) / Float(seg) * 2 * .pi
                let ca = cos(a), sa = sin(a)
                var off: SIMD3<Float>
                if vertical {
                    off = SIMD3(ca * r.rx, 0, sa * r.ry)
                    if sa > 0 { off.z += sa * sa * r.front }
                } else {
                    off = SIMD3(ca * r.rx, sa * r.ry, 0)
                }
                row.append(b.v(r.c + off, r.color, r.b0, r.b1, r.w))
            }
            idx.append(row)
        }
        for i in 0..<(rings.count - 1) {
            for k in 0..<seg {
                let k1 = (k + 1) % seg
                let a = idx[i][k], bb = idx[i + 1][k], c = idx[i][k1], d = idx[i + 1][k1]
                let mid = (b.p[Int(a)] + b.p[Int(d)]) * 0.5
                let axis = (rings[i].c + rings[i + 1].c) * 0.5
                var out = mid - axis
                if vertical { out.y = 0 } else { out.z = 0 }
                b.face(a, bb, c, outward: out)
                b.face(c, bb, d, outward: out)
            }
        }
        func cap(_ i: Int, dir: Float) {
            let r = rings[i]
            let centre = b.v(r.c, r.color, r.b0, r.b1, r.w)
            let out: SIMD3<Float> = vertical ? SIMD3(0, dir, 0) : SIMD3(0, 0, dir)
            for k in 0..<seg {
                b.face(centre, idx[i][k], idx[i][(k + 1) % seg], outward: out)
            }
        }
        if capStart { cap(0, dir: vertical ? (rings[0].c.y < rings[1].c.y ? -1 : 1) : (rings[0].c.z < rings[1].c.z ? -1 : 1)) }
        if capEnd {
            let n = rings.count - 1
            cap(n, dir: vertical ? (rings[n].c.y > rings[n - 1].c.y ? 1 : -1) : (rings[n].c.z > rings[n - 1].c.z ? 1 : -1))
        }
    }

    /// Ellipsoid with an optional per-vertex deformation; rigidly bound to one bone.
    private static func blob(_ b: inout Builder, centre: SIMD3<Float>, radii: SIMD3<Float>, bone: Int, color: (SIMD3<Float>) -> SIMD3<Float>,
                             lat: Int = 10, lon: Int = 14, keep: ((SIMD3<Float>) -> Bool)? = nil,
                             deform: ((SIMD3<Float>) -> SIMD3<Float>)? = nil) {
        var grid: [[UInt16?]] = []
        for i in 0...lat {
            let th = Float(i) / Float(lat) * .pi
            var row: [UInt16?] = []
            for j in 0..<lon {
                let ph = Float(j) / Float(lon) * 2 * .pi
                let unit = SIMD3<Float>(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
                if let keep, !keep(unit) { row.append(nil); continue }
                var q = unit * radii
                if let deform { q = deform(q) }
                row.append(b.v(centre + q, color(unit), bone, bone, 0))
            }
            grid.append(row)
        }
        for i in 0..<lat {
            for j in 0..<lon {
                let j1 = (j + 1) % lon
                guard let a = grid[i][j], let c = grid[i][j1], let bb = grid[i + 1][j], let d = grid[i + 1][j1] else { continue }
                let out = (b.p[Int(a)] + b.p[Int(d)]) * 0.5 - centre
                b.face(a, bb, c, outward: out)
                b.face(c, bb, d, outward: out)
            }
        }
    }

    private static func buildMesh(bind: [SIMD3<Float>], look l: Look, female: Bool) -> Mesh {
        var b = Builder()
        let fat = l.build
        let skin = l.skin
        let top = l.top
        let pants = l.pants
        let shoe = l.shoes
        let hair = l.hair

        // Torso: crotch → neck base.
        let hipW: Float = (female ? 0.165 : 0.150) + 0.02 * fat
        let waistW: Float = (female ? 0.125 : 0.140) + 0.045 * fat
        let chestW: Float = (female ? 0.150 : 0.172) + 0.02 * fat
        let belly: Float = 0.035 * fat
        let beltY: Float = 1.0
        let coat = l.jacketLength
        func torsoColor(_ y: Float) -> SIMD3<Float> { y < beltY - coat ? pants : top }
        let torso: [(Float, Float, Float, Float, Int, Int, Float)] = [
            // y, rx, rz, front, b0, b1, w
            (0.84, hipW * 0.55, 0.075, 0, B.hips, 0, 0),
            (0.88, hipW * 0.92, 0.10, 0.0, B.hips, 0, 0),
            (0.95, hipW, 0.112, 0.005, B.hips, 0, 0),
            (1.02, (hipW + waistW) * 0.5, 0.108 + belly * 0.4, belly * 0.6, B.hips, B.spine, 0.4),
            (1.10, waistW, 0.102 + belly * 0.6, belly, B.spine, 0, 0),
            (1.19, (waistW + chestW) * 0.5, 0.106 + belly * 0.3, female ? 0.02 : belly * 0.5, B.spine, B.chest, 0.5),
            (1.28, chestW, 0.112, female ? 0.035 : 0.012, B.chest, 0, 0),
            (1.36, chestW * 1.02, 0.106, female ? 0.02 : 0.008, B.chest, 0, 0),
            (1.42, chestW * 0.88, 0.088, 0, B.chest, 0, 0),
            (1.455, 0.075, 0.062, 0, B.chest, B.neck, 0.4),
        ]
        tube(&b, torso.map { Ring(c: SIMD3(0, $0.0, -0.005), rx: $0.1, ry: $0.2, b0: $0.4, b1: $0.5, w: $0.6,
                                  color: torsoColor($0.0), front: $0.3) }, seg: 16, capStart: true, capEnd: false)

        // Neck.
        tube(&b, [
            Ring(c: SIMD3(0, 1.44, -0.01), rx: 0.058, ry: 0.056, b0: B.chest, b1: B.neck, w: 0.5, color: l.cap == nil && l.apron == nil && l.sleeves > 0.5 && coat > 0.15 ? top : skin),
            Ring(c: SIMD3(0, 1.52, -0.005), rx: 0.052, ry: 0.052, b0: B.neck, color: skin),
            Ring(c: SIMD3(0, 1.585, 0.0), rx: 0.05, ry: 0.05, b0: B.neck, b1: B.head, w: 0.7, color: skin),
        ], seg: 10)

        // Head with jaw and nose.
        let headC = SIMD3<Float>(0, 1.665, 0.008)
        let headR = SIMD3<Float>(0.083, 0.112, 0.098)
        blob(&b, centre: headC, radii: headR, bone: B.head, color: { _ in skin }, lat: 12, lon: 16, deform: { q in
            var q = q
            if q.y < 0 {   // narrower jaw
                let t = min(1, -q.y / 0.112)
                q.x *= 1 - 0.22 * t
                q.z *= 1 - 0.1 * t
            }
            if q.z > 0.06 && abs(q.x) < 0.025 && q.y > -0.05 && q.y < 0.02 {   // nose
                let k = (1 - abs(q.x) / 0.025) * (1 - abs(q.y + 0.015) / 0.035)
                q.z += 0.022 * max(0, k)
            }
            return q
        })

        // Hair.
        switch l.hairStyle {
        case 0: break
        default:
            let r = headR + SIMD3(0.008, 0.008, 0.008)
            blob(&b, centre: headC + SIMD3(0, 0.004, -0.004), radii: r, bone: B.head, color: { _ in hair }, lat: 10, lon: 16,
                 keep: { u in
                     // Hairline: higher at the front, lower at the back and sides.
                     let front = max(0, u.z)
                     return u.y > -0.15 + 0.55 * front * front - (u.z < 0 ? 0.35 * (-u.z) : 0)
                 })
            if l.hairStyle == 2 {
                tube(&b, [
                    Ring(c: SIMD3(0, 1.69, -0.045), rx: 0.088, ry: 0.07, b0: B.head, color: hair),
                    Ring(c: SIMD3(0, 1.58, -0.07), rx: 0.092, ry: 0.05, b0: B.head, b1: B.neck, w: 0.4, color: hair),
                    Ring(c: SIMD3(0, 1.46, -0.085), rx: 0.09, ry: 0.035, b0: B.neck, b1: B.chest, w: 0.6, color: hair),
                ], seg: 10, capEnd: true)
            } else if l.hairStyle == 3 {
                blob(&b, centre: headC + SIMD3(0, 0.07, -0.085), radii: SIMD3(0.045, 0.04, 0.04), bone: B.head, color: { _ in hair }, lat: 6, lon: 8)
            }
        }

        // Arms.
        for side in [Float(-1), Float(1)] {
            let ua = side < 0 ? B.upperArmL : B.upperArmR
            let fa = side < 0 ? B.foreArmL : B.foreArmR
            let hd = side < 0 ? B.handL : B.handR
            let s = bind[ua], e = bind[fa], w = bind[hd]
            let upper = top
            let sleeveEnd: SIMD3<Float> = l.sleeves > 0.5 ? top : skin
            let armR: Float = 0.047 + 0.012 * fat
            tube(&b, [
                Ring(c: s + SIMD3(0, 0.035, 0), rx: armR * 1.05, ry: armR * 1.05, b0: B.chest, b1: ua, w: 0.5, color: upper),
                Ring(c: s + (e - s) * 0.1, rx: armR, ry: armR, b0: ua, color: upper),
                Ring(c: s + (e - s) * 0.45, rx: armR * 0.92, ry: armR * 0.95, b0: ua, color: top),
                Ring(c: s + (e - s) * 0.62, rx: armR * 0.86, ry: armR * 0.9, b0: ua, color: l.sleeves > 0.5 ? top : skin),
                Ring(c: e, rx: armR * 0.78, ry: armR * 0.8, b0: ua, b1: fa, w: 0.5, color: sleeveEnd),
                Ring(c: e + (w - e) * 0.35, rx: armR * 0.8, ry: armR * 0.78, b0: fa, color: sleeveEnd),
                Ring(c: e + (w - e) * 0.92, rx: armR * 0.58, ry: armR * 0.55, b0: fa, color: l.sleeves > 0.5 ? top : skin),
                Ring(c: w + SIMD3(0, 0.01, 0), rx: armR * 0.5, ry: armR * 0.45, b0: fa, b1: hd, w: 0.5, color: skin),
            ], seg: 9)
            // Hand.
            blob(&b, centre: w + SIMD3(side * 0.004, -0.075, 0.008), radii: SIMD3(0.022, 0.078, 0.042), bone: hd, color: { _ in skin }, lat: 6, lon: 8)
        }

        // Legs.
        for side in [Float(-1), Float(1)] {
            let th = side < 0 ? B.thighL : B.thighR
            let sh = side < 0 ? B.shinL : B.shinR
            let ft = side < 0 ? B.footL : B.footR
            let h = bind[th], k = bind[sh], a = bind[ft]
            let legR: Float = (female ? 0.078 : 0.074) + 0.02 * fat
            tube(&b, [
                Ring(c: h + SIMD3(-side * 0.005, 0.03, 0), rx: legR, ry: legR * 1.05, b0: B.hips, b1: th, w: 0.6, color: pants),
                Ring(c: h + (k - h) * 0.15, rx: legR * 0.98, ry: legR * 1.02, b0: th, color: pants),
                Ring(c: h + (k - h) * 0.55, rx: legR * 0.82, ry: legR * 0.86, b0: th, color: pants),
                Ring(c: k + SIMD3(0, 0.03, 0), rx: legR * 0.66, ry: legR * 0.7, b0: th, b1: sh, w: 0.35, color: pants),
                Ring(c: k - SIMD3(0, 0.03, 0), rx: legR * 0.64, ry: legR * 0.68, b0: th, b1: sh, w: 0.7, color: pants),
                Ring(c: k + (a - k) * 0.3, rx: legR * 0.68, ry: legR * 0.74, b0: sh, color: pants),
                Ring(c: k + (a - k) * 0.78, rx: legR * 0.55, ry: legR * 0.57, b0: sh, color: pants),
                Ring(c: a + SIMD3(0, 0.035, 0), rx: legR * 0.52, ry: legR * 0.54, b0: sh, b1: ft, w: 0.5, color: shoe),
            ], seg: 10)
            // Shoe: heel → toe along +z.
            let fl: Float = female ? 0.235 : 0.26
            tube(&b, [
                Ring(c: a + SIMD3(0, -0.035, -0.045), rx: 0.036, ry: 0.04, b0: ft, color: shoe),
                Ring(c: a + SIMD3(0, -0.03, -0.01), rx: 0.044, ry: 0.05, b0: ft, color: shoe),
                Ring(c: a + SIMD3(0, -0.045, fl * 0.35), rx: 0.048, ry: 0.035, b0: ft, color: shoe),
                Ring(c: a + SIMD3(0, -0.055, fl * 0.62), rx: 0.046, ry: 0.024, b0: ft, color: shoe),
                Ring(c: a + SIMD3(0, -0.062, fl * 0.74), rx: 0.03, ry: 0.016, b0: ft, color: shoe),
            ], seg: 8, vertical: false, capStart: true, capEnd: true)
        }

        // Pack into geometry sources.
        let n = b.p.count
        var normals = [SIMD3<Float>](repeating: .zero, count: n)
        for t in stride(from: 0, to: b.tri.count, by: 3) {
            let i0 = Int(b.tri[t]), i1 = Int(b.tri[t + 1]), i2 = Int(b.tri[t + 2])
            let fn = simd_cross(b.p[i1] - b.p[i0], b.p[i2] - b.p[i0])
            normals[i0] += fn
            normals[i1] += fn
            normals[i2] += fn
        }
        normals = normals.map { simd_length($0) > 1e-9 ? simd_normalize($0) : SIMD3(0, 1, 0) }

        func data<T>(_ a: [T]) -> Data { a.withUnsafeBufferPointer { Data(buffer: $0) } }
        let posFlat = b.p.flatMap { [$0.x, $0.y, $0.z] }
        let nrmFlat = normals.flatMap { [$0.x, $0.y, $0.z] }
        let colFlat = b.c.flatMap { [$0.x, $0.y, $0.z, $0.w] }
        let wFlat = b.bw.flatMap { [$0.x, $0.y] }
        let iFlat = b.bi.flatMap { [$0.x, $0.y] }
        return Mesh(
            pos: SCNGeometrySource(data: data(posFlat), semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            nrm: SCNGeometrySource(data: data(nrmFlat), semantic: .normal, vectorCount: n, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            col: SCNGeometrySource(data: data(colFlat), semantic: .color, vectorCount: n, usesFloatComponents: true,
                                   componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16),
            weights: SCNGeometrySource(data: data(wFlat), semantic: .boneWeights, vectorCount: n, usesFloatComponents: true,
                                       componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8),
            indices: SCNGeometrySource(data: data(iFlat), semantic: .boneIndices, vectorCount: n, usesFloatComponents: false,
                                       componentsPerVector: 2, bytesPerComponent: 2, dataOffset: 0, dataStride: 4),
            element: SCNGeometryElement(data: data(b.tri), primitiveType: .triangles, primitiveCount: b.tri.count / 3, bytesPerIndex: 2))
    }

    private static func makeBox() -> SCNNode {
        let box = SCNNode(geometry: SCNBox(width: 0.34, height: 0.045, length: 0.34, chamferRadius: 0.004))
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = World.cardboard
        m.roughness.contents = 0.9
        box.geometry?.firstMaterial = m
        return box
    }
}

/// Deterministic random numbers (SplitMix64), so people and textures are reproducible.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
    mutating func bool(_ p: Double) -> Bool { unit() < p }
}
