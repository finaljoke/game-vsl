# autoloads/run_harness.gd
# Bot 驱动 + 遥测编排器。无 --bot 命令行参数时完全惰性(active=false),真人游玩零影响。
# 职责:读命令行配置、每物理帧驱动 bot 移动、监听升级自动选卡、设种子/快进、检测终局收尾退出。
#
# 本文件含两个纯静态函数(compute_kite_dir / choose_card),不依赖场景,便于单测。
extends Node

# ── 可调参数(集中) ────────────────────────────────────────────────────────
const PERCEPTION_RADIUS: float = 220.0   # kite 感知半径(px):此半径内敌人产生斥力
const CENTER_PULL_GAIN: float = 0.004    # kite 避墙:离中心越远拉回越强
const DEFAULT_FAST: float = 3.0          # --fast 缺省(同种子 diff 验确定性后可升降)
const DEFAULT_INTERVAL: float = 1.0      # tick CSV 采样周期(游戏秒)
const NEAR_RADIUS: float = 140.0         # 传给 player.bot 的近敌半径(预留,DebugMetrics 另有同名)

# 选卡优先级表(命名 profile)。matcher: 精确卡 id,或 "type:<type>" 匹配卡型。
# default = 生存优先(先保命再进攻),给 bot 一套稳定可活满全程的 build。以后外置到 data/bot_profiles/。
const DEFAULT_PROFILE: Array = [
	"perk_hp", "synergy_lifesteal", "perk_heal",
	"type:evolution", "type:synergy", "type:upgrade",
	"type:weapon", "type:perk",
]
const PROFILES: Dictionary = {"default": DEFAULT_PROFILE}

# ── 运行时状态(Task 7 填充驱动逻辑;此处先声明,供其他文件引用) ────────────────
var active: bool = false                 # 是否 bot 模式(无 --bot 时恒 false → 全链路惰性)
var base_time_scale: float = 1.0         # 快进基线;game_feel hitstop 恢复到这里而非写死 1.0

# ── 纯静态决策函数(无场景依赖,单测覆盖) ──────────────────────────────────────

# kite 移动方向:Σ(远离半径内敌人,越近越强) + (拉回竞技场中心,避墙)。归一化;无净向量返回 ZERO。
static func compute_kite_dir(player_pos: Vector2, enemy_positions: Array, arena_center: Vector2, perception_radius: float) -> Vector2:
	var repulse := Vector2.ZERO
	for ep in enemy_positions:
		var to_player: Vector2 = player_pos - ep
		var d := to_player.length()
		if d > perception_radius or d <= 0.001:
			continue
		# 越近权重越大(d→0 时趋近 1,d→radius 时趋近 0)
		repulse += to_player.normalized() * (1.0 - d / perception_radius)
	var center_pull := (arena_center - player_pos) * CENTER_PULL_GAIN
	var dir := repulse + center_pull
	if dir.length() < 0.001:
		return Vector2.ZERO
	return dir.normalized()

# 从 offered 里按 profile 顺序取最高优先命中;无命中取第 0 张兜底(保证一定有解,防暂停卡死)。
static func choose_card(offered: Array, profile: Array) -> Dictionary:
	for matcher in profile:
		for card in offered:
			if _card_matches(card, String(matcher)):
				return card
	return offered[0] if not offered.is_empty() else {}

static func _card_matches(card: Dictionary, matcher: String) -> bool:
	if matcher.begins_with("type:"):
		return String(card.get("type", "")) == matcher.substr(5)
	return String(card.get("id", "")) == matcher
