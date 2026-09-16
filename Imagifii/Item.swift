//
//  Item.swift
//  Imagifii
//
//  Created by Junaid Rajah on 2026/09/16.
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
