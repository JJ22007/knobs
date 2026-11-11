<h1 align="center">Knobs</h1>

<p align="center">
  <b>把值得改的 macOS 设置,放进一张看得懂的清单里。</b><br>
  拨一下开关立刻生效,也可以让 agent 替你拨。换新电脑时,一个文件带走全部习惯。
</p>

<p align="center"><a href="README.md">English</a></p>

<p align="center">
  <img src="docs/demo.gif" width="100%" alt="AI agent 打开屏幕常亮、关掉开窗动画并导出配置">
</p>
<p align="center"><sub>对 Claude Code(Haiku)说一句话,完全不提 Knobs:它自己找到 skill,实时改了两项设置并导出配置。真实运行,思考时间被缩短,路径里的账户名做了遮挡。</sub></p>

Knobs 是一个菜单栏小应用,带一个设置窗口和一个 `knobs` 命令。它把开发者常从 dotfiles 里复制的那些调整(`defaults write …`、`pmset …`、yabai)收到一起,给每一项起了名字、写了说明、配了开关,并且如实标注它什么时候生效。

## 为什么做这个

- **切换桌面空间没有动画,而且不用关 SIP。** 打开后,下一次按 `⌃←` / `⌃→` 就直接跳过去。反悔了就关掉,下一次按键立刻恢复系统的滑动动画。不用重启,不用注销。
- **屏幕常亮不需要 `sudo`。** 一个开关,立即生效;关掉后恢复你原来的熄屏时间。
- **看得懂。** 110 多项设置,分成 13 组,每一项都有白话说明和背后真实的偏好设置键,没有藏在脚本里的东西。
- **能交给 agent。** `knobs list --json` 告诉 agent 每一项是什么意思,`knobs set` 负责修改。
- **能带走。** `knobs export` 导出一个文件。在新电脑上把它交给 agent,设置和快捷键就都一样了。

## 和其他做法比

| | `.macos` 脚本 | nix-darwin | 图形化调节工具 | Knobs |
|---|---|---|---|---|
| 看得懂每项设置是做什么的 | 靠注释 | 选项文档 | 能 | 能,还标出系统默认值和生效时机 |
| 系统允许时无需注销即生效 | 要 `killall` | 要重新构建 | 大多可以 | 可以,做不到时会如实说明 |
| 不关 SIP 实现无动画切换桌面 | 不能 | 不能 | 不能 | 能 |
| AI agent 能读、能解释、能修改 | 只能直接写 `defaults` | 要改 Nix | 不能 | `knobs list --json`、Claude Code skill、退出码 |
| 分享一套设置 | 复制脚本 | 分享 flake | 很少支持 | 一个 JSON 文件、一个链接或一个预设 |
| 撤销 | 自己写 | 回滚 | 部分支持 | 每次 apply 后都能 `knobs undo` |

Knobs 不是要取代完整的 dotfiles 或 Nix 配置。它是那一部分:谁都能用、能交给 agent、一分钟就能读懂。

## 安装

需要 macOS 13 或更高版本,以及 Swift 编译器(没装过就先运行 `xcode-select --install`)。

```bash
git clone https://github.com/JJ22007/knobs.git
cd knobs
bash build.sh install
```

脚本会编译、自测、把 `Knobs.app` 装到 `~/Applications`,把 `knobs` 命令链接到 `~/.local/bin`,然后打开窗口。

### 唯一需要的权限

只有"无动画切换桌面"需要权限:**辅助功能**。因为 Knobs 必须在系统开始播放动画之前接住你的快捷键。在 系统设置 → 隐私与安全性 → 辅助功能 里打开 Knobs 即可,打开的瞬间就生效。其他所有功能都不需要权限,也不需要密码。

如果你会反复从源码编译,先运行一次下面的脚本,授权就不会因为重新编译而失效:

```bash
bash scripts/setup-signing.sh
```

## 它能管什么

| 分组 | 举例 |
|---|---|
| 桌面空间与调度中心 | 无动画切换(键盘和触控板)、不再自动重排空间、按 App 分组窗口 |
| 动画 | 窗口开关、缩放速度、快速查看、访达、程序坞弹跳、最小化效果、减弱动态效果 |
| 电源与亮屏 | 屏幕常亮、电脑不休眠 |
| 菜单栏与时钟 | 自动隐藏菜单栏、图标间距(刘海旁能放下更多图标)、秒、星期、日期、24 小时制 |
| 程序坞 | 自动隐藏、延迟与速度、大小、位置、最近使用、指示点、只显示已打开的 App、滚动显示窗口 |
| 触发角 | 屏幕四个角各做什么:调度中心、桌面、锁屏、快速备忘录或不执行 |
| 桌面与窗口 | 桌面图标、点按墙纸显示桌面、台前调度、小组件、贴边平铺、平铺边距、⌃⌘ 任意位置拖窗口、双击标题栏、标签页 |
| 访达与文件 | 扩展名、隐藏文件、路径栏、状态栏、默认视图、搜索范围、`.DS_Store`、保存对话框、30 天后清倒废纸篓、桌面显示外置磁盘 |
| 键盘与输入 | 按键重复、长按重音菜单、Tab 切换所有控件、自动纠正、智能引号与破折号、行内预测 |
| 触控板与鼠标 | 轻点点按、点按力度、安静点按、三指拖移、滚动惯性、自然滚动、双指右键、三指查询、页面间轻扫、跟踪与滚动速度、连按速度 |
| 截图 | 格式、保存位置、阴影、缩略图、文件名带日期 |
| 系统与 App | 滚动条、边栏图标大小、恢复窗口、界面音效、音量反馈音、插入新设备时不弹“照片”和时间机器 |

动画分组里还有调度中心速度。运行 `knobs list` 可以看到完整清单和当前值。

每一项都标明生效时机:

- **立即生效**:马上起作用。需要重启程序坞或访达时,Knobs 会替你做。
- **之后打开的 App 生效**:已经在运行的 App 要重新打开才会变。
- **注销重新登录后生效**:系统只在登录时读取这些设置。

## 让 agent 来操作

`build.sh install` 还会在 `~/.claude/skills/knobs` 装一个 [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills),Claude Code 在任何文件夹都认识 Knobs:随便在哪儿说一句“别让我的屏幕熄灭”,它会自己用上 `knobs`。`knobs skill remove` 可以移除;`knobs skill` 会把内容打印出来,方便交给其他 agent。其他 agent 可以读 [AGENTS.md](AGENTS.md)。

```bash
knobs list --json              # 每项设置:id、含义、可接受的值、当前值、何时生效
knobs describe dock.autohide   # 查看某一项的详细说明
knobs set dock.autohide on dock.autohideDelay 0
knobs reset dock.autohideDelay # 交还给 macOS 默认值
knobs set spaces.instant on    # 会报告是否真的生效,没生效会说明原因
knobs status
```

可以这样对 agent 说:

> 用 `knobs` 命令看一下我的 macOS 设置(`knobs list --json`)。我想让一切更快:去掉不必要的动画,桌面空间切换不带动画。每改一项之前先告诉我它是做什么的。

窗口里的"Agent 提示词"按钮可以直接复制一段现成的提示词。全部成功时退出码为 0;有任何一项被拒绝时为 1,原因写在 stderr,agent 能据此判断。

## 换新电脑

在旧电脑上:

```bash
knobs export ~/Desktop/my-mac.knobs.json
```

这个文件包含你改过的所有设置、切换空间的快捷键,以及配套工具的配置([Paneful](https://github.com/JJ22007/paneful) 的分屏快捷键)。文件里自带使用说明,所以在新电脑上把它交给任何一个编程 agent,说一句:

> 按照 `my-mac.knobs.json` 把这台 Mac 配置好。

也可以自己动手:

```bash
git clone https://github.com/JJ22007/knobs.git && cd knobs && bash build.sh install
knobs apply ~/Desktop/my-mac.knobs.json --dry-run   # 先看看会改什么
knobs apply ~/Desktop/my-mac.knobs.json
```

## 分享你的设置

配置文件是一个短小、看得懂的 JSON,所以设置可以像 dotfiles 一样传播:放进 gist 或仓库,别人用链接就能直接应用。

```bash
knobs export my-mac.knobs.json                                  # 然后发成 gist,或提交到仓库
knobs apply https://gist.githubusercontent.com/you/…/raw/my-mac.knobs.json --dry-run
knobs apply https://gist.githubusercontent.com/you/…/raw/my-mac.knobs.json
```

全新的 Mac 只要一行:装好 Knobs,先列出会改什么,再应用:

```bash
curl -fsSL https://raw.githubusercontent.com/JJ22007/knobs/main/scripts/bootstrap.sh | bash -s -- <预设名、链接或文件>
```

应用里自带几套现成预设(`knobs presets`),欢迎往 [`presets/`](presets) 提交你自己的:

| 预设 | 适合 |
|---|---|
| `snappy` | 不等动画、安静的程序坞、什么都看得见的访达 |
| `developer` | 按键重复快、不自动纠错不改标点、文件和路径全都看得见 |
| `focus` | 打扰更少、桌面干净、插设备不乱弹窗 |
| `presenter` | 演示和共享屏幕:屏幕不熄灭、桌面干净、角落安静 |
| `jj22007` | 作者自己的 Mac,包括 [Paneful](https://github.com/JJ22007/paneful) 分屏快捷键 |

配置文件只能写入清单里的设置,以及 `Engine.swift` 里列出的配套文件;`--dry-run` 会先把要改的全部列出来。应用陌生人的配置前先读一遍,和对待别人的 dotfiles 一样。

每次 `knobs apply`(以及窗口里的"导入")都会先在 `~/.config/knobs/backups` 存一份快照。`knobs undo` 把所有设置恢复原样,原本没改过的也会交还给 macOS;`knobs undo --list` 列出所有快照。

## 快捷键

开启无动画切换后,由下面这些按键触发,默认与系统一致。

```bash
knobs shortcut                      # 查看
knobs shortcut spaceLeft ctrl+left
knobs shortcut space1 ctrl+1        # 直接跳到桌面 1,一直到 space9
knobs shortcut space1 none
```

## 原理

- 偏好设置类的项目,写入方式与 `defaults write` 相同,写完会读回来确认系统确实接受了。
- 无动画切换是合成一次速度极高的触控板横扫,让程序坞立刻完成切换。这个方法来自 jurplel 的 [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher)(MIT 许可),代码放在 `Vendor/ISS`。
- 屏幕常亮使用电源断言,与 `caffeinate` 是同一套机制。
- 这类实时功能需要 Knobs 在运行。打开"登录时打开 Knobs",重启后它们会自动恢复。

相关文件:`~/.config/knobs/config.json`(实时功能和快捷键)、`~/.config/knobs/status.json`(当前实际生效的状态)。

## 添加你自己的设置

在 `Sources/Catalog.swift` 里加一条,窗口、命令行、导出和导入就都有了。细节写在 `AGENTS.md` 里,可以直接让编程 agent 来加。

## 许可

MIT。其中包含 InstantSpaceSwitcher 的手势代码,同为 MIT。图标来自 [Lucide](https://github.com/lucide-icons/lucide)(ISC 许可),以 SVG 形式放在 `Resources/icons`。
