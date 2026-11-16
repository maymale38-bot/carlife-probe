import Foundation

/// 已知的消息 ID 对照表。日志里直接显示中文名，省得一边看手册一边对十六进制。
/// 来源：对 CarLife 车机端与手机端反向分析的公开实测记录。
enum MessageCatalog {
    static let names: [UInt32: String] = [
        // 连接与握手
        98305: "版本协商",
        65538: "版本协商应答(matchStatus)",
        98343: "统计信息",
        131074: "心跳",

        // 设备与模块
        65540: "手机设备信息(MD_INFO)",
        98307: "车机信息(HU_INFO)",
        65563: "前台状态",
        65560: "亮屏状态",
        65570: "唤醒录音",
        65574: "模块状态",
        98344: "模块开关(HU_MODULE_CONTROL)",

        // 鉴权
        65611: "鉴权结果(authenResult)",
        98380: "鉴权ACK",
        98376: "鉴权请求",
        65609: "鉴权响应",

        // 功能配置
        65544: "编码参数确认",
        65617: "功能配置请求",
        98386: "功能配置(HU_FEATURE_CONFIG)",
        98316: "帧率变更",

        // 视频
        98311: "视频编码初始化",
        98313: "视频编码启动",
        65551: "视频编码状态",

        // 音频
        98318: "暂停播放",
        98322: "音频初始化",

        // 触摸与按键（车机 → 手机）
        425985: "触摸·复合动作",
        425986: "触摸·按下(DOWN)",
        425987: "触摸·抬起(UP)",
        425988: "触摸·移动(MOVE)",
        425989: "触摸·单击",
        425990: "触摸·双击",
        425991: "触摸·长按",
        425992: "硬按键",
    ]

    static func name(for type: UInt32) -> String {
        names[type] ?? "未知消息"
    }

    static func describe(_ type: UInt32) -> String {
        "\(type) | 0x" + String(format: "%08X", type) + " | " + name(for: type)
    }

    private static let portNames: [UInt16: String] = [
        7240: "CMD",
        8240: "VIDEO",
        9240: "MEDIA",
        9241: "TTS",
        9242: "VR",
        9340: "TOUCH",
        9440: "CTRL",
    ]

    static func portName(_ port: UInt16) -> String {
        portNames[port] ?? "PORT"
    }
}
