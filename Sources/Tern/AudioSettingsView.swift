import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var audio: AudioService
    @Environment(\.islandTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("听见任务完成。").font(.system(size: 26, weight: .semibold))
                        Text("一个轻柔的提示音，或一句来自 HomePod 的提醒。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: "homepod.fill").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.white.opacity(0.8))
                }
                PanelCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("播放到哪里", systemImage: "airplay.audio").font(.system(size: 13, weight: .semibold))
                        HStack {
                            Picker("输出设备", selection: $preferences.outputUID) {
                                Text("系统默认输出").tag("")
                                ForEach(audio.outputs) { device in Text((device.isAirPlay ? "AirPlay · " : "") + device.name).tag(device.id) }
                                if !preferences.outputUID.isEmpty && !audio.outputs.contains(where: { $0.id == preferences.outputUID }) { Text("所选设备已断开").tag(preferences.outputUID) }
                            }.labelsHidden()
                            Button { audio.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(IslandButtonStyle()).help("刷新设备")
                        }
                        Text("先在 macOS 控制中心 → 声音 → AirPlay 连接 HomePod。选择“系统默认输出”即可跟随播放；已连接的设备也可能出现在上方列表。").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                        Button("打开系统声音设置") { audio.openSoundSettings() }.buttonStyle(IslandButtonStyle())
                    }
                }
                PanelCard {
                    VStack(alignment: .leading, spacing: 17) {
                        Toggle("播放提示音", isOn: $preferences.soundEnabled).font(.system(size: 13, weight: .medium))
                        HStack {
                            Picker("提示音", selection: $preferences.soundName) {
                                ForEach(["Glass", "Purr", "Pop", "Ping", "Submarine", "Hero"], id: \.self) { Text($0).tag($0) }
                                if !preferences.customSound.isEmpty { Text("自定义提示音").tag("Custom") }
                            }
                            Button("导入音频…") { audio.chooseSound(preferences: preferences) }.buttonStyle(IslandButtonStyle())
                            Button { audio.playChime(preferences: preferences) } label: { Image(systemName: "play.fill") }.buttonStyle(IslandButtonStyle()).help("试听提示音")
                        }
                        HStack { Image(systemName: "speaker.wave.1"); Slider(value: $preferences.volume, in: 0...1); Text("\(Int(preferences.volume * 100))%").monospacedDigit().frame(width: 35) }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
                PanelCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("语音播报", isOn: $preferences.speechEnabled).font(.system(size: 13, weight: .medium))
                        Text("开启后用一句话代替提示音。可只播报状态，也可加入交付摘要。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Picker("声音", selection: $preferences.voiceID) {
                            Text("自动选择中文语音").tag("")
                            ForEach(audio.voices, id: \.id) { voice in Text(voice.name).tag(voice.id) }
                        }
                        TextField("播报内容", text: $preferences.speechTemplate).textFieldStyle(.roundedBorder)
                        Text("可用变量：{agent}  {title}  {status}  {summary}").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                        HStack { Button("试听语音") { audio.testVoice(preferences: preferences) }.buttonStyle(IslandButtonStyle(prominent: true)); Spacer(); Text("使用 macOS 本地语音").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    }
                }
                Text(audio.status).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(28).toggleStyle(.switch).tint(theme.accent).font(.system(size: 12))
        }.onAppear { audio.refreshDevices() }
    }
}
