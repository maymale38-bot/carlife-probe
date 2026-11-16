# CarLife 探针（P0）

一个只做一件事的 iOS App：**在手机上监听 CarLife 的 7 个 TCP 端口，把车机连上来之后的每一条报文原样记录下来**。

它不投屏、不编码、不做 UI —— 这一版的目的只有一个：把你车机的协议版本、握手顺序、端口行为暴露出来，为后面的"自绘车机 UI + 投屏"打地基。

---

## 为什么要先做这个

CarLife 里**车机是客户端、手机是服务端**。手机要监听 `7240 / 8240 / 9240 / 9241 / 9242 / 9340 / 9440`，车机反过来连手机的 IP。方向做反了就永远连不上。

而不同车机、不同固件的协议版本差异很大（老版走明文，新版 4.0 会进 RSA/AES 加密鉴权），握手顺序也有偏差。**先把原始报文抓下来，比照着猜去写投屏要省几个星期。**

---

## 目录结构

```
CarLifeProbe/
├── project.yml                  # XcodeGen 工程描述
├── .github/workflows/build-ipa.yml  # 云端 macOS 出包，不需要 Mac
└── CarLifeProbe/
    ├── Info.plist
    ├── CarLifeProbeApp.swift     # 入口
    ├── ContentView.swift         # 界面
    ├── ProbeModel.swift          # 日志数据与事件分发
    ├── CarLifeServer.swift       # 7 端口监听 + 版本协商应答
    ├── FrameDecoder.swift        # 包头解析（8 字节 / 12 字节两种）
    ├── MessageCatalog.swift      # 已知消息 ID 对照表
    └── NetInfo.swift             # 取本机热点 IP
```

---

## 一、出包（不需要 Mac）

### 方式 A：GitHub Actions

1. 在 GitHub 新建一个仓库，把本目录整体推上去
2. 打开仓库的 **Actions** 页 → 选 `Build unsigned IPA` → 点 **Run workflow**
3. 等 3~5 分钟，在该次运行的 **Artifacts** 里下载 `CarLifeProbe-unsigned-ipa`
4. 解压得到 `CarLifeProbe-unsigned.ipa`

> 流水线跑的是 `macos-14` runner，`xcodegen` 现场生成工程，`CODE_SIGNING_ALLOWED=NO` 出未签名包。

### 方式 B：有 Mac

```bash
brew install xcodegen
xcodegen generate
open CarLifeProbe.xcodeproj
```

在 Xcode 里选你的开发者账号（免费 Apple ID 也行）直接跑到手机上。

---

## 二、装到 iPhone 12 mini

未签名的 IPA 不能直接装，需要签一次。

**Windows 上推荐 Sideloadly：**

1. 电脑装 [iTunes](https://www.apple.com/itunes/)（提供驱动）和 Sideloadly
2. 数据线连上 iPhone，手机上点「信任此电脑」
3. Sideloadly 里把 IPA 拖进去，填你的 Apple ID（免费账号即可）
4. 点 Start，等它签完并安装

**注意：**

- 免费 Apple ID 签的包 **7 天后失效**，到期用 Sideloadly 重签一次即可，App 数据会保留
- 首次运行会要 **本地网络权限**，必须点允许，否则端口监听拿不到流量
- 同一台设备免费账号最多同时装 3 个自签 App

---

## 三、使用步骤（顺序不能错）

```
① 手机：设置 → 个人热点 → 打开「允许他人加入」
        （iOS 不允许 App 自动开热点，只能手动）

② 打开「CarLife 探针」，确认顶部 IP 显示 172.20.10.1，7 个端口全绿

③ 车机：点 CarLife → 选择「无线连接」

④ 车机连上 iPhone 的热点后，日志开始出现报文
```

**保持 App 在前台**。这一版没有做后台保活（`Info.plist` 里已经预留了 `UIBackgroundModes: audio`，等 P1 再接静音音频续命）。

---

## 四、回来给我什么

在 App 底部点 **导出日志** → 分享到微信/文件，把 `CarLifeProbe-log.txt` 发我。

日志每行格式：

```
[时间] 端口(通道名) 方向 消息名 (0x消息ID) | 字节数 | 前 32 字节十六进制
```

**重点看这几件事，你自己也能先判断：**

| 现象 | 说明 |
|---|---|
| `7240 ← 版本协商 (0x00018001)` | 车机发起握手了，这是好消息，链路通了 |
| 该报文的十六进制是 `08 04 10 00` | 协议 major=4 → **新版，会走加密鉴权**，后面要小心 |
| 是 `08 03 10 00` 或 `08 01 10 00` | 老版明文路径，最理想 |
| `→ 已答复 版本协商应答` 之后没有任何后续 | 正常。我们只回了这一条，车机在等设备信息，**这正是我想看的断点位置** |
| 只有 7240 有流量，其他 6 个端口没动静 | 正常，车机通常先只连 CMD 通道 |
| `帧对齐异常 ×N` | 说明包头格式判断错了，回来我按日志调 `FramingMode.forPort` |
| 7 个端口全红 | 本地网络权限没给，或热点没开 |

---

## 五、这一版故意没做的事

- **不发设备信息**（`65540 MD_INFO`）、**不做鉴权**（`65611`）—— 这些的 protobuf 字段序一旦写错会静默断链，等看到车机的真实版本再精确构造
- **不主动推** `98386 功能配置` / `98311 视频编码初始化` —— 需要先确认车机愿意等我们推，还是它自己会发
- **不投屏** —— 视频通道只收不解码，收到什么就记什么

P0 跑通、报文拿到之后，P1 才开始出画面：VideoToolbox 编一帧测试图推给 8240，看车机认不认我们的码流。

---

## 合规与安全

- 这是个人实验项目，与 Apple、百度、丰田均无关联
- 只在你自己的车和自己手机上使用
- 驾驶中不要操作，配置全部在停车状态下完成
