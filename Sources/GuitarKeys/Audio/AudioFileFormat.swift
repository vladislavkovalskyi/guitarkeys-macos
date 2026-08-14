import AVFoundation
import Foundation

/// Формат звукового файла для записи и экспорта.
enum AudioFileFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case m4a, wav, aiff, caf

    var id: String { rawValue }
    var fileExtension: String { rawValue }

    var title: String {
        switch self {
        case .m4a:  return "M4A"
        case .wav:  return "WAV"
        case .aiff: return "AIFF"
        case .caf:  return "CAF"
        }
    }

    var subtitle: String { L.t("format." + rawValue) }

    var isLossless: Bool { self != .m4a }

    func settings(sampleRate: Double, channels: Int) -> [String: Any] {
        switch self {
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 192_000,
            ]
        case .wav, .caf:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .aiff:
            // AIFF по стандарту хранит сэмплы старшим байтом вперёд.
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ]
        }
    }
}
