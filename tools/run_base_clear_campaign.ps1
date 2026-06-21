# tools/run_base_clear_campaign.ps1 — 报告 §5① 内容广度:base 清场组支配测量。
# solobase_ 档(永不进化,纯 base L3)× 种子,出 base 武器自身清场支配报告。
# 跑前先关编辑器(LimboAI 双实例陷阱)。--fixed-fps 60 保 C5 确定性。
param(
	[string]$Godot = "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe",
	[string]$Proj = "D:\Workspace\GAME\game_0_vsl",
	[int[]]$Seeds = @(7, 42, 101, 1, 2),
	[string[]]$Weapons = @("explosion","lightning","maul","frostbite","aura"),  # clear 角色组(P3c EVOLUTION_ROLE)
	[double]$MaxTime = 600,
	[double]$Fast = 8,
	[string]$OutDir = "telemetry/base_clear"
)
foreach ($w in $Weapons) {
	foreach ($s in $Seeds) {
		$out = "$OutDir/solobase_${w}_s${s}"
		Write-Host "[base_clear] solobase_$w seed=$s"
		& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=solobase_$w --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
	}
}
Write-Host "[base_clear] campaign 完成。分析:"
& $Godot --headless --path $Proj -s res://tools/analyze_base_clear.gd -- --dir=$OutDir
