# tools/run_p2a_campaign.ps1 — P2a 进化平衡 campaign:11 solo 档 × 种子,dodge 探针,出多轴报告。
# 跑前先关编辑器(LimboAI 双实例陷阱)。
param(
	[string]$Godot = "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe",
	[string]$Proj = "D:\Workspace\GAME\game_0_vsl",
	[int[]]$Seeds = @(7, 42, 101, 1, 2, 3, 4, 5),
	[string[]]$Weapons = @("knife","whip","boomerang","explosion","aura","lightning","orb","maul","frostbite","gravity_well","reanimate"),
	[double]$MaxTime = 600,
	[double]$Fast = 8,
	[string]$OutDir = "telemetry/p2a"
)
foreach ($w in $Weapons) {
	foreach ($s in $Seeds) {
		$out = "$OutDir/solo_${w}_s${s}"
		Write-Host "[P2a] solo_$w seed=$s"
		& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=solo_$w --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
	}
}
Write-Host "[P2a] campaign 完成。分析:"
& $Godot --headless --path $Proj -s res://tools/analyze_evolutions.gd -- --dir=$OutDir
