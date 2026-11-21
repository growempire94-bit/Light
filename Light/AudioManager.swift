import AVFoundation
import AudioToolbox
import Foundation

/// Two jobs:
/// 1. Keep the app alive in the background by looping silence
///    (UIBackgroundModes = audio). Without this iOS suspends the app
///    within seconds and it can't react to Wi‑Fi changes.
/// 2. Play the loud alarm. Category `.playback` ignores the silent switch.
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    @Published private(set) var isAlarmPlaying = false
    @Published private(set) var keepAliveActive = false

    private var silentPlayer: AVAudioPlayer?
    private var alarmPlayer: AVAudioPlayer?
    private var alarmStopWork: DispatchWorkItem?
    private var vibrateTimer: Timer?
    private var observersInstalled = false

    private init() {}

    // MARK: - Background keep-alive

    func startKeepAlive() {
        installObservers()
        configureSession(forAlarm: isAlarmPlaying)

        if silentPlayer == nil {
            silentPlayer = try? AVAudioPlayer(data: ToneGenerator.silenceWAV())
            silentPlayer?.numberOfLoops = -1
            silentPlayer?.volume = 0
            silentPlayer?.prepareToPlay()
        }
        if silentPlayer?.isPlaying != true {
            silentPlayer?.play()
        }
        keepAliveActive = silentPlayer?.isPlaying == true
    }

    /// Called periodically and when the app becomes active.
    func ensureKeepAlive() {
        if silentPlayer?.isPlaying != true {
            startKeepAlive()
        } else if !keepAliveActive {
            keepAliveActive = true
        }
    }

    // MARK: - Alarm

    func startAlarm(duration: TimeInterval, maxVolume: Bool, vibrate: Bool) {
        configureSession(forAlarm: true)
        if maxVolume {
            VolumeController.shared.setMaxVolume()
        }

        if alarmPlayer == nil {
            alarmPlayer = try? AVAudioPlayer(data: ToneGenerator.sirenWAV())
            alarmPlayer?.numberOfLoops = -1
            alarmPlayer?.prepareToPlay()
        }
        alarmPlayer?.volume = 1
        alarmPlayer?.currentTime = 0
        alarmPlayer?.play()
        isAlarmPlaying = true

        vibrateTimer?.invalidate()
        vibrateTimer = nil
        if vibrate {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            vibrateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }

        alarmStopWork?.cancel()
        alarmStopWork = nil
        if duration > 0 {
            let work = DispatchWorkItem { [weak self] in self?.stopAlarm() }
            alarmStopWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }

        // Keep the silent loop running too, so the app stays alive after the alarm.
        ensureKeepAlive()
    }

    func stopAlarm() {
        alarmStopWork?.cancel()
        alarmStopWork = nil
        vibrateTimer?.invalidate()
        vibrateTimer = nil
        alarmPlayer?.stop()
        isAlarmPlaying = false
        configureSession(forAlarm: false)
        ensureKeepAlive()
    }

    // MARK: - Session

    private func configureSession(forAlarm alarm: Bool) {
        let session = AVAudioSession.sharedInstance()
        // While idle we mix with other apps (music, video keep playing normally).
        // During the alarm we duck other audio so the siren is clearly heard.
        let options: AVAudioSession.CategoryOptions = alarm ? [.duckOthers] : [.mixWithOthers]
        do {
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let center = NotificationCenter.default

        center.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                // Phone call, Siri, alarm clock… iOS paused our audio.
                self.keepAliveActive = false
            case .ended:
                self.resumeAfterInterruption()
            @unknown default:
                break
            }
        }

        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                           object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let wasAlarm = self.isAlarmPlaying
            self.silentPlayer = nil
            self.alarmPlayer = nil
            self.startKeepAlive()
            if wasAlarm {
                self.startAlarm(duration: AppSettings.alarmDuration,
                                maxVolume: AppSettings.maxVolume,
                                vibrate: AppSettings.vibrate)
            }
        }
    }

    private func resumeAfterInterruption() {
        configureSession(forAlarm: isAlarmPlaying)
        silentPlayer?.play()
        if isAlarmPlaying {
            alarmPlayer?.play()
        }
        keepAliveActive = silentPlayer?.isPlaying == true
    }
}
