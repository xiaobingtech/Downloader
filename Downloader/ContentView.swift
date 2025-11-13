//
//  ContentView.swift
//  Downloader
//
//  Created by fanxiaobing on 2025/11/13.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var selectedSegment = 0
    @State private var showAddAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segment Control
                Picker("", selection: $selectedSegment) {
                    Text("下载中").tag(0)
                    Text("已下载").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content
                if selectedSegment == 0 {
                    DownloadListView(
                        tasks: downloadManager.downloadingTasks,
                        onPauseResume: { taskId in
                            let task = downloadManager.downloadingTasks.first { $0.id == taskId }
                            if task?.status == .downloading {
                                downloadManager.pauseDownload(taskId: taskId)
                            } else if task?.status == .paused {
                                downloadManager.resumeDownload(taskId: taskId)
                            }
                        },
                        onDelete: { taskId in
                            downloadManager.deleteTask(taskId: taskId)
                        }
                    )
                } else {
                    DownloadListView(
                        tasks: downloadManager.completedTasks,
                        onPauseResume: { _ in },
                        onDelete: { taskId in
                            downloadManager.deleteTask(taskId: taskId)
                        }
                    )
                }
            }
            .navigationTitle("下载器")
            .overlay(
                // Add Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            showAddAlert = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding()
                    }
                }
            )
            .sheet(isPresented: $showAddAlert) {
                NavigationView {
                    AddDownloadAlert(
                        isPresented: $showAddAlert,
                        onConfirm: { url, fileName in
                            downloadManager.addDownloadTask(url: url, fileName: fileName)
                        }
                    )
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
