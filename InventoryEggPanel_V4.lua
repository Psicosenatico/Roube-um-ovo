-- PSICOSENATICO Inventory Panel V4
-- UI-only structural fix: preserves the stable V8.5 layout anchors and uses a dedicated auto-sized scrolling list.
if _G.PSICO_INVENTORY_PANEL_CLEANUP then pcall(_G.PSICO_INVENTORY_PANEL_CLEANUP) end
local CoreGui=game:GetService('CoreGui')
local function uiParent() local ok,h=pcall(function() return gethui and gethui() end); return (ok and h) or CoreGui end
local function textDesc(root,text) for _,d in ipairs(root:GetDescendants()) do if (d:IsA('TextLabel') or d:IsA('TextButton')) and d.Text==text then return d end end end
local root=uiParent(); local gui,main
for _,g in ipairs(root:GetChildren()) do if g:IsA('ScreenGui') and g.Name:find('PsicoRoubeUmOvo',1,true)==1 and g:FindFirstChild('Main') then gui,main=g,g.Main;break end end
if not main then error('PSICO main panel not found') end
local tabMain=textDesc(main,'FUNÇÕES'); local tabFilters=textDesc(main,'FILTROS ESP')
local normal=textDesc(main,'ESP • Ovos  ON') or textDesc(main,'ESP • Ovos  OFF') or textDesc(main,'ESP • Ovos')
local rarity=textDesc(main,'Raridade mínima')
local mainPage=normal and normal.Parent; local filterPage=rarity and rarity.Parent
local host=mainPage and mainPage.Parent or (filterPage and filterPage.Parent); local sidebar=tabFilters and tabFilters.Parent
if not(tabMain and tabFilters and mainPage and filterPage and host and sidebar) then error('base UI anchors not found') end
local tab=tabFilters:Clone(); tab.Name='InventoryEggTabV4'; tab.Text='OVOS INVENTÁRIO'; tab.Parent=sidebar
local sideLayout=sidebar:FindFirstChildOfClass('UIListLayout')
if sideLayout then tab.LayoutOrder=tabFilters.LayoutOrder+1 else tab.Position=UDim2.new(tabFilters.Position.X.Scale,tabFilters.Position.X.Offset,tabFilters.Position.Y.Scale,tabFilters.Position.Y.Offset+130) end
local page=Instance.new('Frame'); page.Name='InventoryEggPageV4'; page.BackgroundColor3=mainPage.BackgroundColor3; page.BackgroundTransparency=mainPage.BackgroundTransparency; page.BorderSizePixel=0; page.Position=mainPage.Position; page.Size=mainPage.Size; page.AnchorPoint=mainPage.AnchorPoint; page.ClipsDescendants=true; page.Visible=false; page.Parent=host
for _,c in ipairs(mainPage:GetChildren()) do if c:IsA('UICorner') then c:Clone().Parent=page end end
local refresh=Instance.new('TextButton'); refresh.Name='Refresh'; refresh.Text='Atualizar inventário'; refresh.Font=Enum.Font.GothamMedium; refresh.TextSize=10; refresh.TextColor3=Color3.fromRGB(242,246,255); refresh.BackgroundColor3=Color3.fromRGB(35,44,61); refresh.BorderSizePixel=0; refresh.Position=UDim2.new(0,12,0,12); refresh.Size=UDim2.new(1,-24,0,40); refresh.Parent=page
local rc=Instance.new('UICorner');rc.CornerRadius=UDim.new(0,8);rc.Parent=refresh
local status=Instance.new('TextLabel'); status.Name='Status'; status.BackgroundTransparency=1; status.Position=UDim2.new(0,12,0,57); status.Size=UDim2.new(1,-24,0,22); status.Font=Enum.Font.Gotham; status.Text='Painel V4 pronto'; status.TextSize=9; status.TextColor3=Color3.fromRGB(160,178,210); status.TextXAlignment=Enum.TextXAlignment.Center; status.Parent=page
local list=Instance.new('ScrollingFrame'); list.Name='EggList'; list.BackgroundTransparency=1; list.BorderSizePixel=0; list.Position=UDim2.new(0,12,0,84); list.Size=UDim2.new(1,-24,1,-96); list.ScrollBarThickness=5; list.ScrollingDirection=Enum.ScrollingDirection.Y; list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.CanvasSize=UDim2.new(0,0,0,0); list.ClipsDescendants=true; list.Parent=page
local layout=Instance.new('UIListLayout'); layout.Padding=UDim.new(0,7); layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Parent=list
local pad=Instance.new('UIPadding'); pad.PaddingBottom=UDim.new(0,24); pad.Parent=list
local function select(which) mainPage.Visible=which=='main'; filterPage.Visible=which=='filter'; page.Visible=which=='inventory' end
local conns={}; local function conn(s,f)local c=s:Connect(f);conns[#conns+1]=c end
conn(tabMain.Activated,function()select('main')end); conn(tabFilters.Activated,function()select('filter')end); conn(tab.Activated,function()select('inventory')end)
_G.PSICO_INVENTORY_PANEL_V4={Page=page,List=list,Status=status,Refresh=refresh,Tab=tab}
_G.PSICO_INVENTORY_PANEL_CLEANUP=function() for _,c in ipairs(conns) do pcall(function()c:Disconnect()end) end; pcall(function()page:Destroy()end); pcall(function()tab:Destroy()end) end
