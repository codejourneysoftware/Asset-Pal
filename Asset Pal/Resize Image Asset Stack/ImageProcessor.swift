import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Combine

class ImageProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var totalFiles = 0
    @Published var currentFile = 0
    @Published var statusMessage = "Waiting for images..."
    @Published var selectedDevice: AppStoreDevice = .iphone
    @Published var terminalLogs: [String] = [
        "> TERMINAL BOOT SEQUENCE INITIATED...",
        "> MEMORY CHECK: OK",
        "> MAINFRAME ONLINE.",
        "> AWAITING ASSET DROP..."
    ]
    @Published var lastOutputDirectory: URL? = nil
    
    var isOutputDirectoryValid: Bool {
        guard let url = lastOutputDirectory else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    func appendLog(_ message: String) {
        DispatchQueue.main.async {
            self.terminalLogs.append("> \(message)")
        }
    }
    
    func clearLogs() {
        DispatchQueue.main.async {
            self.terminalLogs = [
                "> LOGS PURGED.",
                "> MAINFRAME READY.",
                "> AWAITING ASSET DROP..."
            ]
        }
    }
    
    func openLastOutputDirectory() {
        if let url = lastOutputDirectory {
            NSWorkspace.shared.open(url)
        }
    }

    let context = CIContext(options: nil)

    func processURLs(_ urls: [URL]) {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.statusMessage = "Analyzing items..."
            self.appendLog("ANALYZING DROPPED ITEMS...")
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var imageFiles: [URL] = []
            
            for url in urls {
                // If it's a directory, enumerate it
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles])
                    while let fileURL = enumerator?.nextObject() as? URL {
                        if self.isImage(url: fileURL) {
                            imageFiles.append(fileURL)
                        }
                    }
                } else if self.isImage(url: url) {
                    imageFiles.append(url)
                }
            }
            
            if imageFiles.isEmpty {
                DispatchQueue.main.async {
                    self.statusMessage = "No images found."
                    self.appendLog("ERROR: NO VALID IMAGE FORMATS DETECTED IN DROP.")
                    self.isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.totalFiles = imageFiles.count
                self.currentFile = 0
                self.statusMessage = "Select save location..."
                self.appendLog("FOUND \(self.totalFiles) VALID TARGET(S).")
                self.appendLog("AWAITING OUTPUT DIRECTORY SELECTION...")
            }
            
            // Ask for save folder on Main thread
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.title = "Select Output Folder"
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.prompt = "Save Here"
                
                panel.begin { response in
                    if response == .OK, let outputURL = panel.url {
                        self.lastOutputDirectory = outputURL
                        self.appendLog("DIRECTORY AQUIRED: \(outputURL.lastPathComponent)")
                        self.startProcessing(imageFiles: imageFiles, outputDir: outputURL)
                    } else {
                        // User cancelled
                        self.isProcessing = false
                        self.statusMessage = "Cancelled"
                        self.appendLog("OPERATION ABORTED BY USER.")
                    }
                }
            }
        }
    }
    
    private func isImage(url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.conforms(to: .image)
        }
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg"].contains(ext)
    }
    
    private func startProcessing(imageFiles: [URL], outputDir: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Request system permission to write outside the App Sandbox on this background thread
            let hasAccess = outputDir.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    outputDir.stopAccessingSecurityScopedResource()
                }
            }
            
            for (index, file) in imageFiles.enumerated() {
                DispatchQueue.main.async {
                    self.statusMessage = "Processing \(file.lastPathComponent)..."
                    self.appendLog("PROCESSING [\(index + 1)/\(self.totalFiles)]: \(file.lastPathComponent)")
                    self.currentFile = index + 1
                    self.progress = Double(self.currentFile) / Double(self.totalFiles)
                }
                
                guard let image = NSImage(contentsOf: file) else { 
                    self.appendLog("ERROR: Could not read image data from \(file.lastPathComponent).")
                    continue 
                }
                
                let filteredTargets = AppStoreTargetSizes.sizes.filter { $0.device == self.selectedDevice }
                
                for targetSize in filteredTargets {
                    if let resized = self.processAndResize(image: image, target: targetSize) {
                        self.save(image: resized, originalName: file.deletingPathExtension().lastPathComponent, targetName: targetSize.name, outputDir: outputDir)
                    } else {
                        self.appendLog("ERROR: Engine failed to resize \(file.lastPathComponent) to \(targetSize.name).")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.statusMessage = "Done! Processed \(self.totalFiles) image(s)."
                self.appendLog("PROCESS COMPLETE. \(self.totalFiles) TARGET(S) SUCCESSFULLY EXPORTED.")
                self.isProcessing = false
                self.progress = 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if !self.isProcessing {
                        self.statusMessage = "Ready."
                        self.progress = 0.0
                        self.appendLog("AWAITING NEXT ASSIGNMENT...")
                    }
                }
            }
        }
    }
    
    private func processAndResize(image: NSImage, target: AppStoreSize) -> NSImage? {
        let targetDimensions = target.size
        let outputRect = CGRect(origin: .zero, size: targetDimensions)
        
        // Setup drawing (32-bit RGBA for rendering stability)
        guard let customImageRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                    pixelsWide: Int(targetDimensions.width),
                                                    pixelsHigh: Int(targetDimensions.height),
                                                    bitsPerSample: 8,
                                                    samplesPerPixel: 4,
                                                    hasAlpha: true,
                                                    isPlanar: false,
                                                    colorSpaceName: .calibratedRGB,
                                                    bytesPerRow: 0,
                                                    bitsPerPixel: 0) else { return nil }
        
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: customImageRep) else { return nil }
        NSGraphicsContext.current = context
        
        // 1. Explicitly fill the entire background with solid black first.
        // This acts as a safety layer for any edge slivers.
        NSColor.black.set()
        outputRect.fill()
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        // Pixel-perfect source dimensions
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let sourceAspectRatio = sourceWidth / sourceHeight
        let targetAspectRatio = targetDimensions.width / targetDimensions.height
        
        // 2. Render Blurred Background
        let ciImage = CIImage(cgImage: cgImage)
        
        // Extension: Use Affine Clamp to repeat edge pixels infinitely, preventing dark blur borders.
        let clampFilter = CIFilter.affineClamp()
        clampFilter.inputImage = ciImage
        
        if let clampedCI = clampFilter.outputImage {
            let blurFilter = CIFilter.gaussianBlur()
            blurFilter.inputImage = clampedCI
            let minDimension = min(targetDimensions.width, targetDimensions.height)
            blurFilter.radius = Float(minDimension * 0.05) 
            
            // Create blurred image specifically using the original extent to avoid expand-to-infinity artifacts
            if let blurredCI = blurFilter.outputImage, 
               let blurredCG = self.context.createCGImage(blurredCI, from: ciImage.extent) {
                
                let blurredNS = NSImage(cgImage: blurredCG, size: CGSize(width: sourceWidth, height: sourceHeight))
                
                // Scale to fill + 4px bleed (2px each side) to ensure no black safety layer shows through
                let aspectFillRatio = max(targetDimensions.width / sourceWidth, targetDimensions.height / sourceHeight)
                let fillSize = CGSize(width: sourceWidth * aspectFillRatio + 4, height: sourceHeight * aspectFillRatio + 4)
                let fillRect = CGRect(x: (targetDimensions.width - fillSize.width) / 2.0,
                                      y: (targetDimensions.height - fillSize.height) / 2.0,
                                      width: fillSize.width,
                                      height: fillSize.height)
                
                blurredNS.draw(in: fillRect)
                
                // Add a subtle black tint for better content contrast (reduced to 0.2 for smoother look)
                NSColor(white: 0, alpha: 0.2).setFill()
                outputRect.fill(using: .sourceAtop)
            }
        }
        
        // 3. Render Foreground Image
        // Use Smart-Fill: If aspect ratios are extremely close, use Fill instead of Fit to avoid slivers.
        let isNearlySameAspect = abs(sourceAspectRatio - targetAspectRatio) < 0.005
        let logicRatio = isNearlySameAspect ? 
            max(targetDimensions.width / sourceWidth, targetDimensions.height / sourceHeight) :
            min(targetDimensions.width / sourceWidth, targetDimensions.height / sourceHeight)
        
        let finalFitSize = CGSize(width: sourceWidth * logicRatio, height: sourceHeight * logicRatio)
        let finalFitRect = CGRect(x: (targetDimensions.width - finalFitSize.width) / 2.0,
                                  y: (targetDimensions.height - finalFitSize.height) / 2.0,
                                  width: finalFitSize.width,
                                  height: finalFitSize.height)
        
        // Re-extract NSImage for pixel-perfect drawing context
        let foregroundNS = NSImage(cgImage: cgImage, size: CGSize(width: sourceWidth, height: sourceHeight))
        foregroundNS.draw(in: finalFitRect)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let finalImage = NSImage(size: targetDimensions)
        finalImage.addRepresentation(customImageRep)
        return finalImage
    }
    
    private func save(image: NSImage, originalName: String, targetName: String, outputDir: URL) {
        // Use Core Graphics to ensure the export is opaque (no alpha channel).
        // AppKit's NSGraphicsContext can fail for opaque buffers, but Core Graphics is natively robust for this.
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { 
            self.appendLog("ERROR: Engine failed to extract raw image data for \(targetName).")
            return 
        }
        
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Create an opaque 32-bit context (noneSkipLast) which is natively supported for drawing.
        // Cocoa's PNG writer will then treat this the same as a 24-bit RGB file upon export.
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            self.appendLog("ERROR: Engine failed to create opaque CGContext for \(targetName).")
            return
        }
        
        // Draw into the opaque context
        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.draw(cgImage, in: rect)
        
        guard let opaqueCGImage = context.makeImage() else {
            self.appendLog("ERROR: Engine failed to commit opaque image for \(targetName).")
            return
        }
        
        // Convert to NSBitmapImageRep for PNG compression
        let bitmapRep = NSBitmapImageRep(cgImage: opaqueCGImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { 
            self.appendLog("ERROR: PNG data compression failed for \(targetName).")
            return 
        }
        
        let folderURL = outputDir.appendingPathComponent(targetName, isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            self.appendLog("FS ERROR: Could not create folder at \(folderURL.path). \(error.localizedDescription)")
            return
        }
        
        let fileURL = folderURL.appendingPathComponent("\(originalName)_AppStore.png")
        
        do {
            try pngData.write(to: fileURL)
            self.appendLog("    [✓] \(targetName) successfully written.")
        } catch {
            self.appendLog("FS ERROR: Write failed for \(fileURL.lastPathComponent). \(error.localizedDescription)")
        }
    }
}
