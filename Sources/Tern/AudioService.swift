import AppKit
import CoreAudio
import AVFoundation
import TernCore

struct AudioOutput: Identifiable, Hashable {
    var id: String
    var name: String
    var isAirPlay: Bool
}

private final class SpeechFileWriter: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var closed = false
    private var failure: String?
    init(url: URL) { self.url = url }
    func consume(_ buffer: AVAudioBuffer) -> Result<URL, NSError>? {
        lock.lock(); defer { lock.unlock() }
        guard !closed, let pcm = buffer as? AVAudioPCMBuffer else { return nil }
        if pcm.frameLength == 0 {
            closed = true; file = nil
            if let failure { return .failure(NSError(domain: "Tern.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: failure])) }
            return .success(url)
        }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            try file?.write(from: pcm)
        } catch { failure = error.localizedDescription }
        return nil
    }
    func cancel() { lock.lock(); closed = true; file = nil; lock.unlock(); try? FileManager.default.removeItem(at: url) }
}

@MainActor final class AudioService: NSObject, ObservableObject, NSSoundDelegate {
    @Published var outputs: [AudioOutput] = []
    @Published var status = "提示音跟随所选输出设备"
    private var sound: NSSound?
    private let synthesizer = AVSpeechSynthesizer()
    private var writer: SpeechFileWriter?

    var voices: [(id: String, name: String)] {
        AVSpeechSynthesisVoice.speechVoices().map { ($0.identifier, "\($0.name) · \($0.language)") }.sorted { $0.1 < $1.1 }
    }
    func refreshDevices() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return }
        outputs = ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            func stringProperty(_ selector: AudioObjectPropertySelector) -> String? {
                var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: Unmanaged<CFString>?
                var bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                guard AudioObjectGetPropertyData(id, &a, 0, nil, &bytes, &value) == noErr else { return nil }
                return value?.takeRetainedValue() as String?
            }
            var transport = UInt32(0), bytes = UInt32(MemoryLayout<UInt32>.size)
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectGetPropertyData(id, &a, 0, nil, &bytes, &transport)
            guard let uid = stringProperty(kAudioDevicePropertyDeviceUID) else { return nil }
            return AudioOutput(id: uid, name: stringProperty(kAudioObjectPropertyName) ?? "音频设备", isAirPlay: transport == kAudioDeviceTransportTypeAirPlay)
        }
    }
    func announce(_ session: Session, preferences p: Preferences) {
        if p.speechEnabled {
            let text = p.speechTemplate.replacingOccurrences(of: "{agent}", with: session.agent.name)
                .replacingOccurrences(of: "{title}", with: session.displayTitle)
                .replacingOccurrences(of: "{status}", with: session.state.label)
                .replacingOccurrences(of: "{summary}", with: TextSummary.excerpt(session.summary, limit: 160))
            speak(String(text.prefix(600)), preferences: p)
        } else if p.soundEnabled { playChime(preferences: p) }
    }
    func playChime(preferences p: Preferences) {
        synthesizer.stopSpeaking(at: .immediate); sound?.stop(); writer?.cancel(); writer = nil
        let url = p.soundName == "Custom" ? URL(fileURLWithPath: p.customSound) : URL(fileURLWithPath: "/System/Library/Sounds/\(p.soundName).aiff")
        play(url, uid: p.outputUID, volume: Float(p.volume))
    }
    func testVoice(preferences p: Preferences) {
        speak("Codex 的任务已完成。你可以回到 Tern 查看交付。", preferences: p)
    }
    private func speak(_ text: String, preferences p: Preferences) {
        synthesizer.stopSpeaking(at: .immediate); sound?.stop(); writer?.cancel()
        let next = SpeechFileWriter(url: FileManager.default.temporaryDirectory.appendingPathComponent("tern-\(UUID().uuidString).caf"))
        writer = next
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = p.voiceID.isEmpty ? AVSpeechSynthesisVoice(language: "zh-CN") : AVSpeechSynthesisVoice(identifier: p.voiceID)
        utterance.rate = 0.49
        let uid = p.outputUID, volume = Float(p.volume)
        status = "正在生成本地语音…"
        synthesizer.write(utterance) { [weak self, next] buffer in
            guard let result = next.consume(buffer) else { return }
            Task { @MainActor in
                guard let self, self.writer === next else { return }
                switch result {
                case .success(let url): self.play(url, uid: uid, volume: volume)
                case .failure(let error): self.status = "语音生成失败：\(error.localizedDescription)"
                }
            }
        }
    }
    private func play(_ url: URL, uid: String, volume: Float) {
        refreshDevices()
        guard uid.isEmpty || outputs.contains(where: { $0.id == uid }) else {
            status = "所选设备已断开。请重新连接 HomePod 或选择系统默认输出。"; return
        }
        guard let next = NSSound(contentsOf: url, byReference: true) else { status = "无法读取提示音文件。"; return }
        next.volume = volume
        if !uid.isEmpty { next.playbackDeviceIdentifier = uid }
        sound?.stop(); sound = next; next.delegate = self
        status = next.play() ? "正在播放 · \(outputs.first(where: { $0.id == uid })?.name ?? "系统默认输出")" : "播放失败，请检查输出设备。"
    }
    func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        guard sound === self.sound else { return }
        writer?.cancel(); writer = nil
        status = finished ? "播放完成" : "播放已停止"
    }
    func chooseSound(preferences p: Preferences) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Tern/Sounds")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let copy = folder.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
            try FileManager.default.copyItem(at: url, to: copy)
            p.customSound = copy.path; p.soundName = "Custom"
        } catch { status = "导入失败：\(error.localizedDescription)" }
    }
    func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}
