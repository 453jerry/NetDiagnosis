//
//  Pinger+Rx.swift
//
//
//  Created by Jerry on 2023/4/1.
//

import Foundation
import NetDiagnosis
import RxSwift

extension Pinger: ReactiveCompatible {}

extension Reactive where Base: Pinger {
    
    public func ping(
        packetSize: Int? = nil,
        hopLimit: UInt8? = nil,
        timeOut: TimeInterval = 1.0
    ) -> Single<Pinger.PingResult> {
        Single<Pinger.PingResult>.create { single in
            base.ping(packetSize: packetSize, hopLimit: hopLimit, timeOut: timeOut) { result in
                switch result {
                case .pong, .hopLimitExceeded, .timeout:
                    single(.success(result))
                case .failed(let error):
                    single(.failure(error))
                }
            }
            return Disposables.create()
        }
        .observe(on: MainScheduler())
    }
    
    public func trace(
        packetSize: Int? = nil,
        initHop: UInt8 = 1,
        maxHop: UInt8 = 64,
        packetCount: UInt8 = 3,
        timeOut: TimeInterval = 1.0
    ) -> Observable<Pinger.TracePacketResult> {
        Observable<Pinger.TracePacketResult>.create { observer in
            var isStop = false
            base.trace(
                packetSize: packetSize,
                initHop: initHop,
                maxHop: maxHop,
                packetCount: packetCount,
                timeOut: timeOut,
                tracePacketCallback: { trackPacketResult, stopTrace in
                    observer.onNext(trackPacketResult)
                    stopTrace(isStop)
                },
                onTraceComplete: { _, _ in
                    observer.onCompleted()
                }
            )

            return Disposables.create {
                isStop = true
            }
        }
    }
}
