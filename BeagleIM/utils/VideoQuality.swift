//
// VideoQuality.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import Foundation
import AVKit

enum VideoQuality: String {
    case original
    case high
    case medium
    case low
    
    static var current: VideoQuality {
        return Settings.videoQuality;
    }
    
    var label: String {
        switch self {
        case .original:
            return NSLocalizedString("Original", comment: "video quality")
        case .high:
            return NSLocalizedString("High", comment: "video quality")
        case .medium:
            return NSLocalizedString("Medium", comment: "video quality")
        case .low:
            return NSLocalizedString("Low", comment: "video quality")
        }
    }
    
    var preset: String {
        switch self {
        case .original:
            return AVAssetExportPresetPassthrough;
        case .high:
            return AVAssetExportPresetHighestQuality;
        case .medium:
            return AVAssetExportPresetMediumQuality;
        case .low:
            return AVAssetExportPresetLowQuality;
        }
    }
}
