-- DebrisMagnet / Auto Pull v5. Entrada aprendida por mudancas durante um toque real.
-- Sem ponteiro virtual, TP, alteracao da barra, forca ou quantidade de alvos.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
local legacy=env.__NetoMagnetHoldProbe
if env.MagnetDebug and type(env.MagnetDebug.Close)=="function" then pcall(env.MagnetDebug.Close) end
if type(env.__NetoMagnetProbe)=="table" then env.__NetoMagnetProbe.enabled=false end
local pg=player:WaitForChild("PlayerGui")
local alive,active=true,nil
local lastReport=nil
local start,stop,copy,close
local own=setmetatable({},{__mode="k"})
local lifetime={}
local getup=(debug and debug.getupvalues) or env.getupvalues
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
local title=Instance.new("TextLabel") title.Text="AUTO PULL / V5" title.Font=Enum.Font.GothamBold title.TextSize=14
title.BackgroundTransparency=1 title.TextColor3=Color3.new(1,1,1) title.Position=UDim2.fromOffset(10,0) title.Size=UDim2.fromOffset(220,36) title.Active=true title.Parent=panel
local minimize=button("-",244,1,32) local exit=button("X",282,1,33)
local toggle=button("Auto Pull: OFF",10,43,305) local copyButton=button("Copiar debug",10,85,305)
local label=Instance.new("TextLabel") label.Text="Ative, segure no jogo ate a barra avancar e solte uma vez.\nEle identifica a entrada e testa manter sozinho."
label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top
label.Font=Enum.Font.Gotham label.TextSize=12 label.TextColor3=Color3.new(1,1,1) label.BackgroundTransparency=1
label.Position=UDim2.fromOffset(10,130) label.Size=UDim2.fromOffset(305,76) label.Parent=panel
local output=Instance.new("TextBox") output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false output.Text=""
output.Font=Enum.Font.Code output.TextSize=10 output.BackgroundColor3=Color3.fromRGB(28,30,39) output.TextColor3=Color3.new(1,1,1)
output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top
output.Position=label.Position output.Size=label.Size output.Visible=false output.Parent=panel
local mini=Instance.new("TextButton") mini.Text="PULL" mini.Font=Enum.Font.GothamBold mini.TextSize=12 mini.TextColor3=Color3.new(1,1,1)
mini.BackgroundColor3=Color3.fromRGB(66,49,110) mini.Size=UDim2.fromOffset(64,35) mini.Position=panel.Position mini.Visible=false mini.Parent=gui

local setUp=(debug and debug.setupvalue) or env.setupvalue
local learned=nil
local probe=env.__NetoMagnetHoldProbe
if type(probe)~="table" or probe.version~=3 then
    if type(probe)=="table" then probe.enabled=false probe.hold=false end
    probe={version=3,installed=false,enabled=false,stepRefs=setmetatable({},{__mode="k"})} env.__NetoMagnetHoldProbe=probe
end
local function install()
    if probe.installed then return true end
    local hook=hookmetamethod or env.hookmetamethod local method=getnamecallmethod or env.getnamecallmethod
    if type(hook)~="function" or type(method)~="function" then return false end
    local original
    local wrapper=function(self,...)
        if probe.enabled and self==probe.remote and method()=="FireServer" then
            if probe.tail-probe.head<128 then
                local action,id=... probe.tail=probe.tail+1
                probe.queue[probe.tail]={action=action,id=id,at=os.clock(),own=probe.ownStop==true}
            else probe.dropped=probe.dropped+1 end
        end
        return original(self,...)
    end
    local native=newcclosure or env.newcclosure if type(native)=="function" then wrapper=native(wrapper) end
    local ok,result=pcall(hook,game,"__namecall",wrapper)
    if ok then original=result probe.installed=true end return ok
end
local function drain(s)
    while probe.head<=probe.tail do
        local row=probe.queue[probe.head] probe.queue[probe.head]=nil probe.head=probe.head+1
        if row.action=="Start" or row.action=="Catch" or row.action=="Stop" then
            if not row.own then s.report.gameSent[row.action]=(s.report.gameSent[row.action] or 0)+1 end
            if row.action=="Start" and type(row.id)=="number" then
                s.pending[row.id]={started=row.at,manual=s.report.manualTouches,clean=next(s.touches)==nil and row.at>s.lastManualEnd+.3,binding=s.binding and s.binding.confirmed==true}
            elseif row.action=="Stop" and row.id~=nil then s.pending[row.id]=nil end
            event(s,row.own and "cleanup" or "game_send",row.action,{id=row.id})
        end
    end
    probe.queue={} probe.head=1 probe.tail=0
end
local function readRef(ref,cache)
    if ref.kind=="table" then return rawget(ref.owner,ref.key) end
    if ref.kind=="value" then return ref.owner.Value end
    local v
    if cache then v=cache[ref.fn] if v==nil then v=values(ref.fn) or false cache[ref.fn]=v end else v=values(ref.fn) end
    return v and v[ref.key]
end
local function writeRef(ref,value)
    if ref.kind=="table" then ref.owner[ref.key]=value
    elseif ref.kind=="value" then ref.owner.Value=value
    else assert(type(setUp)=="function","Executor sem setupvalue") setUp(ref.fn,ref.key,value) end
end
local function release(s,reason)
    local b=s.binding
    if b and b.wrote then
        local ok,err=pcall(writeRef,b.ref,b.original)
        local readOk,current=pcall(readRef,b.ref)
        s.report.inputRestored=ok and readOk and current==b.original
        if not ok then s.report.restoreError=tostring(err):sub(1,140) end
        b.wrote=false event(s,"input","released",{path=b.ref.path,reason=reason})
    end
    s.binding=nil
end
local function stopPending(s)
    if not s.remote then return end
    local ids={} for id in pairs(s.pending) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do
        probe.ownStop=true local ok=pcall(function() s.remote:FireServer("Stop",id) end) probe.ownStop=false
        if ok then s.report.cleanupStops=s.report.cleanupStops+1 end
    end s.pending={}
end
local function findStep(s)
    if type(getConnections)~="function" or type(getConstants)~="function" or type(getup)~="function" then return end
    local ok,list=pcall(getConnections,Run.RenderStepped) if not ok or type(list)~="table" then return end
    for i,c in ipairs(list) do
        if i>160 then break end
        local good,fn,foreign=pcall(function() return c.Function,c.ForeignState end)
        if good and not foreign and type(fn)=="function" and not own[fn] then
            local cached=probe.stepRefs[fn] or (legacy and legacy.stepRefs and legacy.stepRefs[fn]) or (legacy and legacy.stepHooks and legacy.stepHooks[fn])
            local actual=cached and (cached.actual or cached.original) or fn
            local source=cached and cached.source or "" local scriptObject=nil
            if type(getfenv)=="function" then pcall(function() local e=getfenv(actual) local x=rawget(e,"script") if typeof(x)=="Instance" then scriptObject=x source=path(x) end end) end
            if source:match("PlayerScripts%..*%.DebrisMagnet$") then
                local read,constants=pcall(getConstants,actual) local marks={}
                if read and type(constants)=="table" then for _,x in pairs(constants) do if type(x)=="string" then marks[x]=true end end end
                local v=values(actual) local hasPlayer,hasHud=false,false
                if v then for _,x in pairs(v) do if x==player then hasPlayer=true end if typeof(x)=="Instance" and x.Name=="DebrisHUD" then hasHud=true end end end
                if v and hasPlayer and hasHud and marks.DebrisMagnet and marks.GetMagnetStrength and marks.GetPullCount and marks.Progress then
                    s.step={fn=actual,source=source,script=scriptObject} probe.stepRefs[fn]={actual=actual,source=source}
                    s.report.liveStep={source=source,actualConnection=true,unwrappedLegacyHook=actual~=fn}
                    local names={} for key in pairs(marks) do if #names<150 then names[#names+1]=key end end table.sort(names)
                    s.report.inputConstants=names return
                end
            end
        end
    end
end
local function discoverRefs(s)
    if not s.step then return end
    local refs,queue,seenFn,seenTable={},{{value=s.step.fn,path="Step",depth=0}},{},{}
    local head,nodes=1,0
    local function addRef(ref)
        if #refs>=240 then return end
        ref.id=#refs+1 refs[#refs+1]=ref
    end
    while head<=#queue and nodes<420 do
        local item=queue[head] head=head+1 nodes=nodes+1
        local x=item.value local kind=typeof(x)
        if type(x)=="function" and not seenFn[x] then
            seenFn[x]=true
            local v=values(x)
            local audio=false
            if x~=s.step.fn and type(getConstants)=="function" then
                local ok,cs=pcall(getConstants,x)
                if ok and type(cs)=="table" then for _,k in pairs(cs) do if k=="MagnetPull" then audio=true end end end
            end
            if v and not audio then
                local keys={} for k in pairs(v) do if type(k)=="number" then keys[#keys+1]=k end end table.sort(keys)
                for _,k in ipairs(keys) do
                    local value=v[k] local p=item.path.."/u"..k
                    if type(value)=="boolean" then
                        -- O campo vizinho de UIS foi testado nas V3/V4 e nao sustenta o puxao.
                        local rejected=x==s.step.fn and v[k+1]==UIS
                        if not rejected then addRef({kind="upvalue",fn=x,key=k,path=p}) else s.report.excludedDerivedField=p end
                    elseif item.depth<4 and (type(value)=="function" or type(value)=="table" or (typeof(value)=="Instance" and value.ClassName=="BoolValue")) then
                        queue[#queue+1]={value=value,path=p,depth=item.depth+1}
                    end
                end
            end
        elseif kind=="Instance" and x.ClassName=="BoolValue" then addRef({kind="value",owner=x,path=item.path..".Value"})
        elseif type(x)=="table" and kind=="table" and not seenTable[x] then
            seenTable[x]=true
            local chunk=type(rawget(x,"Id"))=="number" and (rawget(x,"Model")~=nil or rawget(x,"Object")~=nil or rawget(x,"Born")~=nil)
            if not chunk and not (rawget(x,"BaseStrength") and rawget(x,"Chunks")) then
                local entries={} local count=0
                for k,v in next,x do count=count+1 if count>70 then break end entries[#entries+1]={key=k,value=v} end
                table.sort(entries,function(a,b) return tostring(a.key)<tostring(b.key) end)
                for _,entry in ipairs(entries) do
                    local k,value=entry.key,entry.value local p=item.path.."/"..tostring(k):sub(1,45)
                    if type(value)=="boolean" and (not table.isfrozen or not table.isfrozen(x)) then addRef({kind="table",owner=x,key=k,path=p})
                    elseif item.depth<4 and (type(value)=="function" or type(value)=="table" or (typeof(value)=="Instance" and value.ClassName=="BoolValue")) then
                        queue[#queue+1]={value=value,path=p,depth=item.depth+1}
                    end
                end
            end
        end
    end
    s.refs=refs s.report.discovery={references=#refs,inspected=nodes,bounded=head<=#queue,paths={}}
    for i,ref in ipairs(refs) do if i<=48 then s.report.discovery.paths[#s.report.discovery.paths+1]={path=ref.path,kind=ref.kind} end end
    s.report.rootUpvalues={}
    for index,value in pairs(values(s.step.fn) or {}) do
        local row={index=index,type=typeof(value)}
        if type(value)=="boolean" then row.value=value
        elseif typeof(value)=="Instance" then row.path=path(value)
        elseif type(value)=="table" and typeof(value)=="table" then
            row.fields={} local count=0
            for key,x in next,value do count=count+1 if count>18 then break end row.fields[#row.fields+1]={key=tostring(key):sub(1,50),type=typeof(x)} end
        end
        if #s.report.rootUpvalues<48 then s.report.rootUpvalues[#s.report.rootUpvalues+1]=row end
    end
end
local function snapshot(s)
    local out,cache={},{}
    for _,ref in ipairs(s.refs or {}) do
        local ok,value=pcall(readRef,ref,cache) if ok and type(value)=="boolean" then out[ref.id]=value end
    end return out
end
local function overDebug(input)
    local p=input.Position if not p then return false end
    local ok,list=pcall(function() return pg:GetGuiObjectsAtPosition(p.X,p.Y) end)
    if ok then for _,x in ipairs(list) do if x==gui or x:IsDescendantOf(gui) then return true end end end return false
end
local function onBegin(s,input,processed)
    local kind=input.UserInputType
    if not valid(s) or processed or overDebug(input) or (kind~=Enum.UserInputType.Touch and kind~=Enum.UserInputType.MouseButton1) then return end
    s.report.manualTouches=s.report.manualTouches+1 s.touches[input]=true
    if not s.binding and s.step and not s.capture then
        s.capture={input=input,at=os.clock(),before=s.baseline or {},samples={},peak=s.report.ui.progress or 0}
        event(s,"manual","calibration_begin",{})
    end
end
local function onEnd(s,input)
    if not valid(s) or not s.touches[input] then return end
    s.touches[input]=nil s.lastManualEnd=os.clock()
    local capture=s.capture if not capture or capture.input~=input then return end
    s.capture=nil s.releaseWait=true
    task.delay(.10,function()
        if not valid(s) then return end
        s.releaseWait=false local after=snapshot(s) local candidates={} local changes={}
        for _,ref in ipairs(s.refs or {}) do
            local before=capture.before[ref.id] local held=capture.samples[ref.id]
            if held and held.count>=2 and type(before)=="boolean" and held.value~=before and after[ref.id]==before then
                local score=ref.kind=="table" and 15 or 0 local name=ref.path:lower()
                for _,word in ipairs({"held","hold","press","touch","down","input","trigger"}) do if name:find(word,1,true) then score=score+40 end end
                candidates[#candidates+1]={ref=ref,held=held.value,score=score}
                if #changes<24 then changes[#changes+1]={path=ref.path,kind=ref.kind,before=before,held=held.value,after=after[ref.id]} end
            end
        end
        table.sort(candidates,function(a,b) if a.score==b.score then return a.ref.path<b.ref.path end return a.score>b.score end)
        s.report.calibration={duration=os.clock()-capture.at,peak=capture.peak,changes=changes}
        if capture.peak>.01 and os.clock()-capture.at>.4 then
            s.candidates={} for i=1,math.min(6,#candidates) do s.candidates[#s.candidates+1]=candidates[i] end
            s.nextCandidate=1
        end
        event(s,"manual","calibration_end",{candidates=#candidates,peak=capture.peak})
    end)
end
local function beginTrial(s,candidate)
    local ref=candidate.ref local ok,original=pcall(readRef,ref)
    if not ok or type(original)~="boolean" then return false end
    local wrote,err=pcall(writeRef,ref,candidate.held)
    if not wrote then event(s,"input","write_failed",{path=ref.path,error=tostring(err):sub(1,100)}) return false end
    s.report.holdWrites=s.report.holdWrites+1
    local readOk,readback=pcall(readRef,ref)
    if not readOk or readback~=candidate.held then pcall(writeRef,ref,original) event(s,"input","write_not_visible",{path=ref.path}) return false end
    s.binding={ref=ref,original=original,held=candidate.held,started=os.clock(),baseline=s.report.ui.progress or 0,low=s.report.ui.progress or 0,rewrites=0,wrote=true,confirmed=false}
    s.report.binding={path=ref.path,kind=ref.kind,confirmed=false}
    event(s,"input","trial_begin",{path=ref.path,held=candidate.held}) return true
end
local function tick(s)
    if not valid(s) then return end
    drain(s) local now=os.clock() local ready,full,_,percent=hudState(s)
    if not s.step and now>=(s.nextDiscovery or 0) then
        s.nextDiscovery=now+1 findStep(s)
        if s.step then discoverRefs(s) s.baseline=snapshot(s) end
    end
    if not ready or full then
        release(s,full and "mochila cheia" or "fora da area") stopPending(s)
        s.phase=full and "Mochila cheia" or "Equipe o ima na area de coleta" return
    end
    if not s.step then s.phase="Procurando a rotina ativa do ima" return end
    if s.capture then
        s.capture.peak=math.max(s.capture.peak,percent)
        if now>=(s.nextSample or 0) then
            s.nextSample=now+.04
            for id,value in pairs(snapshot(s)) do
                local item=s.capture.samples[id]
                if not item or item.value~=value then s.capture.samples[id]={value=value,count=1} else item.count=item.count+1 end
            end
        end
        s.phase="Observando a entrada real: quando a barra avancar, solte" return
    end
    if s.releaseWait or next(s.touches) then return end
    if not s.binding then
        if learned and learned.fn==s.step.fn then if not beginTrial(s,learned.candidate) then learned=nil end
        elseif s.candidates then
            while not s.binding and s.nextCandidate<=#s.candidates do
                local candidate=s.candidates[s.nextCandidate] s.nextCandidate=s.nextCandidate+1 beginTrial(s,candidate)
            end
        end
    end
    local b=s.binding
    if not b then
        if now>=(s.nextBaseline or 0) then s.nextBaseline=now+.08 s.baseline=snapshot(s) end
        s.phase="Calibracao: segure no jogo ate a barra avancar e solte uma vez" return
    end
    local current=readRef(b.ref)
    if current~=b.held then
        b.rewrites=b.rewrites+1
        local ok,err=pcall(writeRef,b.ref,b.held)
        if not ok then error(tostring(err)) end s.report.holdWrites=s.report.holdWrites+1
    else b.rewrites=0 end
    b.low=math.min(b.low,percent)
    if b.rewrites>=3 then
        learned=nil event(s,"input","trial_rejected",{path=b.ref.path,rewrites=b.rewrites,progress=percent})
        release(s,"campo regravado pelo jogo") stopPending(s) return
    end
    if not b.confirmed then
        if now-b.started>.25 and percent>b.low+.035 and b.rewrites<3 then
            b.confirmed=true s.report.binding.confirmed=true learned={fn=s.step.fn,candidate={ref=b.ref,held=b.held}}
            event(s,"input","progress_without_touch",{path=b.ref.path,progress=percent})
        elseif now-b.started>1.3 then
            event(s,"input","trial_rejected",{path=b.ref.path,rewrites=b.rewrites,progress=percent})
            release(s,"nao sustentou progresso sem toque") stopPending(s) return
        end
    end
    if s.report.autonomousCaught>=2 then s.report.autonomousVerified=true end
    s.phase=s.report.autonomousVerified and "Auto Pull: coletas sem toque confirmadas" or (b.confirmed and "Entrada mantida; validando coletas sem toque" or "Testando entrada depois de soltar a tela")
end
local function receive(s,action,id,used,capacity)
    if not valid(s) then return end drain(s)
    if action=="Caught" and type(id)=="number" and not s.caughtIds[id] then
        s.caughtIds[id]=true s.report.caughtWhileEnabled=s.report.caughtWhileEnabled+1 local pull=s.pending[id]
        local autonomous=pull and pull.clean and pull.binding and pull.manual==s.report.manualTouches and next(s.touches)==nil or false
        if autonomous then s.report.autonomousCaught=s.report.autonomousCaught+1 else s.report.assistedOrUnownedCaught=s.report.assistedOrUnownedCaught+1 end
        append(s.report.catches,{id=id,t=elapsed(s),seconds=pull and os.clock()-pull.started,used=used,capacity=capacity,autonomous=autonomous},12)
        s.pending[id]=nil event(s,"server","Caught",{id=id,autonomous=autonomous})
    elseif action=="Released" or action=="Refused" then
        if id~=nil then s.pending[id]=nil end
        s.report[action]=(s.report[action] or 0)+1 event(s,"server",action,{id=id})
    end
end

copy=function()
    local r=active and active.report or lastReport
    if not r then label.Text="Ative Auto Pull para gerar o resultado." return end
    if active then r.seconds=elapsed(active) end
    local export={} for key,value in pairs(r) do export[key]=value end
    export.events={} for _,value in ipairs(r.events) do export.events[#export.events+1]=value end
    local payload=Http:JSONEncode(export)
    if #payload>18000 then export.trimmed=true export.rootUpvalues=nil payload=Http:JSONEncode(export) end
    if #payload>18000 then export.inputConstants=nil payload=Http:JSONEncode(export) end
    while #payload>18000 and #export.events>8 do table.remove(export.events,1) payload=Http:JSONEncode(export) end
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
    local s={started=os.clock(),running=true,links={},pending={},caughtIds={},touches={},lastManualEnd=-math.huge,phase="Iniciando"}
    s.report={format="magnet-autopull-v5-state-discovery",mode="auto",placeId=game.PlaceId,running=true,
        note="Auto Pull com calibracao: observa mudancas em referencias vivas durante um toque e testa manter a entrada apos soltar. Candidatos sao reversiveis; barra/forca/alvos nao sao modificados. Sem clique virtual nem Start/Catch direto. So duas coletas completas sem toque confirmam o auto.",
        capabilities={connections=type(getConnections)=="function",upvalues=type(getup)=="function",constants=type(getConstants)=="function",setupvalue=type(setUp)=="function",sharedTables=true,screenInput=false},
        gameSent={Start=0,Catch=0,Stop=0},directSent={Start=0,Catch=0},holdWrites=0,cleanupStops=0,caughtWhileEnabled=0,autonomousCaught=0,assistedOrUnownedCaught=0,autonomousVerified=false,manualTouches=0,catches={},events={}}
    active=s lastReport=s.report
    s.report.device={}
    pcall(function() s.report.device.touchEnabled=UIS.TouchEnabled s.report.device.mouseEnabled=UIS.MouseEnabled end)
    pcall(function() s.report.device.lastInputType=tostring(UIS:GetLastInputType()) end)
    probe.enabled=false probe.queue={} probe.head=1 probe.tail=0 probe.dropped=0 probe.ownStop=false
    local folder=RS:FindFirstChild("Remotes") local remote=folder and folder:FindFirstChild("DebrisMagnet")
    if remote and remote:IsA("RemoteEvent") then s.remote=remote probe.remote=remote connect(remote.OnClientEvent,function(...) receive(s,...) end,s.links) end
    s.report.outgoingCapture=install() probe.enabled=s.report.outgoingCapture findStep(s)
    if s.step then discoverRefs(s) s.baseline=snapshot(s) end
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
        if os.clock()>=(s.nextUi or 0) then s.nextUi=os.clock()+.12 label.Text=s.phase.."\nColetas sem toque: "..s.report.autonomousCaught end
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
