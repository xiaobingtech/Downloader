//
//  M3U8Parser.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import Foundation

/// Parsed segment info from m3u8
struct M3U8Segment {
    let index: Int
    let url: URL
    let duration: Double
}

/// M3U8 file parser
class M3U8Parser {
    
    /// Parse m3u8 content and extract segment URLs
    /// - Parameters:
    ///   - content: m3u8 file content string
    ///   - baseURL: Base URL for resolving relative paths
    /// - Returns: Array of segment info in order
    static func parse(content: String, baseURL: URL) throws -> [M3U8Segment] {
        var segments: [M3U8Segment] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentDuration: Double = 0
        var index = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments (except EXTINF)
            if trimmed.isEmpty || (trimmed.hasPrefix("#") && !trimmed.hasPrefix("#EXTINF")) {
                continue
            }
            
            // Parse duration from EXTINF
            if trimmed.hasPrefix("#EXTINF:") {
                let durationPart = trimmed
                    .replacingOccurrences(of: "#EXTINF:", with: "")
                    .components(separatedBy: ",")
                    .first ?? "0"
                currentDuration = Double(durationPart) ?? 0
                continue
            }
            
            // This should be a segment URL
            if !trimmed.hasPrefix("#") {
                if let segmentURL = resolveURL(trimmed, baseURL: baseURL) {
                    segments.append(M3U8Segment(
                        index: index,
                        url: segmentURL,
                        duration: currentDuration
                    ))
                    index += 1
                }
                currentDuration = 0
            }
        }
        
        return segments
    }
    
    /// Resolve segment URL (handle relative and absolute paths)
    private static func resolveURL(_ urlString: String, baseURL: URL) -> URL? {
        // Already absolute URL
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return URL(string: urlString)
        }
        
        // Relative URL - resolve against base
        let base = baseURL.deletingLastPathComponent()
        return base.appendingPathComponent(urlString)
    }
    
    /// Fetch and parse m3u8 from URL
    /// - Parameter url: m3u8 file URL
    /// - Returns: Parsed segments or error
    static func fetch(from url: URL) async throws -> [M3U8Segment] {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw M3U8Error.invalidContent
        }
        return try parse(content: content, baseURL: url)
    }
}

/// M3U8 parsing errors
enum M3U8Error: Error, LocalizedError {
    case invalidContent
    case noSegmentsFound
    case fetchFailed(Error)
    case encryptedStreamNotSupported
    
    var errorDescription: String? {
        switch self {
        case .invalidContent:
            return "Invalid m3u8 content"
        case .noSegmentsFound:
            return "No segments found in m3u8"
        case .fetchFailed(let error):
            return "Failed to fetch m3u8: \(error.localizedDescription)"
        case .encryptedStreamNotSupported:
            return "Encrypted streams are not supported (EXT-X-KEY detected)"
        }
    }
}
