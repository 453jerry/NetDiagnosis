//
//  Pinger.swift
//  
//
//  Created by Jerry on 2023/2/4.
//

import Darwin
import Foundation

// swiftlint: disable type_body_length force_unwrapping function_body_length
public class Pinger {
    public struct Response {
        public var len: Int
        public var from: IPAddr
        public var hopLimit: UInt8
        public var sequence: UInt16
        public var identifier: UInt16
        public var rtt: TimeInterval
    }
    
    public enum PingResult {
        case pong(_: Response)
        case hopLimitExceeded(_: Response)
        case timeout(sequence: UInt16, identifier: UInt16)
        case failed(_: Error)
    }
    
    public typealias PingCallback = (_ result: PingResult) -> Void

    public let icmpIdentifier = UInt16.random(in: 1..<UInt16.max)
    var icmpSequence: UInt16 = 0
    
    public let remoteAddr: IPAddr
    let sock: Int32
    let serailQueue = DispatchQueue(label: "Pinger Queue", qos: .userInteractive)
        
    public init(
        remoteAddr: IPAddr
    ) throws {
        self.remoteAddr = remoteAddr
        self.sock = socket(
            Int32(self.remoteAddr.addressFamily.raw),
            SOCK_DGRAM,
            {
                switch remoteAddr {
                case .ipv4:
                    return IPPROTO_ICMP
                case .ipv6:
                    return IPPROTO_ICMPV6
                }
            }()
        )
        guard self.sock > 0 else {
            throw POSIXError.init(POSIXErrorCode.init(rawValue: errno)!)
        }
        try self.setReceiveHopLimit(true)
    }

    deinit {
        close(sock)
    }

    public func ping(
        packetSize: Int? = nil,
        hopLimit: UInt8? = nil,
        timeOut: TimeInterval = 1.0,
        callback: @escaping PingCallback
    ) {
        self.serailQueue.async {
            let result = self.ping(packetSize: packetSize, hopLimit: hopLimit, timeOut: timeOut)
            callback(result)
        }
    }

    func ping(
        packetSize: Int?,
        hopLimit: UInt8?,
        timeOut: TimeInterval
    ) -> PingResult {
        // setup
        let currentID = self.icmpIdentifier
        let currentSeq = self.icmpSequence
        
        do {
            
            var begin = Date.init()
            var timeLeft = timeOut
            // send
            try send(
                icmpIdentifier: currentID,
                icmpSeq: currentSeq,
                hopLimit: hopLimit,
                packetSize: packetSize
            )
            self.icmpSequence += 1
            timeLeft -= Date().timeIntervalSince(begin)
            
            // Receive
            try self.setReceiveTimeout(timeOut)
            repeat {
                if timeLeft <= 0 {
                    return .timeout(
                        sequence: currentSeq,
                        identifier: currentID
                    )
                } else {
                    try self.setReceiveTimeout(timeLeft)
                }
                
                var cmsgBuffer = [UInt8](
                    repeating: 0,
                    count: (MemoryLayout<cmsghdr>.size) + MemoryLayout<UInt32>.size
                )
                var recvBuffer = [UInt8](repeating: 0, count: 1024)
                var srcAddr = sockaddr_storage()
                
                begin = Date.init()
                let receivedCount = try receive(
                    recvBuffer: &recvBuffer,
                    cmsgBuffer: &cmsgBuffer,
                    srcAddr: &srcAddr
                )
                timeLeft -= Date().timeIntervalSince(begin)
                
                // Get HopLimit/TTL, SrcAddr, ICMP packet
                guard let hopLimit = cmsgBuffer.withUnsafeBytes({ ptr in
                    getHopLimit(
                        cmsgBufferPtr: UnsafeRawBufferPointer.init(
                            start: ptr.baseAddress,
                            count: Int(cmsgBuffer.count)
                        )
                    )
                }),
                let srcAddr = srcAddr.toIPAddr(),
                let icmpPacketPtr = recvBuffer.withUnsafeBytes({ ptr in
                    switch self.remoteAddr.addressFamily {
                    case .ipv4:
                        return getICMPPacketPtr(
                            ipPacketPtr: UnsafeRawBufferPointer.init(
                                start: ptr.baseAddress,
                                count: receivedCount
                            )
                        )
                    case .ipv6:
                        return ptr
                    }
                }) else {
                    continue
                }
                
                if verify(
                    icmpPacketPtr: icmpPacketPtr,
                    expectedIdentifier: currentID,
                    expectedSequence: currentSeq
                ) == false {
                    continue
                }
                
                let icmpHeaderPtr = icmpPacketPtr.bindMemory(to: icmp6_hdr.self)
                let response = Response(
                    len: icmpPacketPtr.count,
                    from: srcAddr,
                    hopLimit: hopLimit,
                    sequence: currentSeq,
                    identifier: currentID,
                    rtt: timeOut - timeLeft
                )
                if icmpHeaderPtr[0].icmp6_type == icmpTypeHopLimitExceeded {
                    return .hopLimitExceeded(response)
                } else if icmpHeaderPtr[0].icmp6_type == icmpTpeEchoReplay &&
                    srcAddr == self.remoteAddr {
                    return .pong(response)
                }
            }
            while(true)
        } catch let error {
            // receive time out
            if (error as? POSIXError)?.code == POSIXError.EAGAIN {
                return.timeout(
                    sequence: currentSeq,
                    identifier: currentID
                )
            }
            return .failed(error)
        }
    }
    
    func send(
        icmpIdentifier: UInt16,
        icmpSeq: UInt16,
        hopLimit: UInt8? = nil,
        packetSize: Int? = nil
    ) throws {
        if let hopLimit = hopLimit {
            try self.setHopLimit(UInt32(hopLimit))
        }
        let packetData = self.createEchoRequestPacket(
            identifier: icmpIdentifier,
            sequence: icmpSeq,
            packetSize: packetSize
        )
        
        let sentCount = packetData.withUnsafeBytes { packetPtr in
            let addrStorage = self.remoteAddr.createSockStorage()
            return withUnsafePointer(to: addrStorage) { addrPtr in
                addrPtr.withMemoryRebound(
                    to: sockaddr.self,
                    capacity: 1
                ) { addrPtr in
                    sendto(
                        self.sock,
                        packetPtr.baseAddress!,
                        packetPtr.count,
                        0,
                        addrPtr,
                        socklen_t(addrPtr.pointee.sa_len)
                    )
                }
            }
        }
        if sentCount == -1 {
            throw POSIXError.init(POSIXErrorCode.init(rawValue: errno)!)
        }
    }
    
    func receive(
        recvBuffer: inout [UInt8],
        cmsgBuffer: inout [UInt8],
        srcAddr: inout sockaddr_storage
    ) throws -> Int {
        var iov = iovec(
            iov_base: recvBuffer.withUnsafeMutableBytes { $0.baseAddress },
            iov_len: recvBuffer.count
        )

        var msghdr = msghdr(
            msg_name: withUnsafeMutablePointer(to: &srcAddr) { $0 },
            msg_namelen: socklen_t( MemoryLayout.size(ofValue: srcAddr)),
            msg_iov: withUnsafeMutablePointer(to: &iov) { $0 },
            msg_iovlen: 1,
            msg_control: cmsgBuffer.withUnsafeMutableBytes { $0.baseAddress },
            msg_controllen: socklen_t(cmsgBuffer.count),
            msg_flags: 0
        )
        
        let receivedCount = withUnsafeMutablePointer(to: &msghdr) { ptr in
            recvmsg(self.sock, ptr, 0)
        }
        guard receivedCount >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
        return receivedCount
    }

    // MARK: - Parse received data & control msg
    func getHopLimit(cmsgBufferPtr: UnsafeRawBufferPointer) -> UInt8? {
        let cmsghdrPtr = cmsgBufferPtr.bindMemory(to: cmsghdr.self)
        if cmsghdrPtr[0].cmsg_level == self.ipProtocol &&
            cmsghdrPtr[0].cmsg_type == self.receiveHopLimitOption {
            return cmsgBufferPtr.load(
                fromByteOffset: MemoryLayout<cmsghdr>.size,
                as: UInt8.self
            )
        } else {
            return nil
        }
    }
    
    func verify(
        icmpPacketPtr: UnsafeRawBufferPointer,
        expectedIdentifier: UInt16,
        expectedSequence: UInt16
    ) -> Bool {
        let icmpHeaderSize = MemoryLayout<icmp6_hdr>.size
        let icmpHeaderPtr = icmpPacketPtr.bindMemory(to: icmp6_hdr.self)
        if icmpHeaderPtr[0].icmp6_type == self.icmpTypeHopLimitExceeded {
            let payloadPtr = UnsafeRawBufferPointer.init(
                rebasing: Slice.init(
                    base: icmpPacketPtr,
                    bounds: icmpHeaderSize ..< icmpPacketPtr.count
                )
            )
            guard let echoRequestPacketPtr = getICMPPacketPtr(ipPacketPtr: payloadPtr) else {
                return false
            }
            let echoRequestHeader = echoRequestPacketPtr.bindMemory(to: icmp6_hdr.self)
            return echoRequestHeader[0].icmp6_type == self.icmpTypeEchoRequst &&
            echoRequestHeader[0].icmp6_dataun.icmp6_un_data16.0 == expectedIdentifier &&
            echoRequestHeader[0].icmp6_dataun.icmp6_un_data16.1 == expectedSequence
        }
        return icmpHeaderPtr[0].icmp6_type == self.icmpTpeEchoReplay &&
        icmpHeaderPtr[0].icmp6_dataun.icmp6_un_data16.0 == expectedIdentifier
        && icmpHeaderPtr[0].icmp6_dataun.icmp6_un_data16.1 == expectedSequence
    }
    
    func getICMPPacketPtr(ipPacketPtr: UnsafeRawBufferPointer) -> UnsafeRawBufferPointer? {
        guard let ipVer = {
            let ver: UInt8 = (ipPacketPtr[0] & 0xF0) >> 4
            if ver == 0x04 {
                return IPAddr.AddressFamily.ipv4
            } else if ver == 0x06 {
                return IPAddr.AddressFamily.ipv6
            }
            return nil
        }() else {
            return nil // Neither IPv4 nor IPv6
        }
        
        switch ipVer {
        case .ipv4:
            let ipv4Ptr = ipPacketPtr.bindMemory(to: ip.self)
            if ipv4Ptr[0].ip_p == IPPROTO_ICMP {
                return UnsafeRawBufferPointer.init(
                    rebasing: Slice.init(
                        base: ipPacketPtr,
                        bounds: Int(ipv4Ptr[0].ip_hl * 4) ..< ipPacketPtr.count
                    )
                )
            }
        case .ipv6:
            let ipv6Ptr = ipPacketPtr.bindMemory(to: ip6_hdr.self)
            if ipv6Ptr[0].ip6_ctlun.ip6_un1.ip6_un1_nxt == IPPROTO_ICMPV6 {
                // Not Support extension header
                // Header length of IPv6 packet is fix value
                return UnsafeRawBufferPointer.init(
                    rebasing: Slice.init(
                        base: ipPacketPtr,
                        bounds: 40 ..< ipPacketPtr.count
                    )
                )
            }
        }
        return nil
    }
    
    func createEchoRequestPacket(
        identifier: UInt16,
        sequence: UInt16,
        packetSize: Int?
    ) -> Data {
        let packetSize = packetSize ?? 64
        
        let icmpHeaderSize = MemoryLayout<icmp6_hdr>.size
        assert(packetSize > icmpHeaderSize)
        
        var packetData = Data.init(
            repeating: 0,
            count: packetSize
        )
        for idx in icmpHeaderSize ..< packetData.count {
            packetData[idx] = UInt8.random(in: 0x21 ... 0x7E) // ASCII printable characters
        }
        
        var time = Date.init().timeIntervalSince1970.toTimeValue()
        let timeSize = MemoryLayout.size(ofValue: time)
        if packetData.count >= (icmpHeaderSize + timeSize) {
            packetData.replaceSubrange(
                Range.init(icmpHeaderSize ... (icmpHeaderSize + timeSize - 1)),
                with: &time,
                count: timeSize
            )
        }
        
        packetData.withUnsafeMutableBytes { rawPtr in
            let icmpHeaddrPtr = rawPtr.bindMemory(to: icmp6_hdr.self)
            icmpHeaddrPtr[0].icmp6_type = UInt8(self.icmpTypeEchoRequst)
            icmpHeaddrPtr[0].icmp6_code = 0
            icmpHeaddrPtr[0].icmp6_cksum = 0
            icmpHeaddrPtr[0].icmp6_dataun.icmp6_un_data16 = (
                identifier,
                sequence
            )
            icmpHeaddrPtr[0].icmp6_cksum = rawPtr.withUnsafeBytes { ptr in
                checkSum(ptr: ptr)
            }
        }
        
        return packetData
    }
}
