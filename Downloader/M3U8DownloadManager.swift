//
//  M3U8DownloadManager.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import Foundation
import Combine

/// Manager for M3U8 download operations
class M3U8DownloadManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var downloadingTasks: [M3U8DownloadTask] = []
    @Published var completedTasks: [M3U8DownloadTask] = []
    
    // MARK: - Private Properties
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 3  // Limit concurrent downloads
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    
    /// Map URLSession task ID to (M3U8Task, segmentIndex)
    private var taskMap: [Int: (M3U8DownloadTask, Int)] = [:]
    
    /// Active download tasks per M3U8 task
    private var activeDownloads: [UUID: Set<Int>] = [:]
    
    /// Maximum concurrent segment downloads
    private let maxConcurrentDownloads = 3
    
    /// Cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Persistence
    
    private var tasksFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("m3u8_tasks.json")
    }
    
    // MARK: - Singleton
    
    static let shared = M3U8DownloadManager()
    
    private override init() {
        super.init()
        loadTasks()
        setupAutoSave()
    }
    
    // MARK: - Persistence Methods
    
    private func loadTasks() {
        guard FileManager.default.fileExists(atPath: tasksFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: tasksFileURL)
            let savedData = try JSONDecoder().decode(SavedM3U8TasksData.self, from: data)
            
            downloadingTasks = savedData.downloadingTasks.compactMap { taskData in
                guard URL(string: taskData.m3u8URLString) != nil else { return nil }
                let task = M3U8DownloadTask(from: taskData)
                // Mark as paused if was downloading
                if task.status == .downloading {
                    task.status = .paused
                }
                return task
            }
            
            completedTasks = savedData.completedTasks.compactMap { taskData in
                guard URL(string: taskData.m3u8URLString) != nil else { return nil }
                return M3U8DownloadTask(from: taskData)
            }
        } catch {
            print("Failed to load M3U8 tasks: \(error)")
        }
    }
    
    func saveTasks() {
        let savedData = SavedM3U8TasksData(
            downloadingTasks: downloadingTasks.map { $0.toData() },
            completedTasks: completedTasks.map { $0.toData() }
        )
        
        do {
            let data = try JSONEncoder().encode(savedData)
            try data.write(to: tasksFileURL)
        } catch {
            print("Failed to save M3U8 tasks: \(error)")
        }
    }
    
    private func setupAutoSave() {
        $downloadingTasks
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveTasks() }
            .store(in: &cancellables)
        
        $completedTasks
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveTasks() }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Add a new M3U8 download task
    @discardableResult
    func addTask(urlString: String, fileName: String? = nil) async -> M3U8DownloadTask? {
        guard let url = URL(string: urlString) else { return nil }
        
        let task = M3U8DownloadTask(m3u8URL: url, fileName: fileName)
        
        await MainActor.run {
            downloadingTasks.append(task)
        }
        
        // Parse m3u8
        do {
            let segments = try await M3U8Parser.fetch(from: url)
            guard !segments.isEmpty else {
                throw M3U8Error.noSegmentsFound
            }
            
            await MainActor.run {
                task.setupSegments(segments)
                task.status = .downloading
                self.startDownloadingSegments(for: task)
                self.saveTasks()
            }
        } catch {
            await MainActor.run {
                task.status = .failed
                task.errorMessage = "Parse failed: \(error.localizedDescription) (\(error))"
                self.saveTasks()
            }
        }
        
        return task
    }
    
    /// Pause a download task
    func pauseDownload(_ task: M3U8DownloadTask) {
        task.status = .paused
        
        // Cancel all active downloads for this task
        for (sessionTaskID, (m3u8Task, _)) in taskMap where m3u8Task.id == task.id {
            urlSession.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == sessionTaskID }?.cancel()
            }
        }
        
        activeDownloads[task.id] = nil
        saveTasks()
    }
    
    /// Resume a paused download task
    func resumeDownload(_ task: M3U8DownloadTask) {
        task.status = .downloading
        startDownloadingSegments(for: task)
        saveTasks()
    }
    
    /// Cancel and remove a download task
    func cancelDownload(_ task: M3U8DownloadTask) {
        pauseDownload(task)
        task.status = .failed
        task.cleanupSegments()
        
        if let index = downloadingTasks.firstIndex(where: { $0.id == task.id }) {
            downloadingTasks.remove(at: index)
        }
        saveTasks()
    }
    
    /// Delete a completed task
    /// - Parameters:
    ///   - task: The task to delete
    ///   - deleteFile: Whether to delete the local file as well
    func deleteCompletedTask(_ task: M3U8DownloadTask, deleteFile: Bool = false) {
        if let index = completedTasks.firstIndex(where: { $0.id == task.id }) {
            completedTasks.remove(at: index)
        }
        
        if deleteFile {
            try? FileManager.default.removeItem(at: task.mp4Path)
        }
        
        saveTasks()
    }
    
    // MARK: - Internal Methods
    
    private func startDownloadingSegments(for task: M3U8DownloadTask) {
        guard task.status == .downloading else { return }
        
        var active = activeDownloads[task.id] ?? []
        
        while active.count < maxConcurrentDownloads {
            guard let nextIndex = task.nextSegmentToDownload() else { break }
            guard !active.contains(nextIndex) else { continue }
            
            active.insert(nextIndex)
            task.segmentStates[nextIndex] = .downloading
            
            let segment = task.segments[nextIndex]
            let downloadTask = urlSession.downloadTask(with: segment.url)
            taskMap[downloadTask.taskIdentifier] = (task, nextIndex)
            downloadTask.resume()
        }
        
        activeDownloads[task.id] = active
    }
    
    private func handleSegmentCompleted(task: M3U8DownloadTask, segmentIndex: Int, fileURL: URL) {
        // Move file to segment path
        let destinationURL = task.segmentPath(at: segmentIndex)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: fileURL, to: destinationURL)
            task.segmentStates[segmentIndex] = .completed
        } catch {
            task.segmentStates[segmentIndex] = .failed
            task.retryCount[segmentIndex] += 1
        }
        
        // Remove from active
        activeDownloads[task.id]?.remove(segmentIndex)
        
        // Check if all completed
        if task.allSegmentsCompleted {
            Task {
                await mergeAndConvert(task: task)
            }
        } else {
            // Start next segment
            startDownloadingSegments(for: task)
        }
        
        saveTasks()
    }
    
    private func handleSegmentFailed(task: M3U8DownloadTask, segmentIndex: Int, error: Error) {
        task.segmentStates[segmentIndex] = .failed
        task.retryCount[segmentIndex] += 1
        activeDownloads[task.id]?.remove(segmentIndex)
        
        // Check if should retry
        if task.shouldRetry(at: segmentIndex) {
            startDownloadingSegments(for: task)
        } else if !task.segmentStates.contains(.downloading) && !task.segmentStates.contains(.waiting) {
            // All done but some failed
            task.status = .failed
            task.errorMessage = "Some segments failed to download"
        }
        
        saveTasks()
    }
    
    private func mergeAndConvert(task: M3U8DownloadTask) async {
        await MainActor.run {
            task.status = .merging
        }
        
        // Merge segments
        let segmentPaths = (0..<task.totalCount).map { task.segmentPath(at: $0) }
        
        do {
            try TSMerger.merge(segmentPaths: segmentPaths, to: task.mergedTSPath)
        } catch {
            await MainActor.run {
                task.status = .failed
                task.errorMessage = "Merge failed: \(error.localizedDescription) (\(error))"
                self.saveTasks()
            }
            return
        }
            
        await MainActor.run {
            task.status = .converting
        }
            
        // Convert to MP4
        do {
            // Validate merged file
            let attr = try FileManager.default.attributesOfItem(atPath: task.mergedTSPath.path)
            let fileSize = attr[.size] as? UInt64 ?? 0
            if fileSize == 0 {
                throw NSError(domain: "Conversion", code: -1, userInfo: [NSLocalizedDescriptionKey: "Merged file is empty"])
            }
            
            // Check first few bytes
            let handle = try FileHandle(forReadingFrom: task.mergedTSPath)
            let headerData = handle.readData(ofLength: 10)
            try handle.close()
            
            if let headerString = String(data: headerData, encoding: .utf8), 
               headerString.lowercased().contains("html") || headerString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                throw NSError(domain: "Conversion", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid file content (looks like HTML/XML)"])
            }
            
            try await MP4Converter.convert(from: task.mergedTSPath, to: task.mp4Path)
            
            // Cleanup
            task.cleanupSegments()
            try? FileManager.default.removeItem(at: task.mergedTSPath)
            
            await MainActor.run {
                self.moveToCompleted(task)
            }
        } catch {
            await MainActor.run {
                task.status = .failed
                let path = task.mergedTSPath.path
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
                task.errorMessage = "Convert failed: \(error.localizedDescription) (File: \(path), Size: \(size))"
                self.saveTasks()
            }
        }
    }
    
    private func moveToCompleted(_ task: M3U8DownloadTask) {
        task.status = .completed
        
        if let index = downloadingTasks.firstIndex(where: { $0.id == task.id }) {
            downloadingTasks.remove(at: index)
        }
        completedTasks.insert(task, at: 0)
        saveTasks()
    }
}

// MARK: - URLSessionDownloadDelegate

extension M3U8DownloadManager: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (task, segmentIndex) = taskMap[downloadTask.taskIdentifier] else { return }
        taskMap.removeValue(forKey: downloadTask.taskIdentifier)
        handleSegmentCompleted(task: task, segmentIndex: segmentIndex, fileURL: location)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error,
              let (m3u8Task, segmentIndex) = taskMap[task.taskIdentifier] else { return }
        taskMap.removeValue(forKey: task.taskIdentifier)
        handleSegmentFailed(task: m3u8Task, segmentIndex: segmentIndex, error: error)
    }
}

// MARK: - Persistence Data

private struct SavedM3U8TasksData: Codable {
    let downloadingTasks: [M3U8TaskData]
    let completedTasks: [M3U8TaskData]
}
