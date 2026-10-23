import AppKit

enum AppResources {
    static let Icon: NSImage? = {
        if let URL = Foundation.Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let Image = NSImage(contentsOf: URL) {
            return Image
        }
        guard let URL = Bundle.url(forResource: "AppIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: URL)
    }()

    static let Bundle: Foundation.Bundle = {
        if let URL = Foundation.Bundle.main.resourceURL?.appendingPathComponent("AscendaraMac_Ascendara.bundle"),
           let Packaged = Foundation.Bundle(url: URL) {
            return Packaged
        }
        return Foundation.Bundle.module
    }()
}
