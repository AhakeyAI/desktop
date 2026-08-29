import Foundation

public enum AhaKeyReleasePathViolation: Equatable, Error, Sendable {
    case notAbsolute(String)
    case emptyPath
    case sourceEqualsDestination
    case backupAlreadyExists(String)
    case stagingAlreadyExists(String)
    case pathEscapesAllowedRoot(String)
    case pathContainsSymlink(String)
    case applicationsOutputForbidden(String)
    case missingCandidate
}

/// Canonical / allowed-root / symlink / `/Applications` 输出防护。
/// 安装器在任何删除、复制、rename 之前调用；打包脚本走同一套规则的 Python 镜像。
public enum AhaKeyReleasePathGuard {
    public static func parentDirectory(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    public static func standardizedAbsolute(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AhaKeyReleasePathViolation.emptyPath }
        guard trimmed.hasPrefix("/") else { throw AhaKeyReleasePathViolation.notAbsolute(trimmed) }
        let standardized = (trimmed as NSString).standardizingPath
        guard standardized.hasPrefix("/") else { throw AhaKeyReleasePathViolation.notAbsolute(standardized) }
        return standardized
    }

    public static func isUnderApplications(_ path: String) throws -> Bool {
        let canonical = try standardizedAbsolute(path)
        return canonical == "/Applications" || canonical.hasPrefix("/Applications/")
    }

    public static func refuseApplicationsOutput(_ path: String) throws {
        if try isUnderApplications(path) {
            throw AhaKeyReleasePathViolation.applicationsOutputForbidden(try standardizedAbsolute(path))
        }
    }

    public static func requireAllowed(
        _ path: String,
        roots: [String]
    ) throws -> String {
        let canonical = try standardizedAbsolute(path)
        let allowed = try roots.map(standardizedAbsolute)
        let ok = allowed.contains { root in
            canonical == root || canonical.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
        guard ok else {
            throw AhaKeyReleasePathViolation.pathEscapesAllowedRoot(canonical)
        }
        return canonical
    }

    public static func rejectSymlinkEscape(
        _ path: String,
        roots: [String],
        resolve: (String) -> String?,
        isSymlink: (String) -> Bool
    ) throws {
        try rejectSymlinkInsideAllowedRoots(path, roots: roots, resolve: resolve, isSymlink: isSymlink)
    }

    /// 只检查 allowed root 之下的符号链接。`/var` → `/private/var` 这类系统前缀不视为穿透。
    public static func rejectSymlinkInsideAllowedRoots(
        _ path: String,
        roots: [String],
        resolve: (String) -> String?,
        isSymlink: (String) -> Bool
    ) throws {
        let canonical = try standardizedAbsolute(path)
        for root in try roots.map(standardizedAbsolute) {
            if canonical == root || canonical.hasPrefix(root.hasSuffix("/") ? root : root + "/") {
                if isSymlink(root) {
                    throw AhaKeyReleasePathViolation.pathContainsSymlink(root)
                }
                var prefix = root
                let remainder: [String]
                if canonical == root {
                    remainder = []
                } else {
                    let extra = String(canonical.dropFirst(root.count))
                    remainder = extra.split(separator: "/").map(String.init).filter { !$0.isEmpty }
                }
                for part in remainder {
                    prefix = (prefix as NSString).appendingPathComponent(part)
                    if isSymlink(prefix) {
                        if let resolved = resolve(prefix) {
                            let resolvedStd = try standardizedAbsolute(resolved)
                            do {
                                _ = try requireAllowed(resolvedStd, roots: [root])
                            } catch {
                                throw AhaKeyReleasePathViolation.pathContainsSymlink(prefix)
                            }
                        } else {
                            throw AhaKeyReleasePathViolation.pathContainsSymlink(prefix)
                        }
                    }
                }
            }
        }
    }

    public static func validateReplacement(
        source: String,
        destination: String,
        backup: String,
        staging: String,
        allowedRoots: [String],
        candidateRoots: [String],
        permitsApplicationsDestination: Bool,
        itemExists: (String) -> Bool,
        resolve: (String) -> String?,
        isSymlink: (String) -> Bool
    ) throws {
        let src = try standardizedAbsolute(source)
        let dest = try standardizedAbsolute(destination)
        let bak = try standardizedAbsolute(backup)
        let stage = try standardizedAbsolute(staging)
        if src == dest || src == bak || dest == bak || src == stage || dest == stage {
            throw AhaKeyReleasePathViolation.sourceEqualsDestination
        }
        try validateCandidateSource(src, candidateRoots: candidateRoots, isSymlink: isSymlink)
        if !permitsApplicationsDestination {
            try refuseApplicationsOutput(dest)
            try refuseApplicationsOutput(bak)
            try refuseApplicationsOutput(stage)
        }
        for path in [dest, bak, stage] {
            _ = try requireAllowed(path, roots: allowedRoots)
            try rejectSymlinkInsideAllowedRoots(
                path,
                roots: allowedRoots,
                resolve: resolve,
                isSymlink: isSymlink
            )
        }
        if isSymlink(src) {
            throw AhaKeyReleasePathViolation.pathContainsSymlink(src)
        }
        if itemExists(bak) {
            throw AhaKeyReleasePathViolation.backupAlreadyExists(bak)
        }
        if itemExists(stage) {
            throw AhaKeyReleasePathViolation.stagingAlreadyExists(stage)
        }
    }

    public static func validateMove(
        from source: String,
        to destination: String,
        allowedRoots: [String],
        permitsApplicationsDestination: Bool,
        itemExists: (String) -> Bool,
        resolve: (String) -> String?,
        isSymlink: (String) -> Bool
    ) throws {
        let src = try standardizedAbsolute(source)
        let dest = try standardizedAbsolute(destination)
        if src == dest {
            throw AhaKeyReleasePathViolation.sourceEqualsDestination
        }
        if !permitsApplicationsDestination {
            try refuseApplicationsOutput(src)
            try refuseApplicationsOutput(dest)
        }
        _ = try requireAllowed(src, roots: allowedRoots)
        _ = try requireAllowed(dest, roots: allowedRoots)
        try rejectSymlinkInsideAllowedRoots(src, roots: allowedRoots, resolve: resolve, isSymlink: isSymlink)
        try rejectSymlinkInsideAllowedRoots(dest, roots: allowedRoots, resolve: resolve, isSymlink: isSymlink)
        if isSymlink(src) {
            throw AhaKeyReleasePathViolation.pathContainsSymlink(src)
        }
        if isSymlink(dest) {
            throw AhaKeyReleasePathViolation.pathContainsSymlink(dest)
        }
        if itemExists(dest) {
            throw AhaKeyReleasePathViolation.backupAlreadyExists(dest)
        }
    }

    public static func validateDestructive(
        _ path: String,
        allowedRoots: [String],
        permitsApplicationsDestination: Bool,
        resolve: (String) -> String?,
        isSymlink: (String) -> Bool
    ) throws {
        let canonical = try standardizedAbsolute(path)
        if !permitsApplicationsDestination {
            try refuseApplicationsOutput(canonical)
        }
        _ = try requireAllowed(canonical, roots: allowedRoots)
        try rejectSymlinkInsideAllowedRoots(
            canonical,
            roots: allowedRoots,
            resolve: resolve,
            isSymlink: isSymlink
        )
        if isSymlink(canonical) {
            throw AhaKeyReleasePathViolation.pathContainsSymlink(canonical)
        }
    }

    /// Candidate 必须落在明确的 candidate root 下，并从该 root 起检查整条父级链。
    public static func validateCandidateSource(
        _ source: String,
        candidateRoots: [String],
        isSymlink: (String) -> Bool
    ) throws {
        let src = try standardizedAbsolute(source)
        let roots = try candidateRoots.map(standardizedAbsolute)
        guard let root = roots.first(where: { src == $0 || src.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) else {
            throw AhaKeyReleasePathViolation.pathEscapesAllowedRoot(src)
        }
        if isSymlink(root) {
            throw AhaKeyReleasePathViolation.pathContainsSymlink(root)
        }
        var prefix = root
        if src != root {
            let extra = String(src.dropFirst(root.count))
            let remainder = extra.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            for part in remainder {
                prefix = (prefix as NSString).appendingPathComponent(part)
                if isSymlink(prefix) {
                    throw AhaKeyReleasePathViolation.pathContainsSymlink(prefix)
                }
            }
        }
    }
}
