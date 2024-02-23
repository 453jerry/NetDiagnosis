//
//  Pinger+Trace.swift
//  
//
//  Created by Jerry on 2023/2/22.
//

import Foundation
import OrderedCollections

extension Pinger {
    public enum TraceStatus {
        case traced
        case maxHopExceeded
        case stoped
        case failed(_: Error)
    }
    
    public struct TracePacketResult {
        public var pingResult: PingResult
        public var hop: UInt8
        public var packetIndex: UInt8
    }
    
    public func trace(
        packetSize: Int? = nil,
        initHop: UInt8 = 1,
        maxHop: UInt8 = 64,
        packetCount: UInt8 = 3,
        timeOut: TimeInterval = 1.0,
        tracePacketCallback: ((
            _ packetResult: TracePacketResult,
            _ stopTrace: (_: Bool) -> Void
        ) -> Void)?,
        onTraceComplete: ((
            _ result: OrderedDictionary<UInt8, [PingResult]>,
            _ status: TraceStatus
        ) -> Void)?
    ) {
        // swiftlint: disable closure_body_length
        self.serailQueue.async {
            var traceResults: OrderedDictionary<UInt8, [PingResult]> = [:]
            for hopLimit in initHop ... maxHop {
                for packetIdx in 0 ..< packetCount {
                    let pingResult = self.ping(
                        packetSize: packetSize,
                        hopLimit: hopLimit,
                        timeOut: timeOut
                    )
                    var hopResults = traceResults[hopLimit] ?? []
                    hopResults.append(pingResult)
                    traceResults[hopLimit] = hopResults
                    var isStop = false
                    let packetResult = TracePacketResult.init(
                        pingResult: pingResult,
                        hop: hopLimit,
                        packetIndex: packetIdx
                    )
                    tracePacketCallback?(packetResult) { isStop = $0 }
                    switch pingResult {
                    case .pong:
                        if packetIdx == packetCount - 1 {
                            onTraceComplete?(traceResults, .traced)
                            return
                        }
                    case .failed(let error):
                        onTraceComplete?(traceResults, .failed(error))
                        return
                    default: 
                        break
                    }
                    if isStop {
                        onTraceComplete?(traceResults, .stoped)
                        return
                    }
                }
            }
            onTraceComplete?(traceResults, .maxHopExceeded)
        }
    }
}
