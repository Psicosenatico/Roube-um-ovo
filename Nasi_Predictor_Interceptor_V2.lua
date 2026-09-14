--[[
PSICOSENATICO | NASI PREDICTOR INTERCEPTOR V2.1

Fluxo:
1) Abra o hub Nasi e espere a UI generica carregar.
2) Execute este interceptor.
3) Selecione Steal An Egg.
4) Quando o menu SAE abrir, toque MARCAR PREDICTOR.
5) Abra/atualize a aba Predictor.
6) Aguarde alguns segundos, toque SNAPSHOT e depois EXPORTAR.

Captura leve:
- HttpGet/HttpGetAsync
- request/http_request/syn.request equivalentes
- payloads com aparencia de Lua (arquivo separado quando writefile existe)
- chamadas globais de loadstring feitas depois da instalacao
- remotes filtrados por Egg/Rarity/Cycle/Predict/Spawn/Field/Lottery
- diferencas de getgenv/_G e textos novos da UI

Nao usa getgc, decompile, debug hooks ou scan de closures.
Nao altera ovos, ciclo, luck, movimento, combate ou dinheiro.
Authorization/Cookie e chaves sensiveis sao mascarados no relatorio.
]]

if _G.PSICO_NASI_INTERCEPTOR_V2_CLEANUP then
    pcall(_G.PSICO_NASI_INTERCEPTOR_V2_CLEANUP)
end

local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer
local G=(getgenv and getgenv()) or _G
local START_CLOCK=os.clock()
local START_UNIX=os.time()

local MAX={requests=400,loadstrings=100,remotes=250,payloads=40,ui=500,globals=700,payloadBytes=2500000}
local KEYWORDS={"egg","rarity","cycle","predict","spawn","field","lottery"}
local State={alive=true,phase="game_select",requests={},loadstrings={},remotes={},payloads={},marks={},snapshots={},originals={},seen={},uiBase={},globalBase={},gui=nil,status=nil}

local function now() return os.clock()-START_CLOCK end
local function safe(v)local ok,r=pcall(tostring,v);return ok and r or "?" end
local function cut(v,n)local s=safe(v);n=n or 220;if #s<=n then return s end;return s:sub(1,n).."...<"..(#s-n).." more>" end
local function low(v)return string.lower(safe(v)) end
local function bounded(t,v,n)t[#t+1]=v;if #t>n then table.remove(t,1) end end
local function host(url)return safe(url):match("^https?://([^/%?]+)") or "" end

local function sensitive(k)
    k=low(k)
    return k:find("key",1,true) or k:find("token",1,true) or k:find("auth",1,true) or k:find("secret",1,true) or k:find("session",1,true) or k:find("cookie",1,true) or k:find("password",1,true)
end

local function redactUrl(url)
    url=safe(url)
    local base,q=url:match("^([^?]+)%?(.*)$")
    if not q then return url end
    local out={}
    for part in q:gmatch("[^&]+") do
        local k,v=part:match("^([^=]+)=(.*)$")
        if k then out[#out+1]=k.."="..(sensitive(k) and "<redacted>" or v:sub(1,180)) else out[#out+1]=part:sub(1,180) end
    end
    return base.."?"..table.concat(out,"&")
end

local function redactHeaders(h)
    if type(h)~="table" then return nil end
    local out,n={},0
    for k,v in pairs(h) do
        n+=1;if n>30 then break end
        out[safe(k)]=sensitive(k) and "<redacted>" or cut(v,120)
    end
    return out
end

local function fingerprint(s)
    if type(s)~="string" then return "?" end
    local n=#s;local a=n>0 and string.byte(s,1) or 0;local b=n>1 and string.byte(s,math.floor(n/2)) or 0;local c=n>0 and string.byte(s,n) or 0;local d=0
    local step=math.max(1,math.floor(n/16))
    for i=1,n,step do d=(d+string.byte(s,i)*((i%251)+1))%2147483647 end
    return table.concat({n,a,b,c,d},":")
end

local function hasKeyword(s)
    s=low(s)
    for _,k in ipairs(KEYWORDS) do if s:find(k,1,true) then return true end end
    return false
end

local function looksLua(body,url)
    if type(body)~="string" or #body<20 then return false end
    local u=low(url or "");local p=body:sub(1,1000)
    return u:find(".lua",1,true)~=nil or u:find("raw.githubusercontent.com",1,true)~=nil or p:find("loadstring",1,true)~=nil or p:find("getgenv",1,true)~=nil or p:find("game:GetService",1,true)~=nil or p:find("Luraph",1,true)~=nil or p:match("^%s*return%s")~=nil or p:match("^%s*local%s")~=nil
end

local function savePayload(kind,body,source)
    if type(body)~="string" or #State.payloads>=MAX.payloads then return nil end
    local fp=fingerprint(body)
    if State.seen[fp] then return State.seen[fp] end
    local id=#State.payloads+1
    local name=string.format("Psico_Nasi_V2_%s_%03d_%d.lua.txt",kind,id,os.time())
    local saved=false;local note=nil
    if #body<=MAX.payloadBytes and type(writefile)=="function" then local ok,err=pcall(writefile,name,body);saved=ok;if not ok then note=cut(err,180) end
    elseif #body>MAX.payloadBytes then note="payload_too_large" else note="writefile_unavailable" end
    local row={id=id,t=now(),unix=os.time(),phase=State.phase,kind=kind,source=redactUrl(source or ""),bytes=#body,fingerprint=fp,file=saved and name or nil,saved=saved,note=note,preview=cut(body,240)}
    State.payloads[id]=row;State.seen[fp]=row;return row
end

local function recordRequest(source,method,url,opts,response,okFlag,err)
    if not State.alive then return end
    local status,body,headers
    if type(response)=="table" then status=response.StatusCode or response.Status or response.status_code or response.status;body=response.Body or response.body or response.ResponseBody or response.responseBody;headers=response.Headers or response.headers
    elseif type(response)=="string" then status=200;body=response end
    local payload=looksLua(body,url) and savePayload("http",body,url) or nil
    bounded(State.requests,{t=now(),unix=os.time(),phase=State.phase,source=source,method=safe(method or "GET"),url=redactUrl(url or "?"),host=host(url or ""),status=status,bytes=type(body)=="string" and #body or nil,ok=okFlag,error=err and cut(err,260) or nil,requestHeaders=type(opts)=="table" and redactHeaders(opts.Headers or opts.headers) or nil,responseHeaders=redactHeaders(headers),luaPayloadId=payload and payload.id or nil},MAX.requests)
end

local function wrapRequest(holder,key,label)
    local ok,original=pcall(function()return holder and holder[key] end)
    if not ok or type(original)~="function" then return false end
    local wrapper
    wrapper=function(opts,...)
        local url,method="?","GET"
        if type(opts)=="table" then url=opts.Url or opts.URL or opts.url or "?";method=opts.Method or opts.method or "GET" elseif type(opts)=="string" then url=opts end
        local packed=table.pack(pcall(original,opts,...))
        if packed[1] then recordRequest(label,method,url,opts,packed[2],true,nil);return table.unpack(packed,2,packed.n) end
        recordRequest(label,method,url,opts,nil,false,packed[2]);error(packed[2],0)
    end
    local setOk=pcall(function()holder[key]=wrapper end)
    if setOk then State.originals[#State.originals+1]={holder=holder,key=key,fn=original,wrapper=wrapper} end
    return setOk
end

local function installRequestHooks()
    local seen={}
    local function add(holder,key,label)
        local ok,fn=pcall(function()return holder and holder[key] end)
        if ok and type(fn)=="function" and not seen[fn] and wrapRequest(holder,key,label) then seen[fn]=true end
    end
    for _,name in ipairs({"request","http_request","httprequest"}) do add(G,name,name) end
    if type(G.syn)=="table" then add(G.syn,"request","syn.request") end
    if type(G.http)=="table" then add(G.http,"request","http.request") end
    if type(G.fluxus)=="table" then add(G.fluxus,"request","fluxus.request") end
end

local function installLoadstring()
    local original=rawget(G,"loadstring") or loadstring
    if type(original)~="function" then return end
    local wrapper
    wrapper=function(source,chunkname,...)
        if State.alive and type(source)=="string" then local p=savePayload("loadstring",source,chunkname or "loadstring");bounded(State.loadstrings,{t=now(),unix=os.time(),phase=State.phase,bytes=#source,fingerprint=fingerprint(source),chunkname=chunkname and cut(chunkname,160) or nil,payloadId=p and p.id or nil},MAX.loadstrings) end
        return original(source,chunkname,...)
    end
    if pcall(function()G.loadstring=wrapper end) then State.originals[#State.originals+1]={holder=G,key="loadstring",fn=original,wrapper=wrapper} end
    if G~=_G then local old=rawget(_G,"loadstring");if type(old)=="function" and old==original and pcall(function()_G.loadstring=wrapper end) then State.originals[#State.originals+1]={holder=_G,key="loadstring",fn=old,wrapper=wrapper} end end
end

local function arg(v,depth)
    depth=depth or 0;local tv=typeof(v)
    if tv=="string" then return cut(v,180) end
    if tv=="number" or tv=="boolean" or tv=="nil" then return v end
    if tv=="Instance" then local ok,r=pcall(function()return v:GetFullName() end);return ok and r or safe(v) end
    if tv=="table" and depth<1 then local out,n={},0;for k,x in pairs(v) do n+=1;if n>12 then out["<more>"]="...";break end;local ks=safe(k);out[ks]=sensitive(ks) and "<redacted>" or arg(x,depth+1) end;return out end
    return "<"..tv..":"..cut(v,80)..">"
end

local oldNamecall
local function installNamecall()
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then return end
    local closure
    closure=function(self,...)
        local method=getnamecallmethod()
        if State.alive and (method=="HttpGet" or method=="HttpGetAsync") then
            local a={...};local packed=table.pack(pcall(oldNamecall,self,...))
            if packed[1] then recordRequest("game:"..method,"GET",a[1],nil,packed[2],true,nil);return table.unpack(packed,2,packed.n) end
            recordRequest("game:"..method,"GET",a[1],nil,nil,false,packed[2]);error(packed[2],0)
        end
        if State.alive and (method=="FireServer" or method=="InvokeServer") then
            local full="";local ok=pcall(function()full=self:GetFullName() end);if not ok then full=safe(self) end
            if hasKeyword(full) then
                local raw={...};local args={};for i=1,math.min(#raw,10) do args[i]=arg(raw[i],0) end
                local row={t=now(),unix=os.time(),phase=State.phase,method=method,remote=full,args=args}
                if method=="InvokeServer" then
                    local packed=table.pack(pcall(oldNamecall,self,...))
                    if packed[1] then row.ok=true;row.returns={};for i=2,math.min(packed.n,7) do row.returns[#row.returns+1]=arg(packed[i],0) end;bounded(State.remotes,row,MAX.remotes);return table.unpack(packed,2,packed.n) end
                    row.ok=false;row.error=cut(packed[2],220);bounded(State.remotes,row,MAX.remotes);error(packed[2],0)
                else bounded(State.remotes,row,MAX.remotes) end
            end
        end
        return oldNamecall(self,...)
    end
    local ok=pcall(function()oldNamecall=hookmetamethod(game,"__namecall",type(newcclosure)=="function" and newcclosure(closure) or closure) end)
    if not ok then oldNamecall=nil end
end

local function compact(v)
    local tv=typeof(v)
    if tv=="string" then return {type=tv,value=cut(v,180)} end
    if tv=="number" or tv=="boolean" then return {type=tv,value=v} end
    if tv=="table" then local n=0;for _ in pairs(v) do n+=1;if n>1000 then break end end;return {type=tv,count=n} end
    return {type=tv}
end

local function globals()
    local out,count={},0
    local function add(tbl,prefix)
        if type(tbl)~="table" then return end
        for k,v in pairs(tbl) do count+=1;if count>MAX.globals then return end;local name=prefix..safe(k);if not sensitive(name) then out[name]=compact(v) end end
    end
    add(G,"G:");if G~=_G then add(_G,"_G:") end;return out
end

local function diff(old,new)
    local added,changed={},{}
    for k,v in pairs(new) do
        if old[k]==nil then added[k]=v else local ok1,a=pcall(HttpService.JSONEncode,HttpService,old[k]);local ok2,b=pcall(HttpService.JSONEncode,HttpService,v);if ok1 and ok2 and a~=b then changed[k]={before=old[k],after=v} end end
    end
    return added,changed
end

local function roots()
    local r={};local ok,h=pcall(function()return gethui and gethui() end);if ok and h then r[#r+1]=h end;r[#r+1]=CoreGui;local pg=LP and LP:FindFirstChildOfClass("PlayerGui");if pg then r[#r+1]=pg end;return r
end

local function uiTexts()
    local set,out={},{}
    for _,root in ipairs(roots()) do
        local ok,list=pcall(function()return root:GetDescendants() end)
        if ok then
            for _,x in ipairs(list) do
                if #out>=MAX.ui then break end
                if x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then
                    local okT,text=pcall(function()return x.Text end)
                    if okT and type(text)=="string" and text~="" and #text<=800 and not set[text] then set[text]=true;local path=safe(x);pcall(function()path=x:GetFullName() end);out[#out+1]={text=text,path=path} end
                end
            end
        end
    end
    return out,set
end

local function snapshot(label)
    local g=globals();local ui,set=uiTexts();local addG,chgG=diff(State.globalBase,g);local newUI={}
    for _,r in ipairs(ui) do if not State.uiBase[r.text] then newUI[#newUI+1]=r end end
    local row={t=now(),unix=os.time(),phase=State.phase,label=label,globalsAdded=addG,globalsChanged=chgG,newUITexts=newUI,counts={requests=#State.requests,loadstrings=#State.loadstrings,remotes=#State.remotes,payloads=#State.payloads}}
    State.snapshots[#State.snapshots+1]=row;State.globalBase=g;State.uiBase=set;return row
end

local function restoreWrappers()
    for i=#State.originals,1,-1 do local x=State.originals[i];pcall(function()if x.holder[x.key]==x.wrapper then x.holder[x.key]=x.fn end end) end
    table.clear(State.originals)
end

local function stopCapture()
    State.alive=false
    restoreWrappers()
end

local function report()
    local domains={};for _,r in ipairs(State.requests) do if r.host and r.host~="" then domains[r.host]=(domains[r.host] or 0)+1 end end
    return {Meta={Version="NasiPredictorInterceptorV2.1",PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,StartedUnix=START_UNIX,FinishedUnix=os.time(),FinalPhase=State.phase,Note="Observational capture. Auth/cookie/query secrets redacted. Lua-like bodies saved separately when possible."},Summary={Requests=#State.requests,Loadstrings=#State.loadstrings,Remotes=#State.remotes,Payloads=#State.payloads,Snapshots=#State.snapshots,Domains=domains},Marks=State.marks,Requests=State.requests,Loadstrings=State.loadstrings,Remotes=State.remotes,Payloads=State.payloads,Snapshots=State.snapshots}
end

local function status(s)if State.status and State.status.Parent then State.status.Text=s end end

local function export()
    snapshot("export")
    local ok,json=pcall(HttpService.JSONEncode,HttpService,report())
    if not ok then status("Erro JSON: "..cut(json,220));return end
    local name="Psico_Nasi_Predictor_Interceptor_V2_"..os.time()..".json";local wrote=false
    if type(writefile)=="function" then wrote=pcall(writefile,name,json) end;if type(setclipboard)=="function" then pcall(setclipboard,json) end
    stopCapture();status((wrote and "Exportado: " or "JSON copiado: ")..name.."\nCaptura encerrada e wrappers restaurados.\nPayloads: "..#State.payloads.." | Req: "..#State.requests.." | Remotes: "..#State.remotes)
end

local function parentGui()local ok,h=pcall(function()return gethui and gethui() end);return (ok and h) or CoreGui end
local function button(p,text,pos,size)local b=Instance.new("TextButton");b.Position=pos;b.Size=size;b.BackgroundColor3=Color3.fromRGB(27,67,114);b.BorderSizePixel=0;b.Text=text;b.TextColor3=Color3.fromRGB(240,247,255);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=p;Instance.new("UICorner",b).CornerRadius=UDim.new(0,8);return b end

local function makeGui()
    local p=parentGui();local old=p:FindFirstChild("PSICO_NASI_PREDICTOR_INTERCEPTOR_V2");if old then old:Destroy() end
    local gui=Instance.new("ScreenGui");gui.Name="PSICO_NASI_PREDICTOR_INTERCEPTOR_V2";gui.ResetOnSpawn=false;gui.DisplayOrder=1200;gui.Parent=p;State.gui=gui
    local frame=Instance.new("Frame");frame.AnchorPoint=Vector2.new(.5,.5);frame.Position=UDim2.fromScale(.5,.5);frame.Size=UDim2.fromOffset(440,260);frame.BackgroundColor3=Color3.fromRGB(10,19,36);frame.BorderSizePixel=0;frame.Parent=gui;Instance.new("UICorner",frame).CornerRadius=UDim.new(0,14)
    local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,9);title.Size=UDim2.new(1,-28,0,28);title.Font=Enum.Font.GothamBold;title.Text="NASI PREDICTOR INTERCEPTOR • V2.1";title.TextSize=14;title.TextColor3=Color3.fromRGB(235,244,255);title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=frame
    local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,43);st.Size=UDim2.new(1,-28,0,92);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.fromRGB(214,228,247);st.TextXAlignment=Enum.TextXAlignment.Left;st.TextYAlignment=Enum.TextYAlignment.Top;st.Parent=frame;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9);local pad=Instance.new("UIPadding",st);pad.PaddingLeft=UDim.new(0,8);pad.PaddingTop=UDim.new(0,7);State.status=st
    status("Ativo • fase: game_select\nSelecione Steal An Egg no Nasi.\nDepois marque PREDICTOR antes de abrir essa aba.")
    local mark=button(frame,"MARCAR PREDICTOR",UDim2.fromOffset(14,146),UDim2.new(.5,-20,0,34));local snap=button(frame,"SNAPSHOT",UDim2.new(.5,6,0,146),UDim2.new(.5,-20,0,34));local exp=button(frame,"EXPORTAR",UDim2.fromOffset(14,190),UDim2.new(.65,-20,0,34));local close=button(frame,"FECHAR",UDim2.new(.65,6,0,190),UDim2.new(.35,-20,0,34))
    mark.MouseButton1Click:Connect(function()State.phase="predictor";State.marks[#State.marks+1]={t=now(),unix=os.time(),phase="predictor"};snapshot("phase:predictor");status("Fase PREDICTOR marcada.\nAbra/atualize o Predictor e aguarde alguns segundos.\nDepois toque SNAPSHOT e EXPORTAR.") end)
    snap.MouseButton1Click:Connect(function()local s=snapshot("manual");status("Snapshot salvo. Novos textos UI: "..#s.newUITexts.."\nReq "..#State.requests.." | LS "..#State.loadstrings.." | Remote "..#State.remotes.." | Payload "..#State.payloads) end)
    exp.MouseButton1Click:Connect(export)
    close.MouseButton1Click:Connect(function()stopCapture();if State.gui then State.gui:Destroy() end end)
    local dragging=false;local dragStart,startPos
    frame.InputBegan:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true;dragStart=input.Position;startPos=frame.Position end end)
    frame.InputChanged:Connect(function(input)if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then local d=input.Position-dragStart;frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end)
    UIS.InputEnded:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
    task.spawn(function()while State.alive and st.Parent do task.wait(1);local last=State.requests[#State.requests];st.Text="Ativo • fase: "..State.phase.."\nReq "..#State.requests.." | LS "..#State.loadstrings.." | Remote "..#State.remotes.." | Payload "..#State.payloads..(last and ("\nUltimo host: "..(last.host~="" and last.host or "?")) or "") end end)
end

_G.PSICO_NASI_INTERCEPTOR_V2_CLEANUP=function()stopCapture();if State.gui then pcall(function()State.gui:Destroy() end) end end

State.globalBase=globals();local _,base=uiTexts();State.uiBase=base;State.marks[#State.marks+1]={t=now(),unix=os.time(),phase="game_select"}
installRequestHooks();installLoadstring();installNamecall();makeGui()
