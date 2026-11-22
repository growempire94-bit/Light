import SceneKit
import UIKit

/// A low-poly human with realistic proportions (≈1.75 m), built from primitives
/// and animated procedurally: walking, working, sitting, carrying a pizza box.
final class PersonNode {
    let node = SCNNode()
    private let body = SCNNode()
    private let leftLeg = SCNNode(), rightLeg = SCNNode()
    private let leftArm = SCNNode(), rightArm = SCNNode()
    private let box: SCNNode = {
        let box = SCNNode(geometry: SCNBox(width: 0.34, height: 0.045, length: 0.34, chamferRadius: 0.004))
        let boxMat = SCNMaterial()
        boxMat.lightingModel = .physicallyBased
        boxMat.diffuse.contents = World.cardboard
        boxMat.roughness.contents = 0.9
        box.geometry?.firstMaterial = boxMat
        box.position = SCNVector3(0, 1.02, 0.32)
        box.isHidden = true
        return box
    }()
    private var phase: Float = Float.random(in: 0...6)
    private(set) var isSitting = false

    enum Outfit { case casual, apron, courier }

    static let skinTones: [UIColor] = [
        UIColor(red: 0.93, green: 0.78, blue: 0.66, alpha: 1), UIColor(red: 0.86, green: 0.68, blue: 0.55, alpha: 1),
        UIColor(red: 0.76, green: 0.57, blue: 0.43, alpha: 1), UIColor(red: 0.55, green: 0.38, blue: 0.27, alpha: 1),
    ]
    static let tops: [UIColor] = [
        UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1), UIColor(red: 0.55, green: 0.56, blue: 0.58, alpha: 1),
        UIColor(red: 0.80, green: 0.78, blue: 0.72, alpha: 1), UIColor(red: 0.24, green: 0.31, blue: 0.24, alpha: 1),
        UIColor(red: 0.44, green: 0.14, blue: 0.13, alpha: 1), UIColor(red: 0.20, green: 0.27, blue: 0.40, alpha: 1),
        UIColor(red: 0.62, green: 0.50, blue: 0.36, alpha: 1), UIColor(red: 0.90, green: 0.90, blue: 0.88, alpha: 1),
    ]
    static let pants: [UIColor] = [
        UIColor(red: 0.17, green: 0.22, blue: 0.33, alpha: 1), UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1),
        UIColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1), UIColor(red: 0.29, green: 0.37, blue: 0.48, alpha: 1),
    ]
    static let hairs: [UIColor] = [
        UIColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1), UIColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1),
        UIColor(red: 0.55, green: 0.42, blue: 0.26, alpha: 1), UIColor(red: 0.62, green: 0.60, blue: 0.57, alpha: 1),
    ]

    private static func mat(_ color: UIColor, rough: CGFloat = 0.85) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = rough
        m.metalness.contents = 0.0
        return m
    }

    init(outfit: Outfit = .casual, seed: Int = Int.random(in: 0...10_000)) {
        var rng = SeededRandom(seed: UInt64(seed))
        let skin = PersonNode.mat(PersonNode.skinTones[rng.int(PersonNode.skinTones.count)], rough: 0.6)
        let top: SCNMaterial
        switch outfit {
        case .casual: top = PersonNode.mat(PersonNode.tops[rng.int(PersonNode.tops.count)])
        case .apron: top = PersonNode.mat(UIColor(white: 0.93, alpha: 1))
        case .courier: top = PersonNode.mat(UIColor(red: 0.95, green: 0.70, blue: 0.10, alpha: 1))
        }
        let pantsMat = PersonNode.mat(PersonNode.pants[rng.int(PersonNode.pants.count)])
        let shoe = PersonNode.mat(UIColor(white: rng.bool(0.5) ? 0.08 : 0.85, alpha: 1), rough: 0.5)
        let hair = PersonNode.mat(PersonNode.hairs[rng.int(PersonNode.hairs.count)], rough: 0.7)
        let height = Float(rng.range(0.93, 1.06))
        let longHair = rng.bool(0.45)

        node.addChildNode(body)
        body.scale = SCNVector3(height, height, height)

        // Legs: pivot at the hip, geometry hangs down.
        for (leg, x) in [(leftLeg, Float(-0.1)), (rightLeg, Float(0.1))] {
            leg.position = SCNVector3(x, 0.92, 0)
            let thigh = SCNNode(geometry: SCNCapsule(capRadius: 0.075, height: 0.9))
            thigh.geometry?.firstMaterial = pantsMat
            thigh.position = SCNVector3(0, -0.45, 0)
            leg.addChildNode(thigh)
            let foot = SCNNode(geometry: SCNBox(width: 0.11, height: 0.07, length: 0.27, chamferRadius: 0.03))
            foot.geometry?.firstMaterial = shoe
            foot.position = SCNVector3(0, -0.88, 0.05)
            leg.addChildNode(foot)
            body.addChildNode(leg)
        }

        let torso = SCNNode(geometry: SCNCapsule(capRadius: 0.19, height: 0.68))
        torso.geometry?.firstMaterial = top
        torso.position = SCNVector3(0, 1.24, 0)
        torso.scale = SCNVector3(1, 1, 0.62)
        body.addChildNode(torso)

        if outfit == .apron {
            let apron = SCNNode(geometry: SCNBox(width: 0.34, height: 0.62, length: 0.02, chamferRadius: 0.01))
            apron.geometry?.firstMaterial = PersonNode.mat(UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1))
            apron.position = SCNVector3(0, 1.08, 0.125)
            body.addChildNode(apron)
        }
        if outfit == .courier {
            let bag = SCNNode(geometry: SCNBox(width: 0.38, height: 0.42, length: 0.30, chamferRadius: 0.03))
            bag.geometry?.firstMaterial = PersonNode.mat(UIColor(red: 0.98, green: 0.72, blue: 0.08, alpha: 1), rough: 0.6)
            bag.position = SCNVector3(0, 1.30, -0.27)
            body.addChildNode(bag)
        }

        let neck = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.1))
        neck.geometry?.firstMaterial = skin
        neck.position = SCNVector3(0, 1.6, 0)
        body.addChildNode(neck)

        let head = SCNNode(geometry: SCNSphere(radius: 0.11))
        head.geometry?.firstMaterial = skin
        head.position = SCNVector3(0, 1.72, 0.01)
        head.scale = SCNVector3(0.9, 1.08, 0.98)
        body.addChildNode(head)

        let hairCap = SCNNode(geometry: SCNSphere(radius: 0.118))
        hairCap.geometry?.firstMaterial = hair
        hairCap.position = SCNVector3(0, 1.755, -0.012)
        hairCap.scale = SCNVector3(0.93, 0.9, 1.0)
        body.addChildNode(hairCap)
        if longHair {
            let back = SCNNode(geometry: SCNCapsule(capRadius: 0.09, height: 0.36))
            back.geometry?.firstMaterial = hair
            back.position = SCNVector3(0, 1.6, -0.07)
            back.scale = SCNVector3(1.1, 1, 0.6)
            body.addChildNode(back)
        }
        if outfit == .apron {
            let cap = SCNNode(geometry: SCNCylinder(radius: 0.11, height: 0.07))
            cap.geometry?.firstMaterial = PersonNode.mat(UIColor(white: 0.12, alpha: 1))
            cap.position = SCNVector3(0, 1.84, -0.01)
            body.addChildNode(cap)
        }

        for (arm, x) in [(leftArm, Float(-0.245)), (rightArm, Float(0.245))] {
            arm.position = SCNVector3(x, 1.47, 0)
            let upper = SCNNode(geometry: SCNCapsule(capRadius: 0.052, height: 0.62))
            upper.geometry?.firstMaterial = top
            upper.position = SCNVector3(0, -0.29, 0)
            arm.addChildNode(upper)
            let hand = SCNNode(geometry: SCNSphere(radius: 0.048))
            hand.geometry?.firstMaterial = skin
            hand.position = SCNVector3(0, -0.62, 0.01)
            arm.addChildNode(hand)
            body.addChildNode(arm)
        }

        body.addChildNode(box)

        node.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    var carrying: Bool {
        get { !box.isHidden }
        set { box.isHidden = !newValue }
    }

    func face(_ dir: SIMD3<Float>) {
        guard dir.x * dir.x + dir.z * dir.z > 1e-4 else { return }
        node.eulerAngles.y = atan2(dir.x, dir.z)
    }

    func faceToward(_ p: SIMD3<Float>) {
        let pos = SIMD3<Float>(node.position.x, node.position.y, node.position.z)
        face(p - pos)
    }

    /// Advance the procedural animation. `moving` = walking speed in m/s (0 = standing).
    func animate(dt: Float, moving: Float, working: Bool) {
        if isSitting { return }
        if moving > 0.01 {
            phase += dt * moving * 5.2
            let s = sin(phase)
            leftLeg.eulerAngles.x = s * 0.45
            rightLeg.eulerAngles.x = -s * 0.45
            let armSwing = carrying ? 0 : s * 0.38
            leftArm.eulerAngles.x = carrying ? -1.15 : -armSwing
            rightArm.eulerAngles.x = carrying ? -1.15 : armSwing
            body.position.y = abs(cos(phase)) * 0.035
        } else {
            phase += dt * (working ? 7 : 1.2)
            leftLeg.eulerAngles.x = 0
            rightLeg.eulerAngles.x = 0
            body.position.y = 0
            if carrying {
                leftArm.eulerAngles.x = -1.15
                rightArm.eulerAngles.x = -1.15
            } else if working {
                leftArm.eulerAngles.x = -0.95 + sin(phase) * 0.25
                rightArm.eulerAngles.x = -0.95 + sin(phase + 1.7) * 0.25
            } else {
                leftArm.eulerAngles.x = sin(phase) * 0.03
                rightArm.eulerAngles.x = -sin(phase) * 0.03
            }
        }
    }

    func sit(_ on: Bool) {
        isSitting = on
        if on {
            leftLeg.eulerAngles.x = -1.45
            rightLeg.eulerAngles.x = -1.45
            leftArm.eulerAngles.x = -0.9
            rightArm.eulerAngles.x = -0.9
            body.position.y = -0.47
        } else {
            body.position.y = 0
        }
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
