//
//  DownloadTask.swift
//  Downloader
//
//  Created by fanxiaobing on 2025/11/13.
//

import Foundation
import Combine

enum DownloadStatus: String, Codable {
    case downloading
    case paused
    case completed
    case failed
}

enum DownloadType: String, Codable {
    case directLink
    case m3u8
}

class DownloadTask: ObservableObject, Identifiable {
    let id: UUID
    let url: String
    let fileName: String
    let downloadType: DownloadType
    @Published var status: DownloadStatus
    @Published var progress: Double // 0.0 to 1.0
    @Published var downloadSpeed: Double // bytes per second
    @Published var downloadedBytes: Int64
    @Published var totalBytes: Int64?
    @Published var totalSegments: Int?
    @Published var downloadedSegments: Int
    
    var filePath: URL? // 下载完成后的文件路径
    
    init(id: UUID = UUID(), url: String, fileName: String, downloadType: DownloadType, status: DownloadStatus = .downloading) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.downloadType = downloadType
        self.status = status
        self.progress = 0.0
        self.downloadSpeed = 0.0
        self.downloadedBytes = 0
        self.totalBytes = nil
        self.filePath = nil
        self.totalSegments = nil
        self.downloadedSegments = 0
    }
    
    var displayFileName: String {
        let fileExtension = downloadType == .m3u8 ? "ts" : (URL(string: url)?.pathExtension ?? "")
        return "\(fileName).\(fileExtension)"
    }
    
    var formattedSpeed: String {
        if downloadSpeed < 1024 {
            return String(format: "%.0f B/s", downloadSpeed)
        } else if downloadSpeed < 1024 * 1024 {
            return String(format: "%.1f KB/s", downloadSpeed / 1024)
        } else {
            return String(format: "%.1f MB/s", downloadSpeed / (1024 * 1024))
        }
    }
    
    var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }
    
    var formattedSegments: String {
        if let total = totalSegments, total > 0 {
            return "\(downloadedSegments)/\(total)"
        } else {
            return "--/--"
        }
    }
}

struct DownloadTaskSnapshot: Codable {
    let id: UUID
    let url: String
    let fileName: String
    let downloadType: DownloadType
    let status: DownloadStatus
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64?
    let filePath: String?
    let totalSegments: Int?
    let downloadedSegments: Int
}

extension DownloadTask {
    convenience init(snapshot: DownloadTaskSnapshot) {
        self.init(id: snapshot.id, url: snapshot.url, fileName: snapshot.fileName, downloadType: snapshot.downloadType, status: snapshot.status)
        progress = snapshot.progress
        downloadedBytes = snapshot.downloadedBytes
        totalBytes = snapshot.totalBytes
        if let filePath = snapshot.filePath, !filePath.isEmpty {
            self.filePath = URL(fileURLWithPath: filePath)
        } else {
            self.filePath = nil
        }
        downloadSpeed = 0.0
        totalSegments = snapshot.totalSegments
        downloadedSegments = snapshot.downloadedSegments
    }
    
    func makeSnapshot() -> DownloadTaskSnapshot {
        DownloadTaskSnapshot(
            id: id,
            url: url,
            fileName: fileName,
            downloadType: downloadType,
            status: status,
            progress: progress,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            filePath: filePath?.path,
            totalSegments: totalSegments,
            downloadedSegments: downloadedSegments
        )
    }
}

