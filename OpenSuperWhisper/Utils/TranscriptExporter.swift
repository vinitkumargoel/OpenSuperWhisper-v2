import Foundation
import UniformTypeIdentifiers

/// Serializes recordings to a chosen text format for export.
enum TranscriptExportFormat: String, CaseIterable, Identifiable {
    case txt
    case markdown
    case csv
    case json

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .txt: return "Plain Text (.txt)"
        case .markdown: return "Markdown (.md)"
        case .csv: return "CSV (.csv)"
        case .json: return "JSON (.json)"
        }
    }

    var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .markdown: return "md"
        case .csv: return "csv"
        case .json: return "json"
        }
    }

    var contentType: UTType {
        switch self {
        case .txt: return .plainText
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .csv: return .commaSeparatedText
        case .json: return .json
        }
    }
}

enum TranscriptExporter {
    private static var timestampFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }

    static func serialize(_ recordings: [Recording], format: TranscriptExportFormat) -> String {
        switch format {
        case .txt: return txt(recordings)
        case .markdown: return markdown(recordings)
        case .csv: return csv(recordings)
        case .json: return json(recordings)
        }
    }

    private static func txt(_ recordings: [Recording]) -> String {
        recordings.map { rec in
            let header = DateFormatter.exportHeader.string(from: rec.timestamp)
            return "[\(header)]\n\(rec.transcription)"
        }.joined(separator: "\n\n")
    }

    private static func markdown(_ recordings: [Recording]) -> String {
        var out = "# Transcriptions\n\n"
        out += recordings.map { rec in
            let header = DateFormatter.exportHeader.string(from: rec.timestamp)
            return "## \(header)\n\n\(rec.transcription)"
        }.joined(separator: "\n\n---\n\n")
        return out
    }

    private static func csv(_ recordings: [Recording]) -> String {
        var rows = ["timestamp,duration_seconds,words,transcription,raw_transcription"]
        for rec in recordings {
            let ts = timestampFormatter.string(from: rec.timestamp)
            let words = TextUtil.wordCount(rec.transcription)
            let cols = [
                ts,
                String(format: "%.2f", rec.duration),
                String(words),
                rec.transcription,
                rec.rawTranscription ?? ""
            ].map(csvEscape)
            rows.append(cols.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func json(_ recordings: [Recording]) -> String {
        let iso = timestampFormatter
        let objects: [[String: Any]] = recordings.map { rec in
            [
                "timestamp": iso.string(from: rec.timestamp),
                "duration": rec.duration,
                "words": TextUtil.wordCount(rec.transcription),
                "transcription": rec.transcription,
                "rawTranscription": rec.rawTranscription ?? ""
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

private extension DateFormatter {
    static let exportHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
