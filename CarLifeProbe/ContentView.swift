import SwiftUI
import UIKit

struct ContentView: View {

    @ObservedObject var model: ProbeModel
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusPanel
                Divider()
                logList
                Divider()
                bottomBar
            }
            .navigationTitle("CarLife 探针")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                model.start()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 顶部状态

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本机热点 IP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.localIP)
                        .font(.system(.title2, design: .monospaced))
                        .foregroundStyle(model.localIP.hasPrefix("172.20.10") ? .green : .orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("收到报文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(model.inboundTotal)")
                        .font(.system(.title2, design: .monospaced))
                }
            }

            if !model.localIP.hasPrefix("172.20.10") {
                Text("提示：先在「设置 → 个人热点」里打开热点，车机连上后 IP 会变成 172.20.10.1")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 6) {
                ForEach(CarLifeServer.ports, id: \.self) { port in
                    portChip(port)
                }
            }

            Toggle("自动答复版本协商（98305 → 65538）", isOn: $model.autoReply)
                .font(.footnote)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
    }

    private func portChip(_ port: UInt16) -> some View {
        let listening = model.listeningPorts.contains(port)
        return VStack(spacing: 2) {
            Text("\(port)")
                .font(.system(.caption2, design: .monospaced))
            Text(MessageCatalog.portName(port))
                .font(.system(size: 9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(listening ? Color.green.opacity(0.22) : Color.red.opacity(0.18))
        )
        .foregroundStyle(listening ? Color.green : Color.red)
    }

    // MARK: - 日志

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if model.entries.isEmpty {
                        Text("等待车机连接……\n\n顺序：打开个人热点 → 车机上点 CarLife 无线连接 → 连上这个热点。\n报文会出现在这里。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }

                    ForEach(model.entries) { entry in
                        row(entry).id(entry.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: model.entries.count) { _ in
                if let last = model.entries.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func row(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(timeText(entry.date))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\(entry.port)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.cyan)
                Text(entry.arrow)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(entry.arrow == "←" ? Color.green : (entry.arrow == "→" ? Color.orange : Color.gray))
                Text(entry.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(entry.arrow == "·" ? Color.secondary : Color.primary)
                Spacer(minLength: 0)
                if entry.byteCount > 0 {
                    Text("\(entry.byteCount)B")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            if !entry.payloadHex.isEmpty {
                Text(entry.payloadHex)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    // MARK: - 底部

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                model.clear()
            } label: {
                Label("清空", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let url = exportURL {
                ShareLink(item: url) {
                    Label("分享日志", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    exportURL = model.exportFileURL()
                } label: {
                    Label("导出日志", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .font(.footnote)
        .padding(12)
    }
}
