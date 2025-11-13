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
                        onDelete: { onDelete(task.id) }
                    )
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.displayFileName)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
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
                    Text(task.formattedProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
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
    }
}

