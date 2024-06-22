//
//  Event+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2023.
//
//

import Foundation
import CoreData
import UIKit
import Combine

public class Event: NSManagedObject, Identifiable {
    
    var zapState: ZapState?
    var parentEvents: [Event] = []
    
    var isScreenshot: Bool = false // Must use Text
    var previewImages: [PostedImageMeta] = []
    var previewVideos: [PostedVideoMeta] = []
    var cancellationId: UUID?
    
    public override func validateValue(_ value: AutoreleasingUnsafeMutablePointer<AnyObject?>, forKey key: String) throws {
        
        // Daily maintenance deletes old events, but these events don't have proper inverse relationship (not needed)
        // But core data seems to cry about it, and crashes when it tries to access a relation that has been deleted
        // Ignoring validation seems to fix it, hopefully it doesn't break other things...
        let skipValidationFor = ["replyTo","reactionTo", "replyToRoot", "firstQuote", "zapFromRequest", "zappedEvent"]
        if skipValidationFor.contains(key) {
            // Ignore validation for the relationship
            return
        }
        
        try super.validateValue(value, forKey: key)
    }
    
    lazy var fastTags: [(String, String, String?, String?)] = {
        guard let tagsSerialized = tagsSerialized else { return [] }
        guard let jsonData = tagsSerialized.data(using: .utf8) else { return [] }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String]] else {
            return []
        }
        
        return jsonArray
        //            .filter { $0.count >= 2 }
            .map { ($0[safe: 0] ?? "WTF", $0[safe: 1] ?? "WTF", $0[safe: 2], $0[safe: 3]) }
    }()
}

