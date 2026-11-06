-- Teste separado de AUTO FISH DIRETO. Nome preservado para o mesmo loadstring.
-- Protocolo observado: Fishing:FireServer("Cast"), ("Hook"), ("Catch").
-- So conta uma captura quando recebe Fishing.OnClientEvent("Caught", ...).
-- Nao altera a barra nem inventa progresso local. Nao modifica o hub.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
for _,name in ipairs({"FishingDebug","FishingAutoTest"}) do
    if env[name] and type(env[name].Close)=="function" then pcall(env[name].Close) end
end
local remotes=RS:WaitForChild("Remotes")
local fishing=remotes:FindFirstChild("Fishing")
assert(fishing and fishing:IsA("RemoteEvent"),"RemoteEvent Fishing indisponivel.")
local alive,enabled=true,false
local links={}
local active=false
local cycle=0
local phase="OFF"
local castAt,ackAt,biteAt,hookAt=nil,nil,nil,nil
local lastSend={Cast=-math.huge,Hook=-math.huge,Catch=-math.huge}
local attemptInterval=.05
local currentUI=nil
local barWasVisible=false
local sentCatchWithoutFull=false
local caughtThisCycle=false
local adoptCurrent=false
local adoptedMinigame=false
local toggle,close,copy
local started=os.clock()
local report={format="fishing-direct-test-v1",placeId=game.PlaceId,
    note="Somente Caught recebido do servidor conta. Ausencia da barra local nao prova que todos os limites do servidor foram ignorados.",
    sent={Cast=0,Hook=0,Catch=0},caught=0,catches={},events={},timeouts=0,interval=.05}
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
        for k,x in pairs(v) do
            n=n+1 if n>6 or budget.left<=0 then break end
            out[tostring(k)]=safe(x,depth+1,budget)
        end
        return out
    end
    return {type=kind,value=tostring(v):sub(1,140)}
end
local function record(kind,action,...)
    local event={t=now(),kind=kind,action=tostring(action):sub(1,80),cycle=cycle}
    local args=table.pack(...)
    if args.n>0 then
        event.args={} local budget={left=18}
        for i=1,math.min(args.n,5) do event.args[tostring(i)]=safe(args[i],0,budget) end
    end
    report.events[#report.events+1]=event
    if #report.events>36 then table.remove(report.events,1) end
end
local function rod()
    local c=player.Character
    if not c then return end
    local h=c:FindFirstChild("Humanoid")
    if h and h.Health<=0 then return end
    local tool=c:FindFirstChild("FishingRod")
    if tool and tool:IsA("Tool") then return tool end
end
local function reelBar()
    if currentUI and currentUI.Parent then return currentUI end
    local pg=player:WaitForChild("PlayerGui")
    local front=pg:FindFirstChild("Front")
    local main=front and front:FindFirstChild("MainFrame")
    currentUI=main and main:FindFirstChild("ReelBar")
    return currentUI
end
local function uiProgress()
    local bar=reelBar()
    local shown=bar and bar.Visible or false
    local percent=bar and bar:FindFirstChild("Percent")
    local text=percent and percent.Text
    local n=text and tonumber(((text:match("[%d.,]+") or ""):gsub(",",".")))
    return shown,n,text
end
-- Painel de teste independente: ligado/desligado, intervalo e resultado para retorno.
local gui=Instance.new("ScreenGui") gui.Name="FishingDirectTest" gui.ResetOnSpawn=false gui.DisplayOrder=10031
 gui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(312,224) panel.Position=UDim2.new(0,12,0.15,0)
 panel.BackgroundColor3=Color3.fromRGB(21,23,30) panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,9)
local function button(text,x,y,w,h)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.Gotham b.TextSize=13
    b.TextColor3=Color3.new(1,1,1) b.BackgroundColor3=Color3.fromRGB(66,49,110)
    b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(w,h) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="AUTO FISH / TESTE DIRETO" title.Font=Enum.Font.GothamBold title.TextSize=13
 title.TextColor3=Color3.new(1,1,1) title.BackgroundTransparency=1 title.Active=true
 title.Position=UDim2.fromOffset(10,3) title.Size=UDim2.fromOffset(224,30) title.Parent=panel
local minimize=button("-",242,6,26,26) local exit=button("X",276,6,26,26)
local autoButton=button("Auto Fish: OFF",10,42,292,36)
local intervalLabel=Instance.new("TextLabel") intervalLabel.Text="Tentativas (segundos)" intervalLabel.Font=Enum.Font.Gotham intervalLabel.TextSize=12
 intervalLabel.TextColor3=Color3.new(1,1,1) intervalLabel.BackgroundTransparency=1
 intervalLabel.Position=UDim2.fromOffset(10,85) intervalLabel.Size=UDim2.fromOffset(190,30) intervalLabel.Parent=panel
local intervalBox=Instance.new("TextBox") intervalBox.Text="0.05" intervalBox.ClearTextOnFocus=false intervalBox.Font=Enum.Font.Code intervalBox.TextSize=13
 intervalBox.TextColor3=Color3.new(1,1,1) intervalBox.BackgroundColor3=Color3.fromRGB(35,37,46)
 intervalBox.Position=UDim2.fromOffset(206,85) intervalBox.Size=UDim2.fromOffset(96,30) intervalBox.Parent=panel
local copyButton=button("Copiar resultado",10,123,292,31)
local label=Instance.new("TextLabel") label.Text="Chegue perto do lago e ative."
 label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top
 label.Font=Enum.Font.Gotham label.TextSize=12 label.TextColor3=Color3.new(1,1,1) label.BackgroundTransparency=1
 label.Position=UDim2.fromOffset(10,164) label.Size=UDim2.fromOffset(292,53) label.Parent=panel
local mini=Instance.new("TextButton") mini.Text="PESCA" mini.Font=Enum.Font.GothamBold mini.TextSize=12
 mini.TextColor3=Color3.new(1,1,1) mini.BackgroundColor3=Color3.fromRGB(66,49,110)
 mini.Position=panel.Position mini.Size=UDim2.fromOffset(70,38) mini.Visible=false mini.Parent=gui
Instance.new("UICorner",mini).CornerRadius=UDim.new(0,8)
local output=Instance.new("TextBox") output.Text="" output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false
 output.Font=Enum.Font.Code output.TextSize=10 output.TextColor3=Color3.new(1,1,1) output.BackgroundColor3=Color3.fromRGB(29,31,39)
 output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top
 output.Position=UDim2.fromOffset(0,230) output.Size=UDim2.fromOffset(312,135) output.Visible=false output.Parent=panel
local function invalidate(reason)
    active=false cycle=cycle+1
    castAt,ackAt,biteAt,hookAt=nil,nil,nil,nil
    barWasVisible=false caughtThisCycle=false sentCatchWithoutFull=false
    phase=reason or "OFF"
end
local function send(action,force)
    if not alive or not enabled or not active or not rod() then return false end
    if not force and os.clock()-lastSend[action]<attemptInterval then return false end
    lastSend[action]=os.clock()
    report.sent[action]=report.sent[action]+1
    -- Guarda somente envios de transicao; repeticoes sao contadas sem inflar o relatorio.
    if action=="Cast" or (action=="Hook" and not hookAt) then record("send",action) end
    if action=="Hook" and not hookAt then hookAt=os.clock() end
    if action=="Catch" then
        local shown,n=uiProgress()
        if not shown or not n or n<100 then sentCatchWithoutFull=true end
        report.lastCatchRequest={t=now(),cycle=cycle,barVisible=shown,percent=n}
    end
    fishing:FireServer(action)
    return true
end
local function attempt(force)
    if not active then return end
    local id=cycle
    local shown=uiProgress()
    phase=shown and "Solicitando captura sem esperar a barra" or "Tentando fisgar e capturar cedo"
    -- A barra do peixe anterior pode demorar a sumir. Ela nao bloqueia a nova fisgada.
    -- Hook so e dispensado quando adotamos um minigame manual ja em andamento.
    if not adoptedMinigame and (not hookAt or (force and biteAt and biteAt>lastSend.Hook)) then
        send("Hook",true)
    end
    if cycle==id and active then send("Catch",force) end
end
local function beginCast()
    if not rod() or not enabled or not alive then return end
    cycle=cycle+1 active=true caughtThisCycle=false sentCatchWithoutFull=false barWasVisible=false
    castAt=os.clock() ackAt=nil biteAt=nil hookAt=nil
    lastSend.Hook,lastSend.Catch=-math.huge,-math.huge
    phase="Lancando direto"
    local shown=uiProgress()
    adoptedMinigame=adoptCurrent and shown
    adoptCurrent=false barWasVisible=shown
    if adoptedMinigame then
        ackAt=os.clock() phase="Tentando finalizar o minigame atual" attempt(true)
    else send("Cast",true) end
end
connect(fishing.OnClientEvent,function(action,...)
    if not alive or not enabled then return end
    local args=table.pack(...)
    record("server",action,...)
    if not active or caughtThisCycle then return end
    if action=="Cast" then
        ackAt=ackAt or os.clock()
        -- O servidor aceitou o lancamento. Nao espera animacao local ou barra aparecer.
        attempt(false)
    elseif action=="Bite" then
        biteAt=os.clock()
        -- Se a fisgada antecipada foi ignorada, a mordida provoca nova tentativa imediata.
        attempt(true)
    elseif action=="Caught" then
        caughtThisCycle=true
        local elapsed=castAt and os.clock()-castAt or nil
        local hookElapsed=hookAt and os.clock()-hookAt or nil
        report.caught=report.caught+1
        local result={t=now(),fish=safe(args[1],0,{left=8}),value2=safe(args[2],0,{left=8}),
            value3=safe(args[3],0,{left=8}),autoFlag=args[4],seconds=elapsed,afterHook=hookElapsed,
            attemptedBeforeLocalFull=sentCatchWithoutFull}
        report.catches[#report.catches+1]=result
        if #report.catches>8 then table.remove(report.catches,1) end
        active=false phase="Captura confirmada; relancando"
    end
end)
toggle=function(value)
    if not alive then return end
    if value==nil then value=not enabled end
    enabled=value==true
    adoptCurrent=enabled
    invalidate(enabled and "Aguardando vara perto do lago" or "OFF")
    autoButton.Text=enabled and "Auto Fish: ON" or "Auto Fish: OFF"
end
copy=function()
    report.phase=phase report.enabled=enabled report.interval=attemptInterval report.seconds=now()
    local shown,n,text=uiProgress()
    report.ui={barVisible=shown,percent=n,text=text}
    report.hasRod=rod()~=nil
    local payload=Http:JSONEncode(report)
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
    toggle(false) alive=false
    for _,c in ipairs(links) do c:Disconnect() end
    gui:Destroy()
end
env.FishingAutoTest={Toggle=toggle,Copy=copy,Close=close,Report=report}
connect(autoButton.Activated,function() toggle() end)
connect(copyButton.Activated,copy)
connect(exit.Activated,close)
connect(minimize.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false end)
connect(intervalBox.FocusLost,function()
    local n=tonumber((intervalBox.Text:gsub(",",".")))
    if n and n==n then attemptInterval=math.clamp(n,.02,1) end
    intervalBox.Text=tostring(attemptInterval)
end)
local dragging,dragInput,inputStart,panelStart
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
            math.clamp(panelStart.Y.Scale*view.Y+panelStart.Y.Offset+delta.Y,0,math.max(0,view.Y-224)))
    end
end)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
task.spawn(function()
    while alive do
        if enabled then
            local ok,err=pcall(function()
                if not rod() then
                    if active then invalidate("Aguardando vara perto do lago") end
                    phase="Aguardando vara perto do lago"
                elseif not active then
                    if os.clock()-lastSend.Cast>=.03 then beginCast() end
                else
                    local shown=uiProgress()
                    if shown and not barWasVisible then
                        barWasVisible=true attempt(true)
                    elseif ackAt or biteAt or shown then
                        attempt(false)
                    elseif os.clock()-lastSend.Cast>=1 and os.clock()-castAt<4 then
                        send("Cast",true)
                    end
                    if active and os.clock()-castAt>=8 then
                        report.timeouts=report.timeouts+1
                        record("timeout","NoCaught",{seconds=os.clock()-castAt,barVisible=shown})
                        toggle(false)
                        phase="Sem Caught em 8 s. Copie o resultado para ajustar."
                    end
                end
            end)
            if not ok then
                report.error=tostring(err) toggle(false) phase="Erro. Copie o resultado."
            end
        end
        task.wait(.02)
    end
end)
task.spawn(function()
    while alive do
        label.Text=phase
        task.wait(.15)
    end
end)
print("Teste de Auto Fish direto pronto. Inicia OFF; aproxime-se do lago e ative.")
