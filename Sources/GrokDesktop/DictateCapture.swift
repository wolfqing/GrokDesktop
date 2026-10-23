import AVFoundation
import Foundation
import GrokDesktopCore
import Speech

/// Turns the companion mic into text. The final transcript is applied by the caller.
@MainActor
final class DictateCapture: ObservableObject {
    @Published var listening = false
    @Published var status = ""
    @Published var levels: [CGFloat] = LevelTape.flat

    private let engine = AVAudioEngine()
    private nonisolated let meter = LevelTape()
    private nonisolated let audio = AudioTarget()
    private var meterTimer: Timer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var tapInstalled = false
    private var taskGeneration = 0
    private var barrenTasks = 0
    private var transcript = SpeechTranscript()
    private var onPartial: ((String) -> Void)?
    private var onFinal: ((String) -> Void)?
    private var deniedSpeech = ""
    private var deniedMic = ""
    private var unavailableText = ""
    private var localeID = "system"

    func toggle(
        localeID: String,
        deniedSpeech: String,
        deniedMic: String,
        unavailable: String,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        if listening {
            stop()
            return
        }
        status = ""
        self.localeID = localeID
        self.deniedSpeech = deniedSpeech
        self.deniedMic = deniedMic
        self.unavailableText = unavailable
        self.onPartial = onPartial
        self.onFinal = onFinal
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            Task { @MainActor in
                self?.continueAfterSpeech(auth == .authorized)
            }
        }
    }

    private func continueAfterSpeech(_ allowed: Bool) {
        guard allowed else {
            status = deniedSpeech
            return
        }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                self?.continueAfterMicrophone(granted)
            }
        }
    }

    private func continueAfterMicrophone(_ granted: Bool) {
        guard granted else {
            status = deniedMic
            return
        }
        start()
    }

    func stop() {
        taskGeneration += 1
        onPartial = nil
        onFinal = nil
        transcript = SpeechTranscript()
        audio.set(nil)
        meterTimer?.invalidate()
        meterTimer = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        recognition?.cancel()
        request = nil
        recognition = nil
        recognizer = nil
        listening = false
        levels = LevelTape.flat
    }

    private func start() {
        let identifier = LocaleCatalog.speechIdentifier(preference: localeID, preferredLanguages: Locale.preferredLanguages)
        var recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
        if recognizer?.isAvailable != true {
            recognizer = SFSpeechRecognizer(locale: .current)
        }
        guard let recognizer, recognizer.isAvailable else {
            status = unavailableText
            return
        }
        self.recognizer = recognizer
        transcript = SpeechTranscript()
        barrenTasks = 0
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = unavailableText
            return
        }
        let meter = self.meter
        let audio = self.audio
        meter.reset()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            audio.append(buffer)
            meter.push(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            status = unavailableText
            return
        }
        listening = true
        startMeter()
        beginTask()
    }

    /// One recognition task covers one stretch of speech. A later stretch must not replace it.
    private func beginTask() {
        guard listening, let recognizer else { return }
        taskGeneration += 1
        let generation = taskGeneration
        recognition?.cancel()
        request?.endAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        audio.set(request)
        self.request = request
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let final = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.listening, self.taskGeneration == generation else { return }
                if !text.isEmpty {
                    self.barrenTasks = 0
                    self.transcript.absorb(text, isFinal: final)
                    let spoken = self.transcript.text
                    if !spoken.isEmpty {
                        self.onPartial?(spoken)
                    }
                    if final {
                        self.beginTask()
                        return
                    }
                }
                if failed {
                    self.barrenTasks += 1
                    if self.barrenTasks <= 3 {
                        self.beginTask()
                    } else {
                        self.stop()
                    }
                }
            }
        }
    }

    private func startMeter() {
        meterTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.listening else { return }
                self.levels = self.meter.snapshot()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }
}

/// Rolling loudness samples for the dotted voice waveform. The audio tap writes; the UI reads.
private final class LevelTape: @unchecked Sendable {
    static let count = 96
    static let flat = Array(repeating: CGFloat(0), count: count)

    private let lock = NSLock()
    private var samples: [Float]

    init() {
        samples = Array(repeating: 0, count: Self.count)
    }

    func reset() {
        lock.lock()
        samples = Array(repeating: 0, count: Self.count)
        lock.unlock()
    }

    func push(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?.pointee else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 1 else { return }
        var sum: Float = 0
        var seen = 0
        var index = 0
        while index < frames {
            let sample = channel[index]
            sum += sample * sample
            seen += 1
            index += 2
        }
        let rms = sqrt(sum / Float(seen))
        var level = min(1, pow(rms * 18, 0.72))
        if level < 0.045 { level = 0 }
        lock.lock()
        let smoothed = (samples.last ?? 0) * 0.42 + level * 0.58
        samples.removeFirst()
        samples.append(smoothed)
        lock.unlock()
    }

    func snapshot() -> [CGFloat] {
        lock.lock()
        let copy = samples.map { CGFloat($0) }
        lock.unlock()
        return copy
    }
}

/// The audio tap always writes into the current recognition request.
private final class AudioTarget: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }
}
