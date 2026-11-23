import SceneKit
import UIKit
import simd

/// Fixed spots in the world (metres). +x along the street, +z toward the road.
/// The shop occupies x −4.2…4.2, z −7.2…0; the sidewalk z 0…3.3; the road z 3.3…11.
enum Spot {
    static let walkZ: Float = 2.2
    static let leftEnd: Float = -27
    static let rightEnd: Float = 27
    static let doorX: Float = 2.8
    static let doorOut = SIMD3<Float>(2.8, 0, 1.0)
    static let doorIn = SIMD3<Float>(2.8, 0, -0.75)
    static let queue: [SIMD3<Float>] = [
        SIMD3(1.4, 0, -3.3), SIMD3(1.9, 0, -2.75), SIMD3(2.4, 0, -2.2), SIMD3(2.75, 0, -1.6),
        SIMD3(2.8, 0, -0.95), SIMD3(2.85, 0, -0.3), SIMD3(3.1, 0, 0.6), SIMD3(3.6, 0, 1.25),
    ]
    static let pickup = SIMD3<Float>(-0.45, 0, -3.3)
    static let waiting: [SIMD3<Float>] = [
        SIMD3(-3.6, 0, -3.0), SIMD3(-3.0, 0, -3.05), SIMD3(-2.4, 0, -3.0), SIMD3(-1.8, 0, -3.05),
        SIMD3(-3.3, 0, -2.5), SIMD3(-2.7, 0, -2.5), SIMD3(-1.2, 0, -3.0), SIMD3(-2.1, 0, -2.5),
    ]
    static let cashier = SIMD3<Float>(1.4, 0, -4.7)
    static let cooks: [SIMD3<Float>] = [SIMD3(-0.6, 0, -5.05), SIMD3(0.6, 0, -5.05), SIMD3(1.8, 0, -5.05)]
    static let cleanerRoute: [SIMD3<Float>] = [
        SIMD3(-3.3, 0, -2.6), SIMD3(-0.9, 0, -2.4), SIMD3(-0.9, 0, -0.35), SIMD3(-3.5, 0, -0.35), SIMD3(-2.4, 0, -1.25),
    ]
    static let promoter = SIMD3<Float>(4.9, 0, 1.6)
}

struct Seat {
    let position: SIMD3<Float>
    let facing: SIMD3<Float>   // point to look at (table centre)
}

final class World: NSObject {
    static let cardboard: UIImage = Tex.cardboard()

    let scene = SCNScene()
    let view: SCNView
    let cameraNode = SCNNode()
    private(set) var seats: [Seat] = []
    var onTap: ((String) -> Void)?

    // Lighting.
    private let sun = SCNNode()
    private let ambient = SCNNode()
    private var interiorLights: [SCNNode] = []
    private var interiorGlow: [SCNMaterial] = []
    private var streetGlass: SCNMaterial?
    private let tubeMat = World.pbr(UIColor(white: 0.95, alpha: 1), rough: 0.3)
    private var interiorBuilt = false
    private var streetLights: [SCNNode] = []
    private var streetBulb: SCNMaterial?
    private var litWindows: SCNMaterial!
    private var neighbourShopLight: SCNMaterial!
    private let ovenRoot = SCNNode()
    private var ovenGlow: SCNMaterial?
    private let ovenLight = SCNNode()
    private var fire: SCNParticleSystem?
    private var ovenSlots: [SIMD3<Float>] = []
    private let tablesRoot = SCNNode()
    private let upgradesRoot = SCNNode()
    private let hallRoot = SCNNode()
    private let menuMaterial = SCNMaterial()
    private let signMaterial = SCNMaterial()
    private var signLamps: [SCNMaterial] = []
    private var cars: [Car] = []
    private var lastSkyKey = -1
    private var envIsNight: Bool?
    private var flicker: Float = 0
    private var currentOven = ""
    private var appliedKey = ""
    private var renovated = false

    // Live props.
    private var prepPizzas: [SCNNode] = []
    private var ovenPizzas: [SCNNode] = []
    private var readyBoxes: [SCNNode] = []
    private var plates: [Int: SCNNode] = [:]
    private let doorPanel = SCNNode()
    private var doorOpen: Float = 0
    private var people: [WeakPerson] = []

    private struct WeakPerson { weak var node: SCNNode? }

    private struct Car {
        let node: SCNNode
        var active = false
        var dir: Float = 1
        var speed: Float = 9
    }

    // Camera rig.
    private var camYaw: Float = 0
    private var camPitch: Float = 0.9
    private var camDist: Float = 15.5
    private var camTarget = SIMD3<Float>(0.3, 0.2, -2.3)

    // MARK: materials

    static func pbr(_ contents: Any, rough: CGFloat = 0.8, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    private lazy var steel: SCNMaterial = {
        let m = World.pbr(Tex.stainless(), rough: 0.28, metal: 1)
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        return m
    }()
    private lazy var darkSteel = World.pbr(UIColor(white: 0.18, alpha: 1), rough: 0.35, metal: 0.9)
    private lazy var blackMetal = World.pbr(UIColor(white: 0.04, alpha: 1), rough: 0.42, metal: 0.7)
    private lazy var aluminium = World.pbr(UIColor(white: 0.12, alpha: 1), rough: 0.3, metal: 0.8)
    private lazy var white = World.pbr(UIColor(white: 0.92, alpha: 1), rough: 0.5)
    private lazy var rubber = World.pbr(UIColor(white: 0.03, alpha: 1), rough: 0.9)
    private lazy var glass: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.8, green: 0.88, blue: 0.9, alpha: 1)
        m.roughness.contents = 0.03
        m.metalness.contents = 0.0
        m.transparency = 0.08
        m.blendMode = .alpha
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }()

    // Tiling sizes of the surface sets (metres per texture).
    private func surf(_ id: String, tint: UIColor? = nil, rough: CGFloat? = nil, metal: CGFloat = 0) -> (SCNMaterial, Float) {
        let tiles: [String: Float] = [
            "floor_tiles_06": 3.0, "herringbone_parquet": 3.4, "terracotta_floor_tiles": 2.08, "long_white_tiles": 1.27,
            "painted_plaster_wall": 2.0, "red_brick_03": 1.0, "beige_wall_002": 3.0, "rectangular_facade_tiles": 2.0,
            "patterned_concrete_pavers": 1.8, "asphalt_02": 3.0, "granular_concrete": 2.4, "wood_table_001": 1.5,
            "oak_veneer_01": 1.83, "marble_01": 1.5, "large_red_bricks": 2.0, "yellow_plaster": 2.0,
            "painted_metal_shutter": 2.0, "dark_wood": 2.0,
        ]
        return (Assets.surface(id, tint: tint, roughness: rough, metal: metal), tiles[id] ?? 2)
    }

    // MARK: setup

    override init() {
        view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        super.init()
        view.scene = scene
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.allowsCameraControl = false
        view.isJitteringEnabled = false

        setupCamera()
        setupLights()
        buildGround()
        buildNeighbours()
        buildShopShell()
        buildKitchen()
        buildCounter()
        buildStreetFurniture()
        scene.rootNode.addChildNode(ovenRoot)
        scene.rootNode.addChildNode(tablesRoot)
        scene.rootNode.addChildNode(hallRoot)
        scene.rootNode.addChildNode(upgradesRoot)
        buildLiveProps()
        for i in 0..<4 { cars.append(Car(node: makeCar(seed: i))) }
        cars.forEach { $0.node.isHidden = true; scene.rootNode.addChildNode($0.node) }
        installGestures()
    }

    private func setupCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 38
        cam.zNear = 0.2
        cam.zFar = 220
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = -0.1
        cam.minimumExposure = -2
        cam.maximumExposure = 2
        cam.bloomIntensity = 0.55
        cam.bloomThreshold = 1.0
        cam.bloomBlurRadius = 12
        cam.screenSpaceAmbientOcclusionIntensity = 1.2
        cam.screenSpaceAmbientOcclusionRadius = 0.3
        cam.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        cam.screenSpaceAmbientOcclusionDepthThreshold = 0.15
        cam.vignettingIntensity = 0.35
        cam.vignettingPower = 0.8
        cam.colorFringeStrength = 0
        cam.saturation = 1.05
        cam.contrast = 0.06
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        applyCamera()
    }

    func resetCamera() {
        camYaw = 0
        camPitch = 0.9
        camDist = 15.5
        camTarget = SIMD3(0.3, 0.2, -2.3)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.45
        applyCamera()
        SCNTransaction.commit()
    }

    /// Positions the camera for screenshots / presets.
    func setCamera(yaw: Float, pitch: Float, distance: Float, target: SIMD3<Float>) {
        camYaw = yaw
        camPitch = pitch
        camDist = distance
        camTarget = target
        applyCamera()
    }

    private func applyCamera() {
        let dir = SIMD3<Float>(sin(camYaw) * cos(camPitch), sin(camPitch), cos(camYaw) * cos(camPitch))
        cameraNode.simdPosition = camTarget + dir * camDist
        cameraNode.simdLook(at: camTarget, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
    }

    private func setupLights() {
        let s = SCNLight()
        s.type = .directional
        s.castsShadow = true
        s.shadowMode = .deferred
        s.shadowSampleCount = 12
        s.shadowRadius = 2.0
        s.shadowMapSize = CGSize(width: 4096, height: 4096)
        s.automaticallyAdjustsShadowProjection = true
        s.maximumShadowDistance = 42
        s.shadowCascadeCount = 2
        s.shadowColor = UIColor(white: 0, alpha: 0.6)
        s.intensity = 1400
        sun.light = s
        scene.rootNode.addChildNode(sun)

        let a = SCNLight()
        a.type = .ambient
        a.intensity = 60
        ambient.light = a
        scene.rootNode.addChildNode(ambient)

        scene.lightingEnvironment.intensity = 1.0
        updateSky(minute: 12 * 60)

        let ol = SCNLight()
        ol.type = .omni
        ol.color = UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1)
        ol.intensity = 0
        ol.attenuationStartDistance = 0.1
        ol.attenuationEndDistance = 3.0
        ovenLight.light = ol
        scene.rootNode.addChildNode(ovenLight)
    }

    // MARK: building helpers

    @discardableResult
    private func slab(_ w: Float, _ h: Float, _ l: Float, _ m: (SCNMaterial, Float), _ x: Float, _ y: Float, _ z: Float,
                      parent: SCNNode? = nil, shadow: Bool = true) -> SCNNode {
        let n = SCNNode(geometry: Geo.box(w, h, l, tile: m.1))
        n.geometry?.firstMaterial = m.0
        n.position = SCNVector3(x, y, z)
        n.castsShadow = shadow
        (parent ?? scene.rootNode).addChildNode(n)
        return n
    }

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

    enum Anchor { case bottom, back, top }

    /// Places a converted model. `.bottom`: footprint centred, resting on y; `.back`: mounted on a wall
    /// (back face at the given z, facing +z before rotation); `.top`: hanging from y.
    @discardableResult
    private func put(_ id: String, part: String = "root", _ p: SIMD3<Float>, yaw: Float = 0, scale: Float = 1,
                     anchor: Anchor = .bottom, parent: SCNNode? = nil, tap: String? = nil) -> SCNNode {
        let holder = SCNNode()
        let m = Assets.model(id, part: part)
        let (lo, hi) = Assets.bounds(id, part: part)
        let c = (lo + hi) * 0.5
        switch anchor {
        case .bottom: m.simdPosition = SIMD3(-c.x, -lo.y, -c.z) * scale
        case .back: m.simdPosition = SIMD3(-c.x, -c.y, -lo.z) * scale
        case .top: m.simdPosition = SIMD3(-c.x, -hi.y, -c.z) * scale
        }
        m.simdScale = SIMD3(repeating: scale)
        holder.addChildNode(m)
        holder.simdPosition = p
        holder.eulerAngles.y = yaw
        if let tap { holder.name = "tap:" + tap }
        (parent ?? scene.rootNode).addChildNode(holder)
        return holder
    }

    // MARK: ground

    private func buildGround() {
        let pavers = surf("patterned_concrete_pavers")
        slab(70, 0.14, 3.3, pavers, 0, -0.07, 1.65, shadow: false)
        let curb = surf("granular_concrete", tint: UIColor(white: 0.85, alpha: 1))
        slab(70, 0.18, 0.2, curb, 0, -0.06, 3.35)
        let asphalt = surf("asphalt_02")
        slab(70, 0.1, 7.6, asphalt, 0, -0.18, 7.25, shadow: false)
        slab(70, 0.18, 0.2, curb, 0, -0.06, 11.15)
        slab(70, 0.14, 3.6, pavers, 0, -0.07, 13.05, shadow: false)
        // Courtyard behind the buildings.
        let yard = surf("granular_concrete", tint: UIColor(white: 0.62, alpha: 1))
        slab(70, 0.1, 30, yard, 0, -0.08, -22, shadow: false)

        // Road markings.
        let paint = World.pbr(UIColor(white: 0.86, alpha: 1), rough: 0.6)
        var x: Float = -34
        while x < 35 {
            box(3.0, 0.004, 0.12, paint, x, -0.128, 7.25)
            x += 6
        }
        for i in 0..<9 {
            box(0.5, 0.004, 6.6, paint, 7.4 + Float(i) * 0.95, -0.128, 7.25)
        }
        put("water_manhole_cover", SIMD3(-3.5, -0.14, 6.2))
        put("water_manhole_cover", SIMD3(12.5, -0.14, 8.4))

        // A low wall closing the far side of the street.
        let far = surf("yellow_plaster", tint: UIColor(red: 0.95, green: 0.9, blue: 0.82, alpha: 1))
        slab(70, 2.2, 0.3, far, 0, 1.1, 15.0)
    }

    // MARK: neighbouring buildings (modular facade kit)

    private func buildNeighbours() {
        let plaster = Assets.sharedMaterial("facade", named: "plaster")
        func tinted(_ c: UIColor) -> SCNMaterial? {
            guard let p = plaster?.copy() as? SCNMaterial else { return nil }
            p.multiply.contents = c
            return p
        }
        litWindows = SCNMaterial()
        litWindows.lightingModel = .physicallyBased
        litWindows.diffuse.contents = UIColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 1)
        litWindows.roughness.contents = 0.08
        litWindows.emission.contents = UIColor(red: 1.0, green: 0.78, blue: 0.5, alpha: 1)
        litWindows.emission.intensity = 0
        neighbourShopLight = SCNMaterial()
        neighbourShopLight.lightingModel = .physicallyBased
        neighbourShopLight.diffuse.contents = UIColor(red: 0.12, green: 0.14, blue: 0.13, alpha: 1)
        neighbourShopLight.roughness.contents = 0.05
        neighbourShopLight.emission.contents = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)
        neighbourShopLight.emission.intensity = 0.25

        var rng = SeededRandom(seed: 77)
        // side: -1 = left of the shop, +1 = right.
        for side in [Float(-1), Float(1)] {
            let cols = 4, floors = 4
            let root = SCNNode()
            scene.rootNode.addChildNode(root)
            let inner: Float = 4.35
            let width = Float(cols) * 3
            let tint = side < 0 ? UIColor(red: 1.0, green: 0.92, blue: 0.80, alpha: 1) : UIColor(red: 0.86, green: 0.9, blue: 0.93, alpha: 1)
            let wallMat = tinted(tint)
            // Body behind the facade.
            let fire = surf(side < 0 ? "large_red_bricks" : "yellow_plaster",
                            tint: side < 0 ? nil : UIColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 1))
            let cx = side * (inner + width / 2)
            let h = Float(floors) * 3
            slab(width, h, 12, fire, cx, h / 2, -6.02, parent: root)
            let roof = World.pbr(UIColor(white: 0.2, alpha: 1), rough: 0.9)
            box(CGFloat(width), 0.2, 12.2, roof, cx, h + 0.1, -6.0, parent: root)

            for c in 0..<cols {
                let xr = side < 0 ? -inner - 3 * Float(c) : inner + 3 * Float(c + 1)
                for f in 0..<floors {
                    let y = Float(f) * 3
                    let wall: String, win: String
                    if f == 0 {
                        let isDoor = c == 1
                        wall = isDoor ? "wall_door_centered_large_01" : "wall_window_centered_large_01"
                        win = isDoor ? "door_centered_large_01" : "window_centered_large_01"
                    } else {
                        let double = (c % 2 == 1)
                        wall = double ? "wall_window_centered_double_02" : "wall_window_centered_large_02"
                        win = double ? "window_centered_double_02" : "window_centered_large_02"
                    }
                    let w = Assets.model("facade", part: wall)
                    w.position = SCNVector3(xr, y, 0)
                    if let wm = wallMat { Assets.override(w, where: { $0.contains("plaster") }, with: wm) }
                    root.addChildNode(w)
                    let wn = Assets.model("facade", part: win)
                    wn.position = SCNVector3(xr, y, 0)
                    if f == 0 {
                        Assets.override(wn, where: { $0.contains("glass") }, with: side < 0 ? neighbourShopLight : litWindows)
                    } else if rng.bool(0.45) {
                        Assets.override(wn, where: { $0.contains("glass") }, with: litWindows)
                    }
                    root.addChildNode(wn)
                    // Air conditioners on some upper windows, as everywhere in Odesa.
                    if f > 0 && rng.bool(0.3) {
                        put("exterior_aircon_unit", SIMD3(xr - 0.45, y + 0.35, 0.02), anchor: .back, parent: root)
                    }
                }
                let cor = Assets.model("facade", part: "cornice_standard_standard_01")
                cor.position = SCNVector3(xr, 3.0, 0)
                root.addChildNode(cor)
                let crown = Assets.model("facade", part: "crown_standard_standard_01")
                crown.position = SCNVector3(xr, h, 0)
                root.addChildNode(crown)
            }
            // Crown and cornice ends at the shop side.
            let endX = side < 0 ? -inner : inner
            for (part, y) in [("crown_end_01", h), ("cornice_end_01", Float(3))] {
                let e = Assets.model("facade", part: side < 0 ? part : part.replacingOccurrences(of: "_01", with: "_02"))
                e.position = SCNVector3(endX, y, 0)
                root.addChildNode(e)
            }

            // Ground floor tenants: a pharmacy on the left, an empty unit for rent on the right.
            if side < 0 {
                let sign = SCNNode(geometry: SCNPlane(width: 5.2, height: 0.55))
                let m = World.pbr(Tex.shopSign("АПТЕКА", bg: UIColor(red: 0.05, green: 0.42, blue: 0.25, alpha: 1), cross: true), rough: 0.4)
                m.emission.contents = m.diffuse.contents
                m.emission.intensity = 0.35
                sign.geometry?.firstMaterial = m
                sign.position = SCNVector3(-inner - 4.5, 2.62, 0.12)
                root.addChildNode(sign)
                put("potted_plant_02", SIMD3(-inner - 2.0, 0, 0.45), parent: root)
            } else {
                for c in [0, 2, 3] {
                    let xr = inner + 3 * Float(c + 1)
                    put("rollershutter_window_01", part: "rollershutter_window_01_graffiti", SIMD3(xr - 1.5, 0.12, 0.02),
                        scale: 1.0, anchor: .bottom, parent: root)
                }
                let banner = SCNNode(geometry: SCNPlane(width: 2.4, height: 0.6))
                banner.geometry?.firstMaterial = World.pbr(Tex.shopSign("ОРЕНДА  067 123 45 67", bg: UIColor(red: 0.85, green: 0.1, blue: 0.08, alpha: 1), cross: false), rough: 0.6)
                banner.position = SCNVector3(inner + 6 - 1.5, 2.5, 0.1)
                root.addChildNode(banner)
            }
        }
    }

    // MARK: shop shell

    private var hallFloor: SCNNode?
    private var hallWalls: [SCNNode] = []
    private var accentWall: SCNNode?

    private func buildShopShell() {
        // Floors.
        hallFloor = slab(8.4, 0.04, 3.65, surf("floor_tiles_06"), 0, -0.02, -1.825, shadow: false)
        slab(8.4, 0.04, 3.55, surf("terracotta_floor_tiles"), 0, -0.02, -5.425, shadow: false)

        // Interior walls: plaster in the hall, white tiles up to 2 m in the kitchen.
        let plaster = surf("painted_plaster_wall", tint: UIColor(red: 0.98, green: 0.95, blue: 0.9, alpha: 1))
        let tiles = surf("long_white_tiles")
        let wallTop = World.pbr(UIColor(white: 0.16, alpha: 1), rough: 0.7)
        for sx in [Float(-1), Float(1)] {
            let x = sx * 4.275
            hallWalls.append(slab(0.15, 3.0, 3.65, plaster, x, 1.5, -1.825))
            slab(0.15, 2.0, 3.55, tiles, x, 1.0, -5.425)
            slab(0.15, 1.0, 3.55, plaster, x, 2.5, -5.425)
            box(0.17, 0.04, 7.3, wallTop, x, 3.02, -3.6)
        }
        slab(8.7, 2.0, 0.15, tiles, 0, 1.0, -7.275)
        slab(8.7, 1.0, 0.15, plaster, 0, 2.5, -7.275)
        box(8.72, 0.04, 0.17, wallTop, 0, 3.02, -7.275)
        // Exterior of the back wall (courtyard side).
        slab(8.7, 3.0, 0.02, surf("beige_wall_002", tint: UIColor(white: 0.8, alpha: 1)), 0, 1.5, -7.36)

        // Front: dark tile plinth, aluminium shopfront, fascia with the sign.
        let plinth = surf("rectangular_facade_tiles", tint: UIColor(white: 0.55, alpha: 1))
        slab(6.6, 0.45, 0.25, plinth, -1.05, 0.225, 0)
        slab(0.9, 0.45, 0.25, plinth, 3.9, 0.225, 0)
        for (cx, w) in [(Float(-1.05), CGFloat(6.6)), (Float(3.9), CGFloat(0.9))] {
            let g = SCNNode(geometry: SCNBox(width: w, height: 2.3, length: 0.02, chamferRadius: 0))
            g.geometry?.firstMaterial = glass
            g.position = SCNVector3(cx, 1.6, 0)
            g.castsShadow = false
            scene.rootNode.addChildNode(g)
        }
        for mx in [Float(-4.3), Float(-2.6), Float(-0.9), Float(0.8), Float(2.25), Float(3.35), Float(4.3)] {
            box(0.07, 2.4, 0.1, aluminium, mx, 1.65, 0)
        }
        box(8.7, 0.07, 0.12, aluminium, 0, 0.46, 0)
        box(8.7, 0.08, 0.12, aluminium, 0, 2.78, 0)
        // Door frame and sliding glass leaf.
        box(1.2, 0.06, 0.12, aluminium, 2.8, 2.3, 0)
        let leafGlass = SCNNode(geometry: SCNBox(width: 1.0, height: 2.2, length: 0.02, chamferRadius: 0))
        leafGlass.geometry?.firstMaterial = glass
        leafGlass.castsShadow = false
        doorPanel.addChildNode(leafGlass)
        for dx in [Float(-0.5), Float(0.5)] { box(0.05, 2.2, 0.05, aluminium, dx, 0, 0, parent: doorPanel) }
        box(1.0, 0.05, 0.05, aluminium, 0, 1.1, 0, parent: doorPanel)
        box(1.0, 0.05, 0.05, aluminium, 0, -1.1, 0, parent: doorPanel)
        box(0.03, 0.5, 0.04, aluminium, -0.4, 0.05, 0.05, parent: doorPanel)
        doorPanel.position = SCNVector3(2.8, 1.12, 0.05)
        scene.rootNode.addChildNode(doorPanel)

        let fascia = World.pbr(UIColor(red: 0.13, green: 0.14, blue: 0.15, alpha: 1), rough: 0.45, metal: 0.4)
        box(8.7, 0.6, 0.24, fascia, 0, 3.12, 0.02)
        let signPlane = SCNNode(geometry: SCNPlane(width: 4.2, height: 0.48))
        signMaterial.lightingModel = .physicallyBased
        signMaterial.roughness.contents = 0.4
        signPlane.geometry?.firstMaterial = signMaterial
        signPlane.position = SCNVector3(-0.7, 3.12, 0.145)
        signPlane.name = "tap:ads"
        scene.rootNode.addChildNode(signPlane)

        // Interior lights (warm in the hall, neutral in the kitchen).
        for (p, t) in [(SIMD3<Float>(-2.1, 2.7, -1.6), CGFloat(3000)), (SIMD3<Float>(1.4, 2.7, -1.8), 3000),
                       (SIMD3<Float>(0.3, 2.7, -5.4), 4200)] {
            let l = SCNLight()
            l.type = .omni
            l.temperature = t
            l.intensity = 0
            l.attenuationStartDistance = 1.0
            l.attenuationEndDistance = 7.5
            l.attenuationFalloffExponent = 1.6
            let ln = SCNNode()
            ln.light = l
            ln.simdPosition = p
            scene.rootNode.addChildNode(ln)
            interiorLights.append(ln)
        }

        // Hall furniture that is always there.
        put("wall_clock", SIMD3(-4.2, 2.25, -2.6), yaw: .pi / 2, anchor: .back, parent: nil)
        put("WetFloorSign_01", SIMD3(-3.9, 0, -3.35), yaw: 0.4)
    }

    // MARK: kitchen

    private var prepTableRoot = SCNNode()

    private func buildKitchen() {
        // Shelving with stock on the back wall.
        let shelf = put("steel_frame_shelves_01", SIMD3(2.1, 0, -6.95), scale: 0.1, tap: "kitchen")
        _ = shelf
        put("cardboard_box_01", SIMD3(1.85, 0.13, -6.95), yaw: 0.1)
        put("cardboard_box_01", SIMD3(2.3, 0.13, -6.92), yaw: -0.2)
        put("plastic_crate_01", SIMD3(1.85, 0.64, -6.95), yaw: .pi / 2)
        put("plastic_crate_01", SIMD3(2.35, 0.64, -6.95), yaw: .pi / 2)
        put("cardboard_box_01", SIMD3(2.1, 1.15, -6.95), yaw: 0.05)
        put("plastic_crate_01", SIMD3(1.9, 1.66, -6.95), yaw: .pi / 2)
        put("plastic_crate_01", SIMD3(2.2, 0.0, -6.5), yaw: 0.3)
        put("plastic_crate_01", SIMD3(2.2, 0.27, -6.5), yaw: 0.25)

        // Upright fridge.
        let fridge = SCNNode()
        fridge.name = "tap:kitchen"
        fridge.position = SCNVector3(3.6, 0, -6.8)
        scene.rootNode.addChildNode(fridge)
        box(0.72, 2.0, 0.68, steel, 0, 1.0, 0, chamfer: 0.01, parent: fridge)
        let fdoor = World.pbr(UIColor(red: 0.1, green: 0.12, blue: 0.13, alpha: 1), rough: 0.05)
        fdoor.emission.contents = UIColor(red: 0.5, green: 0.6, blue: 0.65, alpha: 1)
        fdoor.emission.intensity = 0.25
        box(0.6, 1.5, 0.02, fdoor, 0, 1.15, 0.345, parent: fridge)
        box(0.03, 0.45, 0.04, aluminium, -0.26, 1.2, 0.37, parent: fridge)
        for (i, y) in [Float(0.65), Float(1.05), Float(1.45)].enumerated() {
            for k in 0..<4 {
                let c: UIColor = [UIColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1), UIColor(red: 0.95, green: 0.85, blue: 0.6, alpha: 1),
                                  UIColor(red: 0.3, green: 0.55, blue: 0.2, alpha: 1), UIColor(white: 0.9, alpha: 1)][(i + k) % 4]
                box(0.11, 0.16, 0.1, World.pbr(c, rough: 0.5), -0.2 + Float(k) * 0.13, y, 0.22, parent: fridge)
            }
        }

        // Hand sink on the right wall.
        let sink = SCNNode()
        sink.position = SCNVector3(3.95, 0, -5.55)
        scene.rootNode.addChildNode(sink)
        box(0.5, 0.85, 0.6, steel, 0, 0.425, 0, parent: sink)
        box(0.4, 0.02, 0.45, darkSteel, 0, 0.86, 0, parent: sink)
        cylinder(0.015, 0.3, steel, 0.18, 1.0, 0, parent: sink)

        // Range hood above the oven corner.
        let hood = SCNNode()
        hood.position = SCNVector3(-2.95, 0, -6.6)
        scene.rootNode.addChildNode(hood)
        box(1.9, 0.5, 1.2, steel, 0, 2.55, 0, chamfer: 0.02, parent: hood)
        box(0.5, 0.25, 0.4, steel, 0, 2.92, -0.2, parent: hood)

        // Menu board on the back wall.
        let menu = SCNNode(geometry: SCNPlane(width: 2.2, height: 1.15))
        menuMaterial.lightingModel = .physicallyBased
        menuMaterial.roughness.contents = 0.85
        menu.geometry?.firstMaterial = menuMaterial
        menu.position = SCNVector3(0.3, 2.15, -7.19)
        menu.name = "tap:menu"
        scene.rootNode.addChildNode(menu)
        box(2.3, 1.25, 0.03, blackMetal, 0.3, 2.15, -7.21)

        scene.rootNode.addChildNode(prepTableRoot)
    }

    private func buildPrepTable(fridgeTop: Bool) {
        prepTableRoot.childNodes.forEach { $0.removeFromParentNode() }
        prepTableRoot.name = "tap:kitchen"
        let p = prepTableRoot
        if fridgeTop {
            // Refrigerated prep counter: doors below, ingredient pans under a sneeze guard.
            box(3.6, 0.86, 0.72, steel, 0.6, 0.43, -5.75, chamfer: 0.01, parent: p)
            for i in 0..<4 {
                box(0.82, 0.62, 0.02, darkSteel, -0.75 + Float(i) * 0.9, 0.45, -5.385, parent: p)
                box(0.5, 0.025, 0.03, aluminium, -0.75 + Float(i) * 0.9, 0.7, -5.37, parent: p)
            }
            box(3.6, 0.04, 0.72, steel, 0.6, 0.88, -5.75, parent: p)
            let colors: [UIColor] = [UIColor(red: 0.75, green: 0.12, blue: 0.08, alpha: 1), UIColor(red: 0.97, green: 0.93, blue: 0.8, alpha: 1),
                                     UIColor(red: 0.85, green: 0.35, blue: 0.3, alpha: 1), UIColor(red: 0.25, green: 0.45, blue: 0.15, alpha: 1),
                                     UIColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1), UIColor(red: 0.4, green: 0.25, blue: 0.15, alpha: 1),
                                     UIColor(red: 0.15, green: 0.15, blue: 0.12, alpha: 1), UIColor(red: 0.9, green: 0.55, blue: 0.4, alpha: 1)]
            for (i, c) in colors.enumerated() {
                box(0.36, 0.06, 0.26, World.pbr(c, rough: 0.55), -0.95 + Float(i) * 0.44, 0.905, -5.97, parent: p)
            }
            let guardGlass = SCNNode(geometry: SCNBox(width: 3.5, height: 0.3, length: 0.01, chamferRadius: 0))
            guardGlass.geometry?.firstMaterial = glass
            guardGlass.position = SCNVector3(0.6, 1.12, -5.83)
            guardGlass.eulerAngles.x = -0.35
            p.addChildNode(guardGlass)
        } else {
            // Plain stainless worktable with an undershelf.
            box(3.6, 0.04, 0.7, steel, 0.6, 0.88, -5.75, parent: p)
            box(3.5, 0.03, 0.62, steel, 0.6, 0.18, -5.75, parent: p)
            for (lx, lz) in [(Float(-1.15), Float(-6.05)), (2.35, -6.05), (-1.15, -5.45), (2.35, -5.45)] {
                box(0.04, 0.88, 0.04, steel, lx, 0.44, lz, parent: p)
            }
            put("plastic_crate_01", SIMD3(-0.6, 0.195, -5.8), yaw: .pi / 2, parent: p)
            put("cardboard_box_01", SIMD3(1.5, 0.195, -5.8), parent: p)
            // Ingredient tubs on the table.
            let tub = World.pbr(UIColor(white: 0.96, alpha: 1), rough: 0.3)
            for i in 0..<5 {
                cylinder(0.08, 0.12, tub, -0.9 + Float(i) * 0.22, 0.96, -6.0, parent: p)
            }
        }
        put("wooden_cutting_board", SIMD3(1.95, 0.9, -5.7), yaw: 0.1, parent: p)
        // Dough balls tray.
        let tray = World.pbr(UIColor(red: 0.85, green: 0.25, blue: 0.15, alpha: 1), rough: 0.5)
        box(0.6, 0.08, 0.4, tray, 2.0, 0.94, -6.0, parent: p)
        let dough = World.pbr(UIColor(red: 0.96, green: 0.9, blue: 0.78, alpha: 1), rough: 0.7)
        for i in 0..<6 {
            let d = SCNNode(geometry: SCNSphere(radius: 0.06))
            d.geometry?.firstMaterial = dough
            d.scale = SCNVector3(1, 0.6, 1)
            d.position = SCNVector3(1.8 + Float(i % 3) * 0.18, 0.99, -6.08 + Float(i / 3) * 0.16)
            p.addChildNode(d)
        }
        p.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    // MARK: counter

    private func buildCounter() {
        let root = SCNNode()
        root.name = "tap:menu"
        scene.rootNode.addChildNode(root)
        slab(3.0, 0.98, 0.66, surf("oak_veneer_01"), 0.6, 0.49, -4.0, parent: root)
        box(3.0, 0.08, 0.02, blackMetal, 0.6, 0.04, -3.665, parent: root)
        slab(3.12, 0.04, 0.78, surf("marble_01", tint: UIColor(white: 0.55, alpha: 1), rough: 0.2), 0.6, 1.0, -4.0, parent: root)
        // Pizza-by-the-slice display case.
        let caseNode = SCNNode()
        caseNode.position = SCNVector3(0.35, 1.02, -4.0)
        root.addChildNode(caseNode)
        box(0.95, 0.03, 0.5, steel, 0, 0.015, 0, parent: caseNode)
        let caseGlass = SCNNode(geometry: SCNBox(width: 0.95, height: 0.34, length: 0.5, chamferRadius: 0.01))
        caseGlass.geometry?.firstMaterial = glass
        caseGlass.position = SCNVector3(0, 0.2, 0)
        caseNode.addChildNode(caseGlass)
        for k in 0..<2 {
            let pz = World.pizzaNode(radius: 0.2)
            pz.position = SCNVector3(-0.22 + Float(k) * 0.44, 0.045, 0)
            pz.eulerAngles.y = Float(k) * 1.3
            caseNode.addChildNode(pz)
        }
        // Cash drawer / POS screen.
        box(0.36, 0.1, 0.4, blackMetal, 1.45, 1.07, -4.05, chamfer: 0.01, parent: root)
        let screen = World.pbr(UIColor(red: 0.05, green: 0.08, blue: 0.1, alpha: 1), rough: 0.1)
        screen.emission.contents = Tex.posScreen()
        screen.emission.intensity = 0.8
        let mon = SCNNode(geometry: SCNBox(width: 0.32, height: 0.22, length: 0.02, chamferRadius: 0.005))
        mon.geometry?.materials = [screen, blackMetal, blackMetal, blackMetal, blackMetal, blackMetal]
        mon.position = SCNVector3(1.45, 1.3, -4.12)
        mon.eulerAngles.y = .pi
        mon.eulerAngles.x = 0.15
        root.addChildNode(mon)
        cylinder(0.015, 0.16, blackMetal, 1.45, 1.17, -4.12, parent: root)
        // Napkins and a tip jar.
        box(0.12, 0.1, 0.08, darkSteel, 0.0, 1.07, -3.75, parent: root)
        let jar = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.14))
        jar.geometry?.firstMaterial = glass
        jar.position = SCNVector3(1.0, 1.09, -3.75)
        root.addChildNode(jar)
        put("potted_plant_04", SIMD3(2.0, 1.02, -3.8), parent: root)
        root.enumerateHierarchy { n, _ in if n.geometry?.firstMaterial !== self.glass { n.castsShadow = true } }
    }

    // MARK: street furniture

    private func buildStreetFurniture() {
        for x in [Float(-8.5), Float(9.5), Float(-26), Float(26)] {
            let l = put("street_lamp_01", SIMD3(x, 0, 3.0))
            _ = l
            let sl = SCNLight()
            sl.type = .omni
            sl.temperature = 3000
            sl.intensity = 0
            sl.attenuationStartDistance = 1
            sl.attenuationEndDistance = 11
            sl.attenuationFalloffExponent = 1.5
            let ln = SCNNode()
            ln.light = sl
            ln.position = SCNVector3(x, 3.6, 3.0)
            scene.rootNode.addChildNode(ln)
            streetLights.append(ln)
        }
        streetBulb = Assets.sharedMaterial("street_lamp_01", named: "bulb")
        streetGlass = Assets.sharedMaterial("street_lamp_01", named: "glass")
        streetGlass?.emission.contents = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        streetGlass?.emission.intensity = 0
        interiorGlow = [tubeMat]
        for (id, name) in [("modern_ceiling_lamp_01", "globe"), ("hanging_industrial_lamp", "glass")] {
            if let m = Assets.sharedMaterial(id, named: name) { interiorGlow.append(m) }
        }

        put("metal_trash_can", SIMD3(4.75, 0, 0.45))
        put("trashbag", SIMD3(-16.8, 0, 0.5), yaw: 0.6)
        put("utility_box_01", SIMD3(-5.0, 0, 0.35))
        put("security_camera_01", SIMD3(4.15, 2.55, 0.25), yaw: 0.5)
        put("covered_car", SIMD3(13.5, -0.12, 10.1), yaw: .pi / 2 + 0.03)
        put("metal_trash_can", SIMD3(-2.0, 0, -9.0), yaw: 0.3)
        put("metal_trash_can", SIMD3(-1.1, 0, -9.1), yaw: -0.2)
        put("trashbag", SIMD3(-0.4, 0, -9.0))
        put("plastic_crate_01", SIMD3(1.2, 0, -8.0), yaw: 0.2)
        put("plastic_crate_01", SIMD3(1.25, 0.264, -8.0), yaw: 0.25)
        put("exterior_aircon_unit", SIMD3(2.8, 2.0, -7.37), yaw: .pi, anchor: .back)
    }

    // MARK: live props (pizzas, boxes, plates)

    static func pizzaNode(radius: CGFloat = 0.16, raw: Bool = false) -> SCNNode {
        let cyl = SCNCylinder(radius: radius, height: 0.018)
        let top = World.pbr(raw ? World.rawPizzaImage : World.pizzaImage, rough: 0.55)
        let crust = World.pbr(UIColor(red: raw ? 0.93 : 0.78, green: raw ? 0.85 : 0.55, blue: raw ? 0.7 : 0.3, alpha: 1), rough: 0.8)
        cyl.materials = [crust, top, crust]
        let n = SCNNode(geometry: cyl)
        n.castsShadow = false
        return n
    }

    static let pizzaImage: UIImage = Tex.pizzaTop()
    static let rawPizzaImage: UIImage = Tex.pizzaTop(raw: true)

    private func buildLiveProps() {
        for c in Spot.cooks {
            let pz = World.pizzaNode(radius: 0.15, raw: true)
            pz.position = SCNVector3(c.x, 0.915, -5.6)
            pz.isHidden = true
            scene.rootNode.addChildNode(pz)
            prepPizzas.append(pz)
        }
        let boxMat = World.pbr(World.cardboard, rough: 0.9)
        let lid = World.pbr(Tex.pizzaBoxLid(), rough: 0.85)
        for k in 0..<6 {
            let b = SCNNode(geometry: SCNBox(width: 0.34, height: 0.045, length: 0.34, chamferRadius: 0.003))
            b.geometry?.materials = [boxMat, boxMat, boxMat, boxMat, lid, boxMat]
            b.position = SCNVector3(-0.62 + Float(k / 3) * 0.02, 1.045 + Float(k % 3) * 0.047, -3.86 - Float(k / 3) * 0.36)
            b.eulerAngles.y = Float(k) * 0.07
            b.isHidden = true
            scene.rootNode.addChildNode(b)
            readyBoxes.append(b)
        }
    }

    func clearPlates() {
        plates.values.forEach { $0.removeFromParentNode() }
        plates.removeAll()
    }

    func setEating(seat: Int, _ on: Bool) {
        if !on {
            plates[seat]?.removeFromParentNode()
            plates[seat] = nil
            return
        }
        guard plates[seat] == nil, seat < seats.count else { return }
        let s = seats[seat]
        let toward = simd_normalize(SIMD3(s.facing.x - s.position.x, 0, s.facing.z - s.position.z))
        let p = s.facing - toward * 0.2
        let plate = SCNNode(geometry: SCNCylinder(radius: 0.17, height: 0.012))
        plate.geometry?.firstMaterial = World.pbr(UIColor(white: 0.96, alpha: 1), rough: 0.25)
        plate.position = SCNVector3(p.x, 0.772, p.z)
        let pz = World.pizzaNode(radius: 0.15)
        pz.position = SCNVector3(0, 0.014, 0)
        plate.addChildNode(pz)
        let glassCup = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.12))
        glassCup.geometry?.firstMaterial = glass
        glassCup.position = SCNVector3(0.2, 0.06, 0.05)
        plate.addChildNode(glassCup)
        scene.rootNode.addChildNode(plate)
        plates[seat] = plate
    }

    // MARK: upgrades

    func apply(_ s: GameState) {
        if s.oven != currentOven { buildOven(s.oven) }
        let key = [String(s.tables), s.building.sorted().joined(), s.equipment.sorted().joined(), s.adsOn.sorted().joined(),
                   String(s.flyersDay)].joined(separator: "|")
        if key != appliedKey {
            appliedKey = key
            let reno = s.building.contains("renovation")
            if reno != renovated || !interiorBuilt {
                interiorBuilt = true
                renovated = reno
                applyInterior(renovated: reno)
            }
            buildPrepTable(fridgeTop: s.equipment.contains("prepFridge"))
            buildTables(s)
            buildUpgrades(s)
        }
        let lit = s.building.contains("sign")
        let signImage = Tex.sign(lit ? "ПИЦЦЕРИЯ" : "ПИЦЦА", lit: lit)
        signMaterial.diffuse.contents = signImage
        signMaterial.emission.contents = lit ? signImage : UIColor.black
        signMaterial.emission.intensity = lit ? 1.2 : 0
        updateMenu(s)
    }

    func updateMenu(_ s: GameState) {
        let lines = Catalog.pizzas.filter { s.unlockedPizzas.contains($0.id) }.map { ($0.name, "\(Int(s.price($0.id).rounded()))") }
        menuMaterial.diffuse.contents = Tex.menuBoard(lines: lines)
    }

    private func applyInterior(renovated reno: Bool) {
        hallFloor?.geometry = Geo.box(8.4, 0.04, 3.65, tile: reno ? 3.4 : 3.0)
        hallFloor?.geometry?.firstMaterial = (reno ? surf("herringbone_parquet") : surf("floor_tiles_06")).0
        accentWall?.removeFromParentNode()
        accentWall = nil
        hallRoot.childNodes.forEach { $0.removeFromParentNode() }
        let tube = tubeMat
        if reno {
            // Brick accent wall, pendant lamps, pictures, plants, shelving with wine.
            accentWall = slab(0.04, 3.0, 3.65, surf("red_brick_03"), -4.19, 1.5, -1.825, parent: hallRoot)
            for p in [SIMD3<Float>(-3.15, 3.0, -1.2), SIMD3<Float>(-1.7, 3.0, -1.2), SIMD3<Float>(-0.25, 3.0, -1.2)] {
                put("modern_ceiling_lamp_01", p - SIMD3(0, 1.173 - 0.25, 0), parent: hallRoot)
            }
            put("hanging_industrial_lamp", SIMD3(0.0, 3.0, -4.0), scale: 0.8, anchor: .top, parent: hallRoot)
            put("hanging_industrial_lamp", SIMD3(1.3, 3.0, -4.0), scale: 0.8, anchor: .top, parent: hallRoot)
            put("hanging_picture_frame_02", SIMD3(-4.17, 1.75, -0.9), yaw: .pi / 2, anchor: .back, parent: hallRoot)
            put("hanging_picture_frame_02", SIMD3(-4.17, 1.75, -2.6), yaw: .pi / 2, anchor: .back, parent: hallRoot)
            put("potted_plant_02", SIMD3(-3.85, 0, -0.35), parent: hallRoot)
            put("potted_plant_02", SIMD3(1.15, 0, -0.35), yaw: 1.2, parent: hallRoot)
            put("wooden_display_shelves_01", SIMD3(4.02, 0, -2.4), yaw: -.pi / 2, parent: hallRoot)
            put("hanging_industrial_lamp", SIMD3(0.6, 3.0, -5.6), scale: 0.8, anchor: .top, parent: hallRoot)
            put("hanging_industrial_lamp", SIMD3(-2.4, 3.0, -5.6), scale: 0.8, anchor: .top, parent: hallRoot)
        } else {
            for p in [SIMD3<Float>(-2.2, 2.92, -1.8), SIMD3<Float>(0.9, 2.92, -1.8), SIMD3<Float>(0.6, 2.92, -5.6), SIMD3<Float>(-2.6, 2.92, -5.6)] {
                box(1.25, 0.05, 0.12, white, p.x, p.y, p.z, parent: hallRoot)
                box(1.2, 0.03, 0.06, tube, p.x, p.y - 0.035, p.z, parent: hallRoot)
            }
        }
        hallRoot.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    private func buildOven(_ id: String) {
        currentOven = id
        ovenRoot.childNodes.forEach { $0.removeFromParentNode() }
        ovenPizzas.forEach { $0.removeFromParentNode() }
        ovenPizzas.removeAll()
        fire = nil
        ovenRoot.name = "tap:kitchen"
        let glow = World.pbr(UIColor(red: 0.1, green: 0.04, blue: 0.02, alpha: 1), rough: 0.6)
        glow.emission.contents = UIColor(red: 1, green: 0.42, blue: 0.1, alpha: 1)
        glow.emission.intensity = 0
        ovenGlow = glow
        let r = ovenRoot
        switch id {
        case "wood":
            // Brick base, tiled dome, arched mouth with a real fire inside.
            let base = surf("red_brick_03")
            slab(1.9, 1.0, 1.8, base, -2.95, 0.5, -6.25, parent: r)
            slab(1.96, 0.06, 1.86, surf("marble_01", tint: UIColor(white: 0.4, alpha: 1)), -2.95, 1.03, -6.25, parent: r)
            let domeMat = surf("red_brick_03", tint: UIColor(red: 0.95, green: 0.8, blue: 0.7, alpha: 1))
            let dome = SCNNode(geometry: SCNSphere(radius: 0.85))
            dome.geometry?.firstMaterial = domeMat.0
            dome.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeScale(4, 2, 1)
            dome.position = SCNVector3(-2.95, 1.06, -6.35)
            dome.scale = SCNVector3(1, 0.68, 1)
            r.addChildNode(dome)
            let arch = SCNNode(geometry: SCNBox(width: 0.62, height: 0.38, length: 0.3, chamferRadius: 0.14))
            arch.geometry?.firstMaterial = surf("red_brick_03").0
            arch.position = SCNVector3(-2.95, 1.25, -5.55)
            r.addChildNode(arch)
            let mouth = SCNNode(geometry: SCNBox(width: 0.5, height: 0.3, length: 0.1, chamferRadius: 0.12))
            mouth.geometry?.firstMaterial = glow
            mouth.position = SCNVector3(-2.95, 1.22, -5.42)
            r.addChildNode(mouth)
            cylinder(0.11, 1.6, blackMetal, -2.95, 2.35, -6.2, parent: r)
            // Firewood stacked under the oven.
            let log = World.pbr(UIColor(red: 0.35, green: 0.24, blue: 0.15, alpha: 1), rough: 0.95)
            for i in 0..<9 {
                let l = SCNNode(geometry: SCNCylinder(radius: 0.055, height: 0.5))
                l.geometry?.firstMaterial = log
                l.eulerAngles.z = .pi / 2
                l.position = SCNVector3(-1.75 + Float(i % 3) * 0.0, 0.06 + Float(i / 3) * 0.1, -6.75 + Float(i % 3) * 0.12)
                r.addChildNode(l)
            }
            let ps = World.makeFire()
            let fireNode = SCNNode()
            fireNode.position = SCNVector3(-2.95, 1.1, -6.5)
            fireNode.addParticleSystem(ps)
            r.addChildNode(fireNode)
            fire = ps
            ovenLight.position = SCNVector3(-2.95, 1.3, -5.2)
            ovenSlots = [SIMD3(-3.2, 1.08, -6.0), SIMD3(-2.7, 1.08, -6.0), SIMD3(-3.15, 1.08, -6.35), SIMD3(-2.75, 1.08, -6.35)]
        case "deck":
            let stand = SCNNode()
            stand.position = SCNVector3(-2.95, 0, -6.5)
            r.addChildNode(stand)
            box(1.45, 0.06, 1.05, steel, 0, 0.6, 0, parent: stand)
            for (lx, lz) in [(Float(-0.68), Float(-0.48)), (0.68, -0.48), (-0.68, 0.48), (0.68, 0.48)] {
                box(0.05, 0.6, 0.05, steel, lx, 0.3, lz, parent: stand)
            }
            for (i, y) in [Float(0.88), Float(1.38)].enumerated() {
                box(1.45, 0.48, 1.05, steel, 0, y, 0, chamfer: 0.01, parent: stand)
                let win = SCNNode(geometry: SCNBox(width: 0.7, height: 0.16, length: 0.02, chamferRadius: 0.01))
                win.geometry?.firstMaterial = glow
                win.position = SCNVector3(-0.15, y + 0.02, 0.53)
                stand.addChildNode(win)
                box(0.9, 0.03, 0.05, blackMetal, -0.15, y + 0.15, 0.56, parent: stand)
                box(0.22, 0.32, 0.02, blackMetal, 0.55, y, 0.53, parent: stand)
                _ = i
            }
            ovenLight.position = SCNVector3(-2.95, 1.2, -5.7)
            ovenSlots = [SIMD3(-3.25, 0.9, -6.3), SIMD3(-2.75, 0.9, -6.3), SIMD3(-3.25, 1.4, -6.3), SIMD3(-2.75, 1.4, -6.3)]
        default:
            let stand = SCNNode()
            stand.position = SCNVector3(-2.95, 0, -6.55)
            r.addChildNode(stand)
            box(0.95, 0.04, 0.8, steel, 0, 0.85, 0, parent: stand)
            box(0.9, 0.03, 0.75, steel, 0, 0.2, 0, parent: stand)
            for (lx, lz) in [(Float(-0.44), Float(-0.36)), (0.44, -0.36), (-0.44, 0.36), (0.44, 0.36)] {
                box(0.04, 0.85, 0.04, steel, lx, 0.425, lz, parent: stand)
            }
            put("plastic_crate_01", SIMD3(0, 0.215, 0), yaw: .pi / 2, parent: stand)
            box(0.9, 0.62, 0.78, steel, 0, 1.18, 0, chamfer: 0.01, parent: stand)
            let door = SCNNode(geometry: SCNBox(width: 0.58, height: 0.42, length: 0.02, chamferRadius: 0.01))
            door.geometry?.firstMaterial = glow
            door.position = SCNVector3(-0.1, 1.18, 0.395)
            stand.addChildNode(door)
            box(0.2, 0.5, 0.02, blackMetal, 0.33, 1.18, 0.395, parent: stand)
            box(0.5, 0.03, 0.04, aluminium, -0.1, 1.43, 0.42, parent: stand)
            ovenLight.position = SCNVector3(-2.95, 1.2, -5.8)
            ovenSlots = [SIMD3(-3.05, 1.06, -6.45), SIMD3(-3.05, 1.24, -6.45)]
        }
        for s in ovenSlots {
            let pz = World.pizzaNode(radius: 0.15)
            pz.position = SCNVector3(s.x, s.y, s.z)
            pz.isHidden = true
            r.addChildNode(pz)
            ovenPizzas.append(pz)
        }
        r.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    static func makeFire() -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.particleImage = Tex.softDot()
        ps.birthRate = 140
        ps.particleLifeSpan = 0.55
        ps.particleLifeSpanVariation = 0.2
        ps.emitterShape = SCNBox(width: 0.5, height: 0.02, length: 0.25, chamferRadius: 0)
        ps.particleVelocity = 0.35
        ps.particleVelocityVariation = 0.15
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = 18
        ps.particleSize = 0.09
        ps.particleSizeVariation = 0.04
        ps.particleColor = UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1)
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        let sizeCurve = SCNParticlePropertyController(animation: { () -> CAKeyframeAnimation in
            let a = CAKeyframeAnimation()
            a.values = [0.6, 1.0, 0.2]
            a.keyTimes = [0, 0.3, 1]
            return a
        }())
        let colorCurve = SCNParticlePropertyController(animation: { () -> CAKeyframeAnimation in
            let a = CAKeyframeAnimation()
            a.values = [UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 0.9), UIColor(red: 1, green: 0.45, blue: 0.1, alpha: 0.7),
                        UIColor(red: 0.6, green: 0.1, blue: 0.02, alpha: 0)]
            a.keyTimes = [0, 0.4, 1]
            return a
        }())
        ps.propertyControllers = [.size: sizeCurve, .color: colorCurve]
        return ps
    }

    private func buildTables(_ s: GameState) {
        tablesRoot.childNodes.forEach { $0.removeFromParentNode() }
        plates.values.forEach { $0.removeFromParentNode() }
        plates.removeAll()
        seats.removeAll()
        tablesRoot.name = "tap:hall"
        let reno = s.building.contains("renovation")
        let inside: [SIMD3<Float>] = [
            SIMD3(-3.15, 0, -1.75), SIMD3(-1.7, 0, -1.75), SIMD3(-3.15, 0, -0.65),
            SIMD3(-1.7, 0, -0.65), SIMD3(-0.25, 0, -1.75), SIMD3(-0.25, 0, -0.65),
        ]
        for i in 0..<min(s.tables, inside.count) { addTable(at: inside[i], renovated: reno) }
        if s.building.contains("terrace") {
            for p in [SIMD3<Float>(-3.4, 0, 1.0), SIMD3<Float>(-1.85, 0, 1.0), SIMD3<Float>(-0.3, 0, 1.0)] {
                addTerraceSet(at: p)
            }
            put("planter_box_01", SIMD3(-4.2, 0, 1.75), yaw: .pi / 2, parent: tablesRoot)
            put("planter_box_01", SIMD3(0.65, 0, 1.75), yaw: .pi / 2, parent: tablesRoot)
            put("planter_box_01", SIMD3(-1.1, 0, 1.75), yaw: .pi / 2, parent: tablesRoot)
        }
        tablesRoot.enumerateHierarchy { n, _ in if n.geometry?.firstMaterial !== self.glass { n.castsShadow = true } }
    }

    private func addTable(at p: SIMD3<Float>, renovated reno: Bool) {
        let t = SCNNode()
        t.position = SCNVector3(p.x, 0, p.z)
        tablesRoot.addChildNode(t)
        slab(0.72, 0.035, 0.72, surf(reno ? "dark_wood" : "wood_table_001"), 0, 0.745, 0, parent: t)
        cylinder(0.035, 0.72, blackMetal, 0, 0.37, 0, parent: t)
        box(0.5, 0.025, 0.06, blackMetal, 0, 0.012, 0, parent: t)
        box(0.06, 0.025, 0.5, blackMetal, 0, 0.012, 0, parent: t)
        // Condiments.
        cylinder(0.02, 0.09, World.pbr(UIColor(red: 0.6, green: 0.12, blue: 0.05, alpha: 1), rough: 0.3), 0.05, 0.81, 0.02, parent: t)
        cylinder(0.02, 0.09, World.pbr(UIColor(white: 0.95, alpha: 1), rough: 0.3), -0.02, 0.81, -0.03, parent: t)
        for side in [Float(-1), Float(1)] {
            let cx = p.x + side * 0.58
            let chairId = reno ? "painted_wooden_chair_01" : "plastic_monobloc_chair_01"
            // Chairs face +z in the model; turn them toward the table.
            put(chairId, SIMD3(cx, 0, p.z), yaw: side < 0 ? .pi / 2 : -.pi / 2, parent: tablesRoot)
            seats.append(Seat(position: SIMD3(cx + side * 0.04, 0, p.z), facing: SIMD3(p.x, 0, p.z)))
        }
    }

    private func addTerraceSet(at p: SIMD3<Float>) {
        let id = "outdoor_table_chair_set_01"
        put(id, part: "outdoor_table_chair_set_01_table", SIMD3(p.x, 0, p.z), yaw: .pi / 2, parent: tablesRoot)
        for side in [Float(-1), Float(1)] {
            let cx = p.x + side * 0.58
            put(id, part: "outdoor_table_chair_set_01_chair_01", SIMD3(cx, 0, p.z), yaw: side < 0 ? -.pi / 2 : .pi / 2, parent: tablesRoot)
            seats.append(Seat(position: SIMD3(cx + side * 0.04, 0, p.z), facing: SIMD3(p.x, 0, p.z)))
        }
    }

    private func buildUpgrades(_ s: GameState) {
        upgradesRoot.childNodes.forEach { $0.removeFromParentNode() }
        signLamps.removeAll()
        let has = { (id: String) in s.equipment.contains(id) || s.building.contains(id) }
        let u = upgradesRoot

        if has("mixer") {
            let m = SCNNode()
            m.position = SCNVector3(2.95, 0, -6.75)
            m.name = "tap:kitchen"
            u.addChildNode(m)
            box(0.5, 0.7, 0.55, white, 0, 0.35, 0, chamfer: 0.04, parent: m)
            box(0.3, 0.6, 0.25, white, 0, 0.95, -0.15, chamfer: 0.04, parent: m)
            box(0.42, 0.18, 0.5, white, 0, 1.32, 0.0, chamfer: 0.05, parent: m)
            let bowl = SCNNode(geometry: SCNCylinder(radius: 0.21, height: 0.28))
            bowl.geometry?.firstMaterial = steel
            bowl.position = SCNVector3(0, 0.88, 0.08)
            m.addChildNode(bowl)
        }
        if has("coffee") {
            let c = SCNNode()
            c.position = SCNVector3(1.95, 1.02, -4.12)
            c.name = "tap:kitchen"
            u.addChildNode(c)
            box(0.55, 0.42, 0.42, steel, 0, 0.21, 0, chamfer: 0.02, parent: c)
            box(0.55, 0.06, 0.42, blackMetal, 0, 0.45, 0, parent: c)
            for dx in [Float(-0.12), Float(0.12)] {
                cylinder(0.035, 0.06, blackMetal, dx, 0.13, 0.2, parent: c)
                let cup = SCNNode(geometry: SCNCylinder(radius: 0.03, height: 0.06))
                cup.geometry?.firstMaterial = white
                cup.position = SCNVector3(dx, 0.04, 0.2)
                c.addChildNode(cup)
            }
        }
        if has("terminal") {
            box(0.08, 0.025, 0.16, blackMetal, 1.12, 1.035, -3.78, chamfer: 0.01, parent: u)
            let screen = World.pbr(UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), rough: 0.1)
            screen.emission.contents = UIColor(red: 0.2, green: 0.45, blue: 0.7, alpha: 1)
            box(0.06, 0.004, 0.06, screen, 1.12, 1.05, -3.75, parent: u)
        }
        if has("generator") {
            put("portable_generator", SIMD3(-4.0, 0, 0.75), yaw: 0.2, parent: u, tap: "kitchen")
            // Cable to the shop.
            let cable = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 1.0))
            cable.geometry?.firstMaterial = blackMetal
            cable.eulerAngles.x = .pi / 2
            cable.position = SCNVector3(-3.8, 0.02, 0.25)
            u.addChildNode(cable)
        }
        if has("windows") {
            let decal = SCNMaterial()
            decal.lightingModel = .constant
            decal.diffuse.contents = Tex.windowDecal()
            decal.blendMode = .alpha
            decal.isDoubleSided = true
            decal.writesToDepthBuffer = false
            let d = SCNNode(geometry: SCNPlane(width: 2.6, height: 1.3))
            d.geometry?.firstMaterial = decal
            d.position = SCNVector3(-1.6, 1.45, 0.02)
            d.castsShadow = false
            u.addChildNode(d)
            // Chalkboard menu on the pavement.
            let board = put("standing_chalkboard_01", SIMD3(1.55, 0, 0.95), yaw: 0.35, parent: u, tap: "menu")
            _ = board
        }
        if has("sign") {
            for x in [Float(-3.6), Float(-0.7), Float(2.2)] {
                put("industrial_wall_lamp", SIMD3(x, 3.5, 0.14), anchor: .back, parent: u)
            }
            if let g = Assets.sharedMaterial("industrial_wall_lamp", named: "glass") {
                g.emission.contents = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
                signLamps.append(g)
            }
        }
        if s.adsOn.contains("billboard") {
            let bb = SCNNode()
            bb.name = "tap:ads"
            bb.position = SCNVector3(-12.5, 0, 3.0)
            bb.eulerAngles.y = 0.25
            u.addChildNode(bb)
            box(0.18, 3.6, 0.18, darkSteel, 0, 1.8, -0.1, parent: bb)
            box(4.2, 2.2, 0.2, darkSteel, 0, 4.2, -0.12, parent: bb)
            let poster = World.pbr(Tex.billboard(), rough: 0.6)
            poster.emission.contents = Tex.billboard()
            poster.emission.intensity = 0.25
            let pn = SCNNode(geometry: SCNPlane(width: 4.0, height: 2.0))
            pn.geometry?.firstMaterial = poster
            pn.position = SCNVector3(0, 4.2, 0.0)
            bb.addChildNode(pn)
        }
        if s.adsOn.contains("delivery") {
            let sticker = SCNNode(geometry: SCNPlane(width: 0.32, height: 0.2))
            let m = World.pbr(Tex.shopSign("ДОСТАВКА", bg: UIColor(red: 0.16, green: 0.45, blue: 0.22, alpha: 1), cross: false), rough: 0.5)
            sticker.geometry?.firstMaterial = m
            sticker.position = SCNVector3(3.85, 1.5, 0.02)
            u.addChildNode(sticker)
        }
        u.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    // MARK: people

    func add(_ person: PersonNode, at p: SIMD3<Float>) {
        person.node.simdPosition = p
        scene.rootNode.addChildNode(person.node)
        people.append(WeakPerson(node: person.node))
    }

    // MARK: per-frame

    struct Ambience {
        var minute: Double
        var interiorPowered: Bool
        var streetPowered: Bool
        var ovenBusy: Float      // 0…1
        var ovenWorking: Bool
        var ovenPizzas = 0
        var prepping: [Bool] = []
        var readyBoxes = 0
    }

    func update(dt: Float, visualSpeed: Float, _ a: Ambience) {
        let hour = Float(a.minute / 60)
        let dayT = (hour - 5.5) / 15
        let sunHeight = sin(dayT * .pi)
        let elev = max(0.08, asin(max(-1, min(1, sunHeight))))
        let az = (dayT - 0.5) * 1.9 + 0.5
        sun.eulerAngles = SCNVector3(-elev, az, 0)
        let dayAmount = max(0, min(1, (sunHeight + 0.05) / 0.35))
        sun.light?.intensity = CGFloat(1500 * dayAmount)
        sun.light?.temperature = CGFloat(3500 + 2700 * max(0, min(1, sunHeight * 2.2)))
        ambient.light?.intensity = CGFloat(15 + 50 * dayAmount)
        let night = dayAmount < 0.25
        if envIsNight != night {
            envIsNight = night
            scene.lightingEnvironment.contents = Assets.url(night ? "env_night.exr" : "env_day.exr")
        }
        scene.lightingEnvironment.intensity = CGFloat(night ? 0.35 : 0.25 + 0.85 * dayAmount)

        let skyKey = Int(a.minute / 10)
        if skyKey != lastSkyKey {
            lastSkyKey = skyKey
            updateSky(minute: a.minute)
        }

        let interior: CGFloat = a.interiorPowered ? CGFloat(900 - 450 * dayAmount) : 0
        for l in interiorLights { l.light?.intensity = interior }
        for g in interiorGlow {
            g.emission.contents = a.interiorPowered ? UIColor(red: 1, green: 0.9, blue: 0.75, alpha: 1) : UIColor.black
            g.emission.intensity = a.interiorPowered ? 1.2 : 0
        }
        let streetOn = a.streetPowered && dayAmount < 0.4
        for l in streetLights { l.light?.intensity = streetOn ? 1800 : 0 }
        streetBulb?.emission.contents = streetOn ? UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1) : UIColor.black
        streetGlass?.emission.intensity = streetOn ? 1.5 : 0
        litWindows?.emission.intensity = CGFloat(a.streetPowered ? max(0, 1 - dayAmount * 1.6) * 1.4 : 0.08)
        neighbourShopLight?.emission.intensity = a.streetPowered ? 0.35 + (1 - CGFloat(dayAmount)) * 0.6 : 0
        for g in signLamps { g.emission.intensity = a.interiorPowered && dayAmount < 0.5 ? 1.6 : 0 }
        signMaterial.emission.intensity = (signMaterial.emission.contents as? UIImage) != nil && a.interiorPowered ? 1.0 + CGFloat(1 - dayAmount) * 0.8 : 0

        flicker += dt * 9
        let woodOven = currentOven == "wood"
        let base: Float = a.ovenWorking ? (woodOven ? 1.0 : 0.35 + 0.6 * a.ovenBusy) : (woodOven ? 0.25 : 0)
        let f = woodOven ? (0.85 + 0.15 * sin(flicker) * sin(flicker * 0.37 + 1)) : 1
        ovenGlow?.emission.intensity = CGFloat(base * f * 2.4)
        ovenLight.light?.intensity = CGFloat(base * f * (woodOven ? 600 : 220))
        fire?.birthRate = CGFloat(a.ovenWorking ? 140 : 25)

        for (i, n) in prepPizzas.enumerated() { n.isHidden = !(i < a.prepping.count && a.prepping[i]) }
        for (i, n) in ovenPizzas.enumerated() { n.isHidden = i >= a.ovenPizzas }
        for (i, n) in readyBoxes.enumerated() { n.isHidden = i >= a.readyBoxes }

        updateDoor(dt: dt)
        updateCars(dt: dt * visualSpeed)
    }

    private func updateDoor(dt: Float) {
        people.removeAll { $0.node?.parent == nil }
        let near = people.contains { w in
            guard let n = w.node else { return false }
            let p = n.simdPosition
            return abs(p.x - Spot.doorX) < 0.9 && abs(p.z) < 1.4
        }
        doorOpen += ((near ? 1 : 0) - doorOpen) * min(1, dt * 6)
        doorPanel.position.x = Spot.doorX + doorOpen * 0.95
    }

    private func updateSky(minute: Double) {
        let hour = Float(minute / 60)
        let sunHeight = sin((hour - 5.5) / 15 * .pi)
        let night = max(0, min(1, (-sunHeight + 0.08) / 0.25))
        scene.background.contents = Tex.sky(sunHeight: sunHeight, night: night)
    }

    // MARK: cars

    private func makeCar(seed: Int) -> SCNNode {
        var rng = SeededRandom(seed: UInt64(seed + 11))
        let root = SCNNode()
        let colors: [UIColor] = [UIColor(white: 0.88, alpha: 1), UIColor(white: 0.08, alpha: 1), UIColor(white: 0.5, alpha: 1),
                                 UIColor(red: 0.5, green: 0.06, blue: 0.06, alpha: 1), UIColor(red: 0.1, green: 0.18, blue: 0.32, alpha: 1),
                                 UIColor(red: 0.62, green: 0.6, blue: 0.55, alpha: 1)]
        let paint = World.pbr(colors[rng.int(colors.count)], rough: 0.18, metal: 0.55)
        paint.clearCoat.contents = 1.0
        paint.clearCoatRoughness.contents = 0.05
        let tint = World.pbr(UIColor(white: 0.03, alpha: 1), rough: 0.05, metal: 0.3)
        let tyre = World.pbr(UIColor(white: 0.04, alpha: 1), rough: 0.9)
        let rim = World.pbr(UIColor(white: 0.6, alpha: 1), rough: 0.3, metal: 1)

        // Side profile (x = length, y = height), extruded across the width.
        let body = UIBezierPath()
        body.move(to: CGPoint(x: -2.2, y: 0.32))
        body.addLine(to: CGPoint(x: -2.22, y: 0.78))
        body.addQuadCurve(to: CGPoint(x: -1.9, y: 0.98), controlPoint: CGPoint(x: -2.2, y: 0.96))
        body.addLine(to: CGPoint(x: -1.35, y: 1.0))
        body.addLine(to: CGPoint(x: 1.1, y: 0.97))
        body.addQuadCurve(to: CGPoint(x: 2.15, y: 0.78), controlPoint: CGPoint(x: 2.05, y: 0.92))
        body.addLine(to: CGPoint(x: 2.22, y: 0.42))
        body.addQuadCurve(to: CGPoint(x: 2.05, y: 0.3), controlPoint: CGPoint(x: 2.2, y: 0.3))
        body.addLine(to: CGPoint(x: -2.05, y: 0.3))
        body.close()
        let shape = SCNShape(path: body, extrusionDepth: 1.76)
        shape.chamferRadius = 0.09
        shape.chamferMode = .both
        shape.firstMaterial = paint
        let bn = SCNNode(geometry: shape)
        bn.eulerAngles.y = -.pi / 2
        root.addChildNode(bn)

        let cabin = UIBezierPath()
        cabin.move(to: CGPoint(x: -1.55, y: 0.96))
        cabin.addLine(to: CGPoint(x: -1.05, y: 1.42))
        cabin.addQuadCurve(to: CGPoint(x: 0.35, y: 1.44), controlPoint: CGPoint(x: -0.3, y: 1.5))
        cabin.addLine(to: CGPoint(x: 1.15, y: 0.96))
        cabin.close()
        let cs = SCNShape(path: cabin, extrusionDepth: 1.5)
        cs.chamferRadius = 0.07
        cs.chamferMode = .both
        cs.materials = [tint, tint, tint, paint, paint]
        let cn = SCNNode(geometry: cs)
        cn.eulerAngles.y = -.pi / 2
        root.addChildNode(cn)

        for (wx, wz) in [(Float(-0.8), Float(1.38)), (0.8, 1.38), (-0.8, -1.38), (0.8, -1.38)] {
            let w = SCNNode(geometry: SCNCylinder(radius: 0.32, height: 0.22))
            w.geometry?.firstMaterial = tyre
            w.eulerAngles.z = .pi / 2
            w.position = SCNVector3(wx, 0.32, wz)
            root.addChildNode(w)
            let r = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.225))
            r.geometry?.firstMaterial = rim
            r.eulerAngles.z = .pi / 2
            r.position = SCNVector3(wx, 0.32, wz)
            root.addChildNode(r)
        }
        let lamp = World.pbr(UIColor(white: 1, alpha: 1), rough: 0.1)
        lamp.emission.contents = UIColor(white: 0.95, alpha: 1)
        box(0.34, 0.1, 0.04, lamp, -0.58, 0.75, 2.2, chamfer: 0.02, parent: root)
        box(0.34, 0.1, 0.04, lamp, 0.58, 0.75, 2.2, chamfer: 0.02, parent: root)
        let rear = World.pbr(UIColor(red: 0.5, green: 0.02, blue: 0.02, alpha: 1), rough: 0.2)
        rear.emission.contents = UIColor(red: 0.6, green: 0, blue: 0, alpha: 1)
        box(0.36, 0.09, 0.04, rear, -0.6, 0.8, -2.2, chamfer: 0.02, parent: root)
        box(0.36, 0.09, 0.04, rear, 0.6, 0.8, -2.2, chamfer: 0.02, parent: root)
        let plate = World.pbr(UIColor(white: 0.95, alpha: 1), rough: 0.4)
        box(0.52, 0.11, 0.01, plate, 0, 0.5, 2.24, parent: root)
        root.enumerateHierarchy { n, _ in n.castsShadow = true }
        return root
    }

    private func updateCars(dt: Float) {
        for i in cars.indices {
            if !cars[i].active {
                if Float.random(in: 0...1) < dt * 0.1 {
                    cars[i].active = true
                    cars[i].dir = Bool.random() ? 1 : -1
                    cars[i].speed = Float.random(in: 8...12)
                    let z: Float = cars[i].dir > 0 ? 5.4 : 9.1
                    cars[i].node.position = SCNVector3(-cars[i].dir * 36, -0.12, z)
                    cars[i].node.eulerAngles.y = cars[i].dir > 0 ? .pi / 2 : -.pi / 2
                    cars[i].node.isHidden = false
                }
                continue
            }
            cars[i].node.position.x += cars[i].dir * cars[i].speed * dt
            if abs(cars[i].node.position.x) > 37 {
                cars[i].active = false
                cars[i].node.isHidden = true
            }
        }
    }

    // MARK: camera gestures and taps

    private var pinchStart: Float = 15
    private var rotateStart: Float = 0
    private var twoFingerStart: Float = 0.9

    private func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        let pan2 = UIPanGestureRecognizer(target: self, action: #selector(onTilt(_:)))
        pan2.minimumNumberOfTouches = 2
        pan2.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan2)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        view.addGestureRecognizer(pinch)
        let rot = UIRotationGestureRecognizer(target: self, action: #selector(onRotate(_:)))
        view.addGestureRecognizer(rot)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTapGesture(_:)))
        view.addGestureRecognizer(tap)
        for g in [pan2, pinch, rot] { g.delegate = self }
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        let k = camDist * 0.0016
        let right = SIMD3<Float>(cos(camYaw), 0, -sin(camYaw))
        let fwd = SIMD3<Float>(-sin(camYaw), 0, -cos(camYaw))
        camTarget -= right * Float(t.x) * k
        camTarget += fwd * Float(t.y) * k / max(0.4, sin(camPitch))
        camTarget.x = max(-12, min(12, camTarget.x))
        camTarget.z = max(-8, min(7, camTarget.z))
        applyCamera()
    }

    @objc private func onTilt(_ g: UIPanGestureRecognizer) {
        if g.state == .began { twoFingerStart = camPitch }
        let t = g.translation(in: view)
        camPitch = max(0.35, min(1.4, twoFingerStart + Float(t.y) * 0.004))
        applyCamera()
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .began { pinchStart = camDist }
        camDist = max(5.5, min(30, pinchStart / Float(max(0.2, g.scale))))
        applyCamera()
    }

    @objc private func onRotate(_ g: UIRotationGestureRecognizer) {
        if g.state == .began { rotateStart = camYaw }
        camYaw = max(-0.8, min(0.8, rotateStart - Float(g.rotation)))
        applyCamera()
    }

    @objc private func onTapGesture(_ g: UITapGestureRecognizer) {
        let p = g.location(in: view)
        let hits = view.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
        for h in hits {
            var n: SCNNode? = h.node
            while let cur = n {
                if let name = cur.name, name.hasPrefix("tap:") {
                    onTap?(String(name.dropFirst(4)))
                    return
                }
                n = cur.parent
            }
        }
    }
}

extension World: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
