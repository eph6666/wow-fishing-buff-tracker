# 本地验证

这些测试使用 **Lua 5.1**。本地测试不能模拟 WoW 的真实硬件输入、taint、
secret 值、游戏服务器和视觉渲染。修复内容见 [更新记录](../CHANGELOG.md)，
仍需进游戏确认的行为见 [客户端验收清单](../docs/CLIENT_TEST_PLAN.md)。

在仓库根目录运行：

```bash
lua5.1 tests/smoke.lua FishingBuffTracker
lua5.1 tests/audit.lua FishingBuffTracker
```

也可以只运行名称包含某字符串的用例：

```bash
lua5.1 tests/audit.lua FishingBuffTracker combat_
```

`audit.lua` 是回归测试。2026-09-17 修复完成后的验证结果为
**177 通过、0 失败，退出码 0**。修复前基线为 12 通过、12 失败；
随后按 F01–F11 保留缺陷回归并补充边界测试。任何失败都会产生非零退出码，
不会把尚未修复的问题当作预期失败而吞掉。
两个 `database_contract_` 用例使用数据库支持的输入，而非客户端抓取；
Settings 尺寸和停止拖动测试使用已注明来源的 UI/API 契约。

`wow_mock.lua`：

- 按 TOC 加载插件，每个用例独立初始化。
- 记录 secure attributes、图标、倒计时、数量、布局和创建的对象。
- 未知方法保持 `nil`，不会自动返回空函数；纯视觉方法有显式白名单。
- 检查战斗中对 secure frame 和其父级的部分保护变更。
- 模拟焦点、继承可见性、事件、Aura、临时附魔、背包数量、玩具所有权和冷却。
- 为本插件使用的锚点、父子尺寸和滚动范围求解几何关系，覆盖不同 Settings
  内容区域尺寸。字体测量采用估值；不模拟客户端缩放后的像素渲染。
- 用严格替身验证受限字段的访问顺序；这不是 Lua secret 的真实执行环境。
- 不实现通用 XML 模板继承、完整 protected 状态传播或 taint。

要执行目标版本 Blizzard 的真实 Lua 分派代码，先下载独立源码副本。
下面命令只用于准备本地测试依赖；第三方 UI 文件无需放进插件目录：

```bash
mkdir -p /tmp/fbt-blizzard-test
curl -fL \
  https://codeload.github.com/Gethe/wow-ui-source/tar.gz/4e3cbb8c5609e4bfc332c0aebbfa4d79731fab59 \
  -o /tmp/fbt-blizzard-test/source.tar.gz
tar -xzf /tmp/fbt-blizzard-test/source.tar.gz -C /tmp/fbt-blizzard-test
lua5.1 tests/blizzard_contract.lua FishingBuffTracker \
  /tmp/fbt-blizzard-test/wow-ui-source-4e3cbb8c5609e4bfc332c0aebbfa4d79731fab59
```

该测试覆盖 24 组动作/CVar 组合、复用按钮的动作切换及释放、旧点击缺陷
对照组、Aura 分页及失效槽位、过滤和提前终止，以及物品和临时附魔 API
签名。它还执行原生 Settings `DisplayLayout` 和滚动模板回调，检查多种
实际内容区域尺寸、窗口变化、最后一行可达性及列表缩短后的滚动钳制。
拖动契约核对 `StartMoving` 和 `StopMovingOrSizing` 的保护标记；不执行
这两个原生方法本体。
固定版本、来源文件和使用范围记录在 `fixtures/source_manifest.json`。
它把最终 `UseToy` / `SecureCmdUseItem` / `RunMacroText` 接到记录器，
所以通过只表示 Lua 分派正确，不表示物品在客户端已成功使用。

Lua 语法检查：

```bash
luac5.1 -p FishingBuffTracker/*.lua tests/*.lua tests/fixtures/review_data.lua
git diff --check
```

若解释器的可执行文件名是 `lua` / `luac`，确认版本为 5.1 后替换命令名。
`audit.lua` 和 `blizzard_contract.lua` 使用 Lua 5.1 的 `setfenv`，
不声称兼容 Lua 5.2+。

标签发布工作流会执行以上三套测试和语法检查，再调用
`scripts/package.py` 生成安装包。Blizzard 源码只作为测试依赖下载到临时目录，
不会进入插件安装包。
