//
// Markdown.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import AppKit

class Markdown {
    
    static func applyStyling(attributedString msg: NSMutableAttributedString) {
        let stylingColor = NSColor(calibratedWhite: 0.5, alpha: 1.0);
        
        let message = msg.string;
        
        var boldStart: String.Index? = nil;
        var italicStart: String.Index? = nil;
        var underlineStart: String.Index? = nil;
        var codeStart: String.Index? = nil;
        var idx = message.startIndex;
        
        var canStart = true;
        
        while idx != message.endIndex {
            let c = message[idx];
            switch c {
            case "*":
                let nidx = message.index(after: idx);
                if nidx != message.endIndex, message[nidx] == "*" {
                    if boldStart == nil {
                        if canStart {
                            boldStart = idx;
                        }
                    } else {
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(boldStart!.encodedOffset...message.index(after: boldStart!).encodedOffset));
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(idx.encodedOffset...nidx.encodedOffset));
                        
                        msg.applyFontTraits(.boldFontMask, range: NSRange(boldStart!.encodedOffset...nidx.encodedOffset));
                        boldStart = nil;
                    }
                    canStart = true;
                    idx = nidx;
                } else {
                    if italicStart == nil {
                        if canStart {
                            italicStart = idx;
                        }
                    } else {
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(italicStart!.encodedOffset...italicStart!.encodedOffset));
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(idx.encodedOffset...idx.encodedOffset));
                        
                        msg.applyFontTraits(.italicFontMask, range: NSRange(italicStart!.encodedOffset...idx.encodedOffset));
                        italicStart = nil;
                    }
                    canStart = true;
                }
            case "_":
                if underlineStart == nil {
                    if canStart {
                        underlineStart = idx;
                    }
                } else {
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(underlineStart!.encodedOffset...underlineStart!.encodedOffset));
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(idx.encodedOffset...idx.encodedOffset));
                    
                    msg.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(underlineStart!.encodedOffset...idx.encodedOffset));
                    underlineStart = nil;
                }
                canStart = true;
            case "`":
                if codeStart == nil {
                    if canStart {
                        codeStart = idx;
                    }
                } else {
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(codeStart!.encodedOffset...codeStart!.encodedOffset));
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(idx.encodedOffset...idx.encodedOffset));

                    msg.applyFontTraits([.fixedPitchFontMask, .unboldFontMask, .unitalicFontMask], range: NSRange(codeStart!.encodedOffset...idx.encodedOffset));
                    
                    if message.distance(from: codeStart!, to: idx) > 1 {
                        let clearRange = NSRange(message.index(after: codeStart!).encodedOffset...message.index(before: idx).encodedOffset);
                        msg.removeAttribute(.foregroundColor, range: clearRange);
                        msg.removeAttribute(.underlineStyle, range: clearRange);
                        msg.addAttribute(.foregroundColor, value: NSColor.textColor, range: clearRange);
                    }
                    codeStart = nil;
                }
                canStart = true;
            case "\n", " ":
                canStart = true;
            default:
                canStart = false;
                break;
            }
            idx = message.index(after: idx);
        }
    }
    
}