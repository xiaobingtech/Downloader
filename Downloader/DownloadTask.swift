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
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.fileName = url.lastPathComponent.isEmpty ? "Unknown" : url.lastPathComponent
        self.createdAt = Date()
        self.status = .waiting
        self.progress = 0.0
        self.totalBytes = 0
        self.downloadedBytes = 0
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
}
