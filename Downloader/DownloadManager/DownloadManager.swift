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
        guard let url = URL(string: task.url) else { return }
        
        let asset = AVURLAsset(url: url)
        let downloadSession = AVAssetDownloadURLSession(
            configuration: .background(withIdentifier: "com.xiaobing.Downloader.m3u8"),
            assetDownloadDelegate: M3U8DownloadDelegate(task: task, manager: self),
            delegateQueue: OperationQueue.main
        )
        
        guard let downloadTask = downloadSession.makeAssetDownloadTask(
            asset: asset,
            assetTitle: task.fileName,
            assetArtworkData: nil,
            options: nil
        ) else {
            task.status = .failed
            return
        }
        
        m3u8Sessions[task.id] = downloadTask
        downloadTask.resume()
        
        // 对于m3u8，使用简化的进度监控
        startM3U8ProgressMonitoring(task: task)
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
        // M3U8下载进度由AVAssetDownloadDelegate的didWriteData方法更新
        // 这里只需要监控下载速度
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
                }
            }
            
            self.lastUpdateTime[task.id] = currentTime
            self.lastDownloadedBytes[task.id] = task.downloadedBytes
        }
        
        speedTimers[task.id] = timer
        RunLoop.current.add(timer, forMode: .common)
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

