//
//  DownloadListView.swift
//  Downloader
//
//  Created by fanxiaobing on 2025/11/13.
//

import SwiftUI

struct DownloadListView: View {
    let tasks: [DownloadTask]
    let onPauseResume: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onShare: ((UUID) -> Void)?
    
    init(tasks: [DownloadTask], onPauseResume: @escaping (UUID) -> Void, onDelete: @escaping (UUID) -> Void, onShare: ((UUID) -> Void)? = nil) {
        self.tasks = tasks
        self.onPauseResume = onPauseResume
        self.onDelete = onDelete
        self.onShare = onShare
    }
    
    var body: some View {
        if tasks.isEmpty {
            VStack {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("暂无任务")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(.top)
                Spacer()
            }
        } else {
            List {
                ForEach(tasks) { task in
                    DownloadTaskRow(
                        task: task,
                        onPauseResume: { onPauseResume(task.id) },
                        onDelete: { onDelete(task.id) },
                        onShare: onShare != nil ? { onShare?(task.id) } : nil
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive, action: {
                            onDelete(task.id)
                        }) {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
    }
}

struct DownloadTaskRow: View {
    @ObservedObject var task: DownloadTask
    let onPauseResume: () -> Void
    let onDelete: () -> Void
    let onShare: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.displayFileName)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // 操作按钮（仅暂停/继续，删除已改为左滑）
                if task.status == .downloading || task.status == .paused {
                    Button(action: onPauseResume) {
                        Image(systemName: task.status == .downloading ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            if task.status == .downloading || task.status == .paused {
                ProgressView(value: task.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                
                HStack {
                    if task.downloadType == .m3u8 {
                        Text(task.formattedSegments)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(task.formattedProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(task.formattedSpeed)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if task.status == .completed {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("下载完成")
                        .font(.caption)
                        .foregroundColor(.green)
                    if onShare != nil {
                        Spacer()
                        Text("点击整行分享")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if task.status == .failed {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text("下载失败")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if task.status == .completed {
                onShare?()
            }
        }
    }
}


