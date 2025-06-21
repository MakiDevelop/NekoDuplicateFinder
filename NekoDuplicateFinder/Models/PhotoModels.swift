import Foundation
import Photos
import Vision
import UIKit

// MARK: - Photo Asset Model
struct PhotoAsset: Identifiable, Hashable, Codable {
    let id: UUID
    let asset: PHAsset
    let localIdentifier: String
    let creationDate: Date?
    let fileSize: Int64
    let dimensions: CGSize
    var md5Hash: String?
    var featurePrint: VNFeaturePrintObservation?
    var isSelected: Bool = false
    
    init(asset: PHAsset, md5Hash: String? = nil, featurePrint: VNFeaturePrintObservation? = nil) {
        self.id = UUID()
        self.asset = asset
        self.localIdentifier = asset.localIdentifier
        self.creationDate = asset.creationDate
        self.fileSize = asset.getFileSize()
        self.dimensions = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        self.md5Hash = md5Hash
        self.featurePrint = featurePrint
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(localIdentifier)
    }
    
    static func == (lhs: PhotoAsset, rhs: PhotoAsset) -> Bool {
        return lhs.localIdentifier == rhs.localIdentifier
    }
    
    // Custom coding keys to exclude non-codable properties
    enum CodingKeys: String, CodingKey {
        case id, localIdentifier, creationDate, fileSize, dimensions, md5Hash, isSelected
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        localIdentifier = try container.decode(String.self, forKey: .localIdentifier)
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        dimensions = try container.decode(CGSize.self, forKey: .dimensions)
        md5Hash = try container.decodeIfPresent(String.self, forKey: .md5Hash)
        isSelected = try container.decode(Bool.self, forKey: .isSelected)
        
        // Reconstruct PHAsset from localIdentifier
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        asset = fetchResult.firstObject ?? PHAsset()
        featurePrint = nil // Will be regenerated if needed
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(localIdentifier, forKey: .localIdentifier)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(dimensions, forKey: .dimensions)
        try container.encodeIfPresent(md5Hash, forKey: .md5Hash)
        try container.encode(isSelected, forKey: .isSelected)
        // Note: featurePrint is excluded as it's not Codable
    }
}

// MARK: - Duplicate Group Model
struct DuplicateGroup: Identifiable, Equatable, Codable {
    let id: UUID
    let photos: [PhotoAsset]
    let groupType: DuplicateType
    let totalSize: Int64
    let potentialSavings: Int64
    
    init(photos: [PhotoAsset], type: DuplicateType) {
        self.id = UUID()
        self.photos = photos
        self.groupType = type
        self.totalSize = photos.reduce(0) { $0 + $1.fileSize }
        // Calculate potential savings (keep one, delete the rest)
        self.potentialSavings = totalSize - (photos.first?.fileSize ?? 0)
    }
    
    static func == (lhs: DuplicateGroup, rhs: DuplicateGroup) -> Bool {
        return lhs.id == rhs.id && lhs.groupType == rhs.groupType
    }
    
    // Custom coding keys to exclude non-codable properties
    enum CodingKeys: String, CodingKey {
        case id, photos, groupType, totalSize, potentialSavings
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        photos = try container.decode([PhotoAsset].self, forKey: .photos)
        groupType = try container.decode(DuplicateType.self, forKey: .groupType)
        totalSize = try container.decode(Int64.self, forKey: .totalSize)
        potentialSavings = try container.decode(Int64.self, forKey: .potentialSavings)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(photos, forKey: .photos)
        try container.encode(groupType, forKey: .groupType)
        try container.encode(totalSize, forKey: .totalSize)
        try container.encode(potentialSavings, forKey: .potentialSavings)
    }
}

// MARK: - Duplicate Types
enum DuplicateType: Equatable, Codable {
    case exact      // 100% identical (same MD5)
    case similar    // Visually similar (feature print distance)
    
    var displayName: String {
        switch self {
        case .exact: return "完全重複"
        case .similar: return "視覺相似"
        }
    }
    
    var icon: String {
        switch self {
        case .exact: return "doc.on.doc"
        case .similar: return "eye"
        }
    }
}

// MARK: - Scanning Status
enum ScanningStatus: Equatable {
    case notStarted
    case scanning(progress: Double, currentPhoto: Int, totalPhotos: Int, currentBatch: Int, totalBatches: Int)
    case completed(duplicates: [DuplicateGroup], totalSavings: Int64, isFinalBatch: Bool)
    case error(String)
    
    static func == (lhs: ScanningStatus, rhs: ScanningStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted):
            return true
        case (.scanning(let p1, let c1, let t1, let cb1, let tb1),
              .scanning(let p2, let c2, let t2, let cb2, let tb2)):
            return p1 == p2 && c1 == c2 && t1 == t2 && cb1 == cb2 && tb1 == tb2
        case (.completed(let d1, let s1, let f1),
              .completed(let d2, let s2, let f2)):
            // For UI updates, comparing counts and flags is sufficient and more performant
            return d1.count == d2.count && s1 == s2 && f1 == f2
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

// MARK: - Scan Cache
struct ScanCache: Codable {
    let scanDate: Date
    let totalPhotos: Int
    let duplicates: [DuplicateGroup]
    let totalSavings: Int64
    let settings: ScanningSettings
    
    var isValid: Bool {
        // Cache is valid based on settings.cacheValidityHours
        return Date().timeIntervalSince(scanDate) < TimeInterval(settings.cacheValidityHours * 3600)
    }
}

// MARK: - Scanning Settings
class ScanningSettings: ObservableObject, Codable {
    @Published var enableSimilarDetection: Bool = true
    @Published var similarityThreshold: Float = 0.2  // Distance threshold (0.0 = identical, 1.0 = completely different)
    @Published var keepNewestPhotos: Bool = true
    @Published var skipHEIC: Bool = false
    @Published var maxImageDimension: CGFloat = 1024  // For performance optimization
    @Published var maxPhotosToProcess: Double = 1000  // Changed from Int to Double
    @Published var batchSize: Double = 100  // Batch size for processing
    @Published var enableCache: Bool = true
    @Published var cacheValidityHours: Double = 24  // Changed from Int to Double

    enum CodingKeys: String, CodingKey {
        case enableSimilarDetection, similarityThreshold, keepNewestPhotos, skipHEIC, maxImageDimension, maxPhotosToProcess, batchSize, enableCache, cacheValidityHours
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableSimilarDetection = try container.decode(Bool.self, forKey: .enableSimilarDetection)
        similarityThreshold = try container.decode(Float.self, forKey: .similarityThreshold)
        keepNewestPhotos = try container.decode(Bool.self, forKey: .keepNewestPhotos)
        skipHEIC = try container.decode(Bool.self, forKey: .skipHEIC)
        maxImageDimension = try container.decode(CGFloat.self, forKey: .maxImageDimension)
        maxPhotosToProcess = try container.decode(Double.self, forKey: .maxPhotosToProcess)
        batchSize = try container.decode(Double.self, forKey: .batchSize)
        enableCache = try container.decode(Bool.self, forKey: .enableCache)
        cacheValidityHours = try container.decode(Double.self, forKey: .cacheValidityHours)
        
        // 手動觸發 objectWillChange 以確保 UI 更新
        objectWillChange.send()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enableSimilarDetection, forKey: .enableSimilarDetection)
        try container.encode(similarityThreshold, forKey: .similarityThreshold)
        try container.encode(keepNewestPhotos, forKey: .keepNewestPhotos)
        try container.encode(skipHEIC, forKey: .skipHEIC)
        try container.encode(maxImageDimension, forKey: .maxImageDimension)
        try container.encode(maxPhotosToProcess, forKey: .maxPhotosToProcess)
        try container.encode(batchSize, forKey: .batchSize)
        try container.encode(enableCache, forKey: .enableCache)
        try container.encode(cacheValidityHours, forKey: .cacheValidityHours)
    }

    init() {}
}

// MARK: - PHAsset Extension
extension PHAsset {
    func getFileSize() -> Int64 {
        let resources = PHAssetResource.assetResources(for: self)
        return resources.first?.value(forKey: "fileSize") as? Int64 ?? 0
    }
    
    func getThumbnail(size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        
        PHImageManager.default().requestImage(
            for: self,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
}

// MARK: - Scanning Progress
struct ScanningProgress {
    let processedCount: Int
    let totalCount: Int
    let currentPhase: ScanningPhase
    let estimatedTimeRemaining: TimeInterval?
    
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(processedCount) / Double(totalCount)
    }
}

enum ScanningPhase {
    case loadingAssets
    case calculatingHashes
    case generatingFeaturePrints
    case comparingImages
    case groupingDuplicates
    
    var displayName: String {
        switch self {
        case .loadingAssets: return "載入照片中..."
        case .calculatingHashes: return "計算檔案雜湊..."
        case .generatingFeaturePrints: return "生成特徵向量..."
        case .comparingImages: return "比對圖片中..."
        case .groupingDuplicates: return "分組重複圖片..."
        }
    }
}

// MARK: - Scan Record Model
struct ScanRecord: Codable, Hashable {
    let localIdentifier: String
    let modificationDate: Date
} 