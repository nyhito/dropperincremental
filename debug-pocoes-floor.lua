-- Auto Fish mobile: clique rapido fora do minigame; segurar/soltar seguindo o peixe.
-- Entrada de tela virtual autorizada. Mantem o nome e a janela do teste.
-- A frequencia real depende dos frames; nao altera a barra nem promete queda instantanea.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
for _,name in ipairs({"FishingDebug","FishingAutoTest"}) do
    if env[name] and type(env[name].Close)=="function" then pcall(env[name].Close) end
end
local fishing=RS:WaitForChild("Remotes"):FindFirstChild("Fishing")
assert(fishing and fishing:IsA("RemoteEvent"),"Fishing indisponivel.")
local alive,enabled=true,false
local links={}
local started=os.clock()
local phase,stage="OFF","idle"
local cycle,stateAt=0,os.clock()
local rodCache,uiCache=nil,nil
local castAt,biteAt,hookAt=nil,nil,nil
local interval=0.001
local lastClick,nextClick=-math.huge,0
local castCheckAt,attemptsSinceCheck=0,0
local completionSent,held=false,false
local inputEpoch,injecting=0,0
local activeInput=nil
local virtualInputAt=-math.huge
local virtualX,virtualY=nil,nil
local modes,modeIndex={},1
local modeFault,inputWorking=false,false
local autoOwned,manualAssisted=false,false
local geometry={}
local dropDebug=nil
local dropConnection=nil
local dragging=false
local autoButton=nil
local toggle,close,copy,setHeld,click,chooseMode
local startDropDebug,stopDropDebug
local report={format="fishing-controller-v7-fast-screen",placeId=game.PlaceId,
    note="Cliques virtuais rapidos sem minigame; durante a barra usa segurar/soltar. Caught recebido confirma captura. Frequencia limitada aos frames. Queda/mordida nao removidas.",
    caught=0,escaped=0,manualOrUnownedCaught=0,manualTouches=0,castsAccepted=0,bites=0,clicks=0,holdChanges=0,catchRequests=0,
    events={},catches={},inputErrors={},capabilities={},interval=interval}
local function connect(signal,fn)
    local c=signal:Connect(fn) links[#links+1]=c return c
end
local function now() return math.floor((os.clock()-started)*1000+.5)/1000 end
local function safe(v,depth,budget)
    budget.left=budget.left-1
    if budget.left<0 then return "[limit]" end
    local kind=typeof(v)
    if kind=="nil" then return {type="nil"} end
    if kind=="string" then return v:sub(1,140) end
    if kind=="boolean" then return v end
    if kind=="number" then return v==v and v~=math.huge and v~=-math.huge and v or tostring(v) end
    if kind=="Instance" then return {type=kind,path=v:GetFullName()} end
    if kind=="Vector3" then return {type=kind,x=v.X,y=v.Y,z=v.Z} end
    if kind=="table" and depth<2 then
        local out,n={},0
        for k,x in pairs(v) do n=n+1 if n>6 or budget.left<=0 then break end out[tostring(k)]=safe(x,depth+1,budget) end
        return out
    end
    return {type=kind,value=tostring(v):sub(1,140)}
end
local function record(kind,action,...)
    local e={t=now(),kind=kind,action=tostring(action):sub(1,90),cycle=cycle,stage=stage}
    local args=table.pack(...)
    if args.n>0 then e.args={} local b={left=18} for i=1,math.min(5,args.n) do e.args[tostring(i)]=safe(args[i],0,b) end end
    if dropDebug and dropDebug.running and #dropDebug.events<36 then
        if kind=="server" or tostring(action):find("Cast",1,true) or tostring(action):find("Hook",1,true) then
            dropDebug.events[#dropDebug.events+1]=e
        end
    end
    report.events[#report.events+1]=e
    if #report.events>32 then table.remove(report.events,1) end
end
local function rod()
    local c=player.Character
    if not c then return end
    local h=c:FindFirstChild("Humanoid") if h and h.Health<=0 then return end
    if rodCache and rodCache.Parent==c then return rodCache end
    local t=c:FindFirstChild("FishingRod")
    rodCache=t and t:IsA("Tool") and t or nil
    return rodCache
end
local function reelBar()
    if uiCache and uiCache.Parent then return uiCache end
    local pg=player:FindFirstChild("PlayerGui")
    local front=pg and pg:FindFirstChild("Front")
    local main=front and front:FindFirstChild("MainFrame")
    uiCache=main and main:FindFirstChild("ReelBar")
    return uiCache
end
local function progress()
    local bar=reelBar()
    local text=bar and bar:FindFirstChild("Percent")
    local value=text and tonumber(((text.Text:match("[%d.,]+") or ""):gsub(",",".")))
    return bar and bar.Visible or false,value
end
local clickPoint={x=nil,y=nil,at=-math.huge,vx=0,vy=0}
local pointBlocked=false
local function pointIsFree(x,y)
    local pg=player:FindFirstChild("PlayerGui")
    if not pg then return false end
    local ok,hits=pcall(function() return pg:GetGuiObjectsAtPosition(x,y) end)
    if not ok or type(hits)~="table" then return true end
    for _,obj in ipairs(hits) do
        local a=obj
        for _=1,10 do
            if not a or a==pg then break end
            if a:IsA("GuiButton") or a:IsA("TextBox") then return false end
            if a.Name=="FishingControllerTest" then return false end
            a=a.Parent
        end
    end
    return true
end
local function position()
    local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000,700)
    if os.clock()-clickPoint.at<.35 and view.X==clickPoint.vx and view.Y==clickPoint.vy then
        return clickPoint.x,clickPoint.y
    end
    clickPoint.at=os.clock() clickPoint.vx=view.X clickPoint.vy=view.Y
    clickPoint.x,clickPoint.y=nil,nil
    for _,point in ipairs({{.78,.30},{.65,.36},{.53,.34},{.42,.38},{.78,.47},{.6,.48},{.52,.21},{.42,.23}}) do
        local x,y=math.floor(view.X*point[1]),math.floor(view.Y*point[2])
        if pointIsFree(x,y) then clickPoint.x=x clickPoint.y=y break end
    end
    return clickPoint.x,clickPoint.y
end
local function inputError(message)
    modeFault=true
    report.inputErrors[#report.inputErrors+1]={t=now(),mode=modes[modeIndex] and modes[modeIndex].name,error=tostring(message):sub(1,230)}
    if #report.inputErrors>6 then table.remove(report.inputErrors,1) end
end
local function refreshModes()
    modes={} modeIndex=1 modeFault=false
    local virtual
    pcall(function() virtual=game:GetService("VirtualInputManager") end)
    if virtual then
        modes[#modes+1]={name="VirtualInput / clique na tela",press=function(down)
            local point=activeInput
            if not point then return end
            virtualInputAt=os.clock() virtualX=point.x virtualY=point.y
            virtual:SendMouseButtonEvent(point.x,point.y,0,down,game,0)
        end}
    end
    local press=mouse1press or env.mouse1press
    local unpress=mouse1release or env.mouse1release
    if type(press)=="function" and type(unpress)=="function" then
        modes[#modes+1]={name="Executor / pressionar e soltar",press=function(down)
            virtualInputAt=os.clock()
            if down then press() else unpress() end
        end}
    end
    report.capabilities={screenInput=true,virtualInput=virtual~=nil,executorMouse=type(press)=="function" and type(unpress)=="function",inputModes=#modes}
end
setHeld=function(down,force)
    if down and (not alive or not enabled) then return false end
    if held==down and not force then return true end
    local mode=modes[modeIndex]
    if not mode then return false end
    if down then
        local x,y=position()
        if not x then pointBlocked=true return false end
        pointBlocked=false activeInput={x=x,y=y}
    end
    -- Marca antes do evento: Cast/Hook podem retornar durante o proprio callback.
    held=down
    injecting=injecting+1
    local ok,err=pcall(mode.press,down)
    injecting=injecting-1
    if not ok then
        held=false
        if down then pcall(mode.press,false) end
        inputError(err) return false
    end
    report.holdChanges=report.holdChanges+1 report.inputMode=mode.name
    if not down then activeInput=nil end
    return true
end
local function release()
    inputEpoch=inputEpoch+1
    if held then setHeld(false,true) end
    held=false activeInput=nil
end
chooseMode=function(reason)
    release() record("input","Switch",reason)
    modeIndex=modeIndex+1
    if modeIndex>#modes then
        enabled=false phase="Clique virtual indisponivel. Copie o resultado."
        if autoButton then autoButton.Text="Auto Fish: OFF" end
        return false
    end
    modeFault=false inputWorking=false castCheckAt=os.clock() attemptsSinceCheck=0
    report.inputMode=modes[modeIndex].name
    return true
end
click=function(reason)
    if not alive or not enabled then return false end
    local shown=progress()
    if shown then return false end -- Nunca mistura spam com o controle da barra.
    local x=position()
    if not x then release() phase="Ponto de clique coberto pela interface" return false end
    release()
    lastClick=os.clock() nextClick=lastClick+interval
    if not setHeld(true) then return false end
    report.clicks=report.clicks+1 attemptsSinceCheck=attemptsSinceCheck+1
    if reason then record("input",reason) end
    local epoch=inputEpoch
    -- Pulso curto, sem espera bloqueante. O proximo frame pode emitir outro clique.
    task.delay(.001,function() if alive and epoch==inputEpoch then release() end end)
    return true
end
-- Painel de teste independente: ligado/desligado, intervalo e resultado para retorno.
local gui=Instance.new("ScreenGui") gui.Name="FishingControllerTest" gui.ResetOnSpawn=false gui.DisplayOrder=10031
 gui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(312,262) panel.Position=UDim2.new(0,12,0.15,0)
 panel.BackgroundColor3=Color3.fromRGB(21,23,30) panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,9)
local function button(text,x,y,w,h)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.Gotham b.TextSize=13
    b.TextColor3=Color3.new(1,1,1) b.BackgroundColor3=Color3.fromRGB(66,49,110)
    b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(w,h) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="AUTO FISH / CLIQUE RAPIDO" title.Font=Enum.Font.GothamBold title.TextSize=13
 title.TextColor3=Color3.new(1,1,1) title.BackgroundTransparency=1 title.Active=true
 title.Position=UDim2.fromOffset(10,3) title.Size=UDim2.fromOffset(224,30) title.Parent=panel
local minimize=button("-",242,6,26,26) local exit=button("X",276,6,26,26)
autoButton=button("Auto Fish: OFF",10,42,292,36)
local intervalLabel=Instance.new("TextLabel") intervalLabel.Text="Intervalo dos cliques (s)" intervalLabel.Font=Enum.Font.Gotham intervalLabel.TextSize=12
 intervalLabel.TextColor3=Color3.new(1,1,1) intervalLabel.BackgroundTransparency=1
 intervalLabel.Position=UDim2.fromOffset(10,85) intervalLabel.Size=UDim2.fromOffset(190,30) intervalLabel.Parent=panel
local intervalBox=Instance.new("TextBox") intervalBox.Text="0.001" intervalBox.ClearTextOnFocus=false intervalBox.Font=Enum.Font.Code intervalBox.TextSize=13
 intervalBox.TextColor3=Color3.new(1,1,1) intervalBox.BackgroundColor3=Color3.fromRGB(35,37,46)
 intervalBox.Position=UDim2.fromOffset(206,85) intervalBox.Size=UDim2.fromOffset(96,30) intervalBox.Parent=panel
local copyButton=button("Copiar resultado",10,123,292,31)
local dropButton=button("Debug queda (12 s)",10,161,292,31)
local label=Instance.new("TextLabel") label.Text="Chegue perto do lago e ative."
 label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top
 label.Font=Enum.Font.Gotham label.TextSize=12 label.TextColor3=Color3.new(1,1,1) label.BackgroundTransparency=1
 label.Position=UDim2.fromOffset(10,200) label.Size=UDim2.fromOffset(292,53) label.Parent=panel
local mini=Instance.new("TextButton") mini.Text="PESCA" mini.Font=Enum.Font.GothamBold mini.TextSize=12
 mini.TextColor3=Color3.new(1,1,1) mini.BackgroundColor3=Color3.fromRGB(66,49,110)
 mini.Position=panel.Position mini.Size=UDim2.fromOffset(70,38) mini.Visible=false mini.Parent=gui
Instance.new("UICorner",mini).CornerRadius=UDim.new(0,8)
local output=Instance.new("TextBox") output.Text="" output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false
 output.Font=Enum.Font.Code output.TextSize=10 output.TextColor3=Color3.new(1,1,1) output.BackgroundColor3=Color3.fromRGB(29,31,39)
 output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top
 output.Position=UDim2.fromOffset(0,268) output.Size=UDim2.fromOffset(312,135) output.Visible=false output.Parent=panel
-- Debug opcional de 12 s: observa bobber e eventos, sem alterar a animacao.
stopDropDebug=function(shouldCopy)
    if not dropDebug or not dropDebug.running then return end
    dropDebug.running=false dropDebug.seconds=now()-dropDebug.started
    if dropConnection then dropConnection:Disconnect() dropConnection=nil end
    dropButton.Text="Debug queda (12 s)"
    if shouldCopy and copy then copy() end
end
startDropDebug=function()
    if not alive or (dropDebug and dropDebug.running) then return end
    local d={running=true,started=now(),events={},parts={},readOnly=true}
    dropDebug=d report.dropDebug=d dropButton.Text="Parar debug / copiar"
    local physical={}
    local function watch(obj)
        if not obj:IsA("BasePart") then return end
        for _,entry in ipairs(physical) do if entry.obj==obj then return end end
        local parent=obj.Parent
        local related=obj.Name:lower():find("bobber",1,true) or (parent and parent.Name:lower():find("bobber",1,true))
        if not related or #physical>=6 then return end
        local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root and (obj.Position-root.Position).Magnitude>100 then return end
        local data={path=obj:GetFullName(),class=obj.ClassName,samples={}}
        physical[#physical+1]={obj=obj,data=data} d.parts[#d.parts+1]=data
    end
    local bobber=workspace:FindFirstChild("Bobber")
    if bobber then watch(bobber) for _,obj in ipairs(bobber:GetDescendants()) do watch(obj) end end
    dropConnection=workspace.DescendantAdded:Connect(function(obj) if d.running then watch(obj) end end)
    task.spawn(function()
        while alive and d.running and now()-d.started<12 do
            for _,entry in ipairs(physical) do
                if entry.obj.Parent and #entry.data.samples<125 then
                    local p=entry.obj.Position
                    entry.data.samples[#entry.data.samples+1]={t=now()-d.started,x=p.X,y=p.Y,z=p.Z}
                end
            end
            task.wait(.1)
        end
        if alive and d.running then stopDropDebug(true) end
    end)
end
local function resetCycle(reason)
    release()
    cycle=cycle+1 stage="idle" stateAt=os.clock() castAt=nil biteAt=nil hookAt=nil
    autoOwned=false manualAssisted=false completionSent=false geometry={}
    nextClick=0 phase=reason or "Aguardando"
end
local function controlBar(dt)
    local bar=reelBar()
    local track=bar and bar:FindFirstChild("Track")
    local lane=track and track:FindFirstChild("Lane")
    local zone=lane and lane:FindFirstChild("Zone")
    local fish=lane and lane:FindFirstChild("Fish")
    if not lane or not zone or not fish or lane.AbsoluteSize.X<=0 or zone.AbsoluteSize.X<=0 then
        phase="Aguardando os elementos da barra"
        return
    end
    local left,width=lane.AbsolutePosition.X,lane.AbsoluteSize.X
    local zx=(zone.AbsolutePosition.X+zone.AbsoluteSize.X*.5-left)/width
    local fx=(fish.AbsolutePosition.X+fish.AbsoluteSize.X*.5-left)/width
    local zw=zone.AbsoluteSize.X/width
    dt=math.clamp(dt or 1/60,.004,.08)
    local g=geometry
    local zv=g.zone and (zx-g.zone)/dt or 0
    local fv=g.fish and (fx-g.fish)/dt or 0
    g.zv=(g.zv or 0)*.55+math.clamp(zv,-4,4)*.45
    g.fv=(g.fv or 0)*.7+math.clamp(fv,-4,4)*.3
    local target=math.clamp(fx+g.fv*.035,0,1)
    local projected=zx+g.zv*.045
    local error=target-projected
    local dead=math.clamp(zw*.045,.003,.014)
    local desired=held
    if error>dead then desired=true elseif error< -dead then desired=false end
    if not setHeld(desired) then
        if pointBlocked then phase="Ponto de clique coberto pela interface" g.lastMove=os.clock()
        elseif chooseMode("Segurar/soltar recusado") then setHeld(desired,true) end
    end
    if g.zone and math.abs(zx-g.zone)>.001 then
        g.lastMove=os.clock() inputWorking=true
    end
    g.lastMove=g.lastMove or os.clock()
    g.zone,g.fish,g.width=zx,fx,zw
    g.error=error g.inside=math.abs(fx-zx)<=zw*.5
    local _,percent=progress()
    if percent then g.peak=math.max(g.peak or 0,percent) if percent<99 then g.sawBelowFull=true end end
    if not g.inside and os.clock()-g.lastMove>.65 then
        chooseMode("Barra nao respondeu ao segurar/soltar")
        g.lastMove=os.clock()
    end
    report.controller={t=now(),fish=fx,zone=zx,width=zw,held=held,inside=g.inside,peak=g.peak,inputWorking=inputWorking}
end
local function onServer(action,...)
    if not alive then return end
    if enabled or (dropDebug and dropDebug.running) then record("server",action,...) end
    if not enabled then return end
    local args=table.pack(...)
    if action=="Cast" then
        if os.clock()-lastClick<2 and autoOwned then
            stage="waitingBite" stateAt=os.clock()
            castAt=castAt or os.clock() inputWorking=true castCheckAt=os.clock()
            report.castsAccepted=report.castsAccepted+1
            phase="Lancou; clicando ate fisgar"
        end
    elseif action=="Bite" then
        report.bites=report.bites+1 biteAt=os.clock()
        if autoOwned then
            stage="hooking" stateAt=os.clock() phase="Fisgando"
            hookAt=os.clock() click("Hook no !")
        end
    elseif action=="Caught" then
        if autoOwned and not manualAssisted and geometry.sawBelowFull then
            report.caught=report.caught+1
            report.catches[#report.catches+1]={t=now(),fish=safe(args[1],0,{left=8}),value2=safe(args[2],0,{left=8}),
                value3=safe(args[3],0,{left=8}),autoFlag=args[4],seconds=castAt and os.clock()-castAt,
                localPeak=geometry.peak,mode=modes[modeIndex] and modes[modeIndex].name}
            if #report.catches>8 then table.remove(report.catches,1) end
        else report.manualOrUnownedCaught=report.manualOrUnownedCaught+1 end
        resetCycle("Captura confirmada; relancando")
        castCheckAt=os.clock() attemptsSinceCheck=0
    elseif action=="Escaped" then
        report.escaped=report.escaped+1 resetCycle("Peixe escapou; relancando")
        castCheckAt=os.clock() attemptsSinceCheck=0
    end
end
connect(fishing.OnClientEvent,onServer)
connect(UIS.InputBegan,function(input,processed)
    if injecting>0 or not enabled or processed or not autoOwned then return end
    if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    if input.UserInputType==Enum.UserInputType.MouseButton1 and os.clock()-virtualInputAt<.12 then
        local p=input.Position
        if not p or not virtualX or (math.abs(p.X-virtualX)<=8 and math.abs(p.Y-virtualY)<=8) then return end
    end
    manualAssisted=true report.manualTouches=report.manualTouches+1
end)
toggle=function(value)
    if not alive then return end
    if value==nil then value=not enabled end
    release() enabled=value==true resetCycle(enabled and "Chegue perto do lago" or "OFF")
    if enabled then
        refreshModes() castCheckAt=os.clock() attemptsSinceCheck=0
        if #modes==0 then enabled=false phase="Executor sem clique virtual. Copie o resultado."
        elseif rod() then phase="Clicando rapido para lancar"
        else phase="Auto ligado; aproxime-se do lago para equipar a vara" end
    end
    autoButton.Text=enabled and "Auto Fish: ON" or "Auto Fish: OFF"
end
copy=function()
    report.enabled=enabled report.phase=phase report.stage=stage report.seconds=now() report.interval=interval
    report.hasRod=rod()~=nil
    local shown,n=progress() report.ui={barVisible=shown,percent=n}
    local export={} for k,v in pairs(report) do export[k]=v end
    local payload=Http:JSONEncode(export)
    if #payload>18000 and dropDebug then
        local d={} for k,v in pairs(dropDebug) do if k~="parts" then d[k]=v end end d.parts={}
        for _,part in ipairs(dropDebug.parts) do
            local samples={}
            for i,sample in ipairs(part.samples) do if i<=3 or i>#part.samples-6 then samples[#samples+1]=sample end end
            d.parts[#d.parts+1]={path=part.path,class=part.class,samples=samples}
        end
        export.dropDebug=d export.trimmed=true payload=Http:JSONEncode(export)
    end
    env.FishingAutoTestReport=payload
    local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard
    local ok,result=false,nil
    if type(clip)=="function" then ok,result=pcall(clip,payload) end
    output.Text=payload output.Visible=not (ok and result~=false)
    if output.Visible then panel.Visible=true mini.Visible=false end
    return payload
end
close=function()
    if not alive then return end
    if dropDebug and dropDebug.running then stopDropDebug(false) end
    toggle(false) alive=false
    for _,c in ipairs(links) do c:Disconnect() end
    gui:Destroy()
end
env.FishingAutoTest={Toggle=toggle,Copy=copy,Close=close,Report=report,StartDropDebug=function() startDropDebug() end,StopDropDebug=function() stopDropDebug(true) end}
connect(autoButton.Activated,function() toggle() end)
connect(copyButton.Activated,copy)
connect(dropButton.Activated,function() if dropDebug and dropDebug.running then stopDropDebug(true) else startDropDebug() end end)
connect(exit.Activated,close)
connect(minimize.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true clickPoint.at=-math.huge end)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false clickPoint.at=-math.huge end)
connect(intervalBox.FocusLost,function()
    local n=tonumber((intervalBox.Text:gsub(",",".")))
    if n and n==n then interval=math.clamp(n,.001,3) end
    intervalBox.Text=tostring(interval) report.interval=interval
end)
local lastRod=nil
local function finishCatch()
    local shown,n=progress()
    if shown and (not n or n<99.95) then return end
    if not completionSent and geometry.sawBelowFull and (geometry.peak or 0)>=99.95 and os.clock()-stateAt>.2 then
        completionSent=true report.catchRequests=report.catchRequests+1 record("send","Catch after 100%")
        fishing:FireServer("Catch")
    end
end
local function step(dt)
    if not alive or not enabled then return end
    local tool=rod()
    if not tool then
        if autoOwned or held then resetCycle("Aguardando vara perto do lago") end
        lastRod=nil castCheckAt=os.clock() attemptsSinceCheck=0
        phase="Aguardando vara perto do lago" return
    end
    local focused=nil pcall(function() focused=UIS:GetFocusedTextBox() end)
    if focused or dragging then release() phase="Pausado enquanto voce usa o painel" castCheckAt=os.clock() return end
    if tool~=lastRod then release() lastRod=tool castCheckAt=os.clock() attemptsSinceCheck=0 end
    if modeFault then if not chooseMode("Falha no clique virtual") then return end end
    local shown,n=progress()
    if shown then
        if stage~="reeling" and stage~="waitingCaught" then
            -- Cancela a soltura atrasada de um clique antes de segurar a barra.
            release() stage="reeling" stateAt=os.clock() geometry={} completionSent=false
            phase="Seguindo o peixe automaticamente"
        end
        if stage=="reeling" then
            if n and n>=99.95 and geometry.sawBelowFull then
                geometry.peak=n stage="waitingCaught" stateAt=os.clock() phase="100%; aguardando captura"
                controlBar(dt)
            else controlBar(dt) end
        elseif stage=="waitingCaught" then
            phase="100%; aguardando captura"
            controlBar(dt)
            if n and n<99 then stage="reeling" stateAt=os.clock() completionSent=false
            else finishCatch() end
        end
        return -- NENHUM clique de spam enquanto a barra estiver visivel.
    end
    if stage=="reeling" then
        release() stage="waitingCaught" stateAt=os.clock()
    end
    if stage=="waitingCaught" then
        finishCatch()
        if os.clock()-stateAt>3 then resetCycle("Sem confirmacao; relancando") end
    end
    if stage=="idle" then
        cycle=cycle+1 autoOwned=true manualAssisted=false stage="casting" stateAt=os.clock() castAt=os.clock()
        geometry={} completionSent=false phase="Clicando rapido para lancar"
    end
    -- Fora da barra, continua clicando inclusive durante queda, espera do ! e relancamento.
    if os.clock()>=nextClick then click() end
    if stage=="casting" and os.clock()-castCheckAt>4 and attemptsSinceCheck>10 then
        chooseMode("Nenhum lancamento confirmado pelo servidor")
    elseif stage=="waitingBite" then
        phase="Clicando rapido; aguardando !"
        if os.clock()-stateAt>12 then resetCycle("Sem mordida; tentando relancar") end
    elseif stage=="hooking" and os.clock()-stateAt>3 then
        resetCycle("Sem barra; tentando relancar")
    end
end
connect(Run.RenderStepped,function(dt)
    if not enabled then return end
    local ok,err=pcall(step,dt)
    if not ok then report.error=tostring(err) toggle(false) phase="Erro. Copie o resultado." end
    if not enabled then autoButton.Text="Auto Fish: OFF" end
end)
local dragInput,inputStart,panelStart
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true dragInput=input.UserInputType==Enum.UserInputType.Touch and input or nil
        inputStart=input.Position panelStart=panel.Position
    end
end)
connect(UIS.InputChanged,function(input)
    if not dragging then return end
    if (dragInput and input==dragInput) or (not dragInput and input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-inputStart
        local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000,700)
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+delta.X,0,math.max(0,view.X-312)),
            math.clamp(panelStart.Y.Scale*view.Y+panelStart.Y.Offset+delta.Y,0,math.max(0,view.Y-262)))
    end
end)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
task.spawn(function()
    while alive do label.Text=phase task.wait(.2) end
end)
print("Teste de pesca por clique e controle de barra pronto. Inicia OFF.")
