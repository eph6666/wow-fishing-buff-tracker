# Fishing Buff Tracker 开发交接

更新时间：2026-09-16

当前版本：`0.2.1`

目标客户端：World of Warcraft Retail `12.1.0`

插件源码目录：`FishingBuffTracker/`

## 一、产品目标

开发一个钓鱼 Buff 状态栏插件，用于检查常用钓鱼 Buff，并在 Buff
缺失时提供对应物品或 Toy 的快捷使用入口。

插件不依赖 Ace3 等第三方库，使用原生 WoW AddOn API。

## 二、完整需求

### 1. 状态栏

- 横向排列所有启用的 Buff。
- 状态栏可移动，位置保存到账号级 SavedVariables。
- 使用左侧三横线专用手柄拖动，Buff 图标本身只负责使用物品。
- 状态栏可锁定；锁定时手柄变暗并停止响应拖动。
- 状态栏右侧有关闭按钮。
- 关闭后可通过控制台或 Slash Command 重新显示。
- 支持调整图标大小、图标间距和整体缩放。

### 2. Buff 与物品状态

- 有 Buff：
  - 显示 Aura 图标。
  - 图标保持彩色。
  - 显示剩余时间。
  - Aura 可叠加时显示层数。
- 无 Buff：
  - 显示对应 Item 或 Toy 图标。
  - 图标必须显示为灰色。
  - 显示背包数量和物品冷却。
  - 点击图标使用对应 Item 或 Toy。
- 没有对应物品时，可通过设置决定是否保留该灰色栏位。

### 3. 诱饵

- 支持配置多个诱饵条目，相当于多选。
- 诱饵没有 Buff 时不提示物品，整个条目隐藏。
- 诱饵 Buff 存在时显示对应 Aura。
- 当前内置诱饵为乌拉特克蛇头鱼诱饵，后续可通过控制台添加更多。

### 4. 控制台

控制台注册在 WoW `Settings` 面板中，支持：

- 显示或隐藏状态栏。
- 锁定或解锁状态栏。
- 重置状态栏位置。
- 恢复内置列表。
- 调整图标大小、间距和缩放。
- 启用或停用条目。
- 修改名称、ItemID 和 SpellID。
- 在 Item 与 Toy 动作之间切换。
- 将条目标记为诱饵。
- 调整条目顺序。
- 删除自定义条目。
- 添加自定义 Buff 条目。

### 5. Slash Commands

- `/fbt`：打开控制台。
- `/fbt config`：打开控制台。
- `/钓鱼buff`：打开控制台。
- `/fishingbuff`：打开控制台。
- `/fbt show`：显示状态栏。
- `/fbt hide`：隐藏状态栏。
- `/fbt lock`：锁定状态栏。
- `/fbt unlock`：解锁状态栏。
- `/fbt reset`：重置位置。
- `/fbt defaults`：恢复内置条目。
- `/fbt status`：输出所有启用条目的 Aura、SpellID、物品数量和渔竿检查结果。

## 三、内置数据

| 分类 | 名称 | ItemID | Aura SpellID | 动作 |
|---|---|---:|---:|---|
| 鱼漂 | 可重复使用的巨型鱼漂 | 202207 | 397827 | Toy |
| 瓶剂 | 哈籁尼尔感知瓶剂 | 241316 | 1236763 | Item |
| 瓶剂 | 晶华感知瓶剂 | 191354 | 371454 | Item |
| 食物 | 血艳蓟茶 | 242299 | 1269152 | Item |
| 鱼漂 | 尖刺钉螺 | 262651 | 1284999 | Secure macro |
| 诱饵 | 乌拉特克蛇头鱼诱饵 | 277821 | 1302820 | Item |
| 鱼 | 剧毒特拉皮鱼 | 274588 | 1303623 | Item |
| 鱼 | 斑点鱂鱼 | 274587 | 1303624 | Item |

补充数据：

- 尖刺钉螺要求钓鱼装备栏装备渔竿 ItemID `244790`。
- 当前 Blizzard UI 中钓鱼专业工具栏位为 inventory slot `28`。
- 尖刺钉螺当前使用：

```text
/use item:262651
/use 28
```

- 乌拉特克 SpellID `1302819` 是制作配方，不是需要监控的 Buff。
- 晶华感知瓶剂 SpellID `396962` 是通用 Phial 行为，实际监控 `371454`。
- 血艳蓟茶需要持续饮用至少 10 秒才获得 Aura `1269152`。

## 四、技术实现

### Data.lua

- 定义默认状态栏配置。
- 定义全部内置条目。
- 定义分类和动作显示名称。

### Core.lua

- 初始化和迁移 `FishingBuffTrackerDB`。
- 合并新增的内置条目。
- 使用 `AuraUtil.ForEachAura` 扫描 `player` 的 `HELPFUL` Aura。
- 处理物品数量、Toy 所有权和钓鱼装备检查。
- 处理事件、战斗结束后的延迟更新以及 Slash Commands。

### Bar.lua

- 使用 `SecureActionButtonTemplate` 创建可点击 Buff 按钮。
- Item 使用 secure action type `item`。
- Toy 使用 secure action type `toy`。
- 尖刺钉螺使用 secure action type `macro`。
- Buff 存在时显示彩色 Aura；不存在时显示灰色 Item。
- 显示倒计时、层数、数量、冷却和装备警告。
- 左侧普通 Button 是专用拖动手柄，避免与 secure 物品按钮冲突。
- 右侧使用 `UIPanelCloseButton` 关闭状态栏。

### Config.lua

- 使用 `Settings.RegisterCanvasLayoutCategory` 注册控制台。
- 原生创建 Checkbox、EditBox、Button 和 ScrollFrame。
- 修改 secure action 或布局时，通过 `RequestRebuild` 在非战斗状态重建。

### SavedVariables

账号级变量：

```lua
FishingBuffTrackerDB = {
    version = 1,
    frame = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -180,
        scale = 1,
        iconSize = 40,
        spacing = 4,
        locked = false,
        visible = true,
        showUnavailable = true,
    },
    entries = {},
}
```

## 五、开发历史

### 调研阶段

- 确认 Retail `12.1.0` 可使用 `C_UnitAuras`、`AuraUtil`、
  `SecureActionButtonTemplate`、`C_Item`、Toy secure action 和 `Settings` API。
- 从 Blizzard UI source snapshot 确认 `FishingToolSlot` 为 slot `28`。
- 补齐未知数据：
  - 可重复使用的巨型鱼漂 ItemID `202207`。
  - 晶华感知瓶剂 Aura SpellID `371454`。
  - 尖刺钉螺 Aura SpellID `1284999`。
  - 乌拉特克蛇头鱼诱饵 Aura SpellID `1302820`。

### v0.1.0

- 完成第一版横向状态栏。
- 支持 Aura 扫描、倒计时、物品数量、冷却和 secure 点击。
- 完成设置控制台、自定义条目和 Slash Commands。
- 初次打包为 ZIP。

### v0.2.0

- 增加状态栏关闭按钮。
- 控制台增加“显示状态栏”。
- 增加 `/fbt config`、`show`、`hide` 和 `/fishingbuff`。
- 统一显示规则：无 Buff 灰色，有 Buff 彩色。
- 生成 ZIP 和 tar.gz。

### v0.2.1

- 修复状态栏难以拖动的问题。
- 原因：拖拽事件原本绑定在 `SecureActionButtonTemplate` Buff 图标上，
  与点击使用物品的行为冲突，父窗口又没有独立可点击拖动区域。
- 删除 Buff 图标上的拖拽事件。
- 新增左侧三横线专用拖动手柄。
- 增加拖动开始、停止和锁定状态测试。

## 六、验证情况

已经验证：

- 所有 Lua 文件通过 Lua `5.1` 语法解析。
- mock WoW API 可完整加载 `Data.lua`、`Core.lua`、`Bar.lua` 和 `Config.lua`。
- SavedVariables 初始化成功。
- 8 个内置 secure 按钮创建成功。
- Item、Toy 和 Macro secure attributes 绑定成功。
- 缺失 Buff 图标为灰色，存在 Buff 时恢复彩色。
- 关闭、重新显示和 Slash Commands 通过 mock 测试。
- 专用手柄可触发 `StartMoving` 和 `StopMovingOrSizing`。
- `0.2.1` tar.gz 内容和压缩数据校验通过。

尚未验证：

- 本机没有安装 WoW，因此没有进行真实客户端运行。
- 尖刺钉螺的两行 secure macro 是否能在 Retail 客户端中一键应用到
  profession fishing tool slot `28`。
- Retail `12.1.0` 的实际 Aura 是否全部与数据库 ID 一致。
- 真实客户端中的 Settings 控制台视觉布局。
- 真实客户端中 secure 按钮、拖动手柄和战斗锁定的交互。

## 七、文件结构

```text
wow-fishing-buff-tracker/
├── FishingBuffTracker/
│   ├── FishingBuffTracker.toc
│   ├── Data.lua
│   ├── Core.lua
│   ├── Bar.lua
│   └── Config.lua
├── tests/
│   └── smoke.lua
├── README.md
├── RESEARCH.md
├── DEVELOPMENT_HANDOFF.md
└── .gitignore
```

发布包 `FishingBuffTracker-v0.2.1.tar.gz` 只包含可安装的
`FishingBuffTracker/` 目录。

发布包 SHA256：

```text
f02fd640d00dc4ae5865db00b1d2986c1418764ad6dab59f8a2821f62516bc53
```

## 八、Git 与设备迁移

- 这是位于工作区内部的独立 Git repository。
- 默认分支为 `main`。
- GitHub 上传已取消，没有配置 remote。
- 交接时已将 `v0.2.1` 源码、测试和本文档整理为本地提交。
- `.gitignore` 排除 `*.zip`、`*.tar.gz` 和 `.DS_Store`。

换设备时建议复制整个 `wow-fishing-buff-tracker/` 目录，而不仅是游戏安装包。
如果只复制 `FishingBuffTracker-v0.2.1.tar.gz`，会缺少测试、研究记录和 Git
开发历史。

新设备检查命令：

```bash
cd wow-fishing-buff-tracker
git status
git log --oneline --decorate -5
sed -n '1,15p' FishingBuffTracker/FishingBuffTracker.toc
```

安装到游戏：

```bash
tar -xzf FishingBuffTracker-v0.2.1.tar.gz
cp -R FishingBuffTracker \
  "/path/to/World of Warcraft/_retail_/Interface/AddOns/"
```

## 九、下一步建议

1. 在 Retail `12.1.0` 中加载插件并开启 Lua 错误显示。
2. 执行 `/fbt status`，核对所有 Aura SpellID。
3. 实测左侧手柄拖动、锁定、关闭和控制台重新显示。
4. 实测所有 Item/Toy 点击。
5. 单独验证尖刺钉螺和 slot `28`。
6. 根据真实客户端截图调整 Settings 控制台布局。
7. 验证完成后发布 `0.3.0`。
