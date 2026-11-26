import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift create_dmg_applications_alias.swift <mounted-volume>\n", stderr)
    exit(2)
}

let volume = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
let alias = volume.appendingPathComponent("Applications")

// Use Finder's native folder bookmark. Its absolute path provides a fallback
// on Macs whose startup volume has a different identity.
let bookmark = try applications.bookmarkData(options: .suitableForBookmarkFile,
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
try URL.writeBookmarkData(bookmark, to: alias)

let target = try URL(resolvingAliasFileAt: alias, options: [.withoutUI, .withoutMounting])
guard target.resolvingSymlinksInPath().path == applications.resolvingSymlinksInPath().path,
      NSWorkspace.shared.setIcon(NSWorkspace.shared.icon(forFile: applications.path),
                                 forFile: alias.path, options: []) else {
    fputs("failed to verify or set the Applications alias icon\n", stderr)
    exit(1)
}
