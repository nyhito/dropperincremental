-- Neto Hub / Obsidian UI
-- UI: https://github.com/deividcomsono/Obsidian
-- Docs: https://docs.mspaint.cc/obsidian
-- Autos independentes. Piso orientado a eventos; captura opcional somente durante aprendizado.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
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
    Footer="Neto Hub | v2.0 | Obsidian UI",
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
local panelEntries,panelLimit,panelNextId={},5,0
local scanReplace=nil
local refreshPanelRows,removePanelEntry,startPanelEntry
local panelCandidate,panelCandidateLocator,panelRecording=nil,nil,{}
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
local potions=newFeature("Potions","Buy Potions",10)
local floorUpgrades=newFeature("Floor","Floor Upgrades",0)
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
local Purchases=(function()
local floor,pot=floorUpgrades,potions
local imported=env.PurchaseDetector and env.PurchaseDetector.Report
local importedJSON=env.PurchaseDetectorReport
if env.PurchaseTest and type(env.PurchaseTest.Close)=="function" then pcall(env.PurchaseTest.Close) end
if env.PurchaseDetector and type(env.PurchaseDetector.Close)=="function" then pcall(env.PurchaseDetector.Close) end
floor.templates={}
local stored=env.__NetoFloorTemplates
if type(stored)=="table" and stored.version==2 and stored.placeId==game.PlaceId and type(stored.templates)=="table" then
    floor.templates=stored.templates
end
local cacheFolder="NetoHub/"..tostring(game.PlaceId)
local cacheFile=cacheFolder.."/floor-templates.json"
if #floor.templates==0 and type(readfile)=="function" then
    pcall(function()
        local data=Http:JSONDecode(readfile(cacheFile))
        if data.version==2 and data.placeId==game.PlaceId and type(data.templates)=="table" then floor.templates=data.templates end
    end)
end
local function saveTemplates()
    local data={version=2,placeId=game.PlaceId,templates=floor.templates}
    env.__NetoFloorTemplates=data
    if type(writefile)=="function" and type(makefolder)=="function" then
        pcall(function() makefolder("NetoHub") end)
        pcall(function() makefolder(cacheFolder) end)
        pcall(function() writefile(cacheFile,Http:JSONEncode(data)) end)
    end
end
local function resolvePath(full)
    if type(full)~="string" then return end
    local current
    for name in full:gmatch("[^.]+") do
        if not current then
            if name=="Workspace" then current=workspace
            elseif name=="ReplicatedStorage" then current=RS
            else return end
        else current=current:FindFirstChild(name) if not current then return end end
    end
    return current
end
local index={paths={},objects={},updated=-math.huge}
local learnConnections={}
local startLearning,finishLearning,startFloor,stopFloor
local function disconnect(list)
    for _,c in ipairs(list) do c:Disconnect() end
    for i=#list,1,-1 do list[i]=nil end
end
local function listen(signal,fn,list)
    local c=signal:Connect(fn) list[#list+1]=c return c
end
local function connect(signal,fn,list) return listen(signal,fn,list or learnConnections) end
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
        local obj=index.paths[v.path] or resolvePath(v.path)
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
    if added>0 then saveTemplates() end
    return added
end

if #floor.templates==0 and type(imported)=="table" and imported.sessions then learnData(imported.sessions.floor) end
if #floor.templates==0 and type(importedJSON)=="string" then
    pcall(function() local d=Http:JSONDecode(importedJSON) if d.sessions then learnData(d.sessions.floor) end end)
end
if #floor.templates>0 then saveTemplates() end
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
    capture.enabled=false
    disconnect(learnConnections)
    floor.learning=nil
    if success then
        saveTemplates()
        if floor.enabled then startFloor() end
        notify("Piso aprendido.")
    else notify("Nenhum piso identificado. Use Aprender piso e pise em um amarelo.") end
end
startLearning=function()
    if floor.learning then return end
    local ok,err=enableCapture()
    if not ok then notify(err) return end
    local s={started=os.clock(),calls={},interactions={},touchedSet={}}
    floor.learning=s
    local function bindCharacter(c)
        local function bindPart(part)
            if not part:IsA("BasePart") then return end
            listen(part.Touched,function(other)
                if floor.learning~=s or not other or not other:IsA("BasePart") or other:IsDescendantOf(c)
                    or s.touchedSet[other] or other.Size.Magnitude>70 then return end
                s.touchedSet[other]=true
                if #s.interactions<24 then s.interactions[#s.interactions+1]={path=path(other)} end
            end,learnConnections)
        end
        for _,part in ipairs(c:GetDescendants()) do bindPart(part) end
        listen(c.DescendantAdded,bindPart,learnConnections)
    end
    if player.Character then bindCharacter(player.Character) end
    listen(player.CharacterAdded,bindCharacter,learnConnections)
    notify("Pise em um upgrade amarelo para aprender.")
    task.spawn(function()
        while alive and floor.learning==s and os.clock()-s.started<30 do
            drainLearning(s)
            if #s.calls>0 then
                local ok,added=pcall(learnData,s)
                if ok and added>0 then finishLearning(true) return end
            end
            task.wait(.3)
        end
        if alive and floor.learning==s then finishLearning(false) end
    end)
end
-- Piso: listeners locais e fila de trabalho. Nenhuma varredura periodica do Workspace.
local watchGeneration=0
local scopes={}
local queue,head,tail={},1,0
local pumping=false
local enqueue,pump
local function running(generation)
    return alive and floor.enabled and watchGeneration==generation
end
local function resetQueue() queue={} head=1 tail=0 end
local function disposeRecord(r)
    r.active=false r.queued=false
    disconnect(r.links) disconnect(r.colors)
end
local function disposeScope(state)
    state.active=false
    disconnect(state.links)
    for _,r in pairs(state.records) do disposeRecord(r) end
    state.records={}
end
stopFloor=function()
    watchGeneration=watchGeneration+1
    for _,state in ipairs(scopes) do disposeScope(state) end
    scopes={}
    resetQueue()
end
local function yellowNow(r)
    return r.active and r.item.Parent and r.part and r.part.Parent and r.part.Transparency<.95 and hint(r.part.Color)=="yellow"
end
local function request(r,generation)
    if not running(generation) or not yellowNow(r) then return end
    local t,item=r.template,r.item
    local id
    if t.kind=="name" then id=t.idType=="number" and tonumber(item.Name) or item.Name
    elseif t.kind=="attribute" then id=item:GetAttribute(t.attribute)
    elseif t.kind=="instance" then id=item end
    if id==nil then return end
    local event=r.remote
    if not event or not event.Parent then event=remoteAt(t.remotePath) r.remote=event end
    if not event then return end
    local args=copyData(t.args) setLeaf(args,t.binding,id)
    local values={n=t.argCount}
    for i=1,t.argCount do values[i]=decode(args[tostring(i)]) end
    if not running(generation) or not yellowNow(r) then return end
    if t.method=="FireServer" and event:IsA("RemoteEvent") then event:FireServer(table.unpack(values,1,values.n))
    elseif t.method=="InvokeServer" and event:IsA("RemoteFunction") then event:InvokeServer(table.unpack(values,1,values.n)) end
end
pump=function(generation)
    if pumping then return end
    pumping=true
    task.spawn(function()
        while running(generation) and head<=tail do
            local began,batch=os.clock(),0
            while running(generation) and head<=tail and batch<8 and os.clock()-began<.002 do
                local r=queue[head] queue[head]=nil head=head+1
                r.queued=false batch=batch+1
                if yellowNow(r) and not r.busy then
                    local elapsed=os.clock()-r.last
                    if elapsed>=2 then
                        r.last=os.clock() r.busy=true
                        local turn=r.turn
                        task.spawn(function()
                            local ok,err=pcall(request,r,generation)
                            r.busy=false
                            if not ok and not r.reported then r.reported=true warn("Neto Hub / piso: "..tostring(err)) end
                            if running(generation) and yellowNow(r) and r.turn~=turn then enqueue(r,generation) end
                        end)
                        task.delay(2,function() if running(generation) and yellowNow(r) then enqueue(r,generation) end end)
                    else
                        task.delay(2-elapsed,function() if running(generation) and yellowNow(r) then enqueue(r,generation) end end)
                    end
                end
            end
            if head<=tail then task.wait() end
        end
        pumping=false
        if head>tail then resetQueue() end
        if floor.enabled and alive and head<=tail then pump(watchGeneration) end
    end)
end
enqueue=function(r,generation)
    if not running(generation) or r.queued or not yellowNow(r) then return end
    r.queued=true tail=tail+1 queue[tail]=r
    pump(generation)
end
local function watchItem(state,item,generation)
    if state.records[item] or not state.active or not running(generation) then return end
    local t=state.template
    if not ((t.anchorBasePart and item:IsA("BasePart")) or (not t.anchorBasePart and item.ClassName==t.anchorClass)) then return end
    local r={item=item,template=t,remote=state.remote,links={},colors={},active=true,last=-math.huge,turn=0}
    state.records[item]=r
    local function check()
        local yellow=yellowNow(r)
        if yellow and not r.wasYellow then r.last=-math.huge r.turn=r.turn+1 end
        r.wasYellow=yellow
        if yellow then enqueue(r,generation) end
    end
    local function bindColor()
        if not r.active or not running(generation) then return end
        disconnect(r.colors)
        local part=descend(item,t.colorSteps)
        r.part=part and part:IsA("BasePart") and part or nil
        if r.part then
            listen(r.part:GetPropertyChangedSignal("Color"),check,r.colors)
            listen(r.part:GetPropertyChangedSignal("Transparency"),check,r.colors)
        end
        check()
    end
    local function rebind()
        if r.rebinding then return end r.rebinding=true
        task.spawn(function() task.wait() r.rebinding=false bindColor() end)
    end
    if #t.colorSteps>0 then
        listen(item.DescendantAdded,rebind,r.links)
        listen(item.DescendantRemoving,rebind,r.links)
    end
    if t.kind=="attribute" then listen(item:GetAttributeChangedSignal(t.attribute),check,r.links) end
    bindColor()
end
local function scopeNames(t)
    local names={}
    for name in t.scopePath:gmatch("[^.]+") do names[#names+1]=name end
    if names[1]~="Workspace" then return {} end
    table.remove(names,1) return names
end
local function watchTemplate(t,generation)
    local state={template=t,links={},records={},active=true,remote=remoteAt(t.remotePath),revision=0}
    scopes[#scopes+1]=state
    local rebuild
    local function schedule()
        if state.scheduled or not state.active or not running(generation) then return end
        state.scheduled=true
        task.spawn(function() task.wait() state.scheduled=false if state.active and running(generation) then rebuild() end end)
    end
    rebuild=function()
        if not state.active or not running(generation) then return end
        state.revision=state.revision+1 local revision=state.revision
        disconnect(state.links)
        for _,r in pairs(state.records) do disposeRecord(r) end state.records={}
        local current=workspace
        local names=scopeNames(t)
        if #names==0 then return end
        for _,name in ipairs(names) do
            local parent=current
            listen(parent.ChildAdded,function(child) if child.Name==name then schedule() end end,state.links)
            listen(parent.ChildRemoved,function(child) if child.Name==name then schedule() end end,state.links)
            current=parent:FindFirstChild(name)
            if not current then return end
        end
        state.scope=current
        listen(current.ChildAdded,function(item) watchItem(state,item,generation) end,state.links)
        listen(current.ChildRemoved,function(item)
            local r=state.records[item] if r then disposeRecord(r) state.records[item]=nil end
        end,state.links)
        task.spawn(function()
            local began=os.clock()
            for i,item in ipairs(current:GetChildren()) do
                if not state.active or not running(generation) or revision~=state.revision then return end
                watchItem(state,item,generation)
                if i%24==0 or os.clock()-began>=.002 then task.wait() began=os.clock() end
            end
        end)
    end
    rebuild()
end
startFloor=function()
    stopFloor()
    if #floor.templates==0 then startLearning() return end
    local generation=watchGeneration
    for _,t in ipairs(floor.templates) do watchTemplate(t,generation) end
end
floor.validate=function() return true end
floor.start=startFloor
floor.release=function()
    stopFloor()
    if floor.learning then capture.enabled=false disconnect(learnConnections) floor.learning=nil end
end
pot.validate=function()
    pot.remote=remote("Merchant")
    return pot.remote~=nil,"Merchant nao encontrado."
end
pot.tick=function(token)
    local frames=player:WaitForChild("PlayerGui"):FindFirstChild("Frames")
    local shop=frames and frames:FindFirstChild("Merchant")
    local main=shop and shop:FindFirstChild("Main")
    local slots={}
    if main then
        for _,slot in ipairs(main:GetChildren()) do
            local buttons=slot:FindFirstChild("Buttons")
            local buy=buttons and buttons:FindFirstChild("Buy")
            if slot.Name:match("^Slot%d+$") and buy and buy:IsA("GuiButton") then slots[#slots+1]={name=slot.Name,buy=buy} end
        end
    end
    if #slots==0 then for _,name in ipairs({"Slot1","Slot2","Slot3"}) do slots[#slots+1]={name=name} end end
    for _,slot in ipairs(slots) do
        for attempt=1,40 do
            if not alive or not pot.enabled or pot.token~=token then return end
            local style=slot.buy and slot.buy:GetAttribute("ButtonStyle")
            -- A consulta de 10s tambem testa um estoque cuja UI ficou desatualizada.
            if attempt>1 and style~="Green" then break end
            pot.remote:FireServer("Buy",slot.name)
            task.wait(.2)
        end
    end
end
return {
    Learn=function() startLearning() end,
    CancelLearning=function() if floor.learning then capture.enabled=false disconnect(learnConnections) floor.learning=nil end end,
    Close=function()
        stopFloor() capture.enabled=false disconnect(learnConnections) floor.learning=nil
        if env.__NetoPurchaseProbeState==capture then env.__NetoPurchaseProbeState=nil end
    end,
}
end)()

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
local function resolvePanel(entry)
    local target,locator=entry.target,entry.locator
    if target and locator and target:IsDescendantOf(locator.root) then return target end
    if not locator then return nil end
    local obj=locator.root
    for _,step in ipairs(locator.steps) do
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
    entry.target=obj
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
local function releaseEntry(entry)
    entry.token=(entry.token or 0)+1
    local held=entry.held entry.held=nil
    if held then pcall(function() held:InputHoldEnd() end) end
end
local function replayEntry(entry)
    if scanning then return end
    local obj=resolvePanel(entry)
    if not obj then return end
    if obj:IsA("ProximityPrompt") then
        local _,_,r=body()
        local part=obj:FindFirstAncestorWhichIsA("BasePart")
        if not obj.Enabled or not r or not part or (r.Position-part.Position).Magnitude>obj.MaxActivationDistance then return end
        entry.held=obj
        local token=entry.token
        obj:InputHoldBegin()
        task.wait(math.max(obj.HoldDuration,0))
        if entry.token==token and entry.held==obj then
            entry.held=nil obj:InputHoldEnd()
        end
        return
    end
    if not visible(obj) then return end
    for _,event in ipairs(entry.pattern) do
        if not spam.enabled or not entry.active or not alive or not obj.Parent then break end
        local args=event.args
        if event.name=="MouseButton1Down" or event.name=="MouseButton1Up" then
            local center=obj.AbsolutePosition+obj.AbsoluteSize/2
            args=table.pack(math.floor(center.X),math.floor(center.Y))
        end
        if type(replaySignal)=="function" then
            replaySignal(obj[event.name],table.unpack(args,1,args.n))
        else
            for _,c in ipairs(listConnections(obj[event.name])) do
                local ok,fn=pcall(function() return c.Function end)
                local enabledOK,isEnabled=pcall(function() return c.Enabled end)
                if ok and type(fn)=="function" and not ownCallbacks[fn] and (not enabledOK or isEnabled~=false) then
                    task.spawn(function()
                        if alive and spam.enabled and entry.active then fn(table.unpack(args,1,args.n)) end
                    end)
                end
            end
        end
    end
end
startPanelEntry=function(entry)
    releaseEntry(entry)
    local token=entry.token
    task.spawn(function()
        while alive and spam.enabled and entry.active and entry.token==token do
            local began=os.clock()
            local ok,err=pcall(replayEntry,entry)
            if not ok and not entry.reported then entry.reported=true notify("Spam Button: "..tostring(err)) end
            if entry.token~=token then break end
            task.wait(math.max(0,spam.interval-(os.clock()-began)))
        end
    end)
end
spam.validate=function()
    if #panelEntries==0 then return false,"Selecione pelo menos um botao com Scan." end
    for _,entry in ipairs(panelEntries) do
        local obj=resolvePanel(entry)
        if obj and not obj:IsA("ProximityPrompt") and type(replaySignal)~="function" and type(listConnections)~="function" then
            return false,"Executor sem firesignal/getconnections."
        end
    end
    return true
end
spam.start=function() for _,entry in ipairs(panelEntries) do startPanelEntry(entry) end end
spam.release=function() for _,entry in ipairs(panelEntries) do releaseEntry(entry) end end
removePanelEntry=function(id)
    for i,entry in ipairs(panelEntries) do
        if entry.id==id then
            entry.active=false releaseEntry(entry) table.remove(panelEntries,i)
            if scanReplace==id then scanning=false scanToken=scanToken+1 Window:Toggle(true) end
            if refreshPanelRows then refreshPanelRows() end
            if #panelEntries==0 and spam.enabled then spam.toggle:SetValue(false) end
            return
        end
    end
end

local function intervalControls(box,f)
    box:AddInput(f.id.."Interval",{
        Text="Intervalo",Default=string.format("%.9g",f.interval),Numeric=false,
        Finished=false,ClearTextOnFocus=false,Tooltip="Zero tenta uma vez por frame.",
    })
    box:AddDropdown(f.id.."Unit",{Text="Unidade",Values={"s","ms"},Default="s"})
end
local tabs={
    Droppers=Window:AddTab("Droppers","mouse-pointer-click"),
    CombatTree=Window:AddTab("Combate / Tree","swords"),
    Purchases=Window:AddTab("Coins / Compras","shopping-cart"),
    Spam=Window:AddTab("Spam Button","scan"),
}
local layout={
    {f=cash,tab=tabs.Droppers,side="Left"},
    {f=bronze,tab=tabs.Droppers,side="Left"},
    {f=combat,tab=tabs.CombatTree,side="Left"},
    {f=tree,tab=tabs.CombatTree,side="Left"},
    {f=coins,tab=tabs.Purchases,side="Left"},
    {f=floorUpgrades,tab=tabs.Purchases,side="Left"},
    {f=potions,tab=tabs.Purchases,side="Right"},
    {f=spam,tab=tabs.Spam,side="Left"},
}
local panelListBox,rows={},{}
for _,item in ipairs(layout) do
    local f=item.f
    local control=item.tab:AddGroupbox({Side=item.side,Name=f.title})
    control:AddToggle(f.id.."Enabled",{Text=f.title,Default=false})
    f.toggle=Toggles[f.id.."Enabled"]
    if f~=floorUpgrades and f~=potions then intervalControls(control,f) end
    if f==coins then
        control:AddSlider("CoinsBatch",{Text="Moedas por lote",Default=25,Min=1,Max=50,Rounding=0})
        control:AddInput("CoinsRetry",{Text="Repetir pedido pendente (s)",Default="3",Numeric=false,Finished=false,ClearTextOnFocus=false})
    elseif f==floorUpgrades then
        control:AddButton("Aprender piso",function() Purchases.Learn() end)
    elseif f==spam then
        control:AddInput("PanelLimit",{Text="Limite de botoes",Default="5",Numeric=false,Finished=true,ClearTextOnFocus=false})
        control:AddButton("Scan / adicionar",function() env.NetoHubStartScan() end)
        control:AddButton("Cancelar Scan",function()
            scanning=false scanToken=scanToken+1 scanReplace=nil
            panelCandidate,panelCandidateLocator,panelRecording=nil,nil,{}
            Window:Toggle(true)
        end)
        panelListBox=tabs.Spam:AddGroupbox({Side="Right",Name="Botoes selecionados"})
    end
end
refreshPanelRows=function()
    for _,row in ipairs(rows) do row:Destroy() end
    rows={}
    for i,entry in ipairs(panelEntries) do
        local obj=resolvePanel(entry)
        local name=obj and ((obj:IsA("TextButton") and obj.Text~="") and obj.Text or obj.Name) or entry.name
        name=tostring(name):gsub("<","&lt;"):gsub(">","&gt;")
        rows[#rows+1]=panelListBox:AddLabel(tostring(i)..". "..string.sub(name,1,90).."\n"..entry.path,true)
        local action=panelListBox:AddButton("Substituir #"..i,function() env.NetoHubStartScan(entry.id) end)
        action:AddButton({Text="X",Func=function() removePanelEntry(entry.id) end})
        rows[#rows+1]=action
    end
end
Options.PanelLimit:OnChanged(function()
    local n=tonumber(Options.PanelLimit.Value)
    if not n or n~=n or n%1~=0 or n<1 or n>50 then notify("O limite deve ser um inteiro entre 1 e 50.") Options.PanelLimit:SetValue(tostring(panelLimit)) return end
    if n<#panelEntries then notify("Remova botoes antes de reduzir o limite para "..n..".") Options.PanelLimit:SetValue(tostring(panelLimit)) return end
    panelLimit=n
end)
local settingsTab=Window:AddTab("Settings","settings")
local menu=settingsTab:AddGroupbox({Side="Left",Name="Menu",IconName="settings"})
menu:AddButton("Minimizar / abrir",function() Window:Toggle() end)
menu:AddButton("Desligar todos",function() if stopAll then stopAll() end end)
menu:AddDropdown("DPIScale",{Text="DPI Scale",Values={"50%","65%","75%","85%","100%","125%","150%"},Default="100%"})
menu:AddToggle("CustomCursor",{Text="Custom Cursor",Default=false})
menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind",{Default="RightShift",NoUI=true,Text="Mostrar / ocultar menu"})
Library.ToggleKeybind=Options.MenuKeybind
menu:AddButton("Unload / fechar tudo",function() Library:Unload() end)

setFeature=function(f,on)
    if not alive then return end
    if f.enabled==on then return end
    if not on then
        f.enabled=false
        f.token=f.token+1
        if f.release then f.release() end
        f.phase="Desligado"
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
    f.enabled=true
    f.token=f.token+1
    local token=f.token
    f.phase="Ligando"
    if f.start then
        local success,err=pcall(f.start)
        if not success then f.toggle:SetValue(false) notify(f.title..": "..tostring(err)) end
        return
    end
    task.spawn(function()
        while alive and f.enabled and f.token==token do
            local began=os.clock()
            local success,err=pcall(f.tick,token)
            if not success then
                f.error=tostring(err)
                f.toggle:SetValue(false)
                f.phase="Erro: "..f.error
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
    if Purchases then Purchases.CancelLearning() end
    for _,f in ipairs(ordered) do f.toggle:SetValue(false) end
end
for _,f in ipairs(ordered) do
    f.toggle:OnChanged(function() setFeature(f,f.toggle.Value) end)
    if Options[f.id.."Interval"] then
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
    local target,locator,pattern=panelCandidate,panelCandidateLocator or makeLocator(panelCandidate),panelRecording
    panelCandidate,panelCandidateLocator,panelRecording=nil,nil,{}
    scanning=false
    Window:Toggle(true)
    if not locator then notify("Nao foi possivel guardar esse botao.") return end
    local replaceIndex
    for i,entry in ipairs(panelEntries) do
        if entry.id==scanReplace then replaceIndex=i end
        if entry.target==target and entry.id~=scanReplace then notify("Esse botao ja esta na lista.") scanReplace=nil return end
    end
    if not replaceIndex and #panelEntries>=panelLimit then notify("Limite atingido.") scanReplace=nil return end
    if replaceIndex then
        local previous=panelEntries[replaceIndex]
        previous.active=false releaseEntry(previous)
    end
    panelNextId=panelNextId+1
    local entry={id=panelNextId,target=target,locator=locator,pattern=pattern,active=true,token=0,
        name=target.Name,path=target:GetFullName():gsub("<","&lt;"):gsub(">","&gt;")}
    if replaceIndex then panelEntries[replaceIndex]=entry else panelEntries[#panelEntries+1]=entry end
    scanReplace=nil
    refreshPanelRows()
    if spam.enabled then startPanelEntry(entry) end

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
env.NetoHubStartScan=function(replaceId)
    if scanning then notify("Conclua ou cancele o Scan atual.") return end
    if not replaceId and #panelEntries>=panelLimit then notify("Limite de botoes atingido.") return end
    scanReplace=replaceId
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
        SaveManager:SetIgnoreIndexes({"CashEnabled","BronzeEnabled","CoinsEnabled","CombatEnabled","TreeEnabled","SpamEnabled","PotionsEnabled","FloorEnabled","MenuKeybind"})
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
    Purchases.Close()
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
env.NetoHub={Features=features,Library=Library,Window=Window,StopAll=stopAll,
    PanelEntries=panelEntries,RemovePanel=removePanelEntry,StartScan=env.NetoHubStartScan}
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
notify("Neto Hub pronto.")
