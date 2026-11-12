# AGENTS.zh-CN.md

给 AI agent 的说明(中文版,内容与 `AGENTS.md` 一致)。这里有两类工作:在用户的 Mac 上使用 Knobs,以及修改 Knobs 本身。

## 替用户使用 Knobs

命令是 `~/.local/bin/knobs`(指向 `~/Applications/Knobs.app` 的链接)。如果不存在,在本仓库运行 `bash build.sh install`。

1. 运行 `knobs list --json`。每一项包含 `id`、`title`、`description`、`accepts`、`value`、`macOSDefault`、`takesEffect`(`instant`、`newWindows` 或 `relogin`,文字说明在 `takesEffectText`)、`customized`;选项类设置还带 `options` 和易读的 `valueLabel`(触发角 `14` 就是“快速备忘录”)。
2. 用 `title` 和 `description` 向用户说明你打算改什么。只改用户提到的内容。
3. `knobs set <id> <值> [<id> <值> ...] --json`。加 `--dry-run` 先预览。一批修改要么全做要么全不做:有一个值被拒绝,就什么都不写。每一项都会返回 `before`、`after` 和 `verified`(从 macOS 回读确认);被拒绝时 `ok` 为 false,原因在 `errors`。没检查过就不要说成功。
4. `takesEffect` 不是"立即生效"时要告诉用户(重新打开 App,或注销重新登录)。
5. 每次修改(set、reset、apply,或在窗口里点一下)之前都会先存快照。`knobs undo` 一次撤回一步;`knobs undo --list` 列出每个快照是在什么修改之前存的。`knobs reset <id>` 把单项交还给 macOS。

所有会输出结果的命令都支持 `--json`:`list`、`describe`、`get`、`set`、`reset`、`apply`、`undo`、`status`、`verify`。

场景:`knobs scene` 列出场景,`knobs scene <名称> [--dry-run] [--json]` 切换。场景就是可以额外带 `"overbright": {"percent": N}` 的配置文件;Knobs 会调用 `overbright mcp`,并报告 Overbright 的回读结果(`reached` 或 `restored` 表示已证实)。场景还可以带 `"paneful": {"layout": [{app 或 title, x, y, w, h, display?}]}`(屏幕比例);Knobs 会调用 `paneful mcp` 的 `apply_layout`,只有每个窗口都到达指定位置才算已证实。快照里包含亮度和 Paneful 存下的窗口布局,所以 `knobs undo` 会把两者一起还原。通过 MCP 时,用 `apply_profile` 加场景名。

`knobs verify` 只读:对这台 Mac 上已经写入的每个键,检查 macOS 存的类型和取值是否符合目录,并列出不符合的。从没写过的键没法用这种方法检查。

支持 MCP 的客户端可以运行 `knobs mcp`:一个 stdio MCP server,用同一份设置目录和同样带校验的写入。默认只读,用 `knobs mcp --allow-write` 启动才允许修改;预览(dryRun)始终可用。工具有:`list_settings`、`describe_setting`、`get_status`、`verify_catalog`、`list_snapshots`、`set_settings`、`reset_settings`、`apply_profile`、`undo`。

输出语言跟随系统。需要固定语言时加环境变量:`KNOBS_LANG=en` 或 `KNOBS_LANG=zh`。设置的值始终用英文书写(`on`、`off`、数字、选项名)。

按配置文件配置一台 Mac:先 `knobs apply <文件|https 链接|预设名> --dry-run`,把清单给用户看,再去掉 `--dry-run` 应用。`knobs undo` 撤销上一次应用(应用前会自动存快照)。`knobs presets` 列出自带预设;新预设放进 `presets/`,`build.sh` 会校验。

唯一不能替用户做的事,是授予"辅助功能"权限(无动画切换桌面需要它)。如果 `knobs set spaces.instant on` 提示正在等待权限,请用户到 系统设置 → 隐私与安全性 → 辅助功能 打开 Knobs。Knobs 一秒内就会发现,用 `knobs status` 确认。不要尝试自己授权,这个项目里的任何操作都不要用 `sudo`。

## 修改 Knobs

- Swift,直接用 `swiftc` 编译,外加 `Vendor/ISS` 里一个 C 库。没有 Xcode 工程,没有 Swift Package,没有其他依赖,请保持这样。
- 命令行工具链没有 SwiftUI 的宏插件,`@State` 无法编译。视图状态像 `UI.swift` 那样放在 `Model` 里(`@Published`)。
- 图标是 `Resources/icons` 里的 [Lucide](https://github.com/lucide-icons/lucide) SVG,由 `lucide(name, size)` 以单色模板图绘制。要用新图标就把 SVG 放进去;不要引入多色图标或 SF Symbols。
- 所有给人看的文字都写成 `L("English", "中文")`。

```bash
bash build.sh            # 编译、自检、校验 presets/
bash build.sh install    # 再安装到 ~/Applications,链接 ~/.local/bin/knobs 并启动
```

| 文件 | 职责 |
|---|---|
| `Catalog.swift` | 设置清单。大多数改动只发生在这里 |
| `Engine.swift` | 读取、校验、写入、重置一项设置;配置文件;导出与导入 |
| `Live.swift` | 应用运行时提供的功能:无动画切换、常亮、登录时打开 |
| `Keys.swift` | 快捷键解析和按键监听 |
| `CLI.swift` | `knobs` 命令 |
| `App.swift` | 菜单栏图标、窗口,以及跟随配置文件的循环 |
| `UI.swift` | SwiftUI 窗口,内容由清单生成 |
| `main.swift` | 入口和 `--selftest` |

### 添加一项设置

在 `Catalog.swift` 的 `catalog` 里用 `toggle`、`number` 或 `choice` 加一条:

```swift
toggle("dock.autohide", .dock, "Hide the Dock automatically", "自动隐藏程序坞",
       "English description.", "中文说明。",
       "com.apple.dock", "autohide", default: false, restart: ["Dock"]),
```

- `default:` 是这个键从未写入时 macOS 的实际行为。必须写对,否则在一台新 Mac 上窗口会显示错误的状态。查不到就用不带默认值的 `number`。
- `restart:` 列出需要重启才能看到变化的进程。`timing:` 必须如实:重启程序坞或访达不够时,用 `.newWindows` 或 `.relogin`。
- 键的含义与标题相反时(如 `DisableAllAnimations`)加 `inverted: true`。
- 在真机上验证:`knobs set`,看效果,再 `knobs reset`。不要把旧 dotfiles 里的键直接抄进来,先确认它在当前 macOS 上还有作用。

### 你自己验证不了的事

无动画切换需要辅助功能权限,只有用户能授予,而且效果是视觉上的。请如实说明,不要声称已经端到端测试过。你能验证的有:自检、`knobs status`、用 `pmset -g assertions` 看常亮、`knobs set` 之后用 `defaults read` 核对。
