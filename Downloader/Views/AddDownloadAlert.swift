//
//  AddDownloadAlert.swift
//  Downloader
//
//  Created by fanxiaobing on 2025/11/13.
//

import SwiftUI

struct AddDownloadAlert: View {
    @Binding var isPresented: Bool
    @State private var downloadURL: String = ""
    @State private var fileName: String = ""
    let onConfirm: (String, String) -> Void
    
    var body: some View {
        Form {
            Section(header: Text("下载信息")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("下载地址")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("请输入下载地址", text: $downloadURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("文件名（不含后缀）")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("请输入文件名", text: $fileName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocorrectionDisabled()
                }
            }
        }
        .navigationTitle("添加下载任务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") {
                    isPresented = false
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("确定") {
                    if !downloadURL.isEmpty && !fileName.isEmpty {
                        onConfirm(downloadURL, fileName)
                        downloadURL = ""
                        fileName = ""
                        isPresented = false
                    }
                }
                .disabled(downloadURL.isEmpty || fileName.isEmpty)
            }
        }
    }
}

