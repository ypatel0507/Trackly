//
//  Item.swift
//  Trackly
//
//  Created by Yash Patel on 2026-08-20.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
