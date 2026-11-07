-- Auto Scrap PC / debug. Mouse segurado; a rotina original puxa e coleta.
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
local pg=player:WaitForChild("PlayerGui")
local alive,active,lastReport=true,nil,nil
local start,stop,copy,close,paint
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
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(302,206) panel.Position=UDim2.fromOffset(12,62)
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
local status=Instance.new("TextLabel") status.BackgroundTransparency=1 status.TextColor3=Color3.new(1,1,1)
status.TextSize=12 status.Font=Enum.Font.Gotham status.TextWrapped=true status.TextXAlignment=Enum.TextXAlignment.Left status.TextYAlignment=Enum.TextYAlignment.Top
status.Position=UDim2.fromOffset(10,121) status.Size=UDim2.fromOffset(282,77) status.Text="Equipe o imã e ative.\nEntrega e retorno automáticos." status.Parent=panel
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
    s.objects={} if not s.step and os.clock()>=(s.nextStep or 0) then s.nextStep=os.clock()+2 scanStep(s) end
    if not s.step then return end
    local ok,up=pcall(getup,s.step) if not ok or type(up)~="table" then return end
    for _,map in pairs(up) do
        if type(map)=="table" then
            local inspected=0
            for key,row in pairs(map) do
                inspected=inspected+1 if inspected>160 then break end
                if type(row)=="table" then
                    local id=rawget(row,"Id") or (type(key)=="number" and key)
                    local obj=id and chunkObject(row) if obj then s.objects[id]=obj end
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
local function setTarget(s,obj,id,source)
    if obj==s.target and id==s.targetId then return end
    s.target=obj s.targetId=id s.targetAt=os.clock() s.lastProgress=os.clock() s.lastFraction=0
    s.report.target=obj and {path=path(obj),id=id,source=source} or nil
    if obj then event(s,"target",s.report.target) end
end
local function chooseTarget(s,u)
    local now=os.clock()
    if s.target and (not objectPosition(s.target) or not inField(s.target)) then setTarget(s,nil) end
    if now>=(s.nextTargets or 0) then
        s.nextTargets=now+.16 liveObjects(s)
        local outline=lockedOutline()
        local lockedId if outline then for id,obj in pairs(s.objects) do if obj==outline or outline:IsDescendantOf(obj) then lockedId=id break end end end
        if outline and not s.cooldown[outline] then setTarget(s,outline,lockedId,"blue_outline") end
        if not outline then
            local latest,at
            for id,t in pairs(s.pulling) do if s.objects[id] and (not at or t>at) then latest,at=id,t end end
            if latest and (not s.targetId or not s.pulling[s.targetId]) then setTarget(s,s.objects[latest],latest,"game_Start") end
        end
        if not s.target then
            local field=workspace:FindFirstChild("DebrisField") local best,bestD
            if field then for _,obj in ipairs(field:GetChildren()) do
                local p=objectPosition(obj) local d=p and (p-BASE).Magnitude
                if d and d<180 and (not s.cooldown[obj] or s.cooldown[obj]<now) and (not bestD or d<bestD) then best,bestD=obj,d end
            end end
            if best then setTarget(s,best,nil,"nearest_fallback") end
        end
    end
    if u.progress>s.lastFraction+.004 then s.lastProgress=now end s.lastFraction=u.progress
    if s.target and now-(s.lastProgress or now)>3 and u.progress<.01 then
        s.cooldown[s.target]=now+4 event(s,"target_no_progress",s.report.target) setTarget(s,nil)
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
        if a=="Start" or a=="Stop" or a=="Catch" then event(s,"game_"..a,{id=id}) end
    end
end
local function saveCharacter(s,char,root,hum)
    if s.char==char then return end
    if s.hum and s.hum.Parent then pcall(function() s.hum.AutoRotate=s.autoRotate end) end
    if s.char then release(s) event(s,"respawn") end
    s.char=char s.root=root s.hum=hum s.autoRotate=hum.AutoRotate s.report.recoveries=s.report.recoveries+(s.hadChar and 1 or 0) s.hadChar=true
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
local function aim(s,point,anchor)
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
    c.Focus=CFrame.new(point) s.root.CFrame=CFrame.lookAt(anchor,anchor+forward)
    return true
end
local function tick(s)
    if not valid(s) then return end drain(s)
    local char=player.Character local root=char and char:FindFirstChild("HumanoidRootPart") local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health<=0 then release(s) s.report.phase="Aguardando personagem" return end
    saveCharacter(s,char,root,hum)
    if not s.atBase and s.stage~="selling" then teleport(s,BASE,"TP_base") s.atBase=true end
    if GS.MenuIsOpen then release(s) s.report.phase="Menu aberto • pausado" return end
    local u=hud(s) local now=os.clock()
    local full=(u.used and u.capacity and u.capacity>0 and u.used>=u.capacity) or (u.visible and u.note:lower():find("backpack full",1,true)~=nil)
    if full and s.stage~="selling" then
        s.stage="selling" s.sellAt=now s.sellStart=u.used s.saleCheck=now+.4 s.saleRetry=now+5
        s.report.trips=s.report.trips+1 setTarget(s,nil) s.pulling={} teleport(s,SELL,"TP_entrega")
    end
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
    local target=chooseTarget(s,u) or (BASE+Vector3.new(0,3,-30))
    if (root.Position-BASE).Magnitude>.6 then root.AssemblyLinearVelocity=Vector3.new(0,0,0) end
    if aim(s,target,BASE) then
        if pointer(s) then s.report.phase=s.target and "Puxando • mouse segurado" or "Procurando alvo • mouse segurado" end
    else release(s) s.report.phase="Aguardando ponto livre" end
end
local function cleanup(s)
    probe.enabled=false probe.queue={} disconnect(s.listeners) release(s)
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
    status.Text=string.format("%s\nMochila: %s / %s • Caught: %d\nEntregas confirmadas: %d • %s",r.phase,tostring(u.used or "?"),tostring(u.capacity or "?"),r.caught,r.deposits,r.backend or "sem entrada")
    mini.Text=s and ("SCRAP "..tostring(u.used or "?")) or "SCRAP OFF"
end
start=function()
    if not alive or active then return end restoreGeneration=restoreGeneration+1
    local remotes=RS:FindFirstChild("Remotes") local remote=remotes and remotes:FindFirstChild("DebrisMagnet")
    if not remote or not remote:IsA("RemoteEvent") then status.Text="Remote DebrisMagnet indisponível." return end
    local s={running=true,started=os.clock(),listeners={},remote=remote,stage="farming",objects={},pulling={},cooldown={},held=false,lastFraction=0,mouseBehavior=UIS.MouseBehavior,mouseIcon=UIS.MouseIconEnabled}
    s.report={format="scrap-pc-hold-v1",note="Mouse PC segurado. Mira segue o alvo; rotina original puxa/coleta. Entrega exige mochila zerada. Caught nao distingue ajuda de outros scripts.",placeId=game.PlaceId,running=true,phase="Iniciando",base=vec(BASE),sale=vec(SELL),caught=0,trips=0,deposits=0,saleTimeouts=0,teleports=0,recoveries=0,presses=0,releases=0,resyncs=0,held=false,events={},inputErrors={},gameSent={Start=0,Catch=0,Stop=0},directSent={Start=0,Catch=0,Stop=0},manualTouches=0}
    active=s lastReport=s.report
    local ok,err=pcall(function()
        installProbe(s)
        connect(remote.OnClientEvent,function(action,id,used,cap)
            if not valid(s) then return end
            if action=="Caught" then
                s.report.caught=s.report.caught+1 s.pulling[id]=nil event(s,"server_Caught",{id=id,used=used,capacity=cap})
                if s.targetId==id then setTarget(s,nil) end
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
env.ScrapPCDebug={Start=start,Stop=stop,Copy=copy,Close=close,GetReport=function() return active and active.report or lastReport end}
connect(toggleButton.Activated,function() if active then stop(true) else start() end end,lifetime)
connect(copyButton.Activated,function() if active then stop(true) else copy() end end,lifetime)
connect(miniButton.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end,lifetime)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false end,lifetime)
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
        panel.Position=UDim2.fromOffset(math.clamp(dragPosition.X.Offset+delta.X,0,math.max(0,v.X-302)),math.clamp(dragPosition.Y.Offset+delta.Y,0,math.max(0,v.Y-206)))
    end
end,lifetime)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end,lifetime)
