//
//  Item.swift
//  reflect
//
//  Created by MJ Kang on 1/31/26.
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
