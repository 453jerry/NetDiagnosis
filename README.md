# NetDiagnosis

[![swift_ver](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F453jerry%2FNetDiagnosis%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/453jerry/NetDiagnosis)
[![platform](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F453jerry%2FNetDiagnosis%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/453jerry/NetDiagnosis)

The goal of this project is to provide swift developers with a bunch of network diagnostic tools that support both IPv4 and IPv6. Currently  Ping, Traceroute, domain name resolve has been implementd.

## How to use

### Resolve domain name

```swift
// lookup ipv4 addrress
let ipv4Result = try! IPAddr.resolve(domainName: "bing.com", addressFamily: .ipv4)
for ip in ipv4Result {
    print(ip)
}
// Output:
// 13.107.21.200
// 204.79.197.200
// 204.79.197.200

// lookup ipv6 addrress
let ipv6Result = try! IPAddr.resolve(domainName: "bing.com", addressFamily: .ipv6)
for ip in ipv6Result {
    print(ip)
}
// Output:
// 2620:1ec:c11::200
```

### Ping

```swift
let remoteAddr = IPAddr.create("13.107.21.200", addressFamily: .ipv4)
// Also support IPv6 address
// let remoteAddr = IPAddr.create("2620:1ec:c11::200", addressFamily: .ipv6) 
let pinger = try! Pinger.init(remoteAddr: remoteAddr) 

pinger.ping { result in
    print(result)
}
// Output:
// pong(from: 13.107.21.200, hopLimit: 113, sequence: 0, identifier: 58577, time: 0.08944892883300781)

pinger.ping(hopLimit: 3) { result in
    print(result)
}
// Output:
// hopLimitExceeded(from: 100.96.15.65, hopLimit: 253, sequence: 1, identifier: 58577, time: 0.030148029327392578)

pinger.ping(hopLimit: 3, timeOut: 0.001) { result in
    print(result)
}
// Output:
// timeout(sequence: 2, identifier: 58577)
```

### Trace route

```swift
let remoteAddr = IPAddr.create("13.107.21.200", addressFamily: .ipv4)
// Also support IPv6 address
// let remoteAddr = IPAddr.create("2620:1ec:c11::200", addressFamily: .ipv6) 
let pinger = try! Pinger.init(remoteAddr: remoteAddr) 

pinger.trace { result, status in
    for (hop,responses) in result {
        print("hop:\(hop)")
        for response in responses {
            print(response)
        }
    }
    print("Complete Status:\(status)")
}
// Output:
//    hop:1
//    hopLimitExceeded(from: 172.20.10.1, hopLimit: 64, sequence: 3, identifier: 63182, time: 0.0032230615615844727)
//    hopLimitExceeded(from: 172.20.10.1, hopLimit: 64, sequence: 4, identifier: 63182, time: 0.0031599998474121094)
//    hopLimitExceeded(from: 172.20.10.1, hopLimit: 64, sequence: 5, identifier: 63182, time: 0.002807021141052246)
//    hop:2
//    timeout(sequence: 6, identifier: 63182)
//    timeout(sequence: 7, identifier: 63182)
//    timeout(sequence: 8, identifier: 63182)
//
//    ......
//
//    hop:13
//    hopLimitExceeded(from: 104.44.236.180, hopLimit: 243, sequence: 39, identifier: 63182, time: 0.04397702217102051)
//    hopLimitExceeded(from: 104.44.236.180, hopLimit: 243, sequence: 40, identifier: 63182, time: 0.059321045875549316)
//    hopLimitExceeded(from: 104.44.236.180, hopLimit: 243, sequence: 41, identifier: 63182, time: 0.04588794708251953)
//    hop:14
//    timeout(sequence: 42, identifier: 63182)
//    timeout(sequence: 43, identifier: 63182)
//    timeout(sequence: 44, identifier: 63182)
//    hop:15
//    timeout(sequence: 45, identifier: 63182)
//    timeout(sequence: 46, identifier: 63182)
//    timeout(sequence: 47, identifier: 63182)
//    hop:16
//    pong(from: 13.107.21.200, hopLimit: 113, sequence: 48, identifier: 63182, time: 0.0753859281539917)
//    pong(from: 13.107.21.200, hopLimit: 113, sequence: 49, identifier: 63182, time: 0.06895899772644043)
//    pong(from: 13.107.21.200, hopLimit: 113, sequence: 50, identifier: 63182, time: 0.06241798400878906)
//
//    Complete Status:traced

pinger.trace(initHop: 10, maxHop: 14, packetCount: 1) { response, hop, packetIndex, stopTrace in
    print("Hop:\(hop) packetIdx:\(packetIndex), response:\(response)")
    // If you want stop trace
    // stopTrace(true)
} onTraceComplete: { _, status in
    print("Complete Status:\(status)")
}
// Output:
// Hop:10 packetIdx:0, response:hopLimitExceeded(from: 202.97.19.94, hopLimit: 246, sequence: 3, identifier: 62186, time: 0.04130589962005615)
// Hop:11 packetIdx:0, response:hopLimitExceeded(from: 203.215.236.98, hopLimit: 244, sequence: 4, identifier: 62186, time: 0.04481005668640137)
// Hop:12 packetIdx:0, response:hopLimitExceeded(from: 104.44.235.186, hopLimit: 244, sequence: 5, identifier: 62186, time: 0.04833698272705078)
// Hop:13 packetIdx:0, response:hopLimitExceeded(from: 104.44.236.180, hopLimit: 243, sequence: 6, identifier: 62186, time: 0.041616082191467285)
// Hop:14 packetIdx:0, response:timeout(sequence: 7, identifier: 62186)
// Complete Status:maxHopExceeded
```

## RxSwfit Support

### Ping

```swift
pinger.rx.ping().subscribe { r in
    print(r)
}
.disposed(by: disposeBag)
// Output:
// success(NetDiagnosis.Pinger.PingResult.pong(NetDiagnosis.Pinger.Response(len: 64, from: 110.242.68.66, hopLimit: 51, sequence: 0, identifier: 47189, rtt: 0.03671896457672119)))
```


### Trace route

```swift
pinger.rx.trace().subscribe { r in
    print(r)
}
.disposed(by: disposeBag)

// Output:
// next(TracePacketResult(pingResult: NetDiagnosis.Pinger.PingResult.timeout(sequence: 0, identifier: 38724), hop: 1, packetIndex: 0))
// next(TracePacketResult(pingResult: NetDiagnosis.Pinger.PingResult.timeout(sequence: 1, identifier: 38724), hop: 1, packetIndex: 1))
// next(TracePacketResult(pingResult: NetDiagnosis.Pinger.PingResult.timeout(sequence: 2, identifier: 38724), hop: 1, packetIndex: 2))

//...

//next(TracePacketResult(pingResult: NetDiagnosis.Pinger.PingResult.pong(NetDiagnosis.Pinger.Response(len: 64, from: 110.242.68.66, hopLimit: 51, sequence: 48, identifier: 38724, rtt: 0.03915095329284668)), hop: 17, packetIndex: 0))
// next(TracePacketResult(pingResult: NetDiagnosis.Pinger.PingResult.pong(NetDiagnosis.Pinger.Response(len: 64, from: 110.242.68.66, hopLimit: 51, sequence: 49, identifier: 38724, rtt: 0.03501296043395996)), hop: 17, packetIndex: 1))
// next(TracePacketResult(pingResult: NetDiagnosis.Pinger.PingResult.pong(NetDiagnosis.Pinger.Response(len: 64, from: 110.242.68.66, hopLimit: 51, sequence: 50, identifier: 38724, rtt: 0.03649783134460449)), hop: 17, packetIndex: 2))
// completed



```
