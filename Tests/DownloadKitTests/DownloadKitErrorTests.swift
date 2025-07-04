//
//  DownloadKitErrorTests.swift
//  DownloadKitTests
//
//  Created by Dal Rupnik on 30.06.2025.
//

import XCTest
@testable import DownloadKit

class DownloadKitErrorTests: XCTestCase {
    
    // MARK: - DownloadKitError Tests
    
    func testDownloadKitErrorLocalizedDescription() {
        let queueError = DownloadKitError.downloadQueue(.noProcessorAvailable("test-id"))
        XCTAssertTrue(queueError.localizedDescription.contains("No processor available for download: test-id"))
        
        let processorError = DownloadKitError.processor(.cannotProcess("test reason"))
        XCTAssertTrue(processorError.localizedDescription.contains("Cannot process download: test reason"))
        
        let cacheError = DownloadKitError.cache(.fileNotFound("/path/to/file"))
        XCTAssertTrue(cacheError.localizedDescription.contains("File not found: /path/to/file"))
        
        let networkError = DownloadKitError.network(.connectionFailed("Network unreachable"))
        XCTAssertTrue(networkError.localizedDescription.contains("Connection failed: Network unreachable"))
    }
    
    func testDownloadKitErrorFailureReason() {
        let queueError = DownloadKitError.downloadQueue(.queueInactive)
        XCTAssertTrue(queueError.failureReason?.contains("download queue has been paused") == true)
        
        let processorError = DownloadKitError.processor(.processorInactive)
        XCTAssertTrue(processorError.failureReason?.contains("processor has been deactivated") == true)
        
        let cacheError = DownloadKitError.cache(.permissionDenied("write"))
        XCTAssertTrue(cacheError.failureReason?.contains("Insufficient permissions") == true)
    }
    
    func testDownloadKitErrorRecoverySuggestion() {
        let queueError = DownloadKitError.downloadQueue(.noProcessorAvailable("test-id"))
        XCTAssertTrue(queueError.recoverySuggestion?.contains("Register an appropriate download processor") == true)
        
        let networkError = DownloadKitError.network(.noNetworkConnection)
        XCTAssertTrue(networkError.recoverySuggestion?.contains("Connect to Wi-Fi or cellular") == true)
    }
    
    // MARK: - DownloadQueueError Tests
    
    func testDownloadQueueError() {
        let noProcessor = DownloadQueueError.noProcessorAvailable("test-download")
        XCTAssertEqual(noProcessor.errorDescription, "No processor available for download: test-download")
        XCTAssertTrue(noProcessor.failureReason?.contains("No registered processor") == true)
        XCTAssertTrue(noProcessor.recoverySuggestion?.contains("Register an appropriate") == true)
        
        let queueInactive = DownloadQueueError.queueInactive
        XCTAssertEqual(queueInactive.errorDescription, "Download queue is inactive")
        XCTAssertTrue(queueInactive.failureReason?.contains("paused or deactivated") == true)
        XCTAssertTrue(queueInactive.recoverySuggestion?.contains("Resume the download queue") == true)
    }
    
    // MARK: - ProcessorError Tests
    
    func testProcessorError() {
        let cannotProcess = ProcessorError.cannotProcess("unsupported format")
        XCTAssertEqual(cannotProcess.errorDescription, "Cannot process download: unsupported format")
        XCTAssertTrue(cannotProcess.failureReason?.contains("processor cannot handle") == true)
        XCTAssertTrue(cannotProcess.recoverySuggestion?.contains("Check the download configuration") == true)
        
        let downloadFailed = ProcessorError.downloadFailed("connection timeout")
        XCTAssertEqual(downloadFailed.errorDescription, "Download failed: connection timeout")
        XCTAssertTrue(downloadFailed.failureReason?.contains("download operation failed") == true)
        XCTAssertTrue(downloadFailed.recoverySuggestion?.contains("Check network connectivity") == true)
    }
    
    // MARK: - CacheError Tests
    
    func testCacheError() {
        let fileExists = CacheError.fileAlreadyExists("/path/to/existing/file")
        XCTAssertEqual(fileExists.errorDescription, "File already exists at path: /path/to/existing/file")
        XCTAssertTrue(fileExists.failureReason?.contains("file with the same name already exists") == true)
        XCTAssertTrue(fileExists.recoverySuggestion?.contains("Remove the existing file") == true)
        
        let storageError = CacheError.storageError("disk full")
        XCTAssertEqual(storageError.errorDescription, "Storage error: disk full")
        XCTAssertTrue(storageError.failureReason?.contains("Failed to store or retrieve") == true)
        XCTAssertTrue(storageError.recoverySuggestion?.contains("Check available disk space") == true)
    }
    
    // MARK: - NetworkError Tests
    
    func testNetworkError() {
        let connectionFailed = NetworkError.connectionFailed("host unreachable")
        XCTAssertEqual(connectionFailed.errorDescription, "Connection failed: host unreachable")
        XCTAssertTrue(connectionFailed.failureReason?.contains("Unable to establish") == true)
        XCTAssertTrue(connectionFailed.recoverySuggestion?.contains("Check network connectivity") == true)
        
        let timeout = NetworkError.timeout("upload")
        XCTAssertEqual(timeout.errorDescription, "Operation timed out: upload")
        XCTAssertTrue(timeout.failureReason?.contains("took too long") == true)
        XCTAssertTrue(timeout.recoverySuggestion?.contains("stronger network connection") == true)
        
        let cancelled = NetworkError.cancelled
        XCTAssertEqual(cancelled.errorDescription, "Network operation was cancelled")
        XCTAssertTrue(cancelled.failureReason?.contains("cancelled by the user") == true)
        XCTAssertTrue(cancelled.recoverySuggestion?.contains("Restart the operation") == true)
        
        let serverError = NetworkError.serverError(404, "Not Found")
        XCTAssertEqual(serverError.errorDescription, "Server error (404): Not Found")
        XCTAssertTrue(serverError.failureReason?.contains("server returned an error") == true)
        XCTAssertTrue(serverError.recoverySuggestion?.contains("Contact the server administrator") == true)
    }
    
    // MARK: - FileSystemError Tests
    
    func testFileSystemError() {
        let cannotCreate = FileSystemError.cannotCreateDirectory("/path/to/dir")
        XCTAssertEqual(cannotCreate.errorDescription, "Cannot create directory: /path/to/dir")
        XCTAssertTrue(cannotCreate.failureReason?.contains("Unable to create the required directory") == true)
        XCTAssertTrue(cannotCreate.recoverySuggestion?.contains("Check file permissions") == true)
        
        let cannotMove = FileSystemError.cannotMoveFile(from: "/source", to: "/dest")
        XCTAssertEqual(cannotMove.errorDescription, "Cannot move file from /source to /dest")
        XCTAssertTrue(cannotMove.failureReason?.contains("File system operation failed") == true)
        XCTAssertTrue(cannotMove.recoverySuggestion?.contains("Verify source and destination paths") == true)
        
        let insufficientSpace = FileSystemError.insufficientSpace
        XCTAssertEqual(insufficientSpace.errorDescription, "Insufficient disk space")
        XCTAssertTrue(insufficientSpace.failureReason?.contains("Not enough free space") == true)
        XCTAssertTrue(insufficientSpace.recoverySuggestion?.contains("Free up disk space") == true)
    }
    
    // MARK: - CloudKitError Tests
    
    func testCloudKitError() {
        let noAssetData = CloudKitError.noAssetData
        XCTAssertEqual(noAssetData.errorDescription, "No asset data found in CloudKit record")
        XCTAssertTrue(noAssetData.failureReason?.contains("does not contain any file assets") == true)
        XCTAssertTrue(noAssetData.recoverySuggestion?.contains("Verify the CloudKit record contains") == true)
        
        let noRecord = CloudKitError.noRecord
        XCTAssertEqual(noRecord.errorDescription, "CloudKit record not found")
        XCTAssertTrue(noRecord.failureReason?.contains("No CloudKit record exists") == true)
        XCTAssertTrue(noRecord.recoverySuggestion?.contains("Check that the record exists") == true)
        
        let invalidRecordID = CloudKitError.invalidRecordID("malformed-id")
        XCTAssertEqual(invalidRecordID.errorDescription, "Invalid CloudKit record ID: malformed-id")
        XCTAssertTrue(invalidRecordID.failureReason?.contains("record ID format is invalid") == true)
        XCTAssertTrue(invalidRecordID.recoverySuggestion?.contains("Verify the CloudKit URL format") == true)
    }
    
    // MARK: - MirrorPolicyError Tests
    
    func testMirrorPolicyError() {
        let noMirrors = MirrorPolicyError.noMirrorsAvailable("resource-123")
        XCTAssertEqual(noMirrors.errorDescription, "No mirrors available for resource: resource-123")
        XCTAssertTrue(noMirrors.failureReason?.contains("No mirror locations are configured") == true)
        XCTAssertTrue(noMirrors.recoverySuggestion?.contains("Configure at least one valid mirror") == true)
        
        let exhausted = MirrorPolicyError.allMirrorsExhausted("resource-456")
        XCTAssertEqual(exhausted.errorDescription, "All mirrors exhausted for resource: resource-456")
        XCTAssertTrue(exhausted.failureReason?.contains("All available mirrors have been tried") == true)
        XCTAssertTrue(exhausted.recoverySuggestion?.contains("Check mirror availability") == true)
    }
    
    // MARK: - NSError Conversion Tests
    
    func testNSErrorToDownloadKitErrorConversion() {
        // Test URL errors
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: [NSLocalizedDescriptionKey: "Request was cancelled"])
        let convertedUrlError = DownloadKitError.from(urlError)
        if case .networkError(.cancelled) = convertedUrlError {
            // Expected
        } else {
            XCTFail("Should convert NSURLErrorCancelled to NetworkError.cancelled")
        }
        
        let timeoutError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "Request timed out"])
        let convertedTimeoutError = DownloadKitError.from(timeoutError)
        if case .networkError(.timeout(_)) = convertedTimeoutError {
            // Expected
        } else {
            XCTFail("Should convert NSURLErrorTimedOut to NetworkError.timeout")
        }
        
        let connectionError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: [NSLocalizedDescriptionKey: "Cannot connect"])
        let convertedConnectionError = DownloadKitError.from(connectionError)
        if case .networkError(.connectionFailed(_)) = convertedConnectionError {
            // Expected
        } else {
            XCTFail("Should convert connection errors to NetworkError.connectionFailed")
        }
        
        // Test file system errors
        let fileExistsError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError, userInfo: [NSLocalizedDescriptionKey: "File exists"])
        let convertedFileError = DownloadKitError.from(fileExistsError)
        if case .fileSystemError(.cannotMoveFile(_, _)) = convertedFileError {
            // Expected
        } else {
            XCTFail("Should convert file exists error to FileSystemError.cannotMoveFile")
        }
        
        // Test unknown error domain
        let unknownError = NSError(domain: "com.unknown.domain", code: 1234, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
        let convertedUnknownError = DownloadKitError.from(unknownError)
        if case .processorError(.downloadFailed(_)) = convertedUnknownError {
            // Expected
        } else {
            XCTFail("Should convert unknown errors to ProcessorError.downloadFailed")
        }
    }
    
    // MARK: - Convenience Extensions Tests
    
    func testConvenienceExtensions() {
        let queueError = DownloadQueueError.queueInactive
        let wrappedQueueError = DownloadKitError.downloadQueue(queueError)
        if case .downloadQueueError(let unwrapped) = wrappedQueueError {
            XCTAssertEqual(unwrapped, queueError)
        } else {
            XCTFail("Convenience extension should wrap queue error correctly")
        }
        
        let processorError = ProcessorError.processorInactive
        let wrappedProcessorError = DownloadKitError.processor(processorError)
        if case .processorError(let unwrapped) = wrappedProcessorError {
            XCTAssertEqual(unwrapped, processorError)
        } else {
            XCTFail("Convenience extension should wrap processor error correctly")
        }
        
        let fileSystemError = FileSystemError.insufficientSpace
        let wrappedFileSystemError = DownloadKitError.fileSystem(fileSystemError)
        if case .fileSystemError(let unwrapped) = wrappedFileSystemError {
            XCTAssertEqual(unwrapped, fileSystemError)
        } else {
            XCTFail("Convenience extension should wrap file system error correctly")
        }
    }
    
    // MARK: - Error Equality Tests
    
    func testErrorEquality() {
        let error1 = DownloadQueueError.noProcessorAvailable("test-id")
        let error2 = DownloadQueueError.noProcessorAvailable("test-id")
        let error3 = DownloadQueueError.noProcessorAvailable("different-id")
        
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
        
        let networkError1 = NetworkError.cancelled
        let networkError2 = NetworkError.cancelled
        let networkError3 = NetworkError.noNetworkConnection
        
        XCTAssertEqual(networkError1, networkError2)
        XCTAssertNotEqual(networkError1, networkError3)
    }
}
