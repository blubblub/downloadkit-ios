//
//  Logger+DownloadKit.swift
//  DownloadKit
//
//  Created by Assistant on 6/30/25.
//

import Foundation
import os.log

extension Logger {
    static let logResourceManager = Logger(subsystem: "org.blubblub.downloadkit", category: "ResourceManager")
    static let logDownloadQueue = Logger(subsystem: "org.blubblub.downloadkit", category: "DownloadQueue")
    static let logWebDownloadProcessor = Logger(subsystem: "org.blubblub.downloadkit", category: "WebDownloadProcessor")
    static let logWebDownload = Logger(subsystem: "org.blubblub.downloadkit", category: "WebDownload")
    static let logWeightedMirrorPolicy = Logger(subsystem: "org.blubblub.downloadkit", category: "WeightedMirrorPolicy")
}
