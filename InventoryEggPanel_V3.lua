-- PSICOSENATICO Inventory Panel V3
-- Egg identity is kept separate from contained pet/category.
-- Uses a dedicated scrolling list and UID-first Tool matching.

if _G.PSICO_INVENTORY_PANEL_CLEANUP then pcall(_G.PSICO_INVENTORY_PANEL_CLEANUP) end
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local LP=Players.LocalPlayer
local alive=true
local conns={}
local function conn(s,f)local c=s:Connect(f);conns[#conns+1]=c;return c end
local function req(path)local x=RS;for p in path:gmatch('[^%.]+') do x=x and x:FindFirstChild(p) end;if not(x and x:IsA('ModuleScript'))then return nil end;local ok,v=pcall(require,x);return ok and v or nil end
local Save=req('Shared.Save') or req('Data.Save')
local EggRecords=req('Shared.Util.EggRecords')
local Assets=req('Data.Assets')
local Earnings=req('Shared.Util.AssetEarnings')
local function call(t,n,...)if type(t)~='table'or type(t[n])~='function'then return nil end;local ok,v=pcall(t[n],...);if ok then return v end;ok,v=pcall(t[n],t,...);return ok and v or nil end
local function norm(v)return tostring(v or ''):lower():gsub('[%s_%-%.:/%[%]%(%)\'•]','')end
local function compact(n)n=tonumber(n);if not n then return '?'end;local a=math.abs(n);if a>=1e12 then return ('%.2fT'):format(n/1e12)elseif a>=1e9 then return ('%.2fB'):format(n/1e9)elseif a>=1e6 then return ('%.2fM'):format(n/1e6)elseif a>=1e3 then return ('%.1fK'):format(n/1e3)end;return tostring(math.floor(n+.5))end
local function round(o,r)local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,r or 8);c.Parent=o end
local function label(p,t,pos,size,sz)local x=Instance.new('TextLabel');x.BackgroundTransparency=1;x.Position=pos;x.Size=size;x.Font=Enum.Font.Gotham;x.Text=t;x.TextSize=sz or 10;x.TextColor3=Color3.fromRGB(225,232,245);x.TextXAlignment=Enum.TextXAlignment.Left;x.Parent=p;return x end
local function button(p,t,pos,size)local x=Instance.new('TextButton');x.BackgroundColor3=Color3.fromRGB(35,44,61);x.BorderSizePixel=0;x.Position=pos;x.Size=size;x.Font=Enum.Font.GothamMedium;x.Text=t;x.TextSize=10;x.TextColor3=Color3.fromRGB(242,246,255);x.Parent=p;round(x,8);return x end
local function findPanel()
 local roots={};local ok,h=pcall(function()return gethui and gethui()end);if ok and h then roots[#roots+1]=h end;roots[#roots+1]=game:GetService('CoreGui')
 for _,r in ipairs(roots)do for _,g in ipairs(r:GetChildren())do if g:IsA('ScreenGui')and g.Name:find('PsicoRoubeUmOvo',1,true)==1 then local m=g:FindFirstChild('Main');if m then return g,m end end end end
end
local gui,main=findPanel();if not main then error('PSICO main panel not found')end
-- discover sidebar/content from existing V8.3
local sidebar,host
for _,d in ipairs(main:GetDescendants())do
 if d:IsA('TextButton')and d.Text=='FUNÇÕES'then sidebar=d.Parent end
end
if not sidebar then error('sidebar not found')end
for _,d in ipairs(main:GetDescendants())do if d:IsA('Frame')and d~=sidebar and d.AbsoluteSize.X>main.AbsoluteSize.X*.55 and d.AbsoluteSize.Y>main.AbsoluteSize.Y*.55 then host=d end end
if not host then error('content host not found')end
local tab=button(sidebar,'OVOS INVENTÁRIO',UDim2.new(0,0,0,250),UDim2.new(1,0,0,108))
local page=Instance.new('Frame');page.Name='InventoryEggPageV3';page.BackgroundTransparency=1;page.Size=UDim2.fromScale(1,1);page.Visible=false;page.Parent=host
local top=Instance.new('Frame');top.BackgroundTransparency=1;top.Size=UDim2.new(1,-20,0,88);top.Position=UDim2.new(0,10,0,10);top.Parent=page
local refresh=button(top,'Atualizar inventário',UDim2.new(0,0,0,0),UDim2.new(1,0,0,44))
local status=label(top,'',UDim2.new(0,0,0,50),UDim2.new(1,0,0,24),9);status.TextXAlignment=Enum.TextXAlignment.Center
local list=Instance.new('ScrollingFrame');list.Name='EggList';list.BackgroundTransparency=1;list.BorderSizePixel=0;list.Position=UDim2.new(0,10,0,100);list.Size=UDim2.new(1,-20,1,-110);list.ScrollBarThickness=5;list.ScrollingDirection=Enum.ScrollingDirection.Y;list.AutomaticCanvasSize=Enum.AutomaticSize.Y;list.CanvasSize=UDim2.new();list.Parent=page
local layout=Instance.new('UIListLayout');layout.Padding=UDim.new(0,6);layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.Parent=list
local pad=Instance.new('UIPadding');pad.PaddingBottom=UDim.new(0,18);pad.Parent=list
local function tools()local a={};for _,r in ipairs({LP:FindFirstChildOfClass('Backpack'),LP.Character})do if r then for _,x in ipairs(r:GetChildren())do if x:IsA('Tool')then a[#a+1]=x end end end end;return a end
local UID_KEYS={'UID','Uid','uid','EggUID','EggUid','ItemUID','ItemUid','Id','ID','id'}
local function val(obj,k)if not obj then return nil end;local ok,v=pcall(function()return obj:GetAttribute(k)end);if ok and v~=nil then return v end;local c=obj:FindFirstChild(k);if c and c:IsA('ValueBase')then return c.Value end end
local function recval(rec,k)if type(rec)~='table'then return nil end;if rec[k]~=nil then return rec[k]end;local it=type(rec.ItemData)=='table'and rec.ItemData;if it and it[k]~=nil then return it[k]end end
local function uidSet(key,rec)local s={};local function add(v)if v~=nil then s[norm(v)]=true end end;add(key);for _,k in ipairs(UID_KEYS)do add(recval(rec,k))end;return s end
local function weight(rec)local v=call(EggRecords,'WeightKg',rec);return tonumber(v)end
local function weightLabel(rec)local v=call(EggRecords,'WeightLabel',rec);return v and tostring(v)or nil end
local function category(rec)return recval(rec,'AssetCategory')or recval(rec,'Category')or recval(rec,'Name')end
local function matchTool(key,rec)
 local ids=uidSet(key,rec);local best,bscore=nil,-1;local rw=weight(rec)
 for _,t in ipairs(tools())do local score=0;for _,k in ipairs(UID_KEYS)do local x=val(t,k);if x~=nil and ids[norm(x)]then score=1000 break end end
  local tn=norm(t.Name);if tn:find('ovo',1,true)or tn:find('egg',1,true)then score=score+80 end
  local tw=t.Name:match('([%d%.,]+)%s*[Kk][Gg]');if rw and tw then local n=tonumber((tw:gsub('%.',''):gsub(',','.')));if n and math.abs(n-rw)<.02 then score=score+150 end end
  if score>bscore then best,bscore=t,score end
 end
 return bscore>=80 and best or nil,bscore
end
local function toolImage(t)if not t then return nil end;if t.TextureId and t.TextureId~=''then return t.TextureId end;for _,d in ipairs(t:GetDescendants())do if d:IsA('ImageLabel')or d:IsA('ImageButton')then if d.Image~=''then return d.Image end end end end
local function contentName(rec)return tostring(category(rec)or'?')end
local function rarityFor(cat)
 if type(Assets)~='table'then return nil,nil end
 local target=norm(cat);local function scan(tbl)for k,c in pairs(tbl or{})do if type(c)=='table'and type(c.Rarity)=='table'then local dn=c.DisplayName or k;if norm(k)==target or norm(dn)==target then return c.Rarity.DisplayName or c.Rarity._id,c end end end end
 if type(Assets.ByRarity)=='table'then for _,g in pairs(Assets.ByRarity)do local r,c=scan(g);if r then return r,c end end end
 if type(Assets.Configs)=='table'then return scan(Assets.Configs)end
end
local colors={Eternal=Color3.fromRGB(245,71,255),Divine=Color3.fromRGB(52,255,238),Secret=Color3.fromRGB(245,245,245),Cosmic=Color3.fromRGB(150,67,255),Mythic=Color3.fromRGB(255,71,121)}
local function clear()for _,x in ipairs(list:GetChildren())do if x:IsA('GuiObject')then x:Destroy()end end end
local current={}
local function render()
 clear();current={};local sd=Save and call(Save,'Get');local inv=type(sd)=='table'and sd.EggInventory;if type(inv)~='table'then status.Text='EggInventory indisponível';return end
 local rows={};for key,rec in pairs(inv)do if type(rec)=='table'then local cat=contentName(rec);local rar,cfg=rarityFor(cat);local w=weight(rec);local wl=weightLabel(rec);local sell=call(EggRecords,'SellPrice',rec);local eps=cfg and tonumber(cfg.EarningRate);local tool,score=matchTool(key,rec);rows[#rows+1]={key=key,rec=rec,cat=cat,rar=rar or tostring(rec.Rarity or'?'),w=w,wl=wl,sell=sell,eps=eps,tool=tool,score=score,img=toolImage(tool)}end end
 table.sort(rows,function(a,b)return(a.w or 0)>(b.w or 0)end);status.Text=('Ovos:%d • vínculo UID/Tool quando disponível'):format(#rows)
 for i,e in ipairs(rows)do local card=Instance.new('TextButton');card.Name='Egg_'..i;card.AutoButtonColor=true;card.Text='';card.BackgroundColor3=Color3.fromRGB(25,34,50);card.BorderSizePixel=0;card.Size=UDim2.new(1,-4,0,92);card.LayoutOrder=i;card.Parent=list;round(card,10)
  local stroke=Instance.new('UIStroke');stroke.Thickness=2;stroke.Color=colors[e.rar]or Color3.fromRGB(74,112,190);stroke.Parent=card
  local img=Instance.new('ImageLabel');img.BackgroundColor3=Color3.fromRGB(17,24,37);img.BorderSizePixel=0;img.Position=UDim2.new(0,8,0,8);img.Size=UDim2.new(0,76,0,76);img.ScaleType=Enum.ScaleType.Fit;img.Image=e.img or'';img.Parent=card;round(img,8)
  local title='Ovo'..(e.wl and(' '..e.wl)or(e.w and(' ('..compact(e.w)..'Kg)')or''));local t=label(card,title,UDim2.new(0,94,0,10),UDim2.new(1,-104,0,25),12);t.Font=Enum.Font.GothamBold;t.TextColor3=colors[e.rar]or Color3.fromRGB(235,240,250)
  label(card,(e.rar or'?')..' • Conteúdo: '..e.cat,UDim2.new(0,94,0,36),UDim2.new(1,-104,0,22),9)
  local meta={};if e.eps then meta[#meta+1]='$'..compact(e.eps)..'/s'end;if tonumber(e.sell)then meta[#meta+1]='Valor $'..compact(e.sell)end;meta[#meta+1]=e.tool and('Tool vinculado'..(e.score>=1000 and' por UID'or''))or'Tool não vinculado';label(card,table.concat(meta,' • '),UDim2.new(0,94,0,60),UDim2.new(1,-104,0,20),8)
  conn(card.Activated,function()if not e.tool or not e.tool.Parent then local nt=matchTool(e.key,e.rec);e.tool=nt end;if e.tool then local hum=LP.Character and LP.Character:FindFirstChildOfClass('Humanoid');if hum then pcall(function()hum:EquipTool(e.tool)end);status.Text='Equipado: '..title end else status.Text='Sem Tool correspondente para este ovo' end end)
 end
end
local function show()
 for _,d in ipairs(host:GetChildren())do if d:IsA('GuiObject')and d~=page then d.Visible=false end end;page.Visible=true;render()
end
conn(tab.Activated,show);conn(refresh.Activated,render)
_G.PSICO_INVENTORY_PANEL_CLEANUP=function()alive=false;for _,c in ipairs(conns)do pcall(function()c:Disconnect()end)end;pcall(function()page:Destroy()end);pcall(function()tab:Destroy()end)end
