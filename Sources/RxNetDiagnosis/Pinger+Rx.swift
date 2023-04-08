//
//  Pinger+Rx.swift
//  
//
//  Created by Jerry on 2023/4/1.
//

import Foundation
import NetDiagnosis
import RxSwift

extension Reactive where Base: Pinger {
    
    public func ping(
        payload: Data? = nil,
        hopLimit: UInt8? = nil,
        timeOut: TimeInterval = 1.0
    ) -> Single<Pinger.Response> {

        return Single<Pinger.Response>.create { single in
            base.ping(payload: payload, hopLimit: hopLimit, timeOut: timeOut) { result in
                switch (result) {
                case .pong, .hopLimitExceeded, .timeout:
                    single(.success(result))
                case .failed(let error):
                    single(.failure(error))
                    break
                }
            }
            return Disposables.create()
        }
        .observe(on: MainScheduler())
    }
}
