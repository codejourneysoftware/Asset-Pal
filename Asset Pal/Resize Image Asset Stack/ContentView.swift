import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var imageProcessor = ImageProcessor()
    @State private var isDropTargeted = false
    
    // Grid configuration for the target sizes area
    let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16)
    ]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // App Header
                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.green)
                        .font(.title)
                    
                    Text("RESIZE IMAGE ASSET STACK // MAINFRAME V1.0")
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    if imageProcessor.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .colorMultiply(.green)
                            .padding(.trailing, 8)
                    } else {
                        Button(action: {
                            // Prevent animations from looking unnatural during raw log resets
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                imageProcessor.clearLogs()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                Text("[ PURGE ]")
                            }
                            .font(.system(.callout, design: .monospaced).weight(.bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.green)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
                .background(Color.black)
                .border(Color.green, width: 1)
                
                // Target Toggle Selector
                HStack(spacing: 0) {
                    Text("> SET TARGET:")
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .foregroundColor(.green)
                        .padding(.trailing, 16)
                    
                    ForEach(AppStoreDevice.allCases) { device in
                        let isActive = imageProcessor.selectedDevice == device
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                imageProcessor.selectedDevice = device
                            }
                        }) {
                            Text(isActive ? "[ \(device.rawValue) ]" : "  \(device.rawValue)  ")
                                .font(.system(.body, design: .monospaced).weight(.bold))
                                .foregroundColor(isActive ? .black : .green)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(isActive ? Color.green : Color.clear)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(imageProcessor.isProcessing)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black)
                .border(Color.green, width: 1)
                
                // Terminal / Drop Zone
                ZStack {
                    if isDropTargeted {
                        Color.green.opacity(0.1)
                    }
                    
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(imageProcessor.terminalLogs.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                                        .foregroundColor(.green)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .padding()
                            .onChange(of: imageProcessor.terminalLogs.count) { _ in
                                withAnimation {
                                    proxy.scrollTo(imageProcessor.terminalLogs.count - 1, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .border(isDropTargeted ? Color.green : Color.green.opacity(0.3), width: isDropTargeted ? 3 : 1)
                .padding()
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    var droppedURLs: [URL] = []
                    let group = DispatchGroup()
                    
                    for provider in providers {
                        group.enter()
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                droppedURLs.append(url)
                            }
                            group.leave()
                        }
                    }
                    
                    group.notify(queue: .main) {
                        imageProcessor.processURLs(droppedURLs)
                    }
                    
                    return true
                }
                .disabled(imageProcessor.isProcessing)
                
                // Sub-section dynamically showing supported output sizes
                VStack(alignment: .leading, spacing: 16) {
                    Text("ACTIVE TARGET SPECIFICATIONS")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.green)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 24) {
                            ForEach(AppStoreTargetSizes.sizes.filter { $0.device == imageProcessor.selectedDevice }) { size in
                                SizeGraphicView(size: size)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    }
                }
                .padding(24)
                .background(Color.black)
                .border(Color.green.opacity(0.3), width: 1)
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

// Visual graphic representing portrait w x h
struct SizeGraphicView: View {
    let size: AppStoreSize
    
    var body: some View {
        VStack(spacing: 12) {
            let actualWidth = size.size.width
            let actualHeight = size.size.height
            let isLandscape = actualWidth > actualHeight
            
            let w = actualWidth / 35
            let h = actualHeight / 35
            
            ZStack {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: w, height: h)
                
                Rectangle()
                    .strokeBorder(Color.green, lineWidth: 1.5)
                    .frame(width: w, height: h)
                
                if isLandscape {
                    HStack(spacing: 2) {
                        Text("\(Int(actualWidth))")
                        Text("x").foregroundColor(.green.opacity(0.6))
                        Text("\(Int(actualHeight))")
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                } else {
                    VStack(spacing: 4) {
                        Text("\(Int(actualWidth))")
                        Text("x").foregroundColor(.green.opacity(0.6))
                        Text("\(Int(actualHeight))")
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .rotationEffect(.degrees(-90))
                }
            }
            .shadow(color: Color.green.opacity(0.2), radius: 5, x: 0, y: 0)
            
            Text(size.name.uppercased().replacingOccurrences(of: "_", with: " "))
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(.green)
                .opacity(isLandscape ? 0.6 : 1.0)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    ContentView()
}
