# Fishing Buff Tracker

一个面向 World of Warcraft Retail 的钓鱼 Buff 状态栏插件。

## 功能

- 横向显示钓鱼 Buff，可通过左侧三横线手柄拖拽。
- 状态栏右侧可直接关闭，并可从设置控制台重新显示。
- Buff 存在时显示 Aura 图标和剩余时间。
- Buff 缺失时物品图标显示为灰色；获得 Buff 后恢复彩色。
- Buff 缺失时仍显示对应物品、数量和冷却，点击即可使用。
- 支持物品、Toy 和 secure macro 三种动作。
- 诱饵条目未激活时自动隐藏。
- 内置设置面板可启用、编辑、排序和新增自定义条目。
- 设置保存在账号级 `FishingBuffTrackerDB`。

## 安装

将整个 `FishingBuffTracker` 目录复制到：

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
- `/fbt status`：在聊天框打印所有条目的 Aura、SpellID 和物品数量。

## 内置条目

| 名称 | ItemID | Aura SpellID |
|---|---:|---:|
| 可重复使用的巨型鱼漂 | 202207 | 397827 |
| 哈籁尼尔感知瓶剂 | 241316 | 1236763 |
| 晶华感知瓶剂 | 191354 | 371454 |
| 血艳蓟茶 | 242299 | 1269152 |
| 尖刺钉螺 | 262651 | 1284999 |
| 乌拉特克蛇头鱼诱饵 | 277821 | 1302820 |
| 剧毒特拉皮鱼 | 274588 | 1303623 |
| 斑点鱂鱼 | 274587 | 1303624 |

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
4. 确认物品被消耗，Aura `1284999` 出现。
5. 执行 `/fbt status` 保存结果。

## 已知边界

- Secure 按钮的动作、显隐和布局变更会在战斗结束后应用。
- Buff 图标负责使用物品，不再承担拖拽；请拖动状态栏左侧的三横线手柄。
- 战斗中关闭或显示状态栏时，操作会排队到战斗结束。
- 血艳蓟茶需要持续饮用至少 10 秒，Buff 不会在首次点击时立即出现。
- 点击一个已经激活的条目仍可能再次使用物品，用于延长可叠加持续时间。
- 当前版本面向 Retail 12.1.0，`.toc` Interface 为 `120100`。
