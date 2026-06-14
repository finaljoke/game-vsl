# autoloads/weapon_db.gd
# 武器数据注册中心。启动时扫描 data/weapons/*.tres，
# 后续加新武器只需 ctrl+N 新建 WeaponData.tres 放进目录即可。
extends Node

const DATA_DIR := "res://data/weapons/"

var _by_id: Dictionary = {}  # String -> WeaponData

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("WeaponDB: cannot open %s" % DATA_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res = load(DATA_DIR + fname)
			if res is WeaponData:
				_by_id[res.id] = res
		fname = dir.get_next()
	dir.list_dir_end()

func get_data(id: String) -> WeaponData:
	return _by_id.get(id, null)

func has_data(id: String) -> bool:
	return _by_id.has(id)

func all_data() -> Array:
	return _by_id.values()

# 所有声明了 evolution.evolved_id 的武器（用于 CardPool 注册进化卡）
func all_evolvable() -> Array:
	var out: Array = []
	for w in _by_id.values():
		if w.evolution.has("evolved_id") and String(w.evolution["evolved_id"]) != "":
			out.append(w)
	return out
