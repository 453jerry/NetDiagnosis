//
//  Pinger+Sockopt.swift
//  
//
//  Created by Jerry on 2023/4/1.
//

import Foundation

extension Pinger {
    // MARK: - Set socket options
    
    func setReceiveHopLimit(_ isReceive: Bool) throws {
        let val: UInt32 = isReceive ? 1 : 0
        let code = withUnsafePointer(to: val) { ptr in
            setsockopt(
                self.sock,
                self.ipProtocol,
                self.receiveHopLimitOption,
                ptr,
                socklen_t(MemoryLayout.size(ofValue: val))
            )
        }
        if code != 0 {
            // swiftlint:disable force_unwrapping
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
    }
    
    func setReceiveTimeout(_ time: TimeInterval) throws {
        let timeVal = time.toTimeVal()
        let code = withUnsafePointer(to: timeVal) { ptr in
            setsockopt(
                self.sock,
                SOL_SOCKET,
                SO_RCVTIMEO,
                ptr,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }
        if code != 0 {
            // swiftlint:disable force_unwrapping
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
    }
    
    func setHopLimit(_ hopLimit: UInt32) throws {
        let code = withUnsafePointer(to: hopLimit) { ptr in
            setsockopt(
                self.sock,
                self.ipProtocol,
                self.hopLimitOption,
                ptr,
                socklen_t(MemoryLayout.size(ofValue: hopLimit))
            )
        }
        if code != 0 {
            // swiftlint:disable force_unwrapping
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
    }
    
    // MARK: - definitions
    
    var ipProtocol: Int32 {
        switch remoteAddr {
        case .ipv4:
            return IPPROTO_IP
        case .ipv6:
            return IPPROTO_IPV6
        }
    }
    
    var receiveHopLimitOption: Int32 {
        switch remoteAddr {
        case .ipv4:
            return IP_RECVTTL
        case .ipv6:
            return IPV6_2292HOPLIMIT
        }
    }
    
    var hopLimitOption: Int32 {
        switch remoteAddr {
        case .ipv4:
            return IP_TTL
        case .ipv6:
            return IPV6_UNICAST_HOPS
        }
    }
    
    var icmpTypeEchoRequst: Int32 {
        switch self.remoteAddr.addressFamily {
        case .ipv4:
            return ICMP_ECHO
        case .ipv6:
            return ICMP6_ECHO_REQUEST
        }
    }
    
    var icmpTpeEchoReplay: Int32 {
        switch self.remoteAddr.addressFamily {
        case .ipv4:
            return ICMP_ECHOREPLY
        case .ipv6:
            return ICMP6_ECHO_REPLY
        }
    }
    
    var icmpTypeHopLimitExceeded: Int32 {
        switch self.remoteAddr.addressFamily {
        case .ipv4:
            return ICMP_TIMXCEED
        case .ipv6:
            return ICMP6_TIME_EXCEEDED
        }
    }
}
