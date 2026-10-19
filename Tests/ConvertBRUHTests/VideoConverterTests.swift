import Foundation
import Testing
@testable import ConvertBRUH

private let input = URL(fileURLWithPath: "/v/@clip: 1.mov")
private let output = URL(fileURLWithPath: "/tmp/salida.mp4")

private func info(video: String?, audio: String?) -> MediaInfo {
    MediaInfo(duration: 3,
              audio: audio.map { .init(codec: $0, sampleRate: 48000, channels: 2, sampleFormat: "fltp", bitsPerRawSample: 0, bitsPerSample: 0) },
              attachedPicVideoIndex: nil, videoCodec: video)
}

private func value(_ args: [String], _ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

@Suite struct VideoConverterTests {
    @Test func h264AACaMP4SeCopiaTodo() {
        let a = VideoConverter.arguments(input: input, output: output, target: .mp4, info: info(video: "h264", audio: "aac"), aacAT: true)
        #expect(value(a, "-c:v") == "copy")
        #expect(value(a, "-c:a") == "copy")
        #expect(a.contains("0:a:0?"))
        #expect(value(a, "-movflags") == "+faststart")
        #expect(a.suffix(2) == ["-y", "file:/tmp/salida.mp4"])
    }

    @Test func pcmEnMP4SeRecodificaSoloElAudio() {
        let a = VideoConverter.arguments(input: input, output: output, target: .mp4, info: info(video: "h264", audio: "pcm_s16le"), aacAT: true)
        #expect(value(a, "-c:v") == "copy")
        #expect(value(a, "-c:a") == "aac_at")
        // En MOV sí cabe el PCM
        let m = VideoConverter.arguments(input: input, output: output, target: .mov, info: info(video: "h264", audio: "pcm_s16le"), aacAT: true)
        #expect(value(m, "-c:a") == "copy")
    }

    @Test func proResAMP4SeRecodificaAH264Par() {
        let a = VideoConverter.arguments(input: input, output: output, target: .mp4, info: info(video: "prores", audio: nil), aacAT: false)
        #expect(value(a, "-c:v") == "libx264")
        #expect(value(a, "-pix_fmt") == "yuv420p")
        #expect(value(a, "-vf") == "scale=trunc(iw/2)*2:trunc(ih/2)*2")
        #expect(!a.contains("-c:a"))
        // ProRes cabe en MOV tal cual
        let m = VideoConverter.arguments(input: input, output: output, target: .mov, info: info(video: "prores", audio: nil), aacAT: false)
        #expect(value(m, "-c:v") == "copy")
    }

    @Test func hevcLlevaEtiquetaHvc1() {
        let a = VideoConverter.arguments(input: input, output: output, target: .mp4, info: info(video: "hevc", audio: "aac"), aacAT: true)
        #expect(value(a, "-tag:v") == "hvc1")
    }

    @Test func gifConPaleta() {
        let a = VideoConverter.gifArguments(input: input, output: output)
        #expect(value(a, "-vf")?.contains("palettegen") == true)
        #expect(value(a, "-loop") == "0")
    }

    @Test func extensionesDeAudioExtraido() {
        #expect(VideoConverter.extractedAudioExtension(codec: "aac") == "m4a")
        #expect(VideoConverter.extractedAudioExtension(codec: "mp3") == "mp3")
        #expect(VideoConverter.extractedAudioExtension(codec: "opus") == "opus")
        #expect(VideoConverter.extractedAudioExtension(codec: "pcm_s24le") == "wav")
        #expect(VideoConverter.extractedAudioExtension(codec: "pcm_s16be") == nil) // → WAV recodificado
        let a = VideoConverter.extractAudioArguments(input: input, output: URL(fileURLWithPath: "/tmp/a.m4a"))
        #expect(value(a, "-c:a") == "copy")
        #expect(a.contains("-vn"))
    }

    @Test func compressYMute() {
        let c = VideoConverter.compressArguments(input: input, output: output, hasAudio: true, aacAT: true)
        #expect(value(c, "-crf") == "26")
        #expect(value(c, "-vf")?.contains("min(1080") == true)
        #expect(value(c, "-b:a") == "128k")
        let m = VideoConverter.muteArguments(input: input, output: output)
        #expect(m.contains("-an"))
        #expect(value(m, "-c") == "copy")
    }
}
