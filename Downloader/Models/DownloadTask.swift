//
//  DownloadTask.swift
//  Downloader
//
//  Created by fanxiaobing on 2025/11/13.
//

import Foundation
import Combine

enum DownloadStatus {
    case downloading
    case paused
    case completed
    case failed
}

enum DownloadType {
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
    }
    
    var displayFileName: String {
        let fileExtension = downloadType == .m3u8 ? "mp4" : (URL(string: url)?.pathExtension ?? "")
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
}

