//
//  Item.swift
//  Oneka
//
//  Created by Jachin Rupe on 3/20/26.
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
