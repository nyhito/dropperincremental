-- Neto Hub / Obsidian UI
-- UI: https://github.com/deividcomsono/Obsidian
-- Docs: https://docs.mspaint.cc/obsidian
-- Seis funcoes. Todos os autos iniciam desligados.
-- Nao instala hooks globais. Intervalos abaixo de um frame dependem do Roblox.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Prompts=game:GetService("ProximityPromptService")
local player=Players.LocalPlayer
assert(player,"Execute no cliente do Roblox.")
assert(game.PlaceId==70960300100792,"Neto Hub: jogo diferente do configurado.")
assert(type(loadstring)=="function","O executor precisa oferecer loadstring.")
local env=(type(getgenv)=="function" and getgenv()) or _G
if type(env.NetoHubCleanup)=="function" then pcall(env.NetoHubCleanup) end

local rootList={player:WaitForChild("PlayerGui"),workspace}
pcall(function() rootList[#rootList+1]=game:GetService("CoreGui") end)
if type(gethui)=="function" then pcall(function() rootList[#rootList+1]=gethui() end) end
local beforeGuis={}
local function visitGuis(callback)
    local visited={}
    for _,root in ipairs(rootList) do
        if not visited[root] then
            visited[root]=true
            pcall(function()
                if root:IsA("ScreenGui") then callback(root) end
                for _,obj in ipairs(root:GetDescendants()) do
                    if obj:IsA("ScreenGui") then callback(obj) end
                end
            end)
        end
    end
end
visitGuis(function(gui) beforeGuis[gui]=true end)

local REPO="https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local function loadModule(path,optional)
    local ok,result=pcall(function()
        local source=game:HttpGet(REPO..path)
        local chunk,err=loadstring(source)
        assert(chunk,err or ("Falha ao compilar "..path))
        return chunk()
    end)
    if not ok then
        if optional then warn("Neto Hub: "..path.." indisponivel: "..tostring(result)) return nil end
        error("Nao foi possivel carregar a Obsidian UI: "..tostring(result))
    end
    return result
end
local Library=loadModule("Library.lua")
local ThemeManager=loadModule("addons/ThemeManager.lua",true)
local SaveManager=loadModule("addons/SaveManager.lua",true)
Library.ForceCheckbox=false
Library.NotifyOnError=true
local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000,700)
local Window=Library:CreateWindow({
    Title="Neto Hub",
    Footer="6 funcoes | v1.0 | Obsidian UI",
    Icon="triangle",
    Center=true,
    AutoShow=true,
    Size=UDim2.fromOffset(math.max(580,math.min(860,viewport.X-48)),math.max(300,math.min(610,viewport.Y-60))),
    Font=Enum.Font.Code,
    CornerRadius=4,
    Resizable=true,
    ShowCustomCursor=false,
    ShowMobileButtons=true,
    MobileButtonsSide="Left",
    NotifySide="Right",
    DisableSearch=false,
    GlobalSearch=true,
    ToggleKeybind=Enum.KeyCode.RightShift,
})
local Toggles,Options=Library.Toggles,Library.Options
local alive=true
local connections,ownedGuis={},{}
local ownCallbacks=setmetatable({}, {__mode="k"})
local features,ordered={},{}
local scanning,scanToken=false,0
local panelTarget,panelLocator,panelPattern=nil,nil,{}
local panelCandidate,panelCandidateLocator,panelRecording=nil,nil,{}
local panelHeld=nil
local statsLabels={}
local setFeature,stopAll
local function notify(text)
    if alive then pcall(function() Library:Notify({Title="Neto Hub",Description=text,Time=4}) end) end
end
local function connect(signal,fn)
    ownCallbacks[fn]=true
    local c=signal:Connect(fn)
    connections[#connections+1]=c
    return c
end
local function labelText(label,text)
    if label then pcall(function() label:SetText(text) end) end
end
local function remote(name)
    local folder=RS:FindFirstChild("Remotes")
    local obj=folder and folder:FindFirstChild(name)
    if obj and obj:IsA("RemoteEvent") then return obj end
end
local function body()
    local c=player.Character
    local h=c and c:FindFirstChildOfClass("Humanoid")
    local r=c and c:FindFirstChild("HumanoidRootPart")
    if h and h.Health>0 and r then return c,h,r end
end
local function region(name)
    local base=workspace:FindFirstChild("Features")
    return base and base:FindFirstChild(name)
end
local function inRing(name)
    local c,h,r=body()
    local area=region(name)
    local ring=area and area:FindFirstChild("Ring")
    local zone=ring and ring:FindFirstChild("Extra")
    if not c or not zone or not zone:IsA("BasePart") then return false,c end
    local p=zone.CFrame:PointToObjectSpace(r.Position)
    local x,z=zone.Size.X/2,zone.Size.Z/2
    if x<=0 or z<=0 then return false,c end
    local vertical=zone.Size.Y/2+r.Size.Y/2+math.max(h.HipHeight,1)
    return (p.X/x)^2+(p.Z/z)^2<=1 and math.abs(p.Y)<=vertical,c
end
local function newFeature(id,title,interval)
    local f={id=id,title=title,enabled=false,interval=interval,unit="s",validInterval=true,token=0,sent=0,phase="Desligado"}
    features[id]=f
    ordered[#ordered+1]=f
    return f
end
local cash=newFeature("Cash","Auto Dropper",0.0001)
local bronze=newFeature("Bronze","Auto Bronze Dropper",0.001)
local coins=newFeature("Coins","Auto Coins",0)
local combat=newFeature("Combat","Auto Combate",0.05)
local tree=newFeature("Tree","Auto Tree",0.05)
local spam=newFeature("Spam","Spam Button",0.05)
coins.batch,coins.retry=25,3
coins.pending=setmetatable({}, {__mode="k"})
coins.visible=0
local function makeRemoteFeature(f,name)
    f.validate=function()
        f.remote=remote(name)
        return f.remote~=nil,name.." nao encontrado."
    end
    f.tick=function()
        if not body() then f.phase="Aguardando personagem" return end
        f.remote:FireServer()
        f.sent=f.sent+1
        f.phase="Ativo"
    end
end
makeRemoteFeature(cash,"DropperClick")
makeRemoteFeature(bronze,"BronzeDropperClick")
coins.validate=function()
    coins.remote=remote("CollectPart")
    return coins.remote~=nil,"CollectPart nao encontrado."
end
coins.tick=function()
    local essentials=workspace:FindFirstChild("MapEssentials")
    local folder=essentials and essentials:FindFirstChild("Spawned")
    if not folder then coins.phase="Aguardando moedas" coins.visible=0 return end
    local _,_,r=body()
    local items={}
    for _,obj in ipairs(folder:GetChildren()) do
        if (obj:IsA("BasePart") or obj:IsA("Model")) and obj:GetAttribute("PickedUp")~=true
            and (obj:GetAttribute("SpawnOrder")~=nil or obj:GetAttribute("FullSize")~=nil) then
            local position=obj:IsA("BasePart") and obj.Position or obj:GetPivot().Position
            items[#items+1]={obj=obj,distance=r and (position-r.Position).Magnitude or math.huge}
        end
    end
    table.sort(items,function(a,b) return a.distance<b.distance end)
    coins.visible=#items
    local batch=0
    for _,item in ipairs(items) do
        if not coins.enabled or not alive then break end
        local obj=item.obj
        local last=coins.pending[obj]
        local moved=last and item.distance+5<last.distance and os.clock()-last.at>=0.5
        if obj.Parent==folder and obj:GetAttribute("PickedUp")~=true
            and (not last or moved or os.clock()-last.at>=coins.retry) then
            coins.remote:FireServer(obj.Name)
            coins.pending[obj]={at=os.clock(),distance=item.distance}
            coins.sent=coins.sent+1
            batch=batch+1
            if batch>=coins.batch then break end
        end
    end
    coins.phase=#items>0 and "Ativo" or "Aguardando moedas"
end
local function makeAreaFeature(f,areaName,clickName,stateName)
    f.inside=false
    f.validate=function()
        f.remote,f.stateRemote=remote(clickName),remote(stateName)
        return f.remote~=nil and f.stateRemote~=nil,"Eventos de "..f.title.." indisponiveis."
    end
    f.release=function()
        if f.inside and f.stateRemote then pcall(function() f.stateRemote:FireServer(false) end) end
        f.inside,f.character=false,nil
    end
    f.tick=function()
        local near,c=inRing(areaName)
        if near then
            if not f.inside or f.character~=c then
                f.stateRemote:FireServer(true)
                f.inside,f.character=true,c
            end
            f.remote:FireServer()
            f.sent=f.sent+1
            f.phase="Ativo no alcance"
        else
            f.release()
            f.phase="Aguardando alcance"
        end
    end
end
makeAreaFeature(combat,"Fighting","MobAttackMlt","FightingState")
makeAreaFeature(tree,"Tree","TreeHit","ChoppingState")
local replaySignal=firesignal or env.firesignal
local listConnections=getconnections or env.getconnections
local function ownUI(obj)
    for gui in pairs(ownedGuis) do if obj==gui or obj:IsDescendantOf(gui) then return true end end
    return false
end
local function makeLocator(obj)
    local anchor
    for _,root in ipairs(rootList) do if obj:IsDescendantOf(root) then anchor=root break end end
    if not anchor then return nil end
    local steps={}
    while obj and obj~=anchor do
        local parent=obj.Parent
        if not parent then return nil end
        local index=0
        for _,sibling in ipairs(parent:GetChildren()) do
            if sibling.Name==obj.Name and sibling.ClassName==obj.ClassName then index=index+1 end
            if sibling==obj then break end
        end
        table.insert(steps,1,{name=obj.Name,class=obj.ClassName,index=index})
        obj=parent
    end
    return {root=anchor,steps=steps}
end
local function resolvePanel()
    if panelTarget and panelLocator and panelTarget:IsDescendantOf(panelLocator.root) then return panelTarget end
    if not panelLocator then return nil end
    local obj=panelLocator.root
    for _,step in ipairs(panelLocator.steps) do
        local found,count=nil,0
        for _,child in ipairs(obj:GetChildren()) do
            if child.Name==step.name and child.ClassName==step.class then
                count=count+1
                if count==step.index then found=child break end
            end
        end
        if not found then return nil end
        obj=found
    end
    panelTarget=obj
    return obj
end
local function visible(obj)
    if not obj.Parent then return false end
    local ok,interactable=pcall(function() return obj.Interactable end)
    if ok and not interactable then return false end
    local p=obj
    while p and p~=game do
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        p=p.Parent
    end
    return true
end
spam.validate=function()
    local obj=resolvePanel()
    if not obj then return false,"Use Scan para selecionar um botao primeiro." end
    if obj:IsA("ProximityPrompt") then return true end
    if #panelPattern==0 then return false,"Conclua o Scan primeiro." end
    return type(replaySignal)=="function" or type(listConnections)=="function",
        "O executor precisa oferecer firesignal ou getconnections."
end
spam.release=function()
    local obj=panelHeld
    panelHeld=nil
    if obj then pcall(function() obj:InputHoldEnd() end) end
end
spam.tick=function()
    local obj=resolvePanel()
    if not obj then spam.phase="Aguardando o alvo reaparecer" return end
    if obj:IsA("ProximityPrompt") then
        local _,_,r=body()
        local part=obj:FindFirstAncestorWhichIsA("BasePart")
        if not obj.Enabled or not r or not part or (r.Position-part.Position).Magnitude>obj.MaxActivationDistance then
            spam.phase="Aguardando alcance" return
        end
        panelHeld=obj
        local heldToken=spam.token
        obj:InputHoldBegin()
        task.wait(math.max(obj.HoldDuration,0))
        if spam.token==heldToken and panelHeld==obj then spam.release() end
    else
        if not visible(obj) then spam.phase="Aguardando botao visivel" return end
        local fired=0
        for _,event in ipairs(panelPattern) do
            if not spam.enabled or not alive or not obj.Parent then break end
            local args=event.args
            if event.name=="MouseButton1Down" or event.name=="MouseButton1Up" then
                local center=obj.AbsolutePosition+obj.AbsoluteSize/2
                args=table.pack(math.floor(center.X),math.floor(center.Y))
            end
            if type(replaySignal)=="function" then
                replaySignal(obj[event.name],table.unpack(args,1,args.n))
                fired=fired+1
            else
                for _,connection in ipairs(listConnections(obj[event.name])) do
                    local ok,fn=pcall(function() return connection.Function end)
                    local enabledOK,isEnabled=pcall(function() return connection.Enabled end)
                    if ok and type(fn)=="function" and not ownCallbacks[fn] and (not enabledOK or isEnabled~=false) then
                        task.spawn(fn,table.unpack(args,1,args.n))
                        fired=fired+1
                    end
                end
            end
        end
        assert(fired>0,"Nenhum callback do botao esta acessivel.")
    end
    spam.sent=spam.sent+1
    spam.phase="Ativo"
end

local function intervalControls(box,f)
    box:AddInput(f.id.."Interval",{
        Text="Intervalo",Default=string.format("%.9g",f.interval),Numeric=false,
        Finished=false,ClearTextOnFocus=false,Tooltip="Zero tenta uma vez por frame.",
    })
    box:AddDropdown(f.id.."Unit",{Text="Unidade",Values={"s","ms"},Default="s"})
end
local icons={Cash="mouse-pointer-click",Bronze="boxes",Coins="coins",Combat="swords",Tree="trees",Spam="scan"}
local tabs={}
for _,f in ipairs(ordered) do
    local tab=Window:AddTab(f.title,icons[f.id])
    tabs[f.id]=tab
    local control=tab:AddGroupbox({Side="Left",Name=f.title,IconName=icons[f.id]})
    local detail=tab:AddGroupbox({Side="Right",Name="Status",IconName="activity"})
    control:AddToggle(f.id.."Enabled",{Text="Ativar "..f.title,Default=false})
    f.toggle=Toggles[f.id.."Enabled"]
    intervalControls(control,f)
    f.statusLabel=detail:AddLabel("Desligado",true)
    f.counterLabel=detail:AddLabel("Envios: 0",true)
    if f==coins then
        control:AddSlider("CoinsBatch",{Text="Moedas por lote",Default=25,Min=1,Max=50,Rounding=0})
        control:AddInput("CoinsRetry",{Text="Repetir pedido pendente (s)",Default="3",Numeric=false,Finished=false,ClearTextOnFocus=false})
        detail:AddLabel("A coleta depende das moedas carregadas e da validacao do jogo.",true)
    elseif f==combat or f==tree then
        detail:AddLabel("Entre no anel para iniciar. Pausa ao sair.",true)
        detail:AddLabel("Combate e arvore se alternam automaticamente.",true)
    elseif f==spam then
        f.targetLabel=detail:AddLabel("Alvo: nenhum",true)
        control:AddButton("Scan / escolher novo",function()
            -- A funcao completa e definida apos a montagem do painel.
            if env.NetoHubStartScan then env.NetoHubStartScan() end
        end)
        control:AddButton("Cancelar Scan",function()
            scanning=false scanToken=scanToken+1
            panelCandidate,panelCandidateLocator,panelRecording=nil,nil,{}
            Window:Toggle(true)
            notify("Scan cancelado.")
        end)
        detail:AddLabel("Scan esconde o hub. Toque no botao do jogo; o painel volta quando detectar.",true)
    else
        detail:AddLabel("Intervalos muito pequenos ficam limitados pelos frames e pelo servidor.",true)
    end
    detail:AddButton("Zerar contador",function() f.sent=0 end)
end
local settingsTab=Window:AddTab("Settings","settings")
local menu=settingsTab:AddGroupbox({Side="Left",Name="Menu",IconName="settings"})
menu:AddButton("Minimizar / abrir",function() Window:Toggle() end)
menu:AddButton("Desligar todos",function() if stopAll then stopAll() end end)
menu:AddDropdown("DPIScale",{Text="DPI Scale",Values={"50%","65%","75%","85%","100%","125%","150%"},Default="100%"})
menu:AddToggle("CustomCursor",{Text="Custom Cursor",Default=false})
menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind",{Default="RightShift",NoUI=true,Text="Mostrar / ocultar menu"})
Library.ToggleKeybind=Options.MenuKeybind
menu:AddButton("Unload / fechar tudo",function() Library:Unload() end)
menu:AddLabel("Perfis salvam intervalos e aparencia. Os autos iniciam OFF.",true)

setFeature=function(f,on)
    if not alive then return end
    if f.enabled==on then return end
    if not on then
        f.enabled=false
        f.token=f.token+1
        if f.release then f.release() end
        f.phase="Desligado"
        labelText(f.statusLabel,f.phase)
        return
    end
    if not f.validInterval then
        f.toggle:SetValue(false)
        notify("Intervalo invalido em "..f.title..".")
        return
    end
    if f==spam and scanning then f.toggle:SetValue(false) notify("Termine o Scan primeiro.") return end
    local ok,valid,reason=pcall(f.validate)
    if not ok or not valid then
        f.toggle:SetValue(false)
        notify(ok and (reason or "Funcao indisponivel.") or tostring(valid))
        return
    end
    if f==tree and combat.enabled then combat.toggle:SetValue(false) end
    if f==combat and tree.enabled then tree.toggle:SetValue(false) end
    f.enabled=true
    f.token=f.token+1
    local token=f.token
    f.phase="Ligando"
    task.spawn(function()
        while alive and f.enabled and f.token==token do
            local began=os.clock()
            local success,err=pcall(f.tick)
            if not success then
                f.error=tostring(err)
                f.toggle:SetValue(false)
                f.phase="Erro: "..f.error
                labelText(f.statusLabel,f.phase)
                notify(f.title..": "..f.error)
                break
            end
            task.wait(math.max(0,f.interval-(os.clock()-began)))
        end
    end)
end
stopAll=function()
    scanning=false scanToken=scanToken+1
    panelCandidate,panelCandidateLocator,panelRecording=nil,nil,{}
    for _,f in ipairs(ordered) do f.toggle:SetValue(false) end
end
for _,f in ipairs(ordered) do
    f.toggle:OnChanged(function() setFeature(f,f.toggle.Value) end)
    Options[f.id.."Interval"]:OnChanged(function()
        local n=tonumber((tostring(Options[f.id.."Interval"].Value):gsub(",",".")))
        local seconds=n and (f.unit=="ms" and n/1000 or n)
        f.validInterval=seconds~=nil and seconds==seconds and seconds>=0 and seconds<=86400
        if f.validInterval then f.interval=seconds end
    end)
    Options[f.id.."Unit"]:OnChanged(function()
        local unit=Options[f.id.."Unit"].Value
        if unit==f.unit then return end
        f.unit=unit
        -- Rele o valor na unidade escolhida. Independe da ordem de carga do perfil.
        local n=tonumber((tostring(Options[f.id.."Interval"].Value):gsub(",",".")))
        local seconds=n and (unit=="ms" and n/1000 or n)
        f.validInterval=seconds~=nil and seconds==seconds and seconds>=0 and seconds<=86400
        if f.validInterval then f.interval=seconds end
    end)
end
Options.CoinsBatch:OnChanged(function() coins.batch=math.clamp(math.floor(Options.CoinsBatch.Value),1,50) end)
Options.CoinsRetry:OnChanged(function()
    local n=tonumber((tostring(Options.CoinsRetry.Value):gsub(",",".")))
    if n and n==n and n>=0.1 and n<=3600 then coins.retry=n end
end)
Options.DPIScale:OnChanged(function() Library:SetDPIScale(tonumber((Options.DPIScale.Value:gsub("%%","")))) end)
Toggles.CustomCursor:OnChanged(function() Library.ShowCustomCursor=Toggles.CustomCursor.Value end)

local scannerReady=false
local hooked=setmetatable({}, {__mode="k"})
local function finishScan(token)
    if not alive or not scanning or token~=scanToken or not panelCandidate then return end
    local hasClick=panelCandidate:IsA("ProximityPrompt")
    for _,event in ipairs(panelRecording) do
        if event.name=="Activated" or event.name=="MouseButton1Click" then hasClick=true end
    end
    if not hasClick then return end
    panelTarget,panelLocator,panelPattern=panelCandidate,panelCandidateLocator or makeLocator(panelCandidate),panelRecording
    panelCandidate,panelCandidateLocator,panelRecording=nil,nil,{}
    scanning=false
    local text=panelTarget:IsA("TextButton") and panelTarget.Text or panelTarget.Name
    if text=="" then text=panelTarget.Name end
    labelText(spam.targetLabel,"Alvo: "..string.sub(text,1,70).."\n"..string.sub(panelTarget:GetFullName(),1,170))
    Window:Toggle(true)
    notify("Alvo selecionado. Ajuste o intervalo e ative Spam Button.")
end
local function hookButton(obj)
    if not obj:IsA("GuiButton") or hooked[obj] or ownUI(obj) then return end
    hooked[obj]=true
    local cached=makeLocator(obj)
    for _,name in ipairs({"MouseButton1Down","MouseButton1Up","Activated","MouseButton1Click"}) do
        connect(obj[name],function(...)
            if not alive or not scanning or ownUI(obj) then return end
            if not panelCandidate then panelCandidate=obj panelCandidateLocator=makeLocator(obj) or cached end
            if panelCandidate~=obj then return end
            local exists=false
            for _,event in ipairs(panelRecording) do if event.name==name then exists=true break end end
            if not exists then panelRecording[#panelRecording+1]={name=name,args=table.pack(...)} end
            if name=="Activated" or name=="MouseButton1Click" then
                local token=scanToken
                task.delay(0.07,function() finishScan(token) end)
            end
        end)
    end
end
env.NetoHubStartScan=function()
    spam.toggle:SetValue(false)
    scanToken=scanToken+1
    panelCandidate,panelCandidateLocator,panelRecording=nil,nil,{}
    if not scannerReady then
        scannerReady=true
        local checked={}
        for _,root in ipairs(rootList) do
            if not checked[root] then
                checked[root]=true
                pcall(function()
                    connect(root.DescendantAdded,hookButton)
                    for _,obj in ipairs(root:GetDescendants()) do hookButton(obj) end
                end)
            end
        end
        connect(Prompts.PromptTriggered,function(prompt,who)
            if not scanning or (who~=nil and who~=player) then return end
            panelCandidate,panelCandidateLocator,panelRecording=prompt,makeLocator(prompt),{}
            finishScan(scanToken)
        end)
    end
    scanning=true
    Window:Toggle(false)
    notify("Toque uma vez no botao do jogo. O hub volta apos detectar.")
    local token=scanToken
    task.delay(30,function()
        if alive and scanning and token==scanToken then
            scanning=false
            Window:Toggle(true)
            notify("Scan expirou. Abra o painel do jogo e tente novamente.")
        end
    end)
end

-- Tema preto/roxo e fonte monoespacada do print.
pcall(function()
    Library:SetFont(Enum.Font.Code)
    if Library.Scheme then
        local colors={BackgroundColor=Color3.fromRGB(14,14,16),MainColor=Color3.fromRGB(18,18,20),
            OutlineColor=Color3.fromRGB(37,37,41),FontColor=Color3.fromRGB(225,225,230),
            AccentColor=Color3.fromRGB(133,92,246)}
        for key,value in pairs(colors) do Library.Scheme[key]=value end
        Library:UpdateColorsUsingRegistry()
    end
end)
if ThemeManager then
    local ok,err=pcall(function()
        ThemeManager:SetLibrary(Library)
        ThemeManager:SetFolder("NetoHub")
        ThemeManager:ApplyToTab(settingsTab)
    end)
    if not ok then warn("Neto Hub / temas: "..tostring(err)) end
end
local filesystem=type(writefile)=="function" and type(readfile)=="function" and type(makefolder)=="function" and type(isfolder)=="function" and type(listfiles)=="function"
if SaveManager and filesystem then
    local ok,err=pcall(function()
        SaveManager:SetLibrary(Library)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({"CashEnabled","BronzeEnabled","CoinsEnabled","CombatEnabled","TreeEnabled","SpamEnabled","MenuKeybind"})
        SaveManager:SetFolder("NetoHub/"..tostring(game.PlaceId))
        SaveManager:BuildConfigSection(settingsTab)
        SaveManager:LoadAutoloadConfig()
    end)
    if not ok then notify("Perfis indisponiveis neste executor.") warn(err) end
else
    local config=settingsTab:AddGroupbox({Side="Right",Name="Configuration",IconName="folder"})
    config:AddLabel("Este executor nao disponibilizou os arquivos necessarios para salvar perfis.",true)
end
visitGuis(function(gui) if not beforeGuis[gui] then ownedGuis[gui]=true end end)

local function cleanup()
    if not alive then return end
    stopAll()
    alive=false
    for _,c in ipairs(connections) do c:Disconnect() end
    spam.release()
    env.NetoHubStartScan=nil
    env.NetoHub=nil
    env.NetoHubCleanup=nil
end
Library:OnUnload(cleanup)
env.NetoHubCleanup=function()
    if not Library.Unloaded then Library:Unload() else cleanup() end
end
env.NetoHub={Features=features,Library=Library,Window=Window,StopAll=stopAll}
-- Encerra as versoes antigas para evitar loops duplicados.
env.CombatAutoRunning=false
for _,name in ipairs({"AutoInteractCleanup","BronzeDropperCleanup","AutoMoedasCleanup","CombatAutoCleanup",
    "TreeAutoCleanup","ButtonAutoCleanup","NewDropperScanStop"}) do
    if type(env[name])=="function" then pcall(env[name]) end
end
env.TreeDebugObserver=nil
env.FightDebugObserver=nil
env.FightRangeObserver=nil
env.CoinDiagObserver=nil
task.spawn(function()
    while alive and not Library.Unloaded do
        for _,f in ipairs(ordered) do
            labelText(f.statusLabel,f.phase)
            labelText(f.counterLabel,"Envios: "..tostring(f.sent)..(f==coins and ("\nMoedas visiveis: "..coins.visible) or ""))
        end
        task.wait(0.5)
    end
end)
notify("Neto Hub pronto. As seis funcoes iniciam OFF.")

