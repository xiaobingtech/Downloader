//
//  DownloadManager.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import Foundation
import Combine

/// Manager class handling all download operations
class DownloadManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// Tasks currently downloading or paused
    @Published var downloadingTasks: [DownloadTask] = []
    /// Completed download tasks
    @Published var completedTasks: [DownloadTask] = []
    
    // MARK: - Private Properties
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.downloader.background")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    
    /// Map task identifiers to DownloadTask objects
    private var taskMap: [Int: DownloadTask] = [:]
    
    /// Cancellables for observing task changes
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Persistence
    
    private static let downloadingTasksKey = "downloadingTasks"
    private static let completedTasksKey = "completedTasks"
    
    private var tasksFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("tasks.json")
    }
    
    // MARK: - Singleton
    
    static let shared = DownloadManager()
    
    private override init() {
        super.init()
        loadTasks()
        setupAutoSave()
    }
    
    // MARK: - Persistence Methods
    
    /// Load tasks from persistent storage
    private func loadTasks() {
        guard FileManager.default.fileExists(atPath: tasksFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: tasksFileURL)
            let decoder = JSONDecoder()
            let savedData = try decoder.decode(SavedTasksData.self, from: data)
            
            // Restore downloading tasks
            downloadingTasks = savedData.downloadingTasks.compactMap { taskData in
                guard URL(string: taskData.urlString) != nil else { return nil }
                return DownloadTask(from: taskData)
            }
            
            // Restore completed tasks
            completedTasks = savedData.completedTasks.compactMap { taskData in
                guard URL(string: taskData.urlString) != nil else { return nil }
                return DownloadTask(from: taskData)
            }
            
            // Resume downloading tasks that were in progress
            for task in downloadingTasks {
                if task.status == .downloading || task.status == .waiting {
                    task.status = .paused  // Mark as paused initially
                }
            }
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }
    
    /// Save tasks to persistent storage
    func saveTasks() {
        let savedData = SavedTasksData(
            downloadingTasks: downloadingTasks.map { $0.toData() },
            completedTasks: completedTasks.map { $0.toData() }
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(savedData)
            try data.write(to: tasksFileURL)
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }
    
    /// Setup auto-save when tasks change
    private func setupAutoSave() {
        // Debounce saves to avoid too frequent writes
        $downloadingTasks
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveTasks()
            }
            .store(in: &cancellables)
        
        $completedTasks
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveTasks()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Add a new download task
    /// - Parameter urlString: URL string to download
    /// - Parameter fileName: Optional custom file name
    /// - Returns: Created DownloadTask or nil if URL is invalid
    @discardableResult
    func addTask(urlString: String, fileName: String? = nil) -> DownloadTask? {
        guard let url = URL(string: urlString), url.scheme != nil else {
            return nil
        }
        
        let task = DownloadTask(url: url, fileName: fileName)
        downloadingTasks.append(task)
        startDownload(task)
        saveTasks()
        return task
    }
    
    /// Start or resume a download task
    func startDownload(_ task: DownloadTask) {
        if let resumeData = task.resumeData {
            // Resume from previous data
            let downloadTask = urlSession.downloadTask(withResumeData: resumeData)
            task.downloadTask = downloadTask
            task.resumeData = nil
            task.deleteResumeData()  // Clean up saved resume data file
            taskMap[downloadTask.taskIdentifier] = task
            downloadTask.resume()
        } else {
            // Start new download
            let downloadTask = urlSession.downloadTask(with: task.url)
            task.downloadTask = downloadTask
            taskMap[downloadTask.taskIdentifier] = task
            downloadTask.resume()
        }
        task.status = .downloading
        saveTasks()
    }
    
    /// Pause a download task
    func pauseDownload(_ task: DownloadTask) {
        task.downloadTask?.cancel(byProducingResumeData: { [weak self, weak task] data in
            task?.resumeData = data
            task?.status = .paused
            self?.saveTasks()
        })
    }
    
    /// Resume a paused download task
    func resumeDownload(_ task: DownloadTask) {
        startDownload(task)
    }
    
    /// Cancel and remove a download task
    func cancelDownload(_ task: DownloadTask) {
        task.downloadTask?.cancel()
        task.status = .failed
        task.deleteResumeData()
        
        if let index = downloadingTasks.firstIndex(where: { $0.id == task.id }) {
            downloadingTasks.remove(at: index)
        }
        saveTasks()
    }
    
    /// Delete a completed task
    func deleteCompletedTask(_ task: DownloadTask) {
        if let index = completedTasks.firstIndex(where: { $0.id == task.id }) {
            completedTasks.remove(at: index)
        }
        saveTasks()
    }
    
    // MARK: - Private Methods
    
    private func moveToCompleted(_ task: DownloadTask) {
        task.status = .completed
        task.progress = 1.0
        task.deleteResumeData()
        
        if let index = downloadingTasks.firstIndex(where: { $0.id == task.id }) {
            downloadingTasks.remove(at: index)
        }
        completedTasks.insert(task, at: 0)
        saveTasks()
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let task = taskMap[downloadTask.taskIdentifier] else { return }
        
        // Move file to documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = documentsPath.appendingPathComponent("Downloads")
        
        // Create downloads directory if needed
        if !FileManager.default.fileExists(atPath: downloadsDir.path) {
            try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        }
        
        let destinationURL = downloadsDir.appendingPathComponent(task.fileName)
        
        do {
            // Remove existing file if exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            moveToCompleted(task)
        } catch {
            task.status = .failed
            task.errorMessage = error.localizedDescription
            saveTasks()
        }
        
        taskMap.removeValue(forKey: downloadTask.taskIdentifier)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let task = taskMap[downloadTask.taskIdentifier] else { return }
        
        task.downloadedBytes = totalBytesWritten
        task.totalBytes = totalBytesExpectedToWrite
        
        if totalBytesExpectedToWrite > 0 {
            task.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let dlTask = taskMap[downloadTask.taskIdentifier] else { return }
        
        if let error = error as NSError? {
            // Check if it's a cancellation with resume data
            if error.code == NSURLErrorCancelled {
                // User cancelled - don't mark as failed
                return
            }
            dlTask.status = .failed
            dlTask.errorMessage = error.localizedDescription
            saveTasks()
        }
    }
    
    // Handle background session events
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // App was relaunched due to background download completion
        saveTasks()
    }
}

// MARK: - Persistence Data Structure

private struct SavedTasksData: Codable {
    let downloadingTasks: [DownloadTaskData]
    let completedTasks: [DownloadTaskData]
}
