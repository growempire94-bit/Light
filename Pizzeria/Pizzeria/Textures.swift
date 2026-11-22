import UIKit

/// Procedural textures, so the game ships without image assets.
enum Tex {
    // MARK: noise helpers

    private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 1_442_695_041)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65_535
    }

    /// Smooth value noise in 0…1.
    static func noise(_ x: Float, _ y: Float, _ seed: Int) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Float(xi), yf = y - Float(yi)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi, seed), b = hash(xi + 1, yi, seed)
        let c = hash(xi, yi + 1, seed), d = hash(xi + 1, yi + 1, seed)
        return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v
    }

    static func fbm(_ x: Float, _ y: Float, _ seed: Int) -> Float {
        noise(x, y, seed) * 0.55 + noise(x * 2.1, y * 2.1, seed + 7) * 0.3 + noise(x * 4.3, y * 4.3, seed + 13) * 0.15
    }

    private static func clamp8(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v * 255))) }

    /// Builds an RGB image pixel by pixel. `f` returns components in 0…1.
    static func pixels(_ w: Int, _ h: Int, _ f: (Int, Int) -> (Float, Float, Float)) -> UIImage {
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let c = f(x, y)
                let i = (y * w + x) * 4
                data[i] = clamp8(c.0)
                data[i + 1] = clamp8(c.1)
                data[i + 2] = clamp8(c.2)
            }
        }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: image)
    }

    static func draw(_ w: Int, _ h: Int, _ body: (CGContext, CGSize) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: w, height: h)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            body(ctx.cgContext, size)
        }
    }

    // MARK: surfaces

    /// Oak floor planks, 8 planks across the texture.
    static func woodFloor(seed: Int = 1, dark: Bool = false) -> UIImage {
        let w = 512, h = 512, plankW = 64
        return pixels(w, h) { x, y in
            let col = x / plankW
            let plankLen = 180 + Int(hash(col, 0, seed) * 200)
            let offset = Int(hash(col, 1, seed) * Float(plankLen))
            let row = (y + offset) / plankLen
            let tone = hash(col, row, seed + 3)
            let lx = Float(x % plankW), ly = Float((y + offset) % plankLen)
            let grain = sin((lx * 0.35 + fbm(lx * 0.05, ly * 0.012, seed + row) * 9) ) * 0.5 + 0.5
            let fine = noise(Float(x) * 0.6, Float(y) * 0.08, seed + 5)
            var base: (Float, Float, Float) = dark ? (0.30, 0.19, 0.11) : (0.56, 0.38, 0.22)
            let k = 0.78 + tone * 0.34 - grain * 0.10 - fine * 0.06
            base = (base.0 * k, base.1 * k, base.2 * k)
            let gapX = x % plankW < 2
            let gapY = (y + offset) % plankLen < 2
            if gapX || gapY { return (base.0 * 0.35, base.1 * 0.35, base.2 * 0.35) }
            return base
        }
    }

    /// Red brick wall with mortar.
    static func bricks(seed: Int = 2) -> UIImage {
        let w = 512, h = 512, bw = 64, bh = 28, mortar = 3
        return pixels(w, h) { x, y in
            let row = y / bh
            let shift = row % 2 == 0 ? 0 : bw / 2
            let col = (x + shift) / bw
            let lx = (x + shift) % bw, ly = y % bh
            let n = fbm(Float(x) * 0.08, Float(y) * 0.08, seed)
            if lx < mortar || ly < mortar {
                let m = 0.62 + n * 0.12
                return (m, m * 0.97, m * 0.92)
            }
            let t = hash(col, row, seed)
            let r: Float = 0.52 + t * 0.16 - n * 0.10
            return (r, r * 0.42 + t * 0.04, r * 0.32)
        }
    }

    /// Warm plaster with subtle stains.
    static func plaster(r: Float, g: Float, b: Float, seed: Int = 3) -> UIImage {
        pixels(256, 256) { x, y in
            let n = fbm(Float(x) * 0.03, Float(y) * 0.03, seed) * 0.08 + noise(Float(x) * 0.5, Float(y) * 0.5, seed + 1) * 0.03
            let k = 0.95 + n
            return (r * k, g * k, b * k)
        }
    }

    /// Square ceramic tiles.
    static func tiles(r: Float, g: Float, b: Float, tile: Int = 64, seed: Int = 4) -> UIImage {
        pixels(512, 512) { x, y in
            if x % tile < 2 || y % tile < 2 { return (0.42, 0.42, 0.42) }
            let t = hash(x / tile, y / tile, seed) * 0.06
            let n = noise(Float(x) * 0.2, Float(y) * 0.2, seed) * 0.03
            let k = 0.96 + t + n
            return (r * k, g * k, b * k)
        }
    }

    static func asphalt(seed: Int = 5) -> UIImage {
        pixels(512, 512) { x, y in
            let speck = hash(x, y, seed)
            let n = fbm(Float(x) * 0.02, Float(y) * 0.02, seed + 1)
            var v: Float = 0.19 + n * 0.06
            if speck > 0.93 { v += 0.12 } else if speck < 0.05 { v -= 0.06 }
            return (v, v, v * 1.03)
        }
    }

    /// Grey pavement slabs (тротуарная плитка).
    static func paving(seed: Int = 6) -> UIImage {
        let s = 64
        return pixels(512, 512) { x, y in
            if x % s < 3 || y % s < 3 { return (0.33, 0.33, 0.32) }
            let t = hash(x / s, y / s, seed) * 0.08
            let n = noise(Float(x) * 0.3, Float(y) * 0.3, seed) * 0.05
            let v: Float = 0.58 + t + n
            return (v, v * 0.99, v * 0.96)
        }
    }

    static func stainless() -> UIImage {
        pixels(256, 256) { x, y in
            let streak = noise(Float(x) * 0.02, Float(y) * 1.5, 9) * 0.08
            let v: Float = 0.72 + streak
            return (v, v, v * 1.02)
        }
    }

    static func cardboard() -> UIImage {
        draw(256, 256) { c, size in
            UIColor(red: 0.74, green: 0.58, blue: 0.40, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            let text = "PIZZA" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 46, weight: .black),
                .foregroundColor: UIColor(red: 0.62, green: 0.10, blue: 0.08, alpha: 1),
            ]
            let ts = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
        }
    }

    static func pizzaTop() -> UIImage {
        draw(256, 256) { c, size in
            UIColor(red: 0.80, green: 0.55, blue: 0.27, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.78, green: 0.22, blue: 0.12, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 22, y: 22, width: 212, height: 212))
            for i in 0..<26 {
                let a = Float(i) * 2.399
                let r = 20 + Float(i % 7) * 13
                let px = 128 + CGFloat(cos(a) * r), py = 128 + CGFloat(sin(a) * r)
                UIColor(red: 0.98, green: 0.90, blue: 0.66, alpha: 0.95).setFill()
                c.fillEllipse(in: CGRect(x: px - 14, y: py - 12, width: 28, height: 24))
            }
            for i in 0..<10 {
                let a = Float(i) * 0.63 + 0.3
                let r: Float = 30 + Float(i % 3) * 28
                UIColor(red: 0.62, green: 0.12, blue: 0.10, alpha: 1).setFill()
                c.fillEllipse(in: CGRect(x: 128 + CGFloat(cos(a) * r) - 11, y: 128 + CGFloat(sin(a) * r) - 11, width: 22, height: 22))
            }
        }
    }

    /// Facade of a neighbouring building: plaster with windows.
    static func facade(r: CGFloat, g: CGFloat, b: CGFloat, floors: Int, seed: Int) -> UIImage {
        draw(512, 512) { c, size in
            UIColor(red: r, green: g, blue: b, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            let fh = size.height / CGFloat(floors)
            for f in 0..<floors {
                for i in 0..<4 {
                    let x = CGFloat(i) * size.width / 4 + 26
                    let y = CGFloat(f) * fh + fh * 0.22
                    let rect = CGRect(x: x, y: y, width: size.width / 4 - 52, height: fh * 0.58)
                    UIColor(white: 0.93, alpha: 1).setFill()
                    c.fill(rect.insetBy(dx: -5, dy: -5))
                    let lit = hash(f, i, seed) > 0.7
                    (lit ? UIColor(red: 0.42, green: 0.40, blue: 0.33, alpha: 1) : UIColor(red: 0.18, green: 0.22, blue: 0.27, alpha: 1)).setFill()
                    c.fill(rect)
                    UIColor(white: 0.93, alpha: 1).setFill()
                    c.fill(CGRect(x: rect.midX - 2, y: rect.minY, width: 4, height: rect.height))
                    c.fill(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.38, width: rect.width, height: 4))
                    UIColor(white: 0.5, alpha: 1).setFill()
                    c.fill(CGRect(x: rect.minX - 8, y: rect.maxY + 5, width: rect.width + 16, height: 6))
                }
            }
        }
    }

    // MARK: signs & boards

    static func menuBoard(lines: [(String, String)]) -> UIImage {
        draw(1024, 640) { c, size in
            UIColor(red: 0.11, green: 0.12, blue: 0.11, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            for i in 0..<1400 {
                let x = CGFloat(hash(i, 1, 77)) * size.width, y = CGFloat(hash(i, 2, 77)) * size.height
                UIColor(white: 1, alpha: 0.025).setFill()
                c.fill(CGRect(x: x, y: y, width: 3, height: 3))
            }
            let title = "МЕНЮ" as NSString
            let tAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 74, weight: .heavy),
                .foregroundColor: UIColor(red: 0.98, green: 0.84, blue: 0.40, alpha: 1),
            ]
            let tSize = title.size(withAttributes: tAttrs)
            title.draw(at: CGPoint(x: (size.width - tSize.width) / 2, y: 28), withAttributes: tAttrs)
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .semibold),
                .foregroundColor: UIColor(white: 0.94, alpha: 1),
            ]
            let priceAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 44, weight: .bold),
                .foregroundColor: UIColor(red: 0.98, green: 0.84, blue: 0.40, alpha: 1),
            ]
            var y: CGFloat = 140
            for (name, price) in lines.prefix(7) {
                (name as NSString).draw(at: CGPoint(x: 60, y: y), withAttributes: nameAttrs)
                let p = price as NSString
                let ps = p.size(withAttributes: priceAttrs)
                p.draw(at: CGPoint(x: size.width - 60 - ps.width, y: y), withAttributes: priceAttrs)
                y += 66
            }
        }
    }

    static func sign(_ text: String, lit: Bool) -> UIImage {
        draw(1024, 256) { c, size in
            (lit ? UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1) : UIColor(white: 0.95, alpha: 1)).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: lit ? 150 : 96, weight: .black),
                .foregroundColor: lit ? UIColor(red: 1.0, green: 0.80, blue: 0.35, alpha: 1) : UIColor(red: 0.70, green: 0.12, blue: 0.10, alpha: 1),
                .kern: lit ? 10 : 2,
            ]
            let s = text as NSString
            let ts = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
        }
    }

    static func billboard() -> UIImage {
        draw(1024, 512) { c, size in
            let colors = [UIColor(red: 0.62, green: 0.08, blue: 0.07, alpha: 1).cgColor,
                          UIColor(red: 0.95, green: 0.42, blue: 0.10, alpha: 1).cgColor]
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor(red: 0.85, green: 0.55, blue: 0.27, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 620, y: 70, width: 380, height: 380))
            UIColor(red: 0.80, green: 0.20, blue: 0.10, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 650, y: 100, width: 320, height: 320))
            let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 92, weight: .black), .foregroundColor: UIColor.white]
            ("Горячая пицца" as NSString).draw(at: CGPoint(x: 50, y: 120), withAttributes: a)
            let b: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 54, weight: .bold), .foregroundColor: UIColor(white: 1, alpha: 0.9)]
            ("100 метров отсюда" as NSString).draw(at: CGPoint(x: 54, y: 260), withAttributes: b)
        }
    }

    static func windowDecal() -> UIImage {
        draw(512, 256) { c, size in
            UIColor(white: 0, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 58, weight: .black),
                                                    .foregroundColor: UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1)]
            ("ПИЦЦА · КОФЕ" as NSString).draw(at: CGPoint(x: 40, y: 90), withAttributes: a)
        }
    }

    // MARK: sky

    /// Equirectangular sky for background and image-based lighting.
    static func sky(sunHeight: Float, night: Float) -> UIImage {
        draw(512, 256) { c, size in
            func mix(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat), _ t: CGFloat) -> UIColor {
                UIColor(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t, alpha: 1)
            }
            let n = CGFloat(max(0, min(1, night)))
            let dusk = CGFloat(max(0, 1 - abs(sunHeight) * 4)) * (1 - n)
            let zenith = mix(mix((0.24, 0.48, 0.82), (0.22, 0.30, 0.55), dusk).rgb, (0.02, 0.03, 0.07), n)
            let horizon = mix(mix((0.70, 0.82, 0.93), (0.98, 0.62, 0.38), dusk).rgb, (0.08, 0.09, 0.14), n)
            let ground = mix((0.30, 0.30, 0.30), (0.03, 0.03, 0.04), n)
            let colors = [zenith.cgColor, horizon.cgColor, ground.cgColor, ground.cgColor]
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.49, 0.52, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
}

private extension UIColor {
    var rgb: (CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }
}
