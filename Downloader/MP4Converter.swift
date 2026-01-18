//
//  MP4Converter.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import Foundation
import AVFoundation
import FFmpegSupport

/// Utility for converting TS files to MP4 format
class MP4Converter {
    
    /// Convert TS file to MP4 using AVAssetExportSession
    /// - Parameters:
    ///   - inputPath: Input TS file path
    ///   - outputPath: Output MP4 file path
    ///   - progress: Progress callback (0.0 - 1.0)
    /// - Throws: ConvertError if conversion fails
    static func convert(
        from inputPath: URL,
        to outputPath: URL,
        progress: ((Float) -> Void)? = nil
    ) async throws {
        // Validate input file exists
        guard FileManager.default.fileExists(atPath: inputPath.path) else {
            throw ConvertError.inputNotFound
        }
        
        // Create output directory if needed
        let outputDir = outputPath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }
        
        // Remove existing output file
        if FileManager.default.fileExists(atPath: outputPath.path) {
            try FileManager.default.removeItem(at: outputPath)
        }
        
        // Usage: ffmpeg(["ffmpeg", "-i", "in.webm", "out.mp4"])
        let command = [
            "ffmpeg",
            "-i", inputPath.path,
            "-c", "copy",
            outputPath.path,
            "-y"
        ]
        
        print("Executing FFmpeg command: \(command)")
        
        let result = ffmpeg(command)
        
        guard result == 0 else {
             throw ConvertError.exportFailed(NSError(domain: "FFmpeg", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "FFmpeg exited with code \(result)"]))
        }
    }
}

/// Conversion errors
enum ConvertError: Error, LocalizedError {
    case inputNotFound
    case notExportable
    case loadFailed(Error)
    case sessionCreationFailed
    case exportFailed(Error)
    case cancelled
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .inputNotFound:
            return "Input file not found"
        case .notExportable:
            return "Asset is not exportable"
        case .loadFailed(let error):
            return "Failed to load asset: \(error.localizedDescription) - \(error)"
        case .sessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription) - \(error)"
        case .cancelled:
            return "Export cancelled"
        case .unknown:
            return "Unknown error"
        }
    }
}
