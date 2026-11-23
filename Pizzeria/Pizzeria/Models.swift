import SceneKit
import UIKit

/// Geometry helpers.
enum Geo {
    /// A box centred at the origin with UVs in (metres / tile), normals and tangents,
    /// so tiling PBR materials keep their real-world scale on any size of box.
    static func box(_ w: Float, _ h: Float, _ l: Float, tile: Float = 1, uvOffset: SIMD2<Float> = .zero) -> SCNGeometry {
        let hx = w / 2, hy = h / 2, hz = l / 2
        // normal, U axis, V axis (U × V = normal)
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)),
            (SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, 1, 0)),
            (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0)),
            (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1)),
            (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
        ]
        let half = SIMD3<Float>(hx, hy, hz)
        var pos: [Float] = [], nrm: [Float] = [], uv: [Float] = [], tan: [Float] = []
        var idx: [UInt16] = []
        for (n, u, v) in faces {
            let base = UInt16(pos.count / 3)
            let hn = simd_dot(simd_abs(n), half), hu = simd_dot(simd_abs(u), half), hv = simd_dot(simd_abs(v), half)
            for (su, sv) in [(Float(-1), Float(-1)), (1, -1), (1, 1), (-1, 1)] {
                let p = n * hn + u * (su * hu) + v * (sv * hv)
                pos += [p.x, p.y, p.z]
                nrm += [n.x, n.y, n.z]
                uv += [simd_dot(p, u) / tile + uvOffset.x, -simd_dot(p, v) / tile + uvOffset.y]
                tan += [u.x, u.y, u.z, 1]
            }
            idx += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        func src(_ a: [Float], _ sem: SCNGeometrySource.Semantic, _ comps: Int) -> SCNGeometrySource {
            let d = a.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(data: d, semantic: sem, vectorCount: a.count / comps, usesFloatComponents: true,
                                     componentsPerVector: comps, bytesPerComponent: 4, dataOffset: 0, dataStride: comps * 4)
        }
        let el = SCNGeometryElement(data: idx.withUnsafeBufferPointer { Data(buffer: $0) }, primitiveType: .triangles,
                                    primitiveCount: idx.count / 3, bytesPerIndex: 2)
        return SCNGeometry(sources: [src(pos, .vertex, 3), src(nrm, .normal, 3), src(uv, .texcoord, 2), src(tan, .tangent, 4)], elements: [el])
    }
}

/// Loads the converted Poly Haven assets (see tools/phconvert.py) and PBR surface sets.
enum Assets {
    private struct Manifest: Decodable {
        struct Mat: Decodable {
            let name: String
            let diffuse: String?
            let normal: String?
            let arm: String?
            let ao: String?
            let color: [Double]
            let metal: Double
            let rough: Double
            let alpha: String
            let doubleSided: Bool
        }
        let materials: [Mat]
        let parts: [String]
    }

    private static var prototypes: [String: [String: SCNNode]] = [:]
    private static var images: [String: UIImage] = [:]
    private static var surfaces: [String: SCNMaterial] = [:]

    static func image(_ file: String) -> UIImage? {
        if let i = images[file] { return i }
        guard let path = Bundle.main.path(forResource: file, ofType: nil), let img = UIImage(contentsOfFile: path) else { return nil }
        images[file] = img
        return img
    }

    static func url(_ file: String) -> URL? { Bundle.main.url(forResource: file, withExtension: nil) }

    private static func setup(_ p: SCNMaterialProperty, repeatable: Bool = true) {
        p.mipFilter = .linear
        p.minificationFilter = .linear
        p.magnificationFilter = .linear
        p.maxAnisotropy = 8
        if repeatable {
            p.wrapS = .repeat
            p.wrapT = .repeat
        }
    }

    /// A tiling PBR material from a Poly Haven texture set (`<id>_diff/nor/arm.jpg`).
    /// `scale` = metres covered by one texture tile (applied by `World.uvBox` geometry in metres).
    static func surface(_ id: String, tint: UIColor? = nil, roughness: CGFloat? = nil, metal: CGFloat = 0, normal: CGFloat = 1) -> SCNMaterial {
        let key = "\(id)|\(tint?.description ?? "")|\(roughness ?? -1)|\(metal)|\(normal)"
        if let m = surfaces[key] { return m }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image("\(id)_diff.jpg") ?? UIColor.gray
        setup(m.diffuse)
        if let n = image("\(id)_nor.jpg") {
            m.normal.contents = n
            m.normal.intensity = normal
            setup(m.normal)
        }
        if let arm = image("\(id)_arm.jpg") {
            if let r = roughness {
                m.roughness.contents = r
            } else {
                m.roughness.contents = arm
                m.roughness.textureComponents = .green
                setup(m.roughness)
            }
            m.ambientOcclusion.contents = arm
            m.ambientOcclusion.textureComponents = .red
            setup(m.ambientOcclusion)
        } else {
            m.roughness.contents = roughness ?? 0.8
        }
        m.metalness.contents = metal
        if let t = tint { m.multiply.contents = t }
        surfaces[key] = m
        return m
    }

    /// A clone of a converted model (geometry and materials are shared between clones).
    static func model(_ id: String, part: String = "root") -> SCNNode {
        if prototypes[id] == nil { load(id) }
        guard let proto = prototypes[id]?[part] else {
            let n = SCNNode()
            n.name = "missing:\(id)/\(part)"
            return n
        }
        return proto.clone()
    }

    static func hasModel(_ id: String) -> Bool { url("\(id).mesh") != nil }

    /// Local bounds of a model part (union of its primitives).
    static func bounds(_ id: String, part: String = "root") -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        if prototypes[id] == nil { load(id) }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for c in prototypes[id]?[part]?.childNodes ?? [] {
            guard let g = c.geometry else { continue }
            let (a, b) = g.boundingBox
            lo = simd_min(lo, SIMD3(a.x, a.y, a.z))
            hi = simd_max(hi, SIMD3(b.x, b.y, b.z))
        }
        if lo.x > hi.x { return (.zero, .zero) }
        return (lo, hi)
    }

    /// Replace materials whose name contains `match` on a private copy of the node's geometries.
    static func override(_ node: SCNNode, where match: (String) -> Bool, with mat: SCNMaterial) {
        node.enumerateHierarchy { n, _ in
            guard let g = n.geometry, let name = g.firstMaterial?.name, match(name) else { return }
            let copy = g.copy() as! SCNGeometry
            copy.materials = [mat]
            n.geometry = copy
        }
    }

    /// Material of a loaded model by (partial) name, shared by every clone of that model.
    static func sharedMaterial(_ id: String, named match: String) -> SCNMaterial? {
        if prototypes[id] == nil { load(id) }
        for (_, p) in prototypes[id] ?? [:] {
            for c in p.childNodes {
                if let m = c.geometry?.firstMaterial, m.name?.contains(match) == true { return m }
            }
        }
        return nil
    }

    private static func material(_ m: Manifest.Mat, model: String) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.name = m.name
        let c = m.color
        let base = UIColor(red: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: 1)
        if let d = m.diffuse, let img = image(d) {
            mat.diffuse.contents = img
            setup(mat.diffuse)
            if c[0] < 0.999 || c[1] < 0.999 || c[2] < 0.999 { mat.multiply.contents = base }
        } else {
            mat.diffuse.contents = base
        }
        if let n = m.normal, let img = image(n) {
            mat.normal.contents = img
            setup(mat.normal)
        }
        if let a = m.arm, let img = image(a) {
            mat.roughness.contents = img
            mat.roughness.textureComponents = .green
            mat.roughness.intensity = CGFloat(m.rough)
            setup(mat.roughness)
            mat.metalness.contents = img
            mat.metalness.textureComponents = .blue
            mat.metalness.intensity = CGFloat(m.metal)
            setup(mat.metalness)
            if a.contains("_arm") {
                mat.ambientOcclusion.contents = img
                mat.ambientOcclusion.textureComponents = .red
                setup(mat.ambientOcclusion)
            }
        } else {
            mat.roughness.contents = CGFloat(m.rough)
            mat.metalness.contents = CGFloat(m.metal)
        }
        mat.isDoubleSided = m.doubleSided
        let lower = m.name.lowercased()
        if lower.contains("glass") || m.alpha == "BLEND" {
            if model == "facade" {
                // Windows of the neighbouring buildings: dark, reflective, opaque.
                mat.diffuse.contents = UIColor(red: 0.05, green: 0.07, blue: 0.08, alpha: 1)
                mat.multiply.contents = nil
                mat.roughness.contents = 0.06
                mat.metalness.contents = 0.0
                mat.normal.contents = nil
            } else {
                mat.diffuse.contents = UIColor(white: 0.9, alpha: 1)
                mat.multiply.contents = nil
                mat.roughness.contents = 0.05
                mat.metalness.contents = 0.0
                mat.normal.contents = nil
                mat.transparency = CGFloat(c.count > 3 && c[3] < 0.99 ? max(0.15, c[3] * 0.5) : 0.25)
                mat.blendMode = .alpha
                mat.writesToDepthBuffer = false
                mat.isDoubleSided = true
            }
        }
        return mat
    }

    private static func load(_ id: String) {
        prototypes[id] = [:]
        guard let murl = url("\(id).mesh"), let jurl = url("\(id).json"),
              let data = try? Data(contentsOf: murl, options: .alwaysMapped),
              let jdata = try? Data(contentsOf: jurl),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: jdata) else {
            print("Assets: cannot load \(id)")
            return
        }
        let mats = manifest.materials.map { material($0, model: id) }
        var off = 0
        func u8() -> Int { defer { off += 1 }; return Int(data[off]) }
        func u16() -> Int { defer { off += 2 }; return Int(data[off]) | Int(data[off + 1]) << 8 }
        func u32() -> Int {
            defer { off += 4 }
            return Int(data[off]) | Int(data[off + 1]) << 8 | Int(data[off + 2]) << 16 | Int(data[off + 3]) << 24
        }
        func chunk(_ n: Int) -> Data {
            defer { off += n }
            return data.subdata(in: off..<(off + n))
        }
        guard data.count > 8, String(data: data.subdata(in: 0..<4), encoding: .ascii) == "PZM2" else { return }
        off = 4
        let partCount = u32()
        var result: [String: SCNNode] = [:]
        for _ in 0..<partCount {
            let nameLen = u16()
            let name = String(data: chunk(nameLen), encoding: .utf8) ?? "root"
            let primCount = u32()
            let root = SCNNode()
            root.name = "\(id)/\(name)"
            for _ in 0..<primCount {
                let mi = u32()
                let vc = u32()
                let ic = u32()
                let flags = u8()
                let ib = u8()
                _ = u16()
                var sources: [SCNGeometrySource] = []
                sources.append(SCNGeometrySource(data: chunk(vc * 12), semantic: .vertex, vectorCount: vc, usesFloatComponents: true,
                                                 componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12))
                sources.append(SCNGeometrySource(data: chunk(vc * 12), semantic: .normal, vectorCount: vc, usesFloatComponents: true,
                                                 componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12))
                if flags & 1 != 0 {
                    sources.append(SCNGeometrySource(data: chunk(vc * 8), semantic: .texcoord, vectorCount: vc, usesFloatComponents: true,
                                                     componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8))
                }
                if flags & 2 != 0 {
                    sources.append(SCNGeometrySource(data: chunk(vc * 16), semantic: .tangent, vectorCount: vc, usesFloatComponents: true,
                                                     componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16))
                }
                let element = SCNGeometryElement(data: chunk(ic * ib), primitiveType: .triangles, primitiveCount: ic / 3, bytesPerIndex: ib)
                let geo = SCNGeometry(sources: sources, elements: [element])
                geo.firstMaterial = mi < mats.count ? mats[mi] : SCNMaterial()
                let n = SCNNode(geometry: geo)
                n.castsShadow = true
                root.addChildNode(n)
            }
            result[name] = root
        }
        prototypes[id] = result
    }
}
