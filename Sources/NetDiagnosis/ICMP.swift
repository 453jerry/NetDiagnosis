//
//  ICMP.swift
//  
//
//  Created by Jerry on 2023/1/30.
//

import Foundation

public enum ICMP {
    public struct Header {
        var type: UInt8
        var code: UInt8
        fileprivate let checkSum: UInt16 = 0x00 // Place holder
        var identifier: UInt16
        var sequenceNumber: UInt16
        
        static let checkSumRange = Range.init(2...3)
    }
    
    public static func createPacketData(
        with header: Header,
        payload: Data? = nil
    ) -> Data {
        var packetData = Data.init(
            count: MemoryLayout.size(ofValue: header) +
            (payload?.count ?? 0)
        )
        
        packetData.withUnsafeMutableBytes { rawPtr in
            // swiftlint: disable force_unwrapping
            var uint8Ptr = rawPtr.bindMemory(to: UInt8.self).baseAddress!
            uint8Ptr.pointee = header.type
            uint8Ptr = uint8Ptr.advanced(by: 1)
            uint8Ptr.pointee = header.code
            uint8Ptr = uint8Ptr.advanced(by: 1)
            
            var uint16Ptr = UnsafeMutablePointer<UInt16>.init(
                OpaquePointer(uint8Ptr)
            )
            uint16Ptr.pointee = 0 // skip checksum
            uint16Ptr = uint16Ptr.advanced(by: 1)
            uint16Ptr.pointee = header.identifier.bigEndian
            uint16Ptr = uint16Ptr.advanced(by: 1)
            uint16Ptr.pointee = header.sequenceNumber.bigEndian
        }

        if let payload = payload {
            packetData.replaceSubrange(8..., with: payload)
        }

        var checkSum: UInt16 = packetData.withUnsafeBytes { ptr in
            calculateCheckSum(
                ptr: ptr,
                skip: Header.checkSumRange
            )
        }

        packetData.replaceSubrange(
            Header.checkSumRange,
            with: &checkSum,
            count: 2
        )
        return packetData
    }
    
    public static func create(
        frome packetDataPtr: UnsafeRawBufferPointer
    ) -> (header: Header, payload: Data) {
        
        var header = packetDataPtr.load(as: Header.self)
        header.identifier = header.identifier.bigEndian
        header.sequenceNumber = header.sequenceNumber.bigEndian
        
        let payload = Data.init(
            // swiftlint: disable force_unwrapping
            bytes: packetDataPtr.baseAddress! + MemoryLayout<Header>.size,
            count: packetDataPtr.count - MemoryLayout<Header>.size
        )
        
        return (header: header, payload: payload)
    }
    
    public static func calculateCheckSum(
        ptr: UnsafeRawBufferPointer,
        skip: Range<Int>
    ) -> UInt16 {
        var sum: UInt32 = 0
        var idx = 0
        while idx < (ptr.count - 1) {
            if skip.contains(idx) == false {
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
}

#if swift(<5.5)

let ICMP_ECHO: Int32 = 8
let ICMP6_ECHO_REQUEST: Int32 = 128
let ICMP_ECHOREPLY: Int32 = 0
let ICMP6_ECHO_REPLY: Int32 = 129
let ICMP_TIMXCEED: Int32 = 11
let ICMP6_TIME_EXCEEDED: Int32 = 3

#endif
