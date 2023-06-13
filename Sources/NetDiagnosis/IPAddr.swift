//
//  IPAddr.swift
//  
//
//  Created by Jerry on 2023/2/20.
//

import Foundation

public enum IPAddr {
    case ipv4(_: in_addr)
    case ipv6(_: in6_addr)

    public func createSockStorage(port: in_port_t = 0) -> sockaddr_storage {
        var addrStorage = sockaddr_storage()
        switch self {
        case .ipv4(let addr):
            withUnsafeMutablePointer(to: &addrStorage, { ptr in
                ptr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                    pointer.pointee.sin_family = sa_family_t(AF_INET)
                    pointer.pointee.sin_port = port
                    pointer.pointee.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
                    pointer.pointee.sin_addr = addr
                }
            })
        case .ipv6(let addr):
            withUnsafeMutablePointer(to: &addrStorage, { ptr in
                ptr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                    pointer.pointee.sin6_family = sa_family_t(AF_INET6)
                    pointer.pointee.sin6_port = port
                    pointer.pointee.sin6_len = __uint8_t(MemoryLayout<sockaddr_in6>.size)
                    pointer.pointee.sin6_addr = addr
                }
            })
        }
        return addrStorage
    }
    
    public static func create(_ addrss: String, addressFamily: AddressFamily) -> IPAddr? {
        switch addressFamily {
        case .ipv4:
            var addr = in_addr()
            if inet_pton(AF_INET, addrss, &addr) == 1 {
            return .ipv4(addr)
            }
        case .ipv6:
            var addr = in6_addr()
            if inet_pton(AF_INET6, addrss, &addr) == 1 {
            return .ipv6(addr)
            }
        }
        return nil
    }
    
    public enum AddressFamily {
        case ipv4
        case ipv6
        
        var raw: Int32 {
            switch self {
            case .ipv4:
            return AF_INET
            case .ipv6:
            return AF_INET6
            }
        }
    }
    
    public var addressFamily: AddressFamily {
        switch self {
        case .ipv4:
            return AddressFamily.ipv4
        case .ipv6:
            return AddressFamily.ipv6
        }
    }
}

extension IPAddr: Equatable {
    public static func == (lhs: IPAddr, rhs: IPAddr) -> Bool {
        switch lhs {
        case .ipv4(let lAddr):
            switch rhs {
            case .ipv4(let rAddr):
                return lAddr == rAddr
            default:
                return false
            }
        case .ipv6(let lAddr):
            switch rhs {
            case .ipv6(let rAddr):
                return lAddr == rAddr
            default:
                return false
            }
        }
    }
}

extension IPAddr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ipv4(let addr):
            return addr.description
        case .ipv6(let addr):
            return addr.description
        }
    }
}

extension IPAddr {
    public struct ResolveDomainNameError: Error {
        let code: Int32
        let msg: String?
    }

    public static func resolve(
        domainName: String, addressFamily: IPAddr.AddressFamily = .ipv4
    ) throws -> [IPAddr] {
        var res: UnsafeMutablePointer<addrinfo>?
        defer {
            freeaddrinfo(res)
        }
        
        guard let cname = domainName.cString(using: .ascii) else {
            return []
        }
        
        var hint = addrinfo()
        hint.ai_family = addressFamily.raw
        let status = getaddrinfo(cname, nil, &hint, &res)
        guard status == 0 else {
            guard let msgPtr = gai_strerror(status) else {
                throw ResolveDomainNameError.init(code: status, msg: nil)
            }
            throw ResolveDomainNameError.init(code: status, msg: String.init(cString: msgPtr))
        }
        
        let addrInfos = sequence(first: res?.pointee.ai_next) { $0?.pointee.ai_next }

        var result: [IPAddr] = []
        for addrInfo in addrInfos {
            guard let sockAddrPtr = addrInfo?.pointee.ai_addr else {
                continue
            }
            if sockAddrPtr.pointee.sa_family == AF_INET6 {
                let addr = sockAddrPtr.withMemoryRebound(
                    to: sockaddr_in6.self,
                    capacity: 1
                ) { ptr in
                    ptr.pointee.sin6_addr
                }
                result.append(.ipv6(addr))
            }
            if sockAddrPtr.pointee.sa_family == AF_INET {
                let addr = sockAddrPtr.withMemoryRebound(
                    to: sockaddr_in.self,
                    capacity: 1
                ) { ptr in
                    ptr.pointee.sin_addr
                }
                result.append(.ipv4(addr))
            }
        }
        return result
    }
}

extension sockaddr_storage {
    public func toIPAddr() -> IPAddr? {
        if self.ss_family == AF_INET {
            guard let addr = withUnsafePointer(to: self, { ptr in
                ptr.withMemoryRebound(
                    to: sockaddr_in.self, 
                    capacity: 1
                ) { addrPtr in
                    #if swift(>=5.7)
                    addrPtr.pointer(to: \sockaddr_in.sin_addr)?.pointee
                    #else
                    addrPtr.pointee.sin_addr
                    #endif
                }
            }) else {
                return nil
            }
            return .ipv4(addr)
        } else if self.ss_family == AF_INET6 {
            guard let addr = withUnsafePointer(to: self, { ptr in
                ptr.withMemoryRebound(
                    to: sockaddr_in6.self, 
                    capacity: 1
                ) { addrPtr in
                    #if swift(>=5.7)
                    addrPtr.pointer(to: \sockaddr_in6.sin6_addr)?.pointee
                    #else
                    addrPtr.pointee.sin6_addr
                    #endif           
                }
            }) else {
                return nil
            }
            return .ipv6(addr)
        }
        return nil
    }
}

extension in_addr: CustomStringConvertible {
    public var description: String {
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        return withUnsafePointer(to: self) { ptr in
            guard inet_ntop(
                AF_INET,
                ptr,
                &buffer,
                socklen_t(INET_ADDRSTRLEN)
            ) != nil else {
                return "Invalid Addr"
            }
            return String.init(cString: buffer)
        }
    }
}

extension in6_addr: CustomStringConvertible {
    public var description: String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        return withUnsafePointer(to: self) { ptr in
            guard inet_ntop(
                AF_INET6,
                ptr,
                &buffer,
                socklen_t(INET6_ADDRSTRLEN)
            ) != nil else {
                return "Invalid Addr"
            }
            return String.init(cString: buffer)
        }
    }
}

extension in_addr: Equatable {
    public static func == (lhs: in_addr, rhs: in_addr) -> Bool {
        lhs.s_addr == rhs.s_addr
    }
}

extension in6_addr: Equatable {
    public static func == (lhs: in6_addr, rhs: in6_addr) -> Bool {
        (lhs.__u6_addr.__u6_addr32.0 == rhs.__u6_addr.__u6_addr32.0) &&
        (lhs.__u6_addr.__u6_addr32.1 == rhs.__u6_addr.__u6_addr32.1) &&
        (lhs.__u6_addr.__u6_addr32.2 == rhs.__u6_addr.__u6_addr32.2) &&
        (lhs.__u6_addr.__u6_addr32.3 == rhs.__u6_addr.__u6_addr32.3)
    }
}
