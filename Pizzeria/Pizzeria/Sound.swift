import AVFoundation
import QuartzCore

/// Game sound. Ambience loops and one-shots are synthesised once at start-up into buffers
/// and played by AVAudioPlayerNodes (nothing is generated on the real-time audio thread).
final class Sound {
    static let shared = Sound()

    private let engine = AVAudioEngine()
    private let streetPlayer = AVAudioPlayerNode()
    private let firePlayer = AVAudioPlayerNode()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [String: CFTimeInterval] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    var muted = false {
        didSet { applyVolumes() }
    }
    /// 0…1, how loud the street is.
    var street: Float = 0.5 {
        didSet { if abs(street - oldValue) > 0.02 { applyVolumes() } }
    }
    /// 0…1, wood fire crackle (only with the wood oven).
    var fire: Float = 0 {
        didSet { if abs(fire - oldValue) > 0.02 { applyVolumes() } }
    }

    private func applyVolumes() {
        streetPlayer.volume = muted ? 0 : 0.55 * street
        firePlayer.volume = muted ? 0 : 0.5 * fire
    }

    func start() {
        guard !started else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        for p in [streetPlayer, firePlayer] {
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
        }
        for _ in 0..<4 {
            let pl = AVAudioPlayerNode()
            engine.attach(pl)
            engine.connect(pl, to: engine.mainMixerNode, format: format)
            players.append(pl)
        }
        let streetLoop = makeStreetLoop()
        let fireLoop = makeFireLoop()
        buffers["cash"] = synth(0.5) { t in
            let e = exp(-t * 10)
            return (sin(2 * .pi * 2093 * t) * 0.5 + sin(2 * .pi * 3136 * t) * 0.25 + sin(2 * .pi * 4186 * t) * 0.1) * e * 0.3
        }
        buffers["door"] = synth(1.0) { t in
            let a = sin(2 * .pi * 1318.5 * t) * exp(-t * 5)
            let t2 = max(0, t - 0.22)
            let b = t > 0.22 ? sin(2 * .pi * 1046.5 * t2) * exp(-t2 * 4.5) : 0
            return (a + b) * 0.16
        }
        buffers["coins"] = synth(0.35) { t in
            var v: Float = 0
            for (k, f) in [(0.0, 3520.0), (0.06, 4186.0), (0.13, 3729.0)] as [(Float, Float)] where t >= k {
                v += sin(2 * .pi * f * (t - k)) * exp(-(t - k) * 30)
            }
            return v * 0.15
        }
        engine.mainMixerNode.outputVolume = 0.9
        engine.prepare()
        do {
            try engine.start()
            streetPlayer.scheduleBuffer(streetLoop, at: nil, options: [.loops], completionHandler: nil)
            firePlayer.scheduleBuffer(fireLoop, at: nil, options: [.loops], completionHandler: nil)
            applyVolumes()
            streetPlayer.play()
            firePlayer.play()
            players.forEach { $0.play() }
        } catch {
            print("Sound: \(error)")
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            try? self.engine.start()
            [self.streetPlayer, self.firePlayer].forEach { $0.play() }
            self.players.forEach { $0.play() }
        }
    }

    // MARK: synthesis

    private struct Rng {
        var s: UInt32 = 0x9E37_79B9
        mutating func next() -> Float {
            s ^= s << 13
            s ^= s >> 17
            s ^= s << 5
            return Float(s) / Float(UInt32.max) * 2 - 1
        }
    }

    private func buffer(_ frames: Int) -> (AVAudioPCMBuffer, UnsafeMutablePointer<Float>) {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        b.frameLength = AVAudioFrameCount(frames)
        return (b, b.floatChannelData![0])
    }

    /// Makes the end of a loop fade into its start so it repeats without a click.
    private func seamless(_ d: UnsafeMutablePointer<Float>, frames: Int, fade: Int) {
        for i in 0..<fade {
            let t = Float(i) / Float(fade)
            d[i] = d[i] * t + d[frames - fade + i] * (1 - t)
        }
    }

    /// 12 s of distant traffic: soft low rumble with a couple of passing cars.
    private func makeStreetLoop() -> AVAudioPCMBuffer {
        let sr = Int(format.sampleRate)
        let total = sr * 12, fade = sr / 2
        var rng = Rng()
        var tmp = [Float](repeating: 0, count: total + fade)
        var lp1: Float = 0, lp2: Float = 0, hp: Float = 0
        let cars: [(Float, Float)] = [(2.5, 3.2), (7.0, 4.0), (10.5, 2.6)]   // centre (s), width (s)
        for i in 0..<tmp.count {
            let t = Float(i) / Float(sr)
            let w = rng.next()
            lp1 += 0.035 * (w - lp1)
            lp2 += 0.035 * (lp1 - lp2)
            hp = lp2
            var swell: Float = 0.35
            for (c, width) in cars {
                let x = (t - c) / width
                swell += 0.9 * exp(-x * x * 4)
            }
            tmp[i] = hp * 3.2 * swell
        }
        let (b, d) = buffer(total + fade)
        for i in 0..<(total + fade) { d[i] = max(-0.9, min(0.9, tmp[i])) }
        seamless(d, frames: total + fade, fade: fade)
        b.frameLength = AVAudioFrameCount(total)
        return b
    }

    /// 6 s of a wood fire: soft hiss with gentle crackles.
    private func makeFireLoop() -> AVAudioPCMBuffer {
        let sr = Int(format.sampleRate)
        let total = sr * 6, fade = sr / 3
        var rng = Rng(s: 0x1234_5678)
        let (b, d) = buffer(total + fade)
        var crack: Float = 0, lp: Float = 0, hiss: Float = 0
        for i in 0..<(total + fade) {
            if abs(rng.next()) > 0.99975 { crack = rng.next() * 0.35 }
            crack *= 0.992
            lp += 0.25 * (crack - lp)
            let w = rng.next()
            hiss += 0.3 * (w - hiss)
            d[i] = lp * 0.8 + hiss * 0.015
        }
        seamless(d, frames: total + fade, fade: fade)
        b.frameLength = AVAudioFrameCount(total)
        return b
    }

    private func synth(_ seconds: Double, _ f: (Float) -> Float) -> AVAudioPCMBuffer {
        let frames = Int(seconds * format.sampleRate)
        let (b, d) = buffer(frames)
        for i in 0..<frames {
            let t = Float(i) / Float(format.sampleRate)
            let fadeOut = min(1, Float(frames - i) / 400)
            d[i] = f(t) * fadeOut
        }
        return b
    }

    /// Plays a one-shot; the same sound is not repeated more often than `minGap` seconds.
    func play(_ name: String, volume: Float = 1, minGap: CFTimeInterval = 0.35) {
        guard started, !muted, let b = buffers[name], engine.isRunning, !players.isEmpty else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[name], now - last < minGap { return }
        lastPlayed[name] = now
        let p = players[next % players.count]
        next += 1
        p.volume = volume
        p.scheduleBuffer(b, at: nil, options: [.interrupts], completionHandler: nil)
        if !p.isPlaying { p.play() }
    }
}
