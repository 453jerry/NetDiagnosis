import XCTest
@testable import NetDiagnosis

final class NetDiagnosisTests: XCTestCase {
    func testCloseSocket() throws {
        let addr = try XCTUnwrap(IPAddr.create("8.8.8.8", addressFamily: .ipv4))
        var socket: Int32?
        weak var wpinger: Pinger?
        try {
            let pinger = try Pinger(remoteAddr: addr)
            wpinger = pinger
            socket = pinger.sock
        }()

        let socketUnwrapped = try XCTUnwrap(socket)
        XCTAssertNil(wpinger)

        XCTAssertFalse(checkIfSocketIsOpen(socketUnwrapped))
    }

    /// This is not a thorough investigation if the socket is open, but should suffice for a simple test
    private func checkIfSocketIsOpen(_ socket: Int32) -> Bool {
        var error = 0
        var errorLength = socklen_t(MemoryLayout<Int>.size)

        if getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &errorLength) < 0 {
            return false
        }
        return error == 0
    }
}
