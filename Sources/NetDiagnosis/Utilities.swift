//
//  Utilities.swift
//  
//
//  Created by Jerry on 2023/4/8.
//

import Foundation

// MARK: - Timer interval
extension TimeInterval {
    func toTimeVal() -> timeval {
        let sec = floor(self)
        let usec = floor((self - sec) * 1000000)
        return timeval.init(
            tv_sec: __darwin_time_t(sec),
            tv_usec: __darwin_suseconds_t(usec)
        )
    }
    
    func toTimeValue() -> time_value {
        let sec = floor(self)
        let usec = floor((self - sec) * 1000000)
        return time_value.init(
            seconds: integer_t(sec),
            microseconds: integer_t(usec)
        )
    }
}

// MARK: - ICMP

public func checkSum(
    ptr: UnsafeRawBufferPointer,
    skip: Range<Int>? = nil
) -> UInt16 {
    var sum: UInt32 = 0
    var idx = 0
    while idx < (ptr.count - 1) {
        if !(skip?.contains(idx) ?? false) {
            sum &+= UInt32(
                ptr.load(
                    fromByteOffset: idx,
                    as: UInt16.self
                )
            )
        }
        idx += 2
    }
    
    if idx == (ptr.count - 1) {
        // swiftlint: disable force_unwrapping
        let tmp = Data.init([ptr.last!, 0x00])
        tmp.withUnsafeBytes { tmpRawPointer in
            sum &+= UInt32(tmpRawPointer.load(as: UInt16.self))
        }
    }
    sum = (sum >> 16) &+ (sum & 0xffff)
    sum &+= (sum >> 16)
    return UInt16(truncatingIfNeeded: ~sum)
}

#if swift(<5.5)
// swiftlint: disable identifier_name
let ICMP_ECHO: Int32 = 8
let ICMP6_ECHO_REQUEST: Int32 = 128
let ICMP_ECHOREPLY: Int32 = 0
let ICMP6_ECHO_REPLY: Int32 = 129
let ICMP_TIMXCEED: Int32 = 11
let ICMP6_TIME_EXCEEDED: Int32 = 3

#endif
