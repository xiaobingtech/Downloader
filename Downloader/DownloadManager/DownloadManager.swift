//
//  DownloadManager.swift
//  Downloader
//
//  Created by fanxiaobing on 2025/11/13.
//

import Foundation
import AVFoundation
import Combine

class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    @Published var downloadingTasks: [DownloadTask] = []
    @Published var completedTasks: [DownloadTask] = []
    
    private let downloadingTasksKey = "downloadingTasks"
    private let completedTasksKey = "completedTasks"
    
    private var downloadSessions: [UUID: URLSessionDownloadTask] = [:]
    private var taskIdMap: [Int: UUID] = [:] // Map taskIdentifier to taskId
    private var m3u8Sessions: [UUID: Any] = [:]
    private var speedTimers: [UUID: Timer] = [:]
    private var lastUpdateTime: [UUID: Date] = [:]
    private var lastDownloadedBytes: [UUID: Int64] = [:]
    
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    private override init() {
        super.init()
        loadAllTasks()
    }
    
    // MARK: - Public Methods
    
    func addDownloadTask(url: String, fileName: String) {
        let downloadType: DownloadType = url.lowercased().contains(".m3u8") ? .m3u8 : .directLink
        let task = DownloadTask(url: url, fileName: fileName, downloadType: downloadType)
        
        downloadingTasks.append(task)
        saveAllTasks()
        startDownload(task: task)
    }
    
    func pauseDownload(taskId: UUID) {
        guard let task = downloadingTasks.first(where: { $0.id == taskId }) else { return }
        
        if let downloadTask = downloadSessions[taskId] {
            downloadTask.cancel { [weak self] resumeData in
                if let resumeData = resumeData {
                    // 保存恢复数据以便后续恢复下载
                    UserDefaults.standard.set(resumeData, forKey: "resume_\(taskId.uuidString)")
                }
                DispatchQueue.main.async {
                    task.status = .paused
                    self?.saveAllTasks()
                }
            }
            if let downloadTask = downloadSessions[taskId] {
                taskIdMap.removeValue(forKey: downloadTask.taskIdentifier)
            }
            downloadSessions.removeValue(forKey: taskId)
        }
        
        speedTimers[taskId]?.invalidate()
        speedTimers.removeValue(forKey: taskId)
        lastUpdateTime.removeValue(forKey: taskId)
        lastDownloadedBytes.removeValue(forKey: taskId)
    }
    
    func resumeDownload(taskId: UUID) {
        guard let task = downloadingTasks.first(where: { $0.id == taskId }) else { return }
        
        task.status = .downloading
        startDownload(task: task)
    }
    
    func deleteTask(taskId: UUID) {
        // 删除文件
        if let task = completedTasks.first(where: { $0.id == taskId }),
           let filePath = task.filePath {
            try? FileManager.default.removeItem(at: filePath)
        }
        
        downloadingTasks.removeAll { $0.id == taskId }
        completedTasks.removeAll { $0.id == taskId }
        
        downloadSessions[taskId]?.cancel()
        downloadSessions.removeValue(forKey: taskId)
        speedTimers[taskId]?.invalidate()
        speedTimers.removeValue(forKey: taskId)
        
        saveAllTasks()
    }
    
    // MARK: - Private Methods
    
    private func startDownload(task: DownloadTask) {
        switch task.downloadType {
        case .directLink:
            startDirectDownload(task: task)
        case .m3u8:
            startM3U8Download(task: task)
        }
    }
    
    private func startDirectDownload(task: DownloadTask) {
        guard let url = URL(string: task.url) else { return }
        
        var request = URLRequest(url: url)
        
        // 检查是否有恢复数据
        if let resumeData = UserDefaults.standard.data(forKey: "resume_\(task.id.uuidString)") {
            let downloadTask = urlSession.downloadTask(withResumeData: resumeData)
            downloadSessions[task.id] = downloadTask
            taskIdMap[downloadTask.taskIdentifier] = task.id
            downloadTask.resume()
            UserDefaults.standard.removeObject(forKey: "resume_\(task.id.uuidString)")
        } else {
            let downloadTask = urlSession.downloadTask(with: request)
            downloadSessions[task.id] = downloadTask
            taskIdMap[downloadTask.taskIdentifier] = task.id
            downloadTask.resume()
        }
        
        startSpeedMonitoring(task: task)
    }
    
    private func startM3U8Download(task: DownloadTask) {
        guard let playlistURL = URL(string: task.url) else { return }
        
        // 开始速度监控（基于字节累计）
        startM3U8ProgressMonitoring(task: task)
        
        // 解析分片并下载 -> 合并TS -> 转码MP4 -> 清理
        parseM3U8(playlistURL: playlistURL) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async {
                    task.status = .failed
                    self.saveAllTasks()
                }
            case .success(let segmentURLs):
                DispatchQueue.main.async {
                    task.totalSegments = segmentURLs.count
                    task.progress = 0
                    task.downloadedSegments = 0
                    task.status = .downloading
                }
                self.downloadSegments(segmentURLs: segmentURLs, for: task) { tempFilesResult in
                    switch tempFilesResult {
                    case .failure:
                        DispatchQueue.main.async {
                            task.status = .failed
                            self.speedTimers[task.id]?.invalidate()
                            self.saveAllTasks()
                        }
                    case .success(let tempFiles):
                        // 合并 TS
                        let mergedTS = self.documentsPath.appendingPathComponent("\(task.fileName)_merged.ts")
                        do {
                            try self.mergeTSFiles(inOrder: tempFiles, to: mergedTS)
                        } catch {
                            DispatchQueue.main.async {
                                task.status = .failed
                                self.speedTimers[task.id]?.invalidate()
                                self.saveAllTasks()
                            }
                            // 清理分片
                            tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
                            return
                        }
                        // 清理分片
                        tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
                        
                        // 转码 MP4
                        let outputMP4 = self.documentsPath.appendingPathComponent(task.displayFileName)
                        self.exportTSAsMP4(inputTS: mergedTS, outputMP4: outputMP4) { exportResult in
                            switch exportResult {
                            case .failure:
                                // 转码失败时降级为直接产出合并后的 TS 文件
                                do {
                                    let tsDestination = self.documentsPath.appendingPathComponent("\(task.fileName).ts")
                                    if FileManager.default.fileExists(atPath: tsDestination.path) {
                                        try FileManager.default.removeItem(at: tsDestination)
                                    }
                                    try FileManager.default.moveItem(at: mergedTS, to: tsDestination)
                                    
                                    DispatchQueue.main.async {
                                        task.filePath = tsDestination
                                        task.status = .completed
                                        task.progress = 1.0
                                        if let total = task.totalSegments {
                                            task.downloadedSegments = total
                                        }
                                        
                                        self.downloadingTasks.removeAll { $0.id == task.id }
                                        self.completedTasks.append(task)
                                        
                                        self.m3u8Sessions.removeValue(forKey: task.id)
                                        self.speedTimers[task.id]?.invalidate()
                                        self.speedTimers.removeValue(forKey: task.id)
                                        
                                        self.saveAllTasks()
                                    }
                                } catch {
                                    DispatchQueue.main.async {
                                        task.status = .failed
                                        self.speedTimers[task.id]?.invalidate()
                                        self.saveAllTasks()
                                    }
                                }
                            case .success:
                                // 删除合并后的 TS
                                try? FileManager.default.removeItem(at: mergedTS)
                                
                                DispatchQueue.main.async {
                                    task.filePath = outputMP4
                                    task.status = .completed
                                    task.progress = 1.0
                                    if let total = task.totalSegments {
                                        task.downloadedSegments = total
                                    }
                                    
                                    self.downloadingTasks.removeAll { $0.id == task.id }
                                    self.completedTasks.append(task)
                                    
                                    self.m3u8Sessions.removeValue(forKey: task.id)
                                    self.speedTimers[task.id]?.invalidate()
                                    self.speedTimers.removeValue(forKey: task.id)
                                    
                                    self.saveAllTasks()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func startSpeedMonitoring(task: DownloadTask) {
        lastUpdateTime[task.id] = Date()
        lastDownloadedBytes[task.id] = task.downloadedBytes
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let lastTime = self.lastUpdateTime[task.id],
                  let lastBytes = self.lastDownloadedBytes[task.id] else { return }
            
            let currentTime = Date()
            let timeInterval = currentTime.timeIntervalSince(lastTime)
            
            if timeInterval > 0 {
                let bytesDownloaded = task.downloadedBytes - lastBytes
                let speed = Double(bytesDownloaded) / timeInterval
                
                DispatchQueue.main.async {
                    task.downloadSpeed = speed
                }
            }
            
            self.lastUpdateTime[task.id] = currentTime
            self.lastDownloadedBytes[task.id] = task.downloadedBytes
        }
        
        speedTimers[task.id] = timer
        RunLoop.current.add(timer, forMode: .common)
    }
    
    private func startM3U8ProgressMonitoring(task: DownloadTask) {
        // M3U8下载进度由AVAssetDownloadDelegate的didWriteData方法更新（字节级）
        // 这里通过定时器计算网速，并根据progress与分片总数估算已下载分片数
        lastUpdateTime[task.id] = Date()
        lastDownloadedBytes[task.id] = task.downloadedBytes
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let lastTime = self.lastUpdateTime[task.id],
                  let lastBytes = self.lastDownloadedBytes[task.id],
                  task.status == .downloading else {
                self?.speedTimers[task.id]?.invalidate()
                return
            }
            
            let currentTime = Date()
            let timeInterval = currentTime.timeIntervalSince(lastTime)
            
            if timeInterval > 0 {
                let bytesDownloaded = task.downloadedBytes - lastBytes
                let speed = Double(bytesDownloaded) / timeInterval
                
                DispatchQueue.main.async {
                    task.downloadSpeed = speed
                    if let total = task.totalSegments, total > 0 {
                        let estimated = Int(max(0, min(Double(total), round(task.progress * Double(total)))))
                        task.downloadedSegments = estimated
                    }
                }
            }
            
            self.lastUpdateTime[task.id] = currentTime
            self.lastDownloadedBytes[task.id] = task.downloadedBytes
        }
        
        speedTimers[task.id] = timer
        RunLoop.current.add(timer, forMode: .common)
    }
    
    private func fetchM3U8SegmentCount(from url: URL, completion: @escaping (Int?) -> Void) {
        // 简单解析：下载m3u8文本，统计#EXTINF行数作为分片数
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard error == nil, let data = data, let text = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            // 过滤注释与空行，统计媒体分片行（常见为#EXTINF后跟URI的下一行，但仅用#EXTINF计数更稳妥）
            let lines = text.split(whereSeparator: \.isNewline)
            let total = lines.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTINF") }.count
            completion(total > 0 ? total : nil)
        }
        task.resume()
    }
    
    private func parseM3U8(playlistURL: URL, completion: @escaping (Result<[URL], Error>) -> Void) {
        URLSession.shared.dataTask(with: playlistURL) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                completion(.failure(NSError(domain: "m3u8.parse", code: -1)))
                return
            }
            let baseURL = playlistURL.deletingLastPathComponent()
            var segmentURLs: [URL] = []
            var variantCandidates: [(url: URL, bandwidth: Int?)] = []
            var pendingVariantInfo: String?
            var foundVariantPlaylist = false
            
            let lines = text.components(separatedBy: .newlines)
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                
                if line.hasPrefix("#EXT-X-STREAM-INF") {
                    foundVariantPlaylist = true
                    pendingVariantInfo = line
                    continue
                }
                
                if line.hasPrefix("#") {
                    continue
                }
                
                let resolvedURL: URL
                if let absoluteURL = URL(string: line), absoluteURL.scheme != nil {
                    resolvedURL = absoluteURL
                } else if let relativeURL = URL(string: line, relativeTo: baseURL)?.absoluteURL {
                    resolvedURL = relativeURL
                } else {
                    continue
                }
                
                if let infoLine = pendingVariantInfo {
                    let bandwidth = Self.parseBandwidth(from: infoLine)
                    variantCandidates.append((url: resolvedURL, bandwidth: bandwidth))
                    pendingVariantInfo = nil
                } else {
                    segmentURLs.append(resolvedURL)
                }
            }
            
            if foundVariantPlaylist {
                guard !variantCandidates.isEmpty else {
                    completion(.failure(NSError(domain: "m3u8.master.empty", code: -4)))
                    return
                }
                let selectedVariant = variantCandidates.max { (lhs, rhs) -> Bool in
                    let leftBandwidth = lhs.bandwidth ?? 0
                    let rightBandwidth = rhs.bandwidth ?? 0
                    return leftBandwidth < rightBandwidth
                }?.url ?? variantCandidates[0].url
                
                self.parseM3U8(playlistURL: selectedVariant, completion: completion)
                return
            }
            
            if segmentURLs.isEmpty {
                completion(.failure(NSError(domain: "m3u8.empty", code: -2)))
            } else {
                completion(.success(segmentURLs))
            }
        }.resume()
    }
    
    private static func parseBandwidth(from streamInfoLine: String) -> Int? {
        let components = streamInfoLine
            .replacingOccurrences(of: "#EXT-X-STREAM-INF:", with: "")
            .split(separator: ",")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("BANDWIDTH=") {
                let valuePart = trimmed.dropFirst("BANDWIDTH=".count)
                return Int(valuePart)
            }
        }
        return nil
    }
    
    private func downloadSegments(segmentURLs: [URL], for task: DownloadTask, completion: @escaping (Result<[URL], Error>) -> Void) {
        // 简化实现：顺序下载，避免同时大量连接；可按需优化并发
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("m3u8_\(task.id.uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        var tempFiles: [URL] = []
        var currentIndex = 0
        var accumulatedBytes: Int64 = 0
        
        func downloadNext() {
            if currentIndex >= segmentURLs.count {
                completion(.success(tempFiles))
                return
            }
            let url = segmentURLs[currentIndex]
            let fileURL = tempDir.appendingPathComponent(String(format: "%08d.ts", currentIndex))
            let taskRequest = URLRequest(url: url)
            let dataTask = URLSession.shared.downloadTask(with: taskRequest) { [weak self] location, _, error in
                guard let self = self else { return }
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let location = location else {
                    completion(.failure(NSError(domain: "m3u8.download", code: -3)))
                    return
                }
                do {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                    try FileManager.default.moveItem(at: location, to: fileURL)
                    tempFiles.append(fileURL)
                    
                    // 更新进度
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                    accumulatedBytes += fileSize
                    DispatchQueue.main.async {
                        task.downloadedSegments = tempFiles.count
                        task.progress = Double(tempFiles.count) / Double(segmentURLs.count)
                        task.downloadedBytes = accumulatedBytes
                        task.totalBytes = nil
                    }
                    
                    currentIndex += 1
                    downloadNext()
                } catch {
                    completion(.failure(error))
                }
            }
            dataTask.resume()
        }
        
        downloadNext()
    }
    
    private func mergeTSFiles(inOrder urls: [URL], to output: URL) throws {
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: nil)
        guard let outHandle = try? FileHandle(forWritingTo: output) else {
            throw NSError(domain: "ts.merge", code: -10)
        }
        defer { try? outHandle.close() }
        for url in urls {
            guard let inHandle = try? FileHandle(forReadingFrom: url) else {
                throw NSError(domain: "ts.merge.read", code: -11)
            }
            let data = try inHandle.readToEnd() ?? Data()
            try? inHandle.close()
            try outHandle.seekToEnd()
            try outHandle.write(contentsOf: data)
        }
    }
    
    private func exportTSAsMP4(inputTS: URL, outputMP4: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        if FileManager.default.fileExists(atPath: outputMP4.path) {
            try? FileManager.default.removeItem(at: outputMP4)
        }
        let asset = AVURLAsset(url: inputTS)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(NSError(domain: "av.exporter.nil", code: -20)))
            return
        }
        exporter.outputURL = outputMP4
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.exportAsynchronously {
            switch exporter.status {
            case .completed:
                completion(.success(()))
            case .failed, .cancelled:
                completion(.failure(exporter.error ?? NSError(domain: "av.exporter.failed", code: -21)))
            default:
                completion(.failure(NSError(domain: "av.exporter.unknown", code: -22)))
            }
        }
    }
    
    private func moveFile(from sourceURL: URL, to task: DownloadTask) {
        let destinationURL = documentsPath.appendingPathComponent(task.displayFileName)
        
        do {
            // 如果目标文件已存在，先删除
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            
            DispatchQueue.main.async {
                task.filePath = destinationURL
                task.status = .completed
                task.progress = 1.0
                
                // 移动到已完成列表
                self.downloadingTasks.removeAll { $0.id == task.id }
                self.completedTasks.append(task)
                
                // 清理
                if let downloadTask = self.downloadSessions[task.id] {
                    self.taskIdMap.removeValue(forKey: downloadTask.taskIdentifier)
                }
                self.downloadSessions.removeValue(forKey: task.id)
                self.speedTimers[task.id]?.invalidate()
                self.speedTimers.removeValue(forKey: task.id)
                self.lastUpdateTime.removeValue(forKey: task.id)
                self.lastDownloadedBytes.removeValue(forKey: task.id)
                
                self.saveAllTasks()
            }
        } catch {
            DispatchQueue.main.async {
                task.status = .failed
                self.saveAllTasks()
            }
        }
    }
    
    func completeM3U8Download(task: DownloadTask, fileURL: URL) {
        // AVAssetDownloadURLSession下载的文件在系统管理的目录中
        // 我们需要复制到Documents目录
        let destinationURL = documentsPath.appendingPathComponent(task.displayFileName)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // 尝试复制文件
            try FileManager.default.copyItem(at: fileURL, to: destinationURL)
            
            DispatchQueue.main.async {
                task.filePath = destinationURL
                task.status = .completed
                task.progress = 1.0
                if let total = task.totalSegments {
                    task.downloadedSegments = total
                }
                if let total = task.totalSegments {
                    task.downloadedSegments = total
                }
                
                self.downloadingTasks.removeAll { $0.id == task.id }
                self.completedTasks.append(task)
                
                self.m3u8Sessions.removeValue(forKey: task.id)
                self.speedTimers[task.id]?.invalidate()
                self.speedTimers.removeValue(forKey: task.id)
                
                self.saveAllTasks()
            }
        } catch {
            // 如果复制失败，尝试直接使用原文件路径
            DispatchQueue.main.async {
                task.filePath = fileURL
                task.status = .completed
                task.progress = 1.0
                if let total = task.totalSegments {
                    task.downloadedSegments = total
                }
                
                self.downloadingTasks.removeAll { $0.id == task.id }
                self.completedTasks.append(task)
                
                self.m3u8Sessions.removeValue(forKey: task.id)
                self.speedTimers[task.id]?.invalidate()
                self.speedTimers.removeValue(forKey: task.id)
                
                self.saveAllTasks()
            }
        }
    }
    
    private func saveAllTasks() {
        // 保存所有任务（下载中和已完成的）
        let encoder = JSONEncoder()
        do {
            let downloadingSnapshots = downloadingTasks.map { $0.makeSnapshot() }
            let completedSnapshots = completedTasks.map { $0.makeSnapshot() }
            
            let downloadingData = try encoder.encode(downloadingSnapshots)
            let completedData = try encoder.encode(completedSnapshots)
            
            UserDefaults.standard.set(downloadingData, forKey: downloadingTasksKey)
            UserDefaults.standard.set(completedData, forKey: completedTasksKey)
        } catch {
            print("保存任务失败: \(error)")
        }
    }
    
    private func loadAllTasks() {
        let decoder = JSONDecoder()
        
        // 加载下载中的任务
        if let downloadingData = UserDefaults.standard.data(forKey: downloadingTasksKey) {
            do {
                let snapshots = try decoder.decode([DownloadTaskSnapshot].self, from: downloadingData)
                downloadingTasks = snapshots.map { DownloadTask(snapshot: $0) }
                
                // 恢复暂停的任务状态，但不自动开始下载
                for task in downloadingTasks {
                    if task.status == .downloading {
                        // 如果任务在下载中，恢复为暂停状态（因为应用重启后需要手动恢复）
                        task.status = .paused
                    }
                }
            } catch {
                print("加载下载中任务失败: \(error)")
            }
        }
        
        // 加载已完成的任务
        if let completedData = UserDefaults.standard.data(forKey: completedTasksKey) {
            do {
                let snapshots = try decoder.decode([DownloadTaskSnapshot].self, from: completedData)
                completedTasks = snapshots.compactMap { snapshot in
                    let task = DownloadTask(snapshot: snapshot)
                    if let filePath = task.filePath {
                        if FileManager.default.fileExists(atPath: filePath.path) {
                            return task
                        } else {
                            return nil
                        }
                    }
                    return nil
                }
            } catch {
                print("加载已完成任务失败: \(error)")
                // 如果新格式加载失败，尝试旧格式
                loadCompletedTasksLegacy()
            }
        } else {
            // 尝试加载旧格式
            loadCompletedTasksLegacy()
        }
    }
    
    private func loadCompletedTasksLegacy() {
        // 兼容旧版本的加载方式
        guard let taskData = UserDefaults.standard.array(forKey: completedTasksKey) as? [[String: String]] else { return }
        
        completedTasks = taskData.compactMap { data in
            guard let idString = data["id"],
                  let id = UUID(uuidString: idString),
                  let url = data["url"],
                  let fileName = data["fileName"],
                  let filePathString = data["filePath"] else { return nil }
            
            let filePath = URL(fileURLWithPath: filePathString)
            // 验证文件是否存在
            guard FileManager.default.fileExists(atPath: filePath.path) else { return nil }
            
            let downloadType: DownloadType = url.lowercased().contains(".m3u8") ? .m3u8 : .directLink
            let task = DownloadTask(id: id, url: url, fileName: fileName, downloadType: downloadType, status: .completed)
            task.filePath = filePath
            task.progress = 1.0
            
            return task
        }
        
        // 保存为新格式
        saveAllTasks()
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskId = taskIdMap[downloadTask.taskIdentifier],
              let task = downloadingTasks.first(where: { $0.id == taskId }) else {
            return
        }
        
        moveFile(from: location, to: task)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let taskId = taskIdMap[downloadTask.taskIdentifier],
              let task = downloadingTasks.first(where: { $0.id == taskId }) else {
            return
        }
        
        DispatchQueue.main.async {
            task.downloadedBytes = totalBytesWritten
            task.totalBytes = totalBytesExpectedToWrite
            
            if totalBytesExpectedToWrite > 0 {
                task.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let taskId = taskIdMap[downloadTask.taskIdentifier],
              let downloadTaskModel = downloadingTasks.first(where: { $0.id == taskId }) else {
            return
        }
        
        if let error = error {
            // 如果是取消操作，不标记为失败
            if (error as NSError).code == NSURLErrorCancelled {
                taskIdMap.removeValue(forKey: downloadTask.taskIdentifier)
                return
            }
            
            DispatchQueue.main.async {
                downloadTaskModel.status = .failed
                self.saveAllTasks()
            }
        }
        
        taskIdMap.removeValue(forKey: downloadTask.taskIdentifier)
        downloadSessions.removeValue(forKey: downloadTaskModel.id)
        speedTimers[downloadTaskModel.id]?.invalidate()
        speedTimers.removeValue(forKey: downloadTaskModel.id)
        lastUpdateTime.removeValue(forKey: downloadTaskModel.id)
        lastDownloadedBytes.removeValue(forKey: downloadTaskModel.id)
    }
}

// MARK: - M3U8 Download Delegate

class M3U8DownloadDelegate: NSObject, AVAssetDownloadDelegate {
    weak var task: DownloadTask?
    weak var manager: DownloadManager?
    
    init(task: DownloadTask, manager: DownloadManager) {
        self.task = task
        self.manager = manager
    }
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let task = task, let manager = manager else { return }
        manager.completeM3U8Download(task: task, fileURL: location)
    }
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let task = task else { return }
        
        DispatchQueue.main.async {
            task.downloadedBytes = totalBytesWritten
            task.totalBytes = totalBytesExpectedToWrite
            
            if totalBytesExpectedToWrite > 0 {
                task.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = self.task else { return }
        
        if let error = error {
            DispatchQueue.main.async {
                downloadTask.status = .failed
            }
        }
    }
}

