//
//  CloudKitDownloadProcessorTests.swift
//  BlubBlubCore_Tests
//
//  Created by Dal Rupnik on 2/5/21.
//  Copyright © 2021 Blub Blub. All rights reserved.
//

import XCTest
import DownloadKit
import CloudKit

extension CloudKitDownloadItem {
    static func sampleItem() -> CloudKitDownloadItem {
        let item = CloudKitDownloadItem(identifier: "org.blubblub.asset.f9a92dad-1f7b-45a9-94fd663fcfb9",
                                        url: URL(string:"cloudkit://iCloud.org.blubblub.app.titan/FileMirrorAsset/9d6c3ad8-4c73-44c9-9ad0-e48265788344")!)
        
        item.totalSize = 120083
        
        return item
    }
}


// To initialize CKContainer, we need a host app with CloudKit entitlement.
// Otherwise, we get an exception:
// Terminating app due to uncaught exception 'CKException', reason: 'The application is missing required entitlement com.apple.developer.icloud-services'

//class CloudKitDownloadProcessorTests: XCTestCase {
//
//    let database = CKContainer(identifier: "iCloud.org.blubblub.app.titan").publicCloudDatabase
//
//    var processor: CloudKitDownloadProcessor!
//    var delegate: DownloadProcessorDelegateMock!
//
//    override func setUpWithError() throws {
//        processor = CloudKitDownloadProcessor(database: database)
//
//        delegate = DownloadProcessorDelegateMock()
//        processor.delegate = delegate
//    }
//
//    override func tearDownWithError() throws {
//        processor = nil
//        delegate = nil
//    }
//
//    func testCanProcess() throws {
//        let item = CloudKitDownloadItem.sampleItem()
//
//        XCTAssert(processor.canProcess(item: item), "Processor should be able to process item")
//    }
//
//    func testCanProcessIsInactive() throws {
//        let item = CloudKitDownloadItem.sampleItem()
//
//        processor.isActive = false
//
//        XCTAssertFalse(processor.canProcess(item: item), "Processor should not be able to process item")
//    }
//
//    func testDownload() throws {
//        let item = CloudKitDownloadItem.sampleItem()
//
//        let expectation = XCTestExpectation(description: "Download should complete in few seconds.")
//
//        delegate.errorCallback = { error in
//            XCTAssert(false, "There should be no error")
//        }
//
//        delegate.finishTransferCallback = { url in
//            XCTAssertFalse(url.absoluteString.isEmpty, "Download URL should not be empty")
//
//            // Attempt to open URL
//
//            guard (try? Data(contentsOf: url)) != nil else {
//                XCTAssert(false, "There should be no error")
//                return
//            }
//            expectation.fulfill()
//        }
//
//        processor.process(item)
//
//        wait(for: [expectation], timeout: 5.0)
//    }
//
//    func testWrongRecordIDError() throws {
//        let item = CloudKitDownloadItem.sampleItem()
//        item.url = URL(string: "cloudkit://iCloud.org.blubblub.app.titan/FileMirrorAsset/1231231")!
//
//
//        let expectation = XCTestExpectation(description: "Download should fail in few seconds.")
//
//        delegate.errorCallback = { error in
//            expectation.fulfill()
//        }
//
//        processor.process(item)
//
//        wait(for: [expectation], timeout: 5.0)
//    }
//
//    func testBadURLError() throws {
//        let item = CloudKitDownloadItem.sampleItem()
//        item.url = URL(string: "cloudkit://iCloud.org.blubblub.app.titan/1231231")!
//
//
//        let expectation = XCTestExpectation(description: "Download should fail immediately, because URL is bad.")
//
//        delegate.errorCallback = { error in
//            expectation.fulfill()
//        }
//
//        processor.process(item)
//
//        wait(for: [expectation], timeout: 5.0)
//    }
//
//    func testStartTransfer() throws {
//        let item = CloudKitDownloadItem.sampleItem()
//
//        let expectation = XCTestExpectation(description: "Download should start in few seconds.")
//        delegate.startTransferCallback = {
//            expectation.fulfill()
//        }
//        processor.process(item)
//
//        wait(for: [expectation], timeout: 5.0)
//    }
//
//    func testCloudProgress() throws {
//        let item = CloudKitDownloadItem.sampleItem()
//
//        guard let progress = item.progress else {
//            fatalError("No progress, no fun.")
//        }
//
//        let expectation = XCTestExpectation(description: "Download should complete in few seconds.")
//        processor.process(item)
//
//        delegate.finishCallback = {
//            if progress.fractionCompleted > 0.0 {
//                expectation.fulfill()
//            }
//        }
//
//        wait(for: [expectation], timeout: 10.0)
//    }
//}
