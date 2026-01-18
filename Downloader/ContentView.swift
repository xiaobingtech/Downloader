//
//  ContentView.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import SwiftUI
import QuickLook

/// Main content view with segmented control and download lists
struct ContentView: View {
    @StateObject private var manager = DownloadManager.shared
    @StateObject private var m3u8Manager = M3U8DownloadManager.shared
    
    @State private var selectedTab: Int = 0
    @State private var showNewTaskSheet: Bool = false
    @State private var previewURL: URL?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control
                Picker("", selection: $selectedTab) {
                    Text("下载中").tag(0)
                    Text("已下载").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Task list
                if selectedTab == 0 {
                    downloadingList
                } else {
                    completedList
                }
            }
            .navigationTitle("下载器")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                // Floating add button
                addButton
            }
            .sheet(isPresented: $showNewTaskSheet) {
                NewTaskSheet(manager: manager, m3u8Manager: m3u8Manager)
            }
        }
        .quickLookPreview($previewURL)
    }
    
    // MARK: - Private Views
    
    /// Check if downloading list is empty
    private var isDownloadingEmpty: Bool {
        manager.downloadingTasks.isEmpty && m3u8Manager.downloadingTasks.isEmpty
    }
    
    /// Check if completed list is empty
    private var isCompletedEmpty: Bool {
        manager.completedTasks.isEmpty && m3u8Manager.completedTasks.isEmpty
    }
    
    /// List of downloading/paused tasks
    private var downloadingList: some View {
        Group {
            if isDownloadingEmpty {
                emptyStateView(
                    icon: "arrow.down.circle",
                    title: "暂无下载任务",
                    subtitle: "点击右下角 + 按钮添加下载"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // M3U8 tasks
                        ForEach(m3u8Manager.downloadingTasks) { task in
                            M3U8TaskRow(task: task, manager: m3u8Manager)
                        }
                        
                        // Normal tasks
                        ForEach(manager.downloadingTasks) { task in
                            DownloadTaskRow(task: task, manager: manager)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    /// List of completed tasks
    private var completedList: some View {
        Group {
            if isCompletedEmpty {
                emptyStateView(
                    icon: "checkmark.circle",
                    title: "暂无已完成任务",
                    subtitle: "完成下载后会显示在这里"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // M3U8 completed tasks
                        ForEach(m3u8Manager.completedTasks) { task in
                            completedM3U8TaskRow(task)
                        }
                        
                        // Normal completed tasks
                        ForEach(manager.completedTasks) { task in
                            completedTaskRow(task)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    /// Row for completed normal task
    private func completedTaskRow(_ task: DownloadTask) -> some View {
        ZStack {
            Color(.systemBackground)
                .contentShape(Rectangle())
                .onTapGesture {
                    previewURL = task.destinationURL
                }
            
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                Text(task.fileName)
                    .font(.body)
                    .lineLimit(1)
                
                Spacer()
                
                Button {
                    manager.deleteCompletedTask(task)
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    /// Row for completed M3U8 task
    private func completedM3U8TaskRow(_ task: M3U8DownloadTask) -> some View {
        ZStack {
            Color(.systemBackground)
                .contentShape(Rectangle())
                .onTapGesture {
                    previewURL = task.mp4Path
                }
            
            HStack(spacing: 12) {
                Image(systemName: "film.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                
                Text(task.fileName + ".mp4")
                    .font(.body)
                    .lineLimit(1)
                
                Spacer()
                
                Button {
                    m3u8Manager.deleteCompletedTask(task)
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    /// Empty state placeholder view
    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// Floating add button
    private var addButton: some View {
        Button {
            showNewTaskSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

#Preview {
    ContentView()
}
