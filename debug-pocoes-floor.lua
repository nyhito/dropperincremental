-- DebrisMagnet: Auto Pull e dois experimentos independentes, todos desligados ao abrir.
-- Sem clique de tela, TP, alteracao de progresso, forca ou movimento das pecas.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
for _,name in ipairs({"MagnetDebug","DigDebug"}) do
    if env[name] and type(env[name].Close)=="function" then pcall(env[name].Close) end
end
local pg=player:WaitForChild("PlayerGui")
local alive,active=true,nil
local reports={}
local lifetime={}
local own=setmetatable({}, {__mode="k"})
local start,stop,copy,close
local activeTick,releaseActive,onMagnetPacket,learnBegin,learnEnd
local learned=nil
local chunkCache={}
local labels={hold="Detectar segurar",progress="Barra / alvos",auto="Auto Pull",early="Captura cedo",multi="Varios alvos"}
local function word(value)
    local text=tostring(value or ""):lower()
    for _,w in ipairs({"debris","magnet","pull","chunk","blackhole","salvage","scrap","tractor"}) do if text:find(w,1,true) then return true end end
    return false
end
local function fieldWord(value)
    local text=tostring(value or ""):lower()
    if word(text) then return true end
    for _,w in ipairs({"target","progress","strength","weight","mass","collect","capacity","backpack","locked","holding","active","duration","required"}) do if text:find(w,1,true) then return true end end
    return false
end
local function valid(s) return alive and active==s and s.running end
local function time(s) return math.floor((os.clock()-s.started)*1000+.5)/1000 end
local function path(obj) local ok,p=pcall(function() return obj:GetFullName() end) return ok and p or "[removed]" end
local function add(list,row,limit) list[#list+1]=row if #list>limit then table.remove(list,1) end end
local function connect(signal,fn,list)
    own[fn]=true local c=signal:Connect(fn) list[#list+1]=c return c
end
local function disconnect(list) for _,c in ipairs(list) do c:Disconnect() end for i=#list,1,-1 do list[i]=nil end end
local function vector(v) return {x=v.X,y=v.Y,z=v.Z} end
local function serial(v,depth,budget)
    budget.left=budget.left-1 if budget.left<0 then return "[limit]" end
    local kind=typeof(v)
    if kind=="nil" then return {type="nil"}
    elseif kind=="string" then return v:sub(1,120)
    elseif kind=="boolean" then return v
    elseif kind=="number" then return v==v and math.abs(v)~=math.huge and v or tostring(v)
    elseif kind=="Vector3" then local r=vector(v) r.type=kind return r
    elseif kind=="Vector2" then return {type=kind,x=v.X,y=v.Y}
    elseif kind=="CFrame" then local r=vector(v.Position) r.type=kind return r
    elseif kind=="UDim2" then return {type=kind,x=v.X.Scale,xOffset=v.X.Offset,y=v.Y.Scale,yOffset=v.Y.Offset}
    elseif kind=="Instance" then return {type=kind,path=path(v),class=v.ClassName}
    elseif type(v)=="table" and depth<2 then
        local r,n={},0 for k,x in next,v do n=n+1 if n>10 or budget.left<=0 then break end r[tostring(k)]=serial(x,depth+1,budget) end return r
    end
    return {type=kind}
end
local function attributes(obj)
    local result={} local ok,values=pcall(function() return obj:GetAttributes() end)
    if ok then local n=0 for k,v in pairs(values) do n=n+1 if n>12 then break end result[k]=serial(v,0,{left=12}) end end
    return result
end
local function position()
    local c=player.Character local root=c and c:FindFirstChild("HumanoidRootPart") return root and root.Position
end
local function shown(obj)
    local p=obj
    for _=1,20 do
        if not p then return false end
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("ScreenGui") then return p.Enabled end
        p=p.Parent
    end
    return false
end
local function isText(obj) return obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") end
local function textOf(obj) return isText(obj) and tostring(obj.Text):gsub("<[^>]+>","") or "" end
local function snapshot(obj)
    local row={path=path(obj),class=obj.ClassName,name=obj.Name,attributes=attributes(obj)}
    if obj:IsA("GuiObject") then
        row.visible=shown(obj) row.size=serial(obj.Size,0,{left=4}) row.position=serial(obj.Position,0,{left=4})
        if isText(obj) then row.text=tostring(obj.Text):sub(1,130) end
    elseif obj:IsA("BasePart") then row.position=vector(obj.Position) row.size=vector(obj.Size) row.anchored=obj.Anchored
    elseif obj:IsA("Model") then pcall(function() row.position=vector(obj:GetPivot().Position) end) end
    return row
end
local function event(s,kind,action,extra)
    add(s.report.events,{t=time(s),kind=kind,action=action,data=extra},24)
end

local gui=Instance.new("ScreenGui") gui.Name="NetoMagnetDebug" gui.ResetOnSpawn=false gui.DisplayOrder=10034 gui.Parent=pg
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(330,335) panel.Position=UDim2.new(0,10,.05,0)
panel.BackgroundColor3=Color3.fromRGB(21,23,30) panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8)
local function button(text,x,y,width)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.Gotham b.TextSize=12 b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(66,49,110) b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(width,34) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="DEBRIS MAGNET / TESTES" title.Font=Enum.Font.GothamBold title.TextSize=13
title.TextColor3=Color3.new(1,1,1) title.BackgroundTransparency=1 title.Active=true title.Position=UDim2.fromOffset(10,0) title.Size=UDim2.fromOffset(225,36) title.Parent=panel
local minimize=button("-",247,2,30) local exit=button("X",286,2,34)
local buttons,copies={},{}
for i,mode in ipairs({"auto","early","multi","hold","progress"}) do
    buttons[mode]=button(labels[mode]..": iniciar",10,44+(i-1)*40,236)
    copies[mode]=button("Copiar",254,44+(i-1)*40,66)
end
local label=Instance.new("TextLabel") label.Text="Teste Auto Pull primeiro, com o ima equipado e de frente para os itens. Cada teste copia so o seu resultado ao parar."
label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top
label.Font=Enum.Font.Gotham label.TextSize=12 label.TextColor3=Color3.new(1,1,1) label.BackgroundTransparency=1 label.Position=UDim2.fromOffset(10,248) label.Size=UDim2.fromOffset(310,75) label.Parent=panel
local output=Instance.new("TextBox") output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false output.Text=""
output.Font=Enum.Font.Code output.TextSize=10 output.BackgroundColor3=Color3.fromRGB(28,30,39) output.TextColor3=Color3.new(1,1,1)
output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top output.Position=UDim2.fromOffset(10,248) output.Size=UDim2.fromOffset(310,75) output.Visible=false output.Parent=panel
local mini=Instance.new("TextButton") mini.Text="MAG" mini.Font=Enum.Font.GothamBold mini.TextSize=12 mini.TextColor3=Color3.new(1,1,1)
mini.BackgroundColor3=Color3.fromRGB(66,49,110) mini.Size=UDim2.fromOffset(60,34) mini.Position=panel.Position mini.Visible=false mini.Parent=gui
local function updateButtons()
    for mode,b in pairs(buttons) do b.Text=labels[mode]..(active and active.mode==mode and ": parar / copiar" or ": iniciar") end
end

-- Hook inerte fora das sessoes; nenhuma API de Instance ou JSON dentro dele.
local probe=env.__NetoMagnetProbe
if type(probe)~="table" or probe.version~=2 then
    if type(probe)=="table" then probe.enabled=false end
    probe={version=2,installed=false,enabled=false} env.__NetoMagnetProbe=probe
end
local function rawClone(v,depth,budget)
    budget.left=budget.left-1 if budget.left<0 then return "[limit]" end
    if type(v)~="table" then return v end
    if depth>=2 then return "[table]" end
    local out,n={},0 for k,x in next,v do n=n+1 if n>10 or budget.left<=0 then break end out[k]=rawClone(x,depth+1,budget) end return out
end
local function queuePacket(s,kind,obj,method,...)
    if not valid(s) then return end
    if probe.tail-probe.head>=192 then s.report.dropped=s.report.dropped+1 return end
    local args=table.pack(...) local values={n=math.min(args.n,10),totalN=args.n} local budget={left=48}
    for i=1,values.n do values[i]=rawClone(args[i],0,budget) end
    probe.tail=probe.tail+1 probe.queue[probe.tail]={kind=kind,obj=obj,method=method,args=values,at=os.clock()}
end
local function install()
    if probe.installed then return true end
    local hook=hookmetamethod or env.hookmetamethod local getMethod=getnamecallmethod or env.getnamecallmethod
    if type(hook)~="function" or type(getMethod)~="function" then return false,"Captura de FireServer/InvokeServer indisponivel" end
    local original
    local fn=function(self,...)
        if probe.enabled and probe.allowed[self] then
            local method=getMethod()
            if method=="FireServer" or method=="InvokeServer" then
                probe.seen[self]=true
                if probe.tail-probe.head<192 then
                    local args=table.pack(...) local values={n=math.min(args.n,10),totalN=args.n} local budget={left=48}
                    for i=1,values.n do values[i]=rawClone(args[i],0,budget) end
                    probe.tail=probe.tail+1 probe.queue[probe.tail]={kind="send",obj=self,method=method,args=values,at=os.clock(),own=(probe.ownDepth or 0)>0}
                else probe.dropped=probe.dropped+1 end
            end
        end
        return original(self,...)
    end
    local native=newcclosure or env.newcclosure if type(native)=="function" then fn=native(fn) end
    local ok,result=pcall(hook,game,"__namecall",fn)
    if not ok then return false,tostring(result):sub(1,150) end
    original=result probe.installed=true return true
end
local noisy={DropperClick=true,BronzeDropperClick=true,MobAttackMlt=true,TreeHit=true,AutoTreeHit=true,FightingState=true,ChoppingState=true,
    EnemySwing=true,EnemyDamaged=true,EnemyKilled=true,CrystalDestroyed=true,UpdateGlobalMilestones=true,RockDestroyed=true,Smelter=true,RockDamaged=true,
    Upgrade=true,Merchant=true,Fishing=true,TreasureHunting=true,TreasureWorld=true}
local function attachRemote(s,obj)
    if s.remoteInfo[obj] or (not obj:IsA("RemoteEvent") and not obj:IsA("RemoteFunction")) then return end
    if obj.Name~="DebrisMagnet" then return end
    if obj:IsA("RemoteEvent") then s.remote=obj end
    local info={path=path(obj),class=obj.ClassName,related=word(obj.Name)}
    s.remoteInfo[obj]=info
    if noisy[obj.Name] and not info.related then return end
    probe.allowed[obj]=true
    if info.related and #s.report.remoteInventory<18 then s.report.remoteInventory[#s.report.remoteInventory+1]=info end
    if obj:IsA("RemoteEvent") then connect(obj.OnClientEvent,function(...)
        if not valid(s) then return end
        if onMagnetPacket then onMagnetPacket(s,...) end
        local action=select(1,...)
        if info.related or probe.seen[obj] or os.clock()-(s.lastInput or -math.huge)<.45 or (type(action)=="string" and word(action)) then queuePacket(s,"receive",obj,"OnClientEvent",...) end
    end,s.links) end
end
local function drain(s,maximum)
    local processed=0
    while probe.head<=probe.tail and processed<(maximum or 72) do
        local row=probe.queue[probe.head] probe.queue[probe.head]=nil probe.head=probe.head+1 processed=processed+1
        local info=s.remoteInfo[row.obj]
        if info then
            if row.kind=="send" and s.auto then
                local action,id=row.args[1],row.args[2]
                if type(id)=="number" then
                    if action=="Start" then
                        if not s.pulls[id] then s.pulls[id]={id=id,started=row.at,nextCatch=row.at+.15,fromGame=not row.own} end
                        if not row.own then s.report.auto.gameStarts=s.report.auto.gameStarts+1 s.lastGameStart={id=id,at=row.at} end
                    elseif action=="Stop" then s.pulls[id]=nil end
                end
            end
            local args={} for i=1,row.args.n do args[tostring(i)]=serial(row.args[i],0,{left=30}) end
            local action=""
            for i=1,math.min(row.args.n,3) do if type(row.args[i])=="string" then action=row.args[i]:sub(1,45) break end end
            local key=row.kind..info.path..row.method..action local group=s.groups[key]
            if not group and #s.report.calls<18 then
                group={kind=row.kind,path=info.path,class=info.class,related=info.related,action=action,method=row.method,count=0,first=row.at-s.started,variants={}}
                s.groups[key]=group s.report.calls[#s.report.calls+1]=group
            end
            if group then
                group.count=group.count+1 group.last=row.at-s.started
                local signature=Http:JSONEncode(args) local found=false
                for _,v in ipairs(group.variants) do if v.signature==signature then v.count=v.count+1 v.last=row.at-s.started found=true break end end
                if not found then
                    if #group.variants<3 then group.variants[#group.variants+1]={signature=signature,args=args,argCount=row.args.totalN,count=1,first=row.at-s.started,last=row.at-s.started}
                    else group.otherVariants=(group.otherVariants or 0)+1 group.lastArgs=args group.lastArgCount=row.args.totalN end
                end
                if row.kind=="receive" and info.related and s.mode=="progress" then
                    local note=action:lower()
                    if note:find("collect",1,true) or note:find("store",1,true) or note:find("backpack",1,true) then
                        add(s.report.collectionEvidence,{t=row.at-s.started,kind="server_event_unclassified",path=info.path,args=args},6)
                    end
                end
            else s.report.droppedGroups=s.report.droppedGroups+1 end
        end
    end
    if probe.head>probe.tail then probe.queue={} probe.head=1 probe.tail=0 end
end

local function toolSnapshot(tool)
    local row=snapshot(tool) row.children={}
    for i,obj in ipairs(tool:GetChildren()) do if i>18 then break end row.children[#row.children+1]={name=obj.Name,class=obj.ClassName} end
    pcall(function() row.enabled=tool.Enabled row.requiresHandle=tool.RequiresHandle end)
    return row
end
local function bindTool(s,tool)
    if not tool:IsA("Tool") or s.tools[tool] or #s.report.tools>=6 then return end
    s.tools[tool]=true local row=toolSnapshot(tool) row.firstSeen=time(s) s.report.tools[#s.report.tools+1]=row
    for _,name in ipairs({"Activated","Deactivated","Equipped","Unequipped"}) do
        local ok,signal=pcall(function() return tool[name] end)
        if ok and signal then connect(signal,function() if valid(s) then event(s,"tool",name,{path=path(tool),attributes=attributes(tool)}) end end,s.links) end
    end
end
local function bindCharacter(s,c)
    if not c or s.characters[c] then return end s.characters[c]=true
    for _,obj in ipairs(c:GetChildren()) do bindTool(s,obj) end
    connect(c.ChildAdded,function(obj) if valid(s) then bindTool(s,obj) end end,s.links)
end
local function inputOverGui(input)
    local p=input.Position if not p then return false end
    local ok,hits=pcall(function() return pg:GetGuiObjectsAtPosition(p.X,p.Y) end)
    if ok then for _,obj in ipairs(hits) do if obj==gui or obj:IsDescendantOf(gui) then return true end end end
    return false
end
local function bindInput(s)
    connect(UIS.InputBegan,function(input,processed)
        if not valid(s) or processed or inputOverGui(input) then return end
        local kind=input.UserInputType
        if kind~=Enum.UserInputType.Touch and kind~=Enum.UserInputType.MouseButton1 then return end
        s.lastInput=os.clock()
        if s.auto then s.report.auto.manualTouches=s.report.auto.manualTouches+1 end
        local row={t=time(s),kind=tostring(kind),ended=false} s.holds[input]=row
        add(s.report.holds,row,16)
        event(s,"input","begin",{kind=tostring(kind)})
        if learnBegin then learnBegin(s,input) end
    end,s.links)
    connect(UIS.InputEnded,function(input,processed)
        if not valid(s) then return end
        local row=s.holds[input]
        if not row and input.UserInputType==Enum.UserInputType.MouseButton1 then for key,item in pairs(s.holds) do if item.kind==tostring(input.UserInputType) then row=item s.holds[key]=nil break end end end
        if row then row.ended=true row.endedAt=time(s) row.duration=row.endedAt-row.t row.endedProcessed=processed s.holds[input]=nil event(s,"input","end",{duration=row.duration}) if learnEnd then learnEnd(s,input,row.duration) end end
    end,s.links)
end

local function addUi(s,obj,reason)
    if not obj:IsA("GuiObject") or obj:IsDescendantOf(gui) or s.uiSeen[obj] then return end
    local replace=nil
    if #s.uiRefs>=24 then
        if isText(obj) then for i,item in ipairs(s.uiRefs) do if not isText(item.obj) then replace=i break end end end
        if not replace then return end
    end
    s.uiSeen[obj]=true
    local row={initial=snapshot(obj),reason=reason,samples={}}
    local index=replace or #s.uiRefs+1
    s.uiRefs[index]={obj=obj,row=row,last="",saved=-math.huge}
    s.report.ui[index]=row
end
local function inspectUi(s,obj)
    if obj:IsDescendantOf(gui) then return end
    local text=textOf(obj)
    if s.uiSeen[obj] and s.uiProbe[obj]==text then return end
    s.uiProbe[obj]=text
    local full=path(obj) local lower=text:lower()
    if obj:IsA("GuiObject") and (word(full) or word(text) or lower:find("backpack",1,true) or lower:find("face a chunk",1,true) or lower:find("locked on",1,true)) then
        addUi(s,obj,"path_or_caption")
        if isText(obj) and (word(text) or lower:find("backpack",1,true)) then
            local parent=obj.Parent
            if parent then for i,child in ipairs(parent:GetDescendants()) do if i>18 then break end if child:IsA("GuiObject") then addUi(s,child,lower:find("backpack",1,true) and "backpack_neighbor" or "near_relevant_caption") end end end
        end
    end
end
local function seedUi(s)
    local front=pg:FindFirstChild("Front") local main=front and front:FindFirstChild("MainFrame")
    local function scan(root)
        for i,obj in ipairs(root:GetDescendants()) do
            if not valid(s) then return end
            if obj:IsA("GuiObject") and not obj:IsDescendantOf(gui) then
                if isText(obj) and #s.pendingTexts<600 then s.pendingTexts[#s.pendingTexts+1]=obj end
                inspectUi(s,obj)
            end
            if i%70==0 then task.wait(.02) end
        end
    end
    local hud=main and main:FindFirstChild("DebrisHUD")
    if hud then scan(hud) end
    if main and #s.uiRefs<12 then scan(main) end
    if valid(s) and #s.uiRefs<10 then scan(pg) end
end
local function sampleUi(s)
    for _,item in ipairs(s.uiRefs) do
        local obj=item.obj
        if obj.Parent then
            local row={t=time(s),visible=shown(obj)}
            if isText(obj) then row.text=tostring(obj.Text):sub(1,120) end
            local size=obj.Size
            row.x=size.X.Scale row.xOffset=size.X.Offset row.y=size.Y.Scale row.yOffset=size.Y.Offset
            local signature=Http:JSONEncode(row):gsub('"t":[%d%.]+,?',"")
            if signature~=item.last and os.clock()-item.saved>.12 then item.last=signature item.saved=os.clock() add(item.row.samples,row,s.mode=="progress" and 6 or 3) end
            if row.text and row.visible then
                local used,cap=row.text:match("(%d+)%s*/%s*(%d+)")
                local p=path(obj):lower()
                if used and (p:find("backpack",1,true) or s.backpackText==obj or item.row.reason=="backpack_neighbor") then
                    local n=tonumber(used)
                    if s.lastBackpack~=nil and s.lastBackpack~=n then add(s.report.collectionEvidence,{t=time(s),kind="ui_backpack_change",from=s.lastBackpack,to=n},8) end
                    s.lastBackpack=n s.backpackText=obj s.report.backpack={used=n,capacity=tonumber(cap),source=path(obj)}
                end
            end
        elseif not item.row.removedAt then item.row.removedAt=time(s) end
    end
end

local function entityPosition(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then local ok,p=pcall(function() return obj:GetPivot().Position end) if ok then return p end end
end
local function targetCandidate(s,obj,context)
    if s.mode~="progress" or s.targets[obj] or #s.report.targets>=8 or (not obj:IsA("BasePart") and not obj:IsA("Model")) then return end
    local name=obj.Name:lower()
    if path(obj):find(".Crane.",1,true) then return end
    if name=="board" or name=="baseplate" or name=="platform" or name=="handle" then return end
    local attrs=obj:GetAttributes() local meaningful=false
    for key in pairs(attrs) do if fieldWord(key) or tostring(key):lower()=="id" then meaningful=true break end end
    local nearbyRoot=obj.Parent and obj.Parent.Name:lower() or ""
    local moving=obj:IsA("BasePart") and not obj.Anchored
    local collectionParent=nearbyRoot:find("chunk",1,true) or nearbyRoot:find("spawn",1,true) or nearbyRoot:find("item",1,true) or nearbyRoot:find("target",1,true)
    if not word(obj.Name) and not meaningful and not collectionParent and not (context and moving) then return end
    local parent=obj.Parent
    if parent and parent:IsA("Model") and (word(parent.Name) or next(parent:GetAttributes())~=nil) then obj=parent end
    if s.targets[obj] then return end
    local p=entityPosition(obj) if not p then return end
    local origin=position() if origin and (p-origin).Magnitude>300 then return end
    local row=snapshot(obj) row.firstSeen=time(s) row.samples={}
    s.targets[obj]={obj=obj,row=row,position=p,saved=-math.huge}
    s.report.targets[#s.report.targets+1]=row
end
local function discoverWorld(s)
    if s.mode~="progress" then return end
    local roots,seen={},{}
    local function choose(root)
        if not root or seen[root] or #roots>=6 then return end
        seen[root]=true roots[#roots+1]=root
    end
    for _,obj in ipairs(workspace:GetChildren()) do if word(obj.Name) then choose(obj) end end
    for _,name in ipairs({"Features","MapEssentials"}) do
        local base=workspace:FindFirstChild(name)
        if base then for _,obj in ipairs(base:GetChildren()) do if word(obj.Name) then choose(obj) end end end
    end
    for _,root in ipairs(roots) do
        if not valid(s) then return end
        local row={path=path(root),attributes=attributes(root),children={}}
        for i,obj in ipairs(root:GetChildren()) do if i>18 then break end row.children[#row.children+1]={name=obj.Name,class=obj.ClassName} end
        s.report.world[#s.report.world+1]=row
        for i,obj in ipairs(root:GetDescendants()) do
            if not valid(s) then return end
            if i>700 then row.truncated=true break end
            targetCandidate(s,obj,true)
            if i%60==0 then task.wait(.02) end
        end
        connect(root.DescendantAdded,function(obj) if valid(s) then targetCandidate(s,obj,true) end end,s.links)
    end
end
local function sampleTargets(s)
    local origin=position()
    for obj,item in pairs(s.targets) do
        local row=item.row
        if not obj.Parent then if not row.removedAt then row.removedAt=time(s) row.removalIsNotCollectionProof=true end
        else
            local p=entityPosition(obj)
            if p then
                local d=origin and (p-origin).Magnitude
                if d then row.minDistance=math.min(row.minDistance or math.huge,d) row.lastDistance=d end
                local attrs=attributes(obj) local key=Http:JSONEncode(attrs)
                if key~=item.lastAttrs then item.lastAttrs=key add(row.samples,{t=time(s),position=vector(p),distance=d,attributes=attrs},5) item.saved=os.clock()
                elseif (p-item.position).Magnitude>.5 and os.clock()-item.saved>.45 then add(row.samples,{t=time(s),position=vector(p),distance=d},5) item.saved=os.clock() end
                item.position=p row.lastPosition=vector(p)
            end
        end
    end
end

-- Inspecao limitada de referencias existentes; nenhuma funcao do jogo e executada.
local function inspectLogic(s)
    local dbg=debug or {}
    local constants=dbg.getconstants or env.getconstants local upvalues=dbg.getupvalues or env.getupvalues
    local connections=getconnections or env.getconnections local closure=getscriptclosure or env.getscriptclosure
    local protos=dbg.getprotos or env.getprotos
    s.report.logic.capabilities={constants=type(constants)=="function",upvalues=type(upvalues)=="function",connections=type(connections)=="function",scriptClosure=type(closure)=="function",protos=type(protos)=="function"}
    local function source(fn)
        local name,src="",""
        if dbg.info then pcall(function() src,name=dbg.info(fn,"sn") end) end
        if type(getfenv)=="function" then pcall(function() local e=getfenv(fn) local script=rawget(e,"script") if typeof(script)=="Instance" then src=path(script) end end) end
        return tostring(src or ""),tostring(name or "")
    end
    local queue,seen={},setmetatable({}, {__mode="k"})
    local function push(fn,origin,live,owner,depth)
        if type(fn)~="function" or own[fn] or seen[fn] or #queue>=48 then return end
        seen[fn]=true queue[#queue+1]={fn=fn,origin=origin,live=live,owner=owner,depth=depth or 0}
    end
    local signals={{Run.RenderStepped,"RenderStepped"},{UIS.InputBegan,"InputBegan"},{UIS.InputEnded,"InputEnded"}}
    for tool in pairs(s.tools) do signals[#signals+1]={tool.Activated,path(tool)..".Activated"} signals[#signals+1]={tool.Deactivated,path(tool)..".Deactivated"} end
    for obj,info in pairs(s.remoteInfo) do if info.related and obj:IsA("RemoteEvent") then signals[#signals+1]={obj.OnClientEvent,info.path} end end
    if type(connections)=="function" then
        for i,item in ipairs(signals) do
            if not valid(s) then return end if i>14 then break end
            local ok,list=pcall(connections,item[1])
            if ok and type(list)=="table" then
                local row={source=item[2],total=0,foreign=0,accessible=0}
                for index,c in ipairs(list) do
                    if index>120 then row.truncated=true break end row.total=row.total+1
                    local good,fn,foreign=pcall(function() return c.Function,c.ForeignState end)
                    if good and foreign then row.foreign=row.foreign+1 end
                    if good and not foreign and type(fn)=="function" and not own[fn] then
                        local src=source(fn)
                        if src:lower():find("playerscripts",1,true) and word(src) then row.accessible=row.accessible+1 push(fn,item[2],true,src) end
                    end
                end
                s.report.logic.signals[#s.report.logic.signals+1]=row
            end
            task.wait(.025)
        end
    end
    local ps=player:FindFirstChild("PlayerScripts") local client=ps and ps:FindFirstChild("Client") local components=client and client:FindFirstChild("Components")
    if components then
        for i,obj in ipairs(components:GetDescendants()) do
            if not valid(s) then return end if i>600 then break end
            if obj:IsA("ModuleScript") and word(obj.Name) and #s.report.logic.scripts<3 then
                s.report.logic.scripts[#s.report.logic.scripts+1]=path(obj)
                if type(closure)=="function" then local ok,fn=pcall(closure,obj) if ok then push(fn,"script-copy",false,path(obj)) end end
            end
            if i%70==0 then task.wait(.02) end
        end
    end
    local head=1
    while valid(s) and head<=#queue do
        local entry=queue[head] head=head+1
        local src,name=source(entry.fn) if src=="" then src=entry.owner or "" end
        local relevant=word(src)
        if relevant then
            local row={source=src,name=name,kind=entry.live and "active-reference" or "metadata-only",origin=entry.origin,constants={},upvalues={},score=entry.live and 20 or 0}
            if type(constants)=="function" then
                local ok,values=pcall(constants,entry.fn)
                if ok and type(values)=="table" then
                    local n=0 for k,v in next,values do n=n+1 if n>200 then break end
                        if type(v)=="string" and fieldWord(v) then row.score=row.score+10 if #row.constants<24 then row.constants[#row.constants+1]={index=tostring(k),value=v:sub(1,80)} end
                        elseif type(v)=="number" and math.abs(v)<=100 and #row.constants<24 then row.constants[#row.constants+1]={index=tostring(k),value=v} end
                    end
                end
            end
            if entry.live and type(upvalues)=="function" then
                if #s.live<4 then s.live[#s.live+1]={fn=entry.fn,source=src} end
                local ok,values=pcall(upvalues,entry.fn)
                if ok and type(values)=="table" then
                    local n=0 for k,v in next,values do n=n+1 if n>32 then break end
                        if type(v)=="function" and entry.depth<3 then push(v,"upvalue:"..tostring(k),true,src,entry.depth+1)
                        elseif type(v)=="boolean" or type(v)=="number" or typeof(v)=="Vector3" or typeof(v)=="Instance" then
                            if #row.upvalues<12 then row.upvalues[#row.upvalues+1]={index=tostring(k),value=serial(v,0,{left=14})} end
                        elseif type(v)=="table" then
                            local fields,count={},0
                            for key,x in next,v do count=count+1 if count>70 then break end
                                if type(key)=="string" and fieldWord(key) and #fields<6 then fields[#fields+1]={key=key,value=serial(x,0,{left=14})} if type(x)=="function" and entry.depth<3 then push(x,"field:"..key,true,src,entry.depth+1) end end
                            end
                            if #fields>0 and #row.upvalues<12 then row.upvalues[#row.upvalues+1]={index=tostring(k),fields=fields} end
                        end
                    end
                end
            end
            if row.score>0 then
                s.report.logic.functions[#s.report.logic.functions+1]=row table.sort(s.report.logic.functions,function(a,b) return a.score>b.score end)
                if #s.report.logic.functions>6 then table.remove(s.report.logic.functions) end
            end
            if type(protos)=="function" and entry.depth<3 then
                local ok,list=pcall(protos,entry.fn)
                if ok and type(list)=="table" then local count=0 for _,fn in pairs(list) do count=count+1 if count>10 then break end push(fn,"prototype-metadata",false,src,entry.depth+1) end end
            end
        end
        s.report.logic.inspected=head-1 task.wait(.03)
    end
    if valid(s) then s.report.logic.status=#s.live>0 and "active_references_found" or (#s.report.logic.functions>0 and "metadata_only" or "no_accessible_live_function") end
end
local function sampleLive(s)
    local getup=(debug and debug.getupvalues) or env.getupvalues
    if type(getup)~="function" then return end
    for _,item in ipairs(s.live) do
        local ok,values=pcall(getup,item.fn)
        if ok and type(values)=="table" then
            local data,n={},0
            for key,v in next,values do n=n+1 if n>32 then break end
                if (type(v)=="number" and math.abs(v)<100000) or type(v)=="boolean" or typeof(v)=="Vector3" or typeof(v)=="Instance" then
                    if #data<10 then data[#data+1]={index=tostring(key),value=serial(v,0,{left=12})} end
                elseif type(v)=="table" then
                    local count=0 for k,x in next,v do count=count+1 if count>45 then break end
                        if type(k)=="string" and fieldWord(k) and #data<10 and type(x)~="function" then data[#data+1]={key=k,value=serial(x,0,{left=12})} end
                    end
                end
            end
            local signature=Http:JSONEncode(data)
            if signature~=item.last then item.last=signature add(s.report.logic.states,{t=time(s),source=item.source,values=data},8) end
        end
    end
end

-- Somente referencias vivas de DebrisMagnet; nunca executa copia de script.
local function getValues(fn)
    local getup=(debug and debug.getupvalues) or env.getupvalues
    if type(getup)~="function" then return nil end
    local ok,values=pcall(getup,fn)
    return ok and type(values)=="table" and values or nil
end
local function findStep(s)
    local gc=getconnections or env.getconnections
    local constants=(debug and debug.getconstants) or env.getconstants
    if type(gc)~="function" or type(constants)~="function" then return end
    local ok,list=pcall(gc,Run.RenderStepped)
    if not ok or type(list)~="table" then return end
    for i,c in ipairs(list) do
        if i>120 then break end
        local good,fn,foreign=pcall(function() return c.Function,c.ForeignState end)
        if good and not foreign and type(fn)=="function" and not own[fn] then
            local src=""
            if type(getfenv)=="function" then pcall(function() local e=getfenv(fn) local x=rawget(e,"script") if typeof(x)=="Instance" then src=path(x) end end) end
            if src:match("PlayerScripts%..*%.DebrisMagnet$") then
                local read,values=pcall(constants,fn)
                local marks={}
                if read and type(values)=="table" then for _,v in pairs(values) do if type(v)=="string" then marks[v]=true end end end
                if marks.GetMagnetStrength and marks.GetPullCount and marks.Progress then
                    s.step={fn=fn,source=src}
                    s.report.liveStep={source=src,verified=true}
                    return
                end
            end
        end
    end
end
local function bools(s)
    if not s.step then return nil end
    local values=getValues(s.step.fn) if not values then return nil end
    local out,n={},0
    for k,v in next,values do
        n=n+1 if n>80 then break end
        if type(k)=="number" and type(v)=="boolean" then out[k]=v end
    end
    return out
end
learnBegin=function(s,input)
    if s.mode~="hold" or s.learningHold or not s.step or not s.boolFrame then return end
    local attempt={input=input,before=s.boolFrame,fn=s.step.fn}
    s.learningHold=attempt
    task.delay(.10,function()
        if valid(s) and s.learningHold==attempt then attempt.during=bools(s) end
    end)
end
learnEnd=function(s,input,duration)
    local attempt=s.learningHold
    if s.mode~="hold" or not attempt or attempt.input~=input then return end
    s.learningHold=nil
    task.delay(.08,function()
        if not valid(s) or not s.step or s.step.fn~=attempt.fn or duration<.35 then return end
        local after=bools(s) if not after or not attempt.during then return end
        s.learnCycles=s.learnCycles+1
        for index,before in pairs(attempt.before) do
            if before==false and attempt.during[index]==true and after[index]==false then
                s.learnScores[index]=(s.learnScores[index] or 0)+1
            end
        end
        local candidates={}
        for index,count in pairs(s.learnScores) do if count>=2 and count==s.learnCycles then candidates[#candidates+1]=index end end
        s.report.learning={cycles=s.learnCycles,candidates=candidates,confirmed=#candidates==1,readOnly=true}
        if #candidates==1 then
            learned={fn=attempt.fn,index=candidates[1],source=s.step.source}
            s.report.learning.index=candidates[1]
        elseif #candidates>1 then learned=nil s.report.learning.reason="Mais de um estado acompanhou o toque; nenhuma escrita autorizada por deteccao." end
    end)
end
local function nativeRelease(s)
    if s.nativeTool then pcall(function() s.nativeTool:Deactivate() end) s.nativeTool=nil end
    if s.bindingWritten and s.binding then
        local setter=(debug and debug.setupvalue) or env.setupvalue
        if type(setter)=="function" then
            local ok=pcall(setter,s.binding.fn,s.binding.index,false)
            s.report.auto.inputRestored=ok
        end
        s.bindingWritten=false
    end
end
local function sendMagnet(s,action,id)
    if not valid(s) or not s.remote then return false end
    local a=s.report.auto
    probe.ownDepth=(probe.ownDepth or 0)+1
    local ok,err=pcall(function() s.remote:FireServer(action,id) end)
    probe.ownDepth=math.max(0,(probe.ownDepth or 1)-1)
    if ok then
        a.sent[action]=(a.sent[action] or 0)+1
        event(s,"request",action,{id=id})
    else a.lastError=tostring(err):sub(1,160) end
    return ok
end
releaseActive=function(s)
    if not s.auto then return end
    nativeRelease(s)
    local ids={} for id in pairs(s.pulls) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do sendMagnet(s,"Stop",id) end
    s.pulls={}
    s.report.auto.phase="OFF"
end
onMagnetPacket=function(s,action,a,b,c)
    local now=os.clock()
    if action=="Spawn" and type(a)=="table" and type(a.Id)=="number" then
        chunkCache[a.Id]={id=a.Id,data=a,seen=now,source="server_spawn"}
        local count,oldest,at=0,nil,math.huge
        for id,item in pairs(chunkCache) do count=count+1 if item.seen<at then oldest,at=id,item.seen end end
        if count>256 then chunkCache[oldest]=nil end
    elseif action=="Caught" and type(a)=="number" then
        add(s.report.collectionEvidence,{t=time(s),kind="server_Caught",id=a,used=b,capacity=c},12)
        if type(b)=="number" and type(c)=="number" then s.report.backpack={used=b,capacity=c,source="DebrisMagnet.Caught"} end
        if s.auto and not s.caughtIds[a] then
            s.caughtIds[a]=true
            local r=s.report.auto local pull=s.pulls[a]
            r.caughtWhileEnabled=r.caughtWhileEnabled+1
            if pull then
                r.controlledCaught=r.controlledCaught+1
                if pull.lastCatch then r.caughtAfterTestRequest=r.caughtAfterTestRequest+1 end
                add(r.catches,{id=a,t=time(s),seconds=now-pull.started,requestedEarly=pull.lastCatch~=nil,firstCatchAge=pull.firstCatchAge,source=pull.fromGame and "game_start" or "test_start"},12)
            else r.unmatchedCaught=r.unmatchedCaught+1 end
            s.pulls[a]=nil s.cooldowns[a]=now+60
            if s.lastGameStart and s.lastGameStart.id==a then s.lastGameStart=nil end
        end
        chunkCache[a]=nil
    elseif (action=="Despawn" or action=="Remove") and type(a)=="number" then
        chunkCache[a]=nil s.pulls[a]=nil
    end
end
local function rowPosition(row,depth)
    if depth>2 then return nil end
    local kind=typeof(row)
    if kind=="Vector3" then return row end
    if kind=="CFrame" then return row.Position end
    if kind=="Instance" then return entityPosition(row) end
    if type(row)~="table" then return nil end
    for _,key in ipairs({"Position","CFrame","Part","Root","Visual","Model","Chunk","Object"}) do
        local value=rawget(row,key)
        if value~=nil and (type(value)=="table" or typeof(value)=="Instance" or typeof(value)=="Vector3" or typeof(value)=="CFrame") then
            local p=rowPosition(value,depth+1) if p then return p end
        end
    end
end
local function readChunks(s)
    if not s.step then return end
    local values=getValues(s.step.fn) if not values then return end
    local seen,remaining={},220
    local function visit(row,key,depth)
        if type(row)~="table" or typeof(row)~="table" or seen[row] or depth>3 or remaining<=0 then return end
        seen[row]=true remaining=remaining-1
        local data=rawget(row,"Data")
        local id=rawget(row,"Id") or rawget(row,"ID") or rawget(row,"id") or (type(data)=="table" and rawget(data,"Id"))
        if not id and type(key)=="number" and (chunkCache[key] or rawget(row,"Progress")~=nil or rawget(row,"Pulling")~=nil or typeof(rawget(row,"Model"))=="Instance") then id=key end
        if type(id)=="number" and id==math.floor(id) and id>0 then
            local item=chunkCache[id] or {id=id,seen=os.clock(),source="live_chunk"}
            item.pos=rowPosition(row,0) or item.pos item.progress=rawget(row,"Progress") or rawget(row,"PullProgress")
            item.pulling=rawget(row,"Pulling")==true item.liveAt=os.clock() item.source="live_chunk"
            chunkCache[id]=item
        end
        local count=0
        for k,v in next,row do count=count+1 if count>64 or remaining<=0 then break end
            if type(v)=="table" and typeof(v)=="table" then visit(v,k,depth+1) end
        end
    end
    for k,v in next,values do if remaining<=0 then break end visit(v,k,0) end
    local report={}
    for id,item in pairs(chunkCache) do
        if #report<8 and item.liveAt and os.clock()-item.liveAt<1 then
            report[#report+1]={id=id,position=item.pos and vector(item.pos),progress=serial(item.progress,0,{left=8}),pulling=item.pulling,source=item.source}
        end
    end
    s.report.liveChunks=report
end
local function selectChunks(s,count)
    local list={} local now=os.clock()
    local origin=position() local camera=workspace.CurrentCamera
    local look=camera and camera.CFrame and camera.CFrame.LookVector
    for id,item in pairs(chunkCache) do
        if not s.pulls[id] and now-(item.liveAt or item.seen)<20 and now>(s.cooldowns[id] or -1) then
            local distance,dot=nil,nil
            if item.pos and origin then
                local d=item.pos-origin distance=d.Magnitude
                if look and distance>.01 then dot=(d.X*look.X+d.Y*look.Y+d.Z*look.Z)/distance end
            end
            local gameTarget=s.lastGameStart and s.lastGameStart.id==id
            local aimed=item.pulling or gameTarget or (distance and distance<250 and dot and dot>.35)
            -- Varios: permite tambem IDs realmente recebidos em Spawn, apenas na area e com a ferramenta equipada.
            if aimed or (s.mode=="multi" and item.data and s.inArea) then
                list[#list+1]={id=id,score=(gameTarget and 1000 or 0)+(item.pulling and 500 or 0)+(dot or 0)*100-(distance or 200),source=aimed and "live_facing" or "server_spawn"}
            end
        end
    end
    table.sort(list,function(a,b) if a.score==b.score then return a.id<b.id end return a.score>b.score end)
    local out={} for i=1,math.min(count,#list) do out[#out+1]=list[i] end return out
end
activeTick=function(s)
    if not valid(s) then return end
    local now=os.clock()
    if not s.step and now>=(s.nextStepScan or 0) then s.nextStepScan=now+2 findStep(s) end
    if s.mode=="hold" then if not s.learningHold then s.boolFrame=bools(s) end return end
    if s.mode=="progress" then if now>=(s.nextChunks or 0) then s.nextChunks=now+.15 readChunks(s) end return end
    local a=s.report.auto
    local setter=(debug and debug.setupvalue) or env.setupvalue
    a.canSetLearnedHold=type(setter)=="function"
    local char=player.Character local tool=char and char:FindFirstChild("DebrisMagnet")
    local front=pg:FindFirstChild("Front") local main=front and front:FindFirstChild("MainFrame") local hud=main and main:FindFirstChild("DebrisHUD")
    s.inArea=hud and shown(hud) or false
    local bag=s.report.backpack
    if not tool or not tool:IsA("Tool") or not tool.Enabled or not s.inArea or (bag and bag.capacity>0 and bag.used>=bag.capacity) then
        if s.nativeTool or s.bindingWritten or next(s.pulls) then releaseActive(s) end
        a.phase=bag and bag.used>=bag.capacity and "Mochila cheia" or "Equipe DebrisMagnet na area do ima"
        return
    end
    if s.nativeTool~=tool then
        nativeRelease(s)
        local ok,err=pcall(function() tool:Activate() end)
        s.nativeTool=tool s.nativeAt=now a.nativeActivations=a.nativeActivations+1
        a.nativeAvailable=ok if not ok then a.lastError=tostring(err):sub(1,160) end
    end
    if learned and s.step and learned.fn==s.step.fn then
        s.binding=learned
        local setter=(debug and debug.setupvalue) or env.setupvalue
        local values=getValues(learned.fn)
        if type(setter)=="function" and values and type(values[learned.index])=="boolean" then
            if values[learned.index]~=true then
                local ok,err=pcall(setter,learned.fn,learned.index,true)
                if ok then s.bindingWritten=true a.learnedWrites=a.learnedWrites+1 else a.lastError=tostring(err):sub(1,160) end
            end
            a.inputMode="estado de segurar confirmado em dois testes"
        elseif type(setter)~="function" then a.bindingUnavailable=true end
    else a.inputMode="Tool:Activate / Deactivate" end
    if s.mode=="auto" then
        a.phase=next(s.pulls) and "Puxando pela ferramenta" or (now-s.nativeAt>3 and "Se nao puxar: Detectar segurar, segure/solte duas vezes" or "Ferramenta ativada; aponte para um item")
        if a.bindingUnavailable and now-s.nativeAt>3 and not next(s.pulls) then a.phase="Executor sem escrita do segurar; pare e copie o resultado" end
        return
    end
    if not s.remote then a.phase="DebrisMagnet remoto indisponivel" return end
    if now>=(s.nextChunks or 0) then s.nextChunks=now+.15 readChunks(s) end
    local count=0
    for id,pull in pairs(s.pulls) do
        if now-pull.started>9 then
            sendMagnet(s,"Stop",id) s.pulls[id]=nil s.cooldowns[id]=now+2 a.timeouts=a.timeouts+1
        else count=count+1 end
    end
    local limit=s.mode=="multi" and 3 or 1
    if count<limit and now>=(s.nextStart or 0) then
        local candidates=selectChunks(s,1)
        local candidate=candidates[1]
        if candidate then
            local pull={id=candidate.id,started=now,nextCatch=now+.15,fromGame=false,selection=candidate.source}
            s.pulls[candidate.id]=pull
            if not sendMagnet(s,"Start",candidate.id) then s.pulls[candidate.id]=nil end
            s.nextStart=now+.12 count=count+1
        end
    end
    a.maxPending=math.max(a.maxPending,count)
    -- No maximo uma requisicao Catch por tick, e 4/s por item; nao completa barra local.
    if now>=(s.nextRequest or 0) then
        local selected
        for _,pull in pairs(s.pulls) do if now>=pull.nextCatch and (not selected or pull.nextCatch<selected.nextCatch) then selected=pull end end
        if selected then
            selected.nextCatch=now+.30 selected.lastCatch=now selected.firstCatchAge=selected.firstCatchAge or now-selected.started
            sendMagnet(s,"Catch",selected.id) s.nextRequest=now+.06
        end
    end
    a.pending=count
    a.phase=count>0 and (s.mode=="multi" and "Testando ate 3 IDs; aguardando Caught" or "Testando Catch cedo; aguardando Caught") or "Aponte para um item para obter um alvo real"
end

copy=function(mode)
    mode=mode or (active and active.mode)
    local r=mode and reports[mode]
    if not r then label.Text="Esse scanner ainda nao tem resultado." return end
    local export={} for k,v in pairs(r) do export[k]=v end
    if active and active.mode==mode then export.seconds=time(active) export.running=true end
    export.calls={}
    for _,group in ipairs(r.calls) do
        local row={} for k,v in pairs(group) do if k~="variants" then row[k]=v end end row.variants={}
        for _,variant in ipairs(group.variants) do local v={} for k,x in pairs(variant) do if k~="signature" then v[k]=x end end row.variants[#row.variants+1]=v end
        export.calls[#export.calls+1]=row
    end
    if r.logic then export.logic={} for k,v in pairs(r.logic) do export.logic[k]=v end export.logic.functions={}
        for _,fn in ipairs(r.logic.functions) do export.logic.functions[#export.logic.functions+1]=fn end end
    local payload=Http:JSONEncode(export)
    if #payload>18000 then
        export.trimmed=true export.remoteInventory=nil export.world=nil
        if export.logic then export.logic.states=nil while #export.logic.functions>3 do table.remove(export.logic.functions) end end
        local ui={} for i,row in ipairs(export.ui or {}) do if i<=12 then ui[#ui+1]=row end end export.ui=ui
        for _,group in ipairs(export.calls) do while #group.variants>2 do table.remove(group.variants) end end
        payload=Http:JSONEncode(export)
    end
    while #payload>18000 do
        if export.logic and #export.logic.functions>1 then table.remove(export.logic.functions)
        elseif #(export.ui or {})>5 then table.remove(export.ui)
        elseif #(export.targets or {})>3 then local list={} for i=2,#export.targets do list[#list+1]=export.targets[i] end export.targets=list
        elseif #(export.events or {})>8 then local list={} for i=2,#export.events do list[#list+1]=export.events[i] end export.events=list
        elseif #export.calls>8 then
            local index=#export.calls for i=#export.calls,1,-1 do if not export.calls[i].related then index=i break end end table.remove(export.calls,index)
        elseif export.logic then export.logic=nil
        elseif #export.calls>4 then table.remove(export.calls)
        elseif #(export.ui or {})>0 then table.remove(export.ui)
        else
            local reduced=false
            for _,group in ipairs(export.calls) do if #group.variants>1 then local last=table.remove(group.variants) group.lastArgs=group.lastArgs or last.args reduced=true break end end
            if not reduced then
                local remaining=140
                local function compact(value,depth)
                    remaining=remaining-1 if remaining<0 then return "[limit]" end
                    if type(value)=="string" then return value:sub(1,72) end
                    if type(value)~="table" then return value end
                    if depth>6 then return "[limit]" end
                    local out,n={},0 for k,v in pairs(value) do n=n+1 if n>12 or remaining<=0 then break end out[type(k)=="string" and k:sub(1,40) or k]=compact(v,depth+1) end return out
                end
                export={format=r.format,mode=r.mode,placeId=r.placeId,seconds=export.seconds,running=export.running,trimmed=true,
                    note="Resultado compacto; dados extras omitidos.",auto=export.auto,learning=export.learning,liveChunks=export.liveChunks,
                    calls=compact(export.calls,0),holds=compact(export.holds,0),tools=compact(export.tools,0),collectionEvidence=compact(export.collectionEvidence,0)}
                payload=Http:JSONEncode(export) break
            end
        end
        payload=Http:JSONEncode(export)
    end
    local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard local ok,value=false,nil
    if type(clip)=="function" then ok,value=pcall(clip,payload) end
    env.MagnetDebugReport=payload
    env.MagnetReports=env.MagnetReports or {} env.MagnetReports[mode]=payload
    if mode=="hold" then env.MagnetHoldReport=payload elseif mode=="progress" then env.MagnetProgressReport=payload end
    output.Text=payload output.Visible=not(ok and value~=false) label.Visible=not output.Visible
    if output.Visible then panel.Visible=true mini.Visible=false end
    return payload
end
stop=function(mode,shouldCopy)
    local s=active
    if not s or (mode and mode~=s.mode) then if shouldCopy~=false and mode then return copy(mode) end return end
    drain(s,192)
    if releaseActive then releaseActive(s) end
    probe.enabled=false
    drain(s,192)
    local ok,message=pcall(function() sampleUi(s) if s.mode=="progress" then sampleTargets(s) end end)
    if not ok then s.report.readError=tostring(message):sub(1,180) end
    for _,row in pairs(s.holds) do row.unfinishedDuration=time(s)-row.t end
    s.report.seconds=time(s) s.report.running=false s.report.dropped=s.report.dropped+(probe.dropped or 0)
    if s.report.logic.status=="scanning" then s.report.logic.status="stopped_before_scan_finished" end
    s.running=false active=nil probe.allowed={}
    disconnect(s.links)
    updateButtons()
    label.Text=labels[s.mode]..": parado. Resultado separado pronto."
    if shouldCopy~=false then return copy(s.mode) end
end
start=function(mode)
    if not alive or not labels[mode] then return end
    if active and active.mode==mode then return end
    if active then stop(active.mode,true) end
    local s={mode=mode,started=os.clock(),running=true,links={},groups={},remoteInfo={},tools={},characters={},holds={},uiRefs={},uiSeen={},uiProbe={},pendingTexts={},textCursor=1,targets={},live={},
        auto=mode=="auto" or mode=="early" or mode=="multi",pulls={},caughtIds={},cooldowns={},learnScores={},learnCycles=0}
    s.report={format="magnet-tests-v2",mode=mode,running=true,placeId=game.PlaceId,note="Sem clique de tela, TP ou alteracao de progresso/forca/pecas. Auto Pull ativa a ferramenta; Captura cedo e Varios alvos enviam Start/Catch/Stop experimentais. So Caught confirma coleta. Caught enquanto ligado nao exclui ajuda manual. Cada botao tem resultado separado.",
        calls={},remoteInventory={},events={},holds={},tools={},ui={},targets={},world={},collectionEvidence={},dropped=0,droppedGroups=0,
        logic={status="scanning",scripts={},signals={},functions={},states={}}}
    if s.auto then s.report.auto={phase="Iniciando",sent={Start=0,Stop=0,Catch=0},gameStarts=0,nativeActivations=0,learnedWrites=0,
        caughtWhileEnabled=0,controlledCaught=0,caughtAfterTestRequest=0,unmatchedCaught=0,catches={},timeouts=0,maxPending=0,manualTouches=0} end
    active=s reports[mode]=s.report
    probe.enabled=false probe.queue={} probe.head=1 probe.tail=0 probe.dropped=0 probe.allowed={} probe.seen={}
    local remotes=RS:FindFirstChild("Remotes")
    if remotes then for _,obj in ipairs(remotes:GetDescendants()) do attachRemote(s,obj) end connect(remotes.DescendantAdded,function(obj) if valid(s) then attachRemote(s,obj) end end,s.links) end
    local supported,err=install() s.report.outgoingCapture=supported s.report.captureError=err probe.enabled=supported
    bindCharacter(s,player.Character)
    connect(player.CharacterAdded,function(c) if valid(s) then bindCharacter(s,c) end end,s.links)
    bindInput(s)
    findStep(s)
    connect(Run.RenderStepped,function()
        if not valid(s) or s.failed then return end
        local ok,message=pcall(function() drain(s,24) activeTick(s) end)
        if not ok then s.failed=true s.report.controlError=tostring(message):sub(1,180) if s.auto then releaseActive(s) s.report.auto.phase="Falha no controle; pare e copie o resultado" end end
    end,s.links)
    connect(pg.DescendantAdded,function(obj)
        if valid(s) and obj:IsA("GuiObject") and not obj:IsDescendantOf(gui) then
            if isText(obj) and #s.pendingTexts<600 then s.pendingTexts[#s.pendingTexts+1]=obj end inspectUi(s,obj)
        end
    end,s.links)
    output.Visible=false label.Visible=true updateButtons()
    task.spawn(function()
        local ok,message=pcall(function() seedUi(s) if valid(s) then discoverWorld(s) end if valid(s) then inspectLogic(s) end end)
        if not ok and valid(s) then s.report.scanError=tostring(message):sub(1,220) end
    end)
    task.spawn(function()
        while valid(s) do
            local ok,message=pcall(function()
            drain(s)
            for _=1,70 do
                if #s.pendingTexts==0 then break end
                if s.textCursor>#s.pendingTexts then s.textCursor=1 break end
                local obj=s.pendingTexts[s.textCursor] s.textCursor=s.textCursor+1
                if obj.Parent then inspectUi(s,obj) end
            end
            sampleUi(s) sampleLive(s)
            if s.mode=="progress" then sampleTargets(s) end
            end)
            if not ok then s.report.readError=tostring(message):sub(1,180) end
            if s.auto then
                local a=s.report.auto
                label.Text=labels[s.mode].." | "..a.phase.."\nCaught: "..a.caughtWhileEnabled.." | Catch pedidos: "..a.sent.Catch.."\nPare no mesmo botao para copiar este teste."
            elseif s.mode=="hold" then
                label.Text="Segure 1 s, solte 1 s; repita duas vezes.\n"..(s.report.learning and s.report.learning.confirmed and "Segurar identificado. Agora teste Auto Pull." or "Detectando o estado real, sem alterar nada.")
            else label.Text="BARRA / ALVOS: "..math.floor(time(s)).." s\nPuxe itens leves/pesados. Pare para copiar so este scanner." end
            task.wait(.15)
        end
    end)
end
close=function()
    if not alive then return end
    if active then stop(active.mode,true) end
    alive=false probe.enabled=false disconnect(lifetime) gui:Destroy()
end
env.MagnetDebug={Start=start,Stop=stop,Copy=copy,Close=close,GetReport=function(mode) return reports[mode] end,GetActive=function() return active and active.mode end}
for mode,b in pairs(buttons) do
    local selected=mode
    connect(b.Activated,function() if active and active.mode==selected then stop(selected,true) else start(selected) end end,lifetime)
    connect(copies[selected].Activated,function() copy(selected) end,lifetime)
end
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
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+delta.X,0,math.max(0,view.X-330)),math.clamp(panelStart.Y.Scale*view.Y+panelStart.Y.Offset+delta.Y,0,math.max(0,view.Y-335)))
    end
end,lifetime)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end,lifetime)

