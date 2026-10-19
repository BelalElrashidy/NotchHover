import Foundation

/// The level meter's band split, on pure tones: --levels-selftest
enum LevelsSelfTest {
    static func run() {
        var results: [String] = []
        func expect(_ label: String, _ condition: Bool) {
            results.append((condition ? "✓ " : "✗ ") + label)
        }

        func bands(frequency: Double, amplitude: Float = 0.5, seconds: Double = 0.5) -> [Float] {
            let analyzer = BandAnalyzer()
            let rate = 48_000.0
            let samples = (0..<Int(rate * seconds)).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
            samples.withUnsafeBufferPointer { buffer in
                // In the 512-frame blocks a tap delivers.
                stride(from: 0, to: buffer.count, by: 512).forEach { start in
                    analyzer.process(buffer.baseAddress! + start, count: min(512, buffer.count - start), sampleRate: rate)
                }
            }
            return analyzer.read().bands
        }
        func show(_ b: [Float]) -> String { b.map { String(format: "%.2f", $0) }.joined(separator: " ") }

        let bass = bands(frequency: 60), voice = bands(frequency: 1000), cymbal = bands(frequency: 9000)
        expect("60 Hz lifts the low bar most (\(show(bass)))", bass[0] > bass[1] && bass[0] > bass[2])
        expect("1 kHz lifts the middle (\(show(voice)))", voice[1] > voice[0] && voice[1] > voice[2])
        expect("9 kHz lifts the high bar (\(show(cymbal)))", cymbal[2] > cymbal[0] && cymbal[2] > cymbal[1])
        let quiet = bands(frequency: 1000, amplitude: 0.01)
        expect("quieter is lower (\(show(quiet)))", quiet[1] < voice[1])
        let silence = bands(frequency: 1000, amplitude: 0)
        expect("silence is zero, and reads as silence", silence.allSatisfy { $0 == 0 })

        let failed = results.filter { $0.hasPrefix("✗") }.count
        FileHandle.standardError.write(Data(("levels: " + results.joined(separator: "  ") + "\n").utf8))
        exit(failed == 0 ? 0 : 1)
    }
}
