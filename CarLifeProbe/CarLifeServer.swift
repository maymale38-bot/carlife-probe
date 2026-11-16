import Foundation
import Network

/// 同时监听 CarLife 的 7 个 TCP 端口，把车机连上来后的每一条报文原样暴露出来。
/// 车机永远是 TCP 客户端，手机永远是服务端 —— 方向做反了就连不上。
final class CarLifeServer {

    static let ports: [UInt16] = [7240, 8240, 9240, 9241, 9242, 9340, 9440]

    enum Event {
        case listening(UInt16)
        case listenFailed(UInt16, String)
        case connected(UInt16, String)
        case closed(UInt16, String)
        case inbound(UInt16, ParsedFrame)
        case outbound(UInt16, UInt32, Data)
        case anomaly(UInt16, Int)
    }

    var onEvent: ((Event) -> Void)?

    /// 是否自动答复版本协商。P0 阶段只回这一条，其他一律不答，目的是观察车机的原始行为。
    var autoReplyVersion = true

    private let queue = DispatchQueue(label: "carlife.probe.server", qos: .userInitiated)
    private var listeners: [UInt16: NWListener] = [:]
    private var decoders: [ObjectIdentifier: FrameDecoder] = [:]
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var reportedAnomalies: [ObjectIdentifier: Int] = [:]

    // MARK: - 监听

    func start() {
        for port in Self.ports {
            start(port: port)
        }
    }

    private func start(port: UInt16) {
        guard listeners[port] == nil else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                emit(.listenFailed(port, "端口号非法"))
                return
            }

            let listener = try NWListener(using: params, on: nwPort)

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.emit(.listening(port))
                case .failed(let error):
                    self.listeners[port] = nil
                    self.emit(.listenFailed(port, error.localizedDescription))
                    self.queue.asyncAfter(deadline: .now() + 2) { self.start(port: port) }
                case .waiting(let error):
                    self.emit(.listenFailed(port, "等待中：" + error.localizedDescription))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.accept(connection, port: port)
            }

            listener.start(queue: queue)
            listeners[port] = listener
        } catch {
            emit(.listenFailed(port, error.localizedDescription))
        }
    }

    // MARK: - 连接

    private func accept(_ connection: NWConnection, port: UInt16) {
        let key = ObjectIdentifier(connection)
        decoders[key] = FrameDecoder(mode: FramingMode.forPort(port))
        connections[key] = connection
        emit(.connected(port, describe(connection.endpoint)))

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed:
                self.close(connection, port: port)
            case .cancelled:
                self.close(connection, port: port)
            default:
                break
            }
        }

        connection.start(queue: queue)
        receive(connection, port: port)
    }

    private func close(_ connection: NWConnection, port: UInt16) {
        let key = ObjectIdentifier(connection)
        guard connections[key] != nil else { return }
        connections[key] = nil
        decoders[key] = nil
        reportedAnomalies[key] = nil
        connection.cancel()
        emit(.closed(port, "连接结束"))
    }

    private func receive(_ connection: NWConnection, port: UInt16) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let key = ObjectIdentifier(connection)

            if let data, !data.isEmpty {
                var decoder = self.decoders[key] ?? FrameDecoder(mode: FramingMode.forPort(port))
                let frames = decoder.append(data)
                let anomalies = decoder.anomalyCount
                self.decoders[key] = decoder

                for frame in frames {
                    self.emit(.inbound(port, frame))
                    self.maybeReply(frame, on: connection, port: port)
                }

                let acknowledged = self.reportedAnomalies[key] ?? 0
                if anomalies > acknowledged {
                    self.reportedAnomalies[key] = anomalies
                    self.emit(.anomaly(port, anomalies - acknowledged))
                }
            }

            if isComplete || error != nil {
                self.close(connection, port: port)
                return
            }
            self.receive(connection, port: port)
        }
    }

    // MARK: - 应答

    /// 只处理版本协商：车机发 98305，我们回 65538 且 matchStatus=1。
    /// 其余消息一律不答 —— 让车机停在下一步，正好看清它的行为。
    private func maybeReply(_ frame: ParsedFrame, on connection: NWConnection, port: UInt16) {
        guard autoReplyVersion, frame.type == 98305 else { return }
        // protobuf: field1(varint) = 1
        send(type: 65538, payload: [0x08, 0x01], on: connection, port: port)
    }

    private func send(type: UInt32, payload: [UInt8], on connection: NWConnection, port: UInt16) {
        var bytes: [UInt8] = []
        let length = payload.count

        switch FramingMode.forPort(port) {
        case .header8:
            bytes += be16(UInt16(clamping: length))
            bytes += [0x00, 0x00]
            bytes += be32(type)
        case .header12:
            bytes += be32(UInt32(length))
            bytes += be32(0)
            bytes += be32(type)
        }

        bytes += payload
        let data = Data(bytes)
        emit(.outbound(port, type, data))
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func be16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private func be32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    // MARK: - 工具

    private func describe(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return String(describing: endpoint)
        }
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}
