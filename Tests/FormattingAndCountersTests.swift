//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  FormattingAndCountersTests.swift — two pure functions that the UI is only as
//  correct as.
//
//  Both exist because the iOS client silently disagreed with the rest of the
//  product:
//
//   - `ByteFormat` used to be ByteCountFormatter with `.binary`, so a 10 GB
//     plan read as "9.3 GB" on iOS and "10.0 GB" on Android, the portal and the
//     backend. A quota figure that does not match the plan the user bought is a
//     support ticket, not a rounding preference.
//   - `TunnelStore.counters` reads wireguard-go's UAPI report, which is the
//     only source for the throughput strip. A parser that quietly returns zero
//     renders as "0 B/s" over a working tunnel, which reads as a dead VPN.
//
import XCTest
@testable import AvangardVPN

final class ByteFormatTests: XCTestCase {

    func testUnderAKilobyteStaysInBytes() {
        XCTAssertEqual(ByteFormat.string(0), "0 B")
        XCTAssertEqual(ByteFormat.string(999), "999 B")
    }

    /// The boundary that matters: base 1000, so 1000 bytes is a kilobyte. Under
    /// the old binary formatter this was still "1,000 bytes".
    func testKilobyteBoundaryIsBaseOneThousand() {
        XCTAssertEqual(ByteFormat.string(1000), "1.0 KB")
    }

    /// The case that sent users to support: the plan says 10 GB, so the app has
    /// to say 10.0 GB. Binary units would render this as 9.3 GB.
    func testTenGigabytePlanReadsAsTenGigabytes() {
        XCTAssertEqual(ByteFormat.string(10_000_000_000), "10.0 GB")
    }

    func testScalesThroughTheUnits() {
        XCTAssertEqual(ByteFormat.string(1_500_000), "1.5 MB")
        XCTAssertEqual(ByteFormat.string(2_000_000_000_000), "2.0 TB")
    }

    /// Larger than a terabyte has nowhere left to go and must not fall off the
    /// end of the unit list.
    func testAboveTerabytesStaysInTerabytes() {
        XCTAssertEqual(ByteFormat.string(5_000_000_000_000_000), "5000.0 TB")
    }

    /// A negative counter is not reachable through the API, but clamping is
    /// cheaper than a "-1 B" appearing on screen if one ever is.
    func testNegativeClampsToZero() {
        XCTAssertEqual(ByteFormat.string(-1), "0 B")
    }

    func testRateAppendsPerSecond() {
        XCTAssertEqual(ByteFormat.rate(1000), "1.0 KB/s")
    }
}

@MainActor
final class RuntimeCounterTests: XCTestCase {

    /// A realistic UAPI report: interface keys first, then the peer's, with the
    /// counters after its public key.
    private let report = """
    private_key=0000000000000000000000000000000000000000000000000000000000000000
    listen_port=51820
    public_key=1111111111111111111111111111111111111111111111111111111111111111
    preshared_key=2222222222222222222222222222222222222222222222222222222222222222
    endpoint=203.0.113.10:51820
    last_handshake_time_sec=1756700000
    last_handshake_time_nsec=123456789
    tx_bytes=4096
    rx_bytes=8192
    persistent_keepalive_interval=25
    errno=0
    """

    func testReadsBothCounters() {
        let counters = TunnelStore.counters(in: report)
        XCTAssertEqual(counters?.rx, 8192)
        XCTAssertEqual(counters?.tx, 4096)
    }

    /// Summed rather than taken from the first peer, so adding a second peer
    /// does not silently halve the reported rate.
    func testSumsAcrossPeers() {
        let twoPeers = report + """

        public_key=3333333333333333333333333333333333333333333333333333333333333333
        tx_bytes=1000
        rx_bytes=2000
        """
        let counters = TunnelStore.counters(in: twoPeers)
        XCTAssertEqual(counters?.rx, 10192)
        XCTAssertEqual(counters?.tx, 5096)
    }

    /// Nil, not (0, 0). The caller treats nil as "no reading" and keeps its
    /// baseline; zeroes would look like a real measurement of a stalled tunnel.
    func testReportWithoutCountersIsNotAReading() {
        XCTAssertNil(TunnelStore.counters(in: "errno=0"))
        XCTAssertNil(TunnelStore.counters(in: ""))
    }

    /// A tunnel that just came up legitimately reports zeroes, and that IS a
    /// reading — it seeds the baseline the first delta is measured from.
    func testZeroCountersAreStillAReading() {
        let fresh = """
        public_key=1111111111111111111111111111111111111111111111111111111111111111
        tx_bytes=0
        rx_bytes=0
        """
        let counters = TunnelStore.counters(in: fresh)
        XCTAssertEqual(counters?.rx, 0)
        XCTAssertEqual(counters?.tx, 0)
    }

    /// Unparseable values are skipped rather than crashing or counting as zero.
    func testGarbageValuesAreIgnored() {
        let mixed = """
        rx_bytes=notanumber
        tx_bytes=512
        """
        let counters = TunnelStore.counters(in: mixed)
        XCTAssertEqual(counters?.rx, 0)
        XCTAssertEqual(counters?.tx, 512)
    }
}
