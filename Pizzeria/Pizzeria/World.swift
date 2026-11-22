import SceneKit
import UIKit

/// Fixed spots in the world (metres). +x along the street, +z toward the road.
/// The shop occupies x −4.2…4.2, z −7.2…0; the sidewalk z 0…3.3; the road z 3.3…11.
enum Spot {
    static let walkZ: Float = 2.35
    static let leftEnd: Float = -27
    static let rightEnd: Float = 27
    static let doorX: Float = 2.8
    static let doorOut = SIMD3<Float>(2.8, 0, 1.1)
    static let doorIn = SIMD3<Float>(2.8, 0, -0.75)
    static let queue: [SIMD3<Float>] = [
        SIMD3(1.4, 0, -3.35), SIMD3(1.95, 0, -2.8), SIMD3(2.45, 0, -2.25), SIMD3(2.75, 0, -1.6),
        SIMD3(2.8, 0, -0.9), SIMD3(2.85, 0, -0.2), SIMD3(3.0, 0, 0.65), SIMD3(3.5, 0, 1.3),
    ]
    static let pickup = SIMD3<Float>(-0.4, 0, -3.35)
    static let waiting: [SIMD3<Float>] = [
        SIMD3(-3.5, 0, -3.05), SIMD3(-2.9, 0, -3.1), SIMD3(-2.3, 0, -3.05), SIMD3(-1.7, 0, -3.1),
        SIMD3(-3.5, 0, -2.5), SIMD3(-2.7, 0, -2.5), SIMD3(-1.1, 0, -3.0), SIMD3(-1.9, 0, -2.5),
    ]
    static let cashier = SIMD3<Float>(1.4, 0, -4.65)
    static let cooks: [SIMD3<Float>] = [SIMD3(-0.6, 0, -5.05), SIMD3(0.6, 0, -5.05), SIMD3(1.8, 0, -5.05)]
    static let cleanerRoute: [SIMD3<Float>] = [
        SIMD3(-3.3, 0, -2.6), SIMD3(-0.9, 0, -2.4), SIMD3(-0.9, 0, -0.35), SIMD3(-3.5, 0, -0.35), SIMD3(-2.4, 0, -1.25),
    ]
    static let promoter = SIMD3<Float>(4.5, 0, 1.7)
}

struct Seat {
    let position: SIMD3<Float>
    let facing: SIMD3<Float>   // point to look at (table centre)
}

final class World {
    static let cardboard: UIImage = Tex.cardboard()

    let scene = SCNScene()
    let view: SCNView
    let cameraNode = SCNNode()
    private(set) var seats: [Seat] = []

    private let sun = SCNNode()
    private let ambient = SCNNode()
    private var interiorLights: [SCNNode] = []
    private var bulbs: [SCNMaterial] = []
    private let streetLight = SCNNode()
    private var streetBulbs: [SCNMaterial] = []
    private let ovenRoot = SCNNode()
    private var ovenGlow: SCNMaterial?
    private let ovenLight = SCNNode()
    private let tablesRoot = SCNNode()
    private let upgradesRoot = SCNNode()
    private let menuMaterial = SCNMaterial()
    private let signMaterial = SCNMaterial()
    private var cars: [Car] = []
    private var lastSkyKey = -1
    private var flicker: Float = 0
    private var currentOven = ""
    private var appliedKey = ""

    private struct Car {
        let node: SCNNode
        var active = false
        var dir: Float = 1
        var speed: Float = 9
    }

    // MARK: materials

    static func pbr(_ contents: Any, rough: CGFloat = 0.8, metal: CGFloat = 0, repeatX: Float = 1, repeatY: Float = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.roughness.contents = rough
        m.metalness.contents = metal
        if repeatX != 1 || repeatY != 1 {
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatX, repeatY, 1)
        }
        return m
    }

    private lazy var woodFloorImg = Tex.woodFloor()
    private lazy var brickImg = Tex.bricks()
    private lazy var plasterImg = Tex.plaster(r: 0.90, g: 0.86, b: 0.79)
    private lazy var steelImg = Tex.stainless()
    private lazy var darkWood = World.pbr(Tex.woodFloor(seed: 9, dark: true), rough: 0.55, repeatX: 0.5, repeatY: 0.5)
    private lazy var steel = World.pbr(steelImg, rough: 0.32, metal: 0.9)
    private lazy var tableTop = World.pbr(Tex.woodFloor(seed: 21), rough: 0.45, repeatX: 0.4, repeatY: 0.4)
    private lazy var blackMetal = World.pbr(UIColor(white: 0.07, alpha: 1), rough: 0.45, metal: 0.6)
    private lazy var white = World.pbr(UIColor(white: 0.92, alpha: 1), rough: 0.6)
    private lazy var glass: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.75, green: 0.85, blue: 0.9, alpha: 1)
        m.roughness.contents = 0.04
        m.metalness.contents = 0.0
        m.transparency = 0.13
        m.transparencyMode = .dualLayer
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }()

    // MARK: setup

    init() {
        view = SCNView(frame: .zero, options: nil)
        view.scene = scene
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.minimumVerticalAngle = 6
        view.defaultCameraController.maximumVerticalAngle = 78

        setupCamera()
        setupLights()
        buildStreet()
        buildShop()
        scene.rootNode.addChildNode(ovenRoot)
        scene.rootNode.addChildNode(tablesRoot)
        scene.rootNode.addChildNode(upgradesRoot)
        for _ in 0..<3 { cars.append(Car(node: makeCar())) }
        cars.forEach { $0.node.isHidden = true; scene.rootNode.addChildNode($0.node) }
    }

    private func setupCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 46
        cam.zNear = 0.1
        cam.zFar = 250
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = -0.15
        cam.bloomIntensity = 0.45
        cam.bloomThreshold = 0.9
        cam.bloomBlurRadius = 10
        cam.screenSpaceAmbientOcclusionIntensity = 1.1
        cam.screenSpaceAmbientOcclusionRadius = 0.35
        cam.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        cam.screenSpaceAmbientOcclusionDepthThreshold = 0.2
        cam.vignettingIntensity = 0.25
        cam.vignettingPower = 0.6
        cameraNode.camera = cam
        resetCamera()
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        view.defaultCameraController.target = SCNVector3(0.3, 0.8, -3.0)
    }

    func resetCamera() {
        cameraNode.position = SCNVector3(7.2, 8.6, 9.6)
        cameraNode.look(at: SCNVector3(0.2, 0.6, -2.9))
        view.pointOfView = cameraNode
        view.defaultCameraController.target = SCNVector3(0.3, 0.8, -3.0)
    }

    private func setupLights() {
        let s = SCNLight()
        s.type = .directional
        s.castsShadow = true
        s.shadowMode = .deferred
        s.shadowSampleCount = 16
        s.shadowRadius = 2.5
        s.shadowMapSize = CGSize(width: 2048, height: 2048)
        s.automaticallyAdjustsShadowProjection = true
        s.maximumShadowDistance = 45
        s.shadowColor = UIColor(white: 0, alpha: 0.55)
        s.intensity = 1300
        sun.light = s
        scene.rootNode.addChildNode(sun)

        let a = SCNLight()
        a.type = .ambient
        a.intensity = 200
        ambient.light = a
        scene.rootNode.addChildNode(ambient)

        scene.lightingEnvironment.intensity = 1.0
        updateSky(minute: 12 * 60)

        let sl = SCNLight()
        sl.type = .spot
        sl.spotInnerAngle = 30
        sl.spotOuterAngle = 95
        sl.intensity = 0
        sl.temperature = 3400
        sl.attenuationStartDistance = 2
        sl.attenuationEndDistance = 14
        streetLight.light = sl
        streetLight.position = SCNVector3(-5.6, 5.0, 2.7)
        streetLight.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(streetLight)

        let ol = SCNLight()
        ol.type = .omni
        ol.color = UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1)
        ol.intensity = 0
        ol.attenuationStartDistance = 0.2
        ol.attenuationEndDistance = 3.2
        ovenLight.light = ol
        scene.rootNode.addChildNode(ovenLight)
    }

    // MARK: helpers

    @discardableResult
    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ mat: SCNMaterial, _ x: Float, _ y: Float, _ z: Float,
                     chamfer: CGFloat = 0, parent: SCNNode? = nil) -> SCNNode {
        let n = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: chamfer))
        n.geometry?.firstMaterial = mat
        n.position = SCNVector3(x, y, z)
        (parent ?? scene.rootNode).addChildNode(n)
        return n
    }

    @discardableResult
    private func cylinder(_ r: CGFloat, _ h: CGFloat, _ mat: SCNMaterial, _ x: Float, _ y: Float, _ z: Float, parent: SCNNode? = nil) -> SCNNode {
        let n = SCNNode(geometry: SCNCylinder(radius: r, height: h))
        n.geometry?.firstMaterial = mat
        n.position = SCNVector3(x, y, z)
        (parent ?? scene.rootNode).addChildNode(n)
        return n
    }

    // MARK: street

    private func buildStreet() {
        let paving = World.pbr(Tex.paving(), rough: 0.85, repeatX: 30, repeatY: 1.6)
        let sidewalk = box(60, 0.14, 3.3, paving, 0, -0.07, 1.65)
        sidewalk.castsShadow = false
        let curb = World.pbr(UIColor(white: 0.62, alpha: 1), rough: 0.8)
        box(60, 0.16, 0.18, curb, 0, -0.06, 3.33)
        let asphalt = World.pbr(Tex.asphalt(), rough: 0.93, repeatX: 12, repeatY: 1.5)
        let road = box(60, 0.1, 7.6, asphalt, 0, -0.17, 7.15)
        road.castsShadow = false
        let paint = World.pbr(UIColor(white: 0.9, alpha: 1), rough: 0.7)
        var x: Float = -29
        while x < 30 {
            box(2.4, 0.01, 0.13, paint, x, -0.115, 7.15)
            x += 5
        }
        // Zebra crossing near the shop.
        for i in 0..<8 {
            box(0.5, 0.01, 6.4, paint, 6.2 + Float(i) * 0.9, -0.115, 7.15)
        }
        let farSidewalk = box(60, 0.14, 3.2, paving, 0, -0.07, 12.55)
        farSidewalk.castsShadow = false

        // Neighbouring buildings (two storeys), left and right of the shop.
        let leftFacade = World.pbr(Tex.facade(r: 0.82, g: 0.74, b: 0.62, floors: 2, seed: 1), rough: 0.9)
        let rightFacade = World.pbr(Tex.facade(r: 0.70, g: 0.73, b: 0.70, floors: 2, seed: 2), rough: 0.9)
        let side = World.pbr(Tex.plaster(r: 0.78, g: 0.74, b: 0.68, seed: 8), rough: 0.9)
        let roof = World.pbr(UIColor(white: 0.32, alpha: 1), rough: 0.9)
        for (facade, cx) in [(leftFacade, Float(-10.35)), (rightFacade, Float(10.35))] {
            let b = SCNNode(geometry: SCNBox(width: 12, height: 7.2, length: 10, chamferRadius: 0))
            b.geometry?.materials = [facade, side, side, side, roof, side]
            b.position = SCNVector3(cx, 3.6, -5.0)
            scene.rootNode.addChildNode(b)
        }
        // Across the road.
        let farFacade = World.pbr(Tex.facade(r: 0.86, g: 0.80, b: 0.70, floors: 3, seed: 3), rough: 0.9, repeatX: 3, repeatY: 1)
        let far = SCNNode(geometry: SCNBox(width: 60, height: 10, length: 8, chamferRadius: 0))
        far.geometry?.materials = [side, side, farFacade, side, roof, side]
        far.position = SCNVector3(0, 5, 18.2)
        scene.rootNode.addChildNode(far)

        // Street lamps.
        let bulbMat = World.pbr(UIColor(white: 0.9, alpha: 1), rough: 0.3)
        bulbMat.emission.contents = UIColor.black
        streetBulbs.append(bulbMat)
        for lx in [Float(-5.6), Float(13)] {
            cylinder(0.07, 5.2, blackMetal, lx, 2.6, 3.0)
            box(0.08, 0.08, 0.6, blackMetal, lx, 5.15, 2.75)
            let head = box(0.42, 0.12, 0.26, blackMetal, lx, 5.05, 2.55, chamfer: 0.04)
            let bulb = SCNNode(geometry: SCNBox(width: 0.34, height: 0.02, length: 0.2, chamferRadius: 0.01))
            bulb.geometry?.firstMaterial = bulbMat
            bulb.position = SCNVector3(0, -0.065, 0)
            head.addChildNode(bulb)
        }

        // Trees.
        let bark = World.pbr(UIColor(red: 0.28, green: 0.22, blue: 0.17, alpha: 1), rough: 0.95)
        let leaves = [
            World.pbr(UIColor(red: 0.22, green: 0.35, blue: 0.15, alpha: 1), rough: 0.85),
            World.pbr(UIColor(red: 0.28, green: 0.40, blue: 0.17, alpha: 1), rough: 0.85),
        ]
        var rng = SeededRandom(seed: 42)
        for tx in [Float(-11.5), Float(-17.5), Float(11.0), Float(18.5)] {
            cylinder(0.13, 3.0, bark, tx, 1.5, 2.95)
            for i in 0..<6 {
                let s = SCNNode(geometry: SCNSphere(radius: CGFloat(rng.range(0.8, 1.2))))
                s.geometry?.firstMaterial = leaves[i % 2]
                s.position = SCNVector3(tx + Float(rng.range(-0.8, 0.8)), Float(rng.range(3.3, 4.3)), 2.95 + Float(rng.range(-0.7, 0.7)))
                scene.rootNode.addChildNode(s)
            }
        }

        // Parked cars along the far curb.
        for (px, pz, dir) in [(Float(-15), Float(10.0), Float(1)), (Float(16), Float(10.0), Float(-1))] {
            let car = makeCar()
            car.position = SCNVector3(px, 0, pz)
            car.eulerAngles.y = dir > 0 ? .pi / 2 : -.pi / 2
            scene.rootNode.addChildNode(car)
        }
    }

    private func makeCar() -> SCNNode {
        let root = SCNNode()
        let colors: [UIColor] = [UIColor(white: 0.85, alpha: 1), UIColor(white: 0.12, alpha: 1), UIColor(white: 0.55, alpha: 1),
                                 UIColor(red: 0.45, green: 0.08, blue: 0.08, alpha: 1), UIColor(red: 0.12, green: 0.20, blue: 0.34, alpha: 1)]
        let paint = World.pbr(colors.randomElement()!, rough: 0.25, metal: 0.6)
        let tint = World.pbr(UIColor(white: 0.06, alpha: 1), rough: 0.08, metal: 0.2)
        let tyre = World.pbr(UIColor(white: 0.05, alpha: 1), rough: 0.9)
        // Car points along +z in local space; length 4.3 m.
        box(1.78, 0.62, 4.3, paint, 0, 0.62, 0, chamfer: 0.22, parent: root)
        box(1.56, 0.55, 2.2, tint, 0, 1.15, -0.25, chamfer: 0.25, parent: root)
        for (wx, wz) in [(Float(-0.82), Float(1.35)), (Float(0.82), Float(1.35)), (Float(-0.82), Float(-1.35)), (Float(0.82), Float(-1.35))] {
            let w = SCNNode(geometry: SCNCylinder(radius: 0.33, height: 0.22))
            w.geometry?.firstMaterial = tyre
            w.eulerAngles.z = .pi / 2
            w.position = SCNVector3(wx, 0.33, wz)
            root.addChildNode(w)
        }
        let lamp = World.pbr(UIColor(white: 1, alpha: 1), rough: 0.2)
        lamp.emission.contents = UIColor(white: 0.9, alpha: 1)
        box(0.3, 0.1, 0.04, lamp, -0.6, 0.72, 2.16, parent: root)
        box(0.3, 0.1, 0.04, lamp, 0.6, 0.72, 2.16, parent: root)
        let rear = World.pbr(UIColor(red: 0.6, green: 0.02, blue: 0.02, alpha: 1), rough: 0.3)
        rear.emission.contents = UIColor(red: 0.5, green: 0, blue: 0, alpha: 1)
        box(0.3, 0.1, 0.04, rear, -0.6, 0.75, -2.16, parent: root)
        box(0.3, 0.1, 0.04, rear, 0.6, 0.75, -2.16, parent: root)
        return root
    }

    // MARK: shop shell

    private func buildShop() {
        let floorDining = World.pbr(woodFloorImg, rough: 0.55, repeatX: 2.2, repeatY: 1)
        box(8.4, 0.04, 3.65, floorDining, 0, -0.02, -1.825).castsShadow = false
        let kitchenTiles = World.pbr(Tex.tiles(r: 0.86, g: 0.86, b: 0.84, tile: 48), rough: 0.35, repeatX: 3, repeatY: 1.4)
        box(8.4, 0.04, 3.55, kitchenTiles, 0, -0.02, -5.425).castsShadow = false

        let brick = World.pbr(brickImg, rough: 0.9, repeatX: 3, repeatY: 1.2)
        let plaster = World.pbr(plasterImg, rough: 0.92, repeatX: 2, repeatY: 1)
        box(8.7, 3.0, 0.15, brick, 0, 1.5, -7.275)
        box(0.15, 3.0, 7.3, plaster, -4.275, 1.5, -3.6)
        box(0.15, 3.0, 7.3, plaster, 4.275, 1.5, -3.6)

        // Front facade: brick plinth, big windows, door, fascia for the sign.
        box(5.85, 0.5, 0.2, brick, -1.275, 0.25, 0)
        box(0.65, 0.5, 0.2, brick, 3.875, 0.25, 0)
        for (cx, w) in [(Float(-1.275), CGFloat(5.85)), (Float(3.875), CGFloat(0.65))] {
            let g = SCNNode(geometry: SCNBox(width: w, height: 2.45, length: 0.02, chamferRadius: 0))
            g.geometry?.firstMaterial = glass
            g.position = SCNVector3(cx, 1.725, 0)
            g.castsShadow = false
            scene.rootNode.addChildNode(g)
        }
        for mx in [Float(-4.2), Float(-2.25), Float(-0.3), Float(1.65), Float(2.22), Float(3.38), Float(4.2)] {
            box(0.07, 2.5, 0.12, blackMetal, mx, 1.75, 0)
        }
        box(8.5, 0.07, 0.14, blackMetal, 0, 0.52, 0)
        box(8.5, 0.07, 0.14, blackMetal, 0, 2.97, 0)
        let fascia = World.pbr(UIColor(red: 0.16, green: 0.17, blue: 0.18, alpha: 1), rough: 0.6)
        box(8.7, 0.62, 0.22, fascia, 0, 3.31, 0)

        // Sign panel on the fascia.
        let signPlane = SCNNode(geometry: SCNPlane(width: 3.6, height: 0.5))
        signMaterial.lightingModel = .physicallyBased
        signMaterial.roughness.contents = 0.5
        signPlane.geometry?.firstMaterial = signMaterial
        signPlane.position = SCNVector3(-0.6, 3.31, 0.115)
        scene.rootNode.addChildNode(signPlane)

        // Counter.
        let counterFront = darkWood
        box(3.0, 1.0, 0.7, counterFront, 0.6, 0.5, -4.0)
        let top = World.pbr(UIColor(white: 0.18, alpha: 1), rough: 0.25, metal: 0.1)
        box(3.1, 0.05, 0.78, top, 0.6, 1.025, -4.0)
        // Pizza display case on the counter.
        let caseGlass = SCNNode(geometry: SCNBox(width: 0.9, height: 0.35, length: 0.5, chamferRadius: 0.02))
        caseGlass.geometry?.firstMaterial = glass
        caseGlass.position = SCNVector3(-0.4, 1.23, -4.0)
        scene.rootNode.addChildNode(caseGlass)

        // Prep table, fridge, shelves.
        box(3.6, 0.9, 0.7, steel, 0.6, 0.45, -5.75)
        box(0.75, 2.0, 0.7, steel, 3.55, 1.0, -6.75)
        let shelf = darkWood
        box(2.2, 0.04, 0.3, shelf, 1.0, 1.75, -7.05)
        box(2.2, 0.04, 0.3, shelf, 1.0, 2.15, -7.05)
        let jar = World.pbr(UIColor(red: 0.85, green: 0.30, blue: 0.15, alpha: 1), rough: 0.3)
        for i in 0..<6 {
            cylinder(0.07, 0.22, jar, 0.1 + Float(i) * 0.33, 1.88, -7.05)
        }

        // Menu board on the back wall.
        let menu = SCNNode(geometry: SCNPlane(width: 2.4, height: 1.5))
        menuMaterial.lightingModel = .physicallyBased
        menuMaterial.roughness.contents = 0.85
        menu.geometry?.firstMaterial = menuMaterial
        menu.position = SCNVector3(-1.9, 2.0, -7.19)
        scene.rootNode.addChildNode(menu)
        box(2.5, 1.6, 0.03, darkWood, -1.9, 2.0, -7.21)

        // Pendant lamps.
        let shade = World.pbr(UIColor(white: 0.08, alpha: 1), rough: 0.4, metal: 0.7)
        for p in [SIMD3<Float>(-2.6, 2.45, -1.3), SIMD3<Float>(-0.6, 2.45, -1.3), SIMD3<Float>(0.6, 2.45, -4.0)] {
            cylinder(0.006, 0.55, blackMetal, p.x, p.y + 0.27, p.z)
            let cone = SCNNode(geometry: SCNCone(topRadius: 0.05, bottomRadius: 0.2, height: 0.2))
            cone.geometry?.firstMaterial = shade
            cone.position = SCNVector3(p.x, p.y, p.z)
            scene.rootNode.addChildNode(cone)
            let bulbMat = World.pbr(UIColor(white: 1, alpha: 1), rough: 0.3)
            bulbs.append(bulbMat)
            let bulb = SCNNode(geometry: SCNSphere(radius: 0.055))
            bulb.geometry?.firstMaterial = bulbMat
            bulb.position = SCNVector3(p.x, p.y - 0.1, p.z)
            scene.rootNode.addChildNode(bulb)
            let l = SCNLight()
            l.type = .omni
            l.temperature = 2800
            l.intensity = 0
            l.attenuationStartDistance = 0.5
            l.attenuationEndDistance = 6.5
            let ln = SCNNode()
            ln.light = l
            ln.position = SCNVector3(p.x, p.y - 0.25, p.z)
            scene.rootNode.addChildNode(ln)
            interiorLights.append(ln)
        }
    }

    // MARK: upgrades

    func apply(_ s: GameState) {
        if s.oven != currentOven { buildOven(s.oven) }
        let key = [String(s.tables), s.building.sorted().joined(), s.equipment.sorted().joined(), s.adsOn.sorted().joined(),
                   String(s.flyersDay)].joined(separator: "|")
        if key != appliedKey {
            appliedKey = key
            buildTables(s)
            buildUpgrades(s)
        }
        let lit = s.building.contains("sign")
        let signImage = Tex.sign(lit ? "ПИЦЦЕРИЯ" : "ПИЦЦА", lit: lit)
        signMaterial.diffuse.contents = signImage
        signMaterial.emission.contents = lit ? signImage : UIColor.black
        signMaterial.emission.intensity = lit ? 1.4 : 0
        updateMenu(s)
    }

    func updateMenu(_ s: GameState) {
        let lines = Catalog.pizzas.filter { s.unlockedPizzas.contains($0.id) }.map { ($0.name, "\(Int(s.price($0.id).rounded()))") }
        menuMaterial.diffuse.contents = Tex.menuBoard(lines: lines)
    }

    private func buildOven(_ id: String) {
        currentOven = id
        ovenRoot.childNodes.forEach { $0.removeFromParentNode() }
        let glow = World.pbr(UIColor(red: 0.12, green: 0.05, blue: 0.02, alpha: 1), rough: 0.6)
        glow.emission.contents = UIColor(red: 1, green: 0.45, blue: 0.12, alpha: 1)
        glow.emission.intensity = 0
        ovenGlow = glow
        switch id {
        case "wood":
            let stone = World.pbr(brickImg, rough: 0.9, repeatX: 2, repeatY: 1)
            box(1.9, 1.0, 1.9, stone, -2.95, 0.5, -6.1, parent: ovenRoot)
            let domeMat = World.pbr(UIColor(red: 0.62, green: 0.30, blue: 0.20, alpha: 1), rough: 0.8)
            let dome = SCNNode(geometry: SCNSphere(radius: 0.88))
            dome.geometry?.firstMaterial = domeMat
            dome.position = SCNVector3(-2.95, 1.0, -6.1)
            dome.scale = SCNVector3(1, 0.62, 1)
            ovenRoot.addChildNode(dome)
            let mouth = SCNNode(geometry: SCNBox(width: 0.55, height: 0.32, length: 0.1, chamferRadius: 0.12))
            mouth.geometry?.firstMaterial = glow
            mouth.position = SCNVector3(-2.95, 1.18, -5.2)
            ovenRoot.addChildNode(mouth)
            cylinder(0.12, 1.4, blackMetal, -2.95, 2.3, -6.3, parent: ovenRoot)
            ovenLight.position = SCNVector3(-2.95, 1.25, -5.0)
        case "deck":
            box(1.4, 0.9, 1.0, steel, -2.95, 0.45, -6.5, parent: ovenRoot)
            for (i, y) in [Float(1.15), Float(1.65)].enumerated() {
                box(1.35, 0.46, 1.0, steel, -2.95, y, -6.5, parent: ovenRoot)
                box(0.9, 0.14, 0.04, glow, -2.95, y - 0.02, -5.98, parent: ovenRoot)
                box(0.9, 0.04, 0.06, blackMetal, -2.95, y + 0.12, -5.96, parent: ovenRoot)
                _ = i
            }
            ovenLight.position = SCNVector3(-2.95, 1.3, -5.6)
        default:
            box(1.0, 0.9, 0.8, steel, -2.95, 0.45, -6.55, parent: ovenRoot)
            box(0.9, 0.7, 0.75, steel, -2.95, 1.25, -6.55, parent: ovenRoot)
            box(0.62, 0.42, 0.03, glow, -3.0, 1.25, -6.16, parent: ovenRoot)
            box(0.1, 0.5, 0.05, blackMetal, -2.55, 1.25, -6.15, parent: ovenRoot)
            ovenLight.position = SCNVector3(-2.95, 1.2, -5.8)
        }
        ovenRoot.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    private func buildTables(_ s: GameState) {
        tablesRoot.childNodes.forEach { $0.removeFromParentNode() }
        seats.removeAll()
        let inside: [SIMD3<Float>] = [
            SIMD3(-3.15, 0, -1.75), SIMD3(-1.7, 0, -1.75), SIMD3(-3.15, 0, -0.65),
            SIMD3(-1.7, 0, -0.65), SIMD3(-0.25, 0, -1.75), SIMD3(-0.25, 0, -0.65),
        ]
        for i in 0..<min(s.tables, inside.count) { addTable(at: inside[i], umbrella: false) }
        if s.building.contains("terrace") {
            for p in [SIMD3<Float>(-3.3, 0, 0.95), SIMD3<Float>(-1.85, 0, 0.95), SIMD3<Float>(-0.4, 0, 0.95)] {
                addTable(at: p, umbrella: true)
            }
            let rail = blackMetal
            box(4.3, 0.05, 0.05, rail, -2.05, 0.9, 1.55, parent: tablesRoot)
            for rx in stride(from: Float(-4.1), through: Float(0.1), by: 0.7) {
                box(0.04, 0.9, 0.04, rail, rx, 0.45, 1.55, parent: tablesRoot)
            }
        }
        tablesRoot.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    private func addTable(at p: SIMD3<Float>, umbrella: Bool) {
        cylinder(0.38, 0.04, tableTop, p.x, 0.74, p.z, parent: tablesRoot)
        cylinder(0.035, 0.72, blackMetal, p.x, 0.37, p.z, parent: tablesRoot)
        cylinder(0.24, 0.03, blackMetal, p.x, 0.015, p.z, parent: tablesRoot)
        for side in [Float(-1), Float(1)] {
            let cx = p.x + side * 0.6
            let chair = SCNNode()
            chair.position = SCNVector3(cx, 0, p.z)
            tablesRoot.addChildNode(chair)
            box(0.42, 0.04, 0.42, darkWood, 0, 0.45, 0, parent: chair)
            for (lx, lz) in [(Float(-0.18), Float(-0.18)), (Float(0.18), Float(-0.18)), (Float(-0.18), Float(0.18)), (Float(0.18), Float(0.18))] {
                box(0.03, 0.45, 0.03, blackMetal, lx, 0.225, lz, parent: chair)
            }
            box(0.03, 0.45, 0.42, darkWood, side * 0.2, 0.7, 0, parent: chair)
            seats.append(Seat(position: SIMD3(cx, 0, p.z), facing: SIMD3(p.x, 0, p.z)))
        }
        if umbrella {
            cylinder(0.025, 2.3, white, p.x, 1.15, p.z, parent: tablesRoot)
            let canopy = SCNNode(geometry: SCNCone(topRadius: 0.02, bottomRadius: 1.1, height: 0.45))
            canopy.geometry?.firstMaterial = World.pbr(UIColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 1), rough: 0.9)
            canopy.position = SCNVector3(p.x, 2.3, p.z)
            tablesRoot.addChildNode(canopy)
        }
    }

    private func buildUpgrades(_ s: GameState) {
        upgradesRoot.childNodes.forEach { $0.removeFromParentNode() }
        let has = { (id: String) in s.equipment.contains(id) || s.building.contains(id) }

        if has("prepFridge") {
            let sneeze = SCNNode(geometry: SCNBox(width: 3.4, height: 0.32, length: 0.02, chamferRadius: 0))
            sneeze.geometry?.firstMaterial = glass
            sneeze.position = SCNVector3(0.6, 1.25, -5.5)
            upgradesRoot.addChildNode(sneeze)
            let colors: [UIColor] = [.systemRed, .systemYellow, .systemGreen, UIColor(red: 0.95, green: 0.9, blue: 0.75, alpha: 1), .brown, .systemOrange]
            for (i, c) in colors.enumerated() {
                box(0.42, 0.1, 0.28, World.pbr(c.withAlphaComponent(1), rough: 0.6), -0.7 + Float(i) * 0.5, 0.95, -5.95, parent: upgradesRoot)
            }
        }
        if has("mixer") {
            box(0.5, 0.75, 0.6, white, 2.75, 0.375, -6.8, chamfer: 0.06, parent: upgradesRoot)
            cylinder(0.2, 0.3, steel, 2.75, 0.9, -6.75, parent: upgradesRoot)
        }
        if has("coffee") {
            box(0.55, 0.45, 0.45, steel, 1.95, 1.27, -4.05, chamfer: 0.03, parent: upgradesRoot)
            box(0.5, 0.12, 0.4, blackMetal, 1.95, 1.56, -4.05, parent: upgradesRoot)
        }
        if has("terminal") {
            box(0.09, 0.03, 0.17, blackMetal, 1.25, 1.07, -3.75, chamfer: 0.01, parent: upgradesRoot)
            let screen = World.pbr(UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), rough: 0.1)
            screen.emission.contents = UIColor(red: 0.2, green: 0.45, blue: 0.7, alpha: 1)
            box(0.07, 0.005, 0.07, screen, 1.25, 1.087, -3.72, parent: upgradesRoot)
        }
        if has("generator") {
            let genMat = World.pbr(UIColor(red: 0.85, green: 0.45, blue: 0.08, alpha: 1), rough: 0.5, metal: 0.3)
            box(0.95, 0.7, 0.6, genMat, 3.95, 0.35, 0.55, chamfer: 0.04, parent: upgradesRoot)
            box(0.85, 0.12, 0.5, blackMetal, 3.95, 0.76, 0.55, parent: upgradesRoot)
        }
        if has("renovation") {
            let panel = darkWood
            box(0.03, 1.1, 7.0, panel, -4.19, 0.55, -3.6, parent: upgradesRoot)
            box(0.03, 1.1, 3.4, panel, 4.19, 0.55, -1.9, parent: upgradesRoot)
            let plant = World.pbr(UIColor(red: 0.2, green: 0.36, blue: 0.16, alpha: 1), rough: 0.8)
            let pot = World.pbr(UIColor(red: 0.55, green: 0.32, blue: 0.22, alpha: 1), rough: 0.8)
            for px in [Float(-3.85), Float(1.0)] {
                cylinder(0.18, 0.4, pot, px, 0.2, -0.35, parent: upgradesRoot)
                let leaves = SCNNode(geometry: SCNSphere(radius: 0.32))
                leaves.geometry?.firstMaterial = plant
                leaves.position = SCNVector3(px, 0.7, -0.35)
                leaves.scale = SCNVector3(1, 1.3, 1)
                upgradesRoot.addChildNode(leaves)
            }
            let frame = World.pbr(UIColor(white: 0.1, alpha: 1), rough: 0.5)
            for (i, z) in [Float(-1.0), Float(-2.6)].enumerated() {
                box(0.03, 0.7, 0.95, frame, -4.18, 1.75, z, parent: upgradesRoot)
                let pic = World.pbr(Tex.pizzaTop(), rough: 0.6)
                let pn = SCNNode(geometry: SCNPlane(width: 0.85, height: 0.6))
                pn.geometry?.firstMaterial = pic
                pn.eulerAngles.y = .pi / 2
                pn.position = SCNVector3(-4.16, 1.75, z)
                upgradesRoot.addChildNode(pn)
                _ = i
            }
        }
        if has("windows") {
            let decal = SCNMaterial()
            decal.lightingModel = .constant
            decal.diffuse.contents = Tex.windowDecal()
            decal.blendMode = .add
            decal.isDoubleSided = true
            decal.writesToDepthBuffer = false
            let d = SCNNode(geometry: SCNPlane(width: 2.6, height: 1.3))
            d.geometry?.firstMaterial = decal
            d.position = SCNVector3(-1.3, 1.5, 0.02)
            d.castsShadow = false
            upgradesRoot.addChildNode(d)
        }
        if s.adsOn.contains("billboard") {
            box(0.15, 3.4, 0.15, blackMetal, -9.0, 1.7, 3.0, parent: upgradesRoot)
            box(0.15, 3.4, 0.15, blackMetal, -6.4, 1.7, 3.0, parent: upgradesRoot)
            let poster = World.pbr(Tex.billboard(), rough: 0.6)
            poster.emission.contents = Tex.billboard()
            poster.emission.intensity = 0.25
            let pn = SCNNode(geometry: SCNPlane(width: 4.0, height: 2.0))
            pn.geometry?.firstMaterial = poster
            pn.position = SCNVector3(-7.7, 4.3, 3.1)
            pn.eulerAngles.y = 0.35
            upgradesRoot.addChildNode(pn)
        }
        upgradesRoot.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    // MARK: people

    func add(_ person: PersonNode, at p: SIMD3<Float>) {
        person.node.position = SCNVector3(p.x, p.y, p.z)
        scene.rootNode.addChildNode(person.node)
    }

    // MARK: per-frame

    struct Ambience {
        var minute: Double
        var interiorPowered: Bool
        var streetPowered: Bool
        var ovenBusy: Float      // 0…1
        var ovenWorking: Bool
    }

    func update(dt: Float, visualSpeed: Float, _ a: Ambience) {
        let hour = Float(a.minute / 60)
        let dayT = (hour - 5.5) / 15
        let sunHeight = sin(dayT * .pi)
        let elev = max(0.06, asin(max(-1, min(1, sunHeight))))
        let az = (dayT - 0.5) * 1.8
        sun.eulerAngles = SCNVector3(-elev, az, 0)
        let dayAmount = max(0, min(1, (sunHeight + 0.05) / 0.35))
        sun.light?.intensity = CGFloat(1500 * dayAmount)
        sun.light?.temperature = CGFloat(3600 + 2600 * max(0, min(1, sunHeight * 2.5)))
        ambient.light?.intensity = CGFloat(60 + 220 * dayAmount)
        scene.lightingEnvironment.intensity = CGFloat(0.12 + 0.95 * dayAmount)

        let skyKey = Int(a.minute / 10)
        if skyKey != lastSkyKey {
            lastSkyKey = skyKey
            updateSky(minute: a.minute)
        }

        let interior: CGFloat = a.interiorPowered ? CGFloat(420 - 220 * dayAmount) : 0
        for l in interiorLights { l.light?.intensity = interior }
        for b in bulbs {
            b.emission.contents = a.interiorPowered ? UIColor(red: 1, green: 0.82, blue: 0.55, alpha: 1) : UIColor.black
        }
        let streetOn = a.streetPowered && dayAmount < 0.35
        streetLight.light?.intensity = streetOn ? 1100 : 0
        for b in streetBulbs { b.emission.contents = streetOn ? UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1) : UIColor.black }

        flicker += dt * 9
        let base: Float = a.ovenWorking ? (currentOven == "wood" ? 1.0 : 0.35 + 0.6 * a.ovenBusy) : (currentOven == "wood" ? 0.25 : 0)
        let f = currentOven == "wood" ? (0.85 + 0.15 * sin(flicker) * sin(flicker * 0.37 + 1)) : 1
        ovenGlow?.emission.intensity = CGFloat(base * f * 2.2)
        ovenLight.light?.intensity = CGFloat(base * f * (currentOven == "wood" ? 420 : 160))

        updateCars(dt: dt * visualSpeed)
    }

    private func updateSky(minute: Double) {
        let hour = Float(minute / 60)
        let sunHeight = sin((hour - 5.5) / 15 * .pi)
        let night = max(0, min(1, (-sunHeight + 0.08) / 0.25))
        let img = Tex.sky(sunHeight: sunHeight, night: night)
        scene.background.contents = img
        scene.lightingEnvironment.contents = img
    }

    private func updateCars(dt: Float) {
        for i in cars.indices {
            if !cars[i].active {
                if Float.random(in: 0...1) < dt * 0.12 {
                    cars[i].active = true
                    cars[i].dir = Bool.random() ? 1 : -1
                    cars[i].speed = Float.random(in: 8...12)
                    let z: Float = cars[i].dir > 0 ? 5.3 : 8.9
                    cars[i].node.position = SCNVector3(-cars[i].dir * 34, 0, z)
                    cars[i].node.eulerAngles.y = cars[i].dir > 0 ? .pi / 2 : -.pi / 2
                    cars[i].node.isHidden = false
                }
                continue
            }
            cars[i].node.position.x += cars[i].dir * cars[i].speed * dt
            if abs(cars[i].node.position.x) > 35 {
                cars[i].active = false
                cars[i].node.isHidden = true
            }
        }
    }
}
