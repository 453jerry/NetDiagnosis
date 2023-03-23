# NetDiagnosis

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
//pong(from: 13.107.21.200, hopLimit: 113, sequence: 0, identifier: 58577, time: 0.08944892883300781)

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
