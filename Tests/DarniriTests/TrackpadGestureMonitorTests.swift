@testable import Darniri
import XCTest

final class TrackpadGestureMonitorTests: XCTestCase {
    func testDecoderReadsStrideIdentityAndOnlyActiveContactStates() throws {
        let data = UnsafeMutableRawPointer.allocate(byteCount: 96 * 7, alignment: 8)
        defer { data.deallocate() }
        data.initializeMemory(as: UInt8.self, repeating: 0, count: 96 * 7)
        for index in 0 ..< 7 {
            let record = data.advanced(by: index * 96)
            record.storeBytes(of: Int32(index + 100), toByteOffset: 16, as: Int32.self)
            record.storeBytes(of: Int32(index + 1), toByteOffset: 20, as: Int32.self)
            record.storeBytes(of: Float(0.25), toByteOffset: 32, as: Float.self)
            record.storeBytes(of: Float(0.75), toByteOffset: 36, as: Float.self)
        }
        let contacts = try XCTUnwrap(TrackpadGestureMonitor.decodeContacts(data: data, count: 7))
        XCTAssertEqual(contacts.map(\.id), [102, 103])
        XCTAssertEqual(contacts.map(\.x), [0.25, 0.25])
        XCTAssertEqual(contacts.map(\.y), [0.75, 0.75])
    }

    func testContactSnapshotsOwnValuesAfterCallbackBufferChanges() throws {
        let data = UnsafeMutableRawPointer.allocate(byteCount: 96, alignment: 8)
        defer { data.deallocate() }
        data.initializeMemory(as: UInt8.self, repeating: 0, count: 96)
        data.storeBytes(of: Int32(4), toByteOffset: 20, as: Int32.self)
        data.storeBytes(of: Float(0.25), toByteOffset: 32, as: Float.self)
        let contacts = try XCTUnwrap(TrackpadGestureMonitor.decodeContacts(data: data, count: 1))
        data.storeBytes(of: Float(0.9), toByteOffset: 32, as: Float.self)
        XCTAssertEqual(contacts.first?.x, 0.25)
    }

    func testEmptyFrameSignalsReleaseAndMalformedFrameIsDropped() {
        XCTAssertEqual(TrackpadGestureMonitor.decodeContacts(data: nil, count: 0)?.count, 0)
        XCTAssertNil(TrackpadGestureMonitor.decodeContacts(data: nil, count: 1))
        XCTAssertNil(TrackpadGestureMonitor.decodeContacts(data: nil, count: -1))
        XCTAssertNil(TrackpadGestureMonitor.decodeContacts(data: nil, count: 17))
    }
}
