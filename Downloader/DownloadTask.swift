//
//  DownloadTask.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import Foundation
import Combine

/// Status of a download task
enum DownloadStatus: String, Codable {
    case waiting      // Waiting to start
    case downloading  // Currently downloading
    case paused       // Paused by user
    case completed    // Download completed
    case failed       // Download failed
}

/// Persistable data structure for DownloadTask
struct DownloadTaskData: Codable {
    let id: UUID
    let urlString: String
    let fileName: String
    let createdAt: Date
    var status: DownloadStatus
    var progress: Double
    var totalBytes: Int64
    var downloadedBytes: Int64
    var resumeDataPath: String?  // Path to saved resume data file
}

/// Model representing a download task
class DownloadTask: Identifiable, ObservableObject {
    let id: UUID
    let url: URL
    let fileName: String
    let createdAt: Date
    
    @Published var status: DownloadStatus
    @Published var progress: Double  // 0.0 - 1.0
    @Published var totalBytes: Int64
    @Published var downloadedBytes: Int64
    @Published var errorMessage: String?
    
    // URLSession download task reference
    var downloadTask: URLSessionDownloadTask?
    // Resume data for paused downloads
    var resumeData: Data?
    
    init(url: URL, fileName: String? = nil) {
        self.id = UUID()
        self.url = url
        
        if let name = fileName, !name.isEmpty {
            self.fileName = name
        } else {
            let lastPath = url.lastPathComponent
            self.fileName = lastPath.isEmpty ? "Unknown" : lastPath
        }
        
        self.createdAt = Date()
        self.status = .waiting
        self.progress = 0.0
        self.totalBytes = 0
        self.downloadedBytes = 0
    }
    
    // Init from persisted data
    init(from data: DownloadTaskData) {
        self.id = data.id
        self.url = URL(string: data.urlString)!
        self.fileName = data.fileName
        self.createdAt = data.createdAt
        self.status = data.status
        self.progress = data.progress
        self.totalBytes = data.totalBytes
        self.downloadedBytes = data.downloadedBytes
        
        // Load resume data if exists
        if let resumeDataPath = data.resumeDataPath {
            let fileURL = DownloadTask.resumeDataDirectory.appendingPathComponent(resumeDataPath)
            self.resumeData = try? Data(contentsOf: fileURL)
        }
    }
    
    /// Convert to persistable data
    func toData() -> DownloadTaskData {
        var resumeDataPath: String? = nil
        
        // Save resume data to file if exists
        if let resumeData = self.resumeData {
            let fileName = "\(id.uuidString).resumedata"
            let fileURL = DownloadTask.resumeDataDirectory.appendingPathComponent(fileName)
            try? resumeData.write(to: fileURL)
            resumeDataPath = fileName
        }
        
        return DownloadTaskData(
            id: id,
            urlString: url.absoluteString,
            fileName: fileName,
            createdAt: createdAt,
            status: status,
            progress: progress,
            totalBytes: totalBytes,
            downloadedBytes: downloadedBytes,
            resumeDataPath: resumeDataPath
        )
    }
    
    /// Delete resume data file
    func deleteResumeData() {
        let fileName = "\(id.uuidString).resumedata"
        let fileURL = DownloadTask.resumeDataDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Directory for storing resume data
    static var resumeDataDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let resumeDir = documentsPath.appendingPathComponent("ResumeData")
        if !FileManager.default.fileExists(atPath: resumeDir.path) {
            try? FileManager.default.createDirectory(at: resumeDir, withIntermediateDirectories: true)
        }
        return resumeDir
    }
    
    /// Formatted progress percentage string
    var progressText: String {
        return String(format: "%.1f%%", progress * 100)
    }
    
    /// Formatted file size string
    var sizeText: String {
        guard totalBytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let downloaded = formatter.string(fromByteCount: downloadedBytes)
        let total = formatter.string(fromByteCount: totalBytes)
        return "\(downloaded) / \(total)"
    }
    
    /// Path to downloaded file
    var destinationURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Downloads").appendingPathComponent(fileName)
    }
}
