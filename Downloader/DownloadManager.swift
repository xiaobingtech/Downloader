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
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    
    /// Map task identifiers to DownloadTask objects
    private var taskMap: [Int: DownloadTask] = [:]
    
    // MARK: - Singleton
    
    static let shared = DownloadManager()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Add a new download task
    /// - Parameter urlString: URL string to download
    /// - Returns: Created DownloadTask or nil if URL is invalid
    @discardableResult
    func addTask(urlString: String) -> DownloadTask? {
        guard let url = URL(string: urlString), url.scheme != nil else {
            return nil
        }
        
        let task = DownloadTask(url: url)
        downloadingTasks.append(task)
        startDownload(task)
        return task
    }
    
    /// Start or resume a download task
    func startDownload(_ task: DownloadTask) {
        if let resumeData = task.resumeData {
            // Resume from previous data
            let downloadTask = urlSession.downloadTask(withResumeData: resumeData)
            task.downloadTask = downloadTask
            task.resumeData = nil
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
    }
    
    /// Pause a download task
    func pauseDownload(_ task: DownloadTask) {
        task.downloadTask?.cancel(byProducingResumeData: { [weak task] data in
            task?.resumeData = data
        })
        task.status = .paused
    }
    
    /// Resume a paused download task
    func resumeDownload(_ task: DownloadTask) {
        startDownload(task)
    }
    
    /// Cancel and remove a download task
    func cancelDownload(_ task: DownloadTask) {
        task.downloadTask?.cancel()
        task.status = .failed
        
        if let index = downloadingTasks.firstIndex(where: { $0.id == task.id }) {
            downloadingTasks.remove(at: index)
        }
    }
    
    /// Delete a completed task
    func deleteCompletedTask(_ task: DownloadTask) {
        if let index = completedTasks.firstIndex(where: { $0.id == task.id }) {
            completedTasks.remove(at: index)
        }
    }
    
    // MARK: - Private Methods
    
    private func moveToCompleted(_ task: DownloadTask) {
        task.status = .completed
        task.progress = 1.0
        
        if let index = downloadingTasks.firstIndex(where: { $0.id == task.id }) {
            downloadingTasks.remove(at: index)
        }
        completedTasks.insert(task, at: 0)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let task = taskMap[downloadTask.taskIdentifier] else { return }
        
        // Move file to documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent(task.fileName)
        
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
        }
    }
}
