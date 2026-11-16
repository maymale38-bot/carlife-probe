import Foundation
import SwiftUI

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let port: UInt16
    let arrow: String
    let title: String
    let payloadHex: String
    let byteCount: Int
}

final class ProbeModel: ObservableObject {

    @Published var entries: [LogEntry] = []
    @Published var listeningPorts: Set<UInt16> = []
    @Published var portErrors: [UInt16: String] = [:]
    @Published var localIP: String = "—"
    @Published var inboundTotal: Int = 0
    @Published var activeConnections: Int = 0
    @Published var autoReply: Bool = true {
        didSet { server.autoReplyVersion = autoReply }
    }

    private let server = CarLifeServer()
    private var ipTimer: Timer?
    private var started = false
    private let maxEntries = 1200

    func start() {
        guard !started else { return }
        started = true

        server.autoReplyVersion = autoReply
        server.onEvent = { [weak self] event in
            self?.handle(event)
        }
        server.start()

        refreshIP()
        ipTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshIP()
        }
    }

    func clear() {
        entries.removeAll()
        inboundTotal = 0
    }

    /// 导出完整日志：离车后把这串文本发出来，就能反推协议
    func exportText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        var lines: [String] = []
        lines.append("# CarLife Prober 日志")
        lines.append("# 导出时间 \(Date())")
        lines.append("# 本机 IP \(localIP)")
        lines.append("# 监听端口 \(CarLifeServer.ports.map { String($0) }.joined(separator: ","))")
        lines.append("#")

        for entry in entries {
            let time = formatter.string(from: entry.date)
            let port = "\(entry.port)(\(MessageCatalog.portName(entry.port)))"
            if entry.byteCount == 0 && entry.payloadHex.isEmpty {
                lines.append("[\(time)] \(port) \(entry.arrow) \(entry.title)")
            } else {
                lines.append("[\(time)] \(port) \(entry.arrow) \(entry.title) | \(entry.byteCount)B | \(entry.payloadHex)")
            }
        }

        return lines.joined(separator: "\n")
    }

    func exportFileURL() -> URL? {
        let name = "CarLifeProbe-log.txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try exportText().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - 事件处理

    private func handle(_ event: CarLifeServer.Event) {
        switch event {
        case .listening(let port):
            listeningPorts.insert(port)
            portErrors[port] = nil
            appendSystem(port: port, text: "端口监听中")

        case .listenFailed(let port, let message):
            portErrors[port] = message
            appendSystem(port: port, text: "监听失败：" + message)

        case .connected(let port, let remote):
            activeConnections += 1
            appendSystem(port: port, text: "车机已连接 ← \(remote)")

        case .closed(let port, let message):
            activeConnections = max(0, activeConnections - 1)
            appendSystem(port: port, text: message)

        case .inbound(let port, let frame):
            inboundTotal += 1
            append(
                LogEntry(
                    date: Date(),
                    port: port,
                    arrow: "←",
                    title: frame.typeName + " (" + frame.typeHex + ")",
                    payloadHex: frame.payloadPreview,
                    byteCount: frame.payload.count
                )
            )

        case .outbound(let port, let type, let data):
            append(
                LogEntry(
                    date: Date(),
                    port: port,
                    arrow: "→",
                    title: "已答复 " + MessageCatalog.name(for: type) + " (" + String(format: "0x%08X", type) + ")",
                    payloadHex: data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " "),
                    byteCount: data.count
                )
            )

        case .anomaly(let port, let count):
            appendSystem(port: port, text: "帧对齐异常 ×\(count)")
        }
    }

    private func appendSystem(port: UInt16, text: String) {
        append(
            LogEntry(
                date: Date(),
                port: port,
                arrow: "·",
                title: text,
                payloadHex: "",
                byteCount: 0
            )
        )
    }

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    private func refreshIP() {
        localIP = NetInfo.wifiIPv4()
    }
}
