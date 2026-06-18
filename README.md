# game_0_vsl

一个 **Vampire Survivors-Like**(吸血鬼幸存者类)核心循环原型,Godot 引擎开发。验证「移动 → 自动攻击 → 收经验 → 升级选武器」闭环,武器系统锚定**上古卷轴(TES)式分类体系**。

> 美术为占位/外部素材;本仓库聚焦机制、数值与打击感。

---

## 环境要求

| 项 | 版本 |
|---|---|
| Godot | **4.6.3-stable**(Forward Plus) |
| 视口 | 固定 1280×720,不可缩放 |
| 主场景 | `res://scenes/main/main.tscn` |
| 测试框架 | gdUnit4(随仓库) |

## 快速开始

```bash
git clone https://github.com/finaljoke/game-vsl.git
cd game-vsl
```

然后**先装下方未入库依赖**,再用 Godot 4.6.3 打开项目并重启编辑器。详见 [CLAUDE.md](CLAUDE.md)。

### ⚠️ 必读:未入库的本地依赖

仓库**不含**以下内容,新克隆/换机必须自行补齐,否则项目无法加载或静默降级:

- **LimboAI v1.7.1**(GDExtension 版,`gdextension-4.6`)——敌人 AI 行为树,`addons/limboai/` 已 gitignore。从 Godot AssetLib 搜 “LimboAI” 或 GitHub release 下 zip 解压到项目根。**GDExtension 只在编辑器启动时加载,装好后必须重启编辑器**,否则 `BTPlayer` 类未注册。
- **美术素材**:`assets/sprites/` 大部分、BGM(`assets/audio/music/`)为本地素材(源自外部 Kenney 大库),未入库。缺失时武器/敌人精灵降级。新拷入素材后须跑一次 headless `--import`(见 CLAUDE.md)。
- **Phantom Camera 陷阱**:新增 `PhantomCamera2D` 时必须手设 `position = (640, 360)` 且 `noise_emitter_layer = 1`,否则**静默失效无报错**(画面跑偏 / 震动不触发)。详见 CLAUDE.md。

## 项目结构

```
autoloads/   单例(GameManager / GameFeel / Vfx / WeaponDB / CardPool /
             RunRecorder / RunHarness / DebugMetrics …)
scenes/      arena · player · enemies · weapons · collectibles · ui · main
data/        weapons/(武器 .tres,数据驱动) 等资源
shaders/     视效着色器(火扰动/冰白边/电抖动/召唤描边/变幻扭曲)
tools/       遥测 A/B 工具(analyze_runs.gd · run_ab_matrix.ps1)
tests/       gdUnit4 单测/集成(31 套件)
docs/        设计 spec 与实现计划(superpowers/specs · superpowers/plans)
addons/      gdUnit4 · godot_ai · phantom_camera · sound_manager · limboai*
```
\* `limboai/` 未入库,见上文。

## 武器系统

14 把武器重做为 **TES 式分类**——武器(单手/双手近战、远程弓/投掷)+ 法术(毁灭火电冰、召唤、变幻),每类一个不可重叠的机制签名;进化是**机制质变**而非数值堆叠。武器走 `WeaponData.levels` 反射 + `CardPool` 自动注册,改数值只动 `data/weapons/*.tres`。

代表:斩 / 长弓 / 回旋斧 / 火球 / 连锁闪电 / 烈焰护体 / 缚灵 / 碎(Maul) / 霜噬(Frostbite) / 引力井(Gravity Well) / 亡者召唤(Reanimate),含 10 个进化(旋风 / 震地 / 箭雨 / 核爆 / 炼狱 / 暴雪 / 奇点 …)。

设计与实现记录见 [docs/superpowers/specs/2026-06-17-weapon-arsenal-redesign-design.md](docs/superpowers/specs/2026-06-17-weapon-arsenal-redesign-design.md)。

## 测试

gdUnit4 headless(全量 **397 用例 / 31 套件全绿**)。`--ignoreHeadlessMode` 必加,否则 exit 103:

```powershell
& "<Godot 4.6.3 console exe>" --headless --path "<repo>" `
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode `
  -a res://tests/
```

> 注意:gdUnit4 中某测试的解析/脚本错误会**静默截断**其后测试的发现——别只看「全绿」,要核对预期用例数。

## 遥测与平衡

`RunHarness` bot 驱动 + `RunRecorder` 记录 → `tools/analyze_runs.gd` 分析(击杀每分 kpm,±35% 带宽)。A/B 矩阵编排 `tools/run_ab_matrix.ps1`,**全程 `--fixed-fps 60`** 保证确定性。最终平衡报告见 [docs/superpowers/plans/2026-06-17-weapon-arsenal-w4-balance-report.md](docs/superpowers/plans/2026-06-17-weapon-arsenal-w4-balance-report.md)。

---

更多开发陷阱(LimboAI、Phantom Camera、素材导入)见 [CLAUDE.md](CLAUDE.md)。
