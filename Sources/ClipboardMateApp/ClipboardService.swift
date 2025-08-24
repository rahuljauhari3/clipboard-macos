import AppKit

enum ClipboardService {
    static func copyToClipboard(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.contentType {
        case .text:
            if let text = item.text { pb.setString(text, forType: .string) }
        case .image:
            if let data = item.imagePNG, let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        }
        _ = pb.changeCount
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = self.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return data
    }
}

