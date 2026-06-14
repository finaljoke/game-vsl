# game_0_vsl — 开发注意事项

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
