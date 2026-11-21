import Foundation

/// Generates sounds in memory as WAV data, so the app doesn't need audio files.
enum ToneGenerator {
    static let sampleRate = 44_100

    /// Loud two-tone siren (sweeps 650 → 1550 → 650 Hz), meant to be looped.
    static func sirenWAV() -> Data {
        let duration = 1.2
        let count = Int(Double(sampleRate) * duration)
        let half = duration / 2
        let fade = 0.004 // short fade at the edges to avoid clicks between loops
        var samples = [Int16](repeating: 0, count: count)
        var phase = 0.0
        let twoPi = 2.0 * Double.pi

        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let progress = t < half ? t / half : (duration - t) / half
            let frequency = 650.0 + 900.0 * progress
            phase += twoPi * frequency / Double(sampleRate)
            if phase > twoPi { phase -= twoPi }

            // Soft-clipped sine ≈ square wave: much louder to the ear than a pure tone.
            var value = tanh(4.0 * sin(phase))

            let edge = min(t, duration - t)
            if edge < fade { value *= edge / fade }

            samples[i] = Int16(value * 0.98 * Double(Int16.max))
        }
        return wav(samples)
    }

    /// Silence used to keep the audio session (and the app) alive in the background.
    static func silenceWAV(seconds: Double = 2) -> Data {
        let count = Int(Double(sampleRate) * seconds)
        return wav([Int16](repeating: 0, count: count))
    }

    /// 16-bit mono PCM WAV container.
    private static func wav(_ samples: [Int16]) -> Data {
        var data = Data()

        func append32(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        let dataSize = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)                       // fmt chunk size
        append16(1)                        // PCM
        append16(1)                        // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))   // byte rate
        append16(2)                        // block align
        append16(16)                       // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append32(dataSize)
        for sample in samples {
            append16(UInt16(bitPattern: sample))
        }
        return data
    }
}
