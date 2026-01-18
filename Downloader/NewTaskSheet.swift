//
//  NewTaskSheet.swift
//  Downloader
//
//  Created by fandong on 2026/1/17.
//

import SwiftUI

/// Sheet view for creating a new download task
struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: DownloadManager
    @ObservedObject var m3u8Manager: M3U8DownloadManager
    
    @State private var urlText: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    
    /// Check if URL is m3u8
    private var isM3U8URL: Bool {
        urlText.lowercased().contains(".m3u8")
    }
    
    /// Check if input is valid (non-empty and valid URL)
    private var isValidInput: Bool {
        guard !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let url = URL(string: urlText), url.scheme != nil else {
            return false
        }
        return true
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // URL Input field
                VStack(alignment: .leading, spacing: 8) {
                    Text("下载链接")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("请输入下载链接", text: $urlText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                
                // URL type indicator
                if isValidInput {
                    HStack {
                        Image(systemName: isM3U8URL ? "film" : "doc")
                            .foregroundStyle(isM3U8URL ? .purple : .blue)
                        Text(isM3U8URL ? "M3U8视频链接" : "普通文件链接")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                
                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                // Download button
                Button {
                    createDownloadTask()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isLoading ? "解析中..." : "开始下载")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(isValidInput && !isLoading ? Color.blue : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!isValidInput || isLoading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .navigationTitle("创建下载任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isLoading)
    }
    
    // MARK: - Private Methods
    
    private func createDownloadTask() {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let _ = URL(string: trimmedURL), trimmedURL.hasPrefix("http") else {
            showError = true
            errorMessage = "请输入有效的下载链接"
            return
        }
        
        showError = false
        
        if isM3U8URL {
            // M3U8 download
            isLoading = true
            Task {
                let task = await m3u8Manager.addTask(urlString: trimmedURL)
                await MainActor.run {
                    isLoading = false
                    if task != nil {
                        dismiss()
                    } else {
                        showError = true
                        errorMessage = "解析M3U8文件失败"
                    }
                }
            }
        } else {
            // Normal download
            if manager.addTask(urlString: trimmedURL) != nil {
                dismiss()
            } else {
                showError = true
                errorMessage = "创建下载任务失败"
            }
        }
    }
}

#Preview {
    NewTaskSheet(manager: DownloadManager.shared, m3u8Manager: M3U8DownloadManager.shared)
}
