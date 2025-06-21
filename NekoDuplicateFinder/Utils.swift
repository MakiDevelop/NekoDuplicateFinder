import Foundation

// MARK: - File Size Formatting
func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

// MARK: - Date Formatting
func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = Locale(identifier: "zh_TW")
    return formatter.string(from: date)
}

// MARK: - Time Formatting
func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return "不到 1 分鐘"
    } else if seconds < 3600 {
        let minutes = Int(seconds / 60)
        return "約 \(minutes) 分鐘"
    } else {
        let hours = Int(seconds / 3600)
        return "約 \(hours) 小時"
    }
}

// MARK: - Number Formatting
func formatNumber(_ number: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
}

// MARK: - Percentage Formatting
func formatPercentage(_ value: Double) -> String {
    return "\(Int(value * 100))%"
} 