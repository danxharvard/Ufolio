import AVFoundation

/// The Ufolio "arrival" sound: a short, wobbly, theremin-style "ooo-WEEE-ooo", in the spirit of
/// 60s–80s sci-fi. It's made from scratch here (no sound file), plays quietly once at launch,
/// and can be turned off in Settings › Appearance.
enum LaunchSound {
    /// Everything to do with the audio engine happens on this queue: starting one up takes the
    /// Mac a moment (about a fifth of a second here), and on the main thread that held up the
    /// first window at every launch.
    private static let queue = DispatchQueue(label: "ufolio.launchsound", qos: .userInitiated)
    private static var engine: AVAudioEngine?   // only touched on `queue`

    static func playIfWanted() {
        guard Prefs.bool(Prefs.launchSound) else { return }
        queue.async {
            guard let buffer = makeBuffer() else { return }
            play(buffer)
        }
    }

    private static func play(_ buffer: AVAudioPCMBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        engine.mainMixerNode.outputVolume = 0.5
        do { try engine.start() } catch { return }
        self.engine?.stop()   // one sound at a time
        self.engine = engine
        player.scheduleBuffer(buffer) {
            // Let go of the audio engine once it's finished (nothing keeps running).
            // Only this play's engine: pressing Play again in Settings started a new one, which
            // the first play's ending then stopped, cutting the second sound short.
            queue.asyncAfter(deadline: .now() + 0.3) {
                engine.stop()
                if self.engine === engine { self.engine = nil }
            }
        }
        player.play()
    }

    /// About two seconds: a glide up and back down with a dreamy vibrato, a soft echo voice an
    /// octave-and-a-bit above, and a gentle fade in and out.
    private static func makeBuffer() -> AVAudioPCMBuffer? {
        let rate = 44_100.0, duration = 2.1
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * duration)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = buffer.frameCapacity
        let frames = Int(buffer.frameLength)
        var phase = 0.0, phase2 = 0.0
        for i in 0..<frames {
            let t = Double(i) / rate
            let p = t / duration
            // The pitch path: rise from 420 Hz to 880 Hz, hang, then slide down to 560 Hz.
            let glide: Double
            if p < 0.35 { glide = 420 + (880 - 420) * smooth(p / 0.35) }
            else if p < 0.55 { glide = 880 }
            else { glide = 880 - (880 - 560) * smooth((p - 0.55) / 0.45) }
            // A slow, deepening wobble: the classic theremin vibrato.
            let vibrato = 1 + 0.035 * (0.4 + p) * sin(2 * .pi * 6.2 * t)
            let frequency = glide * vibrato
            phase += 2 * .pi * frequency / rate
            phase2 += 2 * .pi * frequency * 1.498 / rate   // a fifth above, very soft
            // Mostly a pure tone, with a touch of warmth.
            var sample = sin(phase) + 0.18 * sin(2 * phase) + 0.12 * sin(phase2)
            // Fade in over 0.15 s, out over the last 0.6 s.
            let envelope = min(1, t / 0.15) * min(1, (duration - t) / 0.6)
            sample *= 0.22 * envelope
            // A little stereo shimmer: the right side slightly behind.
            channels[0][i] = Float(sample)
            channels[1][i] = Float(sample * (0.85 + 0.15 * sin(2 * .pi * 0.8 * t)))
        }
        return buffer
    }

    private static func smooth(_ x: Double) -> Double {
        let c = max(0, min(1, x))
        return c * c * (3 - 2 * c)
    }
}
