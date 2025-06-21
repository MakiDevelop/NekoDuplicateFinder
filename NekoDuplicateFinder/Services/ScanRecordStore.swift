//
//  ScanRecordStore.swift
//  NekoDuplicateFinder
//
//  Created by maki on 2024/07/19.
//

import Foundation
import Photos

class ScanRecordStore {
    private static let recordsKey = "NekoDuplicateFinder_ScanRecords_v2"
    private var records: [String: ScanRecord] = [:] // Dictionary for fast lookup

    init() {
        self.records = loadRecords()
        print("🗂️ ScanRecordStore initialized with \(records.count) records.")
    }

    private func loadRecords() -> [String: ScanRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.recordsKey) else {
            return [:]
        }
        do {
            let recordsArray = try JSONDecoder().decode([ScanRecord].self, from: data)
            let recordsDict = Dictionary(uniqueKeysWithValues: recordsArray.map { ($0.localIdentifier, $0) })
            print("✅ Loaded \(recordsDict.count) scan records from UserDefaults.")
            return recordsDict
        } catch {
            print("⚠️ Failed to decode scan records: \(error). Starting fresh.")
            return [:]
        }
    }

    func saveRecords() {
        do {
            let recordsArray = Array(records.values)
            let data = try JSONEncoder().encode(recordsArray)
            UserDefaults.standard.set(data, forKey: Self.recordsKey)
        } catch {
            print("⚠️ Failed to encode scan records for saving: \(error)")
        }
    }

    /// Checks if a photo asset needs to be scanned.
    /// - Parameter asset: The PHAsset to check.
    /// - Returns: `true` if the asset is new or has been modified, otherwise `false`.
    func needsScanning(asset: PHAsset) -> Bool {
        guard let modificationDate = asset.modificationDate else {
            // If no modification date, assume it needs scanning.
            return true
        }
        
        if let record = records[asset.localIdentifier] {
            // Record exists. Check if modification date is newer.
            return modificationDate > record.modificationDate
        } else {
            // No record exists, it's a new photo.
            return true
        }
    }

    /// Updates the record for a given photo asset after it has been processed.
    func addOrUpdateRecord(for asset: PHAsset) {
        guard let modificationDate = asset.modificationDate else { return }
        let newRecord = ScanRecord(localIdentifier: asset.localIdentifier, modificationDate: modificationDate)
        records[asset.localIdentifier] = newRecord
    }
    
    /// Clears all persisted scan records.
    func clearAllRecords() {
        records.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.recordsKey)
        print("🗑️ Cleared all scan records.")
    }
} 