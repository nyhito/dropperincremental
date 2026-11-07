-- Auto Scrap PC v3 / debug. Segura acima do alvo; recupera barra sem coleta.
-- Base 61,3,-432 / entrega 128,3,-407. Sem alterar forca, barra ou pecas.
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local GS=game:GetService("GuiService")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
for _,name in ipairs({"ScrapPCDebug","BlackHoleCollectDebug","MagnetDebug","DigDebug"}) do
    local old=env[name] if old and type(old.Close)=="function" then pcall(old.Close) end
end
for _,name in ipairs({"__NetoMagnetProbe","__NetoMagnetHoldProbe"}) do
    local old=env[name] if type(old)=="table" then old.enabled=false old.hold=false end
end
local BASE,SELL=Vector3.new(61,3,-432),Vector3.new(128,3,-407)
local RESET=Vector3.new(44,3,-418)
local pg=player:WaitForChild("PlayerGui")
local alive,active,lastReport=true,nil,nil
local start,stop,copy,close,paint,setFrozen
local preferences={gold=false,void=false}
local lifetime={}
local restoreGeneration=0
local mobileToken={} env.__NetoScrapMobileToken=mobileToken
local mobile=UIS.TouchEnabled
local getup=(debug and debug.getupvalues) or env.getupvalues
local constants=(debug and debug.getconstants) or env.getconstants
local connections=getconnections or env.getconnections
local vim pcall(function() vim=game:GetService("VirtualInputManager") end)
local core pcall(function() core=game:GetService("CoreGui") end)
local function add(list,value,max) list[#list+1]=value if #list>max then table.remove(list,1) end end
local function path(obj) local ok,p=pcall(function() return obj:GetFullName() end) return ok and p or "removed" end
local function vec(p) return {x=p.X,y=p.Y,z=p.Z} end
local function valid(s) return alive and active==s and s.running end
local function event(s,action,data) add(s.report.events,{t=math.floor((os.clock()-s.started)*1000+.5)/1000,action=action,data=data},55) end
local function connect(sig,fn,list) if not sig then return end local c=sig:Connect(fn) list[#list+1]=c return c end
local function disconnect(list) for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end table.clear(list) end
local function shown(obj)
    for _=1,24 do
        if not obj then return false end
        if obj:IsA("GuiObject") and not obj.Visible then return false end
        if obj:IsA("ScreenGui") then return obj.Enabled end
        obj=obj.Parent
    end return false
end
local function hud(s)
    local front=pg:FindFirstChild("Front") local main=front and front:FindFirstChild("MainFrame")
    local frame=main and main:FindFirstChild("DebrisHUD") local track=frame and frame:FindFirstChild("Track")
    local count=frame and frame:FindFirstChild("Backpack") count=count and count:FindFirstChild("Count")
    local used,cap if count then used,cap=tostring(count.Text):match("(%d+)%s*/%s*(%d+)") end
    local note=track and track:FindFirstChild("Note") local fill=track and track:FindFirstChild("Fill")
    local u={visible=frame and shown(frame) or false,used=tonumber(used),capacity=tonumber(cap),progress=fill and fill.Size.X.Scale or 0,note=note and tostring(note.Text):gsub("<[^>]+>","") or ""}
    s.report.ui=u return u
end
local gui=Instance.new("ScreenGui") gui.Name="NetoScrapPCDebug" gui.ResetOnSpawn=false gui.IgnoreGuiInset=true gui.DisplayOrder=10040 gui.Parent=pg
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(302,250) panel.Position=UDim2.fromOffset(12,62)
panel.BackgroundColor3=Color3.fromRGB(20,23,31) panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,9)
local function button(text,x,y,w)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.GothamBold b.TextSize=12 b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(53,73,124) b.Size=UDim2.fromOffset(w,33) b.Position=UDim2.fromOffset(x,y) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="AUTO SCRAP • PC" title.Font=Enum.Font.GothamBold title.TextSize=14 title.Active=true
title.TextColor3=Color3.new(1,1,1) title.BackgroundTransparency=1 title.Size=UDim2.fromOffset(207,34) title.Parent=panel
local miniButton=button("−",217,1,34) local exitButton=button("X",257,1,34)
local toggleButton=button("Auto Scrap: OFF",10,40,282) local copyButton=button("Parar e copiar debug",10,79,282)
local goldButton=button("Ouro: OFF",10,118,137) local voidButton=button("Vazio: OFF",155,118,137)
local status=Instance.new("TextLabel") status.BackgroundTransparency=1 status.TextColor3=Color3.new(1,1,1)
status.TextSize=12 status.Font=Enum.Font.Gotham status.TextWrapped=true status.TextXAlignment=Enum.TextXAlignment.Left status.TextYAlignment=Enum.TextYAlignment.Top
status.Position=UDim2.fromOffset(10,159) status.Size=UDim2.fromOffset(282,83) status.Text="Segue acima do alvo, olhando para baixo.\nBarra falhou: TP de recuperação por 1 segundo.\nInicia em 3s. Abrir esta janela desliga." status.Parent=panel
local mini=Instance.new("TextButton") mini.Text="SCRAP" mini.Font=Enum.Font.GothamBold mini.TextSize=12 mini.TextColor3=Color3.new(1,1,1)
mini.BackgroundColor3=Color3.fromRGB(53,73,124) mini.Size=UDim2.fromOffset(78,36) mini.Position=panel.Position mini.Visible=false mini.Parent=gui
local function freePoint(x,y)
    if GS.MenuIsOpen then return false end
    for _,root in pairs({pg,core}) do
        local ok,hits=pcall(function() return root:GetGuiObjectsAtPosition(x,y) end)
        if ok and type(hits)=="table" then for _,obj in ipairs(hits) do
            if shown(obj) then
                local a=obj
                for _=1,15 do
                    if not a or a==root then break end
                    if a:IsA("GuiButton") or a:IsA("TextBox") then return false end
                    if a:IsA("GuiObject") and a.Active and (a.BackgroundTransparency<.99 or a==obj and a.Name=="InputShield") then return false end
                    -- Containers transparentes de tela inteira nao sao botoes.
                    if a:IsA("GuiObject") and a:IsDescendantOf(gui) and a.BackgroundTransparency<.99 then return false end
                    a=a.Parent
                end
            end
        end end
    end return true
end
local function pickPoint(s)
    local c=workspace.CurrentCamera if not c then return nil end
    local v=c.ViewportSize local p=s.point
    if p and p.vx==v.X and p.vy==v.Y and freePoint(p.x,p.y) then return p end
    for _,fraction in ipairs({{.5,.40},{.65,.32},{.78,.30},{.42,.34},{.9,.25},{.55,.22},{.94,.45}}) do
        local x,y=math.floor(v.X*fraction[1]),math.floor(v.Y*fraction[2])
        if freePoint(x,y) then s.point={x=x,y=y,vx=v.X,vy=v.Y} return s.point end
    end s.point=nil return nil
end
local function inputError(s,message)
    add(s.report.inputErrors,tostring(message):sub(1,200),8) event(s,"input_error",tostring(message):sub(1,120))
end
local function release(s)
    if not s.held and not s.needsRelease then return end
    local point=s.point or {x=500,y=200}
    if s.backend=="VirtualInput" and vim then
        local ok,err=pcall(function() vim:SendMouseButtonEvent(point.x,point.y,0,false,game,0) end)
        if not ok then inputError(s,err) end
    elseif s.backend=="Executor" and s.mouseRelease then
        local ok,err=pcall(s.mouseRelease) if not ok then inputError(s,err) end
    end
    if s.held then s.report.releases=s.report.releases+1 end
    s.held=false s.needsRelease=false s.report.held=false
end
local function press(s)
    if not valid(s) or s.held then return s.held end
    local p=pickPoint(s) if not p then s.report.phase="Sem ponto livre na tela" return false end
    local ok,err=false,"Entrada virtual indisponível"
    if s.backend~="Executor" and vim then
        s.backend="VirtualInput"
        ok,err=pcall(function() vim:SendMouseMoveEvent(p.x,p.y,game) s.needsRelease=true vim:SendMouseButtonEvent(p.x,p.y,0,true,game,0) end)
        if not ok then release(s) inputError(s,err) s.backend=nil end
    end
    if not ok then
        local down=mouse1press or env.mouse1press local up=mouse1release or env.mouse1release local move=mousemoveabs or env.mousemoveabs
        if type(down)=="function" and type(up)=="function" then
            s.backend="Executor" s.mouseRelease=up
            ok,err=pcall(function()
                if type(move)=="function" then move(p.x,p.y)
                elseif vim then vim:SendMouseMoveEvent(p.x,p.y,game)
                else error("Executor sem movimento do ponteiro") end
                s.needsRelease=true down()
            end)
            if not ok then release(s) inputError(s,err) end
        end
    end
    if not ok then error("Não foi possível segurar o mouse: "..tostring(err)) end
    s.held=true s.report.held=true s.report.backend=s.backend s.report.presses=s.report.presses+1
    s.lastPress=os.clock() event(s,"mouse_down",{backend=s.backend,x=p.x,y=p.y}) return true
end
local function pointer(s)
    local p=pickPoint(s) if not p then release(s) return false end
    if not s.held then return press(s) end
    if s.backend=="Executor" then
        local move=mousemoveabs or env.mousemoveabs
        if type(move)=="function" then move(p.x,p.y) elseif vim then vim:SendMouseMoveEvent(p.x,p.y,game) end
    elseif vim then vim:SendMouseMoveEvent(p.x,p.y,game) end
    -- Se outro toque soltar o mouse, reenvia somente DOWN; nunca faz clique/spam.
    if s.held and os.clock()-s.lastPress>.35 then
        local ok,down=pcall(function() return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)
        if (ok and not down) or s.inputLost then
            if s.backend=="VirtualInput" then vim:SendMouseButtonEvent(p.x,p.y,0,true,game,0)
            else (mouse1press or env.mouse1press)() end
            s.lastPress=os.clock() s.inputLost=false s.report.resyncs=s.report.resyncs+1
        end
    end
    return press(s)
end
local function restoreMobile(s)
    restoreGeneration=restoreGeneration+1 local generation=restoreGeneration
    local r={requested=mobile==true,errors={}} s.report.mobileRestore=r
    if not mobile then r.status="desktop" return end
    local function permitted() return not active and generation==restoreGeneration and env.__NetoScrapMobileToken==mobileToken end
    local function force()
        pcall(function() GS.TouchControlsEnabled=true r.touchControls=true end)
        local touch=pg:FindFirstChild("TouchGui")
        if touch then
            touch.Enabled=true local frame=touch:FindFirstChild("TouchControlFrame")
            if frame then frame.Visible=true local jump=frame:FindFirstChild("JumpButton",true) if jump then jump.Visible=true end end
            r.touchGui=true
        end
    end
    force()
    task.spawn(function()
        if not permitted() then return end
        local ok,err=pcall(function()
            local ps=player:FindFirstChild("PlayerScripts") local module=ps and ps:FindFirstChild("PlayerModule")
            if not module then return end
            local pm=require(module) if not permitted() then return end
            local controls=pm:GetControls() if not controls then return end
            if type(controls.OnLastInputTypeChanged)=="function" then controls:OnLastInputTypeChanged(Enum.UserInputType.Touch)
            elseif type(controls.OnPreferredInputChanged)=="function" then controls:OnPreferredInputChanged(Enum.PreferredInput.Touch) end
            if type(controls.SelectTouchModule)=="function" and type(controls.SwitchToController)=="function" then
                local selected=controls:SelectTouchModule() if selected then controls:SwitchToController(selected) end
            end
            if type(controls.Enable)=="function" then controls:Enable(true) end
            if controls.touchJumpController then controls.touchJumpController:Enable(true,controls.touchControlFrame) end
            if controls.touchControlFrame then controls.touchControlFrame.Visible=true end
            r.controller=true
        end)
        if not ok then add(r.errors,tostring(err):sub(1,140),4) end
    end)
    task.spawn(function()
        task.wait(.025) if not permitted() then return end
        local shield
        local ok,err=pcall(function()
            if not vim or type(vim.SendTouchEvent)~="function" then return end
            shield=Instance.new("ScreenGui") shield.Name="NetoScrapTouchRestore" shield.IgnoreGuiInset=true shield.DisplayOrder=2147483000 shield.Parent=pg
            local frame=Instance.new("Frame") frame.BackgroundTransparency=1 frame.Active=true frame.Size=UDim2.new(1,0,1,0) frame.Parent=shield
            local v=workspace.CurrentCamera.ViewportSize local x,y=math.floor(v.X*.5),math.floor(v.Y*.4)
            local id=980001
            local sent,message=pcall(function() vim:SendTouchEvent(id,0,x,y) end)
            local ended=pcall(function() vim:SendTouchEvent(id,2,x,y) end)
            r.nativeTouch=sent and ended if not sent then error(message) end
        end)
        if shield then shield:Destroy() end
        if not ok then add(r.errors,tostring(err):sub(1,140),4) end
        for _,delay in ipairs({0,.1,.3}) do
            if delay>0 then task.wait(delay) end if not permitted() then return end force()
        end
        pcall(function() r.lastInput=tostring(UIS:GetLastInputType()) end) r.status="done"
    end)
end
local function objectPosition(obj)
    if typeof(obj)~="Instance" or not obj.Parent then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then return obj:GetPivot().Position end
end
local function inField(obj)
    local field=workspace:FindFirstChild("DebrisField")
    return field and typeof(obj)=="Instance" and obj~=field and obj:IsDescendantOf(field)
end
local function chunkObject(row,depth)
    if typeof(row)=="Instance" then return inField(row) and row or nil end
    if type(row)~="table" or (depth or 0)>1 then return nil end
    for _,name in ipairs({"Object","Model","Part","Root","Visual","Chunk"}) do
        local obj=chunkObject(rawget(row,name),(depth or 0)+1) if obj then return obj end
    end
end
local function scanStep(s)
    if type(connections)~="function" or type(getup)~="function" or type(constants)~="function" then return end
    local ok,list=pcall(connections,Run.RenderStepped) if not ok or type(list)~="table" then return end
    for i,c in ipairs(list) do
        if i>120 then break end
        local good,fn=pcall(function() return not c.ForeignState and c.Function end)
        if good and type(fn)=="function" then
            local got,marks=pcall(constants,fn) local words={}
            if got and type(marks)=="table" then for _,v in pairs(marks) do if type(v)=="string" then words[v]=true end end end
            if words.DebrisMagnet and words.GetMagnetStrength and words.GetPullCount then
                local read,up=pcall(getup,fn) local hasPlayer,hasHUD=false,false
                if read and type(up)=="table" then for _,v in pairs(up) do
                    if v==player then hasPlayer=true end
                    if typeof(v)=="Instance" and v.Name=="DebrisHUD" then hasHUD=true end
                end end
                if hasPlayer and hasHUD then s.step=fn s.report.liveStep=true return end
            end
        end
    end
end
local function liveObjects(s)
    s.objects={} s.rows={} if not s.step and os.clock()>=(s.nextStep or 0) then s.nextStep=os.clock()+2 scanStep(s) end
    if not s.step then return end
    local ok,up=pcall(getup,s.step) if not ok or type(up)~="table" then return end
    for _,map in pairs(up) do
        if type(map)=="table" then
            local catalog=rawget(map,"Mutations")
            if type(catalog)=="table" then for key,entry in pairs(catalog) do
                if type(entry)=="table" then
                    local name=tostring(rawget(entry,"Name") or rawget(entry,"Label") or key):lower()
                    local label=(name=="gold" or name=="golden" or name=="ouro") and "Ouro" or (name=="void" or name=="vazio") and "Vazio"
                    if label then
                        local code=rawget(entry,"Id") or rawget(entry,"Index") or (type(key)=="number" and key)
                        if code~=nil then s.mutationCodes[code]=label end
                        local phase=rawget(entry,"Phase") if phase~=nil then s.phaseCodes[phase]=label end
                    end
                end
            end end
            local inspected=0
            for key,row in pairs(map) do
                inspected=inspected+1 if inspected>160 then break end
                if type(row)=="table" then
                    local id=rawget(row,"Id") or (type(key)=="number" and key)
                    local obj=id and chunkObject(row) if obj then s.objects[id]=obj s.rows[id]=row end
                end
            end
        end
    end
end
local function lockedOutline()
    local best,bestD
    for _,root in pairs({workspace:FindFirstChild("DebrisField"),workspace:FindFirstChild("DebrisFX")}) do
        local checked=0
        for _,obj in ipairs(root:GetDescendants()) do
            checked=checked+1 if checked>600 then break end
            if obj:IsA("SelectionBox") or obj:IsA("Highlight") or obj:IsA("BoxHandleAdornment") then
                local enabled,color,ad
                pcall(function()
                    if obj:IsA("Highlight") then enabled=obj.Enabled color=obj.OutlineColor else enabled=obj.Visible color=obj.Color3 end
                    ad=obj.Adornee or obj.Parent
                end)
                if enabled and color and color.B>color.R+.12 and inField(ad) then
                    local p=objectPosition(ad) local d=p and (p-BASE).Magnitude
                    if d and (not bestD or d<bestD) then best,bestD=ad,d end
                end
            end
        end
    end return best
end
local function mutationLabel(value)
    if type(value)~="string" then return nil end
    local normalized=value:lower():gsub("<[^>]*>","")
    for word in normalized:gmatch("[%a]+") do
        if word=="void" or word=="voided" or word=="vazio" then return "Vazio" end
    end
    for word in normalized:gmatch("[%a]+") do
        if word=="gold" or word=="golden" or word=="ouro" then return "Ouro" end
    end
end
local function textureKey(value)
    if type(value)~="string" or value=="" then return nil end
    return value:match("(%d+)%D*$") or value
end
local function mutationData(s,data)
    if type(data)~="table" then return nil end
    for _,key in ipairs({"Mutation","MutationName","Variant","VariantName","Quality","Finish","Trait"}) do
        local value=rawget(data,key) local label=mutationLabel(value)
        if not label and type(value)=="table" then
            for _,name in ipairs({"Name","Label","Title","Id"}) do label=label or mutationLabel(rawget(value,name)) end
        end
        if not label and type(value)=="number" then label=s.mutationCodes[value] end
        if label then return label,"metadata:"..key end
    end
    if rawget(data,"IsVoid")==true or rawget(data,"Vazio")==true then return "Vazio","metadata:flag" end
    if rawget(data,"IsGold")==true or rawget(data,"Gold")==true or rawget(data,"Ouro")==true then return "Ouro","metadata:flag" end
    local phase=rawget(data,"Phase")
    if phase~=nil and s.phaseCodes[phase] then return s.phaseCodes[phase],"metadata:configured_Phase" end
end
local function mutation(s,obj,id)
    local label,source=mutationData(s,s.rows[id])
    if not label then label,source=mutationData(s,s.spawn[id]) end
    local rootAttrs=obj:GetAttributes()
    if not label then label,source=mutationData(s,rootAttrs) end
    if label then return label,source end
    -- GoldTexture/VoidTexture existem em todos os itens: compara a textura ATIVA.
    local pieces={obj} local descendants=obj:GetDescendants()
    for i=1,math.min(#descendants,60) do pieces[#pieces+1]=descendants[i] end
    local baseMatched=false
    for _,piece in ipairs(pieces) do
        local attrs=piece:GetAttributes()
        label,source=mutationData(s,attrs) if label then return label,source end
        if piece:IsA("TextLabel") or piece:IsA("TextButton") then
            label=mutationLabel(piece.Text) if label then return label,"world_label" end
        end
        local current
        pcall(function()
            if piece:IsA("MeshPart") then current=piece.TextureID
            elseif piece:IsA("SurfaceAppearance") then current=piece.ColorMap
            elseif piece:IsA("Decal") or piece:IsA("Texture") then current=piece.Texture end
        end)
        current=textureKey(current)
        if current then
            local parents=piece.Parent and piece.Parent:GetAttributes() or {}
            for _,a in ipairs({attrs,parents,rootAttrs}) do
                if current==textureKey(a.VoidTexture) then return "Vazio","active_texture" end
                if current==textureKey(a.GoldTexture) then return "Ouro","active_texture" end
                if current==textureKey(a.BaseTexture) then baseMatched=true end
            end
        end
    end
    return mutationLabel(obj.Name) or (baseMatched and "Normal" or "Desconhecido"),baseMatched and "base_texture" or "name_or_unknown"
end
local function priority(label)
    if preferences.void and label=="Vazio" then return 2 end
    if preferences.gold and label=="Ouro" then return 1 end
    return 0
end
local function setTarget(s,obj,id,source,classification,evidence)
    if obj==s.target and id==s.targetId then return end
    local previous=s.target
    s.barPeak=nil s.pendingCatch=nil s.barTargetReady=os.clock()+.25 s.report.barMonitor=nil
    s.target=obj s.targetId=id s.targetAt=os.clock() s.lastProgress=os.clock() s.lastFraction=0
    s.targetMutation=classification or "Desconhecido" s.targetPriority=priority(s.targetMutation)
    if obj then
        local position=objectPosition(obj)
        local from=s.root and s.root.Position or BASE
        local flat=Vector3.new(position.X-from.X,0,position.Z-from.Z)
        s.approach=flat.Magnitude>.1 and flat.Unit or s.approach or Vector3.new(0,0,-1)
        s.report.targetSwitches=s.report.targetSwitches+1
    end
    s.report.target=obj and {path=path(obj),id=id,source=source,mutation=s.targetMutation,mutationEvidence=evidence,priority=s.targetPriority} or nil
    if obj then event(s,previous and "target_switch" or "target",s.report.target) end
end
local function chooseTarget(s,u)
    local now=os.clock()
    if s.target and (not objectPosition(s.target) or not inField(s.target) or s.completed[s.targetId] or s.doneObjects[s.target]) then setTarget(s,nil) end
    if now>=(s.nextTargets or 0) then
        s.nextTargets=now+.12 liveObjects(s)
        local candidates,seen={},{}
        local function candidate(obj,id)
            if not obj or seen[obj] or s.completed[id] or s.doneObjects[obj] or not inField(obj) then return end
            local p=objectPosition(obj) if not p then return end seen[obj]=true
            local label,evidence=mutation(s,obj,id)
            if s.classSeen[obj]~=label then
                s.classSeen[obj]=label
                local attrs=obj:GetAttributes() local spawn=s.spawn[id] or {} local row=s.rows[id] or {}
                local sample={id=id,name=obj.Name,classification=label,evidence=evidence}
                for _,name in ipairs({"Mutation","Variant","Phase","IsVoid","IsGold","BaseTexture","GoldTexture","VoidTexture"}) do
                    local v=attrs[name] if v==nil then v=spawn[name] end if v==nil then v=row[name] end
                    if type(v)=="string" or type(v)=="number" or type(v)=="boolean" then sample[name]=v end
                end
                pcall(function() if obj:IsA("MeshPart") then sample.activeTexture=obj.TextureID end end)
                add(s.report.mutationSamples,sample,12)
            end
            if s.target==obj and id and not s.targetId then s.targetId=id s.report.target.id=id end
            if s.cooldown[obj] and s.cooldown[obj]>now then return end
            candidates[#candidates+1]={obj=obj,id=id,label=label,evidence=evidence,rank=priority(label),distance=(p-(s.root and s.root.Position or BASE)).Magnitude}
        end
        for id,obj in pairs(s.objects) do candidate(obj,id) end
        local field=workspace:FindFirstChild("DebrisField")
        if field then for _,obj in ipairs(field:GetChildren()) do candidate(obj,nil) end end
        if s.target then
            s.targetMutation=mutation(s,s.target,s.targetId) s.targetPriority=priority(s.targetMutation)
            s.report.target.mutation=s.targetMutation s.report.target.priority=s.targetPriority
        end
        local best
        for _,c in ipairs(candidates) do
            if c.rank>0 and (not best or c.rank>best.rank or c.rank==best.rank and c.distance<best.distance) then best=c end
        end
        -- Mesma categoria nunca interrompe. Vazio interrompe Ouro/normal; Ouro interrompe normal.
        if best and (not s.target or best.rank>s.targetPriority) then
            if s.target then s.report.priorityPreemptions=s.report.priorityPreemptions+1 end
            setTarget(s,best.obj,best.id,"mutation_priority",best.label,best.evidence)
        elseif not s.target then
            -- Dos dois itens em puxada, permanece no primeiro ate Caught.
            local selected,first
            for _,c in ipairs(candidates) do
                local began=c.id and s.pulling[c.id]
                if began and (not first or began<first) then selected,first=c,began end
            end
            if not selected then
                local outline=lockedOutline()
                for _,c in ipairs(candidates) do if c.obj==outline or outline and outline:IsDescendantOf(c.obj) then selected=c break end end
            end
            if not selected then for _,c in ipairs(candidates) do
                if c.distance<200 and (not selected or c.distance<selected.distance) then selected=c end
            end end
            if selected then setTarget(s,selected.obj,selected.id,first and "first_game_Start" or "outline_or_nearest",selected.label,selected.evidence) end
        end
        local unknown=0 local gold,void=0,0
        for _,c in ipairs(candidates) do
            if c.label=="Desconhecido" then unknown=unknown+1 elseif c.label=="Ouro" then gold=gold+1 elseif c.label=="Vazio" then void=void+1 end
        end
        s.report.available={ouro=gold,vazio=void,unclassified=unknown}
    end
    if u.progress>s.lastFraction+.004 then s.lastProgress=now end s.lastFraction=u.progress
    -- Um alvo sem qualquer progresso pode ter requisito nao atendido; tenta o proximo.
    if s.target and now-(s.lastProgress or now)>8 and u.progress<.01 then
        s.cooldown[s.target]=now+5 event(s,"target_no_progress",s.report.target) setTarget(s,nil)
    end
    for obj,t in pairs(s.cooldown) do if t<now then s.cooldown[obj]=nil end end
    return s.target and objectPosition(s.target)
end
-- Apenas observa chamadas originais; nao envia Start, Catch ou Stop.
local probe=env.__NetoScrapPCProbe
if type(probe)~="table" then probe={enabled=false,queue={},installed=false} env.__NetoScrapPCProbe=probe end
local function installProbe(s)
    probe.remote=s.remote probe.queue={} probe.enabled=false
    if not probe.installed then
        local hook=hookmetamethod or env.hookmetamethod local method=getnamecallmethod or env.getnamecallmethod
        if type(hook)=="function" and type(method)=="function" then
            local old
            local wrapper=function(self,...)
                if probe.enabled and self==probe.remote and method()=="FireServer" then
                    local action,id=...
                    if #probe.queue<128 then probe.queue[#probe.queue+1]={action=action,id=id,at=os.clock()} end
                end
                return old(self,...)
            end
            local native=newcclosure or env.newcclosure if type(native)=="function" then wrapper=native(wrapper) end
            local ok,result=pcall(hook,game,"__namecall",wrapper) if ok then old=result probe.installed=true end
        end
    end
    probe.enabled=probe.installed s.report.outgoingCapture=probe.installed
end
local function drain(s)
    local queue=probe.queue probe.queue={}
    for _,e in ipairs(queue) do
        local a,id=e.action,e.id
        if s.report.gameSent[a] then s.report.gameSent[a]=s.report.gameSent[a]+1 end
        if a=="Start" then s.pulling[id]=e.at elseif a=="Stop" then s.pulling[id]=nil end
        if a=="Catch" and (id==s.targetId or s.objects[id]==s.target) and s.target then
            -- Em FPS baixo, o quadro da barra cheia pode nao aparecer no scanner.
            s.pendingCatch={obj=s.target,id=id,at=e.at,caught=s.report.caught,used=s.report.ui and s.report.ui.used}
        end
        if a=="Start" or a=="Stop" or a=="Catch" then event(s,"game_"..a,{id=id}) end
    end
end
setFrozen=function(s,value)
    if not s.root then return end
    if value then
        if not s.frozen then
            s.frozen=true s.savedCollisions={}
            for _,part in ipairs(s.char:GetDescendants()) do if part:IsA("BasePart") then s.savedCollisions[part]=part.CanCollide end end
            event(s,"freeze_above")
        end
        s.root.Anchored=true
        for part in pairs(s.savedCollisions) do if part.Parent then part.CanCollide=false end end
        s.root.AssemblyLinearVelocity=Vector3.new(0,0,0) s.root.AssemblyAngularVelocity=Vector3.new(0,0,0)
    elseif s.frozen then
        s.root.Anchored=s.originalAnchored
        for part,value in pairs(s.savedCollisions or {}) do if part.Parent then part.CanCollide=value end end
        s.savedCollisions={} s.frozen=false event(s,"unfreeze")
    end
    s.report.frozen=s.frozen==true
end
local function saveCharacter(s,char,root,hum)
    if s.char==char then return end
    if s.hum and s.hum.Parent then pcall(function() s.hum.AutoRotate=s.autoRotate end) end
    if s.char then setFrozen(s,false) release(s) event(s,"respawn") end
    if s.stage=="resetting" then s.stage="farming" s.resetJourney=nil end
    s.barPeak=nil
    s.char=char s.root=root s.hum=hum s.autoRotate=hum.AutoRotate s.report.recoveries=s.report.recoveries+(s.hadChar and 1 or 0) s.hadChar=true
    s.originalAnchored=root.Anchored
    hum.AutoRotate=false s.atBase=false s.pulling={} setTarget(s,nil)
end
local function teleport(s,position,label)
    s.root.CFrame=CFrame.new(position) s.root.AssemblyLinearVelocity=Vector3.new(0,0,0) s.root.AssemblyAngularVelocity=Vector3.new(0,0,0)
    event(s,label,{position=vec(position)}) s.report.teleports=s.report.teleports+1
end
local function saveCamera(s,camera)
    if s.camera==camera then return end
    if s.camera and s.cameraSaved then pcall(function() s.camera.CameraType=s.cameraSaved.type s.camera.CameraSubject=s.cameraSaved.subject s.camera.CFrame=s.cameraSaved.cf end) end
    s.camera=camera s.cameraSaved={type=camera.CameraType,subject=camera.CameraSubject,cf=camera.CFrame,focus=camera.Focus}
end
local function aboveAnchor(s,obj,point)
    local center=point local top=point.Y
    local ok,box,size=pcall(function()
        if obj:IsA("BasePart") then return obj.CFrame,obj.Size end
        if obj:IsA("Model") then return obj:GetBoundingBox() end
    end)
    if ok and size then
        box=box or CFrame.new(point) center=box.Position
        -- Extensao vertical real da caixa, incluindo objetos inclinados.
        top=center.Y+math.abs(box.RightVector.Y)*size.X*.5+math.abs(box.UpVector.Y)*size.Y*.5+math.abs(box.LookVector.Y)*size.Z*.5
    end
    return Vector3.new(center.X,top+1.5,center.Z)-(s.approach or Vector3.new(0,0,-1))*.25
end
local function aim(s,point,anchor,lookDown)
    local c=workspace.CurrentCamera if not c then return false end saveCamera(s,c)
    local p=pickPoint(s) if not p then return false end
    local flat=Vector3.new(point.X,anchor.Y,point.Z)-anchor
    if flat.Magnitude<.1 then flat=Vector3.new(0,0,-1) end
    local forward=flat.Unit local place=anchor+Vector3.new(0,3.5,0)-forward*8
    c.CameraType=Enum.CameraType.Scriptable
    local look=CFrame.lookAt(place,point) c.CFrame=look
    local ray=c:ScreenPointToRay(p.x,p.y)
    local localDirection=look:VectorToObjectSpace(ray.Direction)
    c.CFrame=look*CFrame.lookAt(Vector3.new(0,0,0),localDirection):Inverse()
    c.Focus=CFrame.new(point)
    if lookDown then
        local direction=point-anchor
        local up=Vector3.new(0,1,0)
        if direction.Magnitude>.01 and math.abs(direction.Unit.Y)>.98 then up=s.approach or Vector3.new(0,0,-1) end
        s.root.CFrame=CFrame.lookAt(anchor,point,up)
    else s.root.CFrame=CFrame.lookAt(anchor,anchor+forward) end
    return true
end
local function barFailed(s,u,now)
    if not s.held or not s.target or not u.visible or now<(s.nextBarReset or 0) or now<(s.barTargetReady or 0) or now-(s.lastCaughtAt or -100) < .3 then
        s.barPeak=nil s.report.barMonitor=nil return false
    end
    local p=s.barPeak local fraction=u.progress
    if p and (p.obj~=s.target or s.report.caught>p.caught or u.used and p.used and u.used>p.used) then
        s.barPeak=nil s.report.barMonitor=nil return false
    end
    local request=s.pendingCatch
    if not p and request and request.obj==s.target and now-request.at<.25 then
        p={obj=s.target,id=s.targetId,peak=1,caught=request.caught,used=request.used,at=now,evidence="game_Catch"} s.barPeak=p s.pendingCatch=nil
    elseif not p and fraction>=.97 then
        p={obj=s.target,id=s.targetId,peak=fraction,caught=s.report.caught,used=u.used,at=now,evidence="bar"} s.barPeak=p
    end
    if not p then return false end
    p.peak=math.max(p.peak,fraction)
    if not p.dropAt and fraction<=p.peak-.25 then
        p.dropAt=now s.report.barFalls=s.report.barFalls+1
        event(s,"bar_fell_without_Caught",{id=p.id,peak=p.peak,progress=fraction})
    end
    s.report.barMonitor={peak=p.peak,progress=fraction,pending=p.dropAt~=nil}
    -- Caught pode chegar depois da animacao. Aguarda antes de considerar falha.
    if not p.dropAt or now-p.dropAt<.55 then return false end
    s.resetJourney={obj=s.target,id=s.targetId,at=now,returnAt=now+1}
    s.stage="resetting" s.barPeak=nil s.report.barMonitor=nil
    s.report.barResets=s.report.barResets+1 s.nextBarReset=now+3
    setFrozen(s,false) teleport(s,RESET,"TP_reset_bar")
    s.report.phase="Recuperando barra • esperando 1 segundo"
    return true
end
local function resetTick(s,now)
    local journey=s.resetJourney
    if not journey then s.stage="farming" return false end
    if now<journey.returnAt then
        -- Estado por frame, sem tarefa atrasada que possa teleportar apos OFF.
        aim(s,RESET+Vector3.new(0,2,-15),RESET) pointer(s)
        s.report.phase="Recuperando barra • esperando 1 segundo" return true
    end
    s.resetJourney=nil s.stage="farming" s.barPeak=nil s.report.barMonitor=nil
    s.report.barResetReturns=s.report.barResetReturns+1 s.nextTargets=0
    local obj=journey.obj local point=objectPosition(obj)
    if point and inField(obj) and not s.completed[journey.id] and not s.doneObjects[obj] then
        local label,evidence=mutation(s,obj,journey.id)
        setTarget(s,obj,journey.id,"bar_reset_return",label,evidence)
        teleport(s,aboveAnchor(s,obj,point),"TP_reset_return") setFrozen(s,true)
    else
        setTarget(s,nil) teleport(s,BASE,"TP_reset_return_base")
    end
    event(s,"bar_reset_done",{id=journey.id,waited=now-journey.at})
    return false
end
local function tick(s)
    if not valid(s) then return end drain(s)
    if os.clock()<s.activateAt then s.report.phase="Inicia em "..math.ceil(s.activateAt-os.clock()).."s • feche a interface" return end
    local char=player.Character local root=char and char:FindFirstChild("HumanoidRootPart") local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health<=0 then release(s) s.report.phase="Aguardando personagem" return end
    saveCharacter(s,char,root,hum)
    if not s.atBase and s.stage~="selling" then teleport(s,BASE,"TP_base") s.atBase=true end
    if GS.MenuIsOpen then release(s) s.report.phase="Menu aberto • pausado" return end
    local u=hud(s) local now=os.clock()
    local full=(u.used and u.capacity and u.capacity>0 and u.used>=u.capacity) or (u.visible and u.note:lower():find("backpack full",1,true)~=nil)
    if full and s.stage~="selling" then
        setFrozen(s,false)
        s.barPeak=nil s.resetJourney=nil s.report.barMonitor=nil
        s.stage="selling" s.sellAt=now s.sellStart=u.used s.saleCheck=now+.4 s.saleRetry=now+5
        s.report.trips=s.report.trips+1 setTarget(s,nil) s.pulling={} teleport(s,SELL,"TP_entrega")
    end
    if s.stage=="resetting" and resetTick(s,now) then return end
    if s.stage=="selling" then
        s.report.phase="Entregando • aguardando mochila zerar"
        if now>=s.saleCheck and u.used==0 then
            s.report.deposits=s.report.deposits+1 event(s,"deposit_confirmed",{before=s.sellStart,after=u.used,seconds=now-s.sellAt})
            s.stage="farming" teleport(s,BASE,"TP_retorno") s.nextTargets=0 s.cooldown={}
        else
            if now>=s.saleRetry then
                s.report.saleTimeouts=s.report.saleTimeouts+1 s.saleRetry=now+5 teleport(s,SELL,"retry_entrega") s.report.phase="Entrega pendente • continuo no ponto"
            elseif (root.Position-SELL).Magnitude>.8 then teleport(s,SELL,"corrigir_entrega") end
            aim(s,SELL+Vector3.new(0,2,-15),SELL) pointer(s) return
        end
    end
    local tool=char:FindFirstChild("DebrisMagnet")
    if not tool then
        local bag=player:FindFirstChild("Backpack") tool=bag and bag:FindFirstChild("DebrisMagnet") if tool then hum:EquipTool(tool) end
        if not char:FindFirstChild("DebrisMagnet") then release(s) s.report.phase="Equipe o imã" return end
    end
    if not tool.Enabled then release(s) s.report.phase="Imã indisponível" return end
    if not u.visible then release(s) s.report.phase="Aguardando área do imã" return end
    local target=chooseTarget(s,u)
    if barFailed(s,u,now) then return end
    local anchor=BASE
    if target then
        anchor=aboveAnchor(s,s.target,target)
        setFrozen(s,true) s.report.followFrames=s.report.followFrames+1
        s.report.followPosition=vec(anchor)
    else setFrozen(s,false) target=BASE+Vector3.new(0,3,-30) end
    if (root.Position-anchor).Magnitude>.6 then root.AssemblyLinearVelocity=Vector3.new(0,0,0) end
    if aim(s,target,anchor,s.target~=nil) then
        if pointer(s) then s.report.phase=s.target and "Acima do alvo • segurando • "..s.targetMutation or "Procurando alvo • mouse segurado" end
    else release(s) s.report.phase="Aguardando ponto livre" end
end
local function cleanup(s)
    s.resetJourney=nil s.barPeak=nil s.report.barMonitor=nil
    probe.enabled=false probe.queue={} disconnect(s.listeners) release(s)
    if s.root and s.root.Parent then
        pcall(function() teleport(s,BASE,"TP_base_OFF") s.report.returnedToBase=true end)
    end
    pcall(setFrozen,s,false)
    if s.hum and s.hum.Parent then pcall(function() s.hum.AutoRotate=s.autoRotate end) end
    if s.root and s.root.Parent then pcall(function() s.root.AssemblyAngularVelocity=Vector3.new(0,0,0) end) end
    if s.camera and s.cameraSaved then pcall(function()
        s.camera.CameraType=s.cameraSaved.type s.camera.CameraSubject=s.cameraSaved.subject s.camera.CFrame=s.cameraSaved.cf s.camera.Focus=s.cameraSaved.focus
    end) end
    pcall(function() UIS.MouseBehavior=s.mouseBehavior UIS.MouseIconEnabled=s.mouseIcon end) restoreMobile(s)
end
stop=function(doCopy,reason)
    local s=active if not s then if doCopy and copy then return copy() end return end
    s.running=false active=nil s.report.running=false s.report.seconds=os.clock()-s.started s.report.phase=reason or "OFF"
    event(s,"stop",{reason=reason or "OFF"}) cleanup(s) lastReport=s.report toggleButton.Text="Auto Scrap: OFF" if paint then paint() end
    if doCopy and copy then return copy() end
end
copy=function()
    local r=active and active.report or lastReport if not r then status.Text="Ative primeiro para registrar o teste." return end
    if active then r.seconds=os.clock()-active.started end
    local ok,payload=pcall(function() return Http:JSONEncode(r) end) if not ok then status.Text="Erro ao gerar debug: "..tostring(payload):sub(1,80) return end
    env.ScrapPCDebugReport=payload local clipboard=setclipboard or toclipboard or env.setclipboard or env.toclipboard
    if type(clipboard)=="function" then local copied=pcall(clipboard,payload) if copied then status.Text="Debug copiado. Cole aqui o resultado." return payload end end
    status.Text="Clipboard indisponível. Resultado em getgenv().ScrapPCDebugReport" return payload
end
paint=function()
    local s=active local r=s and s.report or lastReport if not r then return end local u=r.ui or {}
    status.Text=string.format("%s\nMochila: %s / %s • Caught: %d\nEntregas: %d • Vazio > Ouro > normal",r.phase,tostring(u.used or "?"),tostring(u.capacity or "?"),r.caught,r.deposits)
    mini.Text=s and ("SCRAP "..tostring(u.used or "?")) or "SCRAP OFF"
end
start=function(delay)
    if not alive or active then return end restoreGeneration=restoreGeneration+1
    local remotes=RS:FindFirstChild("Remotes") local remote=remotes and remotes:FindFirstChild("DebrisMagnet")
    if not remote or not remote:IsA("RemoteEvent") then status.Text="Remote DebrisMagnet indisponível." return end
    local s={running=true,started=os.clock(),activateAt=os.clock()+math.max(0,tonumber(delay) or 3),listeners={},remote=remote,stage="farming",objects={},rows={},spawn={},spawnOrder={},mutationCodes={},phaseCodes={},completed={},doneObjects=setmetatable({},{__mode="k"}),classSeen=setmetatable({},{__mode="k"}),pulling={},cooldown={},held=false,lastFraction=0,mouseBehavior=UIS.MouseBehavior,mouseIcon=UIS.MouseIconEnabled}
    s.report={format="scrap-pc-hold-v3-above-recovery",note="Segue 1.5 studs acima do topo, olhando para baixo, com mouse mantido. Barra >=97% que cai sem Caught: espera confirmacao, vai ao reset por 1s e volta ao alvo. Vazio > Ouro > normal. Entrega espera mochila zerar; OFF restaura mobile e volta a base.",placeId=game.PlaceId,running=true,phase="Iniciando em 3s",base=vec(BASE),sale=vec(SELL),reset=vec(RESET),caught=0,trips=0,deposits=0,saleTimeouts=0,teleports=0,recoveries=0,barFalls=0,barResets=0,barResetReturns=0,presses=0,releases=0,resyncs=0,held=false,events={},inputErrors={},mutationSamples={},gameSent={Start=0,Catch=0,Stop=0},directSent={Start=0,Catch=0,Stop=0},manualTouches=0,targetSwitches=0,priorityPreemptions=0,followFrames=0,preferences={ouro=preferences.gold,vazio=preferences.void}}
    active=s lastReport=s.report
    local ok,err=pcall(function()
        installProbe(s)
        connect(remote.OnClientEvent,function(action,id,used,cap)
            if not valid(s) then return end
            if action=="Spawn" and type(id)=="table" then
                local data=id if data.Id~=nil then
                    if not s.spawn[data.Id] then
                        s.spawnOrder[#s.spawnOrder+1]=data.Id
                        if #s.spawnOrder>256 then s.spawn[table.remove(s.spawnOrder,1)]=nil end
                    end
                    s.spawn[data.Id]=data s.nextTargets=0
                end
            elseif action=="Caught" then
                s.lastCaughtAt=os.clock() s.barPeak=nil s.report.barMonitor=nil
                s.report.caught=s.report.caught+1 s.pulling[id]=nil event(s,"server_Caught",{id=id,used=used,capacity=cap})
                s.completed[id]=true local obj=s.objects[id] if obj then s.doneObjects[obj]=true end
                if s.targetId==id or obj and s.target==obj then setTarget(s,nil) end
                s.nextTargets=0
            elseif action=="Released" or action=="Refused" then s.pulling[id]=nil event(s,"server_"..action,{id=id}) end
        end,s.listeners)
        connect(UIS.InputBegan,function(input)
            if valid(s) and input.UserInputType==Enum.UserInputType.Touch then s.report.manualTouches=s.report.manualTouches+1 s.inputLost=true end
        end,s.listeners)
        connect(UIS.InputEnded,function(input)
            if valid(s) and input.UserInputType==Enum.UserInputType.MouseButton1 then s.inputLost=true end
        end,s.listeners)
        connect(Run.RenderStepped,function()
            if not valid(s) then return end local success,message=pcall(tick,s)
            if not success then event(s,"error",tostring(message):sub(1,220)) stop(false,"Erro • entrada liberada") return end
            if os.clock()>=(s.nextPaint or 0) then s.nextPaint=os.clock()+.25 paint() end
        end,s.listeners)
        toggleButton.Text="Auto Scrap: ON" panel.Visible=false mini.Visible=true
    end)
    if not ok then event(s,"error",tostring(err)) stop(false,"Erro ao iniciar") end
end
close=function()
    if not alive then return end stop(false,"Fechado") alive=false probe.enabled=false disconnect(lifetime) gui:Destroy()
end
local function setPriority(kind,value)
    if kind=="ouro" then kind="gold" elseif kind=="vazio" then kind="void" end
    if kind~="gold" and kind~="void" then return end
    preferences[kind]=value==nil and not preferences[kind] or value==true
    goldButton.Text="Ouro: "..(preferences.gold and "ON" or "OFF") voidButton.Text="Vazio: "..(preferences.void and "ON" or "OFF")
    if active then active.report.preferences={ouro=preferences.gold,vazio=preferences.void} active.nextTargets=0 end
end
local function openPanel()
    -- Libera o ponteiro ANTES de tornar a interface clicavel.
    if active then stop(false,"Interface aberta • OFF") end
    panel.Position=mini.Position panel.Visible=true mini.Visible=false
end
env.ScrapPCDebug={Start=start,Stop=stop,Copy=copy,Close=close,SetPriority=setPriority,OpenPanel=openPanel,GetReport=function() return active and active.report or lastReport end}
connect(toggleButton.Activated,function() if active then stop(true) else start() end end,lifetime)
connect(copyButton.Activated,function() if active then stop(true) else copy() end end,lifetime)
connect(miniButton.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end,lifetime)
connect(mini.Activated,openPanel,lifetime)
connect(goldButton.Activated,function() setPriority("gold") end,lifetime)
connect(voidButton.Activated,function() setPriority("void") end,lifetime)
connect(exitButton.Activated,close,lifetime)
local dragging,dragInput,dragStart,dragPosition
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true dragInput=input.UserInputType==Enum.UserInputType.Touch and input or nil dragStart=input.Position dragPosition=panel.Position
    end
end,lifetime)
connect(UIS.InputChanged,function(input)
    if dragging and ((dragInput and input==dragInput) or (not dragInput and input.UserInputType==Enum.UserInputType.MouseMovement)) then
        local delta=input.Position-dragStart local v=workspace.CurrentCamera.ViewportSize
        panel.Position=UDim2.fromOffset(math.clamp(dragPosition.X.Offset+delta.X,0,math.max(0,v.X-302)),math.clamp(dragPosition.Y.Offset+delta.Y,0,math.max(0,v.Y-250)))
    end
end,lifetime)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end,lifetime)
