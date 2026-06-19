# 武器/法术军械库 —— 全面严格诊断（2026-06-19）

> 范围：11 基础 + 11 进化 = 22 条目。三层交叉核对：设计 spec（`2026-06-17-weapon-arsenal-redesign-design.md`）×
> 出货数值（`data/weapons/*.tres`）× 实现代码（`scenes/weapons/**`、`scenes/enemies/**`）× W4 遥测报告。
> 维度：建模/视觉、游玩体验、特性设置、升级演变、相互搭配、数值平衡、趣味性、独特性。
>
> 结论先行：**当前军械库的“身份/机制签名”在 spec 层是干净的，但落到代码有 2 个会让整套机制部分空转的硬伤，
> 外加 ~8 个削弱“趣味性/搭配/独特性”的系统级设计缺口。进化全部未经遥测，且多处“进化=数值倒退”。**

---

## A. 系统级问题（高杠杆，应先于逐武器修）

### A1. 【确定性 BUG】控制系统对“冲锋者(charger)”整类失效 — 最严重

`scenes/enemies/ai/atoms/bt_charger.gd` 的四个状态全部**直接写 `agent.velocity`**，绕过了 `agent.resolve_velocity()`：

- APPROACH：`agent.velocity = _dir_to_player(target) * agent.SPEED`
- TELEGRAPH/RECOVER：`agent.velocity = Vector2.ZERO`
- DASH：`agent.velocity = _dash_dir * agent.SPEED * dash_speed_mult`

而 chase/kite/bomber/move_to_target 四个 atom 都走 `resolve_velocity()`（= `desired*move_speed_mult + external_velocity`，硬直时只剩 external）。

**后果**：冲锋者**完全免疫**减速、冻结、硬直、击退、引力拉拽。这等于：
- 碎(maul) 的击退+硬直、霜噬/暴雪 的减速→冻结、引力井/奇点 的拉拽、连锁闪电/雷暴 的感电硬直 —— 对 charger **全部 no-op**。
- charger 只吃直击伤害与 burn DoT。

这把“控制流”的价值在一整个敌人原型上凭空蒸发，且无报错、极难察觉（W4 solo 测试不会暴露，因为 solo 漏斗多为 chase）。
**修**：`bt_charger.gd` 所有 `agent.velocity = X` 改为 `agent.velocity = agent.resolve_velocity(X)`；DASH 是否该免疫硬直可设计决定（建议突进中仍受击退、但 telegraph 前可被硬直打断 → 给控制一个高光“打断冲锋”的瞬间）。

### A2. 【设计死轴】暴击系统根本无法构筑 — 长弓身份半残

`player.gd` 有 `crit_chance=0.0 / crit_mult=2.0`，但**整个卡池（`card_pool.gd`）没有任何一张卡提升 `crit_chance` 或 `crit_mult`**（perk 只有 speed/hp/attack/xp/damage/heal；synergy 只有 pierce/multishot/magnet/lifesteal）。

后果：
- spec 把长弓定位成“**构筑暴击流核心**”，但玩家无从堆暴击。`crit_chance` 永远是 0。
- 长弓实际暴击只来自 `crit_bonus`（0.25–0.35）在“满血或超距”时的概率触发。
- `guaranteed_crit`（金字 + medium 震屏）需 `crit_chance+crit_bonus≥1.0`，基础长弓永远摸不到，只有 thousand_edge(`crit_bonus=1.0`) 能触发 → 暴击的爽感反馈几乎只属于进化形态。

**叠加问题**：`knife_weapon.gd` 用 `get_nearest_enemy()` 锁**最近**敌，而距离暴击要求 `dist > crit_range(260)`。自动锁最近 ⇒ 目标几乎总在 260 内 ⇒ **“距离暴击”几乎永不触发**，只剩“满血暴击”一条路。长弓的两条暴击触发器废了一条、整条暴击轴无法成长。

**修向**：要么给暴击轴补卡（`perk_crit`/`synergy_crit` → 让暴击成为真构筑轴），要么砍掉距离暴击、把长弓重定义为“穿透线 + 满血处决”，别留半挂的机制。

### A3. 【趣味性核心缺失】状态之间、状态与伤害之间零交互（元素系统是平的）

burn/slow/freeze/stun 各自孤立结算，**互不增益、也不放大伤害**：
- 冻结的敌人被打**不碎、无加伤**；硬直/感电的敌人**不吃处决加成**；燃烧的敌人**不会被引爆/蔓延**；
- 连锁闪电不偏好已湿/已冻目标；火球落在引力井聚拢的怪堆上**没有任何额外收益**。

这直接掏空了用户最在意的“**相互搭配 + 趣味性**”。当前所有“combo”（霜噬冻 → 碎/火球收割；引力井聚 → AoE）都只是**走位涌现**，没有任何机制奖励，玩家感受不到“我搭出了连携”。

**这是把这套军械库从“合格”推到“有记忆点”的最大杠杆**。建议引入少量**状态协同规则**（见 §C2）：如“对冻结目标命中 → 碎裂额外伤害”“引力井内伤害 +X%”“burn 目标死亡溅射小火”。

### A4. 【升级演变】进化全部未经遥测，且多处“进化=数值倒退”

W4 只平衡了 **11 把基础**（solo bot 档），**11 个进化形态从未跑过遥测**，数值是设计手填。抽查即见硬问题：

| 进化 | 倒退点（对比所进化的满级基础） | 净评 |
|---|---|---|
| **巨型护盾球 mega_orb** | 每球 `damage 8` < 缚灵 Lv3 的 `14`；且 `.tres` **未注入 hit_cooldown** → 回退到默认 `0.5` > 缚灵 Lv3 的 `0.30` | 单球更弱更慢，仅靠球数 4→8 + dash 勉强翻正。**“终极形态”逐球比满级更差** |
| **炼狱 inferno_aura** | `damage 14→12` | 靠 radius/burn/lifesteal/cooldown 净翻正，可接受 |
| **血鞭 bloody_whip** | `cooldown 0.5→0.6`(更慢)、`damage 34→30` | 靠 full_circle+range 200+bleed+lifesteal 净翻正，但“数值下降”观感差 |
| **千刃 thousand_edge** | `cooldown 0.15` + `volley 5` + `pierce 8` + 满血必暴 | **大概率离谱 OP**，从未测过 |
| **核爆 nuke** | `cooldown 0.5` + blast 128 + scale 1.6 + secondary | 0.5s 一发准全屏清，疑似 OP，从未测过 |

“进化即质变”的 spec 原则在数据层被违反成“质变=有些数字还更小”。`mega_orb` 尤其是 bug 级：玩家把缚灵练满再进化，**实测会感觉变弱**。
**修**：进化档必须跑一轮 solo 遥测（W4 管线现成，加 `solo_<evo_id>` 档即可）；先把 mega_orb 的 damage/hit_cooldown 补到不低于基础满级。

### A5. 【独特性空转】引力井/奇点的“拉拽聚怪”机制性过弱

`gravity_well.gd:482`：`apply_impulse(dir, pull_strength*delta)`，而 `enemy.gd` 每帧 `external_velocity *= 0.85` 衰减。
稳态外力速度 ≈ `pull_strength*delta / (1-0.85)`：
- 基础 pull 120 → 约 **13 px/s**；奇点 pull 240 → 约 **27 px/s**。
- 但敌人自身 chase 速度是 **80 px/s** 朝玩家（`resolve_velocity = desired + external`）。

⇒ 拉力只是 chase 速度上的一个小扰动，**根本拽不动正在追玩家的怪**。引力井的招牌“把散怪揉成团”在面对主流 chase 怪时基本不成立（它现在的 91.6 kpm 主要来自 densest_center 大范围 tick 伤害，**不是来自聚怪**）。招牌机制空转 = 独特性丢失。
**修**：拉力应能短时压过 locomotion（提 pull 或降 decay 或对场内怪施 `slow` 再拉），让“聚怪”真的发生；否则它只是个“低伤大范围 DoT 圈”，与火球/霜噬的“砸密堆”同质。

### A6. 【独特性】召唤随从不拉仇恨、不可被杀 →“AI 盟友”幻想落空

`roaming_minion.gd:84` `collision_layer=0, collision_mask=0`，且敌人 AI 只索敌 `player` 组、从不索敌 `summons`。
后果：
- 随从**无敌**（敌人打不到它）、**穿模**（不挡路）、`max_hp` 是注释自承的“预留”死字段。
- spec 说亡者召唤“**分担仇恨/铺场**”，但随从既不挡刀也不分仇恨，只是“限时漫游的伤害源”。
- 群尸的“死亡分裂”只在 `lifetime` 自然到点时 roll（因为根本不会被打死），与“尸潮在战斗中自我延续”的设想脱节。

“真正的 AI 盟友”是 spec 标的冲刺卖点，落地后退化成“会走路的飞刀”。**修向**：要么让随从可被攻击+拉仇恨（兑现盟友幻想，工作量大），要么诚实地把它重定义为“漫游炮台”并削掉 max_hp 死字段，别留半套召唤幻想。

### A7. 【升级演变】基础武器升级曲线浅、且多把“伤害恒定只堆冷却/穿透”

每把基础只有 3 级、2 张升级卡，且不少把**伤害跨级不变**，只动 cooldown/pierce/chains：
- 长弓：`damage 18/18/18`（恒定），只 cooldown↓ + pierce↑
- 回旋斧：`damage 20/20/20`（恒定），只 cooldown↓ + pierce↑ + range↑
- 连锁闪电：`damage 22/22/22`（恒定），只 cooldown↓ + chains↑

升级体验=“变快/变多”，缺“变强/变质”的节点感；且**全线性、无任何分支选择**（每把唯一升级路径）。用户点名要看“升级演变”，当前是这套军械库最薄的一环。
**修向**：给关键级数注入“小质变”（如长弓 Lv3 解锁“穿透不衰减”、闪电 Lv3“链可回跳”），或引入**每武器可选 modifier 卡**（二选一）制造构筑分叉。

### A8. 【视觉/建模】卡面图标大面积错配 + 进化只是 base 的“重新染色”

**图标错配**（`*.tres` 的 `icon`，玩家选卡时看到的就是它）：

| 武器 | 当前图标 | 问题 |
|---|---|---|
| 斩 whip / 碎 maul / 震地 / 群尸 / 亡者召唤 / 千刃 | `items/dagger.png` | 6 把共用一张匕首图，毫无辨识 |
| 回旋斧 / 霜噬 / 暴雪 | `items/gem.png` | 斧/冰用宝石图 |
| **连锁闪电** | `particles/fireball.png` | **电用火球图**（直接误导元素） |
| 引力井 / 奇点 / 烈焰护体 | `particles/orb_ring.png` | 三者同图 |

**进化视觉=基础重染色**：所有进化复用基础 `.tscn`，差异仅靠 tint/scale —— 核爆=放大 1.6×橙色的火球、旋风镖=染蓝的回旋斧、奇点=与引力井同款、雷暴=染紫的闪电。进化缺“史诗终极形态”的视觉跃迁。

附 **whip 血鞭的染色 bug**：`whip_weapon.gd:1326` 斩击弧只在 `double_sided` 时染红，但血鞭走的是 `full_circle`（没设 double_sided）→ **血鞭的挥砍弧仍是金色**，只有命中 blood_burst 是红的。且 `double_sided` 现在无任何 `.tres` 设置 → 死代码路径。另：血鞭 full_circle 是 360° 命中，但只画了 `_facing` 单向一道弧 → **打击范围与视觉不符**。

### A9. 【相互搭配】协同卡太薄，且一半只服务弓/斧

仅 4 张 synergy：`pierce`(穿透,仅 knife/boomerang/其进化生效)、`multishot`(仅 knife/thousand_edge)、`magnet`(XP)、`lifesteal`(击杀回血)。
- 投射类两张协同**只覆盖弓+斧**，其余 9 把武器没有任何专属协同卡。
- 没有“元素/流派”协同（如“火系全体 burn +X”“控制流：对受控目标加伤”），跨武器构筑身份非常薄。

### A10. 【构筑平衡】进化 perk 门槛分布失衡，强 perk 同时锁最多进化

`requires_perk_stacks` 全为 3，但门槛分布：
- **perk_attack**(攻速,通用强) 锁 4 把：斩/长弓/闪电/霜噬
- **perk_hp**(坦) 锁 4 把：烈焰护体/缚灵/亡者/碎
- **perk_speed** 锁 2 把：回旋斧/引力井
- **perk_damage**(+全伤,通用最强) 锁 **1 把**：火球

后果：① perk_attack 是单计数器 —— 堆满 3 层会**同时**点亮 whip/knife/lightning/frostbite 全部进化就绪（若已满级），“路线选择”被摊平。② perk_damage 又强又只解锁 1 把（且解锁的是已 OP 的火球→更 OP 的核爆），其余想进化的玩家被迫走 perk_attack（恰好也很强）。**强 perk 同时给最多进化 = 没有真正取舍。**

### A11. 【数值平衡 · 已知取舍】火球顽固 OP、缚灵顽固 weak（W4 记录在案）

W4 最终 8/11 落带宽；火球(112.6)/霜噬(103.2) 仍 OP（巡航档，kpm 被刷怪率封顶）、缚灵(31.7) 仍 weak（被动接触频率受限）。这些是 kpm 单指标对“巡航/被动/召唤”档的盲区，W4 已诚实记为取舍。但从**游玩体验**看：火球 + 核爆这条线实质是“无脑全屏清场之王”，挤压其他武器的存在感 —— 值得用“覆盖率 + 存活率”复合判据再压一轮，而非接受。

---

## B. 逐武器诊断

标记：✅良好 ⚠️有缺口 ❌硬伤。verdict 聚焦“最该改的一点”。

### 武器族（Martial）

**1. 斩 Cleave（whip）⚠️**
- 身份/机制清晰（跟随朝向高频弧劈），W4 已从 weak 调到 ok(50.1)。手感是全军械库最“跟手”的一把。
- 缺口：升级仅 cooldown/arc/range 微调，无质变节点；进化血鞭见 A8（金色弧 bug + 范围视觉不符 + cooldown/damage 倒退）。
- verdict：基础健康；修血鞭的视觉与数值倒退。

**2. 碎 Maul（maul）⚠️**
- 身份强（慢重砸 + 击退硬直 + heavy 震屏 + hitstop），打击感配方是范例。
- 缺口：① 对 charger 击退/硬直 no-op（A1）；② 进化震地的“延迟扩张冲击波”只在 `radius<d≤shockwave_radius` 的环带命中 —— 与初砸**不重叠**，中心已被砸的怪不二次吃，环带设计 OK 但需确认 stun/slow 也走 resolve_velocity 才有效（A1）。
- verdict：把控制接上 charger 后，这把是“控场近战”的标杆。

**3. 长弓 Longbow（knife）❌**
- ❌ 暴击轴无法构筑（A2）+ 距离暴击因锁最近敌几乎永不触发。spec 的“暴击流核心”身份落空。
- 升级伤害恒定 18（A7）。进化千刃疑似 OP（A4）。
- verdict：要么补暴击构筑卡兑现身份，要么重定义；这是身份与实现裂得最大的一把。

**4. 回旋斧 Throwing Axe（boomerang）✅/⚠️**
- 去/回双段 + 各自 pierce 的机制独特且实现干净（`boomerang_projectile.gd` 的 `_phase_hits`/`_hit_ids` 折返刷新正确），axe.png 精灵也到位。W4 ok(70.4)。
- 缺口：伤害恒定 20（A7）；进化旋风镖 `orbit_return` 折返改环绕，机制质变成立 ✅，但视觉仅染蓝。
- verdict：最健康的一把之一，仅缺升级深度。

### 法术族 · 毁灭（Destruction）

**5. 火球 Fireball（explosion）⚠️**
- 机制扎实（densest_center 选点 + 地火 burn field，DoT 走独立通道不污染命中反馈 ✅）。
- ❌ 平衡：顽固 OP（A11）；进化核爆 cooldown 0.5 疑似爆表（A4）。
- 同质化：与霜噬/引力井/连锁都“自动砸最密堆”，targeting 高度重合（见 §C1）。
- verdict：削覆盖/复合判据再平衡；核爆必须测。

**6. 烈焰护体 Flame Cloak（aura）✅**
- 自体持续 burn 光环，与火球正交，无震屏避免抖动疲劳（好决策）。W4 ok(64.7)。
- 缺口：进化炼狱 damage 14→12 小倒退（A4，但净翻正）。
- verdict：健康。

**7. 连锁闪电 Chain Lightning（lightning）⚠️**
- 贪心连锁选择(`chain_targets` 纯函数)干净，链上即时伤害 + 链尾感电硬直。W4 ok(68.3)。
- 缺口：① 感电硬直对 charger no-op（A1）；② 伤害恒定 22（A7）；③ 卡面图标是火球（A8）；④ 进化雷暴 sky_strike 用 `randi`，W4 确认 `--fixed-fps 60` 下确定 ✅。
- verdict：把硬直接上 charger + 换图标即良好。

**8. 霜噬 Frostbite（frostbite）❌/⚠️**
- “减速→二次命中冻结”的机制循环是全军械库最聪明的设计之一，冻结链在密堆里能成立。
- ❌ 但减速/冻结对 charger no-op（A1）—— 控制型武器的控制对一整类敌人失效，伤害最大；
- ⚠️ 平衡仍略 OP（103.2）；冻结目标无“碎裂/加伤”payoff（A3）—— 控住了却不奖励收割。
- verdict：A1 修复优先级最高的受益者；再加“冻结协同”就有了灵魂。

### 法术族 · 召唤（Conjuration）

**9. 缚灵 Spectral Wisps（orb）⚠️**
- 环绕守卫被动覆盖，机制清晰。
- ⚠️ 顽固 weak(31.7)，瓶颈是接触频率非伤害（W4 实证 +50%伤害几乎无效）；进化 mega_orb 是**逐球倒退**的 bug 级问题（A4）。
- verdict：接受“低 kpm 高效用”定位，但必须修 mega_orb 倒退；可考虑给“球数”一条协同卡。

**10. 亡者召唤 Reanimate（reanimate）⚠️**
- ⚠️ 随从无敌/不拉仇恨/穿模，“AI 盟友”幻想落空（A6）；W4 调 lifetime 后 ok(77.9)。
- verdict：决定它是“盟友”还是“漫游炮台”，然后把实现对齐到那个定位。

### 法术族 · 变幻（Alteration）

**11. 引力井 Gravity Well（gravity_well）❌**
- ❌ 招牌“拉拽聚怪”机制性过弱，拽不动 chase 怪（A5）；对 charger 更是 no-op（A1）。其 91.6 kpm 来自 AoE tick 而非聚怪 → 实际玩起来与“大范围低伤 DoT 圈”无异，**变幻系的独特性没立起来**。
- 进化奇点的坍缩引爆(`_collapse`)机制成立 ✅，但若怪没被聚拢，坍缩也只是普通 AoE。
- verdict：让拉力真正生效是这把（及整个“变幻系”）存在意义的前提。

---

## C. 推荐的设计模式与实现方案（导向“最佳模式”）

### C1. 先消除“targeting 同质化”
explosion / frostbite / gravity_well / lightning 都“自动砸最密堆”。建议给每类不同的**投放语义**以强化身份：火球=砸密堆（保留）、霜噬=砸**最近聚团**（贴脸控）、引力井=砸**离玩家最远的密堆**（拉回来）、闪电=从最近敌起跳（保留）。让“我往哪打”成为身份的一部分。

### C2. 引入轻量“状态协同规则”兑现搭配/趣味性（最高杠杆）
集中在 `enemy.take_damage` / 状态结算一处加规则，武器零改动即可全员受益：
- **碎裂**：对 `freeze` 中目标的直击 ×1.5 并立即解冻（霜噬→任意收割，给冰系灵魂）。
- **引力增幅**：引力井 `radius` 内敌人受到的所有伤害 +25%（让“聚怪”成为乘区，兑现 spec 的“力量倍增器”）。
- **燃尽**：`burn` 目标死亡时溅射一次小 AoE burn（火系铺场）。
- **处决**：对 `stun`/感电目标伤害 +X%（让闪电/碎的硬直有后续价值）。
这 4 条就能把“相互搭配”从“走位涌现”变成“构筑目标”，且都是纯数值规则、可单测、可遥测。

### C3. 升级演变：每武器 1 个“质变级” + 可选 modifier 二选一
把“伤害恒定只堆冷却”的线性 3 级，改为“Lv2 数值、Lv3 小质变”，并在满级后提供**二选一 modifier 卡**（如长弓：穿透不衰减 / 满血处决强化）制造分叉。复用现有 `WeaponData.levels` 反射 + CardPool 条件 DSL 即可，核心代码不动。

### C4. 暴击轴二选一收口（A2）
要么补 `perk_crit`/`synergy_crit` 让暴击成真构筑轴并修距离暴击的锁敌矛盾，要么删距离暴击、把长弓做成纯穿透+满血处决。别留半挂机制。

### C5. 进化纳入遥测 + 修倒退（A4）
W4 管线加 `solo_<evo_id>` 档跑一轮；先手修 mega_orb（damage/hit_cooldown 不低于基础满级）、复核 nuke/thousand_edge 是否需要降。进化的验收标准应是“每个轴都 ≥ 基础满级，且至少一条机制质变”。

### C6. 控制对 charger 生效（A1）+ 召唤定位收口（A6）+ 引力拉力做实（A5）
三个“机制空转”修完，碎/霜噬/闪电/引力井/亡者召唤的招牌特性才真正存在。

### 优先级建议
1. **A1（charger 免疫）** — 一行级修复，解锁 5 把武器的控制价值。
2. **A4 mega_orb 倒退 + A2 暴击死轴** — 直接的“变强反而变弱/身份落空”体验。
3. **C2 状态协同 4 条规则** — 把军械库从“合格”推到“有记忆点”的最大单点杠杆。
4. **A5 引力拉力 / A6 召唤定位 / A8 图标** — 兑现独特性与视觉辨识。
5. **A7/C3 升级深度、A9 协同卡、A10 perk 门槛、A11 火球再平衡** — 构筑层打磨。
