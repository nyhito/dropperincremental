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
    Footer="Neto Hub | v2.3 | Obsidian UI",
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
local autoFish=newFeature("Fishing","Auto Fish",.001)
local autoDig=newFeature("Dig","Auto Dig",0)
local antiAFK=newFeature("AntiAFK","Anti-AFK",0)
antiAFK.default=true
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
local pumping,scheduled=false,false
local pending={}
local budgetAt,budgetUsed,budgetCost=-math.huge,0,0
local wakeScheduled=false
local enqueue,pump,wakePending
local function dispatchBudget()
    local now=os.clock()
    if now-budgetAt>=.016 then budgetAt=now budgetUsed=0 budgetCost=0 end
    return budgetUsed<24 and budgetCost<.002
end
local function running(generation)
    return alive and floor.enabled and watchGeneration==generation
end
local function resetQueue() queue={} head=1 tail=0 end
local function disposeRecord(r)
    r.active=false r.queued=false pending[r]=nil r.retryTicket=(r.retryTicket or 0)+1
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
    pending={}
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
local function retryLater(r,generation)
    if not running(generation) or not yellowNow(r) then return end
    r.retryTicket=(r.retryTicket or 0)+1
    local ticket=r.retryTicket
    local delay=r.retryDelay or .08
    r.retryDelay=math.min(delay*2,.5)
    task.delay(delay,function()
        if r.retryTicket==ticket and running(generation) and yellowNow(r) then enqueue(r,generation) end
    end)
end
local function dispatch(r,generation)
    r.busy=true r.again=false
    r.last=os.clock()
    local function send()
        local began=os.clock()
        local ok,err=pcall(request,r,generation)
        if r.template.method=="FireServer" then budgetCost=budgetCost+(os.clock()-began) end
        r.busy=false
        if not ok and not r.reported then r.reported=true warn("Neto Hub / piso: "..tostring(err)) end
        if not running(generation) or not yellowNow(r) then return end
        if r.again then r.again=false enqueue(r,generation) else retryLater(r,generation) end
    end
    -- FireServer nao espera resposta: dispara no proprio evento de cor/aparecimento.
    -- InvokeServer tem seu proprio trabalho para nunca bloquear os outros pisos.
    local event=r.remote
    if event and event:IsA("RemoteEvent") then send() else task.spawn(send) end
end
pump=function(generation)
    if pumping or not running(generation) then return end
    pumping=true
    while running(generation) and head<=tail and dispatchBudget() do
        local r=queue[head] queue[head]=nil head=head+1 r.queued=false
        if yellowNow(r) then
            if r.busy then r.again=true
            else
                budgetUsed=budgetUsed+1
                r.retryTicket=(r.retryTicket or 0)+1
                dispatch(r,generation)
            end
        end
    end
    pumping=false
    if head>tail then resetQueue() end
    if head<=tail and not scheduled then
        scheduled=true
        task.spawn(function()
            task.wait() scheduled=false
            if floor.enabled and alive then pump(watchGeneration) end
        end)
    end
end
enqueue=function(r,generation)
    if not running(generation) or r.queued or not yellowNow(r) then return end
    pending[r]=true
    r.queued=true tail=tail+1 queue[tail]=r
    pump(generation)
end
-- Uma compra pode liberar varios amarelos que ja tinham um pedido pendente.
-- Reavalia apenas esses registros, sem percorrer o mapa ou esperar o retry antigo.
wakePending=function(generation)
    if wakeScheduled or not running(generation) then return end
    wakeScheduled=true
    local defer=task.defer or task.spawn
    defer(function()
        wakeScheduled=false
        if not running(generation) then return end
        local list={} for r in pairs(pending) do list[#list+1]=r end
        local n,began=0,os.clock()
        for _,r in ipairs(list) do
            if not running(generation) then return end
            if yellowNow(r) then
                r.retryDelay=.08
                enqueue(r,generation)
                n=n+1
                if n%24==0 or os.clock()-began>=.002 then task.wait() began=os.clock() end
            else pending[r]=nil end
        end
    end)
end
local function watchItem(state,item,generation)
    if state.records[item] or not state.active or not running(generation) then return end
    local t=state.template
    if not ((t.anchorBasePart and item:IsA("BasePart")) or (not t.anchorBasePart and item.ClassName==t.anchorClass)) then return end
    local r={item=item,template=t,remote=state.remote,links={},colors={},active=true,last=-math.huge,turn=0}
    state.records[item]=r
    local function check()
        local yellow=yellowNow(r)
        local wasYellow=r.wasYellow
        if yellow and not wasYellow then r.last=-math.huge r.turn=r.turn+1 r.retryDelay=.08 end
        r.wasYellow=yellow
        if yellow then
            if not wasYellow then enqueue(r,generation) end
        else
            pending[r]=nil r.retryTicket=(r.retryTicket or 0)+1
            if wasYellow then wakePending(generation) end
        end
    end
    local function bindColor()
        if not r.active or not running(generation) then return end
        disconnect(r.colors)
        local part=descend(item,t.colorSteps)
        local nextPart=part and part:IsA("BasePart") and part or nil
        if nextPart~=r.part then r.wasYellow=false r.retryTicket=(r.retryTicket or 0)+1 end
        r.part=nextPart
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
        listen(item.DescendantAdded,bindColor,r.links)
        listen(item.DescendantRemoving,rebind,r.links)
    end
    if t.kind=="attribute" then listen(item:GetAttributeChangedSignal(t.attribute),function() r.wasYellow=false check() end,r.links)
    elseif t.kind=="name" then listen(item:GetPropertyChangedSignal("Name"),function() r.wasYellow=false check() end,r.links) end
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
        task.spawn(function() state.scheduled=false if state.active and running(generation) then rebuild() end end)
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
            local r=state.records[item] if r then local wasYellow=r.wasYellow disposeRecord(r) state.records[item]=nil if wasYellow then wakePending(generation) end end
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

-- Controlador de pesca incorporado; sem janela secundaria ou download do debug.
local function createFishingController(onChanged)
local UIS=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local fishing,fishingConnection=nil,nil
local function overlayParent()
    for gui in pairs(ownedGuis) do if gui.Parent then return gui.Parent end end
    return player:FindFirstChild("PlayerGui")
end
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
local pulse=nil
local frameDuration=1/60
local lastRecovery=-math.huge
local hookAttempts=0
local completionSent,held=false,false
local inputEpoch,injecting=0,0
local activeInput=nil
local virtualInputAt=-math.huge
local virtualX,virtualY=nil,nil
local modes,modeIndex={},1
local modeFault,inputWorking=false,false
local autoOwned=false
local geometry={}
local toggle,close,setHeld,click,chooseMode
local restoreMobile
local mobileToken={}
env.__NetoFishingMobileToken=mobileToken
local mobileDevice=false
pcall(function() mobileDevice=UIS.TouchEnabled==true end)
local restoreGeneration=0
local report={format="fishing-controller-v9-reactive-mobile",placeId=game.PlaceId,
    note="Conta Caught recebido enquanto ligado; nao distingue ajuda manual. Clica ate confirmar Cast, espera Bite e fisga. Barra acompanhada desde a abertura. Queda/mordida nao removidas.",
    caught=0,escaped=0,castsAccepted=0,bites=0,clicks=0,holdChanges=0,catchRequests=0,recoveries=0,holdResyncs=0,
    events={},catches={},inputErrors={},capabilities={},interval=interval}
local function connect(signal,fn)
    ownCallbacks[fn]=true
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
    report.events[#report.events+1]=e
    if #report.events>32 then table.remove(report.events,1) end
end
local function rod()
    local c=player.Character
    if not c then return end
    local h=c:FindFirstChild("Humanoid") if h and h.Health<=0 then return end
    if rodCache and rodCache.Parent==c then return rodCache end
    local t=c:FindFirstChild("FishingRod")
    rodCache=t and t.Parent==c and t:IsA("Tool") and t or nil
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
    local checked={}
    for _,root in ipairs(rootList) do
        if root and root~=workspace and not checked[root] then
            checked[root]=true
            local ok,hits=pcall(function() return root:GetGuiObjectsAtPosition(x,y) end)
            if ok and type(hits)=="table" then
                for _,obj in ipairs(hits) do
                    local belongs=ownUI(obj)
                    local a=obj
                    for _=1,10 do
                        if not a or a==root then break end
                        if a:IsA("GuiObject") and not a.Visible then break end
                        if a:IsA("GuiButton") or a:IsA("TextBox") then return false end
                        if a.Name=="NetoFishingMobileRestore" then return false end
                        -- Floats/Overlay da Obsidian ocupam a tela toda, mas nao consomem entrada.
                        if belongs and a:IsA("GuiObject") and (a.Active==true or (a.BackgroundTransparency or 0)<.99) then return false end
                        a=a.Parent
                    end
                end
            end
        end
    end
    return true
end
local function position()
    local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000,700)
    if os.clock()-clickPoint.at<.35 and view.X==clickPoint.vx and view.Y==clickPoint.vy and clickPoint.x and pointIsFree(clickPoint.x,clickPoint.y) then
        return clickPoint.x,clickPoint.y
    end
    clickPoint.at=os.clock() clickPoint.vx=view.X clickPoint.vy=view.Y
    clickPoint.x,clickPoint.y=nil,nil
    for _,point in ipairs({{.78,.30},{.94,.32},{.985,.24},{.985,.42},{.995,.55},{.65,.36},{.53,.34},{.42,.38},{.78,.47},{.6,.48},{.52,.21},{.42,.23}}) do
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
local function release(force)
    inputEpoch=inputEpoch+1
    pulse=nil
    if force and not activeInput then
        local x,y=virtualX,virtualY
        if not x then x,y=position() end
        if x then activeInput={x=x,y=y} end
    end
    if held or (force and activeInput) then setHeld(false,true) end
    held=false activeInput=nil
end
chooseMode=function(reason)
    -- Troca somente depois de erro real da API, nunca por demora do servidor ou borda da barra.
    release(true) record("input","Switch",reason)
    modeIndex=modeIndex+1
    if modeIndex>#modes then
        enabled=false phase="Clique virtual indisponivel. Copie o resultado."
        if restoreMobile then restoreMobile() end
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
    if pulse or held then return false end
    lastClick=os.clock() nextClick=lastClick+interval
    local epoch=inputEpoch
    if not setHeld(true) then return false end
    report.clicks=report.clicks+1 attemptsSinceCheck=attemptsSinceCheck+1
    if stage=="hooking" then hookAttempts=hookAttempts+1 nextClick=lastClick+math.max(interval,.18) end
    if reason then record("input",reason) end
    -- Um frame pressionado e outro solto. Evita que o mobile junte os dois estados.
    -- A soltura e processada no RenderStepped, sem tasks atrasadas de cliques antigos.
    if enabled and epoch==inputEpoch then pulse={releaseAt=os.clock()+.008,epoch=epoch} end
    return true
end
local function resetCycle(reason)
    release()
    cycle=cycle+1 stage="idle" stateAt=os.clock() castAt=nil biteAt=nil hookAt=nil
    autoOwned=false completionSent=false geometry={} hookAttempts=0
    nextClick=os.clock()+math.min(frameDuration,.04) phase=reason or "Aguardando"
end
local function controlBar(dt)
    local bar=reelBar()
    local track=bar and bar:FindFirstChild("Track")
    local lane=track and track:FindFirstChild("Lane")
    local zone=lane and lane:FindFirstChild("Zone")
    local fish=lane and lane:FindFirstChild("Fish")
    if not lane or not zone or not fish or lane.AbsoluteSize.X<=0 or zone.AbsoluteSize.X<=0 then
        phase="Aguardando os elementos da barra" return
    end
    local left,width=lane.AbsolutePosition.X,lane.AbsoluteSize.X
    local zx=(zone.AbsolutePosition.X+zone.AbsoluteSize.X*.5-left)/width
    local fx=(fish.AbsolutePosition.X+fish.AbsoluteSize.X*.5-left)/width
    local zw=math.clamp(zone.AbsoluteSize.X/width,.01,1)
    dt=math.clamp(dt or 1/60,.004,.08)
    local t=os.clock() local g=geometry
    g.started=g.started or t
    local movement=g.zone and zx-g.zone or 0
    local zv=g.zone and movement/dt or 0
    local fv=g.fish and (fx-g.fish)/dt or 0
    g.zv=(g.zv or 0)*.45+math.clamp(zv,-4,4)*.55
    g.fv=(g.fv or 0)*.6+math.clamp(fv,-4,4)*.4
    -- O centro da zona nao pode ultrapassar as bordas reais da pista.
    local minX,maxX=zw*.5,1-zw*.5
    local target=math.clamp(fx+g.fv*.025,minX,maxX)
    local projected=zx+g.zv*.03
    local error=target-projected
    local dead=math.clamp(zw*.015,.0025,.007)
    local desired=held
    if error>dead then desired=true elseif error< -dead then desired=false end
    local wanted=desired
    if g.releaseUntil and t<g.releaseUntil then desired=false end
    if desired~=held then g.commandAt=t end
    if not setHeld(desired) then
        if pointBlocked then phase="Ponto de clique coberto pela interface" g.lastMove=t
        elseif chooseMode("Segurar/soltar recusado") then setHeld(desired,true) end
    end
    if math.abs(movement)>.0006 then
        g.lastMove=t inputWorking=true
        if not g.firstResponseAt and ((wanted and movement>0) or (not wanted and movement<0)) then g.firstResponseAt=t end
    end
    g.lastMove=g.lastMove or t
    local atLimit=(wanted and zx>=maxX-.04) or (not wanted and zx<=minX+.04)
    local needsMotion=math.abs(error)>math.max(dead*2,.012)
    local wrongWay=(wanted and g.zv<-.08) or (not wanted and g.zv>.08)
    local commandSettled=t-(g.commandAt or g.started)>.12
    -- Detecta comando perdido inclusive quando o peixe ainda esta DENTRO da zona larga.
    if needsMotion and not atLimit and commandSettled and (t-g.lastMove>.16 or wrongWay)
        and t-(g.lastResync or -math.huge)>.3 then
        release(true) g.commandAt=t g.lastResync=t g.lastMove=t
        g.releaseUntil=t+math.min(frameDuration*.75,.03)
        report.holdResyncs=report.holdResyncs+1
    end
    g.zone,g.fish,g.width=zx,fx,zw
    g.error=error g.inside=math.abs(fx-zx)<=zw*.5
    local _,percent=progress()
    if percent then g.peak=math.max(g.peak or 0,percent) if percent<99 then g.sawBelowFull=true end end
    report.controller={t=now(),fish=fx,zone=zx,width=zw,held=held,inside=g.inside,peak=g.peak,inputWorking=inputWorking,
        firstResponseMs=g.firstResponseAt and math.floor((g.firstResponseAt-g.started)*1000+.5)}
end
local function onServer(action,...)
    if not alive then return end
    if enabled then record("server",action,...) end
    if not enabled then return end
    local args=table.pack(...)
    if action=="Cast" then
        if autoOwned and rod() then
            stage="waitingBite" stateAt=os.clock()
            castAt=castAt or os.clock() inputWorking=true castCheckAt=os.clock()
            report.castsAccepted=report.castsAccepted+1
            release(true) phase="Vara lancada; aguardando !"
        end
    elseif action=="Bite" then
        report.bites=report.bites+1 biteAt=os.clock()
        if autoOwned and rod() then
            stage="hooking" stateAt=os.clock() phase="Fisgando"
            hookAt=os.clock() hookAttempts=0 release(true) nextClick=os.clock()+math.min(frameDuration,.04)
            record("input","Hook agendado no !")
        end
    elseif action=="Caught" then
        -- Touch sintetico no mobile nao identifica autoria. Conta apenas o evento real,
        -- sem classificar centenas de eventos injetados como intervencao manual.
        report.caught=report.caught+1
            report.catches[#report.catches+1]={t=now(),fish=safe(args[1],0,{left=8}),value2=safe(args[2],0,{left=8}),
                value3=safe(args[3],0,{left=8}),autoFlag=args[4],seconds=castAt and os.clock()-castAt,
                localPeak=geometry.peak,mode=modes[modeIndex] and modes[modeIndex].name,
                firstResponseMs=geometry.firstResponseAt and math.floor((geometry.firstResponseAt-geometry.started)*1000+.5)}
            if #report.catches>8 then table.remove(report.catches,1) end
        resetCycle("Captura confirmada; relancando")
        castCheckAt=os.clock() attemptsSinceCheck=0
    elseif action=="Escaped" then
        report.escaped=report.escaped+1 resetCycle("Peixe escapou; relancando")
        castCheckAt=os.clock() attemptsSinceCheck=0
    end
end
local function bindRemote()
    local folder=RS:FindFirstChild("Remotes")
    local current=folder and folder:FindFirstChild("Fishing")
    if current and not current:IsA("RemoteEvent") then current=nil end
    if current~=fishing then
        if fishingConnection then fishingConnection:Disconnect() fishingConnection=nil end
        fishing=current
    end
    if fishing and not fishingConnection then fishingConnection=connect(fishing.OnClientEvent,onServer) end
    return fishing~=nil
end
restoreMobile=function()
    if not mobileDevice then return end
    restoreGeneration=restoreGeneration+1
    local generation=restoreGeneration
    local result={requested=true,status="restoring",nativeTouch=false,errors={}}
    report.mobileRestore=result
    local function valid()
        return not enabled and generation==restoreGeneration and env.__NetoFishingMobileToken==mobileToken
    end
    local function forceGui()
        pcall(function() game:GetService("GuiService").TouchControlsEnabled=true result.touchControlsEnabled=true end)
        local pg=player:FindFirstChild("PlayerGui") local touch=pg and pg:FindFirstChild("TouchGui")
        if touch then
            touch.Enabled=true
            local frame=touch:FindFirstChild("TouchControlFrame")
            if frame then
                frame.Visible=true
                local jump=frame:FindFirstChild("JumpButton",true)
                if jump then jump.Visible=true end
            end
            result.touchGuiVisible=true
        end
    end
    forceGui()
    task.spawn(function()
        if not valid() then return end
        -- Seleciona novamente os controles de toque do PlayerModule, incluindo o pulo.
        local ok,err=pcall(function()
            local ps=player:FindFirstChild("PlayerScripts")
            local module=ps and ps:FindFirstChild("PlayerModule")
            if not module then return end
            local playerModule=require(module)
            if not valid() then return end
            local controls=type(playerModule.GetControls)=="function" and playerModule:GetControls()
            if not controls then return end
            if type(controls.OnLastInputTypeChanged)=="function" then controls:OnLastInputTypeChanged(Enum.UserInputType.Touch)
            elseif type(controls.OnPreferredInputChanged)=="function" then controls:OnPreferredInputChanged(Enum.PreferredInput.Touch) end
            if type(controls.SelectTouchModule)=="function" and type(controls.SwitchToController)=="function" then
                local selected=controls:SelectTouchModule()
                if selected then controls:SwitchToController(selected) result.controllerSelected=true end
            end
            if type(controls.Enable)=="function" then controls:Enable(true) end
            if controls.touchJumpController and type(controls.touchJumpController.Enable)=="function" then
                controls.touchJumpController:Enable(true,controls.touchControlFrame) result.jumpEnabled=true
            end
            if controls.touchControlFrame then controls.touchControlFrame.Visible=true end
        end)
        if not ok then result.errors[#result.errors+1]=tostring(err):sub(1,140) end
    end)
    task.spawn(function()
        task.wait(.025)
        if not valid() then return end
        -- Toque consumido por uma Frame vazia: muda o dispositivo sem clicar no jogo.
        local vim,sendTouch
        pcall(function() vim=game:GetService("VirtualInputManager") sendTouch=vim.SendTouchEvent end)
        if type(sendTouch)=="function" then
            local pg=player:FindFirstChild("PlayerGui")
            local shield=Instance.new("ScreenGui") shield.Name="NetoFishingMobileRestore"
            shield.IgnoreGuiInset=true shield.ResetOnSpawn=false shield.DisplayOrder=2147483000 shield.Parent=overlayParent() or pg
            ownedGuis[shield]=true
            local frame=Instance.new("Frame") frame.Name="InputShield" frame.Size=UDim2.new(1,0,1,0)
            frame.BackgroundTransparency=1 frame.Active=true frame.Parent=shield
            local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000,700)
            local x,y=math.floor(view.X*.5),math.floor(view.Y*.4)
            local id=900000+math.floor(os.clock()*1000)%100000
            local sent,message=pcall(sendTouch,vim,id,0,x,y)
            if sent then task.wait(.03)
            elseif #result.errors<3 then result.errors[#result.errors+1]=tostring(message):sub(1,140) end
            -- Encerra o dedo mesmo com cancelamento ou erro parcial no envio inicial.
            local ended=pcall(sendTouch,vim,id,2,x,y)
            result.nativeTouch=sent and ended
            ownedGuis[shield]=nil shield:Destroy()
        end
        for _,delay in ipairs({0,.1,.25}) do
            if delay>0 then task.wait(delay) end
            if not valid() then result.status="cancelled" return end
            forceGui()
        end
        pcall(function() result.lastInput=tostring(UIS:GetLastInputType()) end)
        pcall(function() result.preferredInput=tostring(UIS.PreferredInput) end)
        result.status="done"
    end)
end
toggle=function(value)
    if not alive then return end
    if value==nil then value=not enabled end
    restoreGeneration=restoreGeneration+1
    release(true) enabled=value==true resetCycle(enabled and "Chegue perto do lago" or "OFF")
    if enabled and not bindRemote() then enabled=false phase="Fishing indisponivel." end
    if enabled then
        refreshModes() castCheckAt=os.clock() attemptsSinceCheck=0
        if #modes==0 then enabled=false phase="Executor sem clique virtual. Copie o resultado." restoreMobile()
        elseif rod() then phase="Clicando rapido para lancar"
        else phase="Auto ligado; aproxime-se do lago para equipar a vara" end
    else restoreMobile() end
    if onChanged then onChanged(enabled,phase) end
end
local lastRod=nil
local function recover(reason)
    if os.clock()-lastRecovery<3 then return end
    lastRecovery=os.clock() report.recoveries=report.recoveries+1
    release(true) resetCycle(reason) castCheckAt=os.clock() attemptsSinceCheck=0
    nextClick=os.clock()+.1 record("recovery",reason)
end
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
    frameDuration=math.clamp(dt or 1/60,.004,.1)
    local tool=rod()
    if not tool then
        if autoOwned or held then resetCycle("Aguardando vara perto do lago") end
        lastRod=nil castCheckAt=os.clock() attemptsSinceCheck=0
        phase="Aguardando vara perto do lago" return
    end
    local focused=nil pcall(function() focused=UIS:GetFocusedTextBox() end)
    if focused then release() phase="Pausado enquanto voce usa o painel" castCheckAt=os.clock() return end
    if tool~=lastRod then release() lastRod=tool castCheckAt=os.clock() attemptsSinceCheck=0 end
    if modeFault then if not chooseMode("Falha no clique virtual") then return end end
    local shown,n=progress()
    if shown then
        if pulse then release() end
        if stage~="reeling" and stage~="waitingCaught" then
            -- A fisgada e o primeiro segurar nao podem ocupar o mesmo frame.
            release(true) stage="reeling" stateAt=os.clock()
            geometry={started=os.clock(),releaseUntil=os.clock()+math.min(frameDuration*.75,.03)} completionSent=false
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
        if os.clock()-stateAt>4 then recover("Sem confirmacao; soltando e relancando") end
    end
    if stage=="idle" then
        cycle=cycle+1 autoOwned=true stage="casting" stateAt=os.clock() castAt=os.clock()
        geometry={} completionSent=false phase="Clicando rapido para lancar"
    end
    -- Soltar ocupa seu proprio frame. Nenhum novo press vem nesta mesma passagem.
    if pulse then
        if pulse.epoch~=inputEpoch or os.clock()>=pulse.releaseAt then release() end
        return
    end
    if stage=="casting" and os.clock()-castCheckAt>8 and attemptsSinceCheck>10 then
        recover("Lançamento demorou; soltando e tentando novamente")
    elseif stage=="waitingBite" then
        phase="Vara lancada; aguardando !"
        if os.clock()-stateAt>15 then recover("Sem mordida; soltando e tentando relancar") end
    elseif stage=="hooking" and os.clock()-stateAt>4 then
        recover("Sem barra; soltando e tentando relancar")
    end
    -- Para ao confirmar o lancamento. A proxima entrada e somente na mordida.
    if stage=="casting" and os.clock()>=nextClick then click()
    elseif stage=="hooking" and hookAttempts<4 and os.clock()>=nextClick then click("Hook no !") end
end
connect(Run.RenderStepped,function(dt)
    if not enabled then return end
    local ok,err=pcall(step,dt)
    if not ok then report.error=tostring(err) toggle(false) phase="Erro. Copie o resultado." end
    if not enabled and onChanged then onChanged(false,phase) end
end)

close=function()
    if not alive then return end
    toggle(false) alive=false
    for _,c in ipairs(links) do c:Disconnect() end
end
return {
    Toggle=toggle,Close=close,RestoreMobile=restoreMobile,Report=report,
    IsEnabled=function() return enabled end,
    SetInterval=function(seconds)
        interval=math.clamp(tonumber(seconds) or .001,.001,3)
        report.interval=interval
    end,
    Validate=function() return bindRemote(),"Fishing nao encontrado." end,
}
end
local FishingController=nil
local function getFishingController()
    if not FishingController then
        -- Encerra a versao avulsa para nao haver dois controladores de entrada.
        for _,name in ipairs({"FishingDebug","FishingAutoTest"}) do
            if env[name] and type(env[name].Close)=="function" then pcall(env[name].Close) end
        end
        FishingController=createFishingController(function(on,reason)
            if autoFish.toggle and autoFish.toggle.Value~=on then autoFish.toggle:SetValue(on) end
            if not on and reason and reason~="OFF" then notify("Auto Fish: "..reason) end
        end)
    end
    return FishingController
end
autoFish.validate=function()
    if not remote("Fishing") then return false,"Fishing nao encontrado." end
    return getFishingController().Validate()
end
autoFish.start=function()
    local controller=getFishingController()
    controller.SetInterval(autoFish.interval) controller.Toggle(true)
end
autoFish.release=function() if FishingController then FishingController.Toggle(false) end end
autoFish.updateInterval=function(seconds) if FishingController then FishingController.SetInterval(seconds) end end

-- Auto Dig incorporado: TP e Dig imediato fazem parte do mesmo controle.
-- Nenhuma janela de debug, alteracao da faixa ou clique de tela.
local function createDigController(onChanged)
    local Run=game:GetService("RunService")
    local active,closed=false,false
    local generation=0
    local links,markerLinks={},{}
    local eventRemote,eventConnection=nil,nil
    local refs,state={},{}
    local busy=false
    local pulse,toggle,onServer
    local report={build="hub-dig-3.2",enabled=false,tp=true,digs=0,strikes=0,confirmedHits=0,misses=0,foundWhileEnabled=0,teleports=0,timeouts=0,phase="OFF"}
    local function phase(text) report.phase=text autoDig.phase=text end
    local function disconnect(list) for _,c in ipairs(list) do c:Disconnect() end for i=#list,1,-1 do list[i]=nil end end
    local function listen(signal,fn,list)
        ownCallbacks[fn]=true local c=signal:Connect(fn) local into=list or links into[#into+1]=c return c
    end
    local function shown(obj)
        local p=obj
        for _=1,16 do
            if not p then return false end
            if p:IsA("GuiObject") and not p.Visible then return false end
            if p:IsA("ScreenGui") then return p.Enabled end
            p=p.Parent
        end
        return false
    end
    local function graph()
        local pg=player:FindFirstChild("PlayerGui") local front=pg and pg:FindFirstChild("Front")
        local main=front and front:FindFirstChild("MainFrame") local hud=main and main:FindFirstChild("TreasureHUD")
        local track=hud and hud:FindFirstChild("Track") local zone=track and track:FindFirstChild("Zone")
        local needle=track and track:FindFirstChild("Needle")
        if needle~=refs.needle then
            disconnect(markerLinks)
            if needle then
                local token=generation
                local function changed() if active and generation==token and pulse then pulse() end end
                listen(needle:GetPropertyChangedSignal("Position"),changed,markerLinks)
                listen(needle:GetPropertyChangedSignal("Visible"),changed,markerLinks)
            end
        end
        refs={hud=hud,track=track,zone=zone,needle=needle,checked=os.clock()}
        return hud,track,zone,needle
    end
    local function geometry()
        if not refs.track or not refs.track.Parent or os.clock()-(refs.checked or 0)>.25 then graph() end
        local t,z,n=refs.track,refs.zone,refs.needle
        if not t or not z or not n or not shown(z) or not shown(n) or t.AbsoluteSize.X<=0 then return end
        local cursor,lo,width,margin
        if n.Parent==t and z.Parent==t and n.Position.X.Offset==0 and n.Size.X.Offset==0 and z.Position.X.Offset==0 and z.Size.X.Offset==0 then
            width=z.Size.X.Scale lo=z.Position.X.Scale-z.AnchorPoint.X*width
            cursor=n.Position.X.Scale+(.5-n.AnchorPoint.X)*n.Size.X.Scale margin=.006
        else
            width=z.AbsoluteSize.X/t.AbsoluteSize.X lo=(z.AbsolutePosition.X-t.AbsolutePosition.X)/t.AbsoluteSize.X
            cursor=(n.AbsolutePosition.X+n.AbsoluteSize.X*.5-t.AbsolutePosition.X)/t.AbsoluteSize.X margin=.025
        end
        return cursor,lo,width,math.min(margin,width*.08)
    end
    local function bindRemote()
        local current=remote("TreasureHunting")
        if current~=eventRemote then
            if eventConnection then eventConnection:Disconnect() eventConnection=nil end
            eventRemote=current
        end
        if current and not eventConnection and active then
            local token=generation
            eventConnection=listen(current.OnClientEvent,function(...)
                if active and generation==token then
                    local ok,err=pcall(onServer,...)
                    if not ok then report.error=tostring(err) toggle(false) phase("Erro no Auto Dig") if onChanged then onChanged(false,report.error) end end
                end
            end)
        end
        return current
    end
    local function send(action,...)
        if not active then return false end
        local r=bindRemote() if not r then phase("TreasureHunting indisponivel") return false end
        r:FireServer(action,...) return true
    end
    local function sync(urgent)
        if os.clock()-(state.lastSync or -math.huge)<(urgent and .05 or .25) then return end
        state.lastSync=os.clock() send("Sync")
    end
    local function requestDig()
        if not active or not state.spot or state.layer then return end
        local now=os.clock() local retry=math.clamp((state.rtt or .06)*2+.02,.12,.3)
        if now-(state.lastDig or -math.huge)<retry then return end
        state.lastDig=now phase("Iniciando Dig") report.digs=report.digs+1
        report.spotToDigMs=math.floor((now-state.spot.receivedAt)*1000+.5)
        send("Dig")
    end
    local function jump()
        if not active or not state.spot or state.jumpedKey==state.spot.key then return end
        local _,_,root=body() if not root then phase("Aguardando personagem") return end
        local p=state.spot.position
        if (root.Position-p).Magnitude>500 then phase("Aguardando a area do detector") return end
        local y=math.abs(root.Position.Y-p.Y)<8 and root.Position.Y or p.Y+3
        root.CFrame=CFrame.new(p.X,y,p.Z)*root.CFrame.Rotation
        root.AssemblyLinearVelocity=Vector3.new(0,0,0)
        state.jumpedKey=state.spot.key report.teleports=report.teleports+1
        requestDig()
    end
    onServer=function(action,...)
        local a=table.pack(...)
        if action=="Spot" and typeof(a[2])=="Vector3" then
            local p=a[2] local key=tostring(a[1])..string.format("/%.3f/%.3f",p.X,p.Z)
            if not state.spot or state.spot.key~=key then
                state.spot={key=key,id=a[1],position=p,receivedAt=os.clock()}
                state.layer=nil state.pending=nil state.jumpedKey=nil state.lastDig=-math.huge
                report.spot={id=a[1],x=p.X,y=p.Y,z=p.Z}
            end
            jump()
        elseif action=="Layer" and (type(a[1])=="number" or type(a[1])=="string") and type(a[2])=="number" then
            local key=tostring(a[1]).."/"..tostring(a[3]).."/"..tostring(a[2])
            if not state.layer or state.layer.key~=key then
                state.layer={id=a[1],started=a[2],index=a[3],center=a[4],width=a[5],key=key,receivedAt=os.clock(),armed=true}
                state.pending=nil phase("Aguardando o verde")
            end
            graph()
        elseif action=="Hit" then
            local p=state.pending state.pending=nil
            if p and state.layer and p.key==state.layer.key then
                local rtt=os.clock()-p.at state.rtt=state.rtt and state.rtt*.75+rtt*.25 or rtt
                if a[1]==true then state.layer.completed=true state.layer.hitAt=os.clock() report.confirmedHits=report.confirmedHits+1
                else state.layer.armed=false state.layer.retryAfter=os.clock()+.15 report.misses=report.misses+1 end
            end
        elseif action=="Found" then
            report.foundWhileEnabled=report.foundWhileEnabled+1
            state.layer=nil state.pending=nil state.spot=nil state.jumpedKey=nil
            phase("Solicitando o proximo ponto") sync(true)
        elseif action=="Exit" or action=="Leave" then
            state.layer=nil state.pending=nil state.spot=nil state.jumpedKey=nil phase("Chegue perto da praia")
        end
    end
    local function step()
        local now=os.clock() local layer=state.layer
        if layer then
            if layer.completed then if now-(layer.hitAt or layer.receivedAt)>.4 then sync() end return end
            if state.pending then
                if now-state.pending.at<math.clamp((state.rtt or .07)*2.5+.025,.16,.55) then return end
                state.pending=nil layer.armed=true layer.retryAfter=now report.timeouts=report.timeouts+1
                layer.retries=(layer.retries or 0)+1 if layer.retries>2 then layer.retryAfter=now+.3 sync() end
            end
            local x,lo,width,margin=geometry()
            if not x then phase("Aguardando o traco") return end
            if type(layer.center)=="number" and type(layer.width)=="number" and (math.abs(lo+width*.5-layer.center)>.02 or math.abs(width-layer.width)>.02) then return end
            if x<lo+margin or x>lo+width-margin then layer.armed=true return end
            if not layer.armed or now<(layer.retryAfter or 0) then return end
            local timestamp=workspace:GetServerTimeNow()
            if timestamp<layer.started+.004 then return end
            layer.armed=false state.pending={key=layer.key,at=now} report.strikes=report.strikes+1
            phase("Strike no verde") send("Strike",layer.id,timestamp)
            return
        end
        if not state.spot then sync() return end
        jump() if state.layer then return end
        local _,_,root=body() if not root then return end
        local p=state.spot.position local dx,dz=root.Position.X-p.X,root.Position.Z-p.Z
        if dx*dx+dz*dz<=3.2*3.2 then requestDig() end
    end
    pulse=function()
        if not active or closed or busy then return end busy=true
        local ok,err=pcall(step) busy=false
        if not ok then report.error=tostring(err) toggle(false) phase("Erro no Auto Dig") if onChanged then onChanged(false,report.error) end end
    end
    toggle=function(value)
        if closed then return end
        active=false generation=generation+1
        disconnect(links) disconnect(markerLinks) eventRemote=nil eventConnection=nil refs={}
        state={} report.enabled=false phase("OFF")
        if value~=true then return end
        active=true report.enabled=true local token=generation
        if not bindRemote() then active=false report.enabled=false phase("TreasureHunting indisponivel") if onChanged then onChanged(false,report.phase) end return end
        graph()
        listen(Run.RenderStepped,function() if active and generation==token then pulse() end end)
        if Run.Heartbeat then listen(Run.Heartbeat,function() if active and generation==token then pulse() end end) end
        phase("Buscando ponto do detector") sync(true)
    end
    return {Toggle=toggle,Report=report,IsEnabled=function() return active end,
        Close=function() if not closed then toggle(false) closed=true end end}
end
local DigController=nil
local function getDigController()
    if not DigController then
        if env.DigDebug and type(env.DigDebug.Close)=="function" then pcall(env.DigDebug.Close) end
        DigController=createDigController(function(on,reason)
            if autoDig.toggle and autoDig.toggle.Value~=on then autoDig.toggle:SetValue(on) end
            if not on and reason then notify("Auto Dig: "..tostring(reason)) end
        end)
    end
    return DigController
end
autoDig.validate=function() return remote("TreasureHunting")~=nil,"TreasureHunting nao encontrado." end
autoDig.start=function() getDigController().Toggle(true) end
autoDig.release=function() if DigController then DigController.Toggle(false) end end


-- Anti-AFK orientado ao evento de inatividade, independente da pesca.
local AntiAFK=(function()
    local idleConnection,virtualUser=nil,nil
    local rightHeld,busy=false,false
    local pulseGeneration=0
    local lastPulse=-math.huge
    local heldCamera=nil
    local function releaseRight()
        local wasHeld=rightHeld
        rightHeld=false busy=false
        if wasHeld and virtualUser then pcall(function() virtualUser:Button2Up(Vector2.new(0,0),heldCamera) end) end
        heldCamera=nil
        if wasHeld and (not FishingController or not FishingController.IsEnabled()) then
            pcall(function() getFishingController().RestoreMobile() end)
        end
    end
    local function stop()
        pulseGeneration=pulseGeneration+1
        if idleConnection then idleConnection:Disconnect() idleConnection=nil end
        releaseRight()
    end
    antiAFK.validate=function()
        virtualUser=game:GetService("VirtualUser")
        return player.Idled~=nil and virtualUser~=nil,"Anti-AFK indisponivel neste executor."
    end
    antiAFK.start=function()
        stop()
        local generation=pulseGeneration
        idleConnection=player.Idled:Connect(function()
            if not alive or not antiAFK.enabled or generation~=pulseGeneration or busy or os.clock()-lastPulse<5 then return end
            local camera=workspace.CurrentCamera
            if not camera then return end
            busy=true lastPulse=os.clock() heldCamera=camera.CFrame
            local ok,err=pcall(function()
                virtualUser:CaptureController()
                rightHeld=true virtualUser:Button2Down(Vector2.new(0,0),heldCamera)
            end)
            if not ok then
                releaseRight() antiAFK.error=tostring(err)
                antiAFK.toggle:SetValue(false) notify("Anti-AFK: "..tostring(err)) return
            end
            task.delay(.05,function() if generation==pulseGeneration then releaseRight() end end)
        end)
    end
    antiAFK.release=stop
    return {Close=stop}
end)()

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
    Fishing=Window:AddTab("Pesca / Utilidades","fish"),
    Dig=Window:AddTab("Auto Dig","shovel"),
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
    {f=autoFish,tab=tabs.Fishing,side="Left"},
    {f=autoDig,tab=tabs.Dig,side="Left"},
    {f=antiAFK,tab=tabs.Fishing,side="Right"},
}
local panelListBox,rows={},{}
for _,item in ipairs(layout) do
    local f=item.f
    local control=item.tab:AddGroupbox({Side=item.side,Name=f.title})
    control:AddToggle(f.id.."Enabled",{Text=f.title,Default=f.default==true})
    f.toggle=Toggles[f.id.."Enabled"]
    if f~=floorUpgrades and f~=potions and f~=antiAFK and f~=autoDig then intervalControls(control,f) end
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
        if f.validInterval then f.interval=seconds if f.updateInterval then f.updateInterval(seconds) end end
    end)
    Options[f.id.."Unit"]:OnChanged(function()
        local unit=Options[f.id.."Unit"].Value
        if unit==f.unit then return end
        f.unit=unit
        -- Rele o valor na unidade escolhida. Independe da ordem de carga do perfil.
        local n=tonumber((tostring(Options[f.id.."Interval"].Value):gsub(",",".")))
        local seconds=n and (unit=="ms" and n/1000 or n)
        f.validInterval=seconds~=nil and seconds==seconds and seconds>=0 and seconds<=86400
        if f.validInterval then f.interval=seconds if f.updateInterval then f.updateInterval(seconds) end end
    end)
    end
end
if antiAFK.toggle.Value then setFeature(antiAFK,true) end
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
        SaveManager:SetIgnoreIndexes({"CashEnabled","BronzeEnabled","CoinsEnabled","CombatEnabled","TreeEnabled","SpamEnabled","PotionsEnabled","FloorEnabled","FishingEnabled","DigEnabled","AntiAFKEnabled","MenuKeybind"})
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
    AntiAFK.Close()
    if FishingController then FishingController.Close() end
    if DigController then DigController.Close() end
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
    PanelEntries=panelEntries,RemovePanel=removePanelEntry,StartScan=env.NetoHubStartScan,
    GetFishingController=getFishingController,GetDigController=getDigController}
for _,name in ipairs({"FishingDebug","FishingAutoTest","DigDebug"}) do
    if env[name] and type(env[name].Close)=="function" then pcall(env[name].Close) end
end
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
