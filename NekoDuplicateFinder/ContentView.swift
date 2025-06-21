//
//  ContentView.swift
//  NekoDuplicateFinder
//
//  Created by 千葉牧人 on 2025/6/21.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var scannerService = PhotoScannerService()
    
    var body: some View {
        HomeView(scannerService: scannerService)
    }
}

#Preview {
    ContentView()
}
