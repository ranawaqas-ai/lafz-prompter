//
//  FontDesignExtension.swift
//  notch-prompter
//
//  Created by Jakub Pomykała on 29/03/2026.
//

import SwiftUI

extension Font.Design {
    var displayLocalizedName: LocalizedStringResource {
        switch self {
        case .default:    return "Default"
        case .serif:      return "Serif"
        case .rounded:    return "Rounded"
        case .monospaced: return "Monospaced"
        @unknown default: return "Default"
        }
    }
    
    var previewCharacter: String {
        return "Ag"
    }

    var previewFontView: Font {
        .system(size: 16, design: self)
    }
}
