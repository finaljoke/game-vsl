# tools/run_p3_mix_campaign.ps1 — P3 混编 A/B:mixbase 基线 + 目标(knife/orb)+ explosion(强清场控制组)。
# 跑前先关编辑器(LimboAI 双实例陷阱)。explosion 作控制:solo 已知强清场(backlog 5),用于给
# knife/orb 的边际清场定标——若 knife 边际≈explosion 则 thousand_edge 亦为强清场(OP 嫌疑)。
param(
	[string]$Godot = "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe",
	[string]$Proj = "D:\Workspace\GAME\game_0_vsl",
	[int[]]$Seeds = @(7, 42, 101, 1, 2, 3, 4, 5),
	[string[]]$Targets = @("knife", "orb", "explosion"),
	[double]$MaxTime = 600,
	[double]$Fast = 8,
	[string]$OutDir = "telemetry/p3_mix"
)
# 基线:纯底盘
foreach ($s in $Seeds) {
	$out = "$OutDir/mixbase_s${s}"
	Write-Host "[P3-mix] mixbase seed=$s"
	& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=mixbase --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
}
# 处理组:底盘 + 目标
foreach ($t in $Targets) {
	foreach ($s in $Seeds) {
		$out = "$OutDir/mix_${t}_s${s}"
		Write-Host "[P3-mix] mix_$t seed=$s"
		& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=mix_$t --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
	}
}
Write-Host "[P3-mix] campaign 完成。A/B 边际归因分析:"
& $Godot --headless --path $Proj -s res://tools/analyze_mix_ab.gd -- --dir=$OutDir
