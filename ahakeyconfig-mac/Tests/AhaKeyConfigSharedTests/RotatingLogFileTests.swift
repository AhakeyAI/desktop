import XCTest
@testable import AhaKeyConfigShared

final class RotatingLogFileTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RotatingLogFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeLogFile(maxFileSize: Int = 64, maxArchiveCount: Int = 2) -> RotatingLogFile {
        RotatingLogFile(
            fileURL: tempDirectory.appendingPathComponent("ble-verbose.log"),
            maxFileSize: maxFileSize,
            maxArchiveCount: maxArchiveCount
        )
    }

    private func contents(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 未超限：顺序追加，不发生轮转，也不产生归档文件。
    func testAppendBelowLimitDoesNotRotate() throws {
        let log = makeLogFile(maxFileSize: 1024)
        XCTAssertFalse(try log.append("line-1\n"))
        XCTAssertFalse(try log.append("line-2\n"))
        XCTAssertEqual(contents(log.fileURL), "line-1\nline-2\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.archiveURL(index: 1).path))
    }

    /// 超过上限触发轮转：当前文件变成 .1，新行写入新的当前文件。
    func testExceedingLimitRotatesCurrentFileToArchive1() throws {
        let log = makeLogFile(maxFileSize: 16)
        XCTAssertFalse(try log.append("1234567890\n")) // 11B
        XCTAssertTrue(try log.append("abcdef\n"))       // 11 + 7 = 18 > 16 → 轮转
        XCTAssertEqual(contents(log.fileURL), "abcdef\n")
        XCTAssertEqual(contents(log.archiveURL(index: 1)), "1234567890\n")
    }

    /// 持续写入：最多保留当前 + .1 + .2 共 3 份，最旧的内容被删除。
    func testKeepsAtMostThreeFilesAndDropsOldest() throws {
        let log = makeLogFile(maxFileSize: 8)
        // 每行 8B（"batch-N\n"），每追加一行就触发一次轮转
        for batch in 1 ... 5 {
            try log.append("batch-\(batch)\n")
        }
        XCTAssertEqual(contents(log.fileURL), "batch-5\n")
        XCTAssertEqual(contents(log.archiveURL(index: 1)), "batch-4\n")
        XCTAssertEqual(contents(log.archiveURL(index: 2)), "batch-3\n")
        // 不会产生第 4 份；batch-1 / batch-2 已被删除
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.archiveURL(index: 3).path))
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(files.count, 3)
    }

    /// 归档命名：ble-verbose.log.1 / ble-verbose.log.2。
    func testArchiveNaming() {
        let log = makeLogFile()
        XCTAssertEqual(log.archiveURL(index: 1).lastPathComponent, "ble-verbose.log.1")
        XCTAssertEqual(log.archiveURL(index: 2).lastPathComponent, "ble-verbose.log.2")
    }

    /// 默认参数：单文件 5MB、保留 2 份归档（共 3 份）。
    func testDefaultLimits() {
        let log = RotatingLogFile(fileURL: tempDirectory.appendingPathComponent("x.log"))
        XCTAssertEqual(log.maxFileSize, 5 * 1024 * 1024)
        XCTAssertEqual(log.maxArchiveCount, 2)
    }
}
