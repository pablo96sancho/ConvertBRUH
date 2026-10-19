import Foundation

/// Lo que nos interesa de un archivo según ffprobe.
struct MediaInfo: Equatable {
    struct Audio: Equatable {
        var codec: String
        var sampleRate: Int
        var channels: Int
        var sampleFormat: String
        var bitsPerRawSample: Int
        var bitsPerSample: Int
    }

    var duration: Double?
    var audio: Audio?
    /// Índice entre los streams de vídeo (`0:v:N`) de la carátula adjunta.
    var attachedPicVideoIndex: Int?
}

enum MediaProbe {
    enum ProbeError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self { case .failed(let s): s }
        }
    }

    /// Parseo puro de `ffprobe -of json -show_streams -show_format`.
    static func parse(_ data: Data) throws -> MediaInfo {
        struct Root: Decodable {
            struct Stream: Decodable {
                var codec_type: String?
                var codec_name: String?
                var sample_rate: String?
                var channels: Int?
                var sample_fmt: String?
                var bits_per_raw_sample: String?
                var bits_per_sample: Int?
                var duration: String?
                var disposition: [String: Int]?
            }
            struct Format: Decodable { var duration: String? }
            var streams: [Stream]?
            var format: Format?
        }
        let root = try JSONDecoder().decode(Root.self, from: data)
        var info = MediaInfo()
        var videoIndex = 0
        for s in root.streams ?? [] {
            switch s.codec_type {
            case "audio" where info.audio == nil:
                // Por partes: compiladores anteriores no infieren la expresión entera a tiempo
                let sampleRate: Int = Int(s.sample_rate ?? "") ?? 0
                let rawBits: Int = Int(s.bits_per_raw_sample ?? "") ?? 0
                info.audio = MediaInfo.Audio(
                    codec: s.codec_name ?? "",
                    sampleRate: sampleRate,
                    channels: s.channels ?? 0,
                    sampleFormat: s.sample_fmt ?? "",
                    bitsPerRawSample: rawBits,
                    bitsPerSample: s.bits_per_sample ?? 0)
                if info.duration == nil, let d = Double(s.duration ?? "") { info.duration = d }
            case "video":
                if s.disposition?["attached_pic"] == 1, info.attachedPicVideoIndex == nil {
                    info.attachedPicVideoIndex = videoIndex
                }
                videoIndex += 1
            default:
                break
            }
        }
        if let d = Double(root.format?.duration ?? ""), d > 0 { info.duration = d }
        return info
    }

    static func probe(_ url: URL) async throws -> MediaInfo {
        let result = try await FFmpegRunner.run(
            executable: Binaries.ffprobe,
            arguments: ["-v", "error", "-of", "json", "-show_streams", "-show_format", "file:" + url.path])
        guard result.status == 0 else { throw ProbeError.failed(FFmpegRunner.summarize(result.stderr)) }
        return try parse(Data(result.stdout.utf8))
    }

    /// Comprobación rápida y síncrona de si un vídeo tiene audio (para decidir porciones durante el arrastre).
    static func hasAudioStreamSync(_ url: URL) -> Bool {
        let p = Process()
        p.executableURL = Binaries.ffprobe
        p.arguments = ["-v", "error", "-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0", "file:" + url.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 && !data.isEmpty
    }
}
