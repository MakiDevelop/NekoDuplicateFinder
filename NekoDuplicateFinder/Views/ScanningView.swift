import SwiftUI

struct ScanningView: View {
    @ObservedObject var scannerService: PhotoScannerService
    @Environment(\.dismiss) private var dismiss
    @State private var showingResults = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    // Animated cat icon
                    CatAnimationView()
                        .frame(height: 120)
                    
                    Text("正在掃描照片中...")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("喵～我正在幫你找出重複的照片呢！")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Status Text
                VStack(spacing: 8) {
                    Text(statusText)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("剩餘時間：\(estimatedTimeString)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Progress section
                VStack(spacing: 24) {
                    // Progress bar
                    ProgressBarView(progress: progressValue)
                    
                    // Progress details
                    VStack(spacing: 12) {
                        HStack {
                            Text("已處理")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(processedCount) / \(totalCount)")
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("預估剩餘時間")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(estimatedTimeString)
                                .fontWeight(.medium)
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Control buttons
                VStack(spacing: 16) {
                    Button("取消掃描") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
        }
        .onChange(of: scannerService.scanningStatus) { oldValue, newValue in
            if case .completed = newValue {
                showingResults = true
            }
        }
        .sheet(isPresented: $showingResults) {
            ResultsView(scannerService: scannerService)
        }
    }
    
    // MARK: - Computed Properties
    
    private var progressValue: Double {
        switch scannerService.scanningStatus {
        case .scanning(let progress, _, _, _, _):
            return progress
        case .completed:
            return 1.0
        default:
            return 0.0
        }
    }
    
    private var statusText: String {
        switch scannerService.scanningStatus {
        case .notStarted:
            return "準備開始掃描..."
        case .scanning(_, let current, let total, let currentBatch, let totalBatches):
            if totalBatches > 1 {
                return "正在掃描第 \(currentBatch)/\(totalBatches) 批 (\(current)/\(total))"
            } else {
                return "正在掃描照片... (\(current)/\(total))"
            }
        case .completed:
            return "掃描完成！"
        case .error(let message):
            return "發生錯誤：\(message)"
        }
    }
    
    private var processedCount: Int {
        switch scannerService.scanningStatus {
        case .scanning(_, let current, _, _, _):
            return current
        default:
            return 0
        }
    }
    
    private var totalCount: Int {
        switch scannerService.scanningStatus {
        case .scanning(_, _, let total, _, _):
            return total
        default:
            return 0
        }
    }
    
    private var estimatedTimeString: String {
        let progress = progressValue
        guard progress > 0.1 else { return "計算中..." }
        
        // Since startTime is private, we'll just show a simple message
        return "計算中..."
    }
}

// MARK: - Cat Animation View
struct CatAnimationView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.orange.opacity(0.1))
                .frame(width: 100, height: 100)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
            
            // Cat icon
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
                .rotationEffect(.degrees(isAnimating ? 10 : -10))
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Progress Bar View
struct ProgressBarView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(height: 12)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 12)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 12)
            
            // Percentage
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                LinearGradient(
                    colors: [.orange, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ScanningView(scannerService: PhotoScannerService())
} 