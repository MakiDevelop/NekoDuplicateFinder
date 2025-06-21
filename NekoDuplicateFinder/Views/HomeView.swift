import SwiftUI
import Photos

struct HomeView: View {
    @ObservedObject var scannerService: PhotoScannerService
    @State private var showingSettings = false
    @State private var showingScanningView = false
    @State private var showingWarning = false
    @State private var estimatedPhotoCount = 0
    @State private var isCheckingPhotoCount = false
    @State private var showingBatchProcessingAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header with cat icon
                VStack(spacing: 16) {
                    Image(systemName: "pawprint.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.orange)
                    
                    Text("NekoDuplicateFinder")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("🐾 幫你找出重複照片，釋放更多空間")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Main action button
                VStack(spacing: 20) {
                    Button(action: {
                        Task {
                            await checkPhotoCountAndStartScanning()
                        }
                    }) {
                        HStack(spacing: 12) {
                            if isCheckingPhotoCount {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                            }
                            
                            Text(isCheckingPhotoCount ? "檢查照片中..." : "開始掃描重複照片")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: isCheckingPhotoCount ? [.gray, .gray] : [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: isCheckingPhotoCount ? .gray.opacity(0.3) : .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(scannerService.isScanning || isCheckingPhotoCount)
                    
                    // Settings button
                    Button(action: {
                        showingSettings = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape")
                                .font(.body)
                            Text("設定")
                                .font(.body)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .disabled(isCheckingPhotoCount)
                }
                
                Spacer()
                
                // Features preview
                VStack(spacing: 16) {
                    Text("✨ 功能特色")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        FeatureRow(icon: "doc.on.doc", title: "完全重複偵測", description: "100% 相同的照片")
                        FeatureRow(icon: "eye", title: "視覺相似分析", description: "使用 AI 找出相似圖片")
                        FeatureRow(icon: "shield", title: "隱私保護", description: "全程裝置端處理")
                        FeatureRow(icon: "trash", title: "批次刪除", description: "安全確認後一次刪除")
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .padding(.horizontal, 24)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingScanningView) {
            ScanningView(scannerService: scannerService)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(scannerService: scannerService)
        }
        .alert("大量照片警告", isPresented: $showingWarning) {
            Button("繼續掃描") {
                showingScanningView = true
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("檢測到約 \(estimatedPhotoCount) 張照片，處理時間可能較長且可能消耗較多記憶體。建議先處理較小數量的照片。")
        }
        .confirmationDialog("批次處理選項", isPresented: $showingBatchProcessingAlert, titleVisibility: .visible) {
            Button("處理全部照片（分批）") {
                showingScanningView = true
                Task {
                    await scannerService.startScan(fullScan: true)
                }
            }
            Button("只處理前 \(Int(scannerService.settings.maxPhotosToProcess)) 張") {
                showingScanningView = true
                Task {
                    await scannerService.startScan(fullScan: false)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("檢測到超過 \(Int(scannerService.settings.maxPhotosToProcess)) 張照片。\n\n• 處理全部照片：會分批處理所有照片，速度較慢。\n• 處理部分照片：只處理最新的照片，速度較快。")
        }
    }
    
    private func checkPhotoCountAndStartScanning() async {
        print("[DEBUG] checkPhotoCountAndStartScanning - starting")
        isCheckingPhotoCount = true
        
        // Add a small delay to show the loading state
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Estimate photo count before starting
        let fetchOptions = PHFetchOptions()
        let fetchResult = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: fetchOptions)
        let totalPhotos = fetchResult.count
        let photosToProcess = min(totalPhotos, Int(scannerService.settings.maxPhotosToProcess))
        
        print("[DEBUG] Photo count check - totalPhotos: \(totalPhotos), photosToProcess: \(photosToProcess)")
        
        estimatedPhotoCount = photosToProcess
        
        isCheckingPhotoCount = false
        
        // Show different options based on photo count
        if totalPhotos > Int(scannerService.settings.maxPhotosToProcess) {
            print("[DEBUG] Showing batch processing alert")
            // Show batch processing option
            showingBatchProcessingAlert = true
        } else if photosToProcess > 2000 {
            print("[DEBUG] Showing warning alert")
            showingWarning = true
        } else {
            print("[DEBUG] Starting scan directly")
            showingScanningView = true
            Task {
                await scannerService.startScan(fullScan: true)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    HomeView(scannerService: PhotoScannerService())
} 