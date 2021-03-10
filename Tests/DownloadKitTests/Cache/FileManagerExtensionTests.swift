
import XCTest
@testable import DownloadKit

class FileManagerExtensionTests: XCTestCase {
    
    let fileManager = FileManager.default
    
    override func setUpWithError() throws {
    
    }

    override func tearDownWithError() throws {
    
    }
    
    func testAddingCopyString() {
        XCTAssertEqual("copy-1.test", fileManager.addCopyString(to: "test"))
    }
    
    func testIncrementingCopyCount() {
        XCTAssertEqual("copy-2.image.jpg", fileManager.addCopyString(to: "copy-1.image.jpg"))
        XCTAssertEqual("copy-21.image.jpg", fileManager.addCopyString(to: "copy-20.image.jpg"))
    }
    
    func testUsingDifferentPrefix() {
        XCTAssertEqual("c1.image.jpg", fileManager.addCopyString(to: "image.jpg", with: "c"))
    }
}
