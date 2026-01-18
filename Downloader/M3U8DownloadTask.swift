//
//  M3U8DownloadTask.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import Foundation
import Combine

/// Status for M3U8 download task
enum M3U8TaskStatus: String, Codable {
    case parsing       // Parsing m3u8 file
    case downloading   // Downloading segments
    case paused        // Paused by user
    case merging       // Merging ts files
    case converting    // Converting to MP4
    case completed     // All done
    case failed        // Failed
}

/// Segment download state
enum SegmentState: String, Codable {
    case waiting
    case downloading
    case completed
    case failed
}

/// Persistable data for M3U8DownloadTask
struct M3U8TaskData: Codable {
    let id: UUID
    let m3u8URLString: String
    let fileName: String
    let createdAt: Date
    var status: M3U8TaskStatus
    var segmentURLs: [String]
    var segmentStates: [SegmentState]
    var retryCount: [Int]
}

/// M3U8 download task with segment management
class M3U8DownloadTask: Identifiable, ObservableObject {
    let id: UUID
    let m3u8URL: URL
    let fileName: String
    let createdAt: Date
    
    @Published var status: M3U8TaskStatus
    @Published var segments: [M3U8Segment] = []
    @Published var segmentStates: [SegmentState] = []
    @Published var retryCount: [Int] = []
    @Published var errorMessage: String?
    
    /// Directory for storing downloaded segments
    var segmentsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documentsPath.appendingPathComponent("M3U8Segments/\(id.uuidString)")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// Path to merged ts file
    var mergedTSPath: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Downloads/\(fileNameWithoutExtension).ts")
    }
    
    /// Path to final MP4 file
    var mp4Path: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Downloads/\(fileNameWithoutExtension).mp4")
    }
    
    /// File name without extension
    private var fileNameWithoutExtension: String {
        let name = fileName
        if let dotIndex = name.lastIndex(of: ".") {
            return String(name[..<dotIndex])
        }
        return name
    }
    
    /// Maximum retry count per segment
    static let maxRetryCount = 3
    
    init(m3u8URL: URL, fileName: String? = nil) {
        self.id = UUID()
        self.m3u8URL = m3u8URL
        self.fileName = fileName ?? m3u8URL.deletingPathExtension().lastPathComponent
        self.createdAt = Date()
        self.status = .parsing
    }
    
    /// Init from persisted data
    init(from data: M3U8TaskData) {
        self.id = data.id
        self.m3u8URL = URL(string: data.m3u8URLString)!
        self.fileName = data.fileName
        self.createdAt = data.createdAt
        self.status = data.status
        
        // Restore segments
        self.segments = data.segmentURLs.enumerated().compactMap { index, urlString in
            guard let url = URL(string: urlString) else { return nil }
            return M3U8Segment(index: index, url: url, duration: 0)
        }
        self.segmentStates = data.segmentStates
        self.retryCount = data.retryCount
    }
    
    /// Convert to persistable data
    func toData() -> M3U8TaskData {
        return M3U8TaskData(
            id: id,
            m3u8URLString: m3u8URL.absoluteString,
            fileName: fileName,
            createdAt: createdAt,
            status: status,
            segmentURLs: segments.map { $0.url.absoluteString },
            segmentStates: segmentStates,
            retryCount: retryCount
        )
    }
    
    /// Setup segments after parsing
    func setupSegments(_ parsedSegments: [M3U8Segment]) {
        self.segments = parsedSegments
        self.segmentStates = Array(repeating: .waiting, count: parsedSegments.count)
        self.retryCount = Array(repeating: 0, count: parsedSegments.count)
    }
    
    /// Number of completed segments
    var completedCount: Int {
        segmentStates.filter { $0 == .completed }.count
    }
    
    /// Total segment count
    var totalCount: Int {
        segments.count
    }
    
    /// Progress text (e.g., "15/100")
    var progressText: String {
        return "\(completedCount)/\(totalCount)"
    }
    
    /// Progress as percentage (0.0 - 1.0)
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
    
    /// Status display text
    var statusText: String {
        switch status {
        case .parsing:
            return "解析中..."
        case .downloading:
            return progressText
        case .paused:
            return "已暂停 \(progressText)"
        case .merging:
            return "合并中..."
        case .converting:
            return "转码中..."
        case .completed:
            return "已完成"
        case .failed:
            return "下载失败"
        }
    }
    
    /// Path for segment file
    func segmentPath(at index: Int) -> URL {
        return segmentsDirectory.appendingPathComponent(String(format: "segment_%04d.ts", index))
    }
    
    /// Check if segment needs retry
    func shouldRetry(at index: Int) -> Bool {
        return segmentStates[index] == .failed && retryCount[index] < Self.maxRetryCount
    }
    
    /// Get next segment to download
    func nextSegmentToDownload() -> Int? {
        // First check failed segments that can be retried
        for (index, state) in segmentStates.enumerated() {
            if state == .failed && shouldRetry(at: index) {
                return index
            }
        }
        // Then check waiting segments
        return segmentStates.firstIndex(of: .waiting)
    }
    
    /// Check if all segments are completed
    var allSegmentsCompleted: Bool {
        return !segmentStates.isEmpty && segmentStates.allSatisfy { $0 == .completed }
    }
    
    /// Clean up segment files
    func cleanupSegments() {
        try? FileManager.default.removeItem(at: segmentsDirectory)
    }
}
