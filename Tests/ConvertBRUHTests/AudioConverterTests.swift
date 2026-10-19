import Foundation
import Testing
@testable import ConvertBRUH

private let input = URL(fileURLWithPath: "/m/@Placement Chasers: beat.flac")
private let output = URL(fileURLWithPath: "/tmp/salida.x")

private func info(codec: String, rate: Int = 44100, channels: Int = 2, fmt: String = "s16",
                  raw: Int = 0, bps: Int = 0, pic: Int? = nil) -> MediaInfo {
    MediaInfo(duration: 10, audio: .init(codec: codec, sampleRate: rate, channels: channels, sampleFormat: fmt,
                                         bitsPerRawSample: raw, bitsPerSample: bps),
              attachedPicVideoIndex: pic)
}

/// Valor que sigue a un flag en la lista de argumentos.
private func value(_ args: [String], _ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

@Suite struct BitDepthTests {
    @Test func losslessSeConserva() {
        #expect(AudioConverter.bitDepth(for: info(codec: "flac", fmt: "s32", raw: 24).audio, target: .wav) == .s24)
        #expect(AudioConverter.bitDepth(for: info(codec: "pcm_s24le", fmt: "s32", bps: 24).audio, target: .wav) == .s24)
        #expect(AudioConverter.bitDepth(for: info(codec: "pcm_s16le", fmt: "s16", bps: 16).audio, target: .aiff) == .s16)
        #expect(AudioConverter.bitDepth(for: info(codec: "pcm_f32le", fmt: "flt", bps: 32).audio, target: .wav) == .f32)
        #expect(AudioConverter.bitDepth(for: info(codec: "alac", fmt: "s32p", raw: 24).audio, target: .aiff) == .s24)
    }

    @Test func flacNoAdmiteFloat() {
        #expect(AudioConverter.bitDepth(for: info(codec: "pcm_f32le", fmt: "flt", bps: 32).audio, target: .flac) == .s24)
    }

    @Test func conPerdidaA16() {
        #expect(AudioConverter.bitDepth(for: info(codec: "mp3", fmt: "fltp").audio, target: .wav) == .s16)
        #expect(AudioConverter.bitDepth(for: info(codec: "aac", fmt: "fltp").audio, target: .flac) == .s16)
    }
}

@Suite struct ArgumentosTests {
    @Test func baseConPrefijoFile() {
        let a = AudioConverter.arguments(input: input, output: output, target: .mp3, info: info(codec: "flac"),
                                         isVideoSource: false, aacAT: true)
        #expect(Array(a.prefix(9)) == ["-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1", "-nostats",
                                        "-i", "file:/m/@Placement Chasers: beat.flac"])
        #expect(a.suffix(2) == ["-y", "file:/tmp/salida.x"])
        #expect(value(a, "-map") == "0:a:0")
        #expect(value(a, "-map_metadata") == "0")
    }

    @Test func mp3() {
        let a = AudioConverter.arguments(input: input, output: output, target: .mp3, info: info(codec: "pcm_s16le"),
                                         isVideoSource: false, aacAT: true)
        #expect(value(a, "-c:a") == "libmp3lame")
        #expect(value(a, "-b:a") == "320k")
        #expect(value(a, "-id3v2_version") == "3")
        #expect(!a.contains("-ar"))
    }

    @Test func flac96kHzABajaAMP3yM4AperoNoAWAV() {
        let hi = info(codec: "flac", rate: 96000, fmt: "s32", raw: 24)
        let mp3 = AudioConverter.arguments(input: input, output: output, target: .mp3, info: hi, isVideoSource: false, aacAT: true)
        let m4a = AudioConverter.arguments(input: input, output: output, target: .m4a, info: hi, isVideoSource: false, aacAT: true)
        let wav = AudioConverter.arguments(input: input, output: output, target: .wav, info: hi, isVideoSource: false, aacAT: true)
        #expect(value(mp3, "-ar") == "48000")
        #expect(value(m4a, "-ar") == "48000")
        #expect(!wav.contains("-ar"))
        #expect(value(wav, "-c:a") == "pcm_s24le")
    }

    @Test func familia441() {
        #expect(AudioConverter.outputSampleRate(source: 88200, target: .mp3) == 44100)
        #expect(AudioConverter.outputSampleRate(source: 176400, target: .m4a) == 44100)
        #expect(AudioConverter.outputSampleRate(source: 192000, target: .mp3) == 48000)
        #expect(AudioConverter.outputSampleRate(source: 96000, target: .flac) == 96000)
    }

    @Test func m4aConFallbackAAC() {
        let a = AudioConverter.arguments(input: input, output: output, target: .m4a, info: info(codec: "flac"), isVideoSource: false, aacAT: false)
        #expect(value(a, "-c:a") == "aac")
        #expect(value(a, "-b:a") == "256k")
        #expect(value(a, "-movflags") == "+faststart")
        let b = AudioConverter.arguments(input: input, output: output, target: .m4a, info: info(codec: "flac"), isVideoSource: false, aacAT: true)
        #expect(value(b, "-c:a") == "aac_at")
    }

    @Test func flac24y16() {
        let a24 = AudioConverter.arguments(input: input, output: output, target: .flac, info: info(codec: "pcm_s24le", fmt: "s32", bps: 24),
                                           isVideoSource: false, aacAT: true)
        #expect(value(a24, "-sample_fmt") == "s32")
        #expect(value(a24, "-bits_per_raw_sample") == "24")
        #expect(value(a24, "-compression_level") == "8")
        let a16 = AudioConverter.arguments(input: input, output: output, target: .flac, info: info(codec: "mp3", fmt: "fltp"),
                                           isVideoSource: false, aacAT: true)
        #expect(value(a16, "-sample_fmt") == "s16")
    }

    @Test func aiffBigEndian() {
        let a = AudioConverter.arguments(input: input, output: output, target: .aiff, info: info(codec: "pcm_f32le", fmt: "flt", bps: 32),
                                         isVideoSource: false, aacAT: true)
        #expect(value(a, "-c:a") == "pcm_f32be")
    }

    @Test func caratulaSoloHaciaMP3M4AFLAC() {
        let conPic = info(codec: "mp3", fmt: "fltp", pic: 0)
        let m4a = AudioConverter.arguments(input: input, output: output, target: .m4a, info: conPic, isVideoSource: false, aacAT: true)
        #expect(m4a.contains("0:v:0"))
        #expect(value(m4a, "-c:v") == "copy")
        #expect(value(m4a, "-disposition:v:0") == "attached_pic")
        let wav = AudioConverter.arguments(input: input, output: output, target: .wav, info: conPic, isVideoSource: false, aacAT: true)
        #expect(wav.contains("-vn"))
        #expect(!wav.contains("0:v:0"))
    }

    @Test func videoNuncaLlevaCaratula() {
        let a = AudioConverter.arguments(input: input, output: output, target: .mp3, info: info(codec: "aac", fmt: "fltp", pic: 0),
                                         isVideoSource: true, aacAT: true)
        #expect(a.contains("-vn"))
        #expect(!a.contains("0:v:0"))
    }

    @Test func multicanalAMP3() {
        let a = AudioConverter.arguments(input: input, output: output, target: .mp3, info: info(codec: "pcm_s24le", channels: 6, bps: 24),
                                         isVideoSource: false, aacAT: true)
        #expect(value(a, "-ac") == "2")
        let w = AudioConverter.arguments(input: input, output: output, target: .wav, info: info(codec: "pcm_s24le", channels: 6, bps: 24),
                                         isVideoSource: false, aacAT: true)
        #expect(!w.contains("-ac"))
    }
}

@Suite struct HerramientasAudioTests {
    @Test func compressEsMP3VBR() {
        var o = AudioConverter.Options()
        o.mp3VBR = true
        let a = AudioConverter.arguments(input: input, output: output, target: .mp3, info: info(codec: "flac"), isVideoSource: false, aacAT: true, options: o)
        #expect(value(a, "-q:a") == "5")
        #expect(!a.contains("-b:a"))
    }

    @Test func normalizeFuerzaSampleRate() {
        var o = AudioConverter.Options()
        o.audioFilter = "loudnorm=x"
        o.forceSampleRate = true
        let a = AudioConverter.arguments(input: input, output: output, target: .wav, info: info(codec: "pcm_s24le", rate: 44100, bps: 24),
                                         isVideoSource: false, aacAT: true, options: o)
        #expect(value(a, "-af") == "loudnorm=x")
        #expect(value(a, "-ar") == "44100")
    }

    @Test func mismoFormatoOWAV() {
        #expect(AudioConverter.sameFormatTarget(for: URL(fileURLWithPath: "/a.aif")) == .aiff)
        #expect(AudioConverter.sameFormatTarget(for: URL(fileURLWithPath: "/a.mp3")) == .mp3)
        #expect(AudioConverter.sameFormatTarget(for: URL(fileURLWithPath: "/a.mov")) == .wav)
        #expect(AudioConverter.sameFormatTarget(for: URL(fileURLWithPath: "/a.ogg")) == .wav)
    }

    @Test func parseaLoudnorm() {
        let stderr = """
        [Parsed_loudnorm_0 @ 0x1]
        {
        \t"input_i" : "-41.75",
        \t"input_tp" : "-41.07",
        \t"input_lra" : "0.00",
        \t"input_thresh" : "-51.75",
        \t"output_i" : "-14.00",
        \t"normalization_type" : "linear",
        \t"target_offset" : "0.04"
        }
        """
        let m = AudioConverter.parseLoudnorm(stderr)
        #expect(m == .init(inputI: "-41.75", inputTP: "-41.07", inputLRA: "0.00", inputThresh: "-51.75", targetOffset: "0.04"))
        let f = AudioConverter.loudnormApplyFilter(m!)
        #expect(f.contains("measured_I=-41.75"))
        #expect(f.hasSuffix("linear=true"))
    }

    @Test func silencioNoSeNormaliza() {
        let stderr = #"{ "input_i" : "-inf", "input_tp" : "-inf", "input_lra" : "0.00", "input_thresh" : "-inf", "target_offset" : "inf" }"#
        #expect(AudioConverter.parseLoudnorm(stderr) == nil)
    }

    @Test func metadataCopiaSinTags() {
        let a = AudioConverter.stripMetadataArguments(input: input, output: output)
        #expect(value(a, "-c") == "copy")
        #expect(value(a, "-map_metadata") == "-1")
        #expect(value(a, "-map") == "0:a:0")
    }
}

@Suite struct MediaProbeTests {
    @Test func parseaFlacConCaratula() throws {
        let json = """
        {"streams":[
          {"index":0,"codec_name":"flac","codec_type":"audio","sample_fmt":"s32","sample_rate":"96000","channels":2,"bits_per_raw_sample":"24","duration":"2.0"},
          {"index":1,"codec_name":"mjpeg","codec_type":"video","disposition":{"default":0,"attached_pic":1}}
        ],"format":{"duration":"2.000000"}}
        """
        let i = try MediaProbe.parse(Data(json.utf8))
        #expect(i.audio?.codec == "flac")
        #expect(i.audio?.sampleRate == 96000)
        #expect(i.audio?.bitsPerRawSample == 24)
        #expect(i.attachedPicVideoIndex == 0)
        #expect(i.duration == 2)
    }

    @Test func videoSinAudio() throws {
        let json = #"{"streams":[{"codec_type":"video","codec_name":"h264","disposition":{"attached_pic":0}}],"format":{"duration":"5.0"}}"#
        let i = try MediaProbe.parse(Data(json.utf8))
        #expect(i.audio == nil)
        #expect(i.attachedPicVideoIndex == nil)
    }
}
