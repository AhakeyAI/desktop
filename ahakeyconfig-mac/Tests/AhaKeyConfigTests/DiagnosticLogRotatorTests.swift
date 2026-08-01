import XCTest

@testable import AhaKeyConfig

final class DiagnosticLogRotatorTests: XCTestCase {
    private var directory: URL!
    private var logURL: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DiagnosticLogRotatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("native-speech.log")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
    }

    private var existingFileNames: Set<String> {
        let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        return Set(names ?? [])
    }

    func testDoesNothingBelowLimit() throws {
        try write("small", to: logURL)
        DiagnosticLogRotator.rotateIfNeeded(at: logURL, maxBytes: 1024)
        XCTAssertEqual(existingFileNames, ["native-speech.log"])
    }

    func testDoesNothingWhenFileMissing() {
        DiagnosticLogRotator.rotateIfNeeded(at: logURL, maxBytes: 1)
        XCTAssertTrue(existingFileNames.isEmpty)
    }

    func testRotatesCurrentFileAside() throws {
        try write("0123456789", to: logURL)
        DiagnosticLogRotator.rotateIfNeeded(at: logURL, maxBytes: 10)

        // 轮转后当前文件不复存在，由调用方新建；内容保留在 .1
        XCTAssertEqual(existingFileNames, ["native-speech.log.1"])
        XCTAssertEqual(try String(contentsOf: DiagnosticLogRotator.rotatedURL(for: logURL, index: 1)), "0123456789")
    }

    func testKeepsAtMostFiveFilesAndDropsOldest() throws {
        // 连续轮转 8 次，每次的内容可区分，用来确认丢掉的是最老的那份
        for generation in 0 ..< 8 {
            try write("generation-\(generation)", to: logURL)
            DiagnosticLogRotator.rotateIfNeeded(at: logURL, maxBytes: 1)
        }

        // 保留数含当前正在写的一份；此刻当前那份刚被挪走，所以磁盘上是 4 份历史
        XCTAssertEqual(existingFileNames, [
            "native-speech.log.1",
            "native-speech.log.2",
            "native-speech.log.3",
            "native-speech.log.4",
        ])

        // .1 最新、.4 最老，generation-3 及更早的已被丢弃
        for (index, generation) in zip(1 ... 4, [7, 6, 5, 4]) {
            let url = DiagnosticLogRotator.rotatedURL(for: logURL, index: index)
            XCTAssertEqual(try String(contentsOf: url), "generation-\(generation)")
        }
    }

    func testHonoursSmallerFileBudget() throws {
        for generation in 0 ..< 5 {
            try write("generation-\(generation)", to: logURL)
            DiagnosticLogRotator.rotateIfNeeded(at: logURL, maxBytes: 1, maxFiles: 2)
        }
        XCTAssertEqual(existingFileNames, ["native-speech.log.1"])
        XCTAssertEqual(try String(contentsOf: DiagnosticLogRotator.rotatedURL(for: logURL, index: 1)), "generation-4")
    }

    func testSingleFileBudgetDiscardsInsteadOfKeepingHistory() throws {
        try write("0123456789", to: logURL)
        DiagnosticLogRotator.rotateIfNeeded(at: logURL, maxBytes: 1, maxFiles: 1)
        XCTAssertTrue(existingFileNames.isEmpty)
    }
}
