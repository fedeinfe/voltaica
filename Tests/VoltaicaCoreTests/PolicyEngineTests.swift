import XCTest
@testable import VoltaicaCore

final class PolicyEngineTests: XCTestCase {
    private var engine = PolicyEngine()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(percentage: Int,
                          plugged: Bool = true,
                          temperature: Double = 30,
                          present: Bool = true) -> BatterySnapshot {
        var snapshot = BatterySnapshot()
        snapshot.percentage = percentage
        snapshot.rawPercentage = Double(percentage)
        snapshot.isPluggedIn = plugged
        snapshot.temperature = temperature
        snapshot.isPresent = present
        return snapshot
    }

    func testHoldsAtLimit() {
        var config = ChargeConfiguration()
        config.limit = 80
        let decision = engine.evaluate(config: &config, snapshot: snapshot(percentage: 80), now: now)
        XCTAssertFalse(decision.chargingAllowed)
        XCTAssertEqual(decision.mode, .holding)
    }

    func testChargesBelowLimit() {
        var config = ChargeConfiguration()
        config.limit = 80
        let decision = engine.evaluate(config: &config, snapshot: snapshot(percentage: 60), now: now)
        XCTAssertTrue(decision.chargingAllowed)
        XCTAssertEqual(decision.mode, .charging)
    }

    /// Sailing is the whole point of the app: once held, charging must not resume one percent later.
    func testSailingKeepsChargerOffInsideTheBand() {
        var config = ChargeConfiguration()
        config.limit = 80
        config.sailingEnabled = true
        config.sailingDepth = 5
        _ = engine.evaluate(config: &config, snapshot: snapshot(percentage: 80), now: now)
        let drifted = engine.evaluate(config: &config, snapshot: snapshot(percentage: 77), now: now)
        XCTAssertFalse(drifted.chargingAllowed)
        let resumed = engine.evaluate(config: &config, snapshot: snapshot(percentage: 74), now: now)
        XCTAssertTrue(resumed.chargingAllowed)
    }

    /// The bug that made discharge look broken: asking for one with the limit switched off hit
    /// the "limit off" early return and nothing ever happened.
    func testExplicitDischargeIgnoresTheLimitSwitch() {
        var config = ChargeConfiguration()
        config.enabled = false
        config.discharge = DischargeRequest(target: 50, requestedAt: now)
        let decision = engine.evaluate(config: &config, snapshot: snapshot(percentage: 90), now: now)
        XCTAssertEqual(decision.mode, .discharging)
        XCTAssertFalse(decision.adapterEnabled)
    }

    func testDischargeStopsAtTheConfiguredFloor() {
        var config = ChargeConfiguration()
        config.dischargeFloor = 20
        config.discharge = DischargeRequest(target: 5, requestedAt: now)
        let running = engine.evaluate(config: &config, snapshot: snapshot(percentage: 30), now: now)
        XCTAssertEqual(running.mode, .discharging)
        XCTAssertTrue(running.detail.contains("20%"), "the floor wins over a lower request")

        var atFloor = ChargeConfiguration()
        atFloor.dischargeFloor = 20
        atFloor.discharge = DischargeRequest(target: 5, requestedAt: now)
        let stopped = engine.evaluate(config: &atFloor, snapshot: snapshot(percentage: 20), now: now)
        XCTAssertNotEqual(stopped.mode, .discharging)
        XCTAssertTrue(stopped.adapterEnabled)
        XCTAssertNil(atFloor.discharge)
    }

    /// Some Macs accept the adapter cut and keep running off the wall. Promising a discharge that
    /// will never finish is worse than saying so.
    func testDischargeGivesUpWhenTheMacIgnoresTheCut() {
        engine.adapterCutWorks = false
        var config = ChargeConfiguration()
        config.discharge = DischargeRequest(target: 50, requestedAt: now)
        let decision = engine.evaluate(config: &config, snapshot: snapshot(percentage: 90), now: now)
        XCTAssertTrue(decision.adapterEnabled)
        XCTAssertNotEqual(decision.mode, .discharging)
        XCTAssertNil(config.discharge, "a request that cannot be honoured is dropped, not queued")
    }

    /// The limit has to act on the percentage macOS shows, not the raw gauge ratio: on a worn
    /// pack the two are several points apart and the user only ever sees one of them.
    func testLimitFollowsTheFigureMacOSShows() {
        var snapshot = self.snapshot(percentage: 80)
        snapshot.rawPercentage = 76.4
        var config = ChargeConfiguration()
        config.limit = 80
        let decision = engine.evaluate(config: &config, snapshot: snapshot, now: now)
        XCTAssertEqual(decision.mode, .holding)
        XCTAssertFalse(decision.chargingAllowed)
    }

    func testEmergencyFloorAlwaysCharges() {
        var config = ChargeConfiguration()
        config.limit = 80
        config.pauseUntil = now.addingTimeInterval(3_600)
        let decision = engine.evaluate(config: &config, snapshot: snapshot(percentage: 4), now: now)
        XCTAssertTrue(decision.chargingAllowed, "a nearly flat battery outranks every other rule")
    }

    func testHeatPauseRespectsItsFloor() {
        var config = ChargeConfiguration()
        config.limit = 100
        config.heatProtectionEnabled = true
        config.heatThreshold = 38
        config.heatProtectionFloor = 25
        let hot = engine.evaluate(config: &config,
                                  snapshot: snapshot(percentage: 60, temperature: 41),
                                  now: now)
        XCTAssertFalse(hot.chargingAllowed)
        XCTAssertEqual(hot.mode, .heatPaused)

        let hotAndLow = engine.evaluate(config: &config,
                                        snapshot: snapshot(percentage: 18, temperature: 41),
                                        now: now)
        XCTAssertTrue(hotAndLow.chargingAllowed)
    }

    func testDischargeNeverGoesBelowFifteen() {
        var config = ChargeConfiguration()
        config.limit = 50
        config.discharge = DischargeRequest(target: 5)
        let decision = engine.evaluate(config: &config, snapshot: snapshot(percentage: 14), now: now)
        XCTAssertTrue(decision.adapterEnabled, "the adapter must come back before the pack empties")
    }

    func testUnpluggedNeverTouchesTheCharger() {
        var config = ChargeConfiguration()
        config.limit = 80
        let decision = engine.evaluate(config: &config,
                                       snapshot: snapshot(percentage: 90, plugged: false),
                                       now: now)
        XCTAssertTrue(decision.chargingAllowed)
        XCTAssertTrue(decision.adapterEnabled)
        XCTAssertEqual(decision.mode, .onBattery)
    }

    func testNoBatteryIsInert() {
        var config = ChargeConfiguration()
        let decision = engine.evaluate(config: &config,
                                       snapshot: snapshot(percentage: 0, present: false),
                                       now: now)
        XCTAssertEqual(decision.mode, .noBattery)
        XCTAssertTrue(decision.chargingAllowed)
    }

    func testTopUpOverridesTheLimitThenClears() {
        var config = ChargeConfiguration()
        config.limit = 60
        config.topUp = TopUpRequest(target: 100, expiresAt: now.addingTimeInterval(3_600))
        let climbing = engine.evaluate(config: &config, snapshot: snapshot(percentage: 70), now: now)
        XCTAssertTrue(climbing.chargingAllowed)
        XCTAssertEqual(climbing.mode, .topUp)

        _ = engine.evaluate(config: &config, snapshot: snapshot(percentage: 100), now: now)
        XCTAssertNil(config.topUp, "a satisfied request must not linger")
    }

    func testExpiredTopUpIsDropped() {
        var config = ChargeConfiguration()
        config.limit = 60
        config.topUp = TopUpRequest(target: 100, expiresAt: now.addingTimeInterval(-60))
        let decision = engine.evaluate(config: &config, snapshot: snapshot(percentage: 70), now: now)
        XCTAssertNil(config.topUp)
        XCTAssertFalse(decision.chargingAllowed)
    }

    /// Turning the limit off must look exactly like not having Voltaica installed: the charger
    /// is allowed, and the state reported is the plain hardware state rather than a Voltaica one.
    func testDisabledPolicyHandsBackControl() {
        var config = ChargeConfiguration()
        config.enabled = false
        let decision = engine.evaluate(config: &config, snapshot: snapshot(percentage: 100), now: now)
        XCTAssertTrue(decision.chargingAllowed)
        XCTAssertTrue(decision.adapterEnabled)
        XCTAssertEqual(decision.mode, .charging)
        XCTAssertEqual(decision.detail, "Charge limit off")
    }
}

final class ConfigurationTests: XCTestCase {
    func testValidationClampsEverything() {
        var config = ChargeConfiguration()
        config.limit = 400
        config.sailingDepth = 99
        config.heatThreshold = 5
        config.dischargeFloor = 1
        let clean = config.validated()
        XCTAssertEqual(clean.limit, 100)
        XCTAssertLessThanOrEqual(clean.sailingDepth, 20)
        XCTAssertGreaterThanOrEqual(clean.heatThreshold, 30)
        XCTAssertGreaterThanOrEqual(clean.dischargeFloor, 15)
    }

    func testLowLimitStillLeavesUsableRuntime() {
        var config = ChargeConfiguration()
        config.limit = 0
        XCTAssertGreaterThanOrEqual(config.validated().limit, 20)
    }
}

final class SMCLayoutTests: XCTestCase {
    /// The kernel copies exactly 80 bytes in and out. If Swift ever repacks this struct the
    /// selector silently starts reading the wrong fields, so the size is part of the contract.
    func testParameterStructMatchesTheKernelABI() {
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.stride, 80)
    }

    func testFloatDecodingIsLittleEndian() {
        let bytes: [UInt8] = [0x98, 0x99, 0x0b, 0x42]
        let value = SMCConnection.decodeNumber(bytes: bytes, type: "flt ")
        XCTAssertEqual(value ?? 0, 34.9, accuracy: 0.01)
    }

    func testFixedPointDecoding() {
        XCTAssertEqual(SMCConnection.decodeNumber(bytes: [0x22, 0x80], type: "sp78") ?? 0,
                       34.5, accuracy: 0.001)
    }

    func testByteOrderIsExplicit() {
        let bytes: [UInt8] = [0x12, 0x56]
        XCTAssertEqual(SMCConnection.decodeNumber(bytes: bytes, type: "ui16", order: .big), 4694)
        XCTAssertEqual(SMCConnection.decodeNumber(bytes: bytes, type: "ui16", order: .little), 22034)
    }
}

final class LicenseTests: XCTestCase {
    func testGarbageKeysAreRejected() {
        XCTAssertNil(License.verify(""))
        XCTAssertNil(License.verify("nonsense"))
        XCTAssertNil(License.verify("aaaa.bbbb"))
    }

    /// A key signed by anybody else must not unlock anything, which is the only thing standing
    /// between a paid app and a keygen.
    func testForeignSignatureIsRejected() {
        let payload = Data(#"{"email":"a@b.c","issued":0,"order":"x","seats":3}"#.utf8)
        let fake = "\(License.encodeBase64URL(payload)).\(License.encodeBase64URL(Data(repeating: 7, count: 64)))"
        XCTAssertNil(License.verify(fake))
    }

    func testTrialExpiryFallsBackToTheFreeTier() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let inTrial = License.state(license: nil, firstRun: start, now: start.addingTimeInterval(86_400))
        XCTAssertEqual(inTrial, .trial(daysLeft: 13))
        XCTAssertTrue(inTrial.features.customLimit)

        let after = License.state(license: nil, firstRun: start, now: start.addingTimeInterval(86_400 * 20))
        XCTAssertEqual(after, .trialExpired)
        XCTAssertFalse(after.features.customLimit)
    }

    func testClampPinsTheFreeTierToTheFirmwareCeiling() {
        var config = ChargeConfiguration()
        config.limit = 55
        config.sailingEnabled = true
        config.heatProtectionEnabled = true
        config.discharge = DischargeRequest(target: 40)
        License.clamp(&config, to: .free)
        XCTAssertEqual(config.limit, FeatureSet.freeTierLimit)
        XCTAssertFalse(config.sailingEnabled)
        XCTAssertFalse(config.heatProtectionEnabled)
        XCTAssertNil(config.discharge)
    }

    func testClampLeavesLicensedConfigurationsAlone() {
        var config = ChargeConfiguration()
        config.limit = 55
        let original = config
        License.clamp(&config, to: .full)
        XCTAssertEqual(config, original)
    }
}
