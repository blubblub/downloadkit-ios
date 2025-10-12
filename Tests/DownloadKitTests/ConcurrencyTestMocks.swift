//
//  ConcurrencyTestMocks.swift
//  DownloadKitTests
//
//  Mock actors and implementations for testing concurrent download operations.
//

import XCTest
import Foundation
@testable import DownloadKit

// MARK: - Mock Downloadable Implementation

/// Mock downloadable that simulates downloads using Task.sleep()
actor MockDownloadable: Downloadable {
    
    enum State {
        case idle
        case downloading
        case completed
        case failed
        case cancelled
    }
    
    // MARK: - Configuration
    
    private let _identifier: String
    let delay: TimeInterval
    private let shouldSucceed: Bool
    private let mockFileURL: URL
    
    // MARK: - State
    
    private var state: State = .idle
    private var _startDate: Date?
    private var _finishedDate: Date?
    private var _progress: Foundation.Progress?
    private var _totalBytes: Int64 = 0
    private var _totalSize: Int64 = 1024 * 1024 // 1MB default
    private var _transferredBytes: Int64 = 0
    private var isCancelled = false
    
    // MARK: - Callbacks
    
    var onComplete: ((Result<URL, Error>) -> Void)?
    var onProgress: ((Int64, Int64) -> Void)?
    
    // MARK: - Downloadable Protocol
    
    var identifier: String { _identifier }
    var totalBytes: Int64 { _totalBytes }
    var totalSize: Int64 { _totalSize }
    var transferredBytes: Int64 { _transferredBytes }
    var startDate: Date? { _startDate }
    var finishedDate: Date? { _finishedDate }
    var progress: Foundation.Progress? { _progress }
    
    // MARK: - Initialization
    
    init(identifier: String, delay: TimeInterval, shouldSucceed: Bool, fileURL: URL) {
        self._identifier = identifier
        self.delay = delay
        self.shouldSucceed = shouldSucceed
        self.mockFileURL = fileURL
        self._progress = Foundation.Progress(totalUnitCount: _totalSize)
    }
    
    // MARK: - Public Methods
    
    func start(with parameters: DownloadParameters) {
        guard state == .idle else { return }
        
        state = .downloading
        _startDate = Date()
        
        // Perform simulated download on background thread using Task.sleep
        Task.detached { [weak self, delay, shouldSucceed, mockFileURL] in
            print("STARTED PROCESSSING MOCK...")
            
            guard let self = self else { return }
            
            // Simulate download with periodic progress updates
            let chunks = 10
            let chunkDelay = delay / Double(chunks)
            let chunkDelayNanos = UInt64(chunkDelay * 1_000_000_000)
            
            for i in 1...chunks {
                // Check for cancellation
                let cancelled = await self.checkCancellation()
                if cancelled {
                    print("CANCELLED PROCESSING MOCK...")
                    await self.handleCancellation()
                    return
                }
                
                // Sleep to simulate work using Task.sleep
                try? await Task.sleep(nanoseconds: chunkDelayNanos)
                
                // Update progress
                await self.updateProgress(chunk: i, totalChunks: chunks)
            }
            
            print("FINISHED PROCESSING MOCK...")
            
            // Complete the download
            await self.completeDownload(success: shouldSucceed, fileURL: mockFileURL)
        }
    }
    
    func cancel() {
        isCancelled = true
        if state == .downloading {
            state = .cancelled
            _finishedDate = Date()
        }
    }
    
    func pause() {
        // No-op for mock
    }
    
    // MARK: - Internal Helpers
    
    private func checkCancellation() -> Bool {
        return isCancelled
    }
    
    private func handleCancellation() {
        state = .cancelled
        _finishedDate = Date()
        let error = NSError(domain: "MockDownloadable", code: -999, userInfo: [NSLocalizedDescriptionKey: "Download was cancelled"])
        onComplete?(.failure(error))
    }
    
    private func updateProgress(chunk: Int, totalChunks: Int) {
        let bytesTransferred = (_totalSize * Int64(chunk)) / Int64(totalChunks)
        _transferredBytes = bytesTransferred
        _progress?.completedUnitCount = bytesTransferred
        onProgress?(_transferredBytes, _totalSize)
    }
    
    private func completeDownload(success: Bool, fileURL: URL) {
        _finishedDate = Date()
        
        if success {
            state = .completed
            _transferredBytes = _totalSize
            _totalBytes = _totalSize
            _progress?.completedUnitCount = _totalSize
            onComplete?(.success(fileURL))
        } else {
            state = .failed
            let error = NSError(domain: "MockDownloadable", code: -1, userInfo: [NSLocalizedDescriptionKey: "Simulated download failure"])
            onComplete?(.failure(error))
        }
    }
    
    // MARK: - Test Helpers
    
    func getCurrentState() -> State {
        return state
    }
    
    func setOnComplete(_ callback: @escaping (Result<URL, Error>) -> Void) {
        self.onComplete = callback
    }
    
    func setOnProgress(_ callback: @escaping (Int64, Int64) -> Void) {
        self.onProgress = callback
    }
}

// MARK: - Mock Mirror Policy

struct MockDownloadableConfiguration : Sendable {
    let finishedURL: URL?
    let shouldSucceed: Bool
    let delay: TimeInterval
}

/// Simple mirror policy that returns the mock downloadable
actor MockMirrorPolicy: MirrorPolicy {
    private var configurations: [String: MockDownloadableConfiguration] = [:]
    
    func addConfiguration(_ configuration: MockDownloadableConfiguration, forResource id: String) {
        self.configurations[id] = configuration
    }
    
    
    // MARK: - Mirror Policy
    
    func downloadable(for resource: ResourceFile, lastDownloadableIdentifier: String?, error: Error?) -> Downloadable? {
        guard let configuration = configurations[resource.id] else {
            return nil
        }
        
        return MockDownloadable(identifier: resource.id, delay: configuration.delay, shouldSucceed: configuration.shouldSucceed, fileURL: configuration.finishedURL ?? URL(fileURLWithPath: "/tmp/mock"))
    }
}

// MARK: - Mock Download Processor

actor MockDownloadProcessor: DownloadProcessor {
    weak var observer: DownloadProcessorObserver?
    private(set) var isActive: Bool = true
    private var processingTasks: [String: Task<Void, Never>] = [:]
    
    func set(observer: DownloadProcessorObserver?) {
        self.observer = observer
    }
    
    func canProcess(downloadable: Downloadable) -> Bool {
        return downloadable is MockDownloadable
    }
    
    func process(_ downloadable: Downloadable) async {
        guard let mockDownloadable = downloadable as? MockDownloadable else {
            return
        }
        
        // Notify observer that download began (nonisolated)
        if let observer = observer {
            Task {
                await observer.downloadDidBegin(self, downloadable: downloadable)
            }
        }
        
        // Set up completion callback
        await mockDownloadable.setOnComplete { @Sendable [weak self, weak downloadable] result in
            guard let self = self, let downloadable = downloadable else { return }
            
            Task {
                switch result {
                case .success(let url):
                    await self.observer?.downloadDidFinishTransfer(self, downloadable: downloadable, to: url)
                    await self.observer?.downloadDidFinish(self, downloadable: downloadable)
                case .failure(let error):
                    await self.observer?.downloadDidError(self, downloadable: downloadable, error: error)
                }
            }
        }
        
        // Set up progress callback
        await mockDownloadable.setOnProgress { @Sendable [weak self, weak downloadable] transferred, total in
            guard let self = self, let downloadable = downloadable else { return }
            
            Task {
                if transferred > 0 {
                    await self.observer?.downloadDidStartTransfer(self, downloadable: downloadable)
                }
                await self.observer?.downloadDidTransferData(self, downloadable: downloadable)
            }
        }
        
        // Start the download
        await mockDownloadable.start(with: [:])
    }
    
    func enqueuePending() async {
        // No-op for mock processor
    }
    
    func pause() async {
        isActive = false
    }
    
    func resume() async {
        isActive = true
    }
}
