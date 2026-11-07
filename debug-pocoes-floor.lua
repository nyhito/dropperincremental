-- SuburbField: detector e testes de coleta, principal sem TP; TP opcional.
-- O modo sem TP aprende uma chamada real; nao inventa nomes de comandos.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
for _,name in ipairs({"BlackHoleCollectDebug","MagnetDebug","DigDebug"}) do
    if env[name] and type(env[name].Close)=="function" then pcall(env[name].Close) end
end
for _,name in ipairs({"__NetoMagnetProbe","__NetoMagnetHoldProbe"}) do
    if type(env[name])=="table" then env[name].enabled=false env[name].hold=false end
end
local pg=player:WaitForChild("PlayerGui")
local alive,active,lastReport=true,nil,nil
local start,stop,copy,close
local learnPacket,autoTick,setAuto,refreshItem,scanLive,currentSize
local lifetime={}
local own=setmetatable({},{__mode="k"})
local function path(x) local ok,p=pcall(function() return x:GetFullName() end) return ok and p or "[removed]" end
local function append(list,row,limit) list[#list+1]=row if #list>limit then table.remove(list,1) end end
local function valid(s) return alive and active==s and s.running end
local function time(s) return math.floor((os.clock()-s.started)*1000+.5)/1000 end
local function connect(signal,fn,list) own[fn]=true local c=signal:Connect(fn) list[#list+1]=c return c end
local function disconnect(list) for _,c in ipairs(list) do c:Disconnect() end table.clear(list) end
local function related(value)
    local name=tostring(value or ""):lower():gsub("[%s_%-]","")
    return name:find("suburb",1,true)~=nil or name:find("holesiz",1,true)~=nil or name:find("swallow",1,true)~=nil or name:find("holecollect",1,true)~=nil
end
local function isText(x) return x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") end
local function plain(value) return tostring(value or ""):gsub("<[^>]+>",""):gsub("^%s+",""):gsub("%s+$","") end
local function shown(x)
    for _=1,20 do
        if not x then return false end
        if x:IsA("GuiObject") and not x.Visible then return false end
        if x:IsA("ScreenGui") or x:IsA("BillboardGui") or x:IsA("SurfaceGui") then return x.Enabled end
        x=x.Parent
    end return false
end
local function position()
    local c=player.Character local r=c and c:FindFirstChild("HumanoidRootPart") return r and r.Position
end
local function vec(v) return {x=v.X,y=v.Y,z=v.Z} end
local function serialize(value,depth,budget)
    budget.left=budget.left-1 if budget.left<0 then return "[limit]" end
    local kind=typeof(value)
    if kind=="nil" then return {type="nil"}
    elseif kind=="number" then return value==value and math.abs(value)<math.huge and value or tostring(value)
    elseif kind=="string" then return value:sub(1,140)
    elseif kind=="boolean" then return value
    elseif kind=="Vector3" then local out=vec(value) out.type=kind return out
    elseif kind=="CFrame" then local out=vec(value.Position) out.type=kind return out
    elseif kind=="Instance" then return {type=kind,path=path(value),class=value.ClassName}
    elseif kind=="table" and depth<3 then
        local out,count={},0
        for k,v in next,value do count=count+1 if count>12 or budget.left<=0 then break end out[tostring(k)]=serialize(v,depth+1,budget) end
        return out
    end return {type=kind}
end
local function attrs(x)
    local out={} local ok,list=pcall(function() return x:GetAttributes() end)
    if ok then local count=0 for k,v in pairs(list) do count=count+1 if count>14 then break end out[k]=serialize(v,0,{left=12}) end end return out
end
local function displayNumber(text)
    local n,suffix=plain(text):gsub(",",""):match("^([%d%.]+)%s*([kKmMbB]?)$")
    if not n then return nil end
    local mult=({k=1e3,m=1e6,b=1e9})[suffix:lower()] or 1 return tonumber(n) and tonumber(n)*mult
end
local needKeys={"RequiredHoleSize","MinHoleSize","NeededHoleSize","RequiredSize","MinSize","NeedSize","HoleSizeRequired","UnlockSize","ReqSize","MinimumSize","HoleSize"}
local function needed(values)
    for _,key in ipairs(needKeys) do local value=values[key] if type(value)=="number" and value>=0 then return value,key end end
end
local function event(s,kind,action,data) append(s.report.events,{t=time(s),kind=kind,action=action,data=data},24) end

local gui=Instance.new("ScreenGui") gui.Name="NetoBlackHoleDebug" gui.ResetOnSpawn=false gui.DisplayOrder=10034 gui.Parent=pg
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(335,334) panel.Position=UDim2.new(0,12,.05,0) panel.BackgroundColor3=Color3.fromRGB(21,23,30) panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8)
local function button(text,x,y,width)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.Gotham b.TextSize=12 b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(66,49,110) b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(width,34) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="SUBURB / COLETA V2" title.Font=Enum.Font.GothamBold title.TextSize=13 title.TextColor3=Color3.new(1,1,1)
title.BackgroundTransparency=1 title.Active=true title.Position=UDim2.fromOffset(10,0) title.Size=UDim2.fromOffset(230,36) title.Parent=panel
local minimize=button("-",251,1,30) local exit=button("X",287,1,38)
local toggle=button("Iniciar deteccao",10,40,315)
local remoteButton=button("Auto pegar sem TP: OFF",10,80,315)
local tpButton=button("Auto pegar com TP: OFF",10,120,315)
local sizeBox=Instance.new("TextBox") sizeBox.Text="" sizeBox.PlaceholderText="Hole Size manual (vazio = automatico)" sizeBox.ClearTextOnFocus=false sizeBox.Font=Enum.Font.Gotham sizeBox.TextSize=12 sizeBox.TextColor3=Color3.new(1,1,1)
sizeBox.BackgroundColor3=Color3.fromRGB(38,39,50) sizeBox.Position=UDim2.fromOffset(10,162) sizeBox.Size=UDim2.fromOffset(315,30) sizeBox.Parent=panel
local copyButton=button("Copiar resultado",10,200,315)
local label=Instance.new("TextLabel") label.Text="Inicie, pegue alguns itens andando e encoste em um que exige tamanho maior. Depois pare para copiar."
label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top label.Font=Enum.Font.Gotham label.TextSize=12
label.BackgroundTransparency=1 label.TextColor3=Color3.new(1,1,1) label.Position=UDim2.fromOffset(10,244) label.Size=UDim2.fromOffset(315,80) label.Parent=panel
local output=Instance.new("TextBox") output.Text="" output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false output.Font=Enum.Font.Code output.TextSize=10
output.BackgroundColor3=Color3.fromRGB(28,30,39) output.TextColor3=Color3.new(1,1,1) output.Position=label.Position output.Size=label.Size output.Visible=false output.Parent=panel
local mini=Instance.new("TextButton") mini.Text="HOLE" mini.Font=Enum.Font.GothamBold mini.TextSize=12 mini.TextColor3=Color3.new(1,1,1)
mini.BackgroundColor3=Color3.fromRGB(66,49,110) mini.Size=UDim2.fromOffset(64,34) mini.Position=panel.Position mini.Visible=false mini.Parent=gui

-- Apenas copia dados simples dentro do hook. Argumentos/retornos originais intactos.
local probe=env.__NetoHoleCollectProbe
if type(probe)~="table" or probe.version~=2 then
    if type(probe)=="table" then probe.enabled=false end
    probe={version=2,installed=false,enabled=false} env.__NetoHoleCollectProbe=probe
end
local function rawClone(value,depth,budget)
    budget.left=budget.left-1 if budget.left<0 then return "[limit]" end
    if type(value)~="table" or typeof(value)~="table" then return value end
    if depth>=3 then return "[table]" end
    local out,count={},0 for k,v in next,value do count=count+1 if count>12 or budget.left<=0 then break end out[k]=rawClone(v,depth+1,budget) end return out
end
local function enqueue(kind,obj,method,...)
    if probe.tail-probe.head>=160 then probe.dropped=probe.dropped+1 return end
    local args=table.pack(...) local data={n=math.min(args.n,8),arity=args.n} local budget={left=60}
    for i=1,data.n do data[i]=rawClone(args[i],0,budget) end
    probe.tail=probe.tail+1 probe.queue[probe.tail]={kind=kind,obj=obj,method=method,args=data,at=os.clock(),own=probe.ownThreads[coroutine.running()]==true}
end
local function install()
    if probe.installed then return true end
    local hook=hookmetamethod or env.hookmetamethod local method=getnamecallmethod or env.getnamecallmethod
    if type(hook)~="function" or type(method)~="function" then return false end
    local original
    local wrapper=function(self,...)
        if probe.enabled and probe.allowed[self] then
            local name=method()
            if name=="FireServer" or name=="InvokeServer" then
                local matches=probe.allowed[self]~="id_filter"
                if not matches then
                    local args=table.pack(...)
                    for i=1,math.min(args.n,8) do
                        local value=args[i]
                        if probe.ids[value] then matches=true break end
                        if type(value)=="table" and typeof(value)=="table" then
                            local count=0
                            for _,x in pairs(value) do count=count+1 if count>12 then break end if probe.ids[x] then matches=true break end end
                        end
                        if matches then break end
                    end
                end
                if matches then enqueue("send",self,name,...) end
            end
        end
        return original(self,...)
    end
    local native=newcclosure or env.newcclosure if type(native)=="function" then wrapper=native(wrapper) end
    local ok,result=pcall(hook,game,"__namecall",wrapper)
    if ok then original=result probe.installed=true end return ok
end
local function attachRemote(s,obj)
    if s.remotes[obj] or (not obj:IsA("RemoteEvent") and not obj:IsA("RemoteFunction")) then return end
    local name=obj.Name local match=related(name)
    local lower=name:lower()
    if not match and name~="CollectPart" and name~="Collectible" and not lower:find("collect",1,true) and not lower:find("consume",1,true) and not lower:find("pickup",1,true) then return end
    s.remotes[obj]={path=path(obj),class=obj.ClassName,related=match}
    probe.allowed[obj]=match and true or "id_filter"
    s.report.remotes[#s.report.remotes+1]={path=path(obj),class=obj.ClassName,related=match}
    if obj:IsA("RemoteEvent") and match then connect(obj.OnClientEvent,function(...) if valid(s) then enqueue("receive",obj,"OnClientEvent",...) end end,s.links) end
end
local function actionOf(args)
    local first=args[1]
    if type(first)=="string" then if first:match("^%d+$") or #first>70 then return "[id]" end return first end
    return type(first)=="number" and "[number_or_id]" or "[payload]"
end
local function drain(s,maximum)
    local done=0
    while probe.head<=probe.tail and done<(maximum or 120) do
        local packet=probe.queue[probe.head] probe.queue[probe.head]=nil probe.head=probe.head+1 done=done+1
        local info=s.remotes[packet.obj]
        if info then
            if learnPacket then learnPacket(s,packet,info) end
            if not info.related and packet.kind=="send" and not packet.own then
                local matches=false
                for i=1,packet.args.n do if probe.ids[packet.args[i]] then matches=true break end end
                if not matches and not (s.schema and s.schema.remote==packet.obj) then info=nil end
            end
        end
        if info then
            local args={} for i=1,packet.args.n do args[tostring(i)]=serialize(packet.args[i],0,{left=40}) end
            local action=actionOf(packet.args) local key=info.path..packet.kind..action local group=s.groups[key]
            if not group and #s.report.calls<20 then
                group={kind=packet.kind,path=info.path,method=packet.method,action=action,count=0,first=packet.at-s.started,variants={}}
                s.groups[key]=group s.report.calls[#s.report.calls+1]=group
            end
            if group then
                group.count=group.count+1 group.last=packet.at-s.started
                local signature=Http:JSONEncode(args) local found=false
                for _,variant in ipairs(group.variants) do if variant.signature==signature then variant.count=variant.count+1 variant.last=group.last found=true break end end
                if not found then
                    if #group.variants<3 then group.variants[#group.variants+1]={signature=signature,args=args,argCount=packet.args.arity,count=1,first=group.last,last=group.last}
                    else group.otherVariants=(group.otherVariants or 0)+1 group.lastArgs=args end
                end
            else s.report.droppedGroups=s.report.droppedGroups+1 end
            if packet.kind=="send" then
                s.report.outgoing=s.report.outgoing+1
                append(s.report.interactions,{t=packet.at-s.started,path=info.path,action=action,args=args,position=position() and vec(position()),holeSize=s.report.holeSize and s.report.holeSize.value},12)
            elseif action~="Spawn" then
                append(s.report.serverEvidence,{t=packet.at-s.started,path=info.path,action=action,args=args,classification="received_event_not_yet_validated"},12)
            end
        end
    end
    if probe.head>probe.tail then probe.queue={} probe.head=1 probe.tail=0 end
end
local function inspectText(s,obj)
    if not isText(obj) or obj:IsDescendantOf(gui) then return end
    local text=plain(obj.Text) local lower=text:lower() local full=path(obj)
    if related(full) or lower:find("hole size",1,true) then
        if not s.uiSeen[obj] and #s.ui<36 then s.uiSeen[obj]=true s.ui[#s.ui+1]=obj end
        if shown(obj) and s.lastText[obj]~=text then
            s.lastText[obj]=text append(s.report.ui,{t=time(s),path=full,text=text},14)
            local required=lower:match("^needs?%s+hole%s+size%s*:?%s*([%d%.]+)")
            if required then
                append(s.report.blockedMessages,{t=time(s),text=text,requiredSize=tonumber(required),position=position() and vec(position()),source=full},8)
                local parent=obj
                for _=1,8 do
                    if not parent then break end
                    local item=s.items[parent]
                    if item then item.liveRequired=tonumber(required) refreshItem(s,item) break end
                    parent=parent.Parent
                end
            end
        end
    end
end
local function watchNewText(s,obj)
    if not isText(obj) or obj:IsDescendantOf(gui) or s.textWatches[obj] then return end
    if s.textWatchCount>=48 then
        local oldest,at=nil,math.huge
        for x,item in pairs(s.textWatches) do if item.at<at then oldest,at=x,item.at end end
        if oldest then s.textWatches[oldest].connection:Disconnect() s.textWatches[oldest]=nil s.textWatchCount=s.textWatchCount-1 end
    end
    local item={at=os.clock()}
    local fn=function() if valid(s) then inspectText(s,obj) end end own[fn]=true
    item.connection=obj:GetPropertyChangedSignal("Text"):Connect(fn)
    s.textWatches[obj]=item s.textWatchCount=s.textWatchCount+1
    task.delay(1.5,function()
        if s.textWatches[obj]==item then item.connection:Disconnect() s.textWatches[obj]=nil s.textWatchCount=s.textWatchCount-1 end
    end)
end
local function sampleUi(s)
    for _,obj in ipairs(s.ui) do if obj.Parent then
        inspectText(s,obj)
        if shown(obj) and obj:IsDescendantOf(pg) and path(obj):find(".Front.MainFrame.",1,true) then
            local text=plain(obj.Text) local lower=text:lower()
            local sizeText=lower:match("^hole%s+size%s*:?%s*([%d%.]+%s*[kmb]?)$")
            local n=sizeText and displayNumber(sizeText)
            if not n and displayNumber(text) and obj.Parent then
                for i,sibling in ipairs(obj.Parent:GetChildren()) do
                    if i>20 then break end
                    if isText(sibling) and plain(sibling.Text):lower()=="hole size" then n=displayNumber(text) break end
                end
            end
            if n then
                if s.report.holeSize and s.report.holeSize.value~=n then append(s.report.sizeChanges,{t=time(s),from=s.report.holeSize.value,to=n},8) end
                if not s.report.holeSize or s.report.holeSize.value~=n then s.dirty=true end
                s.report.holeSize={value=n,source=path(obj),kind="displayed_hole_size"}
            end
        end
    end end
end
local function seedUi(s)
    local front=pg:FindFirstChild("Front") local main=front and front:FindFirstChild("MainFrame") local hud=main and (main:FindFirstChild("SuburbHUD") or main:FindFirstChild("HoleHUD"))
    local function scan(root)
        for i,obj in ipairs(root:GetDescendants()) do
            if not valid(s) then return end if i>1400 then break end inspectText(s,obj) if i%80==0 then task.wait(.016) end
        end
    end
    if hud then scan(hud) end
    if valid(s) then scan(pg) end
end
local function itemPosition(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then local ok,value=pcall(function() return obj:GetPivot().Position end) if ok then return value end end
end
local function addObject(s,obj,root)
    if not valid(s) or s.objects[obj] or #s.objectList>=900 or (not obj:IsA("BasePart") and not obj:IsA("Model")) then return end
    local name=obj.Name:lower()
    if name=="board" or name=="baseplate" or name=="floor" or name=="ground" or name=="zone" or name=="hitbox" then return end
    if obj:IsA("BasePart") and obj.Parent and obj.Parent:IsA("Model") and obj.Parent~=root then
        local ownAttrs=attrs(obj) local parentAttrs=attrs(obj.Parent)
        local id=ownAttrs.Id or ownAttrs.ID or ownAttrs.ObjectId or ownAttrs.ItemId or ownAttrs.CollectId
        local parentId=parentAttrs.Id or parentAttrs.ID or parentAttrs.ObjectId or parentAttrs.ItemId or parentAttrs.CollectId
        local grandName=obj.Parent.Parent and obj.Parent.Parent.Name:lower() or ""
        if not id and not needed(ownAttrs) and (parentId or needed(parentAttrs) or grandName:find("object",1,true) or grandName:find("item",1,true)) then obj=obj.Parent end
    end
    if s.objects[obj] then return end
    local p=itemPosition(obj) if not p then return end
    local attributes=attrs(obj) local required,key=needed(attributes)
    local id=attributes.Id or attributes.ID or attributes.ObjectId or attributes.ItemId or attributes.CollectId
    local parent=obj.Parent local parentName=parent and parent.Name:lower() or ""
    local collection=parentName:find("object",1,true) or parentName:find("item",1,true) or parentName:find("spawn",1,true) or parentName:find("collect",1,true)
    if not id and not required and not collection and obj.Parent~=root then return end
    if obj==root then return end
    local row={path=path(obj),name=obj.Name,class=obj.ClassName,attributes=attributes,id=id,idIsCandidate=true,requiredSize=required,requirementSource=key,position=vec(p),firstSeen=time(s)}
    if obj:IsA("BasePart") then row.physicalSize=vec(obj.Size) end
    s.objects[obj]=row s.objectList[#s.objectList+1]=obj
    local item={obj=obj,row=row,type=obj.Name,id=id,explicitRequirement=required}
    s.items[obj]=item
    if refreshItem then refreshItem(s,item) end
    if id~=nil then probe.ids[id]=true probe.ids[tostring(id)]=true end
    probe.ids[obj]=true probe.ids[obj.Name]=true
end
local function discoverWorld(s)
    local roots,seen={},{}
    local function choose(x) if x and not seen[x] and #roots<6 then seen[x]=true roots[#roots+1]=x end end
    choose(workspace:FindFirstChild("SuburbField"))
    for _,x in ipairs(workspace:GetChildren()) do if related(x.Name) then choose(x) end end
    for _,name in ipairs({"Features","MapEssentials"}) do
        local folder=workspace:FindFirstChild(name)
        if folder then for _,x in ipairs(folder:GetChildren()) do if related(x.Name) then choose(x) end end end
    end
    for _,root in ipairs(roots) do
        if not valid(s) then return end
        s.report.worldRoots[#s.report.worldRoots+1]={path=path(root),attributes=attrs(root)}
        for i,obj in ipairs(root:GetChildren()) do
            if not valid(s) then return end
            addObject(s,obj,root)
            if i%50==0 then task.wait(.016) end
        end
        for i,obj in ipairs(root:GetDescendants()) do
            if not valid(s) then return end if i>2200 then s.report.worldTruncated=true break end
            addObject(s,obj,root) if isText(obj) then inspectText(s,obj) end if i%70==0 then task.wait(.016) end
        end
        connect(root.DescendantAdded,function(obj) if valid(s) then addObject(s,obj,root) if isText(obj) then inspectText(s,obj) end end end,s.links)
    end
end
local function sampleObjects(s)
    local origin=position() local list={}
    for _,obj in ipairs(s.objectList) do
        local row=s.objects[obj]
        if not obj.Parent then if not row.removedAt then row.removedAt=time(s) row.removalIsNotCollectionProof=true end
        else
            local p=itemPosition(obj) if p and origin then row.distance=(p-origin).Magnitude end
            local required,key=needed(attrs(obj)) if required then row.requiredSize=required row.requirementSource=key end
        end
        local size=currentSize and currentSize(s) or (s.report.holeSize and s.report.holeSize.value)
        row.eligibilityHint=size and row.requiredSize and (size>=row.requiredSize and "size_sufficient" or "size_insufficient") or "requirement_unknown"
        list[#list+1]=row
    end
    table.sort(list,function(a,b) return (a.distance or math.huge)<(b.distance or math.huge) end)
    s.report.objects={} for i=1,math.min(20,#list) do s.report.objects[#s.report.objects+1]=list[i] end
end
local function inspectLogic(s)
    local gc=getconnections or env.getconnections local getup=(debug and debug.getupvalues) or env.getupvalues local constants=(debug and debug.getconstants) or env.getconstants
    s.report.logic.capabilities={connections=type(gc)=="function",upvalues=type(getup)=="function",constants=type(constants)=="function"}
    if type(gc)~="function" then return end
    local ok,list=pcall(gc,Run.RenderStepped) if not ok or type(list)~="table" then return end
    for i,c in ipairs(list) do
        if not valid(s) then return end if i>160 then break end
        local good,fn,foreign=pcall(function() return c.Function,c.ForeignState end)
        if good and not foreign and type(fn)=="function" and not own[fn] then
            local source=""
            if type(getfenv)=="function" then pcall(function() local e=getfenv(fn) local x=rawget(e,"script") if typeof(x)=="Instance" then source=path(x) end end) end
            if source:match("PlayerScripts%..*%.Suburb$") or source:match("PlayerScripts%..*%.SuburbField$") then
                s.liveFn=fn
                local row={source=source,kind="active-reference",constants={},upvalues={}} local values=nil
                if type(constants)=="function" then local read,cs=pcall(constants,fn) if read and type(cs)=="table" then for _,value in pairs(cs) do if type(value)=="string" and #row.constants<100 then row.constants[#row.constants+1]=value:sub(1,100) end end end end
                if type(getup)=="function" then local read,v=pcall(getup,fn) if read and type(v)=="table" then values=v end end
                if values then
                    for key,value in pairs(values) do
                        if #row.upvalues>=32 then break end
                        if type(value)=="boolean" or type(value)=="number" then row.upvalues[#row.upvalues+1]={index=key,value=value}
                        elseif type(value)=="table" and typeof(value)=="table" then
                            row.upvalues[#row.upvalues+1]={index=key,value=serialize(value,0,{left=55})}
                        end
                    end
                end
                s.report.logic.functions[#s.report.logic.functions+1]=row
                if #s.report.logic.functions>=2 then break end
            end
        end
    end
    s.report.logic.status=#s.report.logic.functions>0 and "active_references_found" or "no_accessible_suburb_callback"
end

local observedNeeds={Bench=50,LampPost=50,Mailbox=50,House1=250,Barn=250,CarTeal=100,CityBus=250,Bush=20,Bushes=20}
local idKeys={"Id","ID","ObjectId","ItemId","CollectId","SuburbId","ObjectID","ItemID","UID"}
local function itemId(a)
    for _,key in ipairs(idKeys) do if type(a[key])=="string" or type(a[key])=="number" then return a[key] end end
end
local function rootPart() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end
currentSize=function(s)
    local manual=displayNumber(sizeBox.Text)
    return manual or (s.report.holeSize and s.report.holeSize.value)
end
local function registerId(s,key,item)
    if key==nil then return end
    local old=s.lookup[key]
    if old==nil or old==item or (old and not old.obj.Parent) then s.lookup[key]=item else s.lookup[key]=false end
    probe.ids[key]=true
end
refreshItem=function(s,item)
    local obj=item.obj if not obj.Parent then return end
    if item.row.removedAt then
        if item.id~=nil then s.completed[item.id]=nil end
        item.row.removedAt=nil item.nextTry=nil item.nextTP=nil
    end
    local a=obj:GetAttributes()
    item.id=itemId(a) or item.liveId or item.id
    item.type=a.ObjectType or a.ItemType or a.Kind or a.Type or item.type
    local required,key=needed(a)
    local label=obj:FindFirstChild("TooBigLabel",true)
    local title=label and label:FindFirstChild("Title",true)
    if title and isText(title) then
        local n=plain(title.Text):lower():match("^needs?%s+hole%s+size%s*:?%s*([%d%.]+)")
        if n then required=tonumber(n) key="TooBigLabel.Title" end
    end
    local rule=s.rules[item.type]
    item.required=required or item.liveRequired or (rule and rule.size) or observedNeeds[item.type]
    item.source=key or (item.liveRequired and "live_object_data") or (rule and rule.source) or (observedNeeds[item.type] and "captured_size_message")
    item.position=itemPosition(obj) or item.position
    if not item.physical then
        if obj:IsA("BasePart") then item.physical=obj.Size.Magnitude
        else pcall(function() item.physical=obj:GetExtentsSize().Magnitude end) end
    end
    item.row.id=item.id item.row.requiredSize=item.required item.row.requirementSource=item.source
    item.row.objectType=item.type
    if item.id~=nil and item.registeredId~=item.id then s.completed[item.id]=nil item.registeredId=item.id end
    registerId(s,obj,item)
    if item.id~=nil then registerId(s,item.id,item) registerId(s,tostring(item.id),item) registerId(s,tonumber(item.id),item) end
    if obj.Name:match("^%d+$") then registerId(s,obj.Name,item) registerId(s,tonumber(obj.Name),item) end
    s.dirty=true
end
local function associated(s,value)
    if typeof(value)~="Instance" then return nil end
    for _=1,7 do
        if not value then break end
        if s.items[value] then return s.items[value] end
        value=value.Parent
    end
end
scanLive=function(s)
    if s.liveScan or not s.liveFn then return end
    local getup=(debug and debug.getupvalues) or env.getupvalues
    if type(getup)~="function" then return end
    s.liveScan=true
    task.spawn(function()
        local ok,err=pcall(function()
            local good,up=pcall(getup,s.liveFn) if not good or type(up)~="table" then return end
            local queue,seen={},{}
            for k,v in pairs(up) do if type(v)=="table" and typeof(v)=="table" then queue[#queue+1]={value=v,key=k,depth=0} end end
            local index,inspected=1,0
            while valid(s) and index<=#queue and inspected<1200 do
                local node=queue[index] index=index+1 local value=node.value
                if not seen[value] then
                    seen[value]=true inspected=inspected+1
                    local item
                    for _,key in ipairs({"Object","Model","Part","Root","Instance","Visual"}) do item=associated(s,rawget(value,key)) if item then break end end
                    local data=type(rawget(value,"Data"))=="table" and value.Data or {}
                    local req=needed(value) or needed(data)
                    if item then
                        item.liveId=itemId(value) or itemId(data) or (type(node.key)=="number" and node.key or nil)
                        item.liveRequired=req or item.liveRequired
                        if type(value.Type)=="string" then item.type=value.Type end
                        refreshItem(s,item)
                    elseif req and type(node.key)=="string" then s.rules[node.key]={size=req,source="live_type_requirement"} end
                    -- Generic Size is used only after two types match requirements already seen in the game.
                    local matches=0
                    for key,entry in pairs(value) do
                        if type(entry)=="table" and observedNeeds[key] and rawget(entry,"Size")==observedNeeds[key] then matches=matches+1 end
                    end
                    if matches>=2 then for key,entry in pairs(value) do if type(key)=="string" and type(entry)=="table" and type(rawget(entry,"Size"))=="number" then s.rules[key]={size=entry.Size,source="live_type_size_validated_by_two_messages"} end end end
                    if node.depth<3 then
                        local count=0
                        for k,v in pairs(value) do count=count+1 if count>1000 then break end
                            if type(v)=="table" and typeof(v)=="table" then queue[#queue+1]={value=v,key=k,depth=node.depth+1} end
                        end
                    end
                    if inspected%70==0 then task.wait(.001) end
                end
            end
            s.report.liveScan={inspected=inspected,bounded=index<=#queue}
            for _,item in pairs(s.items) do if item.obj.Parent then refreshItem(s,item) end end
        end)
        if not ok and valid(s) then s.report.liveScanError=tostring(err):sub(1,150) end
        s.liveScan=false
    end)
end
local collectActions={Collect=true,Consume=true,Eat=true,Pickup=true,PickUp=true,Swallow=true,Take=true}
learnPacket=function(s,packet,info)
    local args=packet.args
    if packet.kind=="receive" then
        local action,id=args[1],args[2]
        if action=="Refused" or action=="Rejected" or action=="TooBig" then
            local item=s.lookup[id]
            if item then item.nextTry=os.clock()+3 end
            s.report.auto.refusals=(s.report.auto.refusals or 0)+1
        end
        if action=="Collected" or action=="Consumed" or action=="Eaten" or action=="Swallowed" then
            local item=s.lookup[id]
            if item and args[3]~=false and not info.path:lower():find("world",1,true) then
                s.report.auto.serverSignals=s.report.auto.serverSignals+1
                if item.id~=nil then s.completed[item.id]=true end
            end
        end
        return
    end
    if packet.own or s.schema or args.arity>8 then return end
    local lower=info.path:lower()
    for _,word in ipairs({"upgrade","purchase","rebirth","prestige","reset"}) do if lower:find(word,1,true) then return end end
    if not info.related and not lower:find("collect",1,true) and not lower:find("consume",1,true) and not lower:find("pickup",1,true) and not collectActions[args[1]] then return end
    if type(args[1])=="string" and not s.lookup[args[1]] then
        local action=args[1]:lower()
        if not collectActions[args[1]] and not action:find("collect",1,true) and not action:find("consume",1,true) and not action:find("swallow",1,true) and not action:find("absorb",1,true) and not action:find("pick",1,true) then return end
    end
    local match,paths,batchIndex=nil,{},nil
    local function hit(value,index,key)
        local item=s.lookup[value]
        if item and (not item.row.removedAt or packet.at-s.started-item.row.removedAt<2) then
            if match and match~=item then return false end
            match=item paths[#paths+1]={index=index,key=key,representation=typeof(value)=="Instance" and "instance" or type(value)}
        end return true
    end
    for i=1,args.n do
        local value=args[i]
        if type(value)=="table" and typeof(value)=="table" then
            local array=true local first=nil local count=0
            for key,x in pairs(value) do
                if type(key)~="number" or key<1 or key%1~=0 or not s.lookup[x] then array=false break end
                count=count+1 if not first then first={value=x,item=s.lookup[x]} end
            end
            if array and first and count>0 and not match then
                match=first.item batchIndex=i paths={{index=i,key=1,representation=typeof(first.value)=="Instance" and "instance" or type(first.value)}}
            else
                for key,x in pairs(value) do if type(x)=="number" or type(x)=="string" or typeof(x)=="Instance" then if not hit(x,i,key) then return end end end
            end
        else if not hit(value,i,nil) then return end end
    end
    if not match or #paths==0 or not match.position then return end
    local p=position() if not p or (match.position-p).Magnitude>35 then return end
    local fixed=rawClone(args,0,{left=100})
    for i=1,args.n do
        local v=args[i]
        if v~=nil and type(v)~="string" and type(v)~="number" and type(v)~="boolean" and typeof(v)~="Instance" and (type(v)~="table" or typeof(v)~="table") then
            s.report.auto.learningError="Chamada contem tipo complexo; registrada para debug." return
        end
    end
    local typeArgs={}
    for i=1,args.n do if args[i]==match.type and not collectActions[args[i]] then typeArgs[#typeArgs+1]=i end end
    s.schema={remote=packet.obj,args=fixed,n=args.arity,paths=paths,typeArgs=typeArgs,method=packet.method,batchIndex=batchIndex}
    s.report.transport={path=info.path,method=packet.method,argCount=args.arity,idPaths=paths,batchIndex=batchIndex,learnedFromId=match.id,learnedFromObject=match.row.path}
    local size=currentSize(s)
    if not match.required and size then
        s.rules[match.type]={size=size,source="observed_collect_request_at_size_upper_bound"}
        refreshItem(s,match)
    end
    event(s,"learned","collection_transport",s.report.transport)
end
local function queueFor(s)
    local size=currentSize(s) if not size then return {} end
    if s.priorityCache and not s.dirty and s.queueSize==size and s.queueMode==s.auto then return s.priorityCache end
    local origin=position() local list={}
    for _,item in pairs(s.items) do
        if item.obj.Parent and item.required and item.required<=size and not (item.id~=nil and s.completed[item.id]) and item.obj:GetAttribute("PickedUp")~=true then
            local needsId=false
            if s.schema then for _,point in ipairs(s.schema.paths) do if point.representation~="instance" then needsId=true end end end
            local canId=s.auto=="tp" or (s.schema and (not needsId or (item.id~=nil and s.lookup[item.id]==item)))
            if canId then
                item.distance=origin and item.position and (item.position-origin).Magnitude or math.huge
                list[#list+1]=item
            end
        end
    end
    table.sort(list,function(a,b)
        if a.required~=b.required then return a.required>b.required end
        if (a.physical or 0)~=(b.physical or 0) then return (a.physical or 0)>(b.physical or 0) end
        return a.distance<b.distance
    end)
    s.priorityCache=list s.dirty=false s.queueSize=size s.queueMode=s.auto return list
end
local function sendItem(s,item)
    local schema=s.schema local args=rawClone(schema.args,0,{left=120})
    if schema.batchIndex then args[schema.batchIndex]={} end
    for _,point in ipairs(schema.paths) do
        local id=point.representation=="instance" and item.obj or (point.representation=="string" and tostring(item.id) or tonumber(item.id))
        if point.key~=nil then args[point.index][point.key]=id else args[point.index]=id end
    end
    for _,i in ipairs(schema.typeArgs) do args[i]=item.type end
    local mode=s.auto item.nextTry=os.clock()+1
    local function execute()
        if not valid(s) or s.auto~=mode or not item.obj.Parent then s.invokePending=false return end
        local thread=coroutine.running() local ownMap=probe.ownThreads ownMap[thread]=true
        local ok,err=pcall(function()
            if schema.method=="InvokeServer" then return schema.remote:InvokeServer(table.unpack(args,1,schema.n)) end
            return schema.remote:FireServer(table.unpack(args,1,schema.n))
        end)
        ownMap[thread]=nil s.invokePending=false
        if valid(s) then
            if ok then s.report.auto.requests=s.report.auto.requests+1 else s.report.auto.lastError=tostring(err):sub(1,130) end
        end
    end
    if schema.method=="InvokeServer" then if not s.invokePending then s.invokePending=true task.spawn(execute) end else execute() end
end
local function returnFromTP(s)
    if s.returnFrame and s.tpRoot and s.tpRoot.Parent then pcall(function() s.tpRoot.CFrame=s.returnFrame end) end
    s.returnFrame=nil s.tpRoot=nil
end
setAuto=function(mode)
    if not active and mode then start() end
    local s=active if not s then return end
    if s.auto==mode then mode=nil end
    if s.auto=="tp" then returnFromTP(s) end
    s.auto=mode s.report.auto.mode=mode or "off"
    s.tpTarget=nil
    if mode=="tp" then
        s.tpRoot=rootPart()
        if s.tpRoot then s.returnFrame=s.tpRoot.CFrame s.tpHeight=s.tpRoot.Position.Y end
    end
    remoteButton.Text="Auto pegar sem TP: "..(mode=="remote" and "ON" or "OFF")
    tpButton.Text="Auto pegar com TP: "..(mode=="tp" and "ON" or "OFF")
    s.nextAction=0
end
autoTick=function(s)
    if not s.auto then return end
    if not s.worldReady then s.report.auto.phase="Lendo os objetos da area; aguarde" return end
    local now=os.clock()
    if now>=(s.nextRefresh or 0) then
        s.nextRefresh=now+.4
        local keep={}
        for obj,item in pairs(s.items) do
            if obj.Parent then refreshItem(s,item) keep[#keep+1]=obj
            else
                if not item.row.removedAt then item.row.removedAt=time(s) end
                if time(s)-item.row.removedAt>3 then
                    s.items[obj]=nil s.objects[obj]=nil
                    for key,value in pairs(s.lookup) do if value==item then s.lookup[key]=nil probe.ids[key]=nil end end
                else keep[#keep+1]=obj end
            end
        end
        s.objectList=keep
        scanLive(s)
    end
    local size=currentSize(s)
    if not size then s.report.auto.phase="Hole Size nao detectado; informe no campo manual" return end
    if s.auto=="remote" and not s.schema then s.report.auto.phase="Pegue um item andando para ensinar a chamada real" return end
    if s.auto=="tp" and s.tpTarget and s.tpTarget.obj.Parent and now<(s.tpDeadline or 0) and not (s.tpTarget.id~=nil and s.completed[s.tpTarget.id]) then return end
    if now<(s.nextAction or 0) then return end
    s.nextAction=now+(s.auto=="tp" and .18 or .035)
    local queue=queueFor(s) s.report.auto.eligible=#queue s.report.auto.currentSize=size
    s.report.auto.priority={}
    for i=1,math.min(6,#queue) do local item=queue[i] s.report.auto.priority[#s.report.auto.priority+1]={id=item.id,type=item.type,requiredSize=item.required} end
    if #queue==0 then s.report.auto.phase="Aguardando objetos com requisito conhecido e tamanho permitido" return end
    if s.auto=="tp" then
        local root=rootPart() if not root then return end
        if root~=s.tpRoot then s.tpRoot=root s.returnFrame=root.CFrame s.tpHeight=root.Position.Y end
        for _,item in ipairs(queue) do if item.obj.Parent and now>=(item.nextTP or 0) and item.position then
            item.nextTP=now+2
            local p=item.position root.CFrame=CFrame.new(p.X,s.tpHeight or root.Position.Y,p.Z)
            s.tpTarget=item s.tpDeadline=now+.45
            s.report.auto.teleports=s.report.auto.teleports+1 s.report.auto.phase="TP para o maior objeto permitido" break
        end end
    else
        local batch=0
        for _,item in ipairs(queue) do
            if now>=(item.nextTry or 0) then
                sendItem(s,item) batch=batch+1
                if batch>=4 or s.invokePending then break end
            end
        end
        s.report.auto.phase="Repetindo a chamada aprendida; maiores permitidos primeiro"
    end
end

copy=function()
    local r=active and active.report or lastReport if not r then label.Text="Inicie o debug primeiro." return end
    if active then drain(active) sampleUi(active) sampleObjects(active) r.seconds=time(active) end
    local export={} for k,v in pairs(r) do export[k]=v end export.calls={}
    for _,group in ipairs(r.calls) do
        local row={} for k,v in pairs(group) do if k~="variants" then row[k]=v end end row.variants={}
        for _,variant in ipairs(group.variants) do local v={} for k,x in pairs(variant) do if k~="signature" then v[k]=x end end row.variants[#row.variants+1]=v end
        export.calls[#export.calls+1]=row
    end
    local payload=Http:JSONEncode(export)
    if #payload>26000 then export.trimmed=true export.logic=nil export.worldRoots=nil export.objects={} for i=1,math.min(8,#r.objects) do export.objects[i]=r.objects[i] end payload=Http:JSONEncode(export) end
    if #payload>26000 then export.ui=nil export.events=nil for _,g in ipairs(export.calls) do while #g.variants>1 do table.remove(g.variants) end end payload=Http:JSONEncode(export) end
    if #payload>26000 then export.interactions=nil export.serverEvidence=nil export.objects=nil payload=Http:JSONEncode(export) end
    while #payload>26000 and #export.calls>4 do table.remove(export.calls,1) payload=Http:JSONEncode(export) end
    if #payload>26000 then
        export.truncatedForClipboard=true
        for _,g in ipairs(export.calls) do g.lastArgs=nil for _,v in ipairs(g.variants) do v.args=serialize(v.args,0,{left=24}) end end
        payload=Http:JSONEncode(export)
    end
    env.BlackHoleCollectReport=payload env.MagnetDebugReport=payload
    local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard local ok,value=false,nil
    if type(clip)=="function" then ok,value=pcall(clip,payload) end
    output.Text=payload output.Visible=not(ok and value~=false) label.Visible=not output.Visible return payload
end
stop=function(shouldCopy)
    local s=active if not s then if shouldCopy~=false then return copy() end return end
    setAuto(nil)
    probe.enabled=false drain(s,200) sampleUi(s) sampleObjects(s)
    s.running=false s.report.running=false s.report.seconds=time(s) s.report.dropped=probe.dropped
    active=nil lastReport=s.report disconnect(s.links) probe.allowed={}
    for obj,item in pairs(s.textWatches) do item.connection:Disconnect() s.textWatches[obj]=nil end s.textWatchCount=0
    toggle.Text="Iniciar debug" label.Text="Parado. Resultado pronto para enviar."
    if shouldCopy~=false then return copy() end
end
start=function()
    if not alive or active then return end
    local s={started=os.clock(),running=true,links={},remotes={},groups={},objects={},objectList={},items={},lookup={},rules={},completed={},touches={},ui={},uiSeen=setmetatable({},{__mode="k"}),lastText=setmetatable({},{__mode="k"}),textWatches={},textWatchCount=0}
    s.report={format="suburb-collect-test-v2",placeId=game.PlaceId,running=true,
        note="Area SuburbField. Sem TP e o modo principal: aprende chamada real ao coletar andando, depois tenta reutiliza-la. TP e opcional e separado. Prioriza maior requisito permitido; ignora requisito desconhecido. Tentativas e remocao local nao provam aceite do servidor. Campo de tamanho manual vazio usa o HUD.",
        auto={mode="off",phase="Detector ativo",requests=0,teleports=0,serverSignals=0},
        calls={},remotes={},interactions={},serverEvidence={},events={},ui={},blockedMessages={},sizeChanges={},objects={},worldRoots={},logic={status="scanning",functions={}},outgoing=0,droppedGroups=0}
    active=s lastReport=s.report probe.enabled=false probe.allowed={} probe.ids={} probe.queue={} probe.head=1 probe.tail=0 probe.dropped=0 probe.ownThreads=setmetatable({},{__mode="k"})
    local folder=RS:FindFirstChild("Remotes")
    if folder then for _,obj in ipairs(folder:GetDescendants()) do attachRemote(s,obj) end connect(folder.DescendantAdded,function(obj) if valid(s) then attachRemote(s,obj) end end,s.links) end
    s.report.outgoingCapture=install() probe.enabled=s.report.outgoingCapture
    connect(pg.DescendantAdded,function(obj) if valid(s) then watchNewText(s,obj) inspectText(s,obj) end end,s.links)
    connect(workspace.DescendantAdded,function(obj) if valid(s) and isText(obj) then watchNewText(s,obj) inspectText(s,obj) end end,s.links)
    toggle.Text="Parar tudo e copiar" output.Visible=false label.Visible=true
    task.spawn(function()
        local ok,err=pcall(function() seedUi(s) if valid(s) then discoverWorld(s) s.worldReady=true end if valid(s) then inspectLogic(s) scanLive(s) end end)
        if not ok and valid(s) then s.report.scanError=tostring(err):sub(1,180) end
    end)
    task.spawn(function()
        while valid(s) do
            local ok,err=pcall(function() drain(s) sampleUi(s) sampleObjects(s) end)
            if not ok then s.report.readError=tostring(err):sub(1,180) end
            local n=currentSize(s)
            label.Text="Hole Size: "..tostring(n or "?").." | "..(s.report.auto.mode or "off").."\n"..s.report.auto.phase.."\nPedidos: "..s.report.auto.requests.." | TP: "..s.report.auto.teleports
            task.wait(.18)
        end
    end)
    task.spawn(function()
        while valid(s) do
            local ok,err=pcall(function() drain(s) autoTick(s) end)
            if not ok then s.report.auto.lastError=tostring(err):sub(1,180) setAuto(nil) end
            task.wait(.03)
        end
    end)
end
close=function()
    if not alive then return end if active then stop(true) end alive=false probe.enabled=false disconnect(lifetime) gui:Destroy()
end
env.BlackHoleCollectDebug={Start=start,Stop=stop,Copy=copy,Close=close,SetAuto=setAuto,GetReport=function() return active and active.report or lastReport end}
connect(toggle.Activated,function() if active then stop(true) else start() end end,lifetime)
connect(copyButton.Activated,copy,lifetime)
connect(remoteButton.Activated,function() setAuto("remote") end,lifetime)
connect(tpButton.Activated,function() setAuto("tp") end,lifetime)
connect(exit.Activated,close,lifetime)
connect(minimize.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end,lifetime)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false end,lifetime)
local dragging,dragInput,inputStart,panelStart
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true dragInput=input.UserInputType==Enum.UserInputType.Touch and input or nil inputStart=input.Position panelStart=panel.Position end
end,lifetime)
connect(UIS.InputChanged,function(input)
    if dragging and ((dragInput and input==dragInput) or (not dragInput and input.UserInputType==Enum.UserInputType.MouseMovement)) then
        local d=input.Position-inputStart local v=workspace.CurrentCamera.ViewportSize
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+d.X,0,math.max(0,v.X-335)),math.clamp(panelStart.Y.Scale*v.Y+panelStart.Y.Offset+d.Y,0,math.max(0,v.Y-334)))
    end
end,lifetime)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end,lifetime)
