extends Node
## Vfx — 全局视效工厂 + 预设注册表。
## 一处定义 FX 配方,武器/敌人/状态系统只调用,不各写一套粒子代码。
## 分工:GameFeel 管屏幕级反馈(震屏/闪屏/顿帧/音效/伤害数字);
##       Vfx 管世界空间的粒子/序列帧/状态指示器实例化。

const PACK := "res://assets/sprites/kenney/particles/pack/"
const EXPL := "res://assets/sprites/kenney/explosions/"

# 一次性粒子爆发预设(CPUParticles2D 配方)。additive=true 走加色发光材质。
const BURST_PRESETS := {
	&"fire_burst":  {"color": Color(1.0, 0.6, 0.1),   "amount": 10, "lifetime": 0.40, "vmin": 50.0, "vmax": 150.0, "smin": 3.0, "smax": 6.0, "additive": false},
	&"frost_burst": {"color": Color(0.55, 0.85, 1.0), "amount": 10, "lifetime": 0.40, "vmin": 40.0, "vmax": 120.0, "smin": 3.0, "smax": 5.0, "additive": false},
	&"hit_spark":   {"color": Color(1.0, 1.0, 0.85),  "amount": 6,  "lifetime": 0.25, "vmin": 60.0, "vmax": 180.0, "smin": 2.0, "smax": 4.0, "additive": true},
	&"magic_burst": {"color": Color(0.7, 0.5, 1.0),   "amount": 12, "lifetime": 0.45, "vmin": 30.0, "vmax": 110.0, "smin": 3.0, "smax": 6.0, "additive": true},
}

# 序列帧预设:目录 + 帧名前缀 + 帧数(00..count-1) + 帧率。
const ANIM_PRESETS := {
	&"explosion_regular": {"dir": "res://assets/sprites/kenney/explosions/", "base": "regularExplosion", "count": 9, "fps": 24.0},
	&"explosion_sonic":   {"dir": "res://assets/sprites/kenney/explosions/", "base": "sonicExplosion",   "count": 9, "fps": 24.0},
	&"explosion_ground":  {"dir": "res://assets/sprites/kenney/explosions/", "base": "groundExplosion",  "count": 9, "fps": 24.0},
}

func get_preset(name: StringName) -> Dictionary:
	if BURST_PRESETS.has(name):
		return BURST_PRESETS[name]
	if ANIM_PRESETS.has(name):
		return ANIM_PRESETS[name]
	return {}
