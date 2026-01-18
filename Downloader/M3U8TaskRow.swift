//
//  M3U8TaskRow.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import SwiftUI

/// Row view for displaying an M3U8 download task
struct M3U8TaskRow: View {
    @ObservedObject var task: M3U8DownloadTask
    @ObservedObject var manager: M3U8DownloadManager
    
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
                    // Video icon
                    Image(systemName: "film")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    
                    // File info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.fileName)
                            .font(.body)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 8) {
                            Text(task.statusText)
                                .font(.caption)
                                .foregroundStyle(statusTextColor)
                            
                            if let error = task.errorMessage, task.status == .failed {
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
            // Only show pause/resume for downloading/paused states
            if task.status == .downloading || task.status == .paused {
                Button {
                    if task.status == .downloading {
                        manager.pauseDownload(task)
                    } else {
                        manager.resumeDownload(task)
                    }
                } label: {
                    Image(systemName: task.status == .downloading ? "pause.circle" : "play.circle")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // Cancel button (not for merging/converting)
            if task.status == .downloading || task.status == .paused || task.status == .failed {
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
    }
    
    // MARK: - Private Properties
    
    private var progressBackgroundColor: Color {
        switch task.status {
        case .downloading:
            return Color.purple.opacity(0.15)
        case .paused:
            return Color.orange.opacity(0.15)
        case .merging, .converting:
            return Color.blue.opacity(0.15)
        case .completed:
            return Color.green.opacity(0.15)
        case .failed:
            return Color.red.opacity(0.15)
        case .parsing:
            return Color.gray.opacity(0.1)
        }
    }
    
    private var statusTextColor: Color {
        switch task.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .merging, .converting:
            return .blue
        default:
            return .secondary
        }
    }
}

#Preview {
    let task = M3U8DownloadTask(m3u8URL: URL(string: "https://example.com/video.m3u8")!, fileName: "test_video")
    task.setupSegments([
        M3U8Segment(index: 0, url: URL(string: "https://example.com/1.ts")!, duration: 4),
        M3U8Segment(index: 1, url: URL(string: "https://example.com/2.ts")!, duration: 4),
    ])
    task.segmentStates[0] = .completed
    task.status = .downloading
    
    return M3U8TaskRow(task: task, manager: M3U8DownloadManager.shared)
        .padding()
}
