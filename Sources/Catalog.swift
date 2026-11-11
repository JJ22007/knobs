// The catalog: every setting Knobs knows, in one readable table.
// To add a setting, add one entry here. Nothing else needs to change:
// the window, the command line, export and import all read this table.

import Foundation

enum Category: String, CaseIterable {
    case spaces, motion, power, menubar, dock, corners, desktop, finder, keyboard, pointer, screenshots, system, app

    var title: String {
        switch self {
        case .spaces: return L("Spaces & Mission Control", "桌面空间与调度中心")
        case .motion: return L("Animations", "动画")
        case .power: return L("Power", "电源与亮屏")
        case .menubar: return L("Menu Bar & Clock", "菜单栏与时钟")
        case .dock: return L("Dock", "程序坞")
        case .corners: return L("Hot Corners", "触发角")
        case .desktop: return L("Desktop & Windows", "桌面与窗口")
        case .finder: return L("Finder & Files", "访达与文件")
        case .keyboard: return L("Keyboard & Typing", "键盘与输入")
        case .pointer: return L("Trackpad & Mouse", "触控板与鼠标")
        case .screenshots: return L("Screenshots", "截图")
        case .system: return L("System & Apps", "系统与 App")
        case .app: return "Knobs"
        }
    }

    /// Icon name in Resources/icons (Lucide, https://lucide.dev).
    var symbol: String {
        switch self {
        case .spaces: return "gallery-horizontal"
        case .motion: return "wind"
        case .power: return "power"
        case .menubar: return "panel-top"
        case .dock: return "dock"
        case .corners: return "scan"
        case .desktop: return "app-window"
        case .finder: return "folder"
        case .keyboard: return "keyboard"
        case .pointer: return "mouse-pointer-2"
        case .screenshots: return "camera"
        case .system: return "monitor-cog"
        case .app: return "sliders-horizontal"
        }
    }
}

enum Kind {
    case toggle
    case number(min: Double, max: Double, step: Double, unit: String, integer: Bool)
    case choice([(value: String, label: String)])
    case text
}

/// When a change becomes visible. Knobs never pretends something is instant when it is not.
enum Timing: String {
    case instant      // takes effect right away
    case newWindows   // apps and windows opened from now on
    case relogin      // after logging out and back in

    var label: String {
        switch self {
        case .instant: return L("instant", "立即生效")
        case .newWindows: return L("apps opened from now on", "之后打开的 App 生效")
        case .relogin: return L("after you log out and back in", "注销重新登录后生效")
        }
    }
}

struct Pref {
    let domain: String   // "NSGlobalDomain" or a bundle id
    let key: String
    var currentHost = false
}

/// Features the running Knobs app provides itself. They have no preference key.
enum LiveID: String {
    case instantSpaces, instantSwipe, awakeDisplay, awakeSystem, launchAtLogin
}

enum Backing {
    /// One or more preference keys that are written together, then these processes are restarted.
    case prefs([Pref], restart: [String])
    case live(LiveID)
}

struct Setting {
    let id: String
    let category: Category
    let title: String
    let detail: String
    let kind: Kind
    let timing: Timing
    let backing: Backing
    /// What macOS does when the key was never written. nil means "unknown, let the system decide".
    let systemDefault: Value?
    /// The preference stores the opposite of what the title says (e.g. "DisableAllAnimations").
    var inverted = false
    /// A choice whose options are numbers in the preference (hot corners, clock date). Shown and
    /// passed around as text ("2"), written as an integer.
    var intChoice = false

    var keyDescription: String {
        switch backing {
        case .prefs(let prefs, _): return prefs.map { "\($0.domain) \($0.key)" }.joined(separator: ", ")
        case .live: return L("provided by the Knobs app", "由 Knobs 应用提供")
        }
    }
}

private let g = "NSGlobalDomain"
private let dock = "com.apple.dock"
private let finder = "com.apple.finder"
private let wm = "com.apple.WindowManager"
private let shot = "com.apple.screencapture"

private func toggle(_ id: String, _ c: Category, _ en: String, _ zh: String, _ dEn: String, _ dZh: String,
                    _ domain: String, _ key: String, default d: Bool, restart: [String] = [],
                    timing: Timing = .instant, inverted: Bool = false, also: [Pref] = [], currentHost: Bool = false) -> Setting {
    Setting(id: id, category: c, title: L(en, zh), detail: L(dEn, dZh), kind: .toggle, timing: timing,
            backing: .prefs([Pref(domain: domain, key: key, currentHost: currentHost)] + also, restart: restart),
            systemDefault: .bool(d), inverted: inverted)
}

private func number(_ id: String, _ c: Category, _ en: String, _ zh: String, _ dEn: String, _ dZh: String,
                    _ domain: String, _ key: String, _ min: Double, _ max: Double, _ step: Double, _ unit: String,
                    integer: Bool = false, default d: Double? = nil, restart: [String] = [], timing: Timing = .instant,
                    also: [Pref] = [], currentHost: Bool = false) -> Setting {
    Setting(id: id, category: c, title: L(en, zh), detail: L(dEn, dZh),
            kind: .number(min: min, max: max, step: step, unit: unit, integer: integer), timing: timing,
            backing: .prefs([Pref(domain: domain, key: key, currentHost: currentHost)] + also, restart: restart),
            systemDefault: d.map { integer ? .int(Int($0)) : .double($0) })
}

private func choice(_ id: String, _ c: Category, _ en: String, _ zh: String, _ dEn: String, _ dZh: String,
                    _ domain: String, _ key: String, _ options: [(String, String)], default d: String,
                    restart: [String] = [], timing: Timing = .instant, asInt: Bool = false) -> Setting {
    Setting(id: id, category: c, title: L(en, zh), detail: L(dEn, dZh),
            kind: .choice(options.map { (value: $0.0, label: $0.1) }), timing: timing,
            backing: .prefs([Pref(domain: domain, key: key)], restart: restart), systemDefault: .string(d),
            intChoice: asInt)
}

private func live(_ id: String, _ c: Category, _ en: String, _ zh: String, _ dEn: String, _ dZh: String, _ feature: LiveID) -> Setting {
    Setting(id: id, category: c, title: L(en, zh), detail: L(dEn, dZh), kind: .toggle, timing: .instant,
            backing: .live(feature), systemDefault: .bool(false))
}

let catalog: [Setting] = [
    // MARK: Spaces
    live("spaces.instant", .spaces, "Switch Spaces instantly (keyboard)", "键盘切换桌面空间不带动画",
         "Your Space shortcuts jump straight to the next desktop with no slide. Turn it off and the native animation is back on the very next press.",
         "用快捷键左右切换桌面时直接跳过去,没有滑动动画。关掉后,下一次切换就恢复系统原生动画。", .instantSpaces),
    live("spaces.instantSwipe", .spaces, "Switch Spaces instantly (trackpad swipe)", "触控板横扫切换桌面不带动画",
         "A three or four finger horizontal swipe switches the Space at once instead of following your fingers.",
         "三指或四指横扫时立刻切换桌面,不再跟着手指滑动。", .instantSwipe),
    toggle("spaces.autoRearrange", .spaces, "Rearrange Spaces by recent use", "根据最近使用自动重排空间",
           "macOS reorders your desktops behind your back. Turn it off so desktop 2 is always desktop 2.",
           "系统会悄悄调整桌面顺序。关掉后,桌面 2 永远是桌面 2。", dock, "mru-spaces", default: true, restart: ["Dock"]),
    toggle("spaces.followApp", .spaces, "Jump to an app's Space when switching to it", "切换 App 时跳到它所在的空间",
           "When you activate an app, move to a Space where it already has windows.",
           "激活某个 App 时,自动跳到它已有窗口的那个桌面。", g, "AppleSpacesSwitchOnActivate", default: true, restart: ["Dock"]),
    toggle("spaces.groupByApp", .spaces, "Group windows by app in Mission Control", "调度中心按 App 分组窗口",
           "Stack each app's windows together in Mission Control.", "在调度中心里把同一个 App 的窗口叠在一起。",
           dock, "expose-group-apps", default: false, restart: ["Dock"]),

    // MARK: Animations
    toggle("motion.reduce", .motion, "Reduce motion", "减弱动态效果",
           "The system-wide accessibility switch: full-screen and Mission Control transitions become a quick fade.",
           "系统级的辅助功能开关:全屏、调度中心等过渡变成快速淡入淡出。",
           "com.apple.universalaccess", "reduceMotion", default: false, timing: .relogin),
    toggle("motion.windowOpen", .motion, "Window open and close animations", "窗口打开/关闭动画",
           "The zoom when a window or dialog appears.", "窗口和对话框出现时的缩放动画。",
           g, "NSAutomaticWindowAnimationsEnabled", default: true, timing: .newWindows),
    number("motion.windowResize", .motion, "Window resize duration", "窗口缩放时长",
           "How long sheets and animated resizes take. 0.001 is effectively instant; macOS uses 0.2.",
           "表单滑出、窗口自动缩放所花的时间。0.001 基本等于瞬间,系统默认 0.2。",
           g, "NSWindowResizeTime", 0.001, 0.5, 0.001, "s", default: 0.2, timing: .newWindows),
    number("motion.missionControl", .motion, "Mission Control animation duration", "调度中心动画时长",
           "How long Mission Control and App Exposé take to open. 0.1 is almost instant.", "打开调度中心和应用程序窗口的动画时长。0.1 几乎是瞬间。",
           dock, "expose-animation-duration", 0, 1, 0.05, "s", restart: ["Dock"]),
    number("motion.quickLook", .motion, "Quick Look animation duration", "快速查看(空格预览)动画时长",
           "How long the Space bar preview takes to open and close. 0 is instant.", "按空格预览文件时的弹出/收起时间,0 为瞬间。",
           g, "QLPanelAnimationDuration", 0, 0.5, 0.01, "s", restart: ["Finder"]),
    toggle("motion.scroll", .motion, "Smooth scrolling", "平滑滚动",
           "Animated scrolling when you press Page Down, Space or click the scroll bar.", "按翻页键、空格或点击滚动条时的滚动动画。",
           g, "NSScrollAnimationEnabled", default: true, timing: .newWindows),
    toggle("motion.finder", .motion, "Finder animations", "访达动画",
           "Window and Get Info animations in Finder.", "访达窗口和“显示简介”的动画。",
           finder, "DisableAllAnimations", default: true, restart: ["Finder"], inverted: true),
    toggle("motion.dockLaunch", .motion, "Bounce icons when apps open", "打开 App 时图标弹跳",
           "The Dock icon bounce while an app launches.", "App 启动时程序坞图标的弹跳。",
           dock, "launchanim", default: true, restart: ["Dock"]),
    choice("motion.minimize", .motion, "Minimize effect", "最小化效果",
           "Scale is the quickest of the three.", "三种效果里“缩放”最快。",
           dock, "mineffect", [("genie", L("Genie", "神奇效果")), ("scale", L("Scale", "缩放")), ("suck", L("Suck", "吸入"))],
           default: "genie", restart: ["Dock"]),

    // MARK: Power
    live("awake.display", .power, "Keep the display awake", "屏幕常亮(不熄屏)",
         "The screen never dims or sleeps while this is on. No password needed; turn it off and your normal sleep timer applies again.",
         "打开后屏幕不会变暗或熄灭,不需要管理员密码。关掉后恢复你原来的熄屏时间。", .awakeDisplay),
    live("awake.system", .power, "Keep the Mac awake", "电脑不休眠(屏幕可以熄)",
         "The Mac keeps running long jobs while idle, but the display may still sleep.",
         "空闲时电脑继续运行(适合跑长任务),但屏幕仍可熄灭。", .awakeSystem),

    // MARK: Menu bar & clock
    toggle("menubar.autohide", .menubar, "Hide the menu bar automatically", "自动隐藏菜单栏",
           "The menu bar slides away until you move the pointer to the top of the screen. Gives every window a little more height.",
           "菜单栏平时收起,指针移到屏幕顶部才出现,窗口能多出一点高度。",
           g, "_HIDE_MENU_BAR", default: false, timing: .relogin),
    number("menubar.spacing", .menubar, "Space between menu bar icons", "菜单栏图标间距",
           "Smaller numbers fit more icons before the notch hides them. 6 is compact; macOS uses about 16.",
           "数值越小,刘海挡住之前能放下的图标越多。6 比较紧凑,系统大约是 16。",
           g, "NSStatusItemSpacing", 0, 20, 1, "px", integer: true, timing: .relogin,
           also: [Pref(domain: g, key: "NSStatusItemSelectionPadding", currentHost: true)], currentHost: true),
    toggle("menubar.clockSeconds", .menubar, "Show seconds in the clock", "时钟显示秒",
           "The menu bar clock ticks every second.", "菜单栏时钟精确到秒。",
           "com.apple.menuextra.clock", "ShowSeconds", default: false, restart: ["ControlCenter"]),
    toggle("menubar.clockWeekday", .menubar, "Show the day of the week", "显示星期",
           "Mon, Tue… next to the time.", "时间旁边显示星期几。",
           "com.apple.menuextra.clock", "ShowDayOfWeek", default: true, restart: ["ControlCenter"]),
    choice("menubar.clockDate", .menubar, "Show the date", "显示日期",
           "Whether the clock includes the date.", "时钟里是否带日期。",
           "com.apple.menuextra.clock", "ShowDate",
           [("0", L("When space allows", "空间允许时")), ("1", L("Always", "始终")), ("2", L("Never", "从不"))],
           default: "0", restart: ["ControlCenter"], asInt: true),
    toggle("menubar.clock24h", .menubar, "24-hour time", "24 小时制",
           "14:05 instead of 2:05 PM, in the menu bar and in apps.", "显示 14:05 而不是下午 2:05,菜单栏和各个 App 都生效。",
           g, "AppleICUForce24HourTime", default: false, restart: ["ControlCenter"], timing: .newWindows),

    // MARK: Dock
    toggle("dock.autohide", .dock, "Hide the Dock automatically", "自动隐藏程序坞",
           "The Dock slides away until you move the pointer to the screen edge.", "程序坞平时收起,指针移到屏幕边缘才出现。",
           dock, "autohide", default: false, restart: ["Dock"]),
    number("dock.autohideDelay", .dock, "Delay before the Dock appears", "程序坞出现前的延迟",
           "How long the pointer must rest on the edge. 0 removes the wait.", "指针在边缘停留多久才弹出。0 为不等待。",
           dock, "autohide-delay", 0, 2, 0.05, "s", restart: ["Dock"]),
    number("dock.autohideSpeed", .dock, "Dock show and hide duration", "程序坞弹出/收起时长",
           "Length of the slide animation. 0 makes it appear at once.", "滑动动画的时长。0 为直接出现。",
           dock, "autohide-time-modifier", 0, 2, 0.05, "s", restart: ["Dock"]),
    number("dock.size", .dock, "Icon size", "图标大小",
           "Dock icon size in pixels.", "程序坞图标的像素大小。",
           dock, "tilesize", 16, 128, 1, "px", integer: true, restart: ["Dock"]),
    toggle("dock.magnify", .dock, "Magnify icons on hover", "悬停时放大图标",
           "Icons grow as the pointer passes over them.", "指针经过时图标放大。",
           dock, "magnification", default: false, restart: ["Dock"]),
    choice("dock.position", .dock, "Position on screen", "在屏幕上的位置",
           "Which edge the Dock sits on.", "程序坞贴在哪一边。",
           dock, "orientation", [("left", L("Left", "左边")), ("bottom", L("Bottom", "底部")), ("right", L("Right", "右边"))],
           default: "bottom", restart: ["Dock"]),
    toggle("dock.recents", .dock, "Show suggested and recent apps", "显示建议和最近使用的 App",
           "The extra section at the end of the Dock.", "程序坞末尾多出来的那一栏。",
           dock, "show-recents", default: true, restart: ["Dock"]),
    toggle("dock.minimizeToApp", .dock, "Minimize windows into the app icon", "窗口最小化到 App 图标",
           "Minimized windows hide behind their app icon instead of taking a Dock slot.", "最小化的窗口收进 App 图标,而不是在程序坞里另占一格。",
           dock, "minimize-to-application", default: false, restart: ["Dock"]),
    toggle("dock.dimHidden", .dock, "Dim icons of hidden apps", "隐藏的 App 图标变半透明",
           "Apps you hid with ⌘H get a translucent icon.", "用 ⌘H 隐藏的 App,图标变成半透明。",
           dock, "showhidden", default: false, restart: ["Dock"]),
    toggle("dock.indicators", .dock, "Show dots under open apps", "在打开的 App 下显示小圆点",
           "The running indicator below each open app.", "已打开 App 下方的指示点。",
           dock, "show-process-indicators", default: true, restart: ["Dock"]),

    toggle("dock.onlyOpenApps", .dock, "Show only open apps", "只显示已打开的 App",
           "The Dock lists running apps only, like a task bar. Pinned apps that are closed disappear.",
           "程序坞只显示正在运行的 App,像任务栏一样;没打开的固定 App 会隐藏。",
           dock, "static-only", default: false, restart: ["Dock"]),
    toggle("dock.scrollToOpen", .dock, "Scroll on an icon to show its windows", "在图标上滚动显示窗口",
           "Scroll up on a Dock icon to spread that app's windows; scroll down to put them back.",
           "在程序坞图标上向上滚动,展开这个 App 的所有窗口,向下滚动收回。",
           dock, "scroll-to-open", default: false, restart: ["Dock"]),

    // MARK: Hot corners
    choice("corners.topLeft", .corners, "Top left corner", "左上角",
           "What happens when the pointer hits this corner of the screen.", "指针碰到屏幕这个角时做什么。",
           dock, "wvous-tl-corner", [("1", L("Nothing", "无")), ("2", L("Mission Control", "调度中心")), ("3", L("App windows", "应用程序窗口")),
             ("4", L("Desktop", "桌面")), ("12", L("Notification Center", "通知中心")), ("11", L("Launchpad", "启动台")),
             ("14", L("Quick Note", "快速备忘录")), ("5", L("Start screen saver", "启动屏幕保护程序")),
             ("10", L("Put display to sleep", "让显示器进入睡眠")), ("13", L("Lock screen", "锁定屏幕"))], default: "1", restart: ["Dock"], asInt: true),
    choice("corners.topRight", .corners, "Top right corner", "右上角",
           "What happens when the pointer hits this corner of the screen.", "指针碰到屏幕这个角时做什么。",
           dock, "wvous-tr-corner", [("1", L("Nothing", "无")), ("2", L("Mission Control", "调度中心")), ("3", L("App windows", "应用程序窗口")),
             ("4", L("Desktop", "桌面")), ("12", L("Notification Center", "通知中心")), ("11", L("Launchpad", "启动台")),
             ("14", L("Quick Note", "快速备忘录")), ("5", L("Start screen saver", "启动屏幕保护程序")),
             ("10", L("Put display to sleep", "让显示器进入睡眠")), ("13", L("Lock screen", "锁定屏幕"))], default: "1", restart: ["Dock"], asInt: true),
    choice("corners.bottomLeft", .corners, "Bottom left corner", "左下角",
           "What happens when the pointer hits this corner of the screen.", "指针碰到屏幕这个角时做什么。",
           dock, "wvous-bl-corner", [("1", L("Nothing", "无")), ("2", L("Mission Control", "调度中心")), ("3", L("App windows", "应用程序窗口")),
             ("4", L("Desktop", "桌面")), ("12", L("Notification Center", "通知中心")), ("11", L("Launchpad", "启动台")),
             ("14", L("Quick Note", "快速备忘录")), ("5", L("Start screen saver", "启动屏幕保护程序")),
             ("10", L("Put display to sleep", "让显示器进入睡眠")), ("13", L("Lock screen", "锁定屏幕"))], default: "1", restart: ["Dock"], asInt: true),
    choice("corners.bottomRight", .corners, "Bottom right corner", "右下角",
           "macOS puts Quick Note here. Set Nothing if you keep triggering it by accident.", "系统默认在这里放“快速备忘录”。经常误触就设为“无”。",
           dock, "wvous-br-corner", [("1", L("Nothing", "无")), ("2", L("Mission Control", "调度中心")), ("3", L("App windows", "应用程序窗口")),
             ("4", L("Desktop", "桌面")), ("12", L("Notification Center", "通知中心")), ("11", L("Launchpad", "启动台")),
             ("14", L("Quick Note", "快速备忘录")), ("5", L("Start screen saver", "启动屏幕保护程序")),
             ("10", L("Put display to sleep", "让显示器进入睡眠")), ("13", L("Lock screen", "锁定屏幕"))], default: "14", restart: ["Dock"], asInt: true),

    // MARK: Desktop & windows
    toggle("desktop.icons", .desktop, "Show icons on the desktop", "桌面上显示图标",
           "Turn off for a completely clean desktop. The files stay in the Desktop folder.", "关掉后桌面完全干净,文件仍在“桌面”文件夹里。",
           finder, "CreateDesktop", default: true, restart: ["Finder"]),
    toggle("desktop.clickToReveal", .desktop, "Click wallpaper to reveal desktop", "点按墙纸显示桌面",
           "Off means a stray click on the wallpaper no longer throws your windows aside.", "关掉后,不小心点到墙纸不会再把所有窗口甩开。",
           wm, "EnableStandardClickToShowDesktop", default: true, restart: ["WindowManager"]),
    toggle("desktop.stageManager", .desktop, "Stage Manager", "台前调度",
           "Apple's window grouping strip on the left edge.", "屏幕左侧的窗口分组条。",
           wm, "GloballyEnabled", default: false, restart: ["WindowManager"]),
    toggle("desktop.widgets", .desktop, "Show widgets on the desktop", "桌面上显示小组件",
           "Desktop widgets when Stage Manager is off.", "未开启台前调度时,桌面上的小组件。",
           wm, "StandardHideWidgets", default: true, restart: ["WindowManager"], inverted: true),
    toggle("windows.tileByDrag", .desktop, "Tile windows by dragging to screen edges", "拖到屏幕边缘时平铺窗口",
           "The built-in edge snapping.", "系统自带的贴边平铺。",
           wm, "EnableTilingByEdgeDrag", default: true, restart: ["WindowManager"]),
    toggle("windows.tileMargins", .desktop, "Leave margins around tiled windows", "平铺的窗口之间留边距",
           "Gaps between windows tiled by macOS.", "系统平铺窗口时留出的间隙。",
           wm, "EnableTiledWindowMargins", default: true, restart: ["WindowManager"]),

    toggle("windows.dragAnywhere", .desktop, "Move windows with ⌃⌘-drag anywhere", "按住 ⌃⌘ 拖动窗口任意位置",
           "Hold Control and Command and drag from anywhere in a window to move it, not just the title bar.",
           "按住 Control 和 Command,从窗口任何地方都能拖动它,不必找标题栏。",
           g, "NSWindowShouldDragOnGesture", default: false, timing: .newWindows),
    choice("windows.doubleClickTitle", .desktop, "Double-click a title bar to", "连按窗口标题栏时",
           "What a double-click on a window's title bar does.", "双击窗口标题栏的效果。",
           g, "AppleActionOnDoubleClick",
           [("Fill", L("Fill the screen", "填充屏幕")), ("Maximize", L("Zoom", "缩放")), ("Minimize", L("Minimize", "最小化")), ("None", L("Do nothing", "不执行任何操作"))],
           default: "Fill", timing: .newWindows),
    choice("windows.tabs", .desktop, "Open documents as tabs", "以标签页打开文稿",
           "Whether new documents open as tabs in the same window instead of new windows.", "新文稿是在同一个窗口开新标签页,还是开新窗口。",
           g, "AppleWindowTabbingMode",
           [("manual", L("Never", "永不")), ("fullscreen", L("In full screen", "全屏时")), ("always", L("Always", "始终"))],
           default: "fullscreen", timing: .newWindows),

    // MARK: Finder & files
    toggle("finder.extensions", .finder, "Show all filename extensions", "显示所有文件扩展名",
           "Always show .txt, .png and friends.", "始终显示 .txt、.png 等扩展名。",
           g, "AppleShowAllExtensions", default: false, restart: ["Finder"]),
    toggle("finder.hiddenFiles", .finder, "Show hidden files", "显示隐藏文件",
           "Dotfiles and other hidden items appear dimmed.", "以点开头的文件等隐藏项目会以浅色显示。",
           finder, "AppleShowAllFiles", default: false, restart: ["Finder"]),
    toggle("finder.pathBar", .finder, "Show the path bar", "显示路径栏",
           "The folder trail at the bottom of Finder windows.", "访达窗口底部的文件夹路径。",
           finder, "ShowPathbar", default: false, restart: ["Finder"]),
    toggle("finder.statusBar", .finder, "Show the status bar", "显示状态栏",
           "Item count and free space at the bottom of Finder windows.", "访达窗口底部的项目数和可用空间。",
           finder, "ShowStatusBar", default: false, restart: ["Finder"]),
    toggle("finder.pathInTitle", .finder, "Show the full path in the window title", "窗口标题显示完整路径",
           "Titles read /Users/you/Projects instead of Projects.", "标题显示 /Users/you/Projects 而不是 Projects。",
           finder, "_FXShowPosixPathInTitle", default: false, restart: ["Finder"]),
    toggle("finder.foldersFirst", .finder, "Keep folders on top when sorting by name", "按名称排序时文件夹置顶",
           "Folders are listed before files.", "文件夹排在文件前面。",
           finder, "_FXSortFoldersFirst", default: false, restart: ["Finder"]),
    choice("finder.view", .finder, "Default view for new windows", "新窗口的默认显示方式",
           "Applies to folders that have no saved view of their own.", "对没有单独保存过显示方式的文件夹生效。",
           finder, "FXPreferredViewStyle",
           [("icnv", L("Icons", "图标")), ("Nlsv", L("List", "列表")), ("clmv", L("Columns", "分栏")), ("glyv", L("Gallery", "画廊"))],
           default: "icnv", restart: ["Finder"]),
    choice("finder.searchScope", .finder, "When performing a search", "执行搜索时",
           "Where Finder looks first.", "访达默认在哪里搜索。",
           finder, "FXDefaultSearchScope",
           [("SCev", L("Search this Mac", "搜索这台 Mac")), ("SCcf", L("Search the current folder", "搜索当前文件夹")), ("SCsp", L("Use the previous scope", "使用上次的范围"))],
           default: "SCev", restart: ["Finder"]),
    toggle("finder.extensionWarning", .finder, "Warn before changing an extension", "更改扩展名前警告",
           "The confirmation dialog when you rename .txt to .md.", "把 .txt 改成 .md 时弹出的确认框。",
           finder, "FXEnableExtensionChangeWarning", default: true, restart: ["Finder"]),
    toggle("finder.noNetworkDSStore", .finder, "Don't write .DS_Store on network drives", "不在网络磁盘上写 .DS_Store",
           "Keeps shared folders free of Finder's bookkeeping files.", "避免在共享文件夹里留下访达的记录文件。",
           "com.apple.desktopservices", "DSDontWriteNetworkStores", default: false, timing: .relogin),
    toggle("finder.noUSBDSStore", .finder, "Don't write .DS_Store on USB drives", "不在 U 盘上写 .DS_Store",
           "Keeps removable drives clean.", "保持移动硬盘和 U 盘干净。",
           "com.apple.desktopservices", "DSDontWriteUSBStores", default: false, timing: .relogin),
    toggle("files.expandSavePanel", .finder, "Expand save dialogs by default", "保存对话框默认展开",
           "Show the full file browser instead of the compact sheet.", "直接显示完整的文件浏览器,而不是精简面板。",
           g, "NSNavPanelExpandedStateForSaveMode", default: false, timing: .newWindows,
           also: [Pref(domain: g, key: "NSNavPanelExpandedStateForSaveMode2")]),
    toggle("files.saveToICloud", .finder, "Save new documents to iCloud by default", "新文稿默认存到 iCloud",
           "Turn off so save dialogs start on this Mac.", "关掉后保存对话框默认定位到本机。",
           g, "NSDocumentSaveNewDocumentsToCloud", default: true, timing: .newWindows),

    toggle("finder.emptyTrash30Days", .finder, "Empty the Trash after 30 days", "30 天后自动清倒废纸篓",
           "Items in the Trash for more than 30 days are deleted for good.", "在废纸篓里放了 30 天以上的项目会被永久删除。",
           finder, "FXRemoveOldTrashItems", default: false, restart: ["Finder"]),
    toggle("finder.warnEmptyTrash", .finder, "Warn before emptying the Trash", "清倒废纸篓前警告",
           "The confirmation dialog when you empty the Trash.", "清倒废纸篓时弹出的确认框。",
           finder, "WarnOnEmptyTrash", default: true, restart: ["Finder"]),
    toggle("finder.externalDisksOnDesktop", .finder, "Show external disks on the desktop", "桌面上显示外置磁盘",
           "USB drives and external disks get a desktop icon when connected.", "接上 U 盘或移动硬盘时,桌面上出现它的图标。",
           finder, "ShowExternalHardDrivesOnDesktop", default: true, restart: ["Finder"]),
    toggle("finder.quitMenu", .finder, "Allow quitting Finder with ⌘Q", "允许用 ⌘Q 退出访达",
           "Adds Quit Finder to the Finder menu, which also hides its desktop icons until you reopen it.",
           "在访达菜单里加上“退出访达”,退出后桌面图标也会隐藏,直到再次打开访达。",
           finder, "QuitMenuItem", default: false, restart: ["Finder"]),

    // MARK: Keyboard & trackpad
    number("keyboard.repeat", .keyboard, "Key repeat interval", "按键重复间隔",
           "Lower is faster. 2 is the fastest System Settings offers, 1 is faster still; macOS starts at 6.",
           "数值越小越快。系统设置里最快是 2,1 更快;系统默认 6。",
           g, "KeyRepeat", 1, 120, 1, "", integer: true, default: 6, timing: .relogin),
    number("keyboard.repeatDelay", .keyboard, "Delay until repeat", "重复前延迟",
           "Lower is shorter. 15 is the shortest System Settings offers; macOS starts at 25.",
           "数值越小越短。系统设置里最短是 15;系统默认 25。",
           g, "InitialKeyRepeat", 10, 120, 1, "", integer: true, default: 25, timing: .relogin),
    toggle("keyboard.pressAndHold", .keyboard, "Hold a key for accent menu", "长按按键弹出重音符菜单",
           "Off makes held keys repeat instead, which Vim users expect.", "关掉后长按改为连续输入,Vim 用户需要这个。",
           g, "ApplePressAndHoldEnabled", default: true, timing: .newWindows),
    toggle("keyboard.fnKeys", .keyboard, "Use F1, F2, etc. as standard function keys", "将 F1、F2 等用作标准功能键",
           "Press Fn to reach brightness and volume instead.", "亮度和音量改为按住 Fn 再按。",
           g, "com.apple.keyboard.fnState", default: false, timing: .relogin),
    toggle("text.autocorrect", .keyboard, "Correct spelling automatically", "自动纠正拼写",
           "macOS rewrites words as you type.", "输入时系统自动改写单词。",
           g, "NSAutomaticSpellingCorrectionEnabled", default: true, timing: .newWindows,
           also: [Pref(domain: g, key: "WebAutomaticSpellingCorrectionEnabled")]),
    toggle("text.capitalize", .keyboard, "Capitalize words automatically", "自动大写字词的首字母",
           "Annoying when typing code or commands.", "写代码或命令时很碍事。",
           g, "NSAutomaticCapitalizationEnabled", default: true, timing: .newWindows),
    toggle("text.doubleSpacePeriod", .keyboard, "Add a period with double-space", "连按两下空格键插入句号",
           "Two spaces become a full stop.", "两个空格变成一个句号。",
           g, "NSAutomaticPeriodSubstitutionEnabled", default: true, timing: .newWindows),
    toggle("text.smartQuotes", .keyboard, "Smart quotes", "智能引号",
           "Straight quotes turn curly, which breaks pasted code.", "直引号自动变弯引号,会弄坏粘贴的代码。",
           g, "NSAutomaticQuoteSubstitutionEnabled", default: true, timing: .newWindows),
    toggle("text.smartDashes", .keyboard, "Smart dashes", "智能破折号",
           "Two hyphens turn into a long dash.", "两个连字符自动变成长破折号。",
           g, "NSAutomaticDashSubstitutionEnabled", default: true, timing: .newWindows),
    toggle("trackpad.tapToClick", .pointer, "Tap to click", "轻点来点按",
           "A light tap counts as a click.", "轻触触控板即算点按。",
           "com.apple.AppleMultitouchTrackpad", "Clicking", default: false, timing: .relogin,
           also: [Pref(domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad", key: "Clicking")]),

    choice("keyboard.fullAccess", .keyboard, "Move focus with Tab in dialogs", "在对话框里用 Tab 切换所有控件",
           "Tab reaches every button and control, not only text fields, so dialogs work without the mouse.",
           "Tab 键可以选中所有按钮和控件,而不只是文本框,对话框不用鼠标也能操作。",
           g, "AppleKeyboardUIMode", [("0", L("Text fields only", "仅文本框")), ("2", L("All controls", "所有控件"))],
           default: "0", timing: .newWindows, asInt: true),
    toggle("text.inlinePrediction", .keyboard, "Show inline predictive text", "显示行内预测文本",
           "The grey suggestions that appear ahead of the cursor as you type.", "打字时光标后面出现的灰色补全建议。",
           g, "NSAutomaticInlinePredictionEnabled", default: true, timing: .newWindows),

    // MARK: Trackpad & mouse
    toggle("trackpad.naturalScroll", .pointer, "Natural scrolling", "自然滚动",
           "Content follows your fingers. Off makes scrolling work like a classic mouse wheel. Applies to mice too.",
           "内容跟着手指走。关掉后滚动方向和传统鼠标滚轮一样,鼠标也受影响。",
           g, "com.apple.swipescrolldirection", default: true, timing: .relogin),
    toggle("trackpad.threeFingerDrag", .pointer, "Three-finger drag", "三指拖移",
           "Drag windows and select text with three fingers, without pressing.", "用三根手指直接拖动窗口、选中文本,不用按下触控板。",
           "com.apple.AppleMultitouchTrackpad", "TrackpadThreeFingerDrag", default: false, timing: .relogin,
           also: [Pref(domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad", key: "TrackpadThreeFingerDrag")]),
    toggle("trackpad.forceClick", .pointer, "Force Click and haptic feedback", "用力点按和触觉反馈",
           "Press harder to look up a word or preview a link.", "用力按下可以查询单词或预览链接。",
           g, "com.apple.trackpad.forceClick", default: true, timing: .relogin),
    number("trackpad.speed", .pointer, "Trackpad tracking speed", "触控板跟踪速度",
           "How far the pointer moves. System Settings goes up to 3.", "指针移动的快慢。系统设置里最大是 3。",
           g, "com.apple.trackpad.scaling", 0, 3, 0.125, "", timing: .relogin),
    number("mouse.speed", .pointer, "Mouse tracking speed", "鼠标跟踪速度",
           "How far the pointer moves with a mouse. System Settings goes up to 3.", "使用鼠标时指针移动的快慢。系统设置里最大是 3。",
           g, "com.apple.mouse.scaling", 0, 3, 0.125, "", timing: .relogin),

    // MARK: Screenshots
    choice("screenshots.format", .screenshots, "File format", "文件格式",
           "JPG files are much smaller; PNG is lossless.", "JPG 文件小得多;PNG 无损。",
           shot, "type", [("png", "PNG"), ("jpg", "JPG"), ("heic", "HEIC"), ("pdf", "PDF"), ("tiff", "TIFF")],
           default: "png", restart: ["SystemUIServer"]),
    Setting(id: "screenshots.location", category: .screenshots, title: L("Save location", "保存位置"),
            detail: L("Folder for new screenshots, for example ~/Pictures/Screenshots. Empty means the Desktop.",
                      "新截图保存到的文件夹,例如 ~/Pictures/Screenshots。留空为桌面。"),
            kind: .text, timing: .instant,
            backing: .prefs([Pref(domain: shot, key: "location")], restart: ["SystemUIServer"]), systemDefault: nil),
    toggle("screenshots.shadow", .screenshots, "Window shadow in screenshots", "窗口截图带阴影",
           "The soft shadow around ⇧⌘4-Space window captures.", "用 ⇧⌘4 加空格截取窗口时四周的阴影。",
           shot, "disable-shadow", default: true, restart: ["SystemUIServer"], inverted: true),
    toggle("screenshots.thumbnail", .screenshots, "Show floating thumbnail", "显示浮动缩略图",
           "The preview in the corner that delays the file by a few seconds.", "右下角的预览,它会让文件晚几秒才保存。",
           shot, "show-thumbnail", default: true, restart: ["SystemUIServer"]),

    toggle("screenshots.date", .screenshots, "Date and time in file names", "文件名里带日期时间",
           "\"Screenshot 2026-11-11 at 17.30.12\" instead of just \"Screenshot\".", "文件名是“截屏 2026-11-11 17.30.12”而不只是“截屏”。",
           shot, "include-date", default: true, restart: ["SystemUIServer"]),

    // MARK: System & apps
    choice("ui.scrollBars", .system, "Show scroll bars", "显示滚动条",
           "Always is easier to grab with a mouse.", "选“始终”用鼠标更容易拖动。",
           g, "AppleShowScrollBars",
           [("Automatic", L("Based on mouse or trackpad", "根据鼠标或触控板自动显示")), ("WhenScrolling", L("When scrolling", "滚动时")), ("Always", L("Always", "始终"))],
           default: "Automatic", timing: .newWindows),
    choice("ui.sidebarIcons", .system, "Sidebar icon size", "边栏图标大小",
           "Finder, Mail and other app sidebars.", "访达、邮件等 App 的边栏。",
           g, "NSTableViewDefaultSizeMode", [("1", L("Small", "小")), ("2", L("Medium", "中")), ("3", L("Large", "大"))],
           default: "2", timing: .newWindows, asInt: true),
    toggle("apps.keepWindows", .system, "Reopen windows when an app relaunches", "App 重新打开时恢复窗口",
           "Off is macOS's \"Close windows when quitting an application\": apps start clean every time.",
           "关掉即系统的“退出 App 时关闭窗口”:每次打开 App 都是干净的。",
           g, "NSQuitAlwaysKeepsWindows", default: false, timing: .newWindows),
    toggle("sound.uiEffects", .system, "Play user interface sound effects", "播放用户界面音效",
           "The sounds for emptying the Trash, moving files and taking screenshots.", "清倒废纸篓、移动文件、截图时的音效。",
           "com.apple.systemsound", "com.apple.sound.uiaudio.enabled", default: true, timing: .relogin),
    toggle("sound.volumeFeedback", .system, "Play feedback when the volume changes", "调节音量时播放反馈音",
           "The pop you hear when pressing the volume keys.", "按音量键时听到的“啵”一声。",
           g, "com.apple.sound.beep.feedback", default: false, timing: .relogin),
    toggle("apps.photosOnConnect", .system, "Open Photos when an iPhone is connected", "连接 iPhone 时打开“照片”",
           "Off stops Photos from popping up every time you plug in a phone or camera to charge.",
           "关掉后,插上手机或相机充电时不会再弹出“照片”。",
           "com.apple.ImageCapture", "disableHotPlug", default: true, inverted: true, currentHost: true),
    toggle("apps.timeMachineNewDisks", .system, "Offer new disks for Time Machine", "提示用新磁盘做时间机器备份",
           "Off stops the \"Use this disk to back up with Time Machine?\" question for every drive you plug in.",
           "关掉后,每次插入新硬盘都不会再问“要用这个磁盘做时间机器备份吗?”",
           "com.apple.TimeMachine", "DoNotOfferNewDisksForBackup", default: true, inverted: true),

    // MARK: Knobs itself
    live("app.launchAtLogin", .app, "Open Knobs at login", "登录时打开 Knobs",
         "Needed for instant Spaces and keep-awake to come back after a restart.",
         "重启后要让“无动画切换”和“屏幕常亮”继续生效,需要打开这一项。", .launchAtLogin),
]

let catalogByID: [String: Setting] = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
