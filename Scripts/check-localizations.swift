// Checks that every string the app uses has a German translation in App/Localizable.xcstrings.
//
// Usage (after a Debug build into build/DerivedData):
//   swift Scripts/check-localizations.swift
//
// The compiler writes all `String(localized:)` keys to *.stringsdata files (SWIFT_EMIT_LOC_STRINGS).
// This script compares them with the catalog and exits with 1 when keys are missing, untranslated or stale.

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let objects = root.appendingPathComponent(
    "build/DerivedData/Build/Intermediates.noindex/gpsloader.build/Debug/gpsloader.build/Objects-normal")
let catalogURL = root.appendingPathComponent("App/Localizable.xcstrings")

var usedKeys = Set<String>()
if let enumerator = FileManager.default.enumerator(at: objects, includingPropertiesForKeys: nil) {
    for case let url as URL in enumerator where url.pathExtension == "stringsdata" {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tables = json["tables"] as? [String: [[String: Any]]] else { continue }
        for entries in tables.values {
            for entry in entries {
                if let key = entry["key"] as? String { usedKeys.insert(key) }
            }
        }
    }
}
guard !usedKeys.isEmpty else {
    print("No extracted strings found in \(objects.path). Build the Debug configuration first.")
    exit(2)
}

guard let catalogData = try? Data(contentsOf: catalogURL),
      let catalog = try? JSONSerialization.jsonObject(with: catalogData) as? [String: Any],
      let strings = catalog["strings"] as? [String: [String: Any]] else {
    print("Cannot read \(catalogURL.path)")
    exit(2)
}

let missing = usedKeys.subtracting(strings.keys).sorted()
let stale = Set(strings.keys).subtracting(usedKeys).sorted()
let untranslated = strings.filter { _, value in
    let localizations = value["localizations"] as? [String: Any]
    let german = (localizations?["de"] as? [String: Any])?["stringUnit"] as? [String: Any]
    return german?["state"] as? String != "translated" || (german?["value"] as? String ?? "").isEmpty
}.keys.sorted()

for key in missing { print("missing in catalog: \(key)") }
for key in untranslated { print("no German translation: \(key)") }
for key in stale { print("stale (no longer used): \(key)") }
print("\(usedKeys.count) keys used, \(strings.count) in catalog, "
    + "\(missing.count) missing, \(untranslated.count) untranslated, \(stale.count) stale")
exit(missing.isEmpty && untranslated.isEmpty && stale.isEmpty ? 0 : 1)
