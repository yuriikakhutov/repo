Invoke-WebRequest https://raw.githubusercontent.com/dotabuff/d2vpkr/master/dota/scripts/npc/items.json -OutFile items.json
Invoke-WebRequest https://raw.githubusercontent.com/dotabuff/d2vpkr/master/dota/scripts/npc/npc_abilities.json -OutFile npc_abilities.json
Invoke-WebRequest https://raw.githubusercontent.com/dotabuff/d2vpkr/master/dota/scripts/npc/npc_heroes.json -OutFile npc_heroes.json
Invoke-WebRequest https://raw.githubusercontent.com/dotabuff/d2vpkr/master/dota/scripts/npc/npc_units.json -OutFile npc_units.json
Write-Host "Press any key to continue..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")