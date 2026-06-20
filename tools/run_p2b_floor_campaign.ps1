# tools/run_p2b_floor_campaign.ps1 — P2b 地板 campaign:3 个纯 solo 测不到的进化,加 perk_hp 防御垫(solofloor_)重测。
# 跑前先关编辑器(LimboAI 双实例陷阱)。
param(
	[string]$Godot = "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe",
	[string]$Proj = "D:\Workspace\GAME\game_0_vsl",
	[int[]]$Seeds = @(7, 42, 101, 1, 2, 3, 4, 5),
	[string[]]$Weapons = @("knife", "orb", "whip"),
	[double]$MaxTime = 600,
	[double]$Fast = 8,
	[string]$OutDir = "telemetry/p2b_floor"
)
foreach ($w in $Weapons) {
	foreach ($s in $Seeds) {
		$out = "$OutDir/solofloor_${w}_s${s}"
		Write-Host "[P2b-floor] solofloor_$w seed=$s"
		& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=solofloor_$w --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
	}
}
Write-Host "[P2b-floor] campaign 完成。分析(地板辈独立基准):"
& $Godot --headless --path $Proj -s res://tools/analyze_evolutions.gd -- --dir=$OutDir
