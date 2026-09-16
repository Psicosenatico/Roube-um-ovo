-- PSICOSENATICO | Roube um Ovo - Precision Menu V8.7
-- New loader filename intentionally avoids stale raw/CDN cache from V8.5/V8.6 tests.

local cb=tostring(os.time()).."_"..tostring(math.random(100000,999999))
loadstring(game:HttpGet("https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/RoubeUmOvo_Menu.lua?cb="..cb))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/InventoryEggPanel_V2.lua?cb="..cb))()
