//
//  CachedLocalFileRealmTests.swift
//  DownloadKitTests
//
//  Created by Assistant on 2025-09-15.
//

import XCTest
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

/// Tests for CachedLocalFile Realm operations, specifically primary key insertion and fetching
class CachedLocalFileRealmTests: XCTestCase {
    
    var realm: Realm!
    
    override func setUpWithError() throws {
        // Setup will be done in async test methods to avoid concurrency issues
    }
    
    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        realm = nil
    }
    
    /// Helper method to create an in-memory Realm for testing
    private func setupRealm() throws {
        let config = Realm.Configuration(
            inMemoryIdentifier: "cached-local-file-test-\(UUID().uuidString)"
        )
        
        // Create Realm instance synchronously
        realm = try Realm(configuration: config)
    }
    
    // MARK: - Primary Key Tests
    
    /// Test that CachedLocalFile can be inserted into Realm and fetched by primary key
    func testInsertAndFetchByPrimaryKey() throws {
        try setupRealm()
        
        // Create a test CachedLocalFile instance
        let testId = "test-resource-\(UUID().uuidString)"
        let testMirrorId = "test-mirror-\(UUID().uuidString)"
        let testFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-file.jpg")
        // Use a specific date to avoid precision issues
        let testCreatedDate = Date(timeIntervalSince1970: 1234567890)
        
        let cachedFile = CachedLocalFile()
        cachedFile.id = testId
        cachedFile.mirrorId = testMirrorId
        cachedFile.fileURL = testFileURL
        cachedFile.createdDate = testCreatedDate  // Use the actual property name
        cachedFile.storage = .cached
        
        // Insert into Realm
        try realm.write {
            realm.add(cachedFile, update: .modified)
        }
        
        // Fetch by primary key
        let fetchedFile = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: testId)
        
        // Verify the object was fetched successfully
        XCTAssertNotNil(fetchedFile, "Should be able to fetch CachedLocalFile by primary key")
        
        // Verify all properties match
        XCTAssertEqual(fetchedFile?.id, testId, "ID should match")
        XCTAssertEqual(fetchedFile?.mirrorId, testMirrorId, "Mirror ID should match")
        XCTAssertEqual(fetchedFile?.fileURL.absoluteString, testFileURL.absoluteString, "File URL should match")
        XCTAssertEqual(fetchedFile?.createdDate, testCreatedDate, "Created date should match")
        XCTAssertEqual(fetchedFile?.storage, .cached, "Storage priority should match")
    }
    
    /// Test that updating an existing CachedLocalFile by primary key works correctly
    func testUpdateExistingByPrimaryKey() throws {
        try setupRealm()
        
        let testId = "update-test-\(UUID().uuidString)"
        let originalURL = FileManager.default.temporaryDirectory.appendingPathComponent("original.jpg")
        let updatedURL = FileManager.default.temporaryDirectory.appendingPathComponent("updated.jpg")
        
        // Insert original file
        let originalFile = CachedLocalFile()
        originalFile.id = testId
        originalFile.mirrorId = "original-mirror"
        originalFile.fileURL = originalURL
        originalFile.storage = .cached
        
        try realm.write {
            realm.add(originalFile, update: .modified)
        }
        
        // Verify original was inserted
        let fetchedOriginal = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: testId)
        XCTAssertEqual(fetchedOriginal?.mirrorId, "original-mirror", "Original mirror ID should be set")
        XCTAssertEqual(fetchedOriginal?.fileURL.absoluteString, originalURL.absoluteString, "Original URL should be set")
        
        // Update the same object with new values
        let updatedFile = CachedLocalFile()
        updatedFile.id = testId  // Same primary key
        updatedFile.mirrorId = "updated-mirror"
        updatedFile.fileURL = updatedURL
        updatedFile.storage = .permanent
        
        try realm.write {
            realm.add(updatedFile, update: .modified)
        }
        
        // Fetch again and verify update
        let fetchedUpdated = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: testId)
        XCTAssertNotNil(fetchedUpdated, "Should still be able to fetch after update")
        XCTAssertEqual(fetchedUpdated?.mirrorId, "updated-mirror", "Mirror ID should be updated")
        XCTAssertEqual(fetchedUpdated?.fileURL.absoluteString, updatedURL.absoluteString, "File URL should be updated")
        XCTAssertEqual(fetchedUpdated?.storage, .permanent, "Storage priority should be updated")
        
        // Verify there's still only one object with this ID
        let allObjects = realm.objects(CachedLocalFile.self).filter("identifier = %@", testId)
        XCTAssertEqual(allObjects.count, 1, "Should have exactly one object with this primary key")
    }
    
    /// Test fetching non-existent object by primary key returns nil
    func testFetchNonExistentByPrimaryKey() throws {
        try setupRealm()
        
        let nonExistentId = "non-existent-\(UUID().uuidString)"
        
        // Try to fetch an object that doesn't exist
        let fetchedFile = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: nonExistentId)
        
        XCTAssertNil(fetchedFile, "Fetching non-existent object should return nil")
    }
    
    /// Test that multiple CachedLocalFiles can be inserted and fetched independently
    func testMultipleInsertAndFetch() throws {
        try setupRealm()
        
        // Create multiple test files
        let testFiles: [(id: String, mirrorId: String)] = [
            ("file-1", "mirror-1"),
            ("file-2", "mirror-2"),
            ("file-3", "mirror-3")
        ]
        
        // Insert all files
        try realm.write {
            for (id, mirrorId) in testFiles {
                let cachedFile = CachedLocalFile()
                cachedFile.id = id
                cachedFile.mirrorId = mirrorId
                cachedFile.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).jpg")
                cachedFile.storage = .cached
                
                realm.add(cachedFile, update: .modified)
            }
        }
        
        // Verify each can be fetched independently by primary key
        for (id, mirrorId) in testFiles {
            let fetchedFile = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: id)
            XCTAssertNotNil(fetchedFile, "Should be able to fetch file with ID: \(id)")
            XCTAssertEqual(fetchedFile?.id, id, "ID should match for \(id)")
            XCTAssertEqual(fetchedFile?.mirrorId, mirrorId, "Mirror ID should match for \(id)")
        }
        
        // Verify total count
        let allFiles = realm.objects(CachedLocalFile.self)
        XCTAssertEqual(allFiles.count, testFiles.count, "Should have correct total number of files")
    }
    
    /// Test that primary key constraint is enforced (duplicates update the existing record)
    func testPrimaryKeyUniqueness() throws {
        try setupRealm()
        
        let testId = "unique-test-\(UUID().uuidString)"
        
        // Insert first file
        let firstFile = CachedLocalFile()
        firstFile.id = testId
        firstFile.mirrorId = "first-mirror"
        firstFile.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("first.jpg")
        
        try realm.write {
            realm.add(firstFile)
        }
        
        // Verify first file was inserted
        let fetchedFirst = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: testId)
        XCTAssertEqual(fetchedFirst?.mirrorId, "first-mirror", "First file should be inserted")
        
        // Try to insert another file with the same primary key using .modified policy (updates existing)
        let duplicateFile = CachedLocalFile()
        duplicateFile.id = testId  // Same primary key
        duplicateFile.mirrorId = "updated-mirror"
        duplicateFile.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("updated.jpg")
        
        // This should update the existing record
        try realm.write {
            realm.add(duplicateFile, update: .modified)
        }
        
        // Verify the record was updated, not duplicated
        let fetchedUpdated = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: testId)
        XCTAssertEqual(fetchedUpdated?.mirrorId, "updated-mirror", "Record should be updated")
        
        // Verify there's only one record with this ID
        let allRecords = realm.objects(CachedLocalFile.self).filter("identifier = %@", testId)
        XCTAssertEqual(allRecords.count, 1, "Should have exactly one record with this primary key")
    }
    
    /// Test deleting an object and verifying it can no longer be fetched by primary key
    func testDeleteAndFetchByPrimaryKey() throws {
        try setupRealm()
        
        let testId = "delete-test-\(UUID().uuidString)"
        
        // Insert a file
        let cachedFile = CachedLocalFile()
        cachedFile.id = testId
        cachedFile.mirrorId = "to-be-deleted"
        cachedFile.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("delete.jpg")
        
        try realm.write {
            realm.add(cachedFile)
        }
        
        // Verify it exists
        let fetchedBeforeDelete = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: testId)
        XCTAssertNotNil(fetchedBeforeDelete, "File should exist before deletion")
        
        // Delete the object
        try realm.write {
            if let objectToDelete = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: testId) {
                realm.delete(objectToDelete)
            }
        }
        
        // Verify it no longer exists
        let fetchedAfterDelete = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: testId)
        XCTAssertNil(fetchedAfterDelete, "File should not exist after deletion")
    }
    
    /// Test that all CachedLocalFile properties are correctly persisted and retrieved
    func testAllPropertiesPersistence() throws {
        try setupRealm()
        
        let testId = "full-test-\(UUID().uuidString)"
        let testMirrorId = "full-mirror-\(UUID().uuidString)"
        let testURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subdir")
            .appendingPathComponent("test-file-with-long-name.jpg")
        let testDate = Date(timeIntervalSince1970: 1234567890) // Specific date for testing
        
        // Create file with all properties set
        let cachedFile = CachedLocalFile()
        cachedFile.identifier = testId
        cachedFile.mirrorIdentifier = testMirrorId
        cachedFile.url = testURL.absoluteString
        cachedFile.createdDate = testDate
        cachedFile.storagePriority = StoragePriority.permanent.rawValue
        
        // Insert into Realm
        try realm.write {
            realm.add(cachedFile)
        }
        
        // Fetch and verify all properties
        guard let fetchedFile = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: testId) else {
            XCTFail("Should be able to fetch the file")
            return
        }
        
        // Verify raw persisted properties
        XCTAssertEqual(fetchedFile.identifier, testId, "Identifier should match")
        XCTAssertEqual(fetchedFile.mirrorIdentifier, testMirrorId, "Mirror identifier should match")
        XCTAssertEqual(fetchedFile.url, testURL.absoluteString, "URL string should match")
        XCTAssertEqual(fetchedFile.createdDate, testDate, "Created date should match")
        XCTAssertEqual(fetchedFile.storagePriority, StoragePriority.permanent.rawValue, "Storage priority raw value should match")
        
        // Verify computed properties
        XCTAssertEqual(fetchedFile.id, testId, "Computed id should match")
        XCTAssertEqual(fetchedFile.mirrorId, testMirrorId, "Computed mirrorId should match")
        XCTAssertEqual(fetchedFile.fileURL.absoluteString, testURL.absoluteString, "Computed fileURL should match")
        XCTAssertEqual(fetchedFile.createdAt, testDate, "Computed createdAt should match")
        XCTAssertEqual(fetchedFile.storage, .permanent, "Computed storage should match")
    }
    
    /// Test batch operations with primary keys
    func testBatchOperationsWithPrimaryKeys() throws {
        try setupRealm()
        
        // Create a batch of files
        let batchSize = 100
        var testFiles: [CachedLocalFile] = []
        
        for i in 0..<batchSize {
            let cachedFile = CachedLocalFile()
            cachedFile.id = "batch-file-\(i)"
            cachedFile.mirrorId = "batch-mirror-\(i)"
            cachedFile.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(i).jpg")
            cachedFile.storage = i % 2 == 0 ? .cached : .permanent
            testFiles.append(cachedFile)
        }
        
        // Insert all at once
        try realm.write {
            realm.add(testFiles, update: .modified)
        }
        
        // Verify all can be fetched by primary key
        for i in 0..<batchSize {
            let fetchedFile = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: "batch-file-\(i)")
            XCTAssertNotNil(fetchedFile, "Should be able to fetch batch file \(i)")
            XCTAssertEqual(fetchedFile?.mirrorId, "batch-mirror-\(i)", "Mirror ID should match for batch file \(i)")
        }
        
        // Test fetching a subset using primary keys
        let keysToFetch = ["batch-file-10", "batch-file-25", "batch-file-50", "batch-file-75"]
        for key in keysToFetch {
            let fetchedFile = realm.object(ofType: CachedLocalFile.self, forPrimaryKey: key)
            XCTAssertNotNil(fetchedFile, "Should be able to fetch specific file: \(key)")
        }
        
        // Verify total count
        let allFiles = realm.objects(CachedLocalFile.self)
        XCTAssertEqual(allFiles.count, batchSize, "Should have all batch files in Realm")
    }
}