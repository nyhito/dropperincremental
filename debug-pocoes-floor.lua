-- Debug de PESCA. Nome preservado para atualizar o mesmo arquivo no GitHub.
-- Observa somente: nao lanca, nao vence minigame, nao dispara compras/eventos.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
if env.FishingDebug and type(env.FishingDebug.Close)=="function" then pcall(env.FishingDebug.Close) end
if env.PurchaseTest and type(env.PurchaseTest.Close)=="function" then pcall(env.PurchaseTest.Close) end
if env.PurchaseDetector and type(env.PurchaseDetector.Close)=="function" then pcall(env.PurchaseDetector.Close) end
local alive,session=true,nil
local links,sessionLinks={},{}
local report,started,previousProbe=nil,0,nil
local duration=40
local ownGui
local start,stop,copy,close
local state={enabled=false,names={},queue={},head=1,tail=0,dropped=0,busy=false}
local ignored={DropperClick=true,BronzeDropperClick=true,CollectPart=true,MobAttackMlt=true,FightingState=true,
    TreeHit=true,ChoppingState=true,EnemySwing=true,EnemyDamaged=true,EnemyKilled=true,CrystalDestroyed=true,
    RockDamaged=true,RockAttackState=true,PlaySound=true,ChangeWalkspeed=true,TextPopUp=true,DisplayMessage=true,
    CreatePopUp=true,ChatMessage=true,UpdateGlobalMilestones=true}
local function fishName(name)
    name=name:lower()
    for _,word in ipairs({"fish","pesca","reel","catch","cast","bait","bobber","rod","lake"}) do
        if name:find(word,1,true) then return true end
    end
    return false
end
local function connect(signal,fn,list)
    local c=signal:Connect(fn) local target=list or links target[#target+1]=c return c
end
local function disconnect(list)
    for _,c in ipairs(list) do c:Disconnect() end
    for i=#list,1,-1 do list[i]=nil end
end
local function stamp() return math.floor((os.clock()-started)*1000+.5)/1000 end
local function serial(v,depth,budget,seen)
    local kind=typeof(v)
    budget.left=budget.left-1
    if budget.left<0 then return "[limit]" end
    if kind=="nil" then return {type="nil"} end
    if kind=="boolean" then return v end
    if kind=="number" then return (v==v and v~=math.huge and v~=-math.huge) and v or tostring(v) end
    if kind=="string" then return v:sub(1,180) end
    if kind=="Instance" then return {type=kind,path=v:GetFullName(),class=v.ClassName} end
    if kind=="Vector3" then return {type=kind,x=v.X,y=v.Y,z=v.Z} end
    if kind=="Vector2" then return {type=kind,x=v.X,y=v.Y} end
    if kind=="table" then
        if depth>=3 or seen[v] then return "[limit]" end
        seen[v]=true
        local out,n={},0
        for k,x in pairs(v) do
            n=n+1 if n>10 or budget.left<=0 then break end
            if type(k)=="string" or type(k)=="number" then out[tostring(k)]=serial(x,depth+1,budget,seen) end
        end
        seen[v]=nil return out
    end
    return {type=kind,value=tostring(v):sub(1,160)}
end
-- O interceptor so copia dados Lua para uma fila limitada; nao consulta o Roblox.
local function rawClone(v,depth,seen,budget)
    if type(v)~="table" then return v end
    if depth>=3 or seen[v] or budget.left<=0 then return "[limit]" end
    seen[v]=true
    local out,n={},0
    for k,x in next,v do
        n=n+1 if n>10 or budget.left<=0 then break end
        budget.left=budget.left-1
        if type(k)=="string" or type(k)=="number" then out[k]=rawClone(x,depth+1,seen,budget) end
    end
    seen[v]=nil return out
end
local function pushRaw(s,obj,method,...)
    if s.tail-s.head+1>=128 then s.dropped=s.dropped+1 return end
    local args=table.pack(...) local frozen={n=args.n} local budget={left=60}
    for i=1,math.min(args.n,8) do frozen[i]=rawClone(args[i],0,{},budget) end
    s.tail=s.tail+1
    s.queue[s.tail]={remote=obj,method=method,args=frozen,at=os.clock()}
end
local function enableCapture()
    local prior=env.__NetoPurchaseProbeState
    if prior and prior.enabled and prior~=state then return false,"Outro detector esta gravando. Encerre-o primeiro." end
    previousProbe=prior
    env.__NetoPurchaseProbeState=state
    if not env.__NetoPurchaseHookInstalled then
        if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then
            return false,"Executor sem observacao de chamadas; interface e respostas ainda serao registradas."
        end
        local ok,err=pcall(function()
            local original
            local handler=function(self,...)
                local s=env.__NetoPurchaseProbeState
                if s and s.enabled and s.names[self] and not s.busy then
                    local method=getnamecallmethod()
                    if method=="FireServer" or method=="InvokeServer" then
                        s.busy=true pcall(pushRaw,s,self,method,...) s.busy=false
                    end
                end
                return original(self,...)
            end
            original=hookmetamethod(game,"__namecall",type(newcclosure)=="function" and newcclosure(handler) or handler)
            env.__NetoPurchaseHookInstalled=true
        end)
        if not ok then return false,tostring(err) end
    end
    state.enabled=true return true
end
local callMap,uiMap,uiCandidates,uiSeen,remoteSeen={},{},{},{},{}
local function drain(s)
    local n=0
    while state.head<=state.tail and n<40 do
        local raw=state.queue[state.head] state.queue[state.head]=nil state.head=state.head+1 n=n+1
        local meta=raw and state.names[raw.remote]
        if meta then
            local firstArg=raw.args[1]
            local action=type(firstArg)=="string" and firstArg:sub(1,70) or nil
            local key=meta.path.."|"..raw.method.."|"..tostring(action or "")
            local entry=callMap[key]
            if not entry and #s.calls<24 then
                entry={remote=meta.path,method=raw.method,action=action,count=0,first=raw.at-started,last=raw.at-started,
                    argCount=raw.args.n,variants={}}
                callMap[key]=entry s.calls[#s.calls+1]=entry
            end
            if entry then
                entry.count=entry.count+1 entry.last=math.floor((raw.at-started)*1000+.5)/1000
                local args,budget={},{left=40}
                for i=1,math.min(raw.args.n,8) do args[tostring(i)]=serial(raw.args[i],0,budget,{}) end
                entry.lastArgs=args
                local signature=Http:JSONEncode(args)
                local variant
                for i,x in ipairs(entry.variants) do if x.signature==signature then variant=i break end end
                if not variant and #entry.variants<3 then
                    variant=#entry.variants+1
                    entry.variants[variant]={args=args,argCount=raw.args.n,count=0,first=stamp(),last=stamp(),signature=signature}
                end
                if variant then local x=entry.variants[variant] x.count=x.count+1 x.last=stamp()
                else entry.extraVariants=(entry.extraVariants or 0)+1 end
                if #s.timeline<64 then s.timeline[#s.timeline+1]={t=math.floor((raw.at-started)*1000+.5)/1000,
                    remote=meta.name,method=raw.method,variant=variant or 0} end
            else s.droppedGroups=s.droppedGroups+1 end
        end
    end
    if state.head>state.tail then state.queue={} state.head=1 state.tail=0 end
end
local function visible(obj)
    if not obj.Parent then return false end
    local p=obj
    for _=1,15 do
        if not p or p==game then break end
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        p=p.Parent
    end
    return true
end
local function uiCandidate(obj)
    if uiSeen[obj] or #uiCandidates>=160 or not obj.Parent or obj==ownGui or obj:IsDescendantOf(ownGui) then return end
    if not (obj:IsA("GuiObject") or obj:IsA("ValueBase")) then return end
    local p=obj local related=false
    for _=1,9 do
        if not p or p==player then break end
        if fishName(p.Name) or p.Name:lower()=="minigame" then related=true break end
        p=p.Parent
    end
    if not related then return end
    local full=obj:GetFullName()
    local lower=full:lower()
    for _,skip in ipairs({"fishingshop","fishpedia","fishingbook","fishinginventory","attackspeedbar"}) do
        if lower:find(skip,1,true) then return end
    end
    uiSeen[obj]=true uiCandidates[#uiCandidates+1]=obj
end
local function uiState(obj)
    local out={visible=visible(obj)}
    if obj:IsA("GuiObject") then
        out.position=tostring(obj.Position) out.size=tostring(obj.Size)
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then out.text=obj.Text:sub(1,130) end
        if obj:IsA("CanvasGroup") then out.alpha=obj.GroupTransparency end
    elseif obj:IsA("ValueBase") then out.value=serial(obj.Value,0,{left=12},{}) end
    local attrs=obj:GetAttributes()
    if next(attrs) then out.attributes=serial(attrs,0,{left=16},{}) end
    return out
end
local function sampleUI(s)
    local sampled,began=0,os.clock()
    for _,obj in ipairs(uiCandidates) do
        if session~=s then return end
        if obj.Parent then
            local ok,value=pcall(uiState,obj)
            if ok then
                local full=obj:GetFullName()
                local entry=uiMap[full]
                if not entry then
                    local slot=#s.ui<45 and (#s.ui+1) or nil
                    if not slot and value.visible then
                        for i,old in ipairs(s.ui) do if not old.seenVisible then slot=i uiMap[old.path]=nil break end end
                    end
                    if slot then
                        entry={path=full,class=obj.ClassName,seenVisible=false,changes=0,samples={}}
                        uiMap[full]=entry s.ui[slot]=entry
                    end
                end
                if entry then
                    local signature=Http:JSONEncode(value)
                    entry.seenVisible=entry.seenVisible or value.visible
                    if entry.signature~=signature then
                        entry.changes=entry.changes+1 entry.signature=signature
                        entry.last=value entry.lastAt=stamp()
                        local sample={t=stamp(),state=value}
                        if #entry.samples<4 then entry.samples[#entry.samples+1]=sample else entry.samples[4]=sample end
                    end
                end
            end
        end
        sampled=sampled+1
        if sampled%24==0 or os.clock()-began>=.002 then task.wait() began=os.clock() end
    end
end
local function avatarState()
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    local out={position=root and tostring(root.Position),tools={}}
    if c then
        for _,obj in ipairs(c:GetChildren()) do if obj:IsA("Tool") then out.tools[#out.tools+1]={name=obj.Name,attributes=serial(obj:GetAttributes(),0,{left=20},{})} end end
    end
    local attrs={}
    for k,v in pairs(player:GetAttributes()) do if fishName(k) then attrs[k]=serial(v,0,{left=12},{}) end end
    if next(attrs) then out.attributes=attrs end
    return out
end
local function discoverWorld(s)
    local roots={workspace:FindFirstChild("Features"),workspace:FindFirstChild("MapEssentials"),workspace}
    local seen={}
    for _,root in pairs(roots) do
        for _,obj in ipairs(root:GetChildren()) do
            if fishName(obj.Name) and not seen[obj] and #s.world<8 then
                seen[obj]=true
                local entry={path=obj:GetFullName(),class=obj.ClassName,attributes=serial(obj:GetAttributes(),0,{left=20},{}),parts={}}
                local candidates=obj:IsA("BasePart") and {obj} or obj:GetDescendants()
                for i,part in ipairs(candidates) do
                    if i>200 then break end
                    if part:IsA("BasePart") and #entry.parts<14 then
                        entry.parts[#entry.parts+1]={path=part:GetFullName(),size=tostring(part.Size),position=tostring(part.Position),
                            canTouch=part.CanTouch,transparency=part.Transparency,attributes=serial(part:GetAttributes(),0,{left=12},{})}
                    end
                end
                s.world[#s.world+1]=entry
            end
        end
    end
end
local function remoteCandidate(obj,s)
    if remoteSeen[obj] or not (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) then return end
    remoteSeen[obj]=true
    if #s.remotes<120 then s.remotes[#s.remotes+1]={name=obj.Name,path=obj:GetFullName(),class=obj.ClassName} end
    if ignored[obj.Name] and not fishName(obj.Name) then return end
    state.names[obj]={path=obj:GetFullName(),name=obj.Name,class=obj.ClassName}
    if obj:IsA("RemoteEvent") then
        connect(obj.OnClientEvent,function(...)
            if session==s then pushRaw(state,obj,"OnClientEvent",...) end
        end,sessionLinks)
    end
end
-- Pequeno painel independente. O hub e suas configuracoes nao sao alterados.
ownGui=Instance.new("ScreenGui") ownGui.Name="FishingDebug" ownGui.ResetOnSpawn=false ownGui.DisplayOrder=10030
ownGui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(310,205) panel.Position=UDim2.new(0,12,0.15,0)
panel.BackgroundColor3=Color3.fromRGB(21,23,30) panel.Parent=ownGui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,9)
local function button(text,x,y,w,h)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.Gotham b.TextSize=13
    b.TextColor3=Color3.new(1,1,1) b.BackgroundColor3=Color3.fromRGB(66,49,110)
    b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(w,h) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="DEBUG / PESCA" title.Font=Enum.Font.GothamBold title.TextSize=14
 title.TextColor3=Color3.new(1,1,1) title.BackgroundTransparency=1 title.Active=true
 title.Position=UDim2.fromOffset(10,3) title.Size=UDim2.fromOffset(210,30) title.Parent=panel
local minimize=button("-",240,6,26,26) local exit=button("X",274,6,26,26)
local startButton=button("Iniciar (40 s)",10,42,290,35)
local stopButton=button("Parar e copiar",10,84,141,32) local copyButton=button("Copiar",159,84,141,32)
local label=Instance.new("TextLabel") label.Text="Inicie e pesque 2 ou 3 peixes manualmente, incluindo o minigame."
label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top
label.Font=Enum.Font.Gotham label.TextSize=12 label.TextColor3=Color3.new(1,1,1) label.BackgroundTransparency=1
label.Position=UDim2.fromOffset(10,125) label.Size=UDim2.fromOffset(290,72) label.Parent=panel
local mini=Instance.new("TextButton") mini.Text="PESCA" mini.Font=Enum.Font.GothamBold mini.TextSize=12
mini.TextColor3=Color3.new(1,1,1) mini.BackgroundColor3=Color3.fromRGB(66,49,110)
mini.Position=panel.Position mini.Size=UDim2.fromOffset(70,38) mini.Visible=false mini.Parent=ownGui
Instance.new("UICorner",mini).CornerRadius=UDim.new(0,8)
local output=Instance.new("TextBox") output.Text="" output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false
output.Font=Enum.Font.Code output.TextSize=10 output.TextColor3=Color3.new(1,1,1) output.BackgroundColor3=Color3.fromRGB(29,31,39)
output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top
output.Position=UDim2.fromOffset(0,211) output.Size=UDim2.fromOffset(310,135) output.Visible=false output.Parent=panel
local function export(s)
    local data={format=s.format,placeId=s.placeId,seconds=s.seconds or stamp(),capabilities=s.capabilities,
        note="Observacao passiva. Chamadas e UI nao comprovam que o servidor aceita pular o minigame.",
        taps=s.taps,holds=s.holds,start=s.start,finish=s.finish,calls={},timeline=s.timeline,ui={},world=s.world,captureMessage=s.captureMessage,
        dropped=s.dropped or state.dropped,droppedGroups=s.droppedGroups}
    for _,c in ipairs(s.calls) do
        local e={remote=c.remote,method=c.method,action=c.action,count=c.count,first=c.first,last=c.last,argCount=c.argCount,variants={},
            extraVariants=c.extraVariants,lastArgs=c.extraVariants and c.lastArgs or nil}
        for _,v in ipairs(c.variants) do e.variants[#e.variants+1]={args=v.args,argCount=v.argCount,count=v.count,first=v.first,last=v.last} end
        data.calls[#data.calls+1]=e
    end
    for _,u in ipairs(s.ui) do
        if u.seenVisible or u.changes>1 then
            data.ui[#data.ui+1]={path=u.path,class=u.class,changes=u.changes,last=u.last,samples=u.samples}
        end
    end
    local inventory={}
    for _,r in ipairs(s.remotes) do if fishName(r.name) then inventory[#inventory+1]=r end end
    data.remotes=inventory
    local payload=Http:JSONEncode(data)
    if #payload>18000 then
        data.trimmed=true
        data.world=nil data.timeline=nil
        for _,u in ipairs(data.ui) do u.samples=nil end
        payload=Http:JSONEncode(data)
    end
    while #payload>18000 and #data.ui>0 do table.remove(data.ui) payload=Http:JSONEncode(data) end
    if #payload>18000 then
        data.trimmed=true
        for _,c in ipairs(data.calls) do while #c.variants>1 do table.remove(c.variants) end end
        payload=Http:JSONEncode(data)
    end
    while #payload>18000 and #data.calls>2 do
        local removeAt
        for i=#data.calls-1,2,-1 do if not fishName(data.calls[i].remote) then removeAt=i break end end
        table.remove(data.calls,removeAt or 2)
        payload=Http:JSONEncode(data)
    end
    if #payload>18000 then
        data.remotes=nil data.start=nil data.finish=nil
        for _,c in ipairs(data.calls) do
            c.lastArgs=c.lastArgs and serial(c.lastArgs,0,{left=12},{})
            for _,v in ipairs(c.variants) do v.args=serial(v.args,0,{left=12},{}) end
        end
        payload=Http:JSONEncode(data)
    end
    return payload
end
copy=function()
    local s=session or report
    if not s then label.Text="Inicie o debug e pesque antes de copiar." return end
    if session then drain(s) s.seconds=stamp() end
    local payload=export(s)
    env.FishingDebugReport=payload
    local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard
    local ok,result=false,nil
    if type(clip)=="function" then ok,result=pcall(clip,payload) end
    output.Text=payload output.Visible=not (ok and result~=false)
    if output.Visible then panel.Visible=true mini.Visible=false label.Text="Copie o texto da caixa abaixo e envie aqui."
    else label.Text="Relatorio copiado. Cole e envie aqui." end
    return payload
end
stop=function(shouldCopy)
    local s=session
    if s then
        state.enabled=false
        drain(s) drain(s) drain(s) drain(s)
        s.seconds=stamp() s.finish=avatarState() s.dropped=state.dropped
        disconnect(sessionLinks)
        session=nil report=s env.FishingDebug.Report=s
        if env.__NetoPurchaseProbeState==state then env.__NetoPurchaseProbeState=previousProbe end
        startButton.Text="Iniciar (40 s)"
    end
    if shouldCopy then return copy() end
end
start=function()
    if session or not alive then return end
    local prior=env.__NetoPurchaseProbeState
    if prior and prior.enabled and prior~=state then label.Text="Outro detector esta gravando. Encerre-o primeiro." return end
    started=os.clock()
    state.enabled=false state.names={} state.queue={} state.head=1 state.tail=0 state.dropped=0
    callMap,uiMap,uiCandidates,uiSeen,remoteSeen={},{},{},{},{}
    local s={format="fishing-debug-v1",placeId=game.PlaceId,calls={},timeline={},ui={},remotes={},world={},taps=0,holds={},droppedGroups=0,
        capabilities={remoteObservation=false,incomingEvents=true,clipboard=type(setclipboard or toclipboard)=="function"}}
    session=s report=s env.FishingDebug.Report=s
    s.start=avatarState()
    local ok,why=enableCapture() s.capabilities.remoteObservation=ok s.captureMessage=why
    local remotes=RS:FindFirstChild("Remotes") or RS
    for _,obj in ipairs(remotes:GetDescendants()) do remoteCandidate(obj,s) end
    connect(remotes.DescendantAdded,function(obj) if session==s then remoteCandidate(obj,s) end end,sessionLinks)
    local pg=player:WaitForChild("PlayerGui")
    connect(pg.DescendantAdded,function(obj) if session==s then uiCandidate(obj) end end,sessionLinks)
    local heldInputs=setmetatable({}, {__mode="k"})
    connect(UIS.InputBegan,function(input,processed)
        if session~=s then return end
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            s.taps=s.taps+1
            heldInputs[input]={at=os.clock(),processed=processed}
        end
    end,sessionLinks)
    connect(UIS.InputEnded,function(input,processed)
        local held=heldInputs[input] heldInputs[input]=nil
        if session~=s or not held then return end
        local seconds=os.clock()-held.at
        if seconds>=.06 then
            local entry={t=math.floor((held.at-started)*1000+.5)/1000,duration=math.floor(seconds*1000+.5)/1000,
                processed=held.processed,endedProcessed=processed}
            if #s.holds<16 then s.holds[#s.holds+1]=entry else s.holds[16]=entry end
        end
    end,sessionLinks)
    startButton.Text="Gravando..."
    label.Text=ok and "Pesque manualmente. Inclua lancamento, minigame e captura." or (why or "Registrando interface e respostas.")
    task.spawn(function()
        for i,obj in ipairs(pg:GetDescendants()) do
            if session~=s then return end
            uiCandidate(obj)
            if i%100==0 then task.wait() end
        end
        if session==s then discoverWorld(s) end
    end)
    task.spawn(function()
        local nextSample=0
        while alive and session==s and os.clock()-started<duration do
            drain(s)
            if os.clock()>=nextSample then
                sampleUI(s) nextSample=os.clock()+.2
                label.Text="Gravando: "..math.floor(os.clock()-started).."/40 s. Pesque normalmente."
            end
            task.wait(.1)
        end
        if alive and session==s then stop(true) end
    end)
end
close=function()
    if not alive then return end
    stop(false) alive=false disconnect(links) ownGui:Destroy()
end
env.FishingDebug={Start=start,Stop=function() return stop(true) end,Copy=copy,Close=close,Report=report}
connect(startButton.Activated,start)
connect(stopButton.Activated,function() stop(true) end)
connect(copyButton.Activated,copy)
connect(exit.Activated,close)
connect(minimize.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false end)
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
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+delta.X,0,math.max(0,view.X-310)),
            math.clamp(panelStart.Y.Scale*view.Y+panelStart.Y.Offset+delta.Y,0,math.max(0,view.Y-205)))
    end
end)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
print("Debug de pesca pronto. Clique Iniciar e pesque manualmente.")
