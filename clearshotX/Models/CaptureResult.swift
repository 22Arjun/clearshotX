//
//  CaptureResult.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import Foundation

struct CaptureResult {
    let image: NSImage
    let fileURL: URL
    let dragFileURL: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let screenFrame: CGRect
}
