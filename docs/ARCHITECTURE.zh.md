# 架构说明（中文）

这份文档写给会 Python、没写过 Swift 的你。先讲整体数据流，再逐个模块说明，
最后附一个 Swift 概念对照表。

## 一、数据流

```
Music.app
  │  ① 系统广播 com.apple.Music.playerInfo（切歌 / 播放 / 暂停时发出）
  │  ② 每秒一次 AppleScript 询问：播放到第几秒了、当前是哪首歌
  ▼
AppleMusicMonitor  ──▶  PlayerSnapshot（状态、位置、曲目、采样时间）
  │
  ▼
AppDelegate.handle(snapshot)
  ├─ PlaybackClock.sync(...)        把"第 N 秒"和"本机时钟"对齐，之后按帧插值
  └─ 曲目变了？ ──▶ LyricsResolver.resolve(track)
                       ├─ AppleMusicCacheProvider   读 Music 自己下载的歌词（首选）
                       └─ LRCLIBProvider            兜底，可关
                              │
                              ▼
                        LyricsDocument（若干 LyricLine，每行有起止时间、文本、可选逐字时间轴）
  │
  ▼
OverlayView（SwiftUI）每秒重绘 20 次：
  用 clock.position() 算出当前时间 ──▶ doc.index(at:) 二分查找当前行 ──▶ 显示当前行 + 下一行
```

## 二、各模块

### Player/ 播放器监听

- `PlayerMonitor.swift` 是协议（相当于 Python 的抽象基类）：谁实现了它，谁就是一个播放器来源。
- `AppleMusicMonitor.swift` 是 Apple Music 的实现。两条线并用：
  - 系统广播只告诉我们"状态变了"，不带播放位置，所以收到后立刻补一次轮询。
  - 轮询用 `NSAppleScript`，脚本一次性返回一个列表（状态、位置、歌名、歌手、专辑、时长、持久 ID），
    避免解析字符串。播放时每秒一次，暂停时每三秒一次。
  - 坑：向没运行的 Music 发 AppleScript 会把它拉起来，所以先用 `NSRunningApplication` 确认它在运行。
  - 坑：AppleScript 里 `st`、`nd`、`rd`、`th` 是序数词保留字，变量不能这么起名（已经踩过）。
- `PlaybackClock.swift`：记录"上次读到的位置"和"读到时的本机时间"，之后任何时刻的位置 =
  上次位置 + 经过的时间。轮询回来的值和预测值差得小就只修正一半，差得大（用户拖了进度条）就直接跳。

### Lyrics/ 歌词

- `Lyrics.swift` 数据模型。`LyricsDocument.index(at:)` 用二分查找找当前行。
- `LyricsProvider.swift`：歌词来源协议 + `LyricsResolver`，按顺序问每个来源，谁先给谁算。
- `AppleMusicCacheProvider.swift`：核心。Music.app 每播一首歌都会请求
  `amp-api.music.apple.com/v1/catalog/<地区>/songs/<id>?include=syllable-lyrics…`，
  macOS 的 URL 缓存把响应原样存在 `~/Library/Caches/com.apple.Music/fsCachedData/<UUID>`。
  我们扫描这个目录，匹配当前曲目后取出 JSON 里的 TTML 字符串。匹配规则按可信度排序：
  1. 歌名相同且时长相差 2.5 秒以内；
  2. 时长相差 1.5 秒以内，且文件是在这首歌开始播放之后写入的。这条是为了应付本地化标题：
     AppleScript 报的是资料库里的名字（"就是现在"），Music 请求歌词时用的是界面语言（"Now Is the Time"）；
  3. 时长相差 1 秒以内，且整个缓存里只有这一首歌是这个时长。
  同一档次里优先取时长最接近的，再取最新写入的文件。
  - 扫描有索引：每个文件记住修改时间和大小，没变的不重复解析；不是歌词的文件也记住，下次直接跳过。
  - 刚切歌时 Music 可能还没请求完，所以最多等 25 秒，每 1 到 2 秒重扫一次。
  - 匹配到的 TTML 会另存到 `~/Library/Application Support/LyricBar/lyrics/`，Music 的缓存被清也不怕。
- `TTMLParser.swift`：解析 Apple 的 TTML。`<p>` 是一行，`<span begin end>` 是一个词，
  `<translations>` 里 `type="subtitle"` 是翻译、`type="replacement"` 是同一语言换个书写（繁转简）。
  `ttm:role="x-bg"` 是和声，v0.1 先忽略。
- `LRCParser.swift` / `LRCLIBProvider.swift`：兜底方案，标准 LRC 格式。
- `LyricsStore.swift`：我们自己的磁盘缓存，文件名是曲目 contentKey 的 SHA-256 前 24 位。

### UI/ 界面

- `OverlayWindow.swift`：`NSPanel` 子类。关键设置：无边框、透明、`.nonactivatingPanel`（点它不会抢焦点）、
  层级 `.statusBar`、`canJoinAllSpaces` + `fullScreenAuxiliary`（所有桌面和全屏应用之上都显示）。
  平时 `ignoresMouseEvents = true` 鼠标穿透，并且每 0.1 秒查一次鼠标位置，鼠标在窗口上就把窗口 alpha 降到 0.15；
  开启"移动模式"后窗口接收鼠标、可拖动，位置存进 UserDefaults。窗口高度跟字号联动。
- `OverlayView.swift`：SwiftUI 视图。`TimelineView` 每秒重算 30 次，用时钟算当前行和当前唱到的位置。
  歌词向上滚动：旧句上滑淡出，下一句放大上移，再下一句从底部淡入。
- `LineMetrics.swift`：逐字染色的核心。用 `NSFont` 量出每个词在这一行里的横向起止位置，
  当前时刻唱到第几个词、唱了几分之几，就换算成一个 x 坐标；视图里白色文字上叠一层彩色文字，
  用宽度为 x 的矩形做遮罩。量尺寸不便宜，所以按"行 + 字号 + 宽度"缓存。
- `StatusBarController.swift`：菜单栏图标 + `NSPopover`。
- `PopoverView.swift`：面板内容，所有开关直接绑定到 `AppState` 的属性。

### App/

- `AppState.swift`：全局状态，`@Published` 的属性一变，绑定它的 SwiftUI 视图自动刷新。设置项的 `didSet` 里顺手写 UserDefaults。
- `AppDelegate.swift`：把上面所有东西接起来。
- `Probe.swift` + `main.swift`：`LyricBar --probe 歌名 歌手 时长` 可以不开界面直接测歌词管线。

## 三、Swift 概念对照（给 Python 人）

| Swift | 类比 Python | 说明 |
|---|---|---|
| `protocol` | `abc.ABC` | 只声明方法签名，谁遵守谁实现 |
| `struct` | `@dataclass(frozen=False)` 但按值拷贝 | 赋值就是复制，改副本不影响原件 |
| `class` | 普通 class | 引用语义 |
| `let` / `var` | 常量 / 变量 | `let` 赋值后不可变 |
| `String?` 可选类型 | `Optional[str]` | 必须显式处理 `nil`，`if let x = ...` 相当于 `if x is not None` |
| `guard ... else { return }` | 提前返回 | 条件不满足就退出，满足则后面可以直接用解包后的变量 |
| 闭包 `{ [weak self] in ... }` | lambda | `[weak self]` 是避免循环引用的惯用写法 |
| `async` / `await` / `Task` | asyncio | 语法几乎一样，`Task { }` 相当于 `create_task` |
| `@MainActor` | "只能在主线程跑" | 界面相关的东西必须在主线程，编译器帮你检查 |
| `@Published` + `ObservableObject` | 观察者模式 | 属性变了，订阅它的视图自动重绘 |
| `some View` | 返回类型是"某种 View" | SwiftUI 的视图都这么写 |

## 四、调试

- 日志：`make logs`，或 `log stream --predicate 'subsystem == "dev.lyricbar"'`
- 不开界面测歌词：`make probe TITLE="Cigarette Daydreams" ARTIST="Cage the Elephant" DURATION=208`
- 权限：系统设置 → 隐私与安全性 → 自动化 → LyricBar → Music
