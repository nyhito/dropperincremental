-- Detector separado: Pocoes / Floor Upgrades. NAO integra nem altera o hub.
-- Observa compras MANUAIS. Nunca dispara FireServer/InvokeServer por conta propria.
-- Captura limitada a 25s, buffer limitado e serializacao fora do interceptador.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local player=Players.LocalPlayer
assert(player,"Execute no cliente.")
local env=(type(getgenv)=="function" and getgenv()) or _G
if env.PurchaseDetector and type(env.PurchaseDetector.Close)=="function" then pcall(env.PurchaseDetector.Close) end
local pg=player:WaitForChild("PlayerGui")
local alive,recording=true,nil
local allConnections,modeConnections={},{}
local report={format="purchases-debug-v1",placeId=game.PlaceId,sessions={}}
local state={enabled=false,names={},queue={},head=1,tail=0,dropped=0,busy=false}
env.__NetoPurchaseProbeState=state
local quiet={DropperClick=true,BronzeDropperClick=true,CollectPart=true,MobAttackMlt=true,TreeHit=true}
local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard
local startMode,stopMode,copyReport,closeDetector
local gui=Instance.new("ScreenGui")
gui.Name,gui.ResetOnSpawn,gui.DisplayOrder="PurchaseDetector",false,10020
gui.Parent=pg
local panel=Instance.new("Frame")
panel.Size,panel.Position=UDim2.fromOffset(320,232),UDim2.new(0,14,0.16,0)
panel.BackgroundColor3,panel.Parent=Color3.fromRGB(20,22,29),gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,10)
local title=Instance.new("TextLabel")
title.Text,title.Font,title.TextSize="DETECTOR DE COMPRAS",Enum.Font.GothamBold,14
title.TextColor3,title.BackgroundTransparency,title.Active=Color3.new(1,1,1),1,true
title.Position,title.Size,title.Parent=UDim2.fromOffset(10,4),UDim2.fromOffset(230,34),panel
local function button(text,x,y,w,h)
    local b=Instance.new("TextButton")
    b.Text,b.Font,b.TextSize=text,Enum.Font.Gotham,14
    b.TextColor3,b.BackgroundColor3=Color3.new(1,1,1),Color3.fromRGB(66,48,111)
    b.Position,b.Size,b.Parent=UDim2.fromOffset(x,y),UDim2.fromOffset(w,h),panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
    return b
end
local minimize=button("-",246,8,30,28)
local exit=button("X",282,8,28,28)
local potions=button("Pocoes",10,46,142,38)
local floor=button("Floor Upgrades",160,46,150,38)
local stop=button("Parar e copiar",10,92,142,34)
local copy=button("Copiar relatorio",160,92,150,34)
local status=Instance.new("TextLabel")
status.Text,status.Font,status.TextSize="Abra a loja, escolha Pocoes e compre manualmente. Depois teste o piso.",Enum.Font.Gotham,12
status.TextWrapped,status.BackgroundTransparency,status.TextColor3=true,1,Color3.new(1,1,1)
status.Position,status.Size,status.Parent=UDim2.fromOffset(10,132),UDim2.fromOffset(300,88),panel
local mini=Instance.new("TextButton")
mini.Name,mini.Text,mini.TextSize,mini.Font="AbrirDetector","DEBUG",12,Enum.Font.GothamBold
mini.TextColor3,mini.BackgroundColor3=Color3.new(1,1,1),Color3.fromRGB(66,48,111)
mini.Size,mini.Position,mini.Visible,mini.Parent=UDim2.fromOffset(78,44),panel.Position,false,gui
Instance.new("UICorner",mini).CornerRadius=UDim.new(0,8)
local output=Instance.new("TextBox")
output.Text,output.ClearTextOnFocus,output.MultiLine,output.TextWrapped="",false,true,true
output.Font,output.TextSize=Enum.Font.Code,11
output.TextColor3,output.BackgroundColor3=Color3.new(1,1,1),Color3.fromRGB(29,31,40)
output.TextXAlignment,output.TextYAlignment=Enum.TextXAlignment.Left,Enum.TextYAlignment.Top
output.Position,output.Size,output.Visible,output.Parent=UDim2.fromOffset(0,238),UDim2.fromOffset(320,130),false,panel
local function connect(signal,fn,list)
    local c=signal:Connect(fn)
    local target=list or allConnections
    target[#target+1]=c
    return c
end
local function disconnect(list)
    for _,c in ipairs(list) do c:Disconnect() end
    for i=#list,1,-1 do list[i]=nil end
end
local function isOwn(obj) return obj==gui or obj:IsDescendantOf(gui) end
local function root() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end
local function tiny(v)
    local t=typeof(v)
    if t=="number" then return (v==v and v~=math.huge and v~=-math.huge) and v or tostring(v) end
    if t=="boolean" then return v end
    return string.sub(tostring(v),1,160)
end
local function attrs(obj)
    local result,n={},0
    for k,v in pairs(obj:GetAttributes()) do
        n=n+1 if n>14 then break end
        result[k]=tiny(v)
    end
    return result
end
local function color(c)
    return {r=math.floor(c.R*255+0.5),g=math.floor(c.G*255+0.5),b=math.floor(c.B*255+0.5)}
end
local function colorHint(c)
    local h,s,v=c:ToHSV()
    if s<0.25 or v<0.2 then return "other" end
    if h>=0.075 and h<=0.205 then return "yellow" end
    if h>=0.22 and h<=0.48 then return "green" end
    if h<=0.065 or h>=0.94 then return "red" end
    return "other"
end
local function info(obj)
    local d={path=obj:GetFullName(),name=obj.Name,class=obj.ClassName,attributes=attrs(obj)}
    if obj:IsA("BasePart") then
        d.position=tostring(obj.Position) d.size=tostring(obj.Size)
        d.color=color(obj.Color) d.colorHint=colorHint(obj.Color)
        d.canTouch=obj.CanTouch d.transparency=obj.Transparency
        local r=root()
        if r then d.distance=math.floor((r.Position-obj.Position).Magnitude*10)/10 end
    end
    if obj:IsA("TextButton") or obj:IsA("TextLabel") then d.text=string.sub(obj.Text,1,180) end
    return d
end
local function visible(obj)
    local current=obj
    while current and current~=game do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        current=current.Parent
    end
    return true
end
local function potionSnapshot()
    local result={}
    for _,obj in ipairs(pg:GetDescendants()) do
        if not isOwn(obj) and (obj:IsA("TextLabel") or obj:IsA("TextButton")) and visible(obj) then
            local path=obj:GetFullName():lower()
            local text=obj.Text:lower()
            if path:find("potion",1,true) or path:find("pocao",1,true) or path:find("poç",1,true)
                or text:find("restock",1,true) or text:find("estoque",1,true) or text:find("refresh",1,true) then
                result[#result+1]=info(obj)
                if #result>=32 then break end
            end
        end
    end
    return result
end
local function floorNameHint(obj)
    local p=obj
    for _=1,4 do
        if not p or p==workspace or p==game then break end
        local name=p.Name:lower()
        if name:find("upgrade",1,true) or name:find("purchase",1,true)
            or name:find("button",1,true) or name:find("buy",1,true) then return true end
        p=p.Parent
    end
    return false
end
local function floorCandidate(obj)
    if not obj:IsA("BasePart") or not obj.CanTouch or obj.Transparency>=0.95 then return false end
    if floorNameHint(obj) then return true end
    return colorHint(obj.Color)~="other" and obj.Size.X<=40 and obj.Size.Z<=40 and obj.Size.Y<=6
end
local function context(obj)
    local d=info(obj)
    d.parents,d.labels,d.values={},{},{}
    local p=obj.Parent
    for _=1,3 do
        if not p or p==workspace or p==game then break end
        d.parents[#d.parents+1]={path=p:GetFullName(),class=p.ClassName,attributes=attrs(p)}
        p=p.Parent
    end
    local scope=obj.Parent
    if scope and scope~=workspace and scope~=game then
        local count=0
        for _,child in ipairs(scope:GetDescendants()) do
            count=count+1 if count>120 then break end
            if (child:IsA("TextLabel") or child:IsA("TextButton")) and #d.labels<8 then
                d.labels[#d.labels+1]={path=child:GetFullName(),text=string.sub(child.Text,1,120)}
            elseif child:IsA("ValueBase") and #d.values<8 then
                local ok,value=pcall(function() return child.Value end)
                if ok then d.values[#d.values+1]={path=child:GetFullName(),value=tiny(value)} end
            end
        end
    end
    return d
end
local function floorInventory()
    local candidates,totals={}, {yellow=0,red=0,green=0,other=0}
    for _,obj in ipairs(workspace:GetDescendants()) do
        if floorCandidate(obj) then
            candidates[#candidates+1]=obj
            local hint=colorHint(obj.Color)
            totals[hint]=totals[hint]+1
        end
    end
    table.sort(candidates,function(a,b)
        local ha,hb=floorNameHint(a),floorNameHint(b)
        if ha~=hb then return ha end
        return a:GetFullName()<b:GetFullName()
    end)
    local samples={}
    for i=1,math.min(24,#candidates) do samples[#samples+1]=context(candidates[i]) end
    return samples,totals,candidates
end
-- Esta copia executa APENAS operacoes Lua. Nao consulta objetos do Roblox.
local function rawClone(v,depth,seen,budget)
    if type(v)~="table" then return v end
    if depth>=3 or budget.left<=0 then return "[limited table]" end
    if seen[v] then return "[cycle]" end
    seen[v]=true
    local out,count={},0
    for k,item in next,v do
        count=count+1 if count>12 or budget.left<=0 then break end
        budget.left=budget.left-1
        if type(k)=="string" or type(k)=="number" then out[k]=rawClone(item,depth+1,seen,budget) end
    end
    seen[v]=nil
    return out
end
local function pushRaw(s,self,method,...)
    if s.tail-s.head+1>=128 then s.dropped=s.dropped+1 return end
    local args=table.pack(...)
    local budget={left=100}
    local frozen={n=args.n}
    for i=1,math.min(args.n,8) do frozen[i]=rawClone(args[i],0,{},budget) end
    s.tail=s.tail+1
    s.queue[s.tail]={remote=self,method=method,args=frozen,at=os.clock()}
end
local function installCapture()
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then
        return false,"Executor sem hookmetamethod/getnamecallmethod."
    end
    local ok,err=pcall(function()
        if env.__NetoPurchaseHookInstalled then return end
        local original
        local handler=function(self,...)
            local s=env.__NetoPurchaseProbeState
            if s and s.enabled and s.names[self] and not s.busy then
                local method=getnamecallmethod()
                if method=="FireServer" or method=="InvokeServer" then
                    s.busy=true
                    pcall(pushRaw,s,self,method,...)
                    s.busy=false
                end
            end
            -- Preserva argumentos, retornos e a chamada original.
            return original(self,...)
        end
        local wrapped=type(newcclosure)=="function" and newcclosure(handler) or handler
        original=hookmetamethod(game,"__namecall",wrapped)
        env.__NetoPurchaseHookInstalled=true
    end)
    return ok,ok and nil or tostring(err)
end
local function registerRemote(obj)
    if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and not quiet[obj.Name] then
        state.names[obj]={path=obj:GetFullName(),class=obj.ClassName}
    end
end
for _,obj in ipairs(RS:GetDescendants()) do registerRemote(obj) end
connect(RS.DescendantAdded,registerRemote)
local function serial(v,depth)
    local t=typeof(v)
    if t=="nil" then return {type="nil"} end
    if t=="Instance" then return {type=t,path=v:GetFullName(),class=v.ClassName,name=v.Name} end
    if t=="number" or t=="boolean" then return tiny(v) end
    if t=="string" then return string.sub(v,1,180) end
    if t=="table" and depth<4 then
        local out,n={},0
        for k,item in pairs(v) do
            n=n+1 if n>14 then break end
            local key=tostring(k)
            local lower=key:lower()
            if lower:find("token",1,true) or lower:find("password",1,true) then out[key]="[redacted]"
            else out[key]=serial(item,depth+1) end
        end
        return out
    end
    return {type=t,value=string.sub(tostring(v),1,180)}
end
local function drain(session)
    local count=0
    while state.head<=state.tail and count<32 do
        local raw=state.queue[state.head]
        state.queue[state.head]=nil state.head=state.head+1 count=count+1
        local meta=raw and state.names[raw.remote]
        if meta then
            local args={}
            for i=1,math.min(raw.args.n,8) do args[tostring(i)]=serial(raw.args[i],0) end
            local argsJSON=Http:JSONEncode(args)
            if #argsJSON>5000 then
                args={truncated=true,preview=string.sub(argsJSON,1,3500)}
                argsJSON=Http:JSONEncode(args)
            end
            local key=meta.path..raw.method..argsJSON
            local call=session.grouped[key]
            local time=math.floor((raw.at-session.started)*1000)/1000
            if call then call.count=call.count+1 call.last=time
            elseif #session.calls<40 then
                call={path=meta.path,class=meta.class,method=raw.method,args=args,argCount=raw.args.n,first=time,last=time,count=1}
                session.grouped[key]=call
                session.calls[#session.calls+1]=call
            else session.omittedCalls=(session.omittedCalls or 0)+1 end
        end
    end
    if state.head>state.tail then state.queue={} state.head=1 state.tail=0 end
end
local function exportReport()
    local clean={format=report.format,placeId=report.placeId,sessions={},
        note="Observacao somente; chamadas nao comprovam compra. Cores sao pistas, nao regras confirmadas."}
    for name,s in pairs(report.sessions) do
        local d={}
        for k,v in pairs(s) do
            if k~="grouped" and k~="started" and k~="watched" and k~="touchedSet" then
                if type(v)=="table" then
                    local list={} for i,item in ipairs(v) do list[i]=item end
                    -- Copia somente arrays para poder limitar o tamanho sem apagar o original.
                    d[k]=#list>0 and list or v
                else d[k]=v end
            end
        end
        clean.sessions[name]=d
    end
    return clean
end
copyReport=function()
    if recording then drain(recording) end
    local clean=exportReport()
    local payload=Http:JSONEncode(clean)
    for _,field in ipairs({"before","after","remoteInventory","interactions","changes","calls"}) do
        for _,s in pairs(clean.sessions) do
            local list=s[field]
            local minimum=(field=="calls" or field=="interactions") and 2 or 0
            while type(list)=="table" and #payload>50000 and #list>minimum do
                table.remove(list)
                clean.truncated=true
                payload=Http:JSONEncode(clean)
            end
        end
    end
    env.PurchaseDetectorReport=payload
    output.Text=payload
    local ok,result=false,nil
    if type(clip)=="function" then ok,result=pcall(clip,payload) end
    if ok and result~=false then
        status.Text="COPIADO. Faça o outro teste ou cole o relatorio aqui."
        output.Visible=false
    else
        status.Text="Copia automatica indisponivel. Selecione o texto abaixo."
        output.Visible=true panel.Visible=true mini.Visible=false
    end
    return payload
end
stopMode=function(shouldCopy)
    local s=recording
    state.enabled=false
    if s then
        while state.head<=state.tail do drain(s) end
        s.seconds=math.floor((os.clock()-s.started)*100)/100
        s.dropped=state.dropped
        if s.mode=="potions" then s.after=potionSnapshot()
        else s.after,s.colorTotalsAfter=floorInventory() end
    end
    disconnect(modeConnections)
    recording=nil
    mini.Text="COPIAR"
    if shouldCopy then copyReport() end
end
local function addFloorWatch(s,obj)
    if s.watched[obj] then return end
    local n=0 for _ in pairs(s.watched) do n=n+1 end
    if n>=80 then return end
    s.watched[obj]=true
    local previous=obj.Color
    connect(obj:GetPropertyChangedSignal("Color"),function()
        if recording~=s or #s.changes>=35 then return end
        local nextColor=obj.Color
        s.changes[#s.changes+1]={seconds=math.floor((os.clock()-s.started)*100)/100,
            path=obj:GetFullName(),before=color(previous),beforeHint=colorHint(previous),
            after=color(nextColor),afterHint=colorHint(nextColor)}
        previous=nextColor
    end,modeConnections)
end
local function bindCharacter(s,character)
    local function bindPart(part)
        if not part:IsA("BasePart") then return end
        pcall(function()
            connect(part.Touched,function(other)
                if recording~=s or not other or not other:IsA("BasePart") or other:IsDescendantOf(character)
                    or s.touchedSet[other] or #s.interactions>=18 then return end
                if other.Transparency>=0.95 or (not floorNameHint(other) and other.Size.Magnitude>65) then return end
                s.touchedSet[other]=true
                local d=context(other)
                d.seconds=math.floor((os.clock()-s.started)*100)/100
                s.interactions[#s.interactions+1]=d
                addFloorWatch(s,other)
            end,modeConnections)
        end)
    end
    for _,part in ipairs(character:GetDescendants()) do bindPart(part) end
    connect(character.DescendantAdded,bindPart,modeConnections)
end
startMode=function(mode)
    if not alive then return end
    if recording then stopMode(false) end
    local s={mode=mode,started=os.clock(),calls={},interactions={},changes={},grouped={},watched={},touchedSet={}}
    report.sessions[mode]=s
    recording=s
    state.queue={} state.head=1 state.tail=0 state.dropped=0
    local ok,err=installCapture()
    s.captureSupported=ok s.captureError=err
    s.remoteInventory={}
    for _,meta in pairs(state.names) do
        local path=meta.path:lower()
        if path:find("potion",1,true) or path:find("purchase",1,true) or path:find("upgrade",1,true)
            or path:find("shop",1,true) or path:find("stock",1,true) then
            s.remoteInventory[#s.remoteInventory+1]=meta
            if #s.remoteInventory>=30 then break end
        end
    end
    if mode=="potions" then
        s.before=potionSnapshot()
        for _,obj in ipairs(pg:GetDescendants()) do
            if obj:IsA("GuiButton") and not isOwn(obj) then
                connect(obj.Activated,function()
                    if recording~=s or #s.interactions>=12 then return end
                    local d=info(obj)
                    d.seconds=math.floor((os.clock()-s.started)*100)/100
                    if obj.Parent then d.parent=info(obj.Parent) end
                    s.interactions[#s.interactions+1]=d
                end,modeConnections)
            end
        end
    else
        local candidates
        s.before,s.colorTotalsBefore,candidates=floorInventory()
        for i=1,math.min(80,#candidates) do addFloorWatch(s,candidates[i]) end
        if player.Character then bindCharacter(s,player.Character) end
        connect(player.CharacterAdded,function(c) if recording==s then bindCharacter(s,c) end end,modeConnections)
        connect(workspace.DescendantAdded,function(obj)
            if recording==s and obj:IsA("BasePart") then
                task.delay(0.2,function() if recording==s and obj.Parent and floorCandidate(obj) then addFloorWatch(s,obj) end end)
            end
        end,modeConnections)
    end
    state.enabled=ok
    output.Visible=false
    status.Text=ok and "Capturando por 25s. Faça compras MANUAIS. Parar e copiar encerra antes."
        or ("Chamadas indisponiveis: "..tostring(err).." UI e cores continuam sendo registradas.")
    if ok then panel.Visible=false mini.Position=panel.Position mini.Visible=true end
    task.spawn(function()
        while alive and recording==s and os.clock()-s.started<25 do
            drain(s)
            local remaining=math.max(0,math.ceil(25-(os.clock()-s.started)))
            mini.Text=(mode=="potions" and "POCOES" or "FLOOR").."\n"..remaining.."s"
            if ok then status.Text="Capturando "..(mode=="potions" and "pocoes" or "piso")..": "
                ..#s.calls.." chamadas distintas | "..#s.interactions.." interacoes | "..remaining.."s" end
            task.wait(0.15)
        end
        if alive and recording==s then stopMode(true) end
    end)
end
closeDetector=function()
    if not alive then return end
    if recording then stopMode(false) end
    alive=false state.enabled=false
    disconnect(allConnections)
    if env.__NetoPurchaseProbeState==state then env.__NetoPurchaseProbeState=nil end
    gui:Destroy()
end
env.PurchaseDetector={Start=startMode,Stop=function() stopMode(true) end,Copy=copyReport,Close=closeDetector,Report=report}
connect(potions.Activated,function() startMode("potions") end)
connect(floor.Activated,function() startMode("floor") end)
connect(stop.Activated,function() stopMode(true) end)
connect(copy.Activated,copyReport)
connect(exit.Activated,closeDetector)
connect(minimize.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false end)
local dragging,dragInput,dragStart,panelStart
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true dragStart=input.Position panelStart=panel.Position
        dragInput=input.UserInputType==Enum.UserInputType.Touch and input or nil
    end
end)
connect(UIS.InputChanged,function(input)
    if not dragging then return end
    if (dragInput and input==dragInput) or (not dragInput and input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-dragStart
        local camera=workspace.CurrentCamera
        local size=camera and camera.ViewportSize or Vector2.new(1000,700)
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+d.X,0,math.max(0,size.X-320)),
            math.clamp(panelStart.Y.Scale*size.Y+panelStart.Y.Offset+d.Y,0,math.max(0,size.Y-232)))
    end
end)
connect(UIS.InputEnded,function(input)
    if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)
print("Detector separado pronto: Pocoes ou Floor Upgrades. Nenhuma compra automatica e executada.")

