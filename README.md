# azure桌面小板

macOS 菜单栏草稿小面板：随手记，一键追加进系统「备忘录」。

## 功能

- **菜单栏常驻「小板」**：点击弹出无边框悬浮面板（不抢焦点、点外面自动收起），没有 Dock 图标
- **防抖自动存草稿**：停止输入 0.5 秒后自动写入 `UserDefaults`（`com.azure.smallpanel` 域，键 `AzurePanel_Draft_Content`）；重启电脑、退出应用后重新打开，草稿原样恢复
- **保存到备忘录（⌘↩）**：通过 AppleScript（osascript）把「时间戳 + 正文」追加到同一条「azure桌面小板」备忘录末尾，不存在会自动创建
- **四则运算**：某行末尾输入 `=`（如 `12+34=`），右侧立刻跳出灰色答案；**回车**把答案固定成正文并换行；光标移走或继续输入则灰色答案消失。支持 `+ - × ÷`、括号、小数、负数、中文符号（＋－×÷＝），可链式接算（`12+34=46+2=` → 48）；灰色答案不计入草稿和备忘录，只有回车固定后才算正文
- **绝不丢字**：点保存前先把当前输入立刻落盘；只有写入**成功**才清空输入框和草稿；失败（没授权 / 超时 / 备忘录无响应）草稿原样保留，错误原因显示在按钮上方，可直接重试
- **粘贴只要纯文字**：⌘V / 拖拽进来的富文本会丢掉字体、颜色、附件，只保留文字（自动清理不换行空格、零宽字符、Windows 换行符）
- **图片自动 OCR**：剪贴板里只有图片（或拖入图片）时，用系统 Vision 框架识别中英文文字后插入，识别过程与结果在底部状态栏提示；识别不到就什么也不插
- **面板可拉伸**：拖面板边缘即可放大缩小（280×226 ~ 520×700），拉伸后的尺寸会记住，下次打开沿用
- **滚动查看**：文字多到溢出时，输入区自动出现滚动条（/双指滑动/方向键都能翻）
- **齿轮菜单**：打开备忘录 App、开机自启开关、清除草稿、退出

## 构建与运行

不需要 Xcode 工程，一条命令即可（已装 Command Line Tools 就能编译）：

```bash
./build.sh            # 只构建
./build.sh --run      # 构建并启动（项目 build 目录版本）
./build.sh --install  # 构建并安装到 /Applications 后启动（推荐，配合开机自启）
```

产物在 `build/azure桌面小板.app`，建议拖进「应用程序」文件夹长期使用。

## 打安装包（DMG）

```bash
./make_dmg.sh
```

产物在 `dist/azure桌面小板-1.0.dmg`：双击打开 → 把 app 拖进 Applications 文件夹即完成安装。
注意：app 是 ad-hoc 签名（无开发者证书），发给别人首次打开需 **右键 → 打开**，或先执行 `xattr -cr /Applications/azure桌面小板.app` 去掉隔离属性。

## 首次保存的授权（重要）

第一次点「保存到备忘录」时，macOS 会弹窗：

> "azure桌面小板"想要访问控制"备忘录" → 点 **允许**

如果之前点过「不允许」：

1. 系统设置 → 隐私与安全性 → 自动化 → azure桌面小板 → 打开「备忘录」开关
2. 如果列表里根本没有这一项，先重置授权再重试：
   ```bash
   tccutil reset AppleEvents com.azure.smallpanel
   ```

## 开机自启

1. 先执行 `./build.sh --install`，把 app 装到 /Applications（固定位置）
2. 点面板左上角齿轮 → 「开机自启」，系统弹窗里点「允许」
3. 也可以在 系统设置 → 通用 → 登录项与扩展 里手动添加 / 管理

以后更新代码后重新 `./build.sh --install` 一次即可，登录项无需重新配置。

## 草稿数据

- 位置：`~/Library/Preferences/com.azure.smallpanel.plist`
- 手动清除草稿：
  ```bash
  defaults delete com.azure.smallpanel AzurePanel_Draft_Content
  ```

## 目录结构

```
azure-desktop-panel/
├── Sources/
│   ├── AzurePanelApp.swift      # @main 入口（SwiftUI App 生命周期）
│   ├── AppDelegate.swift        # 菜单栏「小板」状态项 + 退出前兜底落盘
│   ├── FloatingPanel.swift      # 无边框 NSPanel：弹出、定位、失焦自动隐藏
│   ├── PanelContentView.swift   # 面板 UI + PanelViewModel（防抖/保存状态机）
│   ├── DraftStore.swift         # UserDefaults 草稿读写
│   └── NotesSaver.swift         # osascript 追加写入备忘录（含超时看门狗与错误提示）
├── Resources/Info.plist         # LSUIElement（无 Dock 图标）等
└── build.sh                     # swiftc 一键编译打包
```
