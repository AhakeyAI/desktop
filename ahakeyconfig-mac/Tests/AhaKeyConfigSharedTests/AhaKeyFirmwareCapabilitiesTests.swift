import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyFirmwareCapabilitiesTests: XCTestCase {

    /// Rhino 固件实抓的 26 字节能力帧（含出厂资源束 + 回收槽位区间）。
    private let rhino26Payload = Data([
        3, 4, 2, 4,
        0x3F, 0x00,
        0xF4, 0x00,
        0x20, 0x01,
        0x30, 0x01,
        0x02, 0x00, 0x00, 0x00,
        0xF6, 0x5D, 0x2C, 0x82,
        2, 0,
        0x28, 0x01,
        0x30, 0x01,
    ])

    // MARK: - 三档长度解析

    func testParses26ByteCapabilities() {
        let capabilities = AhaKeyFirmwareCapabilities.parse(rhino26Payload)

        XCTAssertEqual(capabilities?.protocolVersion, 3)
        XCTAssertEqual(capabilities?.modeCount, 4)
        XCTAssertEqual(capabilities?.setCount, 2)
        XCTAssertEqual(capabilities?.stateCount, 4)
        XCTAssertEqual(capabilities?.flags, 0x003F)
        XCTAssertEqual(capabilities?.maxPacketSize, 244)
        XCTAssertEqual(capabilities?.userSlotLimit, 288)
        XCTAssertEqual(capabilities?.factorySlotBase, 304)
        XCTAssertEqual(capabilities?.factoryBundleVersion, 2)
        XCTAssertEqual(capabilities?.factoryManifestCRC, 0x822C5DF6)
        XCTAssertEqual(capabilities?.factoryStatus, 2)
        XCTAssertEqual(capabilities?.factoryError, 0)
        XCTAssertEqual(capabilities?.reclaimSlotBase, 296)
        XCTAssertEqual(capabilities?.reclaimSlotLimit, 304)
        XCTAssertTrue(capabilities?.supportsIdleTaskPicture == true)
        XCTAssertTrue(capabilities?.supportsSessionUpload == true)
    }

    func testParses22ByteCapabilitiesWithFactoryFields() {
        let payload = rhino26Payload.prefix(22)
        let capabilities = AhaKeyFirmwareCapabilities.parse(Data(payload))

        XCTAssertEqual(capabilities?.protocolVersion, 3)
        XCTAssertEqual(capabilities?.factorySlotBase, 304)
        XCTAssertEqual(capabilities?.factoryBundleVersion, 2)
        XCTAssertEqual(capabilities?.factoryManifestCRC, 0x822C5DF6)
        XCTAssertEqual(capabilities?.factoryStatus, 2)
        XCTAssertEqual(capabilities?.factoryError, 0)
        // 无回收槽位区间：回退读取 offset 10/12（与 Rhino parseCapabilities 一致）
        XCTAssertEqual(capabilities?.reclaimSlotBase, 304)
        XCTAssertEqual(capabilities?.reclaimSlotLimit, 2)
    }

    func testParses14ByteCapabilitiesWithFallbacks() {
        let payload = rhino26Payload.prefix(14)
        let capabilities = AhaKeyFirmwareCapabilities.parse(Data(payload))

        XCTAssertEqual(capabilities?.protocolVersion, 3)
        XCTAssertEqual(capabilities?.modeCount, 4)
        XCTAssertEqual(capabilities?.stateCount, 4)
        XCTAssertEqual(capabilities?.maxPacketSize, 244)
        XCTAssertEqual(capabilities?.userSlotLimit, 288)
        // 无出厂字段：factorySlotBase 回退为 userSlotLimit，其余出厂字段为 0
        XCTAssertEqual(capabilities?.factorySlotBase, 288)
        XCTAssertEqual(capabilities?.factoryBundleVersion, 0)
        XCTAssertEqual(capabilities?.factoryManifestCRC, 0)
        XCTAssertEqual(capabilities?.factoryStatus, 0)
        XCTAssertEqual(capabilities?.factoryError, 0)
        // 回收槽位区间回退读取 offset 10/12
        XCTAssertEqual(capabilities?.reclaimSlotBase, 304)
        XCTAssertEqual(capabilities?.reclaimSlotLimit, 2)
    }

    func testRejectsTruncatedCapabilities() {
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(Data(repeating: 0, count: 13)))
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(Data()))
    }

    // MARK: - 能力标志位

    func testIdleTaskPictureRequiresStateCountAndFlag() {
        let base = AhaKeyFirmwareCapabilities.parse(rhino26Payload)!

        let noFlag = AhaKeyFirmwareCapabilities(
            protocolVersion: base.protocolVersion, modeCount: base.modeCount,
            setCount: base.setCount, stateCount: base.stateCount,
            flags: base.flags & ~AhaKeyFirmwareCapabilities.idleTaskPictureFlag,
            maxPacketSize: base.maxPacketSize, userSlotLimit: base.userSlotLimit,
            factorySlotBase: base.factorySlotBase,
            factoryBundleVersion: base.factoryBundleVersion,
            factoryManifestCRC: base.factoryManifestCRC,
            factoryStatus: base.factoryStatus, factoryError: base.factoryError,
            reclaimSlotBase: base.reclaimSlotBase, reclaimSlotLimit: base.reclaimSlotLimit
        )
        XCTAssertFalse(noFlag.supportsIdleTaskPicture)
        XCTAssertTrue(noFlag.supportsSessionUpload)

        let fewerStates = AhaKeyFirmwareCapabilities(
            protocolVersion: base.protocolVersion, modeCount: base.modeCount,
            setCount: base.setCount, stateCount: 3,
            flags: base.flags,
            maxPacketSize: base.maxPacketSize, userSlotLimit: base.userSlotLimit,
            factorySlotBase: base.factorySlotBase,
            factoryBundleVersion: base.factoryBundleVersion,
            factoryManifestCRC: base.factoryManifestCRC,
            factoryStatus: base.factoryStatus, factoryError: base.factoryError,
            reclaimSlotBase: base.reclaimSlotBase, reclaimSlotLimit: base.reclaimSlotLimit
        )
        XCTAssertFalse(fewerStates.supportsIdleTaskPicture)

        let noSession = AhaKeyFirmwareCapabilities(
            protocolVersion: base.protocolVersion, modeCount: base.modeCount,
            setCount: base.setCount, stateCount: base.stateCount,
            flags: base.flags & ~AhaKeyFirmwareCapabilities.sessionUploadFlag,
            maxPacketSize: base.maxPacketSize, userSlotLimit: base.userSlotLimit,
            factorySlotBase: base.factorySlotBase,
            factoryBundleVersion: base.factoryBundleVersion,
            factoryManifestCRC: base.factoryManifestCRC,
            factoryStatus: base.factoryStatus, factoryError: base.factoryError,
            reclaimSlotBase: base.reclaimSlotBase, reclaimSlotLimit: base.reclaimSlotLimit
        )
        XCTAssertFalse(noSession.supportsSessionUpload)
    }

    // MARK: - protocolMode 决策矩阵

    private func capabilities(protocolVersion: Int) -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: protocolVersion, modeCount: 4, setCount: 2, stateCount: 4,
            flags: 0x3F, maxPacketSize: 244, userSlotLimit: 288, factorySlotBase: 304,
            factoryBundleVersion: 2, factoryManifestCRC: 0x822C5DF6,
            factoryStatus: 2, factoryError: 0, reclaimSlotBase: 296, reclaimSlotLimit: 304
        )
    }

    func testProtocolVersion3ResolvesCurrent() {
        XCTAssertEqual(AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities(protocolVersion: 3)), .current)
    }

    func testOtherProtocolVersionsResolveRestrictedUnknown() {
        for version in [0, 1, 2, 4, 255] {
            XCTAssertEqual(
                AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities(protocolVersion: version)),
                .restrictedUnknown,
                "protocolVersion \(version) 应为 restrictedUnknown"
            )
        }
    }

    func testFallbackAfterExhaustedAttempts() {
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.fallbackMode(
                firmwareMainVersion: 1,
                supportsLegacyTaskPictures: true
            ),
            .legacy
        )
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.fallbackMode(
                firmwareMainVersion: 1,
                supportsLegacyTaskPictures: false
            ),
            .legacyBaseOnly
        )
        for version in [0, 2, 3, 255] {
            XCTAssertEqual(
                AhaKeyProtocolNegotiation.fallbackMode(
                    firmwareMainVersion: version,
                    supportsLegacyTaskPictures: true
                ),
                .restrictedUnknown,
                "firmwareMainVersion \(version) 应为 restrictedUnknown"
            )
        }
    }

    // MARK: - 重试语义

    func testRetrySemanticsAllowExactlyThreeAttempts() {
        XCTAssertTrue(AhaKeyProtocolNegotiation.shouldRetry(afterFailedAttempt: 1))
        XCTAssertTrue(AhaKeyProtocolNegotiation.shouldRetry(afterFailedAttempt: 2))
        XCTAssertFalse(AhaKeyProtocolNegotiation.shouldRetry(afterFailedAttempt: 3))
        XCTAssertEqual(AhaKeyProtocolNegotiation.maxAttempts, 3)
    }

    // MARK: - 消费入口（M2/M3）

    func testUSBTransportOnlyAllowedOnCurrent() {
        XCTAssertTrue(AhaKeyProtocolMode.current.allowsUSBConfigurationTransport)
        XCTAssertFalse(AhaKeyProtocolMode.negotiating.allowsUSBConfigurationTransport)
        XCTAssertFalse(AhaKeyProtocolMode.legacy.allowsUSBConfigurationTransport)
        XCTAssertFalse(AhaKeyProtocolMode.legacyBaseOnly.allowsUSBConfigurationTransport)
        XCTAssertFalse(AhaKeyProtocolMode.restrictedUnknown.allowsUSBConfigurationTransport)
    }

    func testTaskPictureConfigurationAllowedOnKnownProtocols() {
        XCTAssertTrue(AhaKeyProtocolMode.current.allowsTaskPictureConfiguration)
        XCTAssertTrue(AhaKeyProtocolMode.legacy.allowsTaskPictureConfiguration)
        XCTAssertFalse(AhaKeyProtocolMode.legacyBaseOnly.allowsTaskPictureConfiguration)
        XCTAssertFalse(AhaKeyProtocolMode.negotiating.allowsTaskPictureConfiguration)
        XCTAssertFalse(AhaKeyProtocolMode.restrictedUnknown.allowsTaskPictureConfiguration)
    }
}
