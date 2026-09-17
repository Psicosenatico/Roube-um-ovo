-- PSICOSENATICO Inventory V6
-- Loads stable V5, compacts the inventory header/list and adds a conservative UI-slot bridge.
local cb=tostring(os.time())..'_'..tostring(math.random(100000,999999))
local src=game:HttpGet('https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/InventoryEggPanel_V5.lua?cb='..cb)
local fn,err=loadstring(src);if not fn then error('Inventory V5 compile: '..tostring(err))end
local ok,e=pcall(fn);if not ok then error('Inventory V5 runtime: '..tostring(e))end

task.defer(function()
 task.wait(.15)
 local Players=game:GetService('Players');local CoreGui=game:GetService('CoreGui');local LP=Players.LocalPlayer
 local function root()local ok,h=pcall(function()return gethui and gethui()end);return(ok and h)or CoreGui end
 local main
 for _,g in ipairs(root():GetChildren())do if g:IsA('ScreenGui')and g.Name:find('PsicoRoubeUmOvo',1,true)==1 then main=g:FindFirstChild('Main');if main then break end end end
 if not main then return end
 local function txt(s)for _,d in ipairs(main:GetDescendants())do if(d:IsA('TextButton')or d:IsA('TextLabel'))and d.Text==s then return d end end end end
 local tab=txt('OVOS INVENTÁRIO');if not tab then return end
 local page
 for _,d in ipairs(main:GetDescendants())do if d:IsA('Frame')and d.Name=='InventoryEggPageV5'then page=d;break end end
 if not page then return end
 local refresh=txt('Atualizar inventário');local sort
 for _,d in ipairs(page:GetDescendants())do if d:IsA('TextButton')and d.Text:find('Ordenar:',1,true)==1 then sort=d;break end end
 local status
 for _,d in ipairs(page:GetChildren())do if d:IsA('TextLabel')then status=d end end
 local list
 for _,d in ipairs(page:GetChildren())do if d:IsA('ScrollingFrame')then list=d;break end end
 if refresh and sort then
  refresh.Position=UDim2.new(0,10,0,6);refresh.Size=UDim2.new(.49,-12,0,28)
  sort.Position=UDim2.new(.49,2,0,6);sort.Size=UDim2.new(.51,-12,0,28)
 end
 if status then status.Position=UDim2.new(0,10,0,36);status.Size=UDim2.new(1,-20,0,14);status.TextSize=7 end
 if list then
  list.Position=UDim2.new(0,10,0,52);list.Size=UDim2.new(1,-20,1,-56)
  local p=list:FindFirstChildOfClass('UIPadding');if p then p.PaddingBottom=UDim.new(0,8)end
 end
 -- Keep the third tab aligned with the existing sidebar even if scale/offset differs on mobile.
 local filters=txt('FILTROS ESP');if filters then local parent=filters.Parent;local fun=txt('FUNÇÕES');local gap=10;if fun and fun.Parent==parent then gap=math.max(6,filters.AbsolutePosition.Y-(fun.AbsolutePosition.Y+fun.AbsoluteSize.Y))end;tab.Position=UDim2.new(filters.Position.X.Scale,filters.Position.X.Offset,filters.Position.Y.Scale,filters.Position.Y.Offset+filters.Size.Y.Offset+gap);tab.Size=filters.Size end

 -- Passive UI-slot bridge: only uses an already-rendered inventory button whose visible text/weight matches the selected card.
 local function norm(v)return tostring(v or''):lower():gsub('[%s_%-%.:/%[%]%(%)\'•]','')end
 local function weight(s)local x=tostring(s or''):match('([%d%.,]+)%s*[Kk][Gg]');return x and x:gsub('%D','')or nil end
 local function visibleText(btn)local a={};for _,d in ipairs(btn:GetDescendants())do if(d:IsA('TextLabel')or d:IsA('TextButton'))and d.Visible and d.Text~=''then a[#a+1]=d.Text end end;return table.concat(a,' ')end
 local function uiCandidates()
  local out={};for _,rg in ipairs({LP:FindFirstChildOfClass('PlayerGui'),CoreGui})do if rg then for _,d in ipairs(rg:GetDescendants())do if(d:IsA('ImageButton')or d:IsA('TextButton'))and d.Visible and not d:IsDescendantOf(main)then out[#out+1]=d end end end end;return out
 end
 local function bridge(card)
  local title,detail='','';for _,d in ipairs(card:GetChildren())do if d:IsA('TextLabel')then if title==''then title=d.Text else detail=detail..' '..d.Text end end end
  local wt=weight(title..' '..detail);if not wt then return false end
  local best,bscore=nil,0
  for _,b in ipairs(uiCandidates())do local t=visibleText(b);local s=0;if weight(t)==wt then s=s+100 end;if norm(t):find('ovo',1,true)or norm(t):find('egg',1,true)then s=s+20 end;if s>bscore then best,bscore=b,s end end
  if best and bscore>=100 and firesignal then local ok=pcall(function()firesignal(best.MouseButton1Click)end);return ok end
  return false
 end
 if list then
  list.ChildAdded:Connect(function(card)if not card:IsA('TextButton')then return end;card.Activated:Connect(function()task.delay(.08,function()if status and status.Text:find('não possui Tool',1,true)then if bridge(card)then status.Text='Seleção enviada pelo slot visual correspondente'else status.Text='Registro encontrado, mas ainda sem Tool/slot equipável correspondente'end end end)end)end)
  for _,card in ipairs(list:GetChildren())do if card:IsA('TextButton')then card.Activated:Connect(function()task.delay(.08,function()if status and status.Text:find('não possui Tool',1,true)then if bridge(card)then status.Text='Seleção enviada pelo slot visual correspondente'else status.Text='Registro encontrado, mas ainda sem Tool/slot equipável correspondente'end end end)end)end end
 end
end)