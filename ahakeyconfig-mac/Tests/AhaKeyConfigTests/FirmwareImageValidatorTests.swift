import Foundation
import XCTest
@testable import AhaKeyConfig

final class FirmwareImageValidatorTests: XCTestCase {
    func testValidIntelHEXProducesDescriptor() throws {
        let url = try temporaryHEX(contents: ":0100000001FE\n:00000001FF\n")
        defer { try? FileManager.default.removeItem(at: url) }

        let descriptor = try FirmwareImageValidator.validate(url: url)

        XCTAssertEqual(descriptor.fileName, url.lastPathComponent)
        XCTAssertEqual(descriptor.byteCount, 26)
        XCTAssertEqual(descriptor.sha256.count, 64)
        XCTAssertFalse(descriptor.isBundled)
    }

    func testBundledFirmwarePassesIntelHEXAndHashValidation() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = packageRoot
            .appendingPathComponent("Resources/FirmwareFlasher/firmware")
            .appendingPathComponent(AhaKeyFirmwareFlasherResources.bundledFirmwareFileName)

        let descriptor = try FirmwareImageValidator.validate(url: url, isBundled: true)

        XCTAssertEqual(descriptor.sha256, AhaKeyFirmwareFlasherResources.bundledFirmwareSHA256)
        XCTAssertTrue(descriptor.isBundled)
    }

    func testInvalidIntelHEXChecksumIsRejected() throws {
        let url = try temporaryHEX(contents: ":0100000001FF\n:00000001FF\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try FirmwareImageValidator.validate(url: url)) { error in
            XCTAssertEqual(error as? FirmwareImageValidationError, .invalidChecksum(line: 1))
        }
    }

    func testIntelHEXWithoutDataIsRejected() throws {
        let url = try temporaryHEX(contents: ":00000001FF\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try FirmwareImageValidator.validate(url: url)) { error in
            XCTAssertEqual(error as? FirmwareImageValidationError, .missingDataRecord)
        }
    }

    func testIntelHEXWithoutEOFIsRejected() throws {
        let url = try temporaryHEX(contents: ":0100000001FE\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try FirmwareImageValidator.validate(url: url)) { error in
            XCTAssertEqual(error as? FirmwareImageValidationError, .missingEOF)
        }
    }

    func testIntelHEXOutsideCH582CodeFlashIsRejected() throws {
        let url = try temporaryHEX(contents: ":020000040007F3\n:0100000001FE\n:00000001FF\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try FirmwareImageValidator.validate(url: url)) { error in
            XCTAssertEqual(
                error as? FirmwareImageValidationError,
                .addressOutOfRange(line: 2, maximumExclusive: 0x70000)
            )
        }
    }

    func testMalformedExtendedAddressRecordIsRejected() throws {
        let url = try temporaryHEX(contents: ":0100000400FB\n:00000001FF\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try FirmwareImageValidator.validate(url: url)) { error in
            XCTAssertEqual(error as? FirmwareImageValidationError, .malformedRecord(line: 1))
        }
    }

    func testRecordAfterEOFIsRejected() throws {
        let url = try temporaryHEX(contents: ":0100000001FE\n:00000001FF\n:0400000500000000F7\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try FirmwareImageValidator.validate(url: url)) { error in
            XCTAssertEqual(error as? FirmwareImageValidationError, .malformedRecord(line: 3))
        }
    }

    func testStagerRejectsFirmwareChangedAfterValidation() throws {
        let url = try temporaryHEX(contents: ":0100000001FE\n:00000001FF\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let descriptor = try FirmwareImageValidator.validate(url: url)

        try Data(":0100000002FD\n:00000001FF\n".utf8).write(to: url, options: .atomic)

        XCTAssertThrowsError(try FirmwareImageStager.stage(descriptor)) { error in
            XCTAssertEqual(error as? FirmwareFlasherError, .firmwareChanged)
        }
    }

    func testStagerUsesExactValidatedBytes() throws {
        let contents = ":0100000001FE\n:00000001FF\n"
        let url = try temporaryHEX(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }
        let descriptor = try FirmwareImageValidator.validate(url: url)

        let stagedURL = try FirmwareImageStager.stage(descriptor)
        defer { try? FileManager.default.removeItem(at: stagedURL) }

        XCTAssertEqual(try Data(contentsOf: stagedURL), Data(contents.utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: stagedURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o400))
    }

    private func temporaryHEX(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("hex")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }
}
