//
//  DownloadTaskRow.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import SwiftUI

/// Row view for displaying a download task with progress background
struct DownloadTaskRow: View {
    @ObservedObject var task: DownloadTask
    @ObservedObject var manager: DownloadManager
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Progress background
                Rectangle()
                    .fill(progressBackgroundColor)
                    .frame(width: geometry.size.width * task.progress)
                    .animation(.linear(duration: 0.1), value: task.progress)
                
                // Content
                HStack(spacing: 12) {
                    // File info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.fileName)
                            .font(.body)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 8) {
                            Text(task.progressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if !task.sizeText.isEmpty {
                                Text(task.sizeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let error = task.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    if task.status != .completed {
                        actionButtons
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(height: 56)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Private Views
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Pause/Resume button
            Button {
                if task.status == .downloading {
                    manager.pauseDownload(task)
                } else if task.status == .paused {
                    manager.resumeDownload(task)
                }
            } label: {
                Image(systemName: task.status == .downloading ? "pause.circle" : "play.circle")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .disabled(task.status == .completed || task.status == .failed)
            
            // Cancel button
            Button {
                manager.cancelDownload(task)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Private Properties
    
    private var progressBackgroundColor: Color {
        switch task.status {
        case .downloading:
            return Color.blue.opacity(0.15)
        case .paused:
            return Color.orange.opacity(0.15)
        case .completed:
            return Color.green.opacity(0.15)
        case .failed:
            return Color.red.opacity(0.15)
        case .waiting:
            return Color.gray.opacity(0.1)
        }
    }
}

#Preview {
    VStack {
        let task = DownloadTask(url: URL(string: "https://example.com/file.zip")!)
        task.progress = 0.45
        task.status = .downloading
        task.totalBytes = 1024 * 1024 * 100
        task.downloadedBytes = 1024 * 1024 * 45
        return DownloadTaskRow(task: task, manager: DownloadManager.shared)
    }
    .padding()
}
