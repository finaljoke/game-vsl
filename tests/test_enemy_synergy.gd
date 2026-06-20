extends GdUnitTestSuite
# Enemy.synergy_multiplier 纯静态乘区单测(无场景)。
# 状态键互斥(冻结只走碎裂、硬直只走处决)、引力增幅吃双通道、其余通道隔离。

func test_no_status_is_identity() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_frozen_direct_shatters() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.0)).is_equal_approx(1.5, 0.0001)

func test_frozen_dot_does_not_shatter() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, true, false, 1.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_stun_direct_full_hp_execute_base() -> void:
	# 满血 hp_frac=1.0 → 1 + 0.2 + 0.8*0 = 1.2
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 1.0, 0.0)).is_equal_approx(1.2, 0.0001)

func test_stun_direct_near_death_execute_max() -> void:
	# 濒死 hp_frac=0.0 → 1 + 0.2 + 0.8*1 = 2.0
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 0.0, 0.0)).is_equal_approx(2.0, 0.0001)

func test_stun_dot_does_not_execute() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, false, true, 0.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_amp_applies_to_direct() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.25)).is_equal_approx(1.25, 0.0001)

func test_amp_applies_to_dot() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, false, false, 1.0, 0.25)).is_equal_approx(1.25, 0.0001)

func test_frozen_plus_amp_direct_stacks_multiplicatively() -> void:
	# 1.5 * 1.25 = 1.875
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.25)).is_equal_approx(1.875, 0.0001)

func test_near_death_stun_plus_amp_direct_stacks() -> void:
	# 2.0 * 1.25 = 2.5
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 0.0, 0.25)).is_equal_approx(2.5, 0.0001)

func test_frozen_only_excludes_execute() -> void:
	# 仅冻结(非硬直)即便残血,只 ×1.5,不含处决项
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 0.0, 0.0)).is_equal_approx(1.5, 0.0001)

func test_stun_only_excludes_shatter() -> void:
	# 仅硬直(非冻结)满血,只 ×1.2,不含碎裂项
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 1.0, 0.0)).is_equal_approx(1.2, 0.0001)

func test_frozen_and_stun_stack_multiplicatively() -> void:
	# 冻结+硬直同时(满血)：碎裂 ×1.5 与处决 ×1.2 经两个独立 if 乘算 → 1.8。
	# 锁定乘算契约：防未来把两个 if 改成 if/elif 静默改变行为。
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, true, 1.0, 0.0)).is_equal_approx(1.8, 0.0001)

# ── P1 单元2：slow 易伤(加法并桶) ──────────────────────────────────────────
func test_slow_vuln_increases_direct() -> void:
	# slow_vuln 0.30、无其他 → ×1.30
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.0, 0.30)).is_equal_approx(1.30, 0.0001)

func test_slow_vuln_applies_to_dot() -> void:
	# 易伤桶在通道门控之外 → DOT 也吃(同 amp)
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, false, false, 1.0, 0.0, 0.30)).is_equal_approx(1.30, 0.0001)

func test_amp_and_slow_vuln_add_in_same_bucket() -> void:
	# 加法并桶：1 + 0.25 + 0.30 = 1.55(非 1.25×1.30=1.625)
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.25, 0.30)).is_equal_approx(1.55, 0.0001)

func test_slow_vuln_multiplies_across_shatter_bucket() -> void:
	# 碎裂 ×1.5 与易伤桶(1+0.30) 跨桶相乘 → 1.5 × 1.3 = 1.95
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.0, 0.30)).is_equal_approx(1.95, 0.0001)

func test_synergy_default_slow_vuln_is_zero() -> void:
	# 不传 slow_vuln → 退化旧式(向后兼容已锁契约)
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.25)).is_equal_approx(1.875, 0.0001)

func test_effective_slow_vuln_zero_when_not_slowed() -> void:
	assert_float(Enemy.effective_slow_vuln(false, 0.5)).is_equal_approx(0.0, 0.0001)

func test_effective_slow_vuln_baseline_when_slowed() -> void:
	# 无卡也有基线 +30%(C2:slow 不再是孤儿状态)
	assert_float(Enemy.effective_slow_vuln(true, 0.0)).is_equal_approx(0.30, 0.0001)

func test_effective_slow_vuln_caps_at_half() -> void:
	# 基线 0.30 + 卡 0.50 → 封顶 0.50
	assert_float(Enemy.effective_slow_vuln(true, 0.5)).is_equal_approx(0.50, 0.0001)

# ── P1 单元4：元素增益消费点(状态输入修正) ─────────────────────────────────
func test_burn_mult_scales_burn_magnitude() -> void:
	var r := Enemy.modified_status_input(&"burn", 10.0, 1.0, 1.3, 0.0, 0.0)
	assert_float(r["magnitude"]).is_equal_approx(13.0, 0.0001)
	assert_float(r["duration"]).is_equal_approx(1.0, 0.0001)

func test_freeze_dur_bonus_extends_freeze() -> void:
	var r := Enemy.modified_status_input(&"freeze", 0.0, 0.6, 1.0, 0.5, 0.0)
	assert_float(r["duration"]).is_equal_approx(1.1, 0.0001)

func test_shock_dur_bonus_extends_stun() -> void:
	var r := Enemy.modified_status_input(&"stun", 0.0, 0.4, 1.0, 0.0, 0.15)
	assert_float(r["duration"]).is_equal_approx(0.55, 0.0001)

func test_slow_status_unaffected_by_element_mods() -> void:
	var r := Enemy.modified_status_input(&"slow", 0.6, 1.5, 1.3, 0.5, 0.15)
	assert_float(r["magnitude"]).is_equal_approx(0.6, 0.0001)
	assert_float(r["duration"]).is_equal_approx(1.5, 0.0001)
