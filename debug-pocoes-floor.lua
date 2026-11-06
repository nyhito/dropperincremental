-- Teste separado de Buy Potions e Floor Upgrades.
-- Nome preservado: debug-pocoes-floor.lua. Nao altera o hub.
-- Pocoes: chamada confirmada Merchant:FireServer("Buy", "SlotN").
-- Piso: importa o debug salvo ou aprende UMA compra manual; nunca adivinha IDs/eventos.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local player=Players.LocalPlayer
assert(player,"Execute no cliente.")
assert(game.PlaceId==70960300100792,"Jogo diferente do configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
local imported=env.PurchaseDetector and env.PurchaseDetector.Report
local importedJSON=env.PurchaseDetectorReport
if env.PurchaseDetector and type(env.PurchaseDetector.Close)=="function" then pcall(env.PurchaseDetector.Close) end
if env.PurchaseTest and type(env.PurchaseTest.Close)=="function" then pcall(env.PurchaseTest.Close) end
local alive=true
local connections,learnConnections={},{}
local pot={on=false,sent=0,last={},phase="OFF",slots={}}
local floor={on=false,sent=0,last={},phase="OFF",yellow=0,templates={},learning=nil,lastCalls={}}
local stored=env.__NetoFloorTemplates
if type(stored)=="table" and stored.version==2 and stored.placeId==game.PlaceId then floor.templates=stored.templates end
local index={paths={},objects={},updated=-math.huge}
local togglePot,toggleFloor,startLearning,finishLearning,copyStatus,close
local gui=Instance.new("ScreenGui")
gui.Name,gui.ResetOnSpawn,gui.DisplayOrder="PurchaseTest",false,10021
gui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame")
panel.Size,panel.Position=UDim2.fromOffset(330,258),UDim2.new(0,12,0.17,0)
panel.BackgroundColor3,panel.Parent=Color3.fromRGB(21,23,30),gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,10)
local title=Instance.new("TextLabel")
title.Text,title.Font,title.TextSize="COMPRAS / TESTE SEPARADO",Enum.Font.GothamBold,13
title.TextColor3,title.BackgroundTransparency,title.Active=Color3.new(1,1,1),1,true
title.Position,title.Size,title.Parent=UDim2.fromOffset(10,4),UDim2.fromOffset(240,30),panel
local function button(text,x,y,w,h)
    local b=Instance.new("TextButton")
    b.Text,b.Font,b.TextSize=text,Enum.Font.Gotham,13
    b.TextColor3,b.BackgroundColor3=Color3.new(1,1,1),Color3.fromRGB(66,49,110)
    b.Position,b.Size,b.Parent=UDim2.fromOffset(x,y),UDim2.fromOffset(w,h),panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
    return b
end
local min=button("-",258,7,28,27)
local exit=button("X",292,7,28,27)
local potButton=button("Buy Potions: OFF",10,44,310,36)
local floorButton=button("Floor Upgrades: OFF",10,88,310,36)
local learnButton=button("Aprender 1 piso",10,132,146,32)
local copyButton=button("Copiar status",164,132,156,32)
local label=Instance.new("TextLabel")
label.Text,label.Font,label.TextSize="Preparando...",Enum.Font.Gotham,12
label.TextWrapped,label.TextXAlignment,label.TextYAlignment=true,Enum.TextXAlignment.Left,Enum.TextYAlignment.Top
label.TextColor3,label.BackgroundTransparency=Color3.new(1,1,1),1
label.Position,label.Size,label.Parent=UDim2.fromOffset(10,174),UDim2.fromOffset(310,76),panel
local mini=Instance.new("TextButton")
mini.Text,mini.Font,mini.TextSize="COMPRAS",Enum.Font.GothamBold,11
mini.TextColor3,mini.BackgroundColor3=Color3.new(1,1,1),Color3.fromRGB(66,49,110)
mini.Position,mini.Size,mini.Visible,mini.Parent=panel.Position,UDim2.fromOffset(80,42),false,gui
Instance.new("UICorner",mini).CornerRadius=UDim.new(0,8)
local output=Instance.new("TextBox")
output.Text,output.ClearTextOnFocus,output.MultiLine,output.TextWrapped="",false,true,true
output.Font,output.TextSize=Enum.Font.Code,11
output.TextColor3,output.BackgroundColor3=Color3.new(1,1,1),Color3.fromRGB(29,31,39)
output.TextXAlignment,output.TextYAlignment=Enum.TextXAlignment.Left,Enum.TextYAlignment.Top
output.Position,output.Size,output.Visible,output.Parent=UDim2.fromOffset(0,264),UDim2.fromOffset(330,120),false,panel
local function connect(signal,fn,list)
    local c=signal:Connect(fn)
    local destination=list or connections
    destination[#destination+1]=c
    return c
end
local function disconnect(list)
    for _,c in ipairs(list) do c:Disconnect() end
    for i=#list,1,-1 do list[i]=nil end
end
local function path(obj) return obj:GetFullName() end
local function remoteAt(full)
    local remotes=RS:FindFirstChild("Remotes")
    if not remotes then return nil end
    for _,obj in ipairs(remotes:GetDescendants()) do
        if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and path(obj)==full then return obj end
    end
end
local function rebuildIndex(force)
    if not force and os.clock()-index.updated<1 then return end
    index.paths,index.objects={},{}
    for _,obj in ipairs(workspace:GetDescendants()) do
        index.paths[path(obj)]=obj
        if obj:IsA("BasePart") or obj:IsA("Model") then index.objects[#index.objects+1]=obj end
    end
    index.updated=os.clock()
end
local function hint(c)
    local h,s,v=c:ToHSV()
    if s<.25 or v<.2 then return "other" end
    if h>=.075 and h<=.205 then return "yellow" end
    if h>=.22 and h<=.48 then return "green" end
    if h<=.065 or h>=.94 then return "red" end
    return "other"
end
local function copyData(v)
    if typeof(v)=="Instance" or type(v)~="table" then return v end
    local t={} for k,x in pairs(v) do t[k]=copyData(x) end return t
end
local function serial(v,depth)
    local t=typeof(v)
    if t=="nil" then return {type="nil"} end
    if t=="Instance" then return {type=t,path=path(v),class=v.ClassName,name=v.Name} end
    if t=="number" then
        if v~=v or v==math.huge or v==-math.huge then return tostring(v) end
        return v
    end
    if t=="boolean" then return v end
    if t=="string" then return string.sub(v,1,180) end
    if t=="table" and depth<4 then
        local out,n={},0
        for k,x in pairs(v) do n=n+1 if n>14 then break end out[tostring(k)]=serial(x,depth+1) end
        return out
    end
    return {type=t,value=tostring(v)}
end
local function decode(v)
    if typeof(v)=="Instance" then return v end
    if type(v)~="table" then return v end
    if v.type=="nil" then return nil end
    if v.type=="Instance" then
        local obj=index.paths[v.path]
        assert(obj,"Instancia de argumento nao carregada: "..tostring(v.path))
        return obj
    end
    assert(v.type==nil,"Tipo de argumento nao calibrado: "..tostring(v.type))
    local out={}
    local numeric,n=true,0
    for k in pairs(v) do n=n+1 if not tonumber(k) then numeric=false end end
    for k,x in pairs(v) do out[numeric and tonumber(k) or k]=decode(x) end
    return out
end
local function setLeaf(t,keys,value)
    local current=t
    for i=1,#keys-1 do current=current[keys[i]] end
    current[keys[#keys]]=value
end
local function leaves(v,keys,result,depth)
    if depth>4 then return end
    if type(v)=="table" and v.type==nil then
        for k,x in pairs(v) do
            local nextKeys={} for i,key in ipairs(keys) do nextKeys[i]=key end
            nextKeys[#nextKeys+1]=k
            leaves(x,nextKeys,result,depth+1)
        end
    elseif type(v)=="string" or type(v)=="number" or (type(v)=="table" and v.type=="Instance") then
        result[#result+1]={keys=keys,value=v}
    end
end
local generic={button=true,part=true,model=true,main=true,buy=true,upgrade=true,purchase=true,upgrades=true,
    baseplate=true,touch=true,hitbox=true,board=true,floor=true}
local idAttributes={id=true,upgradeid=true,purchaseid=true,key=true,upgrade=true,purchase=true,name=true,index=true}
local function matchIdentifier(obj,value)
    if type(value)=="table" and value.type=="Instance" then
        if value.path==path(obj) then return "instance",nil end
        return
    end
    if (type(value)~="string" and type(value)~="number") or generic[tostring(value):lower()] then return end
    if obj.Name==tostring(value) then return "name",nil end
    for key,x in pairs(obj:GetAttributes()) do
        if idAttributes[key:lower()] and x==value then return "attribute",key end
    end
end
local function relative(root,obj)
    local steps={}
    while obj and obj~=root do
        local parent=obj.Parent
        if not parent then return nil end
        local ordinal=0
        for _,sibling in ipairs(parent:GetChildren()) do
            if sibling.Name==obj.Name and sibling.ClassName==obj.ClassName then ordinal=ordinal+1 end
            if sibling==obj then break end
        end
        table.insert(steps,1,{name=obj.Name,class=obj.ClassName,index=ordinal})
        obj=parent
    end
    return obj==root and steps or nil
end
local function descend(root,steps)
    local current=root
    for _,step in ipairs(steps) do
        local found,count=nil,0
        for _,child in ipairs(current:GetChildren()) do
            if child.Name==step.name and child.ClassName==step.class then
                count=count+1 if count==step.index then found=child break end
            end
        end
        if not found then return nil end
        current=found
    end
    return current
end
local function anchorsFrom(data)
    local out,seen={},{}
    local function add(obj)
        local current=obj
        for _=1,4 do
            if not current or current==workspace or current==game then break end
            if not seen[current] and (current:IsA("BasePart") or current:IsA("Model") or current:IsA("Folder")) then
                seen[current]=true out[#out+1]=current
            end
            current=current.Parent
        end
    end
    for obj in pairs(data.touchedSet or {}) do if typeof(obj)=="Instance" then add(obj) end end
    for _,entry in ipairs(data.interactions or {}) do if entry.path then add(index.paths[entry.path]) end end
    for _,entry in ipairs(data.changes or {}) do if entry.path then add(index.paths[entry.path]) end end
    for _,entries in ipairs({data.before or {},data.after or {}}) do
        for _,entry in ipairs(entries) do
            if entry.colorHint=="yellow" or entry.colorHint=="green" or entry.colorHint=="red" then add(index.paths[entry.path]) end
        end
    end
    return out
end
local function colorSource(anchor,anchors)
    if anchor:IsA("BasePart") and anchor.Transparency<.95 and hint(anchor.Color)~="other" then return anchor end
    for _,obj in ipairs(anchors) do
        if obj:IsA("BasePart") and obj:IsDescendantOf(anchor) and obj.Transparency<.95 and hint(obj.Color)~="other" then return obj end
    end
    local best,score=nil,-1
    local n=0
    for _,obj in ipairs(anchor:GetDescendants()) do
        n=n+1 if n>100 then break end
        if obj:IsA("BasePart") and obj.CanTouch and obj.Transparency<.95 and hint(obj.Color)~="other" then
            local name=obj.Name:lower()
            local weight=(name:find("button",1,true) or name=="main" or name:find("pad",1,true)) and 10 or 1
            if weight>score then best,score=obj,weight end
        end
    end
    return best
end
local function purchaseCall(call)
    local p=tostring(call.path or ""):lower()
    return (call.method=="FireServer" or call.method=="InvokeServer") and not p:find("merchant",1,true)
        and (p:find("purchase",1,true) or p:find("upgrade",1,true) or p:find("buy",1,true) or p:find("unlock",1,true))
end
local function templateKey(t)
    return t.remotePath.."|"..t.scopePath.."|"..t.kind.."|"..tostring(t.attribute).."|"..Http:JSONEncode(t.binding)
        .."|"..Http:JSONEncode(t.colorSteps)
end
local function learnData(data)
    if type(data)~="table" then return 0 end
    rebuildIndex(false)
    local anchors=anchorsFrom(data)
    local added=0
    for _,call in ipairs(data.calls or {}) do
        if purchaseCall(call) and type(call.args)=="table" then
            local options={} leaves(call.args,{},options,0)
            local found=false
            for _,leaf in ipairs(options) do
                for _,anchor in ipairs(anchors) do
                    local kind,attribute=matchIdentifier(anchor,leaf.value)
                    local part=kind and colorSource(anchor,anchors)
                    if part and anchor.Parent and anchor.Parent~=workspace and anchor.Parent~=game then
                        local steps=relative(anchor,part)
                        if steps then
                            local count=call.argCount or 0
                            if count==0 then for key in pairs(call.args) do count=math.max(count,tonumber(key) or 0) end end
                            local t={remotePath=call.path,method=call.method,args=copyData(call.args),argCount=count,
                                binding=leaf.keys,kind=kind,attribute=attribute,scopePath=path(anchor.Parent),
                                anchorClass=anchor.ClassName,anchorBasePart=anchor:IsA("BasePart"),
                                colorSteps=steps,idType=type(leaf.value),sourceId=type(leaf.value)=="table" and leaf.value.path or leaf.value}
                            local valid=pcall(function()
                                for i=1,count do decode(t.args[tostring(i)]) end
                            end)
                            if valid then
                                local key=templateKey(t)
                                local exists=false for _,old in ipairs(floor.templates) do if templateKey(old)==key then exists=true break end end
                                if not exists then floor.templates[#floor.templates+1]=t added=added+1 end
                                found=true break
                            end
                        end
                    end
                end
                if found then break end
            end
        end
    end
    env.__NetoFloorTemplates={version=2,placeId=game.PlaceId,templates=floor.templates}
    return added
end
-- Aproveita os dados completos que o detector anterior guardou no executor.
if type(imported)=="table" and imported.sessions then learnData(imported.sessions.floor) end
if type(importedJSON)=="string" then
    local ok,data=pcall(function() return Http:JSONDecode(importedJSON) end)
    if ok and type(data)=="table" and data.sessions then learnData(data.sessions.floor) end
end
local function merchantMain()
    local frames=player:WaitForChild("PlayerGui"):FindFirstChild("Frames")
    local shop=frames and frames:FindFirstChild("Merchant")
    return shop and shop:FindFirstChild("Main"),shop
end
local function potionSlots()
    local result={}
    local main=merchantMain()
    if main then
        for _,slot in ipairs(main:GetChildren()) do
            local buttons=slot:FindFirstChild("Buttons")
            local buy=buttons and buttons:FindFirstChild("Buy")
            if slot.Name:match("^Slot%d+$") and buy and buy:IsA("GuiButton") then
                result[#result+1]={name=slot.Name,style=buy:GetAttribute("ButtonStyle") or "Unknown"}
            end
        end
    end
    if #result==0 then
        for _,name in ipairs({"Slot1","Slot2","Slot3"}) do result[#result+1]={name=name,style="Unknown"} end
    end
    table.sort(result,function(a,b) return (tonumber(a.name:match("%d+")) or 0)<(tonumber(b.name:match("%d+")) or 0) end)
    return result
end
local function potionTick()
    local remotes=RS:FindFirstChild("Remotes")
    local merchant=remotes and remotes:FindFirstChild("Merchant")
    if not merchant or not merchant:IsA("RemoteEvent") then pot.phase="Aguardando Merchant" return end
    local slots=potionSlots()
    pot.slots=slots
    local sent=0
    for _,slot in ipairs(slots) do
        if not pot.on or not alive then break end
        -- Green: esvazia o estoque. Demais estilos: consulta moderada para notar reposicao mesmo com a loja fechada.
        local delay=slot.style=="Green" and .4 or 4
        if not pot.last[slot.name] or os.clock()-pot.last[slot.name]>=delay then
            merchant:FireServer("Buy",slot.name)
            pot.last[slot.name]=os.clock()
            pot.sent=pot.sent+1 sent=sent+1
        end
    end
    pot.phase=sent>0 and "Comprando / consultando estoque" or "Aguardando estoque / reposicao"
end
local function floorTick()
    if #floor.templates==0 then floor.phase="Precisa aprender 1 piso" return end
    rebuildIndex(false)
    local yellow,batch=0,0
    for _,t in ipairs(floor.templates) do
        local scope=index.paths[t.scopePath]
        local remote=remoteAt(t.remotePath)
        if scope and remote then
            for _,item in ipairs(scope:GetChildren()) do
                if not floor.on or not alive then return end
                local correct=t.anchorBasePart and item:IsA("BasePart") or (not t.anchorBasePart and item.ClassName==t.anchorClass)
                local colorPart=correct and descend(item,t.colorSteps)
                if colorPart and colorPart:IsA("BasePart") and colorPart.Transparency<.95 and hint(colorPart.Color)=="yellow" then
                    yellow=yellow+1
                    local id
                    if t.kind=="name" then id=t.idType=="number" and tonumber(item.Name) or item.Name
                    elseif t.kind=="attribute" then id=item:GetAttribute(t.attribute)
                    elseif t.kind=="instance" then id=item end
                    if id~=nil then
                        local key=t.remotePath.."|"..path(item)
                        if not floor.last[key] or os.clock()-floor.last[key]>=2 then
                            local args=copyData(t.args)
                            setLeaf(args,t.binding,id)
                            local values={n=t.argCount}
                            for i=1,t.argCount do values[i]=decode(args[tostring(i)]) end
                            if t.method=="FireServer" and remote:IsA("RemoteEvent") then remote:FireServer(table.unpack(values,1,values.n))
                            elseif t.method=="InvokeServer" and remote:IsA("RemoteFunction") then remote:InvokeServer(table.unpack(values,1,values.n))
                            else error("Tipo de evento do piso mudou.") end
                            floor.last[key]=os.clock() floor.sent=floor.sent+1 batch=batch+1
                            floor.lastAttempt={path=path(item),remote=t.remotePath}
                            if batch>=4 then floor.yellow=yellow floor.phase="Solicitando amarelos" return end
                        end
                    end
                end
            end
        end
    end
    floor.yellow=yellow
    floor.phase=yellow>0 and "Solicitando amarelos" or "Aguardando amarelos na familia aprendida"
end
-- Captura de calibracao: reutiliza o observador anterior, se disponivel.
-- O caminho critico apenas copia dados Lua; nao executa consultas do Roblox.
local capture={enabled=false,names={},queue={},head=1,tail=0,dropped=0,busy=false}
local function rawClone(v,depth,seen,budget)
    if type(v)~="table" then return v end
    if depth>=3 or budget.left<=0 or seen[v] then return "[limited]" end
    seen[v]=true local out,n={},0
    for k,x in next,v do
        n=n+1 if n>12 or budget.left<=0 then break end
        budget.left=budget.left-1
        if type(k)=="string" or type(k)=="number" then out[k]=rawClone(x,depth+1,seen,budget) end
    end
    seen[v]=nil return out
end
local function pushRaw(s,self,method,...)
    if s.tail-s.head+1>=128 then s.dropped=s.dropped+1 return end
    local args=table.pack(...) local frozen={n=args.n} local budget={left=100}
    for i=1,math.min(args.n,8) do frozen[i]=rawClone(args[i],0,{},budget) end
    s.tail=s.tail+1 s.queue[s.tail]={remote=self,method=method,args=frozen,at=os.clock()}
end
local function enableCapture()
    local remotes=RS:FindFirstChild("Remotes")
    if not remotes then return false,"Pasta Remotes indisponivel." end
    capture.names={}
    for _,obj in ipairs(remotes:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local name=obj.Name:lower()
            if name~="merchant" and (name:find("purchase",1,true) or name:find("upgrade",1,true)
                or name:find("buy",1,true) or name:find("unlock",1,true)) then
                capture.names[obj]={path=path(obj),class=obj.ClassName}
            end
        end
    end
    env.__NetoPurchaseProbeState=capture
    if not env.__NetoPurchaseHookInstalled then
        if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then
            return false,"Executor sem captura de chamadas. Copie o status."
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
    capture.queue={} capture.head=1 capture.tail=0 capture.dropped=0 capture.enabled=true
    return true
end
local function drainLearning(s)
    local n=0
    while capture.head<=capture.tail and n<32 do
        local raw=capture.queue[capture.head]
        capture.queue[capture.head]=nil capture.head=capture.head+1 n=n+1
        local meta=raw and capture.names[raw.remote]
        if meta and #s.calls<40 then
            local args={}
            for i=1,math.min(raw.args.n,8) do args[tostring(i)]=serial(raw.args[i],0) end
            s.calls[#s.calls+1]={path=meta.path,method=raw.method,args=args,argCount=raw.args.n,
                first=raw.at-s.started,last=raw.at-s.started}
        end
    end
    if capture.head>capture.tail then capture.queue={} capture.head=1 capture.tail=0 end
end
finishLearning=function(success)
    local s=floor.learning
    capture.enabled=false
    if s then while capture.head<=capture.tail do drainLearning(s) end floor.lastCalls=s.calls end
    disconnect(learnConnections)
    floor.learning=nil
    learnButton.Text="Aprender 1 piso"
    if success then
        floor.on=s and s.resume or false
        floor.phase="Piso aprendido: "..#floor.templates.." familia(s)"
    else floor.on=false floor.phase="Sem mapeamento. Pise num amarelo durante Aprender." end
    floorButton.Text=floor.on and "Floor Upgrades: ON" or "Floor Upgrades: OFF"
end
startLearning=function(resume)
    if floor.learning then finishLearning(false) end
    floor.on=false floorButton.Text="Floor Upgrades: aprendendo"
    local ok,err=enableCapture()
    if not ok then floor.phase=err floorButton.Text="Floor Upgrades: OFF" return end
    local s={started=os.clock(),resume=resume,calls={},interactions={},touchedSet={}}
    floor.learning=s
    floor.phase="Pise manualmente em UM upgrade amarelo."
    learnButton.Text="Aprendendo..."
    local function bindCharacter(c)
        local function bindPart(part)
            if not part:IsA("BasePart") then return end
            pcall(function()
                connect(part.Touched,function(other)
                    if floor.learning~=s or not other or not other:IsA("BasePart")
                        or other:IsDescendantOf(c) or s.touchedSet[other] or other.Size.Magnitude>70 then return end
                    s.touchedSet[other]=true
                    if #s.interactions<24 then s.interactions[#s.interactions+1]={path=path(other)} end
                end,learnConnections)
            end)
        end
        for _,obj in ipairs(c:GetDescendants()) do bindPart(obj) end
        connect(c.DescendantAdded,bindPart,learnConnections)
    end
    if player.Character then bindCharacter(player.Character) end
    connect(player.CharacterAdded,bindCharacter,learnConnections)
    task.spawn(function()
        while alive and floor.learning==s and os.clock()-s.started<30 do
            drainLearning(s)
            if #s.calls>0 then
                local before=#floor.templates
                learnData(s)
                if #floor.templates>before then finishLearning(true) return end
            end
            task.wait(.3)
        end
        if alive and floor.learning==s then finishLearning(false) end
    end)
end
togglePot=function()
    pot.on=not pot.on pot.phase=pot.on and "Ligando" or "OFF"
    potButton.Text=pot.on and "Buy Potions: ON" or "Buy Potions: OFF"
end
toggleFloor=function()
    if floor.learning then finishLearning(false) return end
    floor.on=not floor.on
    if floor.on and #floor.templates==0 then startLearning(true) return end
    floor.phase=floor.on and "Ligando" or "OFF"
    floorButton.Text=floor.on and "Floor Upgrades: ON" or "Floor Upgrades: OFF"
end
copyStatus=function()
    local templates={}
    for _,t in ipairs(floor.templates) do
        templates[#templates+1]={remote=t.remotePath,scope=t.scopePath,kind=t.kind,attribute=t.attribute,
            binding=t.binding,colorSteps=t.colorSteps,sourceId=t.sourceId}
    end
    local data={format="purchase-test-v2",placeId=game.PlaceId,potions={on=pot.on,phase=pot.phase,sent=pot.sent,slots=pot.slots},
        floor={on=floor.on,phase=floor.phase,sent=floor.sent,yellowKnown=floor.yellow,templates=templates,
            lastAttempt=floor.lastAttempt,calls={}}}
    local calls=floor.learning and floor.learning.calls or floor.lastCalls
    for i=1,math.min(6,#calls) do data.floor.calls[i]=calls[i] end
    local payload=Http:JSONEncode(data)
    local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard
    local ok,result=false,nil
    if type(clip)=="function" then ok,result=pcall(clip,payload) end
    output.Text=payload output.Visible=not (ok and result~=false)
    if output.Visible then panel.Visible=true mini.Visible=false end
    env.PurchaseTestReport=payload
    return payload
end
close=function()
    if not alive then return end
    pot.on,floor.on=false,false
    if floor.learning then finishLearning(false) end
    capture.enabled=false
    if env.__NetoPurchaseProbeState==capture then env.__NetoPurchaseProbeState=nil end
    alive=false disconnect(connections) gui:Destroy()
end
env.PurchaseTest={Close=close,TogglePotions=togglePot,ToggleFloor=toggleFloor,Learn=function() startLearning(true) end,
    Copy=copyStatus,Potions=pot,Floor=floor}
connect(potButton.Activated,togglePot)
connect(floorButton.Activated,toggleFloor)
connect(learnButton.Activated,function() startLearning(true) end)
connect(copyButton.Activated,copyStatus)
connect(exit.Activated,close)
connect(min.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false end)
local dragging,inputStart,panelStart,dragInput
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true inputStart=input.Position panelStart=panel.Position
        dragInput=input.UserInputType==Enum.UserInputType.Touch and input or nil
    end
end)
connect(UIS.InputChanged,function(input)
    if not dragging then return end
    if (dragInput and input==dragInput) or (not dragInput and input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-inputStart
        local size=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000,700)
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+d.X,0,math.max(0,size.X-330)),
            math.clamp(panelStart.Y.Scale*size.Y+panelStart.Y.Offset+d.Y,0,math.max(0,size.Y-258)))
    end
end)
connect(UIS.InputEnded,function(input)
    if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)
task.spawn(function()
    while alive do
        if pot.on then
            local ok,err=pcall(potionTick)
            if not ok then pot.on=false pot.phase="Erro: "..tostring(err) potButton.Text="Buy Potions: OFF" end
        end
        task.wait(.15)
    end
end)
task.spawn(function()
    while alive do
        if floor.on then
            local ok,err=pcall(floorTick)
            if not ok then floor.on=false floor.phase="Erro: "..tostring(err) floorButton.Text="Floor Upgrades: OFF" end
        end
        task.wait(.4)
    end
end)
task.spawn(function()
    while alive do
        label.Text="Pocoes: "..pot.phase.."\nPiso: "..floor.phase.."\nPedidos: "..pot.sent.." / "..floor.sent
            .." | Familias: "..#floor.templates.." | Amarelos: "..floor.yellow
        task.wait(.3)
    end
end)
print("Teste separado pronto: Buy Potions e Floor Upgrades. Os dois iniciam OFF.")
