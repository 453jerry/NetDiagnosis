//
//  Pinger+Trace.swift
//  
//
//  Created by Jerry on 2023/2/22.
//

import Foundation
import OrderedCollections

extension Pinger {
    public typealias TraceResponseCallback = (
        _ response: Response,
        _ hop: UInt8,
        _ packetIndex: UInt8,
        _ stopTrace: (_: Bool) -> Void
    ) -> Void
    
    public enum TraceStatus {
        case traced
        case maxHopExceeded
        case stoped
        case failed(_: Error)
    }
    
    public func trace(
        payload: Data? = nil,
        initHop: UInt8 = 1,
        maxHop: UInt8 = 64,
        packetCount: UInt8 = 3,
        timeOut: TimeInterval = 1.0,
        onTraceResponse: TraceResponseCallback? = nil,
        onTraceComplete: @escaping (
            _ result: OrderedDictionary<UInt8, [Response]>,
            _ status: TraceStatus
        ) -> Void
    ) {
        // swiftlint: disable closure_body_length
        self.serailQueue.async {
            var traceResult: OrderedDictionary<UInt8, [Response]> = [:]
            for hopLimit in initHop ... maxHop {
                for packetIdx in 0 ..< packetCount {
                    let result = self.ping(
                        payload: payload,
                        hopLimit: hopLimit,
                        timeOut: timeOut
                    )
                    var results = traceResult[hopLimit] ?? []
                    results.append(result)
                    traceResult[hopLimit] = results
                    var isStop = false
                    onTraceResponse?(result, hopLimit, packetIdx) { isStop = $0 }
                    switch result {
                    case .pong:
                        if packetIdx == packetCount - 1 {
                            onTraceComplete(traceResult, .traced)
                            return
                        }
                    case .failed(let error):
                        onTraceComplete(traceResult, .failed(error))
                        return
                    default: 
                        break
                    }
                    if isStop {
                        onTraceComplete(traceResult, .stoped)
                        return
                    }
                }
            }
            onTraceComplete(traceResult, .maxHopExceeded)
        }
    }
}
