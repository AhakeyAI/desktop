import XCTest
@testable import AhaKeyConfig

final class VoiceCloudWriteSetupTests: XCTestCase {
    func testSignedOutCloudPresetOffersLoginBeforeEnablement() {
        XCTAssertEqual(VoiceHandoffHost.cloudSetupRequired(
            for: .ahaTypeCloud, isLoggedIn: false, hasToken: false, requiresLogin: false, isEnabled: false
        ), .cloudNotConfigured)
        XCTAssertEqual(VoiceHandoffHost.cloudSetupRequired(
            for: .ahaTypeCloud, isLoggedIn: true, hasToken: true, requiresLogin: true, isEnabled: true
        ), .cloudNotConfigured)
        XCTAssertEqual(VoiceHandoffHost.cloudSetupRequired(
            for: .ahaTypeCloud, isLoggedIn: true, hasToken: false, requiresLogin: false, isEnabled: true
        ), .cloudNotConfigured)
    }

    func testOnlyAhaTypeCloudPresetRequiresTheGlobalToggle() {
        XCTAssertEqual(VoiceHandoffHost.cloudSetupRequired(
            for: .ahaTypeCloud, isLoggedIn: true, hasToken: true, requiresLogin: false, isEnabled: false
        ), .cloudDisabled)
        XCTAssertNil(VoiceHandoffHost.cloudSetupRequired(
            for: .ahaTypeCloud, isLoggedIn: true, hasToken: true, requiresLogin: false, isEnabled: true
        ))
        XCTAssertNil(VoiceHandoffHost.cloudSetupRequired(
            for: .macOSNative, isLoggedIn: false, hasToken: false, requiresLogin: false, isEnabled: false
        ))
    }
}
