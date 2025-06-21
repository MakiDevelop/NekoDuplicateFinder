import SwiftUI
import Photos

struct ResultsView: View {
    @ObservedObject var scannerService: PhotoScannerService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotos: Set<String> = [] // Use localIdentifier as key
    @State private var showingDeleteConfirmation = false
    @State private var showingPhotoDetail: PhotoAsset?
    @State private var isDeleting = false
    @State private var showingSuccessMessage = false
    @State private var deletedCount = 0
    
    private var completedDuplicates: [DuplicateGroup]? {
        switch scannerService.scanningStatus {
        case .completed(let duplicates, _, _):
            return duplicates
        default:
            return nil
        }
    }
    
    private var totalSavings: Int64? {
        switch scannerService.scanningStatus {
        case .completed(_, let savings, _):
            return savings
        default:
            return nil
        }
    }
    
    private var isFinalBatch: Bool {
        switch scannerService.scanningStatus {
        case .completed(_, _, let isFinal):
            return isFinal
        default:
            return true
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with summary
                VStack(spacing: 16) {
                    // Success icon
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("掃描完成！")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let duplicates = completedDuplicates, let savings = totalSavings {
                        VStack(spacing: 8) {
                            Text("找到 \(duplicates.count) 組重複照片")
                                .font(.headline)
                            
                            Text("可釋放 \(formatFileSize(savings)) 空間")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 24)
                
                // Results list
                if let duplicates = completedDuplicates {
                    if duplicates.isEmpty {
                        EmptyResultsView()
                    } else {
                        ResultsListView(
                            duplicates: duplicates,
                            selectedPhotos: $selectedPhotos,
                            scannerService: scannerService,
                            onPhotoTap: { photo in
                                showingPhotoDetail = photo
                            }
                        )
                    }
                }
                
                // Bottom action bar
                if let duplicates = completedDuplicates, !duplicates.isEmpty {
                    BottomActionBar(
                        selectedCount: selectedPhotos.count,
                        totalPhotos: totalPhotoCount(duplicates),
                        duplicates: duplicates,
                        selectedPhotos: $selectedPhotos,
                        onSelectAll: {
                            selectAllPhotos(duplicates)
                        },
                        onDeselectAll: {
                            selectedPhotos.removeAll()
                        },
                        onSelectExact: {
                            selectPhotosByType(duplicates, type: .exact)
                        },
                        onSelectSimilar: {
                            selectPhotosByType(duplicates, type: .similar)
                        },
                        onDelete: {
                            showingDeleteConfirmation = true
                        }
                    )
                }
                
                // Next batch button overlay
                nextBatchButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .overlay(
                // Loading overlay during deletion
                Group {
                    if isDeleting {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            
                            Text("正在刪除照片...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(32)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                    }
                }
            )
        }
        .sheet(item: $showingPhotoDetail) { photo in
            PhotoDetailView(photo: photo, scannerService: scannerService)
        }
        .alert("確認刪除", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("刪除", role: .destructive) {
                Task {
                    await deleteSelectedPhotos()
                }
            }
        } message: {
            Text("確定要刪除選中的 \(selectedPhotos.count) 張照片嗎？此操作無法復原。")
        }
        .alert("刪除成功", isPresented: $showingSuccessMessage) {
            if !isFinalBatch {
                Button("繼續掃描下一批") {
                    Task {
                        await scannerService.continueScan()
                        dismiss()
                    }
                }
            }
            Button("完成") {
                dismiss()
            }
        } message: {
            Text("成功刪除了 \(deletedCount) 張重複照片！")
        }
    }
    
    private func totalPhotoCount(_ duplicates: [DuplicateGroup]) -> Int {
        duplicates.reduce(0) { $0 + $1.photos.count }
    }
    
    private func selectAllPhotos(_ duplicates: [DuplicateGroup]) {
        print("Selecting all photos from \(duplicates.count) groups")
        
        let allPhotoIds = duplicates.flatMap { $0.photos.map { $0.localIdentifier } }
        print("Total photos found: \(allPhotoIds.count)")
        
        selectedPhotos = Set(allPhotoIds)
        print("Final selection count: \(selectedPhotos.count)")
    }
    
    private func selectPhotosByType(_ duplicates: [DuplicateGroup], type: DuplicateType) {
        print("=== SELECTING PHOTOS BY TYPE ===")
        print("Looking for type: \(type.displayName)")
        print("Total groups available: \(duplicates.count)")
        
        // Clear current selection first
        selectedPhotos.removeAll()
        
        // Find groups of the specified type
        var foundGroups: [DuplicateGroup] = []
        for group in duplicates {
            if group.groupType == type {
                foundGroups.append(group)
                print("Found group: \(group.groupType.displayName) with \(group.photos.count) photos")
            }
        }
        
        print("Total groups of type \(type.displayName): \(foundGroups.count)")
        
        // Collect all photo IDs from matching groups
        var photoIds: [String] = []
        for group in foundGroups {
            for photo in group.photos {
                photoIds.append(photo.localIdentifier)
            }
        }
        
        print("Total photos to select: \(photoIds.count)")
        
        // Set the selection
        selectedPhotos = Set(photoIds)
        
        print("Final selection count: \(selectedPhotos.count)")
        print("=== SELECTION COMPLETE ===")
    }
    
    private func deleteSelectedPhotos() async {
        guard let duplicates = completedDuplicates else { return }
        
        isDeleting = true
        
        // Get all selected photos from all groups
        let allSelectedPhotos = duplicates.flatMap { group in
            group.photos.filter { selectedPhotos.contains($0.localIdentifier) }
        }
        
        guard !allSelectedPhotos.isEmpty else {
            isDeleting = false
            return
        }
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(allSelectedPhotos.map { $0.asset } as NSArray)
            }
            
            // Clear selection after successful deletion
            selectedPhotos.removeAll()
            
            // Set success state
            deletedCount = allSelectedPhotos.count
            
            // Add a small delay to ensure the UI updates properly
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            showingSuccessMessage = true
            
            // Show success message
            print("Successfully deleted \(allSelectedPhotos.count) photos")
            
        } catch {
            print("Failed to delete photos: \(error)")
        }
        
        isDeleting = false
    }
    
    @ViewBuilder
    private var nextBatchButton: some View {
        if !isFinalBatch {
            VStack {
                Spacer()
                Button(action: {
                    Task {
                        await scannerService.continueScan()
                        dismiss()
                    }
                }) {
                    HStack {
                        Text("繼續掃描下一批")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right.circle.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Empty Results View
struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("太棒了！")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("沒有找到重複的照片\n你的相簿整理得很乾淨呢！")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

// MARK: - Results List View
struct ResultsListView: View {
    let duplicates: [DuplicateGroup]
    @Binding var selectedPhotos: Set<String>
    let scannerService: PhotoScannerService
    let onPhotoTap: (PhotoAsset) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(duplicates) { group in
                    DuplicateGroupView(
                        group: group,
                        selectedPhotos: $selectedPhotos,
                        scannerService: scannerService,
                        onPhotoTap: onPhotoTap
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Duplicate Group View
struct DuplicateGroupView: View {
    let group: DuplicateGroup
    @Binding var selectedPhotos: Set<String>
    let scannerService: PhotoScannerService
    let onPhotoTap: (PhotoAsset) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Group header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: group.groupType.icon)
                            .foregroundColor(.orange)
                        Text(group.groupType.displayName)
                            .font(.headline)
                    }
                    
                    Text("\(group.photos.count) 張照片 • \(formatFileSize(group.potentialSavings)) 可釋放")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Photo grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(group.photos) { photo in
                    PhotoThumbnailView(
                        photo: photo,
                        isSelected: selectedPhotos.contains(photo.localIdentifier),
                        onToggleSelection: {
                            if selectedPhotos.contains(photo.localIdentifier) {
                                selectedPhotos.remove(photo.localIdentifier)
                            } else {
                                selectedPhotos.insert(photo.localIdentifier)
                            }
                        },
                        onTap: {
                            onPhotoTap(photo)
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Photo Thumbnail View
struct PhotoThumbnailView: View {
    let photo: PhotoAsset
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onTap: () -> Void
    @State private var thumbnail: UIImage?
    
    var body: some View {
        ZStack {
            // Thumbnail image
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray4))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }
            
            // Selection overlay
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .background(Color.white)
                    .clipShape(Circle())
                    .offset(x: 25, y: -25)
            }
        }
        .onTapGesture {
            onToggleSelection()
        }
        .onLongPressGesture {
            onTap()
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        photo.asset.getThumbnail(size: CGSize(width: 160, height: 160)) { image in
            thumbnail = image
        }
    }
}

// MARK: - Bottom Action Bar
struct BottomActionBar: View {
    let selectedCount: Int
    let totalPhotos: Int
    let duplicates: [DuplicateGroup]
    @Binding var selectedPhotos: Set<String>
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onSelectExact: () -> Void
    let onSelectSimilar: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            VStack(spacing: 12) {
                // Category selection buttons
                HStack(spacing: 8) {
                    Button("全選視覺相似") {
                        onSelectSimilar()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                    
                    Button("全選完全重複") {
                        onSelectExact()
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                    
                    Spacer()
                }
                
                // Main action buttons
                HStack(spacing: 16) {
                    // Selection controls
                    HStack(spacing: 12) {
                        Button(selectedCount == totalPhotos ? "取消全選" : "全選") {
                            if selectedCount == totalPhotos {
                                onDeselectAll()
                            } else {
                                onSelectAll()
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    }
                    
                    Spacer()
                    
                    // Delete button
                    Button(action: onDelete) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("刪除選中 (\(selectedCount))")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            selectedCount > 0 ? Color.red : Color.gray
                        )
                        .cornerRadius(8)
                    }
                    .disabled(selectedCount == 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Photo Detail View
struct PhotoDetailView: View {
    let photo: PhotoAsset
    let scannerService: PhotoScannerService
    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: UIImage?
    
    var body: some View {
        NavigationStack {
            VStack {
                if let fullImage = fullImage {
                    Image(uiImage: fullImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Photo info
                VStack(spacing: 12) {
                    InfoRow(title: "檔案大小", value: formatFileSize(photo.fileSize))
                    InfoRow(title: "尺寸", value: "\(Int(photo.dimensions.width)) × \(Int(photo.dimensions.height))")
                    if let date = photo.creationDate {
                        InfoRow(title: "拍攝時間", value: formatDate(date))
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("照片詳情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadFullImage()
        }
    }
    
    private func loadFullImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        
        PHImageManager.default().requestImage(
            for: photo.asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            fullImage = image
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    ResultsView(scannerService: PhotoScannerService())
} 