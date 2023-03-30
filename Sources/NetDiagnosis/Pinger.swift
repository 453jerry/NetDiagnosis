//
//  Pinger.swift
//  
//
//  Created by Jerry on 2023/2/4.
//

import Foundation

// swiftlint: disable file_length
public class Pinger {
    
    var icmpHeader: ICMP.Header = ICMP.Header.init(
        type: 0,
        code: 0,
        identifier: UInt16.random(in: 1..<UInt16.max),
        sequenceNumber: 0
    )
    
    public var icmpIdentifier: UInt16 {
        icmpHeader.identifier
    }
    
    public let remoteAddr: IPAddr
    let socket: Int32
    let serailQueue = DispatchQueue(label: "Pinger Queue", qos: .userInteractive)
        
    public init(
        remoteAddr: IPAddr
    ) throws {
        self.remoteAddr = remoteAddr
        self.socket = Darwin.socket(
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
        guard self.socket > 0 else {
            // swiftlint:disable force_unwrapping
            throw POSIXError.init(POSIXErrorCode.init(rawValue: errno)!)
        }
        
        self.icmpHeader.type = UInt8(self.icmpEqualRequstType)
        
        var hopLimitOption: UInt32 = 1
        guard setsockopt(
            self.socket,
            self.ipProtocol,
            self.receiveHopLimitOption,
            &hopLimitOption,
            socklen_t(MemoryLayout.size(ofValue: hopLimitOption))
        ) == 0 else {
            // swiftlint:disable force_unwrapping
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
    }
    
    public func ping(
        payload: Data? = nil,
        hopLimit: UInt8? = nil,
        timeOut: TimeInterval = 1.0,
        callback: @escaping PingCallback
    ) {
        self.serailQueue.async {
            let result = self.ping(payload: payload, hopLimit: hopLimit, timeOut: timeOut)
            callback(result)
        }
    }
    
    // swiftlint: disable function_body_length
    func ping(
        payload: Data?,
        hopLimit: UInt8?,
        timeOut: TimeInterval
    ) -> Response {
        // setup
        let currentIdentififer = self.icmpHeader.identifier
        let currentSeq = self.icmpHeader.sequenceNumber
        
        do {
            try self.setTimeout(timeOut)
            var begin = Date.init()
            var timeLeft = timeOut
            
            // send
            try send(payload: payload, hopLimit: hopLimit)
            self.icmpHeader.sequenceNumber += 1
            
            // Receive
            repeat {
                if timeLeft <= 0 {
                    return .timeout(
                        sequence: currentSeq,
                        identifier: currentIdentififer
                    )
                } else if timeLeft < timeOut {
                    try self.setTimeout(timeLeft)
                    begin = Date.init()
                }
                
                var cmsgBuffer = [UInt8](
                    repeating: 0,
                    count: (MemoryLayout<cmsghdr>.size) + MemoryLayout<UInt32>.size
                )
                var recvBuffer = [UInt8](repeating: 0, count: 1024)
                var srcAddr = sockaddr_storage()
                var cmsgLen = socklen_t(cmsgBuffer.count)
                
                let receivedCount = try receive(
                    recvBuffer: &recvBuffer,
                    cmsgBuffer: &cmsgBuffer,
                    cmsgLen: &cmsgLen,
                    srcAddr: &srcAddr
                )
                
                timeLeft -= Date().timeIntervalSince(begin)
                
                // parse
                let icmpPacket = recvBuffer.withUnsafeBufferPointer { ptr in
                    parse(
                        receiveBufferPtr: UnsafeRawBufferPointer.init(
                            start: ptr.baseAddress,
                            count: receivedCount
                        )
                    )
                }

                // Get HopLimit/TTL
                let hopLimit = cmsgBuffer.withUnsafeBytes { ptr in
                    getHopLimit(
                        cmsgBufferPtr: UnsafeRawBufferPointer.init(
                            start: ptr.baseAddress,
                            count: Int(cmsgLen)
                        )
                    )
                }

                guard let icmpPacket = icmpPacket,
                    let hopLimit = hopLimit,
                    let srcAddr = srcAddr.toIPAddr() else {
                    continue
                }

                guard verifyICMPPacket(
                    icmpPacket,
                    expectedSequence: currentSeq,
                    expectedIdentifier: currentIdentififer
                ) == true else {
                    continue
                }
                
                if icmpPacket.header.type == icmpHopLimitExceeded {
                    return .hopLimitExceeded(
                        from: srcAddr,
                        hopLimit: hopLimit,
                        sequence: currentSeq,
                        identifier: currentIdentififer,
                        time: timeOut - timeLeft
                    )
                } else if icmpPacket.header.type == icmpEqualReplayType &&
                srcAddr == self.remoteAddr {
                    return .pong(
                        from: srcAddr,
                        hopLimit: hopLimit,
                        sequence: currentSeq,
                        identifier: currentIdentififer,
                        time: timeOut - timeLeft
                    )
                }
            }
            while(true)
        } catch let error {
            // receive time out
            if (error as? POSIXError)?.code == POSIXError.EAGAIN {
                return.timeout(
                    sequence: currentSeq,
                    identifier: currentIdentififer
                )
            }
            return .failed(error)
        }
    }
    
    func send(payload: Data?, hopLimit: UInt8?) throws {
        if let hopLimit = hopLimit {
            try self.setHopLimit(UInt32(hopLimit))
        }
        let packetData = ICMP.createPacketData(
            with: self.icmpHeader,
            payload: payload ?? Self.createRandomPayload(len: 100)
        )
        
        let sentCount = packetData.withUnsafeBytes { packetPtr -> ssize_t in
            let addrStorage = self.remoteAddr.createSockStorage()
            return withUnsafePointer(to: addrStorage) { addrPtr in
                addrPtr.withMemoryRebound(
                    to: sockaddr.self,
                    capacity: 1
                ) { addrPtr in
                    sendto(
                        self.socket,
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
            // swiftlint:disable force_unwrapping
            throw POSIXError.init(POSIXErrorCode.init(rawValue: errno)!)
        }
    }
    
    func receive(
        recvBuffer: inout [UInt8],
        cmsgBuffer: inout [UInt8],
        cmsgLen: inout socklen_t,
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
            msg_controllen: cmsgLen,
            msg_flags: 0
        )
        
        let receivedCount = withUnsafeMutablePointer(to: &msghdr) { ptr in
            recvmsg(self.socket, ptr, 0)
        }
        guard receivedCount >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
        return receivedCount
    }

    public static func createRandomPayload(len: Int) -> Data {
        var data = Data.init(count: len)
        
        for idx in 0 ..< len {
            data[idx] = UInt8.random(in: 1 ... 255)
        }
        return data
    }
    
    deinit {
        shutdown(self.socket, SHUT_RDWR)
        close(self.socket)
    }
}

// MARK: - Response & Callback type
extension Pinger {
    // swiftlint: disable enum_case_associated_values_count
    public enum Response {
        case pong(
            from: IPAddr,
            hopLimit: UInt8,
            sequence: UInt16,
            identifier: UInt16,
            time: TimeInterval
        )
        case hopLimitExceeded(
            from: IPAddr,
            hopLimit: UInt8,
            sequence: UInt16,
            identifier: UInt16,
            time: TimeInterval
        )
        case timeout(sequence: UInt16, identifier: UInt16)
        case failed(_: Error)
    }
    
    public typealias PingCallback = (_ result: Response) -> Void
}

// MARK: - Properties
extension Pinger {
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
    
    var icmpEqualRequstType: Int32 {
        switch self.remoteAddr.addressFamily {
        case .ipv4:
            return ICMP_ECHO
        case .ipv6:
            return ICMP6_ECHO_REQUEST
        }
    }
    
    var icmpEqualReplayType: Int32 {
        switch self.remoteAddr.addressFamily {
        case .ipv4:
            return ICMP_ECHOREPLY
        case .ipv6:
            return ICMP6_ECHO_REPLY
        }
    }
    
    var icmpHopLimitExceeded: Int32 {
        switch self.remoteAddr.addressFamily {
        case .ipv4:
            return ICMP_TIMXCEED
        case .ipv6:
            return ICMP6_TIME_EXCEEDED
        }
    }
}

// MARK: - Set socket options
extension Pinger {
    func setTimeout(_ time: TimeInterval) throws {
        let timeVal = time.toTimeVal()
        let code = withUnsafePointer(to: timeVal) { ptr in
            setsockopt(
                self.socket,
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
                self.socket,
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
}

// MARK: - Parse received data & cmsg
extension Pinger {
    func getICMPPacketPtr(ipPacketPtr: UnsafeRawBufferPointer) -> UnsafeRawBufferPointer? {
        guard let ipVer = { () -> IPAddr.AddressFamily? in
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
        
        let headerLen = { () -> Int in
            switch ipVer {
            case .ipv4:
                return Int((ipPacketPtr[0] & 0x0F) * 4)
            case .ipv6:
                return 40 // Header length of IPv6 packet is fix value
            }
        }()
        
        let `protocol`: UInt32 = {
            switch ipVer {
            case .ipv6:
                return UInt32(ipPacketPtr.load(fromByteOffset: 6, as: UInt8.self))
            case .ipv4:
                return UInt32(ipPacketPtr.load(fromByteOffset: 9, as: UInt8.self))
            }
        }()
        
        guard `protocol` == IPPROTO_ICMP || `protocol` == IPPROTO_ICMPV6 else {
            return nil
        }
       
        let icmpPacketPtr = UnsafeRawBufferPointer.init(
            rebasing: Slice.init(
                base: ipPacketPtr,
                bounds: headerLen ..< ipPacketPtr.count
            )
        )
        return icmpPacketPtr
    }
    
    func getHopLimit(cmsgBufferPtr: UnsafeRawBufferPointer) -> UInt8? {
        let cmsghdrPtr = UnsafePointer<cmsghdr>.init(
            OpaquePointer.init(cmsgBufferPtr.baseAddress)
        )
        if cmsghdrPtr?.pointee.cmsg_level == self.ipProtocol &&
            cmsghdrPtr?.pointee.cmsg_type == self.receiveHopLimitOption {
            return cmsgBufferPtr.load(
                fromByteOffset: MemoryLayout<cmsghdr>.size,
                as: UInt8.self
            )
        } else {
            return nil
        }
    }
    
    typealias ICMPPacket = (header: ICMP.Header, payload: Data)
    
    func parse(
        receiveBufferPtr: UnsafeRawBufferPointer
    ) -> ICMPPacket? {
        guard let icmpPacketPtr = { () -> UnsafeRawBufferPointer? in
            switch self.remoteAddr.addressFamily {
            case .ipv4:
                return getICMPPacketPtr(ipPacketPtr: receiveBufferPtr)
            case .ipv6:
                return receiveBufferPtr
            }
        }() else {
            return nil
        }
        return ICMP.create(frome: icmpPacketPtr)
    }

    func verifyICMPPacket(
        _ icmpPacket: ICMPPacket,
        expectedSequence: UInt16,
        expectedIdentifier: UInt16
    ) -> Bool {
        guard icmpPacket.header.type != icmpEqualReplayType ||
            icmpPacket.header.type != icmpHopLimitExceeded ||
            icmpPacket.header.code != 0 else {
            return false
        }
        
        if icmpPacket.header.type == icmpHopLimitExceeded {
            let originICMPPtr = icmpPacket.payload.withUnsafeBytes { ptr in
                getICMPPacketPtr(ipPacketPtr: ptr)
            }
            guard let originICMPPtr = originICMPPtr else {
                return false
            }
            // Get origin icmp packet
            let originICMPPacket = ICMP.create(frome: originICMPPtr)
            return originICMPPacket.header.identifier == expectedIdentifier &&
            originICMPPacket.header.sequenceNumber == expectedSequence
        } else {
            return  icmpPacket.header.identifier == expectedIdentifier &&
            icmpPacket.header.sequenceNumber == expectedSequence
        }
    }
}

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
}
