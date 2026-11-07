-- DebrisMagnet / Auto Pull v3. Apenas segurar; a rotina original escolhe e coleta.
-- Sem ponteiro virtual, TP, alteracao da barra, forca ou quantidade de alvos.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
if env.MagnetDebug and type(env.MagnetDebug.Close)=="function" then pcall(env.MagnetDebug.Close) end
if type(env.__NetoMagnetProbe)=="table" then env.__NetoMagnetProbe.enabled=false end
local pg=player:WaitForChild("PlayerGui")
local alive,active=true,nil
local lastReport,learned=nil,nil
local start,stop,copy,close
local own=setmetatable({},{__mode="k"})
local lifetime={}
local getup=(debug and debug.getupvalues) or env.getupvalues
local setUp=(debug and debug.setupvalue) or env.setupvalue
local getConstants=(debug and debug.getconstants) or env.getconstants
local getConnections=getconnections or env.getconnections
local function path(x)
    local ok,name=pcall(function() return x:GetFullName() end)
    return ok and name or "[removed]"
end
local function append(list,value,limit)
    list[#list+1]=value if #list>limit then table.remove(list,1) end
end
local function valid(s) return alive and active==s and s.running end
local function elapsed(s) return math.floor((os.clock()-s.started)*1000+.5)/1000 end
local function connect(signal,fn,list)
    own[fn]=true local c=signal:Connect(fn) list[#list+1]=c return c
end
local function disconnect(list) for _,c in ipairs(list) do c:Disconnect() end table.clear(list) end
local function values(fn)
    if type(getup)~="function" then return nil end
    local ok,result=pcall(getup,fn)
    return ok and type(result)=="table" and result or nil
end
local function booleans(v)
    local out={} if not v then return out end
    for k,x in pairs(v) do if type(k)=="number" and type(x)=="boolean" then out[k]=x end end
    return out
end
local function shown(x)
    for _=1,18 do
        if not x then return false end
        if x:IsA("GuiObject") and not x.Visible then return false end
        if x:IsA("ScreenGui") then return x.Enabled end
        x=x.Parent
    end
    return false
end
local function hudState(s)
    local front=pg:FindFirstChild("Front") local main=front and front:FindFirstChild("MainFrame")
    local hud=main and main:FindFirstChild("DebrisHUD")
    local track=hud and hud:FindFirstChild("Track")
    local fill=track and track:FindFirstChild("Fill") local note=track and track:FindFirstChild("Note")
    local bag=hud and hud:FindFirstChild("Backpack") local count=bag and bag:FindFirstChild("Count")
    local used,capacity
    if count and count:IsA("TextLabel") then used,capacity=tostring(count.Text):match("(%d+)%s*/%s*(%d+)") end
    local text=note and tostring(note.Text):gsub("<[^>]+>","") or ""
    local percent=fill and fill.Size.X.Scale or 0
    local full=used and tonumber(used)>=tonumber(capacity) or false
    local ready=hud and shown(hud) or false
    local tool=player.Character and player.Character:FindFirstChild("DebrisMagnet")
    if not tool or not tool:IsA("Tool") or not tool.Enabled then ready=false end
    s.report.ui={note=text,progress=percent,visible=ready,used=tonumber(used),capacity=tonumber(capacity)}
    return ready,full,text,percent
end
local function event(s,kind,action,data)
    append(s.report.events,{t=elapsed(s),kind=kind,action=action,data=data},32)
end

local gui=Instance.new("ScreenGui") gui.Name="NetoMagnetDebug" gui.ResetOnSpawn=false gui.DisplayOrder=10034 gui.Parent=pg
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(325,216) panel.Position=UDim2.new(0,12,.06,0)
panel.BackgroundColor3=Color3.fromRGB(21,23,30) panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,8)
local function button(text,x,y,width)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.Gotham b.TextSize=13 b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(66,49,110) b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(width,35) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="AUTO PULL / V3" title.Font=Enum.Font.GothamBold title.TextSize=14
title.BackgroundTransparency=1 title.TextColor3=Color3.new(1,1,1) title.Position=UDim2.fromOffset(10,0) title.Size=UDim2.fromOffset(220,36) title.Active=true title.Parent=panel
local minimize=button("-",244,1,32) local exit=button("X",282,1,33)
local toggle=button("Auto Pull: OFF",10,43,305) local copyButton=button("Copiar debug",10,85,305)
local label=Instance.new("TextLabel") label.Text="Equipe o ima, aponte para um item e ative.\nSomente Auto Pull nesta versao."
label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top
label.Font=Enum.Font.Gotham label.TextSize=12 label.TextColor3=Color3.new(1,1,1) label.BackgroundTransparency=1
label.Position=UDim2.fromOffset(10,130) label.Size=UDim2.fromOffset(305,76) label.Parent=panel
local output=Instance.new("TextBox") output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false output.Text=""
output.Font=Enum.Font.Code output.TextSize=10 output.BackgroundColor3=Color3.fromRGB(28,30,39) output.TextColor3=Color3.new(1,1,1)
output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top
output.Position=label.Position output.Size=label.Size output.Visible=false output.Parent=panel
local mini=Instance.new("TextButton") mini.Text="PULL" mini.Font=Enum.Font.GothamBold mini.TextSize=12 mini.TextColor3=Color3.new(1,1,1)
mini.BackgroundColor3=Color3.fromRGB(66,49,110) mini.Size=UDim2.fromOffset(64,35) mini.Position=panel.Position mini.Visible=false mini.Parent=gui

-- O hook observa apenas DebrisMagnet e preserva os argumentos e retornos.
-- Nenhuma API de Instance/JSON e nenhuma funcao do jogo e chamada dentro dele.
local probe=env.__NetoMagnetHoldProbe
if type(probe)~="table" or probe.version~=1 then
    if type(probe)=="table" then probe.enabled=false end
    probe={version=1,installed=false,enabled=false} env.__NetoMagnetHoldProbe=probe
end
local function install()
    if probe.installed then return true end
    local hook=hookmetamethod or env.hookmetamethod local method=getnamecallmethod or env.getnamecallmethod
    if type(hook)~="function" or type(method)~="function" then return false end
    local original
    local wrapper=function(self,...)
        if probe.enabled and self==probe.remote and method()=="FireServer" then
            if probe.tail-probe.head<128 then
                local action,id=...
                probe.tail=probe.tail+1
                probe.queue[probe.tail]={action=action,id=id,at=os.clock(),own=probe.ownStop==true}
            else probe.dropped=probe.dropped+1 end
        end
        return original(self,...)
    end
    local native=newcclosure or env.newcclosure if type(native)=="function" then wrapper=native(wrapper) end
    local ok,result=pcall(hook,game,"__namecall",wrapper)
    if ok then original=result probe.installed=true end
    return ok
end
local function drain(s)
    while probe.head<=probe.tail do
        local row=probe.queue[probe.head] probe.queue[probe.head]=nil probe.head=probe.head+1
        if type(row.action)=="string" and (row.action=="Start" or row.action=="Catch" or row.action=="Stop") then
            local r=s.report
            r.gameSent[row.action]=(r.gameSent[row.action] or 0)+(row.own and 0 or 1)
            if row.action=="Start" and type(row.id)=="number" then s.pending[row.id]=row.at s.lastStart=row.at
            elseif row.action=="Stop" and type(row.id)=="number" then s.pending[row.id]=nil end
            event(s,row.own and "cleanup" or "game_send",row.action,{id=row.id})
        end
    end
    probe.queue={} probe.head=1 probe.tail=0
end
local function release(s,reason)
    if s.binding and s.binding.wrote then
        local ok,err=pcall(setUp,s.binding.fn,s.binding.index,s.binding.original)
        s.report.inputRestored=ok
        if not ok then s.report.restoreError=tostring(err):sub(1,160) end
        s.binding.wrote=false
        event(s,"input","released",{reason=reason,index=s.binding.index})
    end
end
local function stopPending(s)
    if not s.remote then return end
    for id in pairs(s.pending) do
        probe.ownStop=true
        local ok=pcall(function() s.remote:FireServer("Stop",id) end)
        probe.ownStop=false
        if ok then s.report.cleanupStops=s.report.cleanupStops+1 end
    end
    s.pending={}
end
local function findStep(s)
    if type(getConnections)~="function" or type(getConstants)~="function" or type(getup)~="function" then return end
    local ok,list=pcall(getConnections,Run.RenderStepped)
    if not ok or type(list)~="table" then return end
    for i,c in ipairs(list) do
        if i>160 then break end
        local good,fn,foreign=pcall(function() return c.Function,c.ForeignState end)
        if good and not foreign and type(fn)=="function" and not own[fn] then
            local source=""
            if type(getfenv)=="function" then pcall(function() local e=getfenv(fn) local script=rawget(e,"script") if typeof(script)=="Instance" then source=path(script) end end) end
            if source:match("PlayerScripts%..*%.DebrisMagnet$") then
                local read,constants=pcall(getConstants,fn)
                local marks={}
                if read and type(constants)=="table" then for _,x in pairs(constants) do if type(x)=="string" then marks[x]=true end end end
                local v=values(fn) local hasPlayer,hasHud=false,false
                if v then for _,x in pairs(v) do
                    if x==player then hasPlayer=true end
                    if typeof(x)=="Instance" and x.Name=="DebrisHUD" then hasHud=true end
                end end
                if v and hasPlayer and hasHud and marks.DebrisMagnet and marks.GetMagnetStrength and marks.GetPullCount and marks.Progress then
                    s.step={fn=fn,source=source} s.report.liveStep={source=source,actualConnection=true}
                    s.boolFrame=booleans(v) return
                end
            end
        end
    end
end
local function chooseCandidate(s,v)
    -- Indice dinamico: booleano vizinho de UIS/GuiService na funcao viva.
    local found={}
    for index,value in pairs(v) do
        if type(index)=="number" and type(value)=="boolean" and v[index+1]==UIS then
            local neighbor=v[index+2]
            if typeof(neighbor)=="Instance" and neighbor.ClassName=="GuiService" then found[#found+1]=index end
        end
    end
    s.report.inputCandidates=found
    return #found==1 and found[1] or nil
end
local function bind(s,index,kind)
    if not s.step or type(setUp)~="function" then return false end
    local v=values(s.step.fn) if not v or type(v[index])~="boolean" then return false end
    s.binding={fn=s.step.fn,index=index,original=v[index],kind=kind,started=os.clock(),baselineProgress=s.report.ui.progress or 0,
        starts=s.report.gameSent.Start or 0,catchesAtBind=s.report.caughtWhileEnabled,peak=0,wrote=false}
    s.report.binding={index=index,source=s.step.source,method=kind,confirmed=false}
    event(s,"input","binding_test",{index=index,method=kind}) return true
end
local function keepHeld(s)
    local b=s.binding local v=values(b.fn)
    if not v or type(v[b.index])~="boolean" then error("Estado de entrada nao esta mais disponivel") end
    if v[b.index]~=true then
        local ok,err=pcall(setUp,b.fn,b.index,true) if not ok then error(tostring(err)) end
        b.wrote=true s.report.holdWrites=s.report.holdWrites+1
    end
end
local function overDebug(input)
    local p=input.Position if not p then return false end
    local ok,list=pcall(function() return pg:GetGuiObjectsAtPosition(p.X,p.Y) end)
    if ok then for _,obj in ipairs(list) do if obj==gui or obj:IsDescendantOf(gui) then return true end end end
    return false
end
local function onBegin(s,input,processed)
    local kind=input.UserInputType
    if not valid(s) or processed or overDebug(input) or (kind~=Enum.UserInputType.Touch and kind~=Enum.UserInputType.MouseButton1) then return end
    s.report.manualTouches=s.report.manualTouches+1
    if s.binding or not s.step or s.manual then return end
    s.manual={input=input,before=s.boolFrame or {},fn=s.step.fn,at=os.clock(),starts=s.report.gameSent.Start or 0,peak=s.report.ui.progress or 0,duringCount={}}
    event(s,"manual","begin",{booleans=s.manual.before})
end
local function onEnd(s,input)
    local attempt=s.manual if not valid(s) or not attempt or attempt.input~=input then return end
    s.manual=nil s.releaseWait=true
    task.delay(.08,function()
        if not valid(s) or not s.step or attempt.fn~=s.step.fn then return end
        s.releaseWait=false
        local after=booleans(values(attempt.fn)) local candidates={}
        for index,before in pairs(attempt.before) do
            if before==false and (attempt.duringCount[index] or 0)>=2 and after[index]==false then candidates[#candidates+1]=index end
        end
        s.report.learning={duration=os.clock()-attempt.at,candidates=candidates,starts=(s.report.gameSent.Start or 0)-attempt.starts,peak=attempt.peak}
        if #candidates==1 and os.clock()-attempt.at>=.35 and (attempt.peak>.01 or s.report.learning.starts>0) then
            learned={fn=attempt.fn,index=candidates[1]} s.report.learning.confirmed=true
            bind(s,candidates[1],"toque real observado e solto")
        else s.report.learning.confirmed=false s.phase="Segure 1 segundo no jogo e solte uma vez para identificar a entrada" end
        event(s,"manual","end",s.report.learning)
    end)
end
local function tick(s)
    if not valid(s) then return end
    drain(s)
    local now=os.clock()
    local ready,full,note,percent=hudState(s)
    if not s.step and now>=(s.nextDiscovery or 0) then s.nextDiscovery=now+1 findStep(s) end
    if not s.step then s.phase="Procurando a funcao ativa do ima" return end
    local v=values(s.step.fn) if not v then error("Nao foi possivel ler a funcao ativa") end
    local current=booleans(v)
    if not s.binding and not s.manual and not s.releaseWait then s.boolFrame=current end
    if s.manual then
        s.manual.peak=math.max(s.manual.peak,percent)
        for index,value in pairs(current) do if value==true then s.manual.duringCount[index]=(s.manual.duringCount[index] or 0)+1 end end
        s.phase="Observando o toque real; solte apos 1 segundo" return
    end
    if not ready or full then
        release(s,full and "mochila cheia" or "fora da area/ferramenta")
        if next(s.pending) then stopPending(s) end
        s.binding=nil s.phase=full and "Mochila cheia: esvazie para continuar" or "Equipe o ima na area de coleta" return
    end
    if type(setUp)~="function" then s.phase="Executor sem acesso ao estado de segurar; copie o debug" return end
    if not s.binding and not s.releaseWait then
        if learned and learned.fn==s.step.fn then bind(s,learned.index,"entrada ja confirmada")
        elseif not s.probed then
            local index=chooseCandidate(s,v) local lower=note:lower()
            if index and (lower:find("locked",1,true) or lower:find("pulling",1,true) or lower:find("slipping",1,true)) then
                s.probed=true bind(s,index,"estado ao lado de UIS/GuiService; validacao por Start e barra")
            elseif not index then s.probed=true end
        end
    end
    if not s.binding then
        s.phase=s.probed and "Segure 1 segundo no jogo e solte uma vez para identificar a entrada" or "Aponte para um item ate aparecer Locked on" return
    end
    keepHeld(s)
    local b=s.binding b.peak=math.max(b.peak,percent)
    if not b.confirmed then
        local progressed=percent>b.baselineProgress+.005 or s.report.caughtWhileEnabled>b.catchesAtBind
        local started=(s.report.gameSent.Start or 0)>b.starts
        if b.kind=="toque real observado e solto" or b.kind=="entrada ja confirmada" or (started and progressed) then
            b.confirmed=true s.report.binding.confirmed=true learned={fn=b.fn,index=b.index}
            event(s,"input","hold_verified",{index=b.index,gameStart=started,progress=percent})
        elseif now-b.started>1.2 then
            release(s,"entrada nao iniciou Start e progresso") stopPending(s)
            s.binding=nil s.report.probeFailed=true s.boolFrame=booleans(values(s.step.fn))
            s.phase="Segure 1 segundo no jogo e solte uma vez para identificar a entrada" return
        end
    end
    s.phase=b.confirmed and "Segurando automaticamente; aponte para os itens" or "Verificando o estado real de segurar"
end
local function receive(s,action,id,used,capacity)
    if not valid(s) then return end
    drain(s)
    if action=="Caught" and type(id)=="number" and not s.caughtIds[id] then
        s.caughtIds[id]=true s.report.caughtWhileEnabled=s.report.caughtWhileEnabled+1
        append(s.report.catches,{id=id,t=elapsed(s),seconds=s.pending[id] and os.clock()-s.pending[id],used=used,capacity=capacity,manualTouches=s.report.manualTouches},12)
        s.pending[id]=nil event(s,"server","Caught",{id=id,used=used,capacity=capacity})
    elseif action=="Released" or action=="Refused" then
        if type(id)=="number" then s.pending[id]=nil end
        s.report[action]=(s.report[action] or 0)+1 event(s,"server",action,{id=id,used=used,capacity=capacity})
    end
end
copy=function()
    local r=active and active.report or lastReport
    if not r then label.Text="Ative Auto Pull para gerar o resultado." return end
    if active then r.seconds=elapsed(active) end
    local payload=Http:JSONEncode(r)
    env.MagnetDebugReport=payload env.MagnetReports={auto=payload}
    local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard
    local ok,value=false,nil if type(clip)=="function" then ok,value=pcall(clip,payload) end
    output.Text=payload output.Visible=not(ok and value~=false) label.Visible=not output.Visible
    if output.Visible then panel.Visible=true mini.Visible=false end
    return payload
end
stop=function(_,shouldCopy)
    local s=active if not s then if shouldCopy~=false then return copy() end return end
    drain(s) release(s,"OFF") stopPending(s) drain(s)
    s.running=false s.report.running=false s.report.seconds=elapsed(s) s.report.phase="OFF" s.report.dropped=probe.dropped
    active=nil lastReport=s.report probe.enabled=false probe.remote=nil disconnect(s.links)
    toggle.Text="Auto Pull: OFF" label.Text="Auto Pull parado. Resultado pronto."
    if shouldCopy~=false then return copy() end
end
start=function(mode)
    if not alive or active or (mode and mode~="auto") then return end
    local s={started=os.clock(),running=true,links={},pending={},caughtIds={},phase="Iniciando"}
    s.report={format="magnet-autopull-v3-hold-state",mode="auto",placeId=game.PlaceId,running=true,
        note="Apenas Auto Pull: mantem o estado de segurar e deixa a rotina original escolher/puxar/coletar. Sem clique virtual, sem Start/Catch direto, sem alteracao da barra/forca/quantidade. So Caught conta; nao exclui ajuda manual.",
        capabilities={connections=type(getConnections)=="function",upvalues=type(getup)=="function",constants=type(getConstants)=="function",setupvalue=type(setUp)=="function",screenInput=false},
        gameSent={Start=0,Catch=0,Stop=0},directSent={Start=0,Catch=0},holdWrites=0,cleanupStops=0,caughtWhileEnabled=0,manualTouches=0,catches={},events={}}
    active=s lastReport=s.report
    probe.enabled=false probe.queue={} probe.head=1 probe.tail=0 probe.dropped=0 probe.ownStop=false
    local folder=RS:FindFirstChild("Remotes") local remote=folder and folder:FindFirstChild("DebrisMagnet")
    if remote and remote:IsA("RemoteEvent") then s.remote=remote probe.remote=remote connect(remote.OnClientEvent,function(...) receive(s,...) end,s.links) end
    s.report.outgoingCapture=install() probe.enabled=s.report.outgoingCapture findStep(s)
    connect(UIS.InputBegan,function(input,processed) onBegin(s,input,processed) end,s.links)
    connect(UIS.InputEnded,function(input) onEnd(s,input) end,s.links)
    connect(Run.RenderStepped,function()
        if not valid(s) or s.failed then return end
        local ok,err=pcall(tick,s)
        if not ok then
            s.failed=true release(s,"erro") stopPending(s)
            s.report.error=tostring(err):sub(1,200) s.phase="Falha ao manter o toque; pare e copie o debug"
        end
        s.report.phase=s.phase
        if os.clock()>=(s.nextUi or 0) then s.nextUi=os.clock()+.12 label.Text=s.phase.."\nCapturas confirmadas: "..s.report.caughtWhileEnabled end
    end,s.links)
    output.Visible=false label.Visible=true toggle.Text="Auto Pull: ON / parar e copiar"
end
close=function()
    if not alive then return end
    if active then stop(nil,true) end
    alive=false probe.enabled=false disconnect(lifetime) gui:Destroy()
end
env.MagnetDebug={Start=start,Stop=stop,Copy=copy,Close=close,GetReport=function() return active and active.report or lastReport end,GetActive=function() return active and "auto" end}
connect(toggle.Activated,function() if active then stop(nil,true) else start("auto") end end,lifetime)
connect(copyButton.Activated,copy,lifetime)
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
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+delta.X,0,math.max(0,view.X-325)),math.clamp(panelStart.Y.Scale*view.Y+panelStart.Y.Offset+delta.Y,0,math.max(0,view.Y-216)))
    end
end,lifetime)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end,lifetime)
