-- PSICOSENATICO Inventory V5
-- Compact list, sidebar alignment, 3-mode sort, images and conservative egg Tool matching.
if _G.PSICO_INVENTORY_PANEL_CLEANUP then pcall(_G.PSICO_INVENTORY_PANEL_CLEANUP) end
local Players=game:GetService('Players');local RS=game:GetService('ReplicatedStorage');local CoreGui=game:GetService('CoreGui');local LP=Players.LocalPlayer
local conns={};local function conn(s,f)local c=s:Connect(f);conns[#conns+1]=c;return c end
local function norm(v)return tostring(v or ''):lower():gsub('[%s_%-%.:/%[%]%(%)\'•]','')end
local function path(p)local x=RS;for q in p:gmatch('[^%.]+')do x=x and x:FindFirstChild(q)end;return x end
local function req(p)local x=path(p);if not(x and x:IsA('ModuleScript'))then return nil end;local ok,v=pcall(require,x);return ok and v or nil end
local Save=req('Shared.Save')or req('Data.Save');local ER=req('Shared.Util.EggRecords');local Assets=req('Data.Assets')
local function call(t,n,...)if type(t)~='table'or type(t[n])~='function'then return nil end;local ok,v=pcall(t[n],...);if ok then return v end;ok,v=pcall(t[n],t,...);return ok and v or nil end
local function round(o,r)local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,r or 8);c.Parent=o end
local function label(p,t,pos,size,sz)local x=Instance.new('TextLabel');x.BackgroundTransparency=1;x.Position=pos;x.Size=size;x.Font=Enum.Font.Gotham;x.Text=t;x.TextSize=sz or 9;x.TextColor3=Color3.fromRGB(225,232,245);x.TextXAlignment=Enum.TextXAlignment.Left;x.Parent=p;return x end
local function button(p,t,pos,size)local x=Instance.new('TextButton');x.BackgroundColor3=Color3.fromRGB(35,44,61);x.BorderSizePixel=0;x.Position=pos;x.Size=size;x.Font=Enum.Font.GothamMedium;x.Text=t;x.TextSize=10;x.TextColor3=Color3.fromRGB(242,246,255);x.Parent=p;round(x,8);return x end
local root=(function()local ok,h=pcall(function()return gethui and gethui()end);return(ok and h)or CoreGui end)();local gui,main
for _,g in ipairs(root:GetChildren())do if g:IsA('ScreenGui')and g.Name:find('PsicoRoubeUmOvo',1,true)==1 then gui=g;main=g:FindFirstChild('Main');if main then break end end end
if not main then error('main panel not found')end
local function text(s)for _,d in ipairs(main:GetDescendants())do if(d:IsA('TextButton')or d:IsA('TextLabel'))and d.Text==s then return d end end end
local fun=text('FUNÇÕES');local filters=text('FILTROS ESP');local normal=text('ESP • Ovos  ON')or text('ESP • Ovos  OFF')or text('ESP • Ovos');local rarity=text('Raridade mínima')
if not(fun and filters and normal and rarity)then error('base anchors not found')end
local sidebar=filters.Parent;local mainPage=normal.Parent;local filterPage=rarity.Parent;local host=mainPage.Parent
-- Place third tab directly below filters using the same dimensions/gap.
local gap=filters.Position.Y.Offset-fun.Position.Y.Offset-fun.Size.Y.Offset;if gap<0 or gap>80 then gap=12 end
local tab=button(sidebar,'OVOS INVENTÁRIO',UDim2.new(filters.Position.X.Scale,filters.Position.X.Offset,filters.Position.Y.Scale,filters.Position.Y.Offset+filters.Size.Y.Offset+gap),filters.Size)
local page=Instance.new('Frame');page.Name='InventoryEggPageV5';page.BackgroundTransparency=1;page.Position=mainPage.Position;page.Size=mainPage.Size;page.AnchorPoint=mainPage.AnchorPoint;page.Visible=false;page.Parent=host
local refresh=button(page,'Atualizar inventário',UDim2.new(0,10,0,10),UDim2.new(1,-20,0,38));local sort=button(page,'Ordenar: $/s',UDim2.new(0,10,0,54),UDim2.new(1,-20,0,34));local status=label(page,'',UDim2.new(0,10,0,91),UDim2.new(1,-20,0,18),8);status.TextXAlignment=Enum.TextXAlignment.Center
local list=Instance.new('ScrollingFrame');list.BackgroundTransparency=1;list.BorderSizePixel=0;list.Position=UDim2.new(0,10,0,112);list.Size=UDim2.new(1,-20,1,-122);list.ScrollBarThickness=4;list.ScrollingDirection=Enum.ScrollingDirection.Y;list.AutomaticCanvasSize=Enum.AutomaticSize.Y;list.CanvasSize=UDim2.new();list.Parent=page
local lay=Instance.new('UIListLayout');lay.Padding=UDim.new(0,5);lay.Parent=list;local pad=Instance.new('UIPadding');pad.PaddingBottom=UDim.new(0,30);pad.Parent=list
local modes={'$/s','Raridade','Valor do ovo'};local mode=1
local rarityNum={Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Cosmic=7,Secret=8,Eternal=9,Divine=10}
local colors={Legendary=Color3.fromRGB(255,174,58),Mythic=Color3.fromRGB(255,71,121),Cosmic=Color3.fromRGB(150,67,255),Secret=Color3.fromRGB(245,245,245),Eternal=Color3.fromRGB(245,71,255),Divine=Color3.fromRGB(52,255,238)}
local function compact(n)n=tonumber(n);if not n then return'?'end;if math.abs(n)>=1e12 then return('%.2fT'):format(n/1e12)elseif math.abs(n)>=1e9 then return('%.2fB'):format(n/1e9)elseif math.abs(n)>=1e6 then return('%.2fM'):format(n/1e6)elseif math.abs(n)>=1e3 then return('%.1fK'):format(n/1e3)end;return tostring(math.floor(n+.5))end
local function rv(r,k)if type(r)~='table'then return nil end;if r[k]~=nil then return r[k]end;local i=type(r.ItemData)=='table'and r.ItemData;return i and i[k]end
local function cat(r)return rv(r,'AssetCategory')or rv(r,'Category')or rv(r,'Name')end
local function catalog(c)if type(Assets)~='table'then return nil end;local n=norm(c);local function scan(t)for k,v in pairs(t or{})do if type(v)=='table'and type(v.Rarity)=='table'and(norm(k)==n or norm(v.DisplayName)==n)then return v end end end;if type(Assets.ByRarity)=='table'then for _,g in pairs(Assets.ByRarity)do local v=scan(g);if v then return v end end end;return type(Assets.Configs)=='table'and scan(Assets.Configs)end
local function tableImage(t,depth,seen)if type(t)~='table'or depth>4 then return nil end;seen=seen or{};if seen[t]then return nil end;seen[t]=true;for k,v in pairs(t)do local nk=norm(k);if nk:find('image',1,true)or nk:find('icon',1,true)or nk:find('texture',1,true)then if type(v)=='string'and v~=''then return v:match('^%d+$')and('rbxassetid://'..v)or v elseif type(v)=='number'and v>1000 then return'rbxassetid://'..math.floor(v)end end end;for _,v in pairs(t)do if type(v)=='table'then local x=tableImage(v,depth+1,seen);if x then return x end end end end
local UID={'UID','Uid','uid','EggUID','EggUid','ItemUID','ItemUid','ID','Id','id'}
local function oval(o,k)local ok,v=pcall(function()return o:GetAttribute(k)end);if ok and v~=nil then return v end;local c=o:FindFirstChild(k);return c and c:IsA('ValueBase')and c.Value or nil end
local function tools()local a={};for _,r in ipairs({LP:FindFirstChildOfClass('Backpack'),LP.Character})do if r then for _,t in ipairs(r:GetChildren())do if t:IsA('Tool')then a[#a+1]=t end end end end;return a end
local function toolFor(key,rec)
 local ids={};ids[norm(key)]=true;for _,k in ipairs(UID)do local v=rv(rec,k);if v~=nil then ids[norm(v)]=true end end
 for _,t in ipairs(tools())do for _,k in ipairs(UID)do local v=oval(t,k);if v~=nil and ids[norm(v)]then return t,'UID' end end end
 -- Safe fallback only for Tools explicitly marked/named as egg; never arbitrary pets.
 local w=tonumber(call(ER,'WeightKg',rec));for _,t in ipairs(tools())do local tn=norm(t.Name);if tn:find('ovo',1,true)or tn:find('egg',1,true)then if w then local raw=t.Name:match('([%d%.,]+)%s*[Kk][Gg]');if raw then local n=tonumber(raw:gsub('%.',''):gsub(',','.'));if n and math.abs(n-w)<.02 then return t,'peso' end end end end end
 return nil,nil
end
local function toolImage(t)if not t then return nil end;if t.TextureId and t.TextureId~=''then return t.TextureId end;for _,d in ipairs(t:GetDescendants())do if(d:IsA('ImageLabel')or d:IsA('ImageButton'))and d.Image~=''then return d.Image end end end
local rows={}
local function clear()for _,x in ipairs(list:GetChildren())do if x:IsA('GuiObject')then x:Destroy()end end end
local function read()
 rows={};local sd=Save and call(Save,'Get');local inv=type(sd)=='table'and sd.EggInventory;if type(inv)~='table'then return end
 for key,r in pairs(inv)do if type(r)=='table'then local c=tostring(cat(r)or'?');local cfg=catalog(c);local rar=cfg and(cfg.Rarity.DisplayName or cfg.Rarity._id)or tostring(r.Rarity or'?');local earn=cfg and tonumber(cfg.EarningRate);local sell=tonumber(call(ER,'SellPrice',r));local w=tonumber(call(ER,'WeightKg',r));local wl=call(ER,'WeightLabel',r);local tool,why=toolFor(key,r);local img=toolImage(tool)or tableImage(r,0,{})or tableImage(cfg,0,{});rows[#rows+1]={key=key,r=r,c=c,rar=rar,earn=earn,sell=sell,w=w,wl=wl,tool=tool,why=why,img=img}end end
end
local function render()
 clear();read();table.sort(rows,function(a,b)if mode==1 then return(a.earn or 0)>(b.earn or 0)elseif mode==2 then return(rarityNum[a.rar]or 0)>(rarityNum[b.rar]or 0)else return(a.sell or 0)>(b.sell or 0)end end);status.Text=('Ovos:%d • Ordenação: %s'):format(#rows,modes[mode])
 for i,e in ipairs(rows)do local card=Instance.new('TextButton');card.Text='';card.BackgroundColor3=Color3.fromRGB(25,34,50);card.BorderSizePixel=0;card.Size=UDim2.new(1,-4,0,64);card.LayoutOrder=i;card.Parent=list;round(card,9);local st=Instance.new('UIStroke');st.Thickness=1.5;st.Color=colors[e.rar]or Color3.fromRGB(74,112,190);st.Parent=card
  local im=Instance.new('ImageLabel');im.BackgroundColor3=Color3.fromRGB(17,24,37);im.BorderSizePixel=0;im.Position=UDim2.new(0,6,0,6);im.Size=UDim2.new(0,52,0,52);im.ScaleType=Enum.ScaleType.Fit;im.Image=e.img or'';im.Parent=card;round(im,7)
  local title='Ovo '..tostring(e.wl or(e.w and(compact(e.w)..'Kg')or'?'));local t=label(card,title,UDim2.new(0,66,0,7),UDim2.new(1,-72,0,19),10);t.Font=Enum.Font.GothamBold;t.TextColor3=colors[e.rar]or Color3.fromRGB(235,240,250)
  label(card,e.rar..' • Conteúdo: '..e.c,UDim2.new(0,66,0,27),UDim2.new(1,-72,0,16),8);label(card,'$'..compact(e.earn)..'/s • Valor $'..compact(e.sell)..(e.tool and(' • Tool '..e.why)or''),UDim2.new(0,66,0,44),UDim2.new(1,-72,0,15),7)
  conn(card.Activated,function()local tool,why=toolFor(e.key,e.r);if not tool then status.Text='Este ovo não possui Tool correspondente carregada';return end;local hum=LP.Character and LP.Character:FindFirstChildOfClass('Humanoid');if hum then pcall(function()hum:EquipTool(tool)end);status.Text='Equipado: '..title..' ('..why..')'end end)
 end
end
local function show()for _,x in ipairs(host:GetChildren())do if x:IsA('GuiObject')then x.Visible=(x==page)end end;page.Visible=true;render()end
conn(tab.Activated,show);conn(refresh.Activated,render);conn(sort.Activated,function()mode=mode%3+1;sort.Text='Ordenar: '..modes[mode];render()end)
-- Preserve base navigation and restore their pages.
conn(fun.Activated,function()page.Visible=false;mainPage.Visible=true;filterPage.Visible=false end);conn(filters.Activated,function()page.Visible=false;mainPage.Visible=false;filterPage.Visible=true end)
_G.PSICO_INVENTORY_PANEL_CLEANUP=function()for _,c in ipairs(conns)do pcall(function()c:Disconnect()end)end;pcall(function()page:Destroy()end);pcall(function()tab:Destroy()end)end