import SwiftUI

struct SettingsView: View {
    @ObservedObject var scannerService: PhotoScannerService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                scanningOptionsSection
                performanceSection
                deletionOptionsSection
                aboutSection
                tipsSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Section Views
    private var scanningOptionsSection: some View {
        Section("掃描選項") {
            Toggle("啟用視覺相似分析", isOn: $scannerService.settings.enableSimilarDetection)
                .tint(.orange)
            
            if scannerService.settings.enableSimilarDetection {
                similarityThresholdView
            }
            
            Toggle("跳過 HEIC 格式", isOn: $scannerService.settings.skipHEIC)
                .tint(.orange)
        }
    }
    
    private var similarityThresholdView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("相似度敏感度")
                Spacer()
                let percentage = Int((1 - scannerService.settings.similarityThreshold) * 100)
                Text("\(percentage)%")
                    .foregroundColor(.secondary)
            }
            
            let binding = Binding(
                get: { 1 - scannerService.settings.similarityThreshold },
                set: { scannerService.settings.similarityThreshold = 1 - $0 }
            )
            
            Slider(value: binding, in: 0.1...0.9, step: 0.05)
                .tint(.orange)
            
            Text("較高敏感度會找出更多相似圖片，但可能包含誤判")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var performanceSection: some View {
        Section("效能設定") {
            imageSizeView
            photoCountView
            batchSizeView
            cacheSettingsView
        }
    }
    
    private var imageSizeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最大圖片尺寸")
                Spacer()
                let size = Int(scannerService.settings.maxImageDimension)
                Text("\(size)px")
                    .foregroundColor(.secondary)
            }
            
            Slider(value: Binding(
                get: { scannerService.settings.maxImageDimension },
                set: { newValue in
                    scannerService.settings.maxImageDimension = newValue
                    scannerService.settings.objectWillChange.send()
                }
            ), in: 512...2048, step: 256)
                .tint(.orange)
            
            Text("較小尺寸可提升掃描速度，但可能影響相似度判斷準確性")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var photoCountView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最大處理照片數")
                Spacer()
                let count = Int(scannerService.settings.maxPhotosToProcess)
                Text("\(count)")
                    .foregroundColor(.secondary)
            }
            
            Slider(value: Binding(
                get: { scannerService.settings.maxPhotosToProcess },
                set: { newValue in
                    scannerService.settings.maxPhotosToProcess = newValue
                    scannerService.settings.objectWillChange.send()
                }
            ), in: 100...10000, step: 100)
                .tint(.orange)
            
            Text("當照片超過此數量時，會自動分批處理。較大的數量可提升效率，但會消耗更多記憶體。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var batchSizeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("每批處理照片數")
                Spacer()
                let count = Int(scannerService.settings.batchSize)
                Text("\(count)")
                    .foregroundColor(.secondary)
            }
            
            Slider(value: Binding(
                get: { scannerService.settings.batchSize },
                set: { newValue in
                    scannerService.settings.batchSize = newValue
                    // 手動觸發 objectWillChange 以確保 UI 更新
                    scannerService.settings.objectWillChange.send()
                }
            ), in: 50...1000, step: 50)
                .tint(.orange)
            
            Text("每批處理的照片數量。較大的批次可提升效率，但會消耗更多記憶體。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var cacheSettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("啟用掃描緩存", isOn: $scannerService.settings.enableCache)
                .tint(.purple)
            
            if scannerService.settings.enableCache {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("緩存有效期")
                        Spacer()
                        Text("\(Int(scannerService.settings.cacheValidityHours)) 小時")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $scannerService.settings.cacheValidityHours, in: 1...168, step: 1)
                        .tint(.purple)
                }
                
                Button("清除緩存") {
                    scannerService.clearCache()
                }
                .foregroundColor(.red)
                
                Button("清除掃描記錄") {
                    scannerService.clearScanRecords()
                }
                .foregroundColor(.red)

                Text("清除掃描記錄會強制下次掃描所有照片，適用於偵測結果異常時。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("緩存可避免重複掃描相同照片，提升掃描速度。設定變更時會自動清除緩存。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var deletionOptionsSection: some View {
        Section("刪除選項") {
            Toggle("保留最新照片", isOn: $scannerService.settings.keepNewestPhotos)
                .tint(.orange)
            
            if scannerService.settings.keepNewestPhotos {
                Text("在重複組中自動保留拍攝時間最新的照片")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var aboutSection: some View {
        Section("關於") {
            VStack(alignment: .leading, spacing: 12) {
                aboutRow(icon: "shield", color: .green, title: "隱私保護", description: "所有照片分析都在裝置端進行，不會上傳到任何伺服器")
                Divider()
                aboutRow(icon: "brain", color: .blue, title: "AI 技術", description: "使用 Apple Vision 框架進行視覺相似度分析")
                Divider()
                aboutRow(icon: "info.circle", color: .orange, title: "版本資訊", description: "NekoDuplicateFinder v1.0")
            }
            .padding(.vertical, 4)
        }
    }
    
    private func aboutRow(icon: String, color: Color, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .fontWeight(.medium)
            }
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var tipsSection: some View {
        Section("使用小貼士") {
            VStack(alignment: .leading, spacing: 12) {
                tipRow(icon: "clock", title: "掃描時間", description: "照片數量越多，掃描時間越長。建議在充電時進行大量掃描。")
                tipRow(icon: "eye", title: "相似度設定", description: "如果找到太多相似圖片，可以調低敏感度；如果遺漏了重複圖片，可以調高敏感度。")
                tipRow(icon: "trash", title: "安全刪除", description: "刪除前請仔細檢查選中的照片，刪除後無法復原。")
            }
            .padding(.vertical, 4)
        }
    }
    
    private func tipRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    SettingsView(scannerService: PhotoScannerService())
} 