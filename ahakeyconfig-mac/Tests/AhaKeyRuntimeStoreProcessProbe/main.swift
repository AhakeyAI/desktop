import Darwin
import Foundation
import AhaKeyConfigShared

@main
enum AhaKeyRuntimeStoreProcessProbe {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            writeError("usage: AhaKeyRuntimeStoreProcessProbe flock <path> | mutate <root>")
            Darwin.exit(2)
        }
        switch command {
        case "flock":
            guard args.count >= 2 else {
                writeError("usage: AhaKeyRuntimeStoreProcessProbe flock <path>")
                Darwin.exit(2)
            }
            flockProbe(path: args[1])
        case "mutate":
            guard args.count >= 2 else {
                writeError("usage: AhaKeyRuntimeStoreProcessProbe mutate <root>")
                Darwin.exit(2)
            }
            mutateProbe(rootPath: args[1])
        default:
            writeError("unknown command \(command)")
            Darwin.exit(2)
        }
    }

    private static func flockProbe(path: String) {
        let fd = open(path, O_RDWR)
        guard fd >= 0 else {
            writeLine("OPEN_FAILED")
            Darwin.exit(1)
        }
        defer { Darwin.close(fd) }
        let rc = flock(fd, LOCK_EX | LOCK_NB)
        if rc == 0 {
            _ = flock(fd, LOCK_UN)
            writeLine("GOT_LOCK")
            Darwin.exit(0)
        }
        writeLine("BLOCKED")
        Darwin.exit(0)
    }

    private static func mutateProbe(rootPath: String) {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard let store = openStore(root: root) else {
            Darwin.exit(1)
        }
        writeLine("READY")
        guard let command = readLine(), command == "MUTATE" else {
            writeLine("BAD_COMMAND")
            Darwin.exit(3)
        }
        Darwin.exit(acceptPackage(store: store))
    }

    private static func openStore(root: URL) -> AhaKeyRuntimePersistentStore? {
        let box = ResultBox<AhaKeyRuntimePersistentStore>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let store = try AhaKeyRuntimePersistentStore(rootDirectory: root)
                _ = try await store.health()
                box.set(.success(store))
            } catch {
                box.set(.failure(error))
                writeError("ERROR \(error)")
            }
            done.signal()
        }
        if done.wait(timeout: .now() + 15) == .timedOut {
            writeLine("READY_TIMEOUT")
            return nil
        }
        return try? box.get().get()
    }

    private static func acceptPackage(store: AhaKeyRuntimePersistentStore) -> Int32 {
        let box = ResultBox<Int32>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let package = try makePageScopedPackage(statusLine: "child-\(UUID().uuidString)")
                _ = try await store.accept(package, resourceFiles: [:])
                await store.close()
                writeLine("GOT_LOCK")
                box.set(.success(0))
            } catch {
                writeError("ERROR \(error)")
                box.set(.success(1))
            }
            done.signal()
        }
        done.wait()
        return (try? box.get().get()) ?? 1
    }

    private static func makePageScopedPackage(statusLine: String) throws -> AhaKeyConfigurationPackage {
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [field: .text(statusLine)],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            statusLine: statusLine
        )
        return try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            baseRevision: .init(7),
            baseObjectFingerprint: try AhaKeyRuntimeObjectFingerprint.hashing(Data(statusLine.utf8)),
            verifiedResources: [],
            operationID: .init()
        )
    }

    private static func writeLine(_ text: String) {
        FileHandle.standardOutput.write(Data("\(text)\n".utf8))
        fflush(stdout)
    }

    private static func writeError(_ text: String) {
        FileHandle.standardError.write(Data("\(text)\n".utf8))
        fflush(stderr)
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<T, Error>?

    func set(_ value: Result<T, Error>) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() throws -> Result<T, Error> {
        lock.lock()
        defer { lock.unlock() }
        guard let value else {
            throw POSIXError(.EINVAL)
        }
        return value
    }
}
