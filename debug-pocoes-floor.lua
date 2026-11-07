-- DebrisMagnet / Auto Pull v4. Consulta de segurar restrita a rotina original.
-- Sem ponteiro virtual, TP, alteracao da barra, forca ou quantidade de alvos.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
if env.MagnetDebug and type(env.MagnetDebug.Close)=="function" then pcall(env.MagnetDebug.Close) end
if type(env.__NetoMagnetProbe)=="table" then env.__NetoMagnetProbe.enabled=false end
local pg=player:WaitForChild("PlayerGui")
local alive,active=true,nil
local lastReport=nil
local start,stop,copy,close
local own=setmetatable({},{__mode="k"})
local lifetime={}
local getup=(debug and debug.getupvalues) or env.getupvalues
local getConstants=(debug and debug.getconstants) or env.getconstants
local getConnections=getconnections or env.getconnections
local function path(x)
    local ok,name=pcall(function() return x:GetFullName() end)
    return ok and name or "[removed]"
end
local function append(list,value,limit)
    list[#list+1]=value if #list>limit then table.remove(list,1) end
end
local function valid(s) return alive and active==s and s.running end
local function elapsed(s) return math.floor((os.clock()-s.started)*1000+.5)/1000 end
local function connect(signal,fn,list)
    own[fn]=true local c=signal:Connect(fn) list[#list+1]=c return c
end
local function disconnect(list) for _,c in ipairs(list) do c:Disconnect() end table.clear(list) end
local function values(fn)
    if type(getup)~="function" then return nil end
    local ok,result=pcall(getup,fn)
    return ok and type(result)=="table" and result or nil
end
local function shown(x)
    for _=1,18 do
        if not x then return false end
        if x:IsA("GuiObject") and not x.Visible then return false end
        if x:IsA("ScreenGui") then return x.Enabled end
        x=x.Parent
    end
    return false
end
local function hudState(s)
    local front=pg:FindFirstChild("Front") local main=front and front:FindFirstChild("MainFrame")
    local hud=main and main:FindFirstChild("DebrisHUD")
    local track=hud and hud:FindFirstChild("Track")
    local fill=track and track:FindFirstChild("Fill") local note=track and track:FindFirstChild("Note")
    local bag=hud and hud:FindFirstChild("Backpack") local count=bag and bag:FindFirstChild("Count")
    local used,capacity
    if count and count:IsA("TextLabel") then used,capacity=tostring(count.Text):match("(%d+)%s*/%s*(%d+)") end
    local text=note and tostring(note.Text):gsub("<[^>]+>","") or ""
    local percent=fill and fill.Size.X.Scale or 0
    local full=used and tonumber(used)>=tonumber(capacity) or false
    local ready=hud and shown(hud) or false
    local tool=player.Character and player.Character:FindFirstChild("DebrisMagnet")
    if not tool or not tool:IsA("Tool") or not tool.Enabled then ready=false end
    s.report.ui={note=text,progress=percent,visible=ready,used=tonumber(used),capacity=tonumber(capacity)}
    return ready,full,text,percent
end
local function event(s,kind,action,data)
    append(s.report.events,{t=elapsed(s),kind=kind,action=action,data=data},32)
end

local gui=Instance.new("ScreenGui") gui.Name="NetoMagnetDebug" gui.ResetOnSpawn=false gui.DisplayOrder=10034 gui.Parent=pg
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(325,216) panel.Position=UDim2.new(0,12,.06,0)
panel.BackgroundColor3=Color3.fromRGB(21,23,30) panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8)
local function button(text,x,y,width)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.Gotham b.TextSize=13 b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(66,49,110) b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(width,35) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="AUTO PULL / V4" title.Font=Enum.Font.GothamBold title.TextSize=14
title.BackgroundTransparency=1 title.TextColor3=Color3.new(1,1,1) title.Position=UDim2.fromOffset(10,0) title.Size=UDim2.fromOffset(220,36) title.Active=true title.Parent=panel
local minimize=button("-",244,1,32) local exit=button("X",282,1,33)
local toggle=button("Auto Pull: OFF",10,43,305) local copyButton=button("Copiar debug",10,85,305)
local label=Instance.new("TextLabel") label.Text="Equipe o ima, aponte para um item e ative.\nSomente Auto Pull nesta versao."
label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top
label.Font=Enum.Font.Gotham label.TextSize=12 label.TextColor3=Color3.new(1,1,1) label.BackgroundTransparency=1
label.Position=UDim2.fromOffset(10,130) label.Size=UDim2.fromOffset(305,76) label.Parent=panel
local output=Instance.new("TextBox") output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false output.Text=""
output.Font=Enum.Font.Code output.TextSize=10 output.BackgroundColor3=Color3.fromRGB(28,30,39) output.TextColor3=Color3.new(1,1,1)
output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top
output.Position=label.Position output.Size=label.Size output.Visible=false output.Parent=panel
local mini=Instance.new("TextButton") mini.Text="PULL" mini.Font=Enum.Font.GothamBold mini.TextSize=12 mini.TextColor3=Color3.new(1,1,1)
mini.BackgroundColor3=Color3.fromRGB(66,49,110) mini.Size=UDim2.fromOffset(64,35) mini.Position=panel.Position mini.Visible=false mini.Parent=gui

-- Estado separado por coroutine: somente consultas feitas pela rotina do ima.
local probe=env.__NetoMagnetHoldProbe
if type(probe)~="table" or probe.version~=2 then
    if type(probe)=="table" then probe.enabled=false probe.hold=false end
    probe={version=2,installed=false,enabled=false,stepHooks=setmetatable({},{__mode="k"}),methodHooks={},inside=setmetatable({},{__mode="k"})}
    env.__NetoMagnetHoldProbe=probe
end
local hookFn=hookfunction or env.hookfunction
local infoFn=debug and debug.info
local oldInfo=(debug and debug.getinfo) or env.getinfo
local mouseButton=Enum.UserInputType.MouseButton1
local downInput={UserInputType=mouseButton,UserInputState=Enum.UserInputState.Begin,KeyCode=Enum.KeyCode.Unknown,Position=Vector3.new(0,0,0),Delta=Vector3.new(0,0,0)}
local function inMagnet()
    if not probe.step then return false end
    if probe.inside[coroutine.running()]==probe.step then return true end
    if probe.gated and not probe.stackFallback then return false end
    for level=3,15 do
        local ok,fn=false,nil
        if type(infoFn)=="function" then ok,fn=pcall(infoFn,level,"f")
        elseif type(oldInfo)=="function" then
            local item
            ok,item=pcall(oldInfo,level,"f") fn=ok and item and item.func
        else break end
        if ok and type(fn)=="function" and (fn==probe.step or fn==probe.originalStep) then return true end
    end
    return false
end
local function query(self,method,arg)
    if not probe.enabled or self~=UIS or (method~="IsMouseButtonPressed" and method~="GetMouseButtonsPressed") then return false end
    if not inMagnet() then return false end
    probe.reads[method]=(probe.reads[method] or 0)+1
    if not probe.hold then return false end
    if method=="IsMouseButtonPressed" and arg~=mouseButton then return false end
    probe.overrides=probe.overrides+1
    probe.forced[method]=(probe.forced[method] or 0)+1
    if method=="IsMouseButtonPressed" then return true,true end
    return true,{downInput}
end
local function install()
    if probe.installed then return true end
    local hook=hookmetamethod or env.hookmetamethod local method=getnamecallmethod or env.getnamecallmethod
    if type(hook)~="function" or type(method)~="function" then return false end
    local original
    local wrapper=function(self,...)
        if probe.enabled then
            local name=method()
            if self==UIS then
                local first=... local handled,value=query(self,name,first)
                if handled then return value end
            elseif self==probe.remote and name=="FireServer" then
                if probe.tail-probe.head<128 then
                    local action,id=...
                    probe.tail=probe.tail+1
                    probe.queue[probe.tail]={action=action,id=id,at=os.clock(),own=probe.ownStop==true,overrides=probe.overrides}
                else probe.dropped=probe.dropped+1 end
            end
        end
        return original(self,...)
    end
    local native=newcclosure or env.newcclosure if type(native)=="function" then wrapper=native(wrapper) end
    local ok,result=pcall(hook,game,"__namecall",wrapper)
    if ok then original=result probe.installed=true end
    return ok
end
local function gateStep(s)
    local fn=s.step.fn local record=probe.stepHooks[fn]
    if record then probe.originalStep=record.original probe.gated=true s.report.scope="rotina do ima / coroutine" return true end
    if type(hookFn)~="function" then
        probe.gated=false s.report.scope="pilha da rotina do ima"
        return type(infoFn)=="function" or type(oldInfo)=="function"
    end
    local original
    local wrapper=function(...)
        if not probe.enabled or probe.step~=fn then return original(...) end
        local thread=coroutine.running() local previous=probe.inside[thread]
        probe.inside[thread]=fn probe.stepCalls=probe.stepCalls+1
        local results=table.pack(pcall(original,...))
        probe.inside[thread]=previous
        if not results[1] then error(results[2],0) end
        return table.unpack(results,2,results.n)
    end
    local ok,result=pcall(hookFn,fn,wrapper)
    if ok and type(result)=="function" then
        original=result probe.originalStep=result probe.stepHooks[fn]={source=s.step.source,inputConstants=s.report.inputConstants,original=result}
        probe.gated=true s.report.scope="rotina do ima / coroutine" return true
    end
    s.report.gateError=tostring(result):sub(1,160) probe.gated=false
    return type(infoFn)=="function" or type(oldInfo)=="function"
end
local function hookQueries(s)
    if type(hookFn)~="function" then return end
    for _,method in ipairs({"IsMouseButtonPressed","GetMouseButtonsPressed"}) do
        local selectedMethod=method
        if not probe.methodHooks[method] then
            local ok,fn=pcall(function() return UIS[method] end)
            if ok and type(fn)=="function" then
                local original
                local wrapper=function(self,...)
                    local first=... local handled,value=query(self,selectedMethod,first)
                    if handled then return value end
                    return original(self,...)
                end
                local good,result=pcall(hookFn,fn,wrapper)
                if good and type(result)=="function" then original=result probe.methodHooks[method]=true
                else s.report.methodHookError=tostring(result):sub(1,160) end
            end
        end
    end
end
local function drain(s)
    while probe.head<=probe.tail do
        local row=probe.queue[probe.head] probe.queue[probe.head]=nil probe.head=probe.head+1
        if type(row.action)=="string" and (row.action=="Start" or row.action=="Catch" or row.action=="Stop") then
            s.report.gameSent[row.action]=(s.report.gameSent[row.action] or 0)+(row.own and 0 or 1)
            if row.action=="Start" and type(row.id)=="number" then
                s.pending[row.id]={started=row.at,manual=s.report.manualTouches,clean=next(s.touches)==nil and row.at>s.lastManualEnd+.3,overrides=row.overrides}
            elseif row.action=="Stop" and type(row.id)=="number" then s.pending[row.id]=nil end
            event(s,row.own and "cleanup" or "game_send",row.action,{id=row.id})
        end
    end
    probe.queue={} probe.head=1 probe.tail=0
end
local function release(s,reason)
    if probe.hold then event(s,"input","released",{reason=reason}) end
    probe.hold=false s.report.inputRestored=true
end
local function stopPending(s)
    if not s.remote then return end
    for id in pairs(s.pending) do
        probe.ownStop=true local ok=pcall(function() s.remote:FireServer("Stop",id) end) probe.ownStop=false
        if ok then s.report.cleanupStops=s.report.cleanupStops+1 end
    end
    s.pending={}
end
local function findStep(s)
    if type(getConnections)~="function" or type(getConstants)~="function" or type(getup)~="function" then return end
    local ok,list=pcall(getConnections,Run.RenderStepped)
    if not ok or type(list)~="table" then return end
    for i,c in ipairs(list) do
        if i>160 then break end
        local good,fn,foreign=pcall(function() return c.Function,c.ForeignState end)
        if good and not foreign and type(fn)=="function" and not own[fn] then
            local source="" local cached=probe.stepHooks[fn]
            if cached then source=cached.source
            elseif type(getfenv)=="function" then pcall(function() local e=getfenv(fn) local script=rawget(e,"script") if typeof(script)=="Instance" then source=path(script) end end) end
            if source:match("PlayerScripts%..*%.DebrisMagnet$") then
                local read,constants=pcall(getConstants,fn) local marks={}
                if read and type(constants)=="table" then for _,x in pairs(constants) do if type(x)=="string" then marks[x]=true end end end
                local v=values(fn) local hasPlayer,hasHud=false,false
                if v then for _,x in pairs(v) do if x==player then hasPlayer=true end if typeof(x)=="Instance" and x.Name=="DebrisHUD" then hasHud=true end end end
                if cached or (v and hasPlayer and hasHud and marks.DebrisMagnet and marks.GetMagnetStrength and marks.GetPullCount and marks.Progress) then
                    s.step={fn=fn,source=source} probe.step=fn
                    s.report.liveStep={source=source,actualConnection=true}
                    local names={}
                    for key in pairs(marks) do if #names<150 then names[#names+1]=key end end table.sort(names)
                    s.report.inputConstants=cached and cached.inputConstants or names
                    s.scopeReady=gateStep(s) hookQueries(s) return
                end
            end
        end
    end
end

local function overDebug(input)
    local p=input.Position if not p then return false end
    local ok,list=pcall(function() return pg:GetGuiObjectsAtPosition(p.X,p.Y) end)
    if ok then for _,obj in ipairs(list) do if obj==gui or obj:IsDescendantOf(gui) then return true end end end
    return false
end
local function onBegin(s,input,processed)
    local kind=input.UserInputType
    if not valid(s) or processed or overDebug(input) or (kind~=Enum.UserInputType.Touch and kind~=Enum.UserInputType.MouseButton1) then return end
    s.report.manualTouches=s.report.manualTouches+1 s.touches[input]=true
    event(s,"manual","begin",{})
end
local function onEnd(s,input)
    if not valid(s) or not s.touches[input] then return end
    s.touches[input]=nil s.lastManualEnd=os.clock() event(s,"manual","end",{})
end
local function tick(s)
    if not valid(s) then return end
    drain(s)
    local now=os.clock()
    local ready,full=hudState(s)
    if not s.step and now>=(s.nextDiscovery or 0) then s.nextDiscovery=now+1 findStep(s) end
    s.report.queryReads=probe.reads s.report.queryForced=probe.forced s.report.queryOverrides=probe.overrides s.report.stepCalls=probe.stepCalls
    if not ready or full then
        release(s,full and "mochila cheia" or "fora da area/ferramenta")
        if next(s.pending) then stopPending(s) end
        s.phase=full and "Mochila cheia: esvazie para continuar" or "Equipe o ima na area de coleta" return
    end
    if not s.step then s.phase="Procurando a rotina original do ima" return end
    if not s.scopeReady then release(s,"sem acesso a rotina") s.phase="Executor nao acessou a rotina; pare e copie o debug" return end
    probe.hold=true
    if probe.overrides==0 then
        if now-s.started>1 and (type(infoFn)=="function" or type(oldInfo)=="function") then probe.stackFallback=true s.report.stackFallback=true end
        s.phase=now-s.started<3 and "Ativando segurar pela consulta de entrada do ima" or "Nenhuma consulta de segurar interceptada; pare e copie o debug"
    elseif s.report.autonomousCaught>=2 then
        s.report.autonomousVerified=true s.phase="Auto Pull ativo: coletas sem toque confirmadas"
    else s.phase="Mantendo segurar; aponte para itens sem segurar a tela" end
end
local function receive(s,action,id,used,capacity)
    if not valid(s) then return end
    drain(s)
    if action=="Caught" and type(id)=="number" and not s.caughtIds[id] then
        s.caughtIds[id]=true s.report.caughtWhileEnabled=s.report.caughtWhileEnabled+1
        local pull=s.pending[id]
        local autonomous=pull and pull.clean and pull.manual==s.report.manualTouches and next(s.touches)==nil and probe.overrides>pull.overrides or false
        if autonomous then s.report.autonomousCaught=s.report.autonomousCaught+1 else s.report.assistedOrUnownedCaught=s.report.assistedOrUnownedCaught+1 end
        append(s.report.catches,{id=id,t=elapsed(s),seconds=pull and os.clock()-pull.started,used=used,capacity=capacity,autonomous=autonomous,manualTouches=s.report.manualTouches},12)
        s.pending[id]=nil event(s,"server","Caught",{id=id,used=used,capacity=capacity,autonomous=autonomous})
    elseif action=="Released" or action=="Refused" then
        if type(id)=="number" then s.pending[id]=nil end
        s.report[action]=(s.report[action] or 0)+1 event(s,"server",action,{id=id,used=used,capacity=capacity})
    end
end

copy=function()
    local r=active and active.report or lastReport
    if not r then label.Text="Ative Auto Pull para gerar o resultado." return end
    if active then r.seconds=elapsed(active) end
    local payload=Http:JSONEncode(r)
    env.MagnetDebugReport=payload env.MagnetReports={auto=payload}
    local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard
    local ok,value=false,nil if type(clip)=="function" then ok,value=pcall(clip,payload) end
    output.Text=payload output.Visible=not(ok and value~=false) label.Visible=not output.Visible
    if output.Visible then panel.Visible=true mini.Visible=false end
    return payload
end
stop=function(_,shouldCopy)
    local s=active if not s then if shouldCopy~=false then return copy() end return end
    drain(s) release(s,"OFF") stopPending(s) drain(s)
    s.running=false s.report.running=false s.report.seconds=elapsed(s) s.report.phase="OFF" s.report.dropped=probe.dropped
    active=nil lastReport=s.report probe.enabled=false probe.remote=nil disconnect(s.links)
    toggle.Text="Auto Pull: OFF" label.Text="Auto Pull parado. Resultado pronto."
    if shouldCopy~=false then return copy() end
end
start=function(mode)
    if not alive or active or (mode and mode~="auto") then return end
    local s={started=os.clock(),running=true,links={},pending={},caughtIds={},touches={},lastManualEnd=-math.huge,phase="Iniciando"}
    s.report={format="magnet-autopull-v4-input-query",mode="auto",placeId=game.PlaceId,running=true,
        note="Apenas Auto Pull: responde pressionado as consultas de entrada feitas pela rotina do ima. Sem ponteiro virtual, sem escrita de upvalues, sem Start/Catch direto. Coletas com ajuda manual sao separadas; confirmacao automatica exige duas coletas sem toque no ciclo.",
        capabilities={connections=type(getConnections)=="function",upvalues=type(getup)=="function",constants=type(getConstants)=="function",hookfunction=type(hookFn)=="function",screenInput=false},
        gameSent={Start=0,Catch=0,Stop=0},directSent={Start=0,Catch=0},holdWrites=0,cleanupStops=0,caughtWhileEnabled=0,autonomousCaught=0,assistedOrUnownedCaught=0,autonomousVerified=false,manualTouches=0,catches={},events={}}
    active=s lastReport=s.report
    s.report.device={}
    pcall(function() s.report.device.touchEnabled=UIS.TouchEnabled s.report.device.mouseEnabled=UIS.MouseEnabled end)
    pcall(function() s.report.device.lastInputType=tostring(UIS:GetLastInputType()) end)
    probe.enabled=false probe.queue={} probe.head=1 probe.tail=0 probe.dropped=0 probe.ownStop=false probe.hold=false probe.step=nil probe.originalStep=nil probe.gated=false probe.stackFallback=false probe.reads={} probe.forced={} probe.overrides=0 probe.stepCalls=0
    local folder=RS:FindFirstChild("Remotes") local remote=folder and folder:FindFirstChild("DebrisMagnet")
    if remote and remote:IsA("RemoteEvent") then s.remote=remote probe.remote=remote connect(remote.OnClientEvent,function(...) receive(s,...) end,s.links) end
    s.report.outgoingCapture=install() probe.enabled=s.report.outgoingCapture findStep(s)
    connect(UIS.InputBegan,function(input,processed) onBegin(s,input,processed) end,s.links)
    connect(UIS.InputEnded,function(input) onEnd(s,input) end,s.links)
    connect(Run.RenderStepped,function()
        if not valid(s) or s.failed then return end
        local ok,err=pcall(tick,s)
        if not ok then
            s.failed=true release(s,"erro") stopPending(s)
            s.report.error=tostring(err):sub(1,200) s.phase="Falha ao manter o toque; pare e copie o debug"
        end
        s.report.phase=s.phase
        if os.clock()>=(s.nextUi or 0) then s.nextUi=os.clock()+.12 label.Text=s.phase.."\nColetas sem toque: "..s.report.autonomousCaught end
    end,s.links)
    output.Visible=false label.Visible=true toggle.Text="Auto Pull: ON / parar e copiar"
end
close=function()
    if not alive then return end
    if active then stop(nil,true) end
    alive=false probe.enabled=false disconnect(lifetime) gui:Destroy()
end
env.MagnetDebug={Start=start,Stop=stop,Copy=copy,Close=close,GetReport=function() return active and active.report or lastReport end,GetActive=function() return active and "auto" end}
connect(toggle.Activated,function() if active then stop(nil,true) else start("auto") end end,lifetime)
connect(copyButton.Activated,copy,lifetime)
connect(exit.Activated,close,lifetime)
connect(minimize.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end,lifetime)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false end,lifetime)
local dragging,dragInput,inputStart,panelStart
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true dragInput=input.UserInputType==Enum.UserInputType.Touch and input or nil inputStart=input.Position panelStart=panel.Position
    end
end,lifetime)
connect(UIS.InputChanged,function(input)
    if dragging and ((dragInput and input==dragInput) or (not dragInput and input.UserInputType==Enum.UserInputType.MouseMovement)) then
        local delta=input.Position-inputStart local view=workspace.CurrentCamera.ViewportSize
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+delta.X,0,math.max(0,view.X-325)),math.clamp(panelStart.Y.Scale*view.Y+panelStart.Y.Offset+delta.Y,0,math.max(0,view.Y-216)))
    end
end,lifetime)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end,lifetime)
