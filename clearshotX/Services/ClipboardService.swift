//
//  ClipboardService.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit

final class ClipboardService {
    @discardableResult
    func copy(_ image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }
}
