import Foundation

/// CarLife 报文的两种包头布局（均为大端序）。
/// 实测结论：7240(CMD) 与 9440(CTRL) 用 8 字节头，其余通道用 12 字节头。
enum FramingMode {
    case header8   // [u16 len][u16 reserved][u32 type]
    case header12  // [u32 len][u32 seq][u32 type]

    var headerSize: Int {
        switch self {
        case .header8: return 8
        case .header12: return 12
        }
    }

    static func forPort(_ port: UInt16) -> FramingMode {
        switch port {
        case 7240, 9440:
            return .header8
        default:
            return .header12
        }
    }
}

struct ParsedFrame {
    let type: UInt32
    let seq: UInt32?
    let payload: Data

    var typeHex: String {
        String(format: "0x%08X", type)
    }

    var typeName: String {
        MessageCatalog.name(for: type)
    }

    /// 前 32 字节的十六进制预览，够看清 protobuf 开头又不刷屏
    var payloadPreview: String {
        let bytes = Array(payload.prefix(32))
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        return payload.count > 32 ? hex + " …" : hex
    }
}

struct FrameDecoder {
    let mode: FramingMode
    private var buffer: [UInt8] = []
    private(set) var anomalyCount = 0

    init(mode: FramingMode) {
        self.mode = mode
    }

    mutating func append(_ data: Data) -> [ParsedFrame] {
        buffer.append(contentsOf: data)

        // 防御：缓冲区异常堆积时丢弃旧数据，避免内存无限增长
        if buffer.count > 4 * 1024 * 1024 {
            buffer.removeFirst(buffer.count - 1024 * 1024)
            anomalyCount += 1
        }

        var frames: [ParsedFrame] = []
        let hs = mode.headerSize

        while buffer.count >= hs {
            let length: Int
            let type: UInt32
            var seq: UInt32?

            switch mode {
            case .header8:
                length = Int(readU16(0))
                type = readU32(4)
                seq = nil
            case .header12:
                length = Int(readU32(0))
                seq = readU32(4)
                type = readU32(8)
            }

            // 长度不合法说明帧头对不上：丢 1 字节重新对齐
            if length < 0 || length > 1_000_000 {
                anomalyCount += 1
                buffer.removeFirst()
                continue
            }

            if buffer.count < hs + length { break }

            let payload = Data(buffer[hs..<(hs + length)])
            buffer.removeFirst(hs + length)
            frames.append(ParsedFrame(type: type, seq: seq, payload: payload))
        }

        return frames
    }

    private func readU16(_ offset: Int) -> UInt16 {
        UInt16(buffer[offset]) << 8 | UInt16(buffer[offset + 1])
    }

    private func readU32(_ offset: Int) -> UInt32 {
        UInt32(buffer[offset]) << 24
            | UInt32(buffer[offset + 1]) << 16
            | UInt32(buffer[offset + 2]) << 8
            | UInt32(buffer[offset + 3])
    }
}
