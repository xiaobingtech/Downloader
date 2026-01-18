//
//  TSMerger.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import Foundation

/// Utility for merging TS segment files
class TSMerger {
    
    /// Merge multiple TS files into one
    /// - Parameters:
    ///   - segmentPaths: Ordered array of segment file paths
    ///   - outputPath: Output file path
    /// - Throws: MergeError if merge fails
    static func merge(segmentPaths: [URL], to outputPath: URL) throws {
        // Validate all segments exist
        for (index, path) in segmentPaths.enumerated() {
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw MergeError.segmentMissing(index: index)
            }
            let attr = try FileManager.default.attributesOfItem(atPath: path.path)
            if let size = attr[.size] as? UInt64, size == 0 {
                throw MergeError.readFailed(index: index, error: NSError(domain: "TSMerger", code: -1, userInfo: [NSLocalizedDescriptionKey: "Segment is empty"]))
            }
        }
        
        // Create output directory if needed
        let outputDir = outputPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw MergeError.directoryCreationFailed(error: error)
        }
        
        // Remove existing output file
        if FileManager.default.fileExists(atPath: outputPath.path) {
            try FileManager.default.removeItem(at: outputPath)
        }
        
        // Merge all segments into one Data object first, then write to file
        var mergedData = Data()
        
        for (index, path) in segmentPaths.enumerated() {
            do {
                let segmentData = try Data(contentsOf: path)
                mergedData.append(segmentData)
            } catch {
                throw MergeError.readFailed(index: index, error: error)
            }
        }
        
        // Write merged data to output file
        do {
            try mergedData.write(to: outputPath, options: .atomic)
        } catch {
            throw MergeError.writeFailed(error: error)
        }
    }
}

/// Merge operation errors
enum MergeError: Error, LocalizedError {
    case segmentMissing(index: Int)
    case directoryCreationFailed(error: Error)
    case readFailed(index: Int, error: Error)
    case writeFailed(error: Error)
    
    var errorDescription: String? {
        switch self {
        case .segmentMissing(let index):
            return "Segment \(index) is missing"
        case .directoryCreationFailed(let error):
            return "Cannot create output directory: \(error.localizedDescription) - \(error)"
        case .readFailed(let index, let error):
            return "Failed to read segment \(index): \(error.localizedDescription) - \(error)"
        case .writeFailed(let error):
            return "Failed to write merged file: \(error.localizedDescription) - \(error)"
        }
    }
}
