//
//  ContentView.swift
//  Downloader
//
//  Created by fanxiaobing on 2025/11/13.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var selectedSegment = 0
    @State private var showAddAlert = false
    @State private var shareItem: URL?
    
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
                        },
                        onShare: { taskId in
                            if let task = downloadManager.completedTasks.first(where: { $0.id == taskId }),
                               let filePath = task.filePath {
                                shareItem = filePath
                            }
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
            .sheet(item: $shareItem) { url in
                ShareSheet(activityItems: [url])
            }
        }
    }
}

// 扩展 URL 使其符合 Identifiable
extension URL: Identifiable {
    public var id: String {
        self.absoluteString
    }
}

// 系统分享视图
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        // 在 iPad 上需要设置 popover 的锚点
        if let popover = controller.popoverPresentationController {
            // 使用屏幕中心作为锚点
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // 不需要更新
    }
}

#Preview {
    ContentView()
}
