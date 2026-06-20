# game_0_vsl — 开发注意事项

> 引擎：**Godot 4.7**（2026-06-20 自 4.6.3 升级；`project.godot` `config/features` 已切）。升级后全量回归通过：headless import 零 GDExtension 报错、gdUnit **456/456**、bot 同种子两跑逐字节一致(C5)。

## LimboAI 依赖（敌人 AI，未入库）

敌人行为由 **LimboAI**（行为树 GDExtension）驱动。`addons/limboai/` 已 gitignore，**新克隆/换机必须先装**否则项目无法加载（`enemy.tscn` 含 `BTPlayer` 节点、AI 脚本 `extends BTAction`）：

- 版本：**v1.7.1**，GDExtension 版（zip `limboai+v1.7.1.gdextension-4.6.zip`，二进制按 Godot 4.6 编译）。**已实测在 Godot 4.7 下正常加载**（`.gdextension` 声明 `compatibility_minimum=4.2`，向前兼容）；当前 4.6 版即可用，官方若出 4.7 目标版可再换。
- 装法：Godot 内 AssetLib 搜 “LimboAI” 下载，或从 GitHub release 下 zip 解压到项目根（zip 内已含 `addons/limboai/`）。
- **GDExtension 只在编辑器启动时加载**：装好后必须重启编辑器，否则 `BTPlayer` 类未注册、图标导入报错。
- 行为树是**代码构建**（[scenes/enemies/ai/enemy_bt.gd](scenes/enemies/ai/enemy_bt.gd) 的 `EnemyBT.build()`），不走 `.tres` 可视化编辑；新增行为在此扩 root_task。
- ⚠ **Windows 双实例冲突**：编辑器开着本项目时再跑 headless（测试/bot），第二个实例复制 `~liblimboai…dll` 临时名会撞 → 报 `Failed to open ~lib… / Error copying library / Can't open GDExtension`，LimboAI 在该 headless 实例加载失败（**非 ABI 问题**）。**跑 headless 前先关编辑器。**

## Phantom Camera v0.11 必读陷阱

每次向场景添加 PhantomCamera2D 时，必须立即做这两件事，否则**静默失效无报错**：

### 1. 设置 position

PhantomCameraHost 会把 Camera2D 的视图中心强制对齐到 **PhantomCamera2D 的世界坐标**，不继承 Camera2D 自身的 position。默认 (0,0) 会让画面中心跑到世界原点。

```
# 本项目固定竞技场 1280×720，中心在：
PhantomCamera2D.position = Vector2(640, 360)
```

### 2. 设置 noise_emitter_layer = 1

| 节点 | 属性 | 默认值 |
|---|---|---|
| PhantomCameraNoiseEmitter2D | noise_emitter_layer | **1** |
| PhantomCamera2D | noise_emitter_layer | **0** ← 问题在这里 |

匹配条件：`pcam_layer & emitter_layer != 0`，默认 `0 & 1 = 0` → 震动永远不触发。

```
PhantomCamera2D.noise_emitter_layer = 1
```

**排查清单**：震动没效果且无报错 → 先查这两项。
