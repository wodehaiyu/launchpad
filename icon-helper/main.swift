import AppKit
import Foundation

let workspace = NSWorkspace.shared
let localizedNamesOnly = CommandLine.arguments.contains("--localized-names")
let localizedNamePreferences = Locale.preferredLanguages.flatMap { language -> [String] in

    var candidates = [
        language,
        language.replacingOccurrences(of: "-", with: "_")
    ]

    let components = language.split(separator: "-").map(String.init)

    if components.first == "zh" {

        if components.contains("Hant") || components.contains("TW") || components.contains("HK") {
            candidates.append(contentsOf: ["zh-Hant", "zh_TW", "zh-TW", "zh-Hant-TW"])
        } else {
            candidates.append(contentsOf: ["zh-Hans", "zh_CN", "zh-CN", "zh-Hans-CN"])
        }

    }

    if let languageCode = components.first {
        candidates.append(languageCode)
    }

    return candidates
}


func localizedDisplayName(for path: String) -> String {

    let bundle = Bundle(
        url: URL(fileURLWithPath: path)
    )

    var localizedInfo: [String: Any] = [:]

    if let bundle,
       let localization = Bundle.preferredLocalizations(
           from: bundle.localizations.filter { $0 != "Base" },
           forPreferences: localizedNamePreferences
       ).first,
       let localizationPath = bundle.path(
           forResource: localization,
           ofType: "lproj"
       ),
       let data = try? Data(
           contentsOf: URL(fileURLWithPath: localizationPath)
               .appendingPathComponent("InfoPlist.strings")
       ),
       let propertyList = try? PropertyListSerialization.propertyList(
           from: data,
           options: [],
           format: nil
       ) as? [String: Any] {

        localizedInfo = propertyList;

    }

    let bundleLocalizedInfo = bundle?.localizedInfoDictionary ?? [:]
    let info = bundle?.infoDictionary ?? [:]

    return localizedInfo["CFBundleDisplayName"] as? String
        ?? localizedInfo["CFBundleName"] as? String
        ?? bundleLocalizedInfo["CFBundleDisplayName"] as? String
        ?? bundleLocalizedInfo["CFBundleName"] as? String
        ?? info["CFBundleDisplayName"] as? String
        ?? info["CFBundleName"] as? String
        ?? FileManager.default.displayName(atPath: path)
}

while let line = readLine() {

    guard let requestData = line.data(using: .utf8),
          let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
          let path = request["path"] as? String else {
        continue
    }

    if localizedNamesOnly {

        let result: [String: String] = [
            "path": path,
            "name": localizedDisplayName(for: path)
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: result),
           let json = String(data: jsonData, encoding: .utf8) {
            print(json)
            fflush(stdout)
        }

        continue

    }

    guard let cachePath = request["cachePath"] as? String else {
        continue
    }

    let image = workspace.icon(
        forFile: path
    )

    let targetSize = max(1, min(2048, request["pixels"] as? Int ?? 256))
    var succeeded = false

    if let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: targetSize,
        pixelsHigh: targetSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) {

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        image.draw(
            in: NSRect(x: 0, y: 0, width: targetSize, height: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        if let pngData = bitmap.representation(
            using: .png,
            properties: [:]
        ) {
            do {
                try pngData.write(
                    to: URL(fileURLWithPath: cachePath),
                    options: .atomic
                )
                succeeded = true
            } catch {
                succeeded = false
            }
        }
    }

    let result: [String: Any] = [
        "path": path,
        "success": succeeded
    ]

    if let jsonData =
        try? JSONSerialization.data(
            withJSONObject: result
        ),
        let json =
        String(
            data: jsonData,
            encoding: .utf8
        ) {

        print(json)
        fflush(stdout)
    }
}