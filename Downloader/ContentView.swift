//
//  ContentView.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import SwiftUI

/// Main content view with segmented control and download lists
struct ContentView: View {
    @StateObject private var manager = DownloadManager.shared
    
    @State private var selectedTab: Int = 0
    @State private var showNewTaskSheet: Bool = false
    
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
                NewTaskSheet(manager: manager)
            }
        }
    }
    
    // MARK: - Private Views
    
    /// List of downloading/paused tasks
    private var downloadingList: some View {
        Group {
            if manager.downloadingTasks.isEmpty {
                emptyStateView(
                    icon: "arrow.down.circle",
                    title: "暂无下载任务",
                    subtitle: "点击右下角 + 按钮添加下载"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
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
            if manager.completedTasks.isEmpty {
                emptyStateView(
                    icon: "checkmark.circle",
                    title: "暂无已完成任务",
                    subtitle: "完成下载后会显示在这里"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
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
    
    /// Row for completed task with delete action
    private func completedTaskRow(_ task: DownloadTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.fileName)
                    .font(.body)
                    .lineLimit(1)
                
                Text(task.sizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
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
        .frame(height: 56)
        .background(Color(.systemBackground))
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
