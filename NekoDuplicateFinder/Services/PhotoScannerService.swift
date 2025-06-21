import Foundation
import Photos
import Vision
import UIKit
import CryptoKit
import Combine

@MainActor
class PhotoScannerService: ObservableObject {
    @Published var scanningStatus: ScanningStatus = .notStarted
    @Published var settings = ScanningSettings()
    private var settingsCancellable: AnyCancellable?
    
    private var photoAssets: [PhotoAsset] = []
    private var exactDuplicates: [String: [PhotoAsset]] = [:]
    private var similarGroups: [DuplicateGroup] = []
    @Published var isScanning = false
    private var shouldPause = false
    
    // Progress tracking
    private var processedCount = 0
    private var totalCount = 0
    private var startTime: Date?
    
    // Batch processing
    private var currentBatch = 0
    private var totalBatches = 0
    private var allDuplicates: [DuplicateGroup] = []
    private var isBatchProcessing = false
    private var fullScan = false
    
    // Feature print cache
    private var featurePrintCache: [String: VNFeaturePrintObservation] = [:]
    
    // Memory management
    private let maxCacheSize = 50 // Reduced from 100 to 50
    private var memoryWarningObserver: NSObjectProtocol?
    
    // Cache management
    private let cacheKey = "NekoDuplicateFinder_ScanCache"
    private var currentCache: ScanCache?
    
    // Progress tracking
    private var scanOffset = 0
    private var allPhotosFetchResult: PHFetchResult<PHAsset>?
    private var isCurrentlyFullScan = false
    
    // Incremental Scanning
    private let recordStore = ScanRecordStore()
    private var assetsToScan: [PHAsset] = []
    
    init() {
        // Listen for memory warnings
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
        
        // Observe settings changes
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        
        // Load existing cache
        loadCache()
        clearCacheInternal()
    }
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func handleMemoryWarning() {
        print("Memory warning received - cleaning up aggressively")
        cleanupMemory()
        featurePrintCache.removeAll()
        
        // Force garbage collection
        autoreleasepool {
            // This will help release memory
        }
    }
    
    private func cleanupMemory() {
        // Clear feature print cache if it gets too large
        if featurePrintCache.count > maxCacheSize {
            let keysToRemove = Array(featurePrintCache.keys.prefix(featurePrintCache.count - maxCacheSize))
            for key in keysToRemove {
                featurePrintCache.removeValue(forKey: key)
            }
        }
        
        // Force garbage collection
        autoreleasepool {
            // This will help release memory
        }
    }
    
    // MARK: - Public Methods
    
    func clearCache() {
        // Cache is currently disabled, but we leave the hook.
    }

    func clearScanRecords() {
        recordStore.clearAllRecords()
    }
    
    func startScan(fullScan: Bool) async {
        self.isCurrentlyFullScan = fullScan
        self.scanOffset = 0
        
        print("[DEBUG] Starting scan - fullScan: \(fullScan)")
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotosResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        print("[DEBUG] Total photos in library: \(allPhotosResult.count)")
        
        // Filter for new or modified photos
        var filteredAssets: [PHAsset] = []
        allPhotosResult.enumerateObjects { (asset, _, _) in
            if self.recordStore.needsScanning(asset: asset) {
                filteredAssets.append(asset)
            }
        }
        
        self.assetsToScan = filteredAssets
        print("🔍 Found \(assetsToScan.count) new or modified photos to scan.")
        
        if assetsToScan.isEmpty {
            print("[DEBUG] No photos to scan - this might be the issue on iPad")
        }
        
        await processNextBatch()
    }

    func continueScan() async {
        guard isCurrentlyFullScan else { return }
        await processNextBatch()
    }
    
    private func processNextBatch() async {
        let totalToScan = assetsToScan.count
        
        print("[DEBUG] processNextBatch - totalToScan: \(totalToScan), isCurrentlyFullScan: \(isCurrentlyFullScan)")
        
        if totalToScan == 0 {
            print("[DEBUG] No photos to scan, completing immediately")
            await MainActor.run {
                scanningStatus = .completed(duplicates: [], totalSavings: 0, isFinalBatch: true)
            }
            return
        }

        if !isCurrentlyFullScan {
            // This is a partial scan (e.g., "first 5000"), not a batch process.
            let photosToProcess = Array(assetsToScan.prefix(Int(settings.maxPhotosToProcess)))
            print("[DEBUG] Partial scan - processing \(photosToProcess.count) photos")
            await runScan(for: photosToProcess, batchInfo: (1, 1))
        } else {
            // This is a full, batched scan.
            let batchSize = Int(settings.batchSize)
            print("[DEBUG] 實際 batchSize: \(batchSize)")
            print("[DEBUG] settings.batchSize 原始值: \(settings.batchSize)")
            print("[DEBUG] settings 物件 ID: \(ObjectIdentifier(settings))")
            guard batchSize > 0 else {
                await MainActor.run { scanningStatus = .error("批次大小必須大於 0") }
                return
            }
            
            if scanOffset >= totalToScan {
                print("[DEBUG] Scan offset (\(scanOffset)) >= total to scan (\(totalToScan)), completing")
                await MainActor.run {
                    // This state should ideally not be reached as isFinalBatch is handled in runScan
                    scanningStatus = .completed(duplicates: [], totalSavings: 0, isFinalBatch: true)
                }
                return
            }

            let remainingCount = totalToScan - scanOffset
            let currentBatchSize = min(batchSize, remainingCount)
            let totalBatches = Int(ceil(Double(totalToScan) / Double(batchSize)))
            let currentBatchNumber = (scanOffset / batchSize) + 1
            
            print("[DEBUG] Batch info - remaining: \(remainingCount), currentBatchSize: \(currentBatchSize), totalBatches: \(totalBatches), currentBatchNumber: \(currentBatchNumber)")
            
            let batchAssets = Array(assetsToScan[scanOffset..<(scanOffset + currentBatchSize)])
            
            // Increment offset *before* the scan.
            self.scanOffset += currentBatchSize
            
            await runScan(for: batchAssets, batchInfo: (currentBatchNumber, totalBatches))
        }
    }

    private func runScan(for assetsForBatch: [PHAsset], batchInfo: (current: Int, total: Int)) async {
        print("[DEBUG] runScan - assets count: \(assetsForBatch.count), batch info: \(batchInfo)")
        
        var photoAssetsForBatch: [PhotoAsset] = []
        for asset in assetsForBatch {
            if self.settings.skipHEIC {
                let resources = PHAssetResource.assetResources(for: asset)
                if resources.contains(where: { $0.uniformTypeIdentifier == "public.heic" }) {
                    continue // Use continue to skip the rest of the loop for this asset
                }
            }
            photoAssetsForBatch.append(PhotoAsset(asset: asset))
        }
        
        print("[DEBUG] After filtering - photoAssetsForBatch count: \(photoAssetsForBatch.count)")
        
        let totalInBatch = photoAssetsForBatch.count
        var processedPhotos: [PhotoAsset] = []
        
        for (index, photo) in photoAssetsForBatch.enumerated() {
            let progress = Double(index + 1) / Double(totalInBatch)
            await MainActor.run {
                scanningStatus = .scanning(progress: progress, currentPhoto: index + 1, totalPhotos: totalInBatch, currentBatch: batchInfo.current, totalBatches: batchInfo.total)
            }

            // Perform processing
            let md5Hash = await calculateMD5Hash(for: photo)
            var featurePrint: VNFeaturePrintObservation?
            if settings.enableSimilarDetection {
                featurePrint = await generateFeaturePrint(for: photo)
            }
            
            var processedPhoto = photo
            processedPhoto.md5Hash = md5Hash
            processedPhoto.featurePrint = featurePrint
            processedPhotos.append(processedPhoto)
            
            // Update the scan record immediately after processing
            recordStore.addOrUpdateRecord(for: processedPhoto.asset)

            // Memory cleanup during processing
            if index % 20 == 0 {
                cleanupMemory()
            }
        }

        let duplicatesInBatch = await findDuplicates(in: processedPhotos)
        let savingsInBatch = duplicatesInBatch.reduce(0) { $0 + $1.potentialSavings }
        
        // Save records at the end of each batch
        recordStore.saveRecords()

        let isFinalBatch = !isCurrentlyFullScan || scanOffset >= assetsToScan.count

        await MainActor.run {
            scanningStatus = .completed(duplicates: duplicatesInBatch, totalSavings: savingsInBatch, isFinalBatch: isFinalBatch)
        }
    }

    // This method is now obsolete and will be replaced by the logic in runScan.
    private func performFullScan() async {
        // All logic has been moved to processNextBatch and runScan.
    }
    
    private func processPhotoBatch(_ batch: [PhotoAsset]) async -> [PhotoAsset] {
        // This logic is now integrated into runScan.
        return []
    }
    
    private func findDuplicates(in photoAssets: [PhotoAsset]) async -> [DuplicateGroup] {
        var duplicateGroups: [DuplicateGroup] = []
        
        // Find exact duplicates (same MD5 hash)
        let exactDuplicates = findExactDuplicates(in: photoAssets)
        duplicateGroups.append(contentsOf: exactDuplicates)
        
        // Find similar duplicates if enabled
        if settings.enableSimilarDetection {
            let similarDuplicates = await findSimilarDuplicates(in: photoAssets)
            duplicateGroups.append(contentsOf: similarDuplicates)
        }
        
        return duplicateGroups
    }
    
    private func findExactDuplicates(in photoAssets: [PhotoAsset]) -> [DuplicateGroup] {
        var hashGroups: [String: [PhotoAsset]] = [:]
        
        // Group photos by MD5 hash
        for photo in photoAssets {
            if let hash = photo.md5Hash {
                if hashGroups[hash] == nil {
                    hashGroups[hash] = []
                }
                hashGroups[hash]?.append(photo)
            }
        }
        
        // Create duplicate groups for hashes with multiple photos
        return hashGroups.compactMap { hash, photos in
            guard photos.count > 1 else { return nil }
            return DuplicateGroup(photos: photos, type: .exact)
        }
    }
    
    private func findSimilarDuplicates(in photoAssets: [PhotoAsset]) async -> [DuplicateGroup] {
        var similarGroups: [DuplicateGroup] = []
        let processedPhotos = photoAssets.filter { $0.featurePrint != nil }
        
        // Compare each photo with others
        for i in 0..<processedPhotos.count {
            for j in (i+1)..<processedPhotos.count {
                let photo1 = processedPhotos[i]
                let photo2 = processedPhotos[j]
                
                // Skip if both photos are already in exact duplicate groups
                if photo1.md5Hash == photo2.md5Hash {
                    continue
                }
                
                // Calculate feature distance
                if let distance = await calculateFeatureDistance(photo1, photo2) {
                    if distance <= settings.similarityThreshold {
                        // Check if either photo is already in a similar group
                        let existingGroup = similarGroups.first { group in
                            group.photos.contains { $0.localIdentifier == photo1.localIdentifier || $0.localIdentifier == photo2.localIdentifier }
                        }
                        
                        if let existingGroup = existingGroup {
                            // Add photos to existing group if not already present
                            var updatedPhotos = existingGroup.photos
                            if !updatedPhotos.contains(where: { $0.localIdentifier == photo1.localIdentifier }) {
                                updatedPhotos.append(photo1)
                            }
                            if !updatedPhotos.contains(where: { $0.localIdentifier == photo2.localIdentifier }) {
                                updatedPhotos.append(photo2)
                            }
                            
                            // Replace the group
                            if let index = similarGroups.firstIndex(where: { $0.id == existingGroup.id }) {
                                similarGroups[index] = DuplicateGroup(photos: updatedPhotos, type: .similar)
                            }
                        } else {
                            // Create new group
                            let newGroup = DuplicateGroup(photos: [photo1, photo2], type: .similar)
                            similarGroups.append(newGroup)
                        }
                    }
                }
            }
        }
        
        return similarGroups
    }
    
    private func groupDuplicates(_ duplicates: [DuplicateGroup]) -> [DuplicateGroup] {
        // This method is called after findDuplicates, so we just return the duplicates as-is
        // The grouping is already done in findDuplicates method
        return duplicates
    }
    
    // MARK: - Helper Methods
    
    private func calculateMD5Hash(for photoAsset: PhotoAsset) async -> String? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            
            // Use smaller size for hash calculation to reduce memory usage
            let targetSize = CGSize(width: 128, height: 128)
            
            PHImageManager.default().requestImage(
                for: photoAsset.asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard let image = image else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Check if the request was cancelled
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Check for errors
                if let error = info?[PHImageErrorKey] as? Error {
                    print("Image request error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Use autorelease pool to manage memory
                autoreleasepool {
                    guard let imageData = image.jpegData(compressionQuality: 0.5) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let hash = SHA256.hash(data: imageData)
                    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: hashString)
                }
            }
        }
    }
    
    private func generateFeaturePrint(for photoAsset: PhotoAsset) async -> VNFeaturePrintObservation? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            
            // Use smaller size for feature print generation to reduce memory usage
            let maxDimension: CGFloat = 512 // Reduced from settings.maxImageDimension to 512
            let targetSize = CGSize(
                width: min(maxDimension, CGFloat(photoAsset.asset.pixelWidth)),
                height: min(maxDimension, CGFloat(photoAsset.asset.pixelHeight))
            )
            
            PHImageManager.default().requestImage(
                for: photoAsset.asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard let image = image else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Check if the request was cancelled
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Check for errors
                if let error = info?[PHImageErrorKey] as? Error {
                    print("Image request error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Use autorelease pool to manage memory
                autoreleasepool {
                    guard let cgImage = image.cgImage else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let request = VNGenerateImageFeaturePrintRequest()
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    
                    do {
                        try handler.perform([request])
                        if let result = request.results?.first as? VNFeaturePrintObservation {
                            continuation.resume(returning: result)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } catch {
                        print("Feature print generation error: \(error)")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
    
    private func calculateFeatureDistance(_ photo1: PhotoAsset, _ photo2: PhotoAsset) async -> Float? {
        guard let feature1 = photo1.featurePrint,
              let feature2 = photo2.featurePrint else {
            return nil
        }
        
        var distance: Float = 0
        do {
            try feature1.computeDistance(&distance, to: feature2)
            return distance
        } catch {
            return nil
        }
    }
    
    // MARK: - Cache Management
    
    private func loadCache() {
        guard settings.enableCache else { return }
        
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cache = try? JSONDecoder().decode(ScanCache.self, from: data) {
            currentCache = cache
            print("Loaded cache from \(cache.scanDate)")
        }
    }
    
    private func saveCache(duplicates: [DuplicateGroup], totalSavings: Int64, totalPhotos: Int) {
        guard settings.enableCache else { return }
        
        let cache = ScanCache(
            scanDate: Date(),
            totalPhotos: totalPhotos,
            duplicates: duplicates,
            totalSavings: totalSavings,
            settings: settings
        )
        
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            currentCache = cache
            print("Saved cache with \(duplicates.count) duplicate groups")
        }
    }
    
    private func clearCacheInternal() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        currentCache = nil
        print("Cache cleared")
    }
    
    private func isCacheValid() -> Bool {
        guard let cache = currentCache else { return false }
        
        // Check if settings have changed
        if cache.settings.enableSimilarDetection != settings.enableSimilarDetection ||
           cache.settings.similarityThreshold != settings.similarityThreshold ||
           cache.settings.skipHEIC != settings.skipHEIC {
            print("Cache invalid: settings changed")
            return false
        }
        
        // Check if cache is still valid
        let isValid = Date().timeIntervalSince(cache.scanDate) < TimeInterval(settings.cacheValidityHours * 3600)
        if !isValid {
            print("Cache expired")
        }
        return isValid
    }
    
    private func getCachedResults() -> (duplicates: [DuplicateGroup], totalSavings: Int64)? {
        guard isCacheValid() else { return nil }
        
        // Verify that cached photos still exist
        let validDuplicates = currentCache?.duplicates.filter { group in
            group.photos.allSatisfy { photo in
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: nil)
                return fetchResult.count > 0
            }
        } ?? []
        
        if validDuplicates.count != currentCache?.duplicates.count {
            print("Some cached photos no longer exist, clearing cache")
            clearCacheInternal()
            return nil
        }
        
        return (validDuplicates, currentCache?.totalSavings ?? 0)
    }
}


