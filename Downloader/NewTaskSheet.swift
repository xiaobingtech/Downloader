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
    
    @State private var urlText: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
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
                    Text("开始下载")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(isValidInput ? Color.blue : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!isValidInput)
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
                }
            }
        }
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Private Methods
    
    private func createDownloadTask() {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let _ = URL(string: trimmedURL), trimmedURL.hasPrefix("http") else {
            showError = true
            errorMessage = "请输入有效的下载链接"
            return
        }
        
        if manager.addTask(urlString: trimmedURL) != nil {
            dismiss()
        } else {
            showError = true
            errorMessage = "创建下载任务失败"
        }
    }
}

#Preview {
    NewTaskSheet(manager: DownloadManager.shared)
}
