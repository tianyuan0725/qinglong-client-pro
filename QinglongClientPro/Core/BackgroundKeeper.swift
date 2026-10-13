import AVFoundation

/// 后台保活器：播放一段**静音**，让 App 退到后台后不被 iOS 挂起，
/// 从而 CronWatchService 的轮询能继续跑、任务完成时能实时弹本地通知。
///
/// 原理：配置 `.playback` 音频会话 + Info.plist 声明 `audio` 后台模式，
/// 系统会像对待音乐播放器一样保持 App 运行。音量为接近 0 的静音 WAV
/// （运行时生成，不打到 IPA 里），不影响用户听其它 App 的声音
/// （`.mixWithOthers`）。
///
/// 仅在「本地通知总开关」开启、正在监听任务、且用户没关保活开关时启动，
/// 避免无谓耗电。开关可在通知栏顶部「后台保活」随时修改。
@MainActor
final class BackgroundKeeper {
    static let shared = BackgroundKeeper()

    private var player: AVAudioPlayer?

    /// 是否正在保活（供设置页展示状态）。
    private(set) var isActive = false

    /// 保活开关 key（通知栏顶部设置，默认开）。
    private static let enabledKey = "qlpro_keepalive"

    /// 用户是否允许后台保活（关闭后仅前台轮询 + BGTask 兜底，更省电）。
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private init() {}

    // MARK: - 启停

    /// 设置保活开关（通知栏顶部开关调用，立即生效并持久化）。
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { start() } else { stop() }
    }

    func start() {
        guard !isActive else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default,
                                         options: [.mixWithOthers])
            try audioSession.setActive(true)
            let url = try Self.silentWavURL()
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1   // 无限循环
            p.volume = 0.001       // 几乎无声（纯保活）
            p.play()
            player = p
            isActive = true
        } catch {
            // 保活失败不阻塞主流程：前台轮询 + BGTask 兜底仍可用
            isActive = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isActive = false
    }

    // MARK: - 静音 WAV 生成

    /// 生成 1 秒 16bit 单声道 8kHz 全零（静音）WAV 到临时目录。
    private static func silentWavURL() throws -> URL {
        let sampleRate = 8000
        let channels = 1
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * blockAlign
        let dataSize = sampleRate * blockAlign   // 1 秒

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendUInt32LE(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendUInt32LE(16)                      // fmt chunk 大小
        data.appendUInt16LE(1)                       // PCM
        data.appendUInt16LE(UInt16(channels))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        data.appendUInt32LE(UInt32(dataSize))
        data.append(Data(count: dataSize))           // 全 0 = 静音

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql_silence.wav")
        try data.write(to: url)
        return url
    }
}

private extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }
}
