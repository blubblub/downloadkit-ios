//
//  Logging.swift
//
//  Created by Jure Lajlar on 05/03/2021.
//

import Foundation
import os.log

public let logDK = OSLog(subsystem: "org.blubblub.downloadkit", category: "DownloadKit")

extension OSLog {
    func info(_ message: StaticString, _ args: Any...) {
        let varArgs = args.map { $0 as! CVarArg }
        print("\(varArgs)")
        
        
        os_log(message, log: self, type: .info, varArgs)
    }
    
    func debug(_ message: StaticString, _ args: Any...) {
        let varArgs = args.map { $0 as! CVarArg }
        
        os_log(message, log: self, type: .debug, varArgs)
    }
    
    func error(_ message: StaticString, _ args: Any...) {
        let varArgs = args.map { $0 as! CVarArg }
        
        os_log(message, log: self, type: .error, varArgs)
    }
    
    func fault(_ message: StaticString, _ args: Any...) {
        let varArgs = args.map { $0 as! CVarArg }
        
        os_log(message, log: self, type: .fault, varArgs)
    }
}
