# tools/run_ab_matrix.ps1 — 跑「单武器档 × 种子」确定性 A/B 矩阵。
param(
	[string]$Godot = "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe",
	[string]$Proj = "D:\Workspace\GAME\game_0_vsl",
	[int[]]$Seeds = @(1, 2, 3, 4, 5),
	[string[]]$Profiles = @("solo_knife","solo_whip","solo_boomerang","solo_explosion","solo_aura","solo_lightning","solo_orb","solo_maul","solo_frostbite","solo_gravity_well","solo_reanimate"),
	[double]$MaxTime = 600,
	[double]$Fast = 8,
	[string]$OutDir = "telemetry/ab"
)
foreach ($prof in $Profiles) {
	foreach ($s in $Seeds) {
		$out = "$OutDir/${prof}_s${s}"
		Write-Host "[A/B] $prof seed=$s"
		& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=$prof --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
	}
}
Write-Host "[A/B] 完成。分析: -s res://tools/analyze_runs.gd -- --dir=$OutDir"
