import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

@MainActor
class FileDropHandler: ObservableObject {
    static let shared = FileDropHandler()
    
    @Published var isDragging = false
    
    private let transcriptionQueue: TranscriptionQueue
    
    private init() {
        self.transcriptionQueue = TranscriptionQueue.shared
    }
    
    func handleDrop(of providers: [NSItemProvider]) async {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                do {
                    let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL?, Error>) in
                        provider.loadItem(forTypeIdentifier: UTType.audio.identifier) { item, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                                return
                            }
                            continuation.resume(returning: item as? URL)
                        }
                    }
                    
                    guard let url = url else {
                        print("Error loading item: not a URL")
                        continue
                    }
                    
                    print("Adding to queue: \(url)")
                    await transcriptionQueue.addFileToQueue(url: url)
                    
                } catch {
                    print("Error loading dropped audio file: \(error)")
                }
            }
        }
    }
}

