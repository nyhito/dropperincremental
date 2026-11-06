-- Dig / gamepass: teste automatico pelo protocolo observado e faixa real.
-- Auto e TP iniciam desligados. Nenhum horario/acerto e forjado.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
for _,name in ipairs({"FishingDebug","FishingAutoTest","DigDebug"}) do
    if env[name] and type(env[name].Close)=="function" then pcall(env[name].Close) end
end
local pg=player:WaitForChild("PlayerGui")
local alive,running=true,false
local generation=0
local function current(token) return alive and running and generation==token end
local started=0
local links,sessionLinks={},{}
local own=setmetatable({}, {__mode="k"})
local report={format="dig-debug-v3-reactive",placeId=game.PlaceId}
local refs={objects={}}
local bound=setmetatable({}, {__mode="k"})
local pendingButtons={}
local monitored,remoteInfo={},{}
local visual=nil
local visualPending=false
local start,stop,copy,close,testZone
local toggleAuto,toggleTP,autoStep,onTreasure,cacheFast,pulse
local auto={enabled=false,tp=false,phase="OFF"}
local function at() return math.floor((os.clock()-started)*1000+.5)/1000 end
local function listen(signal,fn,list)
    own[fn]=true local c=signal:Connect(fn) local into=list or sessionLinks into[#into+1]=c return c
end
local function disconnect(list) for _,c in ipairs(list) do c:Disconnect() end table.clear(list) end
local function word(s)
    s=tostring(s):lower()
    for _,v in ipairs({"dig","detect","treasure","excavat","archaeo","hole","beach"}) do if s:find(v,1,true) then return true end end
    return false
end
local function stateWord(s)
    s=tostring(s):lower()
    if word(s) then return true end
    for _,v in ipairs({"target","spot","green","zone","cursor","window","signal","layer","sweep","width","search","strike","hit"}) do if s:find(v,1,true) then return true end end
    return false
end
local function path(obj) local ok,s=pcall(function() return obj:GetFullName() end) return ok and s or "[removed]" end
local function position()
    local c=player.Character local r=c and c:FindFirstChild("HumanoidRootPart") return r and r.Position
end
local function vec(v) return {x=v.X,y=v.Y,z=v.Z} end
local function short(v,depth,budget)
    budget.left=budget.left-1 if budget.left<0 then return "[limit]" end
    local kind=typeof(v)
    if kind=="nil" then return {type="nil"}
    elseif kind=="string" then return v:sub(1,100)
    elseif kind=="number" then return v==v and math.abs(v)~=math.huge and v or tostring(v)
    elseif kind=="boolean" then return v
    elseif kind=="Vector3" then local r=vec(v) r.type=kind return r
    elseif kind=="CFrame" then local r=vec(v.Position) r.type=kind return r
    elseif kind=="Vector2" then return {type=kind,x=v.X,y=v.Y}
    elseif kind=="UDim2" then return {type=kind,xScale=v.X.Scale,xOffset=v.X.Offset,yScale=v.Y.Scale,yOffset=v.Y.Offset}
    elseif kind=="Instance" then return {type=kind,path=path(v),class=v.ClassName}
    elseif type(v)=="table" and depth<2 then
        local r,n={},0 for k,x in next,v do n=n+1 if n>8 or budget.left<=0 then break end r[tostring(k)]=short(x,depth+1,budget) end return r
    end
    return {type=kind}
end
local function add(list,value,max) list[#list+1]=value if #list>max then table.remove(list,1) end end
local function shown(obj)
    local p=obj
    for _=1,18 do
        if not p then return false end
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("ScreenGui") then return p.Enabled end
        p=p.Parent
    end
    return false
end
local gui=Instance.new("ScreenGui") gui.Name="NetoDigDebug" gui.ResetOnSpawn=false gui.DisplayOrder=10032 gui.Parent=pg
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(330,335) panel.Position=UDim2.new(0,12,.08,0)
panel.BackgroundColor3=Color3.fromRGB(21,23,30) panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,9)
local function button(text,x,y,w,h)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.Gotham b.TextSize=13 b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(66,49,110) b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(w,h) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="DEBUG DIG / GAMEPASS" title.Font=Enum.Font.GothamBold title.TextSize=13
title.TextColor3=Color3.new(1,1,1) title.BackgroundTransparency=1 title.Active=true
title.Position=UDim2.fromOffset(10,3) title.Size=UDim2.fromOffset(230,30) title.Parent=panel
local minimize=button("-",260,6,25,25) local exit=button("X",292,6,25,25)
local startButton=button("Iniciar debug (30 s)",10,42,310,34)
local stopButton=button("Parar / copiar",10,84,150,32) local copyButton=button("Copiar resultado",170,84,150,32)
local testButton=button("Testar faixa verde: OFF",10,125,310,34)
local autoButton=button("Auto Dig: OFF",10,167,150,34)
local tpButton=button("TP ao ponto: OFF",170,167,150,34)
local label=Instance.new("TextLabel") label.Text="Ligue a gamepass e inicie antes de achar um ponto."
label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top
label.Font=Enum.Font.Gotham label.TextSize=12 label.TextColor3=Color3.new(1,1,1) label.BackgroundTransparency=1
label.Position=UDim2.fromOffset(10,213) label.Size=UDim2.fromOffset(310,110) label.Parent=panel
local mini=Instance.new("TextButton") mini.Text="DIG" mini.Font=Enum.Font.GothamBold mini.TextSize=12 mini.TextColor3=Color3.new(1,1,1)
mini.BackgroundColor3=Color3.fromRGB(66,49,110) mini.Position=panel.Position mini.Size=UDim2.fromOffset(60,36) mini.Visible=false mini.Parent=gui
local output=Instance.new("TextBox") output.Text="" output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false
output.Font=Enum.Font.Code output.TextSize=10 output.TextColor3=Color3.new(1,1,1) output.BackgroundColor3=Color3.fromRGB(29,31,39)
output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top
output.Position=UDim2.fromOffset(0,342) output.Size=UDim2.fromOffset(330,135) output.Visible=false output.Parent=panel

-- Captura pequena. Nunca chama metodos de Instance/JSON dentro do namecall.
local probe=env.__NetoDigProbe
if type(probe)~="table" or probe.version~=2 then
    if type(probe)=="table" then probe.enabled=false end
    probe={version=2,installed=false,enabled=false} env.__NetoDigProbe=probe
end
local function rawClone(v,depth,budget)
    budget.left=budget.left-1 if budget.left<0 then return "[limit]" end
    if type(v)~="table" then return v end
    if depth>=2 then return "[table]" end
    local t,n={},0
    for k,x in next,v do n=n+1 if n>8 or budget.left<=0 then break end t[k]=rawClone(x,depth+1,budget) end
    return t
end
local function enqueue(kind,obj,method,...)
    if not running then return end
    if probe.tail-probe.head>=160 then report.dropped=report.dropped+1 return end
    local values=table.pack(...) local copied={n=math.min(values.n,12),totalN=values.n} local budget={left=48}
    for i=1,copied.n do copied[i]=rawClone(values[i],0,budget) end
    probe.tail=probe.tail+1 probe.queue[probe.tail]={kind=kind,obj=obj,method=method,args=copied,time=os.clock()}
end
local function installProbe()
    if probe.installed then return true end
    local hook=hookmetamethod or env.hookmetamethod local namecall=getnamecallmethod or env.getnamecallmethod
    if type(hook)~="function" or type(namecall)~="function" then return false,"hookmetamethod/getnamecallmethod indisponiveis" end
    local original
    local wrapper=function(self,...)
        if probe.enabled and probe.allowed[self] then
            local method=namecall()
            if method=="FireServer" or method=="InvokeServer" then
                probe.seen[self]=true
                if probe.tail-probe.head<160 then
                    local args=table.pack(...) local values={n=math.min(args.n,12),totalN=args.n} local budget={left=48}
                    for i=1,values.n do values[i]=rawClone(args[i],0,budget) end
                    probe.tail=probe.tail+1 probe.queue[probe.tail]={kind="send",obj=self,method=method,args=values,time=os.clock()}
                else probe.dropped=probe.dropped+1 end
            end
        end
        return original(self,...)
    end
    local native=newcclosure or env.newcclosure
    if type(native)=="function" then wrapper=native(wrapper) end
    local ok,result=pcall(hook,game,"__namecall",wrapper)
    if not ok then return false,tostring(result) end
    original=result probe.installed=true return true
end
local function attributes(obj)
    local r,n={},0 local ok,a=pcall(function() return obj:GetAttributes() end)
    if ok then for k,v in pairs(a) do n=n+1 if n>8 then break end r[k]=short(v,0,{left=8}) end end
    return r
end
local function snapshot(obj)
    local r={path=path(obj),class=obj.ClassName,name=obj.Name,attributes=attributes(obj)}
    if obj:IsA("GuiObject") then r.position=short(obj.Position,0,{left=4}) r.size=short(obj.Size,0,{left=4}) r.visible=shown(obj)
        r.absolute={x=obj.AbsolutePosition.X,y=obj.AbsolutePosition.Y,w=obj.AbsoluteSize.X,h=obj.AbsoluteSize.Y} end
    if obj:IsA("TextLabel") or obj:IsA("TextButton") then r.text=obj.Text:sub(1,130) end
    if obj:IsA("BasePart") then r.position=vec(obj.Position) r.size=vec(obj.Size) end
    return r
end
local function isText(obj) return obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") end
local function clean(s) return tostring(s):gsub("<[^>]+>",""):lower():gsub("%s+", " "):match("^%s*(.-)%s*$") end
local function caption(obj)
    if obj:IsA("TextButton") then local text=clean(obj.Text) if text~="" then return text end end
    for i,x in ipairs(obj:GetDescendants()) do
        if i>16 then break end
        if isText(x) then local text=clean(x.Text) if text=="dig" or text=="find the spot" then return text end end
    end
    return ""
end
local function hudFor(obj)
    local p=obj.Parent local fallback=p
    for _=1,4 do
        if not p or p==pg or p:IsA("ScreenGui") then break end
        for i,x in ipairs(p:GetDescendants()) do
            if i>150 then break end
            if isText(x) then local s=clean(x.Text) if s:find("signal",1,true) or s:find("digging",1,true) or s:find("green zone",1,true) or s:find("searching the beach",1,true) then return p end end
        end
        p=p.Parent
    end
    return fallback
end
local function refreshObjects()
    refs.objects={}
    if refs.hud and refs.hud.Parent then for i,obj in ipairs(refs.hud:GetDescendants()) do if i>180 then break end refs.objects[#refs.objects+1]=obj end end
end
local function geometry()
    local track,zone,marker=refs.track,refs.zone,refs.marker
    if not track or not zone or not marker or not zone.Parent or not marker.Parent or track.AbsoluteSize.X<=0 then return nil end
    local left,w=track.AbsolutePosition.X,track.AbsoluteSize.X
    local cursor=(marker.AbsolutePosition.X+marker.AbsoluteSize.X*.5-left)/w
    local lo=(zone.AbsolutePosition.X-left)/w local width=zone.AbsoluteSize.X/w
    local mode="absolute"
    if marker.Parent==track and zone.Parent==track and marker.Position.X.Offset==0 and marker.Size.X.Offset==0 and zone.Position.X.Offset==0 and zone.Size.X.Offset==0 then
        width=zone.Size.X.Scale
        lo=zone.Position.X.Scale-zone.AnchorPoint.X*width
        cursor=marker.Position.X.Scale+(.5-marker.AnchorPoint.X)*marker.Size.X.Scale
        mode="scale_properties"
    end
    local r={cursor=cursor,greenStart=lo,greenWidth=width,inside=cursor>=lo and cursor<=lo+width,mode=mode}
    if visual then r.insideOriginal=cursor>=visual.originalStart and cursor<=visual.originalStart+visual.originalWidth r.visualTest=true end
    return r
end
local function findGeometry()
    if visual then return end
    local best=nil
    for _,zone in ipairs(refs.objects) do
        if zone:IsA("Frame") or zone:IsA("ImageLabel") or zone:IsA("CanvasGroup") then
            local c=zone.BackgroundColor3 local parent=zone.Parent local size=zone.AbsoluteSize
            if zone:IsA("ImageLabel") then local tint=zone.ImageColor3 if tint and tint.G>.4 and tint.G>tint.R*1.15 and tint.G>tint.B*1.1 then c=tint end end
            local name=zone.Name:lower()
            local green=(c.G>.4 and c.G>c.R*1.15 and c.G>c.B*1.1) or name:find("green",1,true) or name=="zone" or name=="targetzone" or name=="sweetspot"
            if not green then
                for _,child in ipairs(zone:GetChildren()) do
                    if child:IsA("UIGradient") then for _,key in ipairs(child.Color.Keypoints) do local color=key.Value if color.G>.4 and color.G>color.R*1.15 and color.G>color.B*1.1 then green=true break end end end
                end
            end
            if parent and parent:IsA("GuiObject") and parent.AbsoluteSize.X>60 and size.X>15 and size.Y>5
                and size.X<parent.AbsoluteSize.X*.9 and size.Y<parent.AbsoluteSize.Y*1.6
                and green then
                local marker,score=nil,0
                for i,obj in ipairs(parent:GetDescendants()) do
                    if i>45 then break end
                    if obj~=zone and not obj:IsDescendantOf(zone) and obj:IsA("GuiObject") then
                        local s=obj.AbsoluteSize local color=obj.BackgroundColor3
                        if s.X>0 and s.X<parent.AbsoluteSize.X*.1 and s.Y>=size.Y*.65 then
                            local n=obj.Name:lower() local rank=(color.R>.65 and color.G>.65 and color.B>.65) and 5 or 0
                            if n:find("cursor",1,true) or n:find("needle",1,true) or n:find("indicator",1,true) or n:find("line",1,true) then rank=rank+10 end
                            if rank>score then score=rank marker=obj end
                        end
                    end
                end
                if marker and (not best or score>best.score) then best={zone=zone,track=parent,marker=marker,score=score} end
            end
        end
    end
    if best then refs.zone=best.zone refs.track=best.track refs.marker=best.marker
        report.geometry={zone=snapshot(best.zone),track=snapshot(best.track),marker=snapshot(best.marker),confidence="paired_green_and_cursor"} end
end
local function readHud()
    local texts={} local phase="unknown" local signal=nil local layer=nil
    for _,obj in ipairs(refs.objects) do
        if isText(obj) and shown(obj) then
            local s=clean(obj.Text)
            if s:find("digging",1,true) or s:find("auto dig",1,true) or s:find("hit the green zone",1,true) or s:find("try the next sweep",1,true) then phase="digging" end
            if s:find("signal",1,true) then signal=tonumber(s:match("([%d.]+)%%")) if phase~="digging" then phase="signal" end end
            if s:find("searching the beach",1,true) and phase=="unknown" then phase="searching" end
            if s:find("layer",1,true) then local value=s:match("(%d+%s*/%s*%d+)") if value then layer=value:gsub("%s","") end end
            if #s>0 and (s=="dig" or s:find("signal",1,true) or s:find("layer",1,true) or s:find("miss",1,true) or s:find("search",1,true)) and #texts<8 then texts[#texts+1]={path=path(obj),text=obj.Text:sub(1,110)} end
        end
    end
    return phase,signal,layer,texts
end
cacheFast=function()
    local front=pg:FindFirstChild("Front") local main=front and front:FindFirstChild("MainFrame")
    local hud=(main and main:FindFirstChild("TreasureHUD")) or refs.hud
    if not hud or not hud.Parent then return end
    if refs.hud~=hud then refs.hud=hud report.hud=path(hud) refreshObjects() end
    local action=hud:FindFirstChild("Action") if action and action:IsA("GuiButton") and not bound[action] then bindButton(action) end
    local track=hud:FindFirstChild("Track") or refs.track
    if not track then return end
    local zone=track:FindFirstChild("Zone") or track:FindFirstChild("GreenZone") or refs.zone
    local marker=track:FindFirstChild("Needle") or track:FindFirstChild("Cursor") or refs.marker
    if not zone or not marker then return end
    refs.track,refs.zone,refs.marker=track,zone,marker
    if refs.watchedMarker~=marker then
        refs.watchedMarker=marker local token=generation
        local function changed()
            if current(token) then refs.markerRevision=(refs.markerRevision or 0)+1 if pulse then pulse() end end
        end
        listen(marker:GetPropertyChangedSignal("Position"),changed)
        listen(marker:GetPropertyChangedSignal("Visible"),changed)
        report.geometry={zone=snapshot(zone),track=snapshot(track),marker=snapshot(marker),confidence="known_TreasureHUD_paths"}
    end
end
local lastTap=-math.huge
local function bindButton(obj)
    if not obj:IsA("GuiButton") or obj:IsDescendantOf(gui) or bound[obj] then return end
    local text=caption(obj)
    if text~="dig" and text~="find the spot" and not obj.Name:lower():find("digbutton",1,true) then return end
    bound[obj]=true local token=generation
    if not refs.button or not shown(refs.button) or shown(obj) then
        refs.button=obj refs.hud=hudFor(obj) refreshObjects()
        report.button=snapshot(obj) report.hud=refs.hud and path(refs.hud)
    end
    local function tapped()
        if not current(token) or os.clock()-lastTap<.05 then return end
        if refs.button~=obj then refs.button=obj refs.hud=hudFor(obj) refreshObjects() findGeometry() end
        lastTap=os.clock()
        local phase,signal,layer=readHud()
        local data={t=at(),phase=phase,signal=signal,layer=layer,geometry=geometry(),button=path(obj),visualTest=visual~=nil}
        local p=position() if p then data.player=vec(p) end
        add(report.taps,data,16)
        if visual then visual.record.taps=visual.record.taps+1
            if data.geometry and data.geometry.insideOriginal==false then visual.record.outsideOriginalTaps=visual.record.outsideOriginalTaps+1 end end
    end
    listen(obj.Activated,tapped)
    if obj.MouseButton1Click then listen(obj.MouseButton1Click,tapped) end
end
local function discoverUi(token)
    local front=pg:FindFirstChild("Front") local main=front and front:FindFirstChild("MainFrame")
    local function scan(root)
        for i,obj in ipairs(root:GetDescendants()) do
            if not current(token) then return end
            local name=obj.Name:lower()
            if not refs.hud and (obj:IsA("GuiObject") or obj:IsA("ScreenGui")) and (name=="treasurehunting" or name=="treasurehuntinghud" or name=="detectorhud" or name=="treasurebar") then
                refs.hud=obj report.hud=path(obj) refreshObjects()
            end
            if obj:IsA("GuiButton") and not obj:IsDescendantOf(gui) then
                if #pendingButtons<320 then pendingButtons[#pendingButtons+1]=obj end
                bindButton(obj)
            end
            if i%80==0 then task.wait(.025) end
        end
    end
    if main then scan(main) end
    if current(token) and not refs.button then scan(pg) end
    if current(token) and refs.button then findGeometry() end
end
local targetKeys={}
local function candidate(v,source,kind)
    if typeof(v)~="Vector3" then return end
    local p=position() if p and (v-p).Magnitude>500 then return end
    local key=string.format("%.2f/%.2f/%.2f",v.X,v.Y,v.Z)
    local entry=targetKeys[key]
    if not entry then
        if #report.targets>=12 then report.targetLimit=true return end
        entry={position=vec(v),firstSeen=at(),source=source,kind=kind or "candidate_not_validated",startDistance=p and (v-p).Magnitude}
        targetKeys[key]=entry report.targets[#report.targets+1]=entry
    end
    entry.lastSeen=at()
end
local function vectorLeaves(value,source,depth,budget)
    budget.left=budget.left-1 if budget.left<0 then return end
    if typeof(value)=="Vector3" then candidate(value,source)
    elseif typeof(value)=="CFrame" then candidate(value.Position,source.."/CFrame")
    elseif type(value)=="table" and depth<2 then
        local n=0 for key,v in next,value do n=n+1 if n>20 or budget.left<=0 then break end vectorLeaves(v,source.."/"..tostring(key),depth+1,budget) end
    end
end
local function inspectWorld(token)
    local features=workspace:FindFirstChild("Features")
    if features then
        for _,root in ipairs(features:GetChildren()) do
            if not current(token) then return end
            if word(root.Name) and #report.world<5 then
                local row={path=path(root),attributes=attributes(root),parts={}}
                report.world[#report.world+1]=row
                vectorLeaves(root:GetAttributes(),row.path.."/attributes",0,{left=24})
                for i,obj in ipairs(root:GetDescendants()) do
                    if not current(token) then return end
                    if i>240 then row.truncated=true break end
                    if obj:IsA("BasePart") and #row.parts<8 and (stateWord(obj.Name) or #row.parts<3) then
                        row.parts[#row.parts+1]=snapshot(obj)
                        vectorLeaves(obj:GetAttributes(),path(obj).."/attributes",0,{left=16})
                    end
                    if i%60==0 then task.wait(.025) end
                end
            end
        end
    end
    local character=player.Character
    if character then for _,obj in ipairs(character:GetChildren()) do if obj:IsA("Tool") then report.tools[#report.tools+1]={name=obj.Name,attributes=attributes(obj)} end end end
end
local groupKeys={}
local function drain()
    local count=0
    while probe.head<=probe.tail and count<80 do
        local row=probe.queue[probe.head] probe.queue[probe.head]=nil probe.head=probe.head+1 count=count+1
        local info=remoteInfo[row.obj]
        if info then
            local args={}
            for i=1,row.args.n do args[tostring(i)]=short(row.args[i],0,{left=25}) vectorLeaves(row.args[i],info.path.."/"..row.kind.."/arg"..i,0,{left=30}) end
            local encoded=Http:JSONEncode(args)
            local action=type(row.args[1])=="string" and row.args[1]:sub(1,40) or ""
            local key=row.kind..info.path..row.method..action
            local group=groupKeys[key]
            if not group and #report.calls<22 then
                group={kind=row.kind,path=info.path,class=info.class,related=info.related,method=row.method,action=action,count=0,first=row.time-started,variants={}}
                groupKeys[key]=group report.calls[#report.calls+1]=group
            end
            if group then
                group.count=group.count+1 group.last=row.time-started
                local found=false
                for _,variant in ipairs(group.variants) do if variant.signature==encoded then variant.count=variant.count+1 variant.last=row.time-started found=true break end end
                if not found then
                    if #group.variants<3 then group.variants[#group.variants+1]={signature=encoded,args=args,argCount=row.args.totalN or row.args.n,count=1,first=row.time-started,last=row.time-started}
                    else group.otherVariants=(group.otherVariants or 0)+1 group.lastArgs=args end
                end
            end
        end
    end
    if probe.head>probe.tail then probe.head=1 probe.tail=0 probe.queue={} end
end
local noisy={DropperClick=true,BronzeDropperClick=true,CollectPart=true,MobAttackMlt=true,TreeHit=true,AutoTreeHit=true,EnemySwing=true,EnemyDamaged=true,EnemyKilled=true,CrystalDestroyed=true,UpdateGlobalMilestones=true,RockDestroyed=true,Smelter=true,RockDamaged=true,Upgrade=true,Merchant=true}
local function attachRemote(obj)
    if remoteInfo[obj] or (not obj:IsA("RemoteEvent") and not obj:IsA("RemoteFunction")) then return end
    local info={path=path(obj),class=obj.ClassName,related=word(obj.Name)} remoteInfo[obj]=info
    if noisy[obj.Name] and not info.related then return end
    probe.allowed[obj]=true
    if #report.remoteInventory<35 then report.remoteInventory[#report.remoteInventory+1]=info end
    if obj:IsA("RemoteEvent") then listen(obj.OnClientEvent,function(...)
        if not running then return end
        if obj.Name=="TreasureHunting" and onTreasure then onTreasure(...) end
        local action=select(1,...)
        if info.related or probe.seen[obj] or os.clock()-lastTap<.4 or (type(action)=="string" and stateWord(action)) then enqueue("receive",obj,"OnClientEvent",...) end
    end) end
end

-- Leitura de metadados; copias de script/protos nao sao executados.
local function inspectLogic(token)
    local dbg=debug or {}
    local constants=dbg.getconstants or env.getconstants local upvalues=dbg.getupvalues or env.getupvalues
    local protos=dbg.getprotos or env.getprotos local proto=dbg.getproto or env.getproto
    local connections=getconnections or env.getconnections local closure=getscriptclosure or env.getscriptclosure local gc=getgc or env.getgc
    report.logic.capabilities={constants=type(constants)=="function",upvalues=type(upvalues)=="function",protos=type(protos)=="function",activeProto=type(proto)=="function",connections=type(connections)=="function",scriptClosure=type(closure)=="function",gc=type(gc)=="function"}
    local queue,seen,scripts={},setmetatable({}, {__mode="k"}),{}
    local function source(fn)
        local s,name,script="","",nil
        if dbg.info then pcall(function() s,name=dbg.info(fn,"sn") end) end
        if type(getfenv)=="function" then pcall(function() local e=getfenv(fn) script=rawget(e,"script") if typeof(script)=="Instance" then s=path(script) end end) end
        return tostring(s or ""),tostring(name or "")
    end
    local function addFunction(fn,origin,live,owner,depth)
        if type(fn)~="function" or own[fn] or seen[fn] or #queue>=160 then return end
        seen[fn]=true queue[#queue+1]={fn=fn,origin=origin,live=live,owner=owner,depth=depth or 0}
    end
    local function owned(fn)
        if type(fn)~="function" or own[fn] then return false end
        local s=source(fn) local l=s:lower()
        return l:find("playerscripts",1,true) and word(l) and not l:find("coregui",1,true)
    end
    local ps=player:FindFirstChild("PlayerScripts") local client=ps and ps:FindFirstChild("Client")
    local components=client and client:FindFirstChild("Components")
    if components then
        for i,obj in ipairs(components:GetDescendants()) do
            if not current(token) then return end
            if (obj:IsA("ModuleScript") or obj:IsA("LocalScript")) and word(obj.Name) and #scripts<6 then scripts[#scripts+1]=obj end
            if i%80==0 then task.wait(.025) end
        end
    end
    for _,script in ipairs(scripts) do
        report.logic.scripts[#report.logic.scripts+1]=path(script)
        if type(closure)=="function" then local ok,fn=pcall(closure,script) if ok then addFunction(fn,"script-copy",false,path(script)) end end
        task.wait(.025) if not current(token) then return end
    end
    if type(connections)=="function" then
        local signals={{Run.RenderStepped,"RenderStepped"},{UIS.InputBegan,"InputBegan"}}
        if refs.button then signals[#signals+1]={refs.button.Activated,"Dig.Activated"} signals[#signals+1]={refs.button.MouseButton1Click,"Dig.MouseButton1Click"} end
        for obj,info in pairs(remoteInfo) do if info.related and obj:IsA("RemoteEvent") then signals[#signals+1]={obj.OnClientEvent,info.path} end end
        for _,item in ipairs(signals) do
            local ok,list=pcall(connections,item[1])
            if ok and type(list)=="table" then
                local summary={source=item[2],foreign=0,accessible=0,total=0}
                for i,c in ipairs(list) do
                    if i>100 then summary.truncated=true break end summary.total=summary.total+1
                    local good,fn,foreign=pcall(function() return c.Function,c.ForeignState end)
                    if good and foreign then summary.foreign=summary.foreign+1 end
                    if good and not foreign and owned(fn) then summary.accessible=summary.accessible+1 addFunction(fn,item[2],true) end
                end
                report.logic.signals[#report.logic.signals+1]=summary
            end
            task.wait(.025) if not current(token) then return end
        end
    end
    local head=1
    local function process()
        while current(token) and head<=#queue do
            local entry=queue[head] head=head+1
            local src,name=source(entry.fn) if src=="" then src=entry.owner or "" end
            local row={source=src,name=name,origin=entry.origin,kind=entry.live and "active-reference" or "metadata-only",constants={},upvalues={},score=0}
            if src:find("TreasureHunting",1,true) then row.score=row.score+100 end
            if type(constants)=="function" then
                local ok,values=pcall(constants,entry.fn)
                if ok and type(values)=="table" then
                    local n=0
                    for k,v in next,values do
                        n=n+1 if n>240 then break end
                        if type(v)=="string" and stateWord(v) then row.score=row.score+10 if #row.constants<24 then row.constants[#row.constants+1]={index=tostring(k),value=v:sub(1,75)} end
                        elseif type(v)=="number" and v==v and math.abs(v)<=100 and #row.constants<24 then row.constants[#row.constants+1]={index=tostring(k),value=v} end
                    end
                end
            end
            if entry.live and type(upvalues)=="function" then
                if #monitored<4 and (src:find("TreasureHunting",1,true) or src:find("Detector",1,true)) then monitored[#monitored+1]={fn=entry.fn,source=src,name=name} end
                local ok,values=pcall(upvalues,entry.fn)
                if ok and type(values)=="table" then
                    local n=0
                    for k,v in next,values do
                        n=n+1 if n>28 then break end
                        if type(v)=="function" then addFunction(v,"upvalue:"..tostring(k),true,src,entry.depth+1)
                        elseif typeof(v)=="Vector3" then row.upvalues[#row.upvalues+1]={index=tostring(k),value=short(v,0,{left=8})} candidate(v,src.."/upvalue"..k)
                        elseif type(v)=="number" or type(v)=="boolean" then if #row.upvalues<8 then row.upvalues[#row.upvalues+1]={index=tostring(k),value=v} end
                        elseif type(v)=="table" then
                            local fields,count={},0
                            for key,x in next,v do
                                count=count+1 if count>80 then break end
                                if type(key)=="string" and stateWord(key) and #fields<5 then
                                    fields[#fields+1]={key=key,value=short(x,0,{left=8})} vectorLeaves(x,src.."/"..key,0,{left=20})
                                    if type(x)=="function" then addFunction(x,"field:"..key,true,src,entry.depth+1) end
                                end
                            end
                            if #fields>0 and #row.upvalues<8 then row.upvalues[#row.upvalues+1]={index=tostring(k),fields=fields} end
                        end
                    end
                end
            end
            if row.score>0 or word(name) then
                report.logic.functions[#report.logic.functions+1]=row
                table.sort(report.logic.functions,function(a,b) return a.score>b.score end)
                if #report.logic.functions>8 then table.remove(report.logic.functions) end
            end
            if entry.depth<5 and type(protos)=="function" then
                local ok,list=pcall(protos,entry.fn)
                if ok and type(list)=="table" then for index,fn in pairs(list) do
                    addFunction(fn,"prototype:"..tostring(index),false,src,entry.depth+1)
                    if type(proto)=="function" then local good,active=pcall(proto,entry.fn,index,true) if good and type(active)=="table" then for i,live in ipairs(active) do if i>3 then break end addFunction(live,"active-proto",true,src,entry.depth+1) end end end
                end end
            end
            report.logic.inspected=head-1 task.wait(.025)
        end
    end
    process()
    if current(token) and #monitored==0 and type(gc)=="function" then
        local ok,list=pcall(gc,false)
        if ok and type(list)=="table" then for i,fn in ipairs(list) do
            if i>10000 or not current(token) then break end
            if type(fn)=="function" and owned(fn) then addFunction(fn,"gc-owner",true) end
            if i%64==0 then task.wait(.025) end
        end end
        process()
    end
    if current(token) then report.logic.status=#monitored>0 and "active_references_found" or (#report.logic.functions>0 and "metadata_only" or "no_accessible_dig_function") end
end

-- Protocolo visto no debug: Dig(); Strike(layerToken, horario atual).
-- Layer: token, inicio, indice, centro e largura. Campos adicionais sao preservados.
local function treasureRemote()
    local remotes=RS:FindFirstChild("Remotes")
    local remote=remotes and remotes:FindFirstChild("TreasureHunting")
    return remote and remote:IsA("RemoteEvent") and remote or nil
end
local function autoLog(kind,action,extra)
    if report.auto then add(report.auto.events,{t=at(),kind=kind,action=action,data=extra},14) end
end
local function send(action,...)
    local remote=treasureRemote()
    if not remote then auto.phase="Remote TreasureHunting ausente" return false end
    local args=table.pack(...)
    local ok,err=pcall(function() remote:FireServer(action,table.unpack(args,1,args.n)) end)
    if not ok then auto.phase="Falha ao enviar "..action autoLog("error",action,tostring(err):sub(1,150)) end
    return ok
end
local function serverNow()
    local ok,value=pcall(function() return workspace:GetServerTimeNow() end)
    if ok and type(value)=="number" then return value end
    if report.auto then report.auto.clockError="GetServerTimeNow indisponivel" end
end
local function sync()
    if os.clock()-(auto.lastSync or -math.huge)<1 then return end
    auto.lastSync=os.clock() send("Sync")
end
local function jumpToSpot()
    if not auto.enabled or not auto.tp or not auto.spot or auto.jumpedKey==auto.spot.key then return end
    local character=player.Character local root=character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local target=auto.spot.position
    if (root.Position-target).Magnitude>500 then auto.phase="Ponto fora da area de teste" return end
    local ok,err=pcall(function()
        local y=math.abs(root.Position.Y-target.Y)<8 and root.Position.Y or target.Y+3
        root.CFrame=CFrame.new(target.X,y,target.Z)*root.CFrame.Rotation
        root.AssemblyLinearVelocity=Vector3.new(0,0,0)
    end)
    if ok then
        auto.jumpedKey=auto.spot.key auto.settleUntil=os.clock()+.12
        report.auto.teleports=report.auto.teleports+1 autoLog("local","TP",vec(target))
    else auto.phase="TP indisponivel" autoLog("error","TP",tostring(err):sub(1,120)) end
end
onTreasure=function(action,...)
    local args=table.pack(...)
    if action=="Spot" then
        local target=args[2]
        if typeof(target)~="Vector3" then return end
        local key=tostring(args[1])..string.format("/%.3f/%.3f",target.X,target.Z)
        if not auto.spot or auto.spot.key~=key then
            auto.spot={id=args[1],position=target,key=key,receivedAt=os.clock()}
            auto.layer=nil auto.pending=nil auto.lastDig=-math.huge auto.jumpedKey=nil
            if auto.enabled then auto.phase="Aguardando alcance para Dig" autoLog("server","Spot",{id=args[1],position=vec(target)}) end
        end
        if report.auto then report.auto.spot={id=args[1],position=vec(target)} end
        if auto.enabled then jumpToSpot() end
    elseif action=="Layer" then
        if (type(args[1])~="number" and type(args[1])~="string") or type(args[2])~="number" then return end
        local key=tostring(args[1]).."/"..tostring(args[3]).."/"..tostring(args[2])
        if not auto.layer or auto.layer.key~=key then
            auto.layer={id=args[1],started=args[2],index=args[3],center=args[4],width=args[5],receivedAt=os.clock(),key=key,armed=true}
            auto.pending=nil auto.phase=auto.enabled and "Esperando o traco entrar no verde" or "OFF"
        end
        cacheFast()
        if visual then testZone(false,true) end
        local record={token=args[1],started=args[2],index=args[3],center=args[4],width=args[5],argCount=args.n+1,extra={}}
        for i=6,math.min(args.n,11) do record.extra[tostring(i+1)]=short(args[i],0,{left=12}) end
        if report.auto then report.auto.layer=record end
        autoLog("server","Layer",record)
    elseif action=="Hit" then
        local visualReply=visual~=nil
        if visual then
            visual.record.accepted=args[1] visual.record.replyAt=at()
            visual.record.replyGeometry=geometry()
            testZone(false)
        end
        if auto.enabled then
            local pending=auto.pending auto.pending=nil
            if visualReply and args[1]==true and auto.layer then auto.layer.completed=true end
            if pending and auto.layer and pending.layerKey==auto.layer.key then
                local rtt=os.clock()-pending.sentAt
                auto.rtt=auto.rtt and auto.rtt*.75+rtt*.25 or rtt report.auto.replyMs=math.floor(auto.rtt*1000+.5)
                if args[1]==true then
                    report.auto.confirmedHits=report.auto.confirmedHits+1 auto.layer.completed=true
                    auto.phase="Acerto confirmado; aguardando camada"
                else
                    report.auto.misses=report.auto.misses+1 auto.layer.armed=false auto.layer.retryAfter=os.clock()+.15
                    auto.phase="Errou; aguardando proxima passagem"
                end
            end
            autoLog("server","Hit",{accepted=args[1],value2=short(args[2],0,{left=8}),value3=short(args[3],0,{left=8})})
        end
    elseif action=="Found" then
        if visual then testZone(false) end
        if auto.enabled then
            report.auto.foundWhileEnabled=report.auto.foundWhileEnabled+1
            autoLog("server","Found",{item=short(args[1],0,{left=8}),amount=short(args[2],0,{left=8})})
        end
        auto.layer=nil auto.pending=nil auto.spot=nil auto.phase=auto.enabled and "Gamepass buscando o proximo ponto" or "OFF"
        auto.waitingSince=os.clock()
    elseif action=="Exit" or action=="Leave" then
        auto.spot=nil auto.layer=nil auto.pending=nil auto.phase=auto.enabled and "Entre na praia com o detector" or "OFF"
    end
end
autoStep=function()
    if not auto.enabled or not running then return end
    local now=os.clock()
    if now<(auto.settleUntil or 0) then return end
    if auto.layer then
        local layer=auto.layer
        if visual or visualPending then auto.phase="Teste verde: toque Dig fora da faixa original" return end
        if layer.completed then
            if now-layer.receivedAt>2 and now-(auto.lastSync or 0)>2 then sync() end
            return
        end
        if auto.pending then
            local limit=math.clamp((auto.rtt or .07)*2.5+.025,.16,.55)
            if now-auto.pending.sentAt<limit then return end
            autoLog("timeout","Strike") auto.pending=nil layer.armed=true layer.retryAfter=now
            report.auto.timeouts=report.auto.timeouts+1
            layer.retries=(layer.retries or 0)+1
            if layer.retries>2 then layer.retryAfter=now+.3 sync() end
        end
        local g=geometry()
        if not g or not refs.track or not shown(refs.track) or not shown(refs.zone) or not shown(refs.marker) then auto.phase="Camada recebida; aguardando traco visivel" return end
        if visual then
            -- A automacao usa a faixa original mesmo durante o teste visual.
            g.greenStart=visual.originalStart g.greenWidth=visual.originalWidth
        end
        if type(layer.center)=="number" and type(layer.width)=="number" and (math.abs(g.greenStart+g.greenWidth*.5-layer.center)>.02 or math.abs(g.greenWidth-layer.width)>.02) then
            auto.phase="Aguardando a faixa da camada atual" return
        end
        local margin=g.mode=="scale_properties" and .006 or .025
        margin=math.min(margin,g.greenWidth*.08)
        local inside=g.cursor>=g.greenStart+margin and g.cursor<=g.greenStart+g.greenWidth-margin
        if not inside then layer.armed=true return end
        if not layer.firstGreenAt then layer.firstGreenAt=now end
        if not layer.armed or now<(layer.retryAfter or 0) then return end
        local timestamp=serverNow() if not timestamp then auto.phase="Sem relogio para Strike" return end
        if timestamp<layer.started+.004 then return end
        layer.armed=false auto.pending={sentAt=now,layerKey=layer.key}
        auto.phase="Enviando Strike no verde"
        report.auto.strikes=report.auto.strikes+1
        autoLog("send","Strike",{token=layer.id,time=timestamp,geometry=g,layerAge=timestamp-layer.started,greenReactionMs=math.floor((now-layer.firstGreenAt)*1000+.5)})
        if not send("Strike",layer.id,timestamp) then auto.pending=nil layer.retryAfter=now+.5 end
        return
    end
    if not auto.spot then
        auto.phase="Aguardando ponto da gamepass"
        if now-(auto.waitingSince or now)>.8 then sync() end
        return
    end
    jumpToSpot()
    if now<(auto.settleUntil or 0) then return end
    local p=position() if not p then auto.phase="Aguardando personagem" return end
    local target=auto.spot.position local dx,dz=p.X-target.X,p.Z-target.Z
    local _,signal=readHud()
    local near=dx*dx+dz*dz<=3.2*3.2
    if not near and (not signal or signal<90) then auto.phase="Gamepass aproximando do ponto" return end
    if now-(auto.lastDig or -math.huge)<.45 then return end
    auto.lastDig=now auto.phase="Iniciando Dig"
    report.auto.digs=report.auto.digs+1 autoLog("send","Dig") send("Dig")
end
toggleAuto=function(value)
    if value==nil then value=not auto.enabled end
    if value and not running then start(true) end
    auto.enabled=value==true and running
    autoButton.Text=auto.enabled and "Auto Dig: ON" or "Auto Dig: OFF"
    if report.auto then report.auto.enabled=auto.enabled end
    if auto.enabled then
        auto.waitingSince=os.clock() auto.lastDig=-math.huge
        auto.phase="Aguardando estado da gamepass"
        if auto.layer then auto.layer.armed=true auto.layer.completed=false end
        sync() jumpToSpot()
    else auto.phase="OFF" auto.pending=nil end
end
toggleTP=function(value)
    if value==nil then value=not auto.tp end
    auto.tp=value==true tpButton.Text=auto.tp and "TP ao ponto: ON" or "TP ao ponto: OFF"
    if report.auto then report.auto.tp=auto.tp end
    if auto.tp then jumpToSpot() end
end

testZone=function(value,preserveGameChange)
    if value==nil then value=visual==nil and not visualPending end
    if not value then visualPending=false end
    if not value and visual then
        local old=visual visual=nil
        local function same(a,b) return a.X.Scale==b.X.Scale and a.X.Offset==b.X.Offset and a.Y.Scale==b.Y.Scale and a.Y.Offset==b.Y.Offset end
        pcall(function()
            if same(old.obj.Size,old.testSize) then old.obj.Size=old.size old.record.restoredSize=true end
            if same(old.obj.Position,old.testPosition) then old.obj.Position=old.position old.record.restoredPosition=true end
        end)
        old.record.gameChanged=preserveGameChange or nil
        old.record.stoppedAt=at() testButton.Text="Testar faixa verde: OFF" return
    end
    if not value then testButton.Text="Testar faixa verde: OFF" return end
    if not running then start(true) end
    cacheFast()
    if not refs.zone or not refs.zone.Parent or not refs.marker or not shown(refs.zone) or not shown(refs.marker) or (auto.enabled and not auto.layer) then
        visualPending=true testButton.Text="Teste verde: aguardando barra"
        label.Text="Teste armado para a proxima barra. O Auto pausa os golpes para voce testar um clique." return
    end
    if visual then return end
    local g=geometry() if not g then return end
    local zone=refs.zone
    local _,_,hudLayer=readHud()
    local row={startedAt=at(),path=path(zone),layer=hudLayer,originalStart=g.greenStart,originalWidth=g.greenWidth,taps=0,outsideOriginalTaps=0,transitions={},changes="visual_only"}
    add(report.visualTests,row,4)
    visualPending=false
    visual={obj=zone,size=zone.Size,position=zone.Position,record=row,hudLayer=hudLayer,originalStart=g.greenStart,originalWidth=g.greenWidth,expiresAt=os.clock()+8,
        testSize=UDim2.new(1,0,zone.Size.Y.Scale,zone.Size.Y.Offset),testPosition=UDim2.new(zone.AnchorPoint.X,0,zone.Position.Y.Scale,zone.Position.Y.Offset)}
    zone.Size=visual.testSize zone.Position=visual.testPosition
    testButton.Text="Restaurar faixa verde"
    label.Text="Faixa VISUAL ampliada. Compare um clique fora da faixa original; camada e eventos dirao se foi aceito."
end

local stepping=false
pulse=function()
    if not running or stepping then return end
    stepping=true
    local ok,err=pcall(function()
        if not refs.zone or not refs.zone.Parent or not refs.marker or not refs.marker.Parent then cacheFast() end
        if visual and os.clock()>visual.expiresAt then testZone(false) end
        if visualPending and refs.zone and refs.marker and shown(refs.zone) and shown(refs.marker) and (not auto.enabled or auto.layer) then testZone(true) end
        if auto.enabled then autoStep() end
    end)
    stepping=false
    if not ok then autoLog("error","controller",tostring(err):sub(1,180)) toggleAuto(false) auto.phase="Erro no controle; copie o resultado" end
end

local lastPhase,lastLayer,lastHud="unknown",nil,""
local movement=nil local lastPos,lastPosAt=nil,nil
local function sampleState()
    if not running then return end
    local phase,signal,layer,texts=readHud() local g=geometry() local t=at()
    report.ui={phase=phase,signal=signal,layer=layer,texts=texts,geometry=g}
    local hudKey=Http:JSONEncode(texts)
    if hudKey~=lastHud then add(report.messages,{t=t,phase=phase,layer=layer,texts=texts,visualTest=visual~=nil},12) lastHud=hudKey end
    if phase~=lastPhase or layer~=lastLayer then
        local event={t=t,from=lastPhase,to=phase,layer=layer,signal=signal,visualTest=visual~=nil}
        add(report.transitions,event,18)
        if visual then
            add(visual.record.transitions,event,6)
            if (visual.hudLayer and layer and layer~=visual.hudLayer) or phase=="searching" or phase=="signal" then
                -- A new layer can already have written new coordinates: never put stale ones over it.
                local changed=visual.obj.Size.X.Scale<.99 or visual.obj.Position.X.Scale~=visual.obj.AnchorPoint.X or visual.obj.Position.X.Offset~=0
                testZone(false,changed)
            end
        end
        lastPhase,lastLayer=phase,layer
    end
    if visual then
        if refs.zone.Size.X.Scale<.99 then visual.record.overwrittenByGameAt=t testZone(false,true)
        elseif g then visual.record.observedWidth=g.greenWidth end
    end
    local p=position()
    if p and lastPos then
        local distance=(p-lastPos).Magnitude
        if distance>.3 then
            if not movement then movement={from=vec(lastPos),to=vec(p),started=lastPosAt or t,ended=t,distance=0,maxStep=0} add(report.movement,movement,10) end
            movement.to=vec(p) movement.ended=t movement.distance=movement.distance+distance movement.maxStep=math.max(movement.maxStep,distance)
            for _,target in ipairs(report.targets) do if not target.firstMovementAfter and target.firstSeen<=t then target.firstMovementAfter=t end end
        elseif movement and t-movement.ended>.25 then movement=nil end
    end
    if p then
        for _,target in ipairs(report.targets) do
            local v=Vector3.new(target.position.x,target.position.y,target.position.z) local distance=(p-v).Magnitude
            target.minDistance=math.min(target.minDistance or math.huge,distance)
            if distance<3.5 and not target.arrivedAt then target.arrivedAt=t target.leadSeconds=t-target.firstSeen end
        end
        lastPos=p lastPosAt=t
    end
    local getup=(debug and debug.getupvalues) or env.getupvalues
    if type(getup)=="function" then
        for _,entry in ipairs(monitored) do
            local ok,values=pcall(getup,entry.fn)
            if ok and type(values)=="table" then
                local count,state=0,{}
                for key,v in next,values do
                    count=count+1 if count>24 then break end
                    if (type(v)=="boolean" or type(v)=="number") and #state<8 then state[#state+1]={index=tostring(key),value=short(v,0,{left=3})} end
                    if typeof(v)=="Vector3" then candidate(v,entry.source.."/upvalue"..key)
                    elseif type(v)=="table" then
                        local n=0 for k,x in next,v do n=n+1 if n>70 then break end if type(k)=="string" and stateWord(k) then vectorLeaves(x,entry.source.."/"..k,0,{left=20}) end end
                    end
                end
                local signature=Http:JSONEncode(state)
                if #state>0 and signature~=entry.lastState then
                    entry.lastState=signature add(report.logic.states,{t=t,source=entry.source,values=state,layer=layer,geometry=g},10)
                end
            end
        end
    end
end
local function updateLabel()
    if visual or visualPending then return end
    if auto.enabled then label.Text=auto.phase.."\n"..(refs.zone and "Faixa/traco detectados" or "Aguardando a interface Dig").."\nUse Parar / copiar para enviar o teste."
    elseif running then label.Text="Gravando: "..math.floor(at()).."/30 s\n"..(refs.button and "Dig detectado" or "Procurando o botao Dig...").." | "..#report.calls.." grupos de eventos\nComplete um ciclo normal; o teste da faixa e opcional."
    else label.Text="Parado. Use Copiar resultado para enviar o diagnostico." end
end
copy=function()
    if report.auto then report.auto.phase=auto.phase report.auto.enabled=auto.enabled report.auto.geometry=geometry() end
    local export={} for k,v in pairs(report) do export[k]=v end
    export.running=running export.seconds=running and at() or (report.seconds or 0) export.dropped=(report.dropped or 0)+(probe.dropped or 0)
    export.calls={}
    for _,group in ipairs(report.calls or {}) do
        local g={} for k,v in pairs(group) do if k~="variants" then g[k]=v end end g.variants={}
        for _,variant in ipairs(group.variants) do local v={} for k,x in pairs(variant) do if k~="signature" then v[k]=x end end g.variants[#g.variants+1]=v end
        export.calls[#export.calls+1]=g
    end
    if report.logic then
        export.logic={} for k,v in pairs(report.logic) do if k~="functions" then export.logic[k]=v end end export.logic.functions={}
        for _,fn in ipairs(report.logic.functions) do local r={} for k,v in pairs(fn) do r[k]=v end export.logic.functions[#export.logic.functions+1]=r end
    end
    local payload=Http:JSONEncode(export)
    if #payload>19000 then
        export.trimmed=true export.remoteInventory=nil
        for _,f in ipairs(export.logic and export.logic.functions or {}) do
            local rows={} for i,row in ipairs(f.constants or {}) do if i<=16 then rows[#rows+1]=row end end f.constants=rows
        end
        payload=Http:JSONEncode(export)
    end
    while #payload>19000 and export.logic and #export.logic.functions>2 do table.remove(export.logic.functions) payload=Http:JSONEncode(export) end
    if #payload>19000 then
        export.world=nil
        local function recent(list,count) local r={} for i=math.max(1,#list-count+1),#list do r[#r+1]=list[i] end return r end
        export.messages=recent(export.messages or {},6) export.taps=recent(export.taps or {},10)
        local targets={} for _,target in ipairs(export.targets or {}) do if target.source and target.source:find("Remotes.TreasureHunting",1,true) then targets[#targets+1]=target end end
        export.targets=recent(targets,6)
        if export.logic then export.logic.states=recent(export.logic.states or {},4) end
        for _,g in ipairs(export.calls) do while #g.variants>1 do table.remove(g.variants) end g.lastArgs=nil end
        payload=Http:JSONEncode(export)
    end
    while #payload>19000 and #export.calls>8 do
        local index=#export.calls
        for i=#export.calls,1,-1 do if not export.calls[i].related then index=i break end end
        table.remove(export.calls,index) export.trimmedGroups=(export.trimmedGroups or 0)+1 payload=Http:JSONEncode(export)
    end
    while #payload>19000 do
        if #(export.messages or {})>2 then table.remove(export.messages,1)
        elseif #(export.taps or {})>4 then table.remove(export.taps,1)
        elseif export.logic then export.logic=nil
        elseif export.geometry then export.geometry=nil
        elseif #export.calls>3 then
            local index=#export.calls
            for i=#export.calls,1,-1 do if export.calls[i].action=="Sync" or not export.calls[i].related then index=i break end end
            table.remove(export.calls,index) export.trimmedGroups=(export.trimmedGroups or 0)+1
        else break end
        payload=Http:JSONEncode(export)
    end
    env.DigDebugReport=payload
    local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard local ok,result=false,nil
    if type(clip)=="function" then ok,result=pcall(clip,payload) end
    output.Text=payload output.Visible=not(ok and result~=false)
    if output.Visible then panel.Visible=true mini.Visible=false end
    return payload
end
stop=function(shouldCopy)
    visualPending=false
    toggleAuto(false)
    if running then drain() testZone(false) running=false generation=generation+1 probe.enabled=false probe.allowed={} disconnect(sessionLinks)
        report.seconds=at() report.running=false end
    startButton.Text="Iniciar debug (30 s)" updateLabel()
    if shouldCopy~=false then return copy() end
end
start=function(lightMode)
    if not alive or running then return end
    started=os.clock() running=true generation=generation+1 local token=generation refs={objects={}}
    bound=setmetatable({}, {__mode="k"}) pendingButtons={} targetKeys={} groupKeys={} remoteInfo={} monitored={}
    lastPhase,lastLayer,lastHud="unknown",nil,"" movement=nil lastPos=nil lastPosAt=nil lastTap=-math.huge
    auto={enabled=false,tp=auto.tp,phase="OFF",waitingSince=os.clock()} visualPending=false
    report={format="dig-debug-v3-reactive",placeId=game.PlaceId,note="Auto por posicao atual do traco, sem clique de tela. TP opcional para Spot. Faixa visual tem teste manual separado e nao prova tolerancia real. Found enquanto ligado nao distingue ajuda manual.",
        calls={},remoteInventory={},taps={},transitions={},messages={},targets={},movement={},visualTests={},dropped=0,logic={status="scanning",scripts={},signals={},functions={},states={}},world={},tools={}}
    report.auto={enabled=false,tp=auto.tp,digs=0,strikes=0,confirmedHits=0,misses=0,foundWhileEnabled=0,teleports=0,timeouts=0,events={}}
    probe.enabled=false probe.queue={} probe.head=1 probe.tail=0 probe.dropped=0 probe.allowed={} probe.seen={}
    local remotes=RS:FindFirstChild("Remotes")
    if remotes then for _,obj in ipairs(remotes:GetDescendants()) do attachRemote(obj) end listen(remotes.DescendantAdded,attachRemote) end
    local supported,err=installProbe() report.outgoingCapture=supported report.captureError=err probe.enabled=supported
    cacheFast()
    listen(Run.RenderStepped,function() if current(token) then pulse() end end)
    if Run.Heartbeat then listen(Run.Heartbeat,function() if current(token) then pulse() end end) end
    listen(pg.DescendantAdded,function(obj)
        if obj:IsA("GuiButton") and not obj:IsDescendantOf(gui) then
            if #pendingButtons<320 then pendingButtons[#pendingButtons+1]=obj end
            (task.defer or task.spawn)(function() if current(token) then bindButton(obj) end end)
        end
    end)
    startButton.Text="Debug gravando..." output.Visible=false
    task.spawn(function()
        local ok,err=pcall(function()
            if not refs.button then discoverUi(token) end
            if current(token) then cacheFast() end
            if lightMode==true or auto.enabled then report.logic.status="light_auto_mode"
            else if current(token) then inspectWorld(token) end if current(token) then inspectLogic(token) end end
        end)
        if not ok and current(token) then report.logic.error=tostring(err):sub(1,220) end
    end)
    task.spawn(function()
        local refreshAt=-math.huge
        while current(token) and (at()<30 or auto.enabled) do
            drain()
            if at()-refreshAt>.5 then
                refreshAt=at()
                for _,obj in ipairs(pendingButtons) do if obj.Parent and not bound[obj] then bindButton(obj) end end
                refreshObjects() findGeometry()
            end
            sampleState() updateLabel() task.wait(.1)
        end
        if current(token) then stop(true) end
    end)
end
close=function()
    if not alive then return end stop(false) alive=false disconnect(links) gui:Destroy()
end
env.DigDebug={Start=start,Stop=stop,Copy=copy,Close=close,TestZone=testZone,ToggleAuto=toggleAuto,ToggleTP=toggleTP,GetReport=function() return report end}
listen(startButton.Activated,start,links)
listen(stopButton.Activated,function() stop(true) end,links)
listen(copyButton.Activated,copy,links)
listen(testButton.Activated,function() testZone() end,links)
listen(autoButton.Activated,function() toggleAuto() end,links)
listen(tpButton.Activated,function() toggleTP() end,links)
listen(exit.Activated,close,links)
listen(minimize.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end,links)
listen(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false end,links)
local dragging,dragInput,inputStart,panelStart
listen(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true dragInput=input.UserInputType==Enum.UserInputType.Touch and input or nil inputStart=input.Position panelStart=panel.Position
    end
end,links)
listen(UIS.InputChanged,function(input)
    if dragging and ((dragInput and input==dragInput) or (not dragInput and input.UserInputType==Enum.UserInputType.MouseMovement)) then
        local delta=input.Position-inputStart local view=workspace.CurrentCamera.ViewportSize
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+delta.X,0,math.max(0,view.X-330)),math.clamp(panelStart.Y.Scale*view.Y+panelStart.Y.Offset+delta.Y,0,math.max(0,view.Y-335)))
    end
end,links)
listen(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end,links)

