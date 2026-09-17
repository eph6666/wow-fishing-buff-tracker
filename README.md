# Fishing Buff Tracker

一个面向 World of Warcraft Retail 的钓鱼 Buff 状态栏插件。

当前版本：`0.3.0`，面向 Retail `12.1.0`。
更新内容见 [CHANGELOG.md](CHANGELOG.md)，本地验证见
[tests/README.md](tests/README.md)，实机待验项目见
[客户端验收清单](docs/CLIENT_TEST_PLAN.md)。

## 功能

- 横向显示钓鱼 Buff，可通过左侧三横线手柄拖拽。
- 状态栏右侧可直接关闭，并可从设置控制台重新显示。
- Buff 存在时显示 Aura 图标和剩余时间。
- 效果数据受客户端限制时显示未知状态；受限的时间或层数显示 `?`。
- Buff 缺失时物品图标显示为灰色；获得 Buff 后恢复彩色。
- Buff 缺失时仍显示对应物品、数量和冷却，点击即可使用。
- 支持物品、Toy 和 secure macro 三种动作。
- 诱饵条目未激活时自动隐藏。
- 内置设置面板可启用、编辑、排序和新增自定义条目。
- 设置保存在账号级 `FishingBuffTrackerDB`。

设置中的文本在回车或失焦时提交。Buff、背包和冷却刷新会保留正在编辑的
草稿；排序、删除、恢复默认、切换条目或关闭面板时，仍未提交的草稿会取消。
图标上的 `?` 表示对应信息暂时无法确认，不代表 Buff 已经消失。
宏条目的 ItemID、临时附魔的追踪 ID 为只读，悬停可查看说明。
加载时会校验保存的配置，保留有效条目与偏好，恢复损坏的字段。

## 安装

从 GitHub Releases 下载 `FishingBuffTracker-v0.3.0.zip`，解压后将整个
`FishingBuffTracker` 目录复制到：

```text
World of Warcraft/_retail_/Interface/AddOns/FishingBuffTracker
```

最终目录应包含：

```text
FishingBuffTracker/
├── FishingBuffTracker.toc
├── Data.lua
├── Core.lua
├── Bar.lua
└── Config.lua
```

进入游戏后执行：

```text
/reload
```

## 命令

- `/fbt` 或 `/fbt config`：打开设置控制台。
- `/钓鱼buff`、`/fishingbuff`：打开设置控制台。
- `/fbt show`：显示状态栏。
- `/fbt hide`：隐藏状态栏。
- `/fbt unlock`：解锁状态栏。
- `/fbt lock`：锁定状态栏。
- `/fbt reset`：重置状态栏位置。
- `/fbt defaults`：恢复内置条目。
- `/fbt status`：在聊天框打印已应用的启用条目状态、追踪 ID 和物品数量。

## 内置条目

| 名称 | ItemID | 追踪对象 |
|---|---:|---:|
| 可重复使用的巨型鱼漂 | 202207 | 397827 |
| 哈籁尼尔感知瓶剂 | 241316 | 1236763 |
| 晶华感知瓶剂 | 191354 | Aura 393714 |
| 血艳蓟茶 | 242299 | 1269152 |
| 尖刺钉螺 | 262651 | 栏位 28 的临时附魔 8675 |
| 乌拉特克蛇头鱼诱饵 | 277821 | 1302820 |
| 剧毒特拉皮鱼 | 274588 | 1303623 |
| 斑点鱂鱼 | 274587 | 1303624 |

晶华感知瓶剂的使用法术为 `371454`，当前按数据库支持的 Aura `393714`
追踪；尖刺钉螺的使用法术为 `1284999`，按临时附魔 `8675` 追踪。
两者的真实客户端返回仍需验收。仍使用旧默认定义的已有条目会定向迁移，
保留名称、停用状态、顺序等偏好；用户自行改过的动作和追踪定义不会被覆盖。

## 尖刺钉螺验证

当前实现使用以下 secure macro，将物品应用到钓鱼专业工具栏位 28：

```text
/use item:262651
/use 28
```

并检查栏位 28 是否装备 ItemID `244790`。该动作必须在 Retail 12.1.0
客户端中实测，因为本机没有安装可用于运行验证的 WoW 客户端。

建议测试步骤：

1. 装备 ItemID `244790`。
2. 确保背包中有 ItemID `262651`。
3. 在非战斗状态点击尖刺钉螺图标。
4. 确认物品被消耗，并执行下列命令检查栏位附魔：

   ```text
   /dump C_PaperDollInfo.GetTemporaryEnchantmentInfo(28)
   ```

5. 核对 `enchantID` 是否为 `8675`、剩余时间是否合理，并执行
   `/fbt status` 保存结果。

## 已知边界

- Secure 按钮的动作、显隐和布局变更会在战斗结束后应用。
- 战斗中编辑条目时，状态栏继续显示和使用已应用的配置；脱战后统一应用
  最新设置。`/fbt status` 会提示尚未应用的更改。
- Buff 图标负责使用物品，不再承担拖拽；请拖动状态栏左侧的三横线手柄。
- 战斗中关闭或显示状态栏时，操作会排队到战斗结束。
- 拖动中进入战斗后松手，会在脱战后停止和保存位置；排队的位置重置随后生效。
- 血艳蓟茶需要持续饮用至少 10 秒，Buff 不会在首次点击时立即出现。
- 点击一个已经激活的条目仍可能再次使用物品，用于延长可叠加持续时间。
- 当前版本面向 Retail 12.1.0，`.toc` Interface 为 `120100`。

## 开发与打包

源码位于 `FishingBuffTracker/`，回归测试位于 `tests/`，使用与验收文档位于
`docs/`。本地审查笔记保存在被忽略的 `.local/notes/`，安装包生成到 `dist/`。

运行本地测试后，用 Python 3 生成只包含插件运行文件的安装包和校验和：

```bash
python3 scripts/package.py --version v0.3.0
```

发布时更新 TOC、更新记录和对应的 `docs/releases/v版本.md`，再推送同版本
Git 标签。GitHub Actions 会重跑 Lua 5.1 回归及固定版本的 Blizzard 源码契约，
通过后创建 Release，上传 ZIP、tar.gz 和 `SHA256SUMS`。
