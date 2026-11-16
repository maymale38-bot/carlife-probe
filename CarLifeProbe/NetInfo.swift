import Foundation
import Darwin

/// 取本机 Wi-Fi 接口的 IPv4。
/// 开「个人热点」时通常拿到 172.20.10.1，车机连上热点后要连的就是这个地址。
enum NetInfo {
    static func wifiIPv4() -> String {
        var result = "—"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr else { continue }
            guard address.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            // en0 = Wi-Fi。热点/普通 Wi-Fi 都走它；其他 en* 作为兜底
            guard name == "en0" || name.hasPrefix("en") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let code = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if code == 0 {
                let value = String(cString: hostname)
                if name == "en0" { return value }
                if result == "—" { result = value }
            }
        }

        return result
    }
}
