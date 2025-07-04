//
//  DownloadKitError.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 30.06.2025.
//

import Foundation

// MARK: - Core DownloadKit Errors

/// The primary error type for DownloadKit operations
public enum DownloadKitError: Error, LocalizedError, Equatable {
    case downloadQueueError(DownloadQueueError)
    case processorError(ProcessorError)
    case cacheError(CacheError)
    case mirrorPolicyError(MirrorPolicyError)
    case networkError(NetworkError)
    case fileSystemError(FileSystemError)
    
    // MARK: - LocalizedError
    
    public var errorDescription: String? {
        switch self {
        case .downloadQueueError(let error):
            return error.errorDescription
        case .processorError(let error):
            return error.errorDescription
        case .cacheError(let error):
            return error.errorDescription
        case .mirrorPolicyError(let error):
            return error.errorDescription
        case .networkError(let error):
            return error.errorDescription
        case .fileSystemError(let error):
            return error.errorDescription
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .downloadQueueError(let error):
            return error.failureReason
        case .processorError(let error):
            return error.failureReason
        case .cacheError(let error):
            return error.failureReason
        case .mirrorPolicyError(let error):
            return error.failureReason
        case .networkError(let error):
            return error.failureReason
        case .fileSystemError(let error):
            return error.failureReason
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .downloadQueueError(let error):
            return error.recoverySuggestion
        case .processorError(let error):
            return error.recoverySuggestion
        case .cacheError(let error):
            return error.recoverySuggestion
        case .mirrorPolicyError(let error):
            return error.recoverySuggestion
        case .networkError(let error):
            return error.recoverySuggestion
        case .fileSystemError(let error):
            return error.recoverySuggestion
        }
    }
}

// MARK: - Download Queue Errors

public enum DownloadQueueError: Error, LocalizedError, Equatable {
    case noProcessorAvailable(String)
    case downloadableNotSupported(String)
    case queueInactive
    case invalidDownloadable(String)
    
    public var errorDescription: String? {
        switch self {
        case .noProcessorAvailable(let identifier):
            return "No processor available for download: \(identifier)"
        case .downloadableNotSupported(let type):
            return "Downloadable type not supported: \(type)"
        case .queueInactive:
            return "Download queue is inactive"
        case .invalidDownloadable(let reason):
            return "Invalid downloadable: \(reason)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .noProcessorAvailable:
            return "No registered processor can handle this download type"
        case .downloadableNotSupported:
            return "The downloadable type is not supported by any available processor"
        case .queueInactive:
            return "The download queue has been paused or deactivated"
        case .invalidDownloadable:
            return "The downloadable object is in an invalid state"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .noProcessorAvailable:
            return "Register an appropriate download processor for this type of download"
        case .downloadableNotSupported:
            return "Check that the correct processors are registered with the download queue"
        case .queueInactive:
            return "Resume the download queue before attempting downloads"
        case .invalidDownloadable:
            return "Verify the downloadable object is properly configured"
        }
    }
}

// MARK: - Processor Errors

public enum ProcessorError: Error, LocalizedError, Equatable {
    case cannotProcess(String)
    case processorInactive
    case invalidParameters(String)
    case downloadFailed(String)
    case unsupportedDownloadType(String)
    
    public var errorDescription: String? {
        switch self {
        case .cannotProcess(let reason):
            return "Cannot process download: \(reason)"
        case .processorInactive:
            return "Download processor is inactive"
        case .invalidParameters(let parameter):
            return "Invalid parameter: \(parameter)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .unsupportedDownloadType(let type):
            return "Unsupported download type: \(type)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .cannotProcess:
            return "The processor cannot handle this download request"
        case .processorInactive:
            return "The processor has been deactivated or paused"
        case .invalidParameters:
            return "Required parameters are missing or invalid"
        case .downloadFailed:
            return "The download operation failed"
        case .unsupportedDownloadType:
            return "The download type is not supported by this processor"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .cannotProcess:
            return "Check the download configuration and try again"
        case .processorInactive:
            return "Ensure the processor is active before starting downloads"
        case .invalidParameters:
            return "Provide all required parameters with valid values"
        case .downloadFailed:
            return "Check network connectivity and retry the download"
        case .unsupportedDownloadType:
            return "Use a processor that supports this download type"
        }
    }
}

// MARK: - Cache Errors

public enum CacheError: Error, LocalizedError, Equatable {
    case fileAlreadyExists(String)
    case cannotGenerateLocalPath(String)
    case storageError(String)
    case databaseError(String)
    case fileNotFound(String)
    case permissionDenied(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileAlreadyExists(let path):
            return "File already exists at path: \(path)"
        case .cannotGenerateLocalPath(let reason):
            return "Cannot generate local path: \(reason)"
        case .storageError(let reason):
            return "Storage error: \(reason)"
        case .databaseError(let reason):
            return "Database error: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let operation):
            return "Permission denied for operation: \(operation)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .fileAlreadyExists:
            return "A file with the same name already exists at the target location"
        case .cannotGenerateLocalPath:
            return "Unable to create a unique local file path"
        case .storageError:
            return "Failed to store or retrieve file from cache"
        case .databaseError:
            return "Database operation failed"
        case .fileNotFound:
            return "The requested file does not exist in cache"
        case .permissionDenied:
            return "Insufficient permissions to perform the operation"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .fileAlreadyExists:
            return "Remove the existing file or use a different filename"
        case .cannotGenerateLocalPath:
            return "Clear some space or check file naming constraints"
        case .storageError:
            return "Check available disk space and file permissions"
        case .databaseError:
            return "Check database configuration and connectivity"
        case .fileNotFound:
            return "Verify the file exists or download it again"
        case .permissionDenied:
            return "Check file system permissions and app sandbox settings"
        }
    }
}

// MARK: - Mirror Policy Errors

public enum MirrorPolicyError: Error, LocalizedError, Equatable {
    case noMirrorsAvailable(String)
    case allMirrorsExhausted(String)
    case cannotGenerateDownloadable(String)
    case invalidMirrorConfiguration(String)
    
    public var errorDescription: String? {
        switch self {
        case .noMirrorsAvailable(let resourceId):
            return "No mirrors available for resource: \(resourceId)"
        case .allMirrorsExhausted(let resourceId):
            return "All mirrors exhausted for resource: \(resourceId)"
        case .cannotGenerateDownloadable(let mirrorId):
            return "Cannot generate downloadable for mirror: \(mirrorId)"
        case .invalidMirrorConfiguration(let reason):
            return "Invalid mirror configuration: \(reason)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .noMirrorsAvailable:
            return "No mirror locations are configured for this resource"
        case .allMirrorsExhausted:
            return "All available mirrors have been tried and failed"
        case .cannotGenerateDownloadable:
            return "Unable to create a downloadable object from the mirror"
        case .invalidMirrorConfiguration:
            return "The mirror configuration contains invalid settings"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .noMirrorsAvailable:
            return "Configure at least one valid mirror for the resource"
        case .allMirrorsExhausted:
            return "Check mirror availability and network connectivity"
        case .cannotGenerateDownloadable:
            return "Verify the mirror configuration and URL format"
        case .invalidMirrorConfiguration:
            return "Check the mirror settings and correct any invalid values"
        }
    }
}

// MARK: - Network Errors

public enum NetworkError: Error, LocalizedError, Equatable {
    case connectionFailed(String)
    case timeout(String)
    case invalidURL(String)
    case serverError(Int, String)
    case cancelled
    case noNetworkConnection
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .cancelled:
            return "Network operation was cancelled"
        case .noNetworkConnection:
            return "No network connection available"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .connectionFailed:
            return "Unable to establish a network connection"
        case .timeout:
            return "The network operation took too long to complete"
        case .invalidURL:
            return "The provided URL is malformed or invalid"
        case .serverError:
            return "The server returned an error response"
        case .cancelled:
            return "The network operation was cancelled by the user or system"
        case .noNetworkConnection:
            return "Device is not connected to the internet"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .connectionFailed:
            return "Check network connectivity and try again"
        case .timeout:
            return "Try again with a stronger network connection"
        case .invalidURL:
            return "Verify the URL format and try again"
        case .serverError:
            return "Contact the server administrator or try again later"
        case .cancelled:
            return "Restart the operation if needed"
        case .noNetworkConnection:
            return "Connect to Wi-Fi or cellular network and try again"
        }
    }
}

// MARK: - File System Errors

public enum FileSystemError: Error, LocalizedError, Equatable {
    case cannotCreateDirectory(String)
    case cannotMoveFile(from: String, to: String)
    case cannotDeleteFile(String)
    case insufficientSpace
    case fileCorrupted(String)
    case accessDenied(String)
    
    public var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory(let path):
            return "Cannot create directory: \(path)"
        case .cannotMoveFile(let from, let to):
            return "Cannot move file from \(from) to \(to)"
        case .cannotDeleteFile(let path):
            return "Cannot delete file: \(path)"
        case .insufficientSpace:
            return "Insufficient disk space"
        case .fileCorrupted(let path):
            return "File is corrupted: \(path)"
        case .accessDenied(let path):
            return "Access denied to file: \(path)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .cannotCreateDirectory:
            return "Unable to create the required directory structure"
        case .cannotMoveFile:
            return "File system operation failed"
        case .cannotDeleteFile:
            return "Unable to remove the file from storage"
        case .insufficientSpace:
            return "Not enough free space on the device"
        case .fileCorrupted:
            return "The file data is corrupted or incomplete"
        case .accessDenied:
            return "Insufficient permissions to access the file"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .cannotCreateDirectory:
            return "Check file permissions and available disk space"
        case .cannotMoveFile:
            return "Verify source and destination paths and permissions"
        case .cannotDeleteFile:
            return "Check file permissions and try again"
        case .insufficientSpace:
            return "Free up disk space and try again"
        case .fileCorrupted:
            return "Download the file again from the source"
        case .accessDenied:
            return "Check app permissions and file access rights"
        }
    }
}

// MARK: - CloudKit Specific Errors

public enum CloudKitError: Error, LocalizedError, Equatable {
    case noAssetData
    case noRecord
    case invalidRecordID(String)
    case databaseUnavailable
    case quotaExceeded
    case recordNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .noAssetData:
            return "No asset data found in CloudKit record"
        case .noRecord:
            return "CloudKit record not found"
        case .invalidRecordID(let recordID):
            return "Invalid CloudKit record ID: \(recordID)"
        case .databaseUnavailable:
            return "CloudKit database is unavailable"
        case .quotaExceeded:
            return "CloudKit quota exceeded"
        case .recordNotFound(let recordID):
            return "CloudKit record not found: \(recordID)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .noAssetData:
            return "The CloudKit record does not contain any file assets"
        case .noRecord:
            return "No CloudKit record exists for the requested download"
        case .invalidRecordID:
            return "The CloudKit record ID format is invalid"
        case .databaseUnavailable:
            return "CloudKit service is temporarily unavailable"
        case .quotaExceeded:
            return "CloudKit storage or transfer quota has been exceeded"
        case .recordNotFound:
            return "The specified CloudKit record does not exist"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .noAssetData:
            return "Verify the CloudKit record contains the expected asset fields"
        case .noRecord:
            return "Check that the record exists in CloudKit and try again"
        case .invalidRecordID:
            return "Verify the CloudKit URL format and record ID"
        case .databaseUnavailable:
            return "Try again later when CloudKit service is available"
        case .quotaExceeded:
            return "Contact app administrator or wait for quota reset"
        case .recordNotFound:
            return "Verify the record ID and check CloudKit database"
        }
    }
}

// MARK: - Convenience Extensions

public extension DownloadKitError {
    static func downloadQueue(_ error: DownloadQueueError) -> DownloadKitError {
        return .downloadQueueError(error)
    }
    
    static func processor(_ error: ProcessorError) -> DownloadKitError {
        return .processorError(error)
    }
    
    static func cache(_ error: CacheError) -> DownloadKitError {
        return .cacheError(error)
    }
    
    static func mirrorPolicy(_ error: MirrorPolicyError) -> DownloadKitError {
        return .mirrorPolicyError(error)
    }
    
    static func network(_ error: NetworkError) -> DownloadKitError {
        return .networkError(error)
    }
    
    static func fileSystem(_ error: FileSystemError) -> DownloadKitError {
        return .fileSystemError(error)
    }
}

// MARK: - Error Conversion Utilities

public extension DownloadKitError {
    /// Convert NSError to appropriate DownloadKitError
    static func from(_ nsError: NSError) -> DownloadKitError {
        switch nsError.domain {
        case NSURLErrorDomain:
            switch nsError.code {
            case NSURLErrorCancelled:
                return .network(.cancelled)
            case NSURLErrorTimedOut:
                return .network(.timeout("Request timed out"))
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return .network(.connectionFailed(nsError.localizedDescription))
            case NSURLErrorNotConnectedToInternet:
                return .network(.noNetworkConnection)
            case NSURLErrorBadURL:
                return .network(.invalidURL(nsError.localizedFailureReason ?? "Invalid URL"))
            default:
                return .network(.connectionFailed(nsError.localizedDescription))
            }
        case NSCocoaErrorDomain:
            switch nsError.code {
            case NSFileWriteFileExistsError:
                return .fileSystem(.cannotMoveFile(from: "temp", to: nsError.localizedFailureReason ?? "unknown"))
            case NSFileWriteNoPermissionError:
                return .fileSystem(.accessDenied(nsError.localizedFailureReason ?? "unknown"))
            default:
                return .fileSystem(.cannotMoveFile(from: "unknown", to: nsError.localizedDescription))
            }
        default:
            // For unknown NSError types, wrap as a generic processor error
            return .processor(.downloadFailed(nsError.localizedDescription))
        }
    }
}
