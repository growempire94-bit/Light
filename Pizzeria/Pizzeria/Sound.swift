import AVFoundation

/// Procedural sound: street ambience, wood-fire crackle and a few one-shots
/// (till, door chime, UI tap). Everything is synthesised at start-up, no audio files.
final class Sound {
    static let shared = Sound()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    // Parameters read by the render callback (written from the main thread).
    private final class Params {
        var street: Float = 0.5
        var fire: Float = 0
        var muted = false
    }
    private let params = Params()

    var street: Float {
        get { params.street }
        set { params.street = max(0, min(1, newValue)) }
    }
    var fire: Float {
        get { params.fire }
        set { params.fire = max(0, min(1, newValue)) }
    }
    var muted: Bool {
        get { params.muted }
        set { params.muted = newValue }
    }

    func start() {
        guard !started else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let p = params
        var brown: Float = 0
        var lp: Float = 0
        var swell: Float = 0
        var swellTarget: Float = 0
        var swellTimer = 0
        var crackle: Float = 0
        var crackleLP: Float = 0
        var seed: UInt32 = 0x1234_5678
        func rnd() -> Float {
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            return Float(seed) / Float(UInt32.max) * 2 - 1
        }
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
            let buf = UnsafeMutableAudioBufferListPointer(abl)
            guard let out = buf.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = Int(frameCount)
            let street = p.muted ? 0 : p.street
            let fire = p.muted ? 0 : p.fire
            for i in 0..<n {
                // Distant traffic: brown noise, low-passed, with slow swells of passing cars.
                let w = rnd()
                brown = (brown + 0.02 * w) * 0.998
                lp += 0.05 * (brown - lp)
                swellTimer -= 1
                if swellTimer <= 0 {
                    swellTimer = 44_100 * Int(3 + abs(rnd()) * 6)
                    swellTarget = abs(rnd()) < 0.55 ? 1 : 0.2
                }
                swell += (swellTarget - swell) * 0.00003
                var s = lp * (0.9 + 2.2 * swell) * 1.6 * street
                // Wood fire: sparse crackles over a soft hiss.
                if fire > 0.01 {
                    if abs(rnd()) > 0.9993 { crackle = rnd() * 0.9 }
                    crackle *= 0.985
                    crackleLP += 0.6 * (crackle - crackleLP)
                    s += (crackleLP * 0.5 + rnd() * 0.004) * fire
                }
                out[i] = max(-1, min(1, s))
            }
            for b in buf.dropFirst() {
                if let d = b.mData { memcpy(d, out, n * MemoryLayout<Float>.size) }
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        for _ in 0..<6 {
            let pl = AVAudioPlayerNode()
            engine.attach(pl)
            engine.connect(pl, to: engine.mainMixerNode, format: format)
            players.append(pl)
        }
        buffers["cash"] = synth(0.55) { t in
            let e = exp(-t * 9)
            return (sin(2 * .pi * 2093 * t) * 0.5 + sin(2 * .pi * 3136 * t) * 0.3 + sin(2 * .pi * 4186 * t) * 0.12) * e * 0.35
                + (t < 0.012 ? Float.random(in: -1...1) * 0.3 * (1 - t / 0.012) : 0)
        }
        buffers["door"] = synth(1.1) { t in
            let a = sin(2 * .pi * 1318.5 * t) * exp(-t * 4.5)
            let t2 = max(0, t - 0.22)
            let b = t > 0.22 ? sin(2 * .pi * 1046.5 * t2) * exp(-t2 * 4) : 0
            return (a + b) * 0.22
        }
        buffers["tap"] = synth(0.06) { t in sin(2 * .pi * 900 * t) * exp(-t * 80) * 0.25 }
        buffers["coins"] = synth(0.35) { t in
            var v: Float = 0
            for (k, f) in [(0.0, 3520.0), (0.06, 4186.0), (0.13, 3729.0)] as [(Float, Float)] where t >= k {
                v += sin(2 * .pi * f * (t - k)) * exp(-(t - k) * 30)
            }
            return v * 0.18
        }
        engine.mainMixerNode.outputVolume = 0.8
        do {
            try engine.start()
            players.forEach { $0.play() }
        } catch {
            print("Sound: \(error)")
        }
    }

    private func synth(_ seconds: Double, _ f: (Float) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        b.frameLength = frames
        let d = b.floatChannelData![0]
        for i in 0..<Int(frames) {
            d[i] = f(Float(i) / Float(format.sampleRate))
        }
        return b
    }

    func play(_ name: String, volume: Float = 1) {
        guard started, !params.muted, let b = buffers[name], engine.isRunning, !players.isEmpty else { return }
        let p = players[next % players.count]
        next += 1
        p.volume = volume
        p.scheduleBuffer(b, at: nil, options: [], completionHandler: nil)
        if !p.isPlaying { p.play() }
    }
}
