import Foundation
import AhaKeyConfigShared

// A maintainer command, deliberately separate from the user App/Agent bundle.
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 4, let minimum = Int(args[3]), minimum > 0 else {
    FileHandle.standardError.write(Data("Usage: ahakey-release-check MANIFEST.json ROOT TRUST-KEYS.json MINIMUM-CATALOG-REVISION\n".utf8))
    exit(2)
}
do {
    let manifestURL = URL(fileURLWithPath: args[0]), trustURL = URL(fileURLWithPath: args[2])
    guard let manifestSize = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, manifestSize <= 1_048_576,
          let trustSize = try trustURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, trustSize <= 65_536 else {
        throw FirmwareReleaseComposition.Failure.malformed
    }
    let manifest = try FirmwareReleaseComposition.decode(Data(contentsOf: manifestURL))
    let keys = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: trustURL))
    let report = try manifest.verify(root: URL(fileURLWithPath: args[1], isDirectory: true), publicKeys: keys, minimumCatalogRevision: minimum)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report)); FileHandle.standardOutput.write(Data([10]))
} catch {
    let data = (try? JSONSerialization.data(withJSONObject: ["error": String(describing: error)], options: [.sortedKeys])) ?? Data()
    FileHandle.standardError.write(data); FileHandle.standardError.write(Data([10]))
    exit(1)
}
