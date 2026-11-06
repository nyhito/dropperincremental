-- Auto Fish mobile: clique rapido fora do minigame; segurar/soltar seguindo o peixe.
-- Entrada de tela virtual autorizada. Mantem o nome e a janela do teste.
-- A frequencia real depende dos frames; nao altera a barra nem promete queda instantanea.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local player=Players.LocalPlayer
assert(player and game.PlaceId==70960300100792,"Execute no jogo configurado.")
local env=(type(getgenv)=="function" and getgenv()) or _G
for _,name in ipairs({"FishingDebug","FishingAutoTest"}) do
    if env[name] and type(env[name].Close)=="function" then pcall(env[name].Close) end
end
local fishing=RS:WaitForChild("Remotes"):FindFirstChild("Fishing")
assert(fishing and fishing:IsA("RemoteEvent"),"Fishing indisponivel.")
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
local completionSent,held=false,false
local inputEpoch,injecting=0,0
local activeInput=nil
local virtualInputAt=-math.huge
local virtualX,virtualY=nil,nil
local modes,modeIndex={},1
local modeFault,inputWorking=false,false
local autoOwned=false
local geometry={}
local dropDebug=nil
local dropConnection=nil
local dragging=false
local autoButton=nil
local toggle,close,copy,setHeld,click,chooseMode
local startDropDebug,stopDropDebug
local observeDropEvent=nil
local diagnosticOwn=setmetatable({}, {__mode="k"})
local report={format="fishing-controller-v8-stable-screen",placeId=game.PlaceId,
    note="Conta Caught recebido enquanto ligado; nao distingue ajuda manual. Cliques completos em frames separados sem minigame; durante a barra segue o peixe. Nao remove queda/mordida.",
    caught=0,escaped=0,castsAccepted=0,bites=0,clicks=0,holdChanges=0,catchRequests=0,recoveries=0,holdResyncs=0,
    events={},catches={},inputErrors={},capabilities={},interval=interval}
local function connect(signal,fn)
    diagnosticOwn[fn]=true
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
    if dropDebug and dropDebug.running and #dropDebug.events<36 then
        if kind=="server" or tostring(action):find("Cast",1,true) or tostring(action):find("Hook",1,true) then
            dropDebug.events[#dropDebug.events+1]=e
        end
    end
    report.events[#report.events+1]=e
    if #report.events>32 then table.remove(report.events,1) end
end
local function rod()
    local c=player.Character
    if not c then return end
    local h=c:FindFirstChild("Humanoid") if h and h.Health<=0 then return end
    if rodCache and rodCache.Parent==c then return rodCache end
    local t=c:FindFirstChild("FishingRod")
    rodCache=t and t:IsA("Tool") and t or nil
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
    local pg=player:FindFirstChild("PlayerGui")
    if not pg then return false end
    local ok,hits=pcall(function() return pg:GetGuiObjectsAtPosition(x,y) end)
    if not ok or type(hits)~="table" then return true end
    for _,obj in ipairs(hits) do
        local a=obj
        for _=1,10 do
            if not a or a==pg then break end
            if a:IsA("GuiButton") or a:IsA("TextBox") then return false end
            if a.Name=="FishingControllerTest" then return false end
            a=a.Parent
        end
    end
    return true
end
local function position()
    local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000,700)
    if os.clock()-clickPoint.at<.35 and view.X==clickPoint.vx and view.Y==clickPoint.vy then
        return clickPoint.x,clickPoint.y
    end
    clickPoint.at=os.clock() clickPoint.vx=view.X clickPoint.vy=view.Y
    clickPoint.x,clickPoint.y=nil,nil
    for _,point in ipairs({{.78,.30},{.65,.36},{.53,.34},{.42,.38},{.78,.47},{.6,.48},{.52,.21},{.42,.23}}) do
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
        if autoButton then autoButton.Text="Auto Fish: OFF" end
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
    if reason then record("input",reason) end
    -- Um frame pressionado e outro solto. Evita que o mobile junte os dois estados.
    -- A soltura e processada no RenderStepped, sem tasks atrasadas de cliques antigos.
    if enabled and epoch==inputEpoch then pulse={releaseAt=os.clock()+.008,epoch=epoch} end
    return true
end
-- Painel de teste independente: ligado/desligado, intervalo e resultado para retorno.
local gui=Instance.new("ScreenGui") gui.Name="FishingControllerTest" gui.ResetOnSpawn=false gui.DisplayOrder=10031
 gui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame") panel.Size=UDim2.fromOffset(312,262) panel.Position=UDim2.new(0,12,0.15,0)
 panel.BackgroundColor3=Color3.fromRGB(21,23,30) panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,9)
local function button(text,x,y,w,h)
    local b=Instance.new("TextButton") b.Text=text b.Font=Enum.Font.Gotham b.TextSize=13
    b.TextColor3=Color3.new(1,1,1) b.BackgroundColor3=Color3.fromRGB(66,49,110)
    b.Position=UDim2.fromOffset(x,y) b.Size=UDim2.fromOffset(w,h) b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6) return b
end
local title=Instance.new("TextLabel") title.Text="AUTO FISH / CLIQUE RAPIDO" title.Font=Enum.Font.GothamBold title.TextSize=13
 title.TextColor3=Color3.new(1,1,1) title.BackgroundTransparency=1 title.Active=true
 title.Position=UDim2.fromOffset(10,3) title.Size=UDim2.fromOffset(224,30) title.Parent=panel
local minimize=button("-",242,6,26,26) local exit=button("X",276,6,26,26)
autoButton=button("Auto Fish: OFF",10,42,292,36)
local intervalLabel=Instance.new("TextLabel") intervalLabel.Text="Intervalo dos cliques (s)" intervalLabel.Font=Enum.Font.Gotham intervalLabel.TextSize=12
 intervalLabel.TextColor3=Color3.new(1,1,1) intervalLabel.BackgroundTransparency=1
 intervalLabel.Position=UDim2.fromOffset(10,85) intervalLabel.Size=UDim2.fromOffset(190,30) intervalLabel.Parent=panel
local intervalBox=Instance.new("TextBox") intervalBox.Text="0.001" intervalBox.ClearTextOnFocus=false intervalBox.Font=Enum.Font.Code intervalBox.TextSize=13
 intervalBox.TextColor3=Color3.new(1,1,1) intervalBox.BackgroundColor3=Color3.fromRGB(35,37,46)
 intervalBox.Position=UDim2.fromOffset(206,85) intervalBox.Size=UDim2.fromOffset(96,30) intervalBox.Parent=panel
local copyButton=button("Copiar resultado",10,123,292,31)
local dropButton=button("Debug queda (12 s)",10,161,292,31)
local label=Instance.new("TextLabel") label.Text="Chegue perto do lago e ative."
 label.TextWrapped=true label.TextXAlignment=Enum.TextXAlignment.Left label.TextYAlignment=Enum.TextYAlignment.Top
 label.Font=Enum.Font.Gotham label.TextSize=12 label.TextColor3=Color3.new(1,1,1) label.BackgroundTransparency=1
 label.Position=UDim2.fromOffset(10,200) label.Size=UDim2.fromOffset(292,53) label.Parent=panel
local mini=Instance.new("TextButton") mini.Text="PESCA" mini.Font=Enum.Font.GothamBold mini.TextSize=12
 mini.TextColor3=Color3.new(1,1,1) mini.BackgroundColor3=Color3.fromRGB(66,49,110)
 mini.Position=panel.Position mini.Size=UDim2.fromOffset(70,38) mini.Visible=false mini.Parent=gui
Instance.new("UICorner",mini).CornerRadius=UDim.new(0,8)
local output=Instance.new("TextBox") output.Text="" output.MultiLine=true output.TextWrapped=true output.ClearTextOnFocus=false
 output.Font=Enum.Font.Code output.TextSize=10 output.TextColor3=Color3.new(1,1,1) output.BackgroundColor3=Color3.fromRGB(29,31,39)
 output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top
 output.Position=UDim2.fromOffset(0,268) output.Size=UDim2.fromOffset(312,135) output.Visible=false output.Parent=panel
-- Diagnostico da queda: leitura local, sem alterar constantes, funcoes ou posicoes.
local function scanFallFunctions(d,active)
    local dbg=debug or {}
    local api={constants=dbg.getconstants or env.getconstants,upvalues=dbg.getupvalues or env.getupvalues,
        protos=dbg.getprotos or env.getprotos,proto=dbg.getproto or env.getproto,
        closure=getscriptclosure or env.getscriptclosure,senv=getsenv or env.getsenv,
        gc=getgc or env.getgc,connections=getconnections or env.getconnections,
        executor=isexecutorclosure or env.isexecutorclosure}
    d.capabilities={}
    for k,fn in pairs(api) do d.capabilities[k]=type(fn)=="function" end
    local scripts=player:FindFirstChild("PlayerScripts")
    local client=scripts and scripts:FindFirstChild("Client")
    local main=client and client:FindFirstChild("Main")
    d.script=main and main:GetFullName() or nil
    local scan={status="scanning",inspected=0,queued=0,liveCandidates=0,metadataCandidates=0,errors={},signals={}}
    d.scan=scan d.functions={}
    local queue,seen={},setmetatable({}, {__mode="k"})
    local head,ops,workAt=1,0,os.clock()
    local function pause(limit)
        ops=ops+1
        if ops>=(limit or 4) or os.clock()-workAt>.0015 then task.wait(.025) ops=0 workAt=os.clock() end
        return active()
    end
    local function fail(where,err)
        if #scan.errors<8 then scan.errors[#scan.errors+1]={where=where,error=tostring(err):sub(1,160)} end
    end
    local function related(value)
        local s=tostring(value):lower()
        for _,word in ipairs({"fish","rod","bobber","bait","cast","reel","bite","hook","tween","lerp","duration","delay","travel","flight","gravity","velocity","fall","animation"}) do
            if s:find(word,1,true) then return true end
        end
        return false
    end
    local function info(fn)
        local src,name="",""
        if dbg.info then pcall(function() src,name=dbg.info(fn,"sn") end)
        elseif dbg.getinfo then pcall(function() local i=dbg.getinfo(fn,"Sn") src=i.source name=i.name end) end
        if type(getfenv)=="function" then pcall(function()
            local scope=getfenv(fn) local script=type(scope)=="table" and rawget(scope,"script")
            if typeof(script)=="Instance" then src=script:GetFullName() end
        end) end
        return tostring(src or ""),tostring(name or "")
    end
    local function owned(fn)
        if diagnosticOwn[fn] then return false end
        if type(api.executor)=="function" then
            local ok,isOwn=pcall(api.executor,fn)
            if ok and isOwn then return false end
        end
        local src=info(fn) local lower=src:lower()
        if lower:find("coregui",1,true) or lower:find("corepackages",1,true) or lower:find("playermodule",1,true) then return false end
        return (d.script and src==d.script) or lower:find("playerscripts.client.main",1,true)
            or (lower:find("playerscripts",1,true) and lower:find("fish",1,true))
    end
    local function add(fn,origin,path,live,bobberContext,parent,index,depth)
        if type(fn)~="function" or diagnosticOwn[fn] or seen[fn] then return end
        if #queue>=512 then scan.truncated=true return end
        seen[fn]=true
        queue[#queue+1]={fn=fn,origin=origin,path=path,live=live,bobberContext=bobberContext,parent=parent,index=index,depth=depth or 0}
        scan.queued=#queue
    end
    local function retain(row)
        d.functions[#d.functions+1]=row
        table.sort(d.functions,function(a,b)
            if a.score==b.score then return a.kind=="active-reference" and b.kind~="active-reference" end
            return a.score>b.score
        end)
        if #d.functions>10 then table.remove(d.functions) end
    end
    local function inspect(entry)
        local fn=entry.fn local src,name=info(fn)
        if src=="" then src=d.script or "" end
        local lower=name:lower()
        local bobberContext=entry.bobberContext or lower:find("bobber",1,true)~=nil
        local score=bobberContext and 100 or (lower:find("fish",1,true) and 70 or 0)
        local rows,numeric={},{}
        if type(api.constants)=="function" then
            local ok,values=pcall(api.constants,fn)
            if ok and type(values)=="table" then
                local n=0
                for index,value in next,values do
                    n=n+1 if n>320 then break end
                    if type(value)=="string" then
                        local s=value:lower()
                        if s:find("bobber",1,true) then score=score+100 bobberContext=true
                        elseif s:find("fishing",1,true) or s:find("reelbar",1,true) then score=score+70
                        elseif s=="cast" or s=="bite" or s=="caught" then score=score+15
                        elseif s:find("lerp",1,true) or s:find("tween",1,true) or s:find("duration",1,true) then score=score+15 end
                        if related(value) and #rows<20 then rows[#rows+1]={index=tostring(index),value=value:sub(1,90)} end
                    elseif type(value)=="number" and value==value and math.abs(value)<=120 and #numeric<16 then
                        numeric[#numeric+1]={index=tostring(index),value=value}
                    end
                end
            end
        end
        if score>=70 then
            local row={origin=entry.origin,path=entry.path,source=src,name=name,
                kind=entry.live and "active-reference" or "metadata-only",score=score,constants={},upvalues={}}
            for _,v in ipairs(numeric) do row.constants[#row.constants+1]=v end
            for _,v in ipairs(rows) do if #row.constants<30 then row.constants[#row.constants+1]=v end end
            if entry.live then scan.liveCandidates=scan.liveCandidates+1 else scan.metadataCandidates=scan.metadataCandidates+1 end
            if entry.live and type(api.upvalues)=="function" then
                local ok,values=pcall(api.upvalues,fn)
                if ok and type(values)=="table" then
                    local n=0
                    for index,value in next,values do
                        n=n+1 if n>32 then break end
                        local kind=typeof(value)
                        if type(value)=="function" then
                            add(value,"upvalue",entry.path.."/u"..tostring(index),true,bobberContext)
                        elseif type(value)=="table" then
                            local selected,count={},0
                            for key,item in next,value do
                                count=count+1 if count>100 then break end
                                if type(key)=="string" and related(key) and #selected<6 then
                                    selected[#selected+1]={key=key:sub(1,70),value=safe(item,0,{left=6})}
                                    if type(item)=="function" then add(item,"upvalue-field",entry.path.."/"..key,true,bobberContext) end
                                end
                            end
                            if #selected>0 then row.upvalues[#row.upvalues+1]={index=tostring(index),fields=selected} end
                        elseif (kind=="number" or kind=="boolean" or kind=="Vector3" or kind=="Instance") and #row.upvalues<10 then
                            row.upvalues[#row.upvalues+1]={index=tostring(index),value=safe(value,0,{left=6})}
                        elseif type(value)=="string" and related(value) and #row.upvalues<10 then
                            row.upvalues[#row.upvalues+1]={index=tostring(index),value=value:sub(1,100)}
                        end
                    end
                end
            end
            retain(row)
            if entry.parent and entry.index and type(api.proto)=="function" then
                local ok,instances=pcall(api.proto,entry.parent,entry.index,true)
                if ok and type(instances)=="table" then
                    for i,instance in ipairs(instances) do
                        if i>4 then break end
                        add(instance,"active-proto",entry.path.."/active"..i,true,bobberContext)
                    end
                end
            end
        end
        if entry.depth~=7 and type(api.protos)=="function" then
            local ok,children=pcall(api.protos,fn)
            if ok and type(children)=="table" then
                local count=0
                for index,child in next,children do
                    count=count+1 if count>512 then scan.truncated=true break end
                    add(child,"prototype",entry.path.."/p"..tostring(index),false,bobberContext,fn,index,entry.depth+1)
                    if not pause(16) then return false end
                end
            end
        end
        return true
    end
    local ok,err=pcall(function()
        if main and type(api.closure)=="function" then
            local good,fn=pcall(api.closure,main)
            if good and type(fn)=="function" then add(fn,"script-copy","Main",false,false)
            else fail("getscriptclosure",good and "closure unavailable" or fn) end
        end
        if main and type(api.senv)=="function" then
            local good,scope=pcall(api.senv,main)
            if good and type(scope)=="table" then
                local count=0
                for key,value in next,scope do
                    count=count+1 if count>160 then break end
                    if type(value)=="function" and (related(key) or owned(value)) then add(value,"script-env","env."..tostring(key),true,false) end
                    if not pause(32) then return end
                end
            elseif not good then fail("getsenv",scope) end
        end
        if type(api.connections)=="function" then
            for _,pair in ipairs({{fishing.OnClientEvent,"Fishing.OnClientEvent"},{Run.RenderStepped,"RenderStepped"},{UIS.InputBegan,"InputBegan"}}) do
                local good,list=pcall(api.connections,pair[1])
                local summary={total=0,foreign=0,accessible=0}
                scan.signals[pair[2]]=summary
                if good and type(list)=="table" then
                    for i,c in ipairs(list) do
                        summary.total=summary.total+1 if i>100 then summary.truncated=true break end
                        local read,fn,foreign,on=pcall(function() return c.Function,c.ForeignState,c.Enabled end)
                        if read and foreign then summary.foreign=summary.foreign+1 end
                        if read and on~=false and type(fn)=="function" and not foreign and owned(fn) then
                            summary.accessible=summary.accessible+1 add(fn,"signal",pair[2].."/"..i,true,false)
                        end
                        if not pause(32) then return end
                    end
                elseif not good then fail(pair[2],list) end
            end
        end
        local function drain()
            while head<=#queue and active() do
                local entry=queue[head] head=head+1 scan.inspected=scan.inspected+1
                if not inspect(entry) then return end
                if not pause() then return end
            end
        end
        drain()
        if active() and scan.liveCandidates==0 and type(api.gc)=="function" then
            local good,list=pcall(api.gc,false)
            if good and type(list)=="table" then
                scan.gcTotal=#list scan.gcVisited=0
                for _,value in ipairs(list) do
                    scan.gcVisited=scan.gcVisited+1
                    if scan.gcVisited>12000 then scan.gcTruncated=true break end
                    if type(value)=="function" and owned(value) then add(value,"gc-owner","gc/"..scan.gcVisited,true,false) end
                    if not pause(64) then return end
                end
                list=nil drain()
            elseif not good then fail("getgc",list) end
        end
    end)
    if not ok then fail("scan",err) end
    scan.status=not active() and "stopped" or (scan.liveCandidates>0 and "active_references_found" or (scan.metadataCandidates>0 and "metadata_only" or "no_accessible_fishing_function"))
    scan.finishedAt=now()-d.started
end

stopDropDebug=function(shouldCopy)
    if not dropDebug or not dropDebug.running then return end
    local d=dropDebug d.running=false d.seconds=now()-d.started
    if d.scan and d.scan.status=="scanning" then d.scan.status="stopping" end
    if dropConnection then dropConnection:Disconnect() dropConnection=nil end
    observeDropEvent=nil
    local summary={casts=#d.cycles,caught=0,escaped=0}
    for _,field in ipairs({"castToLand","castToBite","landToBite","biteToBar","castToCaught","recastGap"}) do
        local count,sum,min,max=0,0,nil,nil
        for _,entry in ipairs(d.cycles) do
            local value=entry[field]
            if type(value)=="number" then count=count+1 sum=sum+value min=not min and value or math.min(min,value) max=not max and value or math.max(max,value) end
        end
        if count>0 then summary[field]={n=count,mean=sum/count,min=min,max=max} end
    end
    for _,entry in ipairs(d.cycles) do if entry.caughtAt then summary.caught=summary.caught+1 end if entry.escapedAt then summary.escaped=summary.escaped+1 end end
    d.summary=summary
    dropButton.Text="Debug queda (12 s)"
    if shouldCopy and copy then copy() end
end
startDropDebug=function()
    if not alive or (dropDebug and dropDebug.running) then return end
    local d={format="fishing-fall-debug-v2",running=true,started=now(),readOnly=true,events={},cycles={},parts={},
        note="Metadados de copia de script nao sao funcao ativa. Aterrissagem estimada perto do ponto recebido no Cast; nao comprova limite do servidor."}
    dropDebug=d report.dropDebug=d dropButton.Text="Parar debug / copiar"
    local state={connections={},roots={},rootList={},rootId=0,current=nil,lastCaught=nil,lastSample=-math.huge}
    local function active() return alive and d.running and dropDebug==d end
    local function listen(signal,fn)
        diagnosticOwn[fn]=true
        state.connections[#state.connections+1]=signal:Connect(fn)
    end
    dropConnection={Disconnect=function()
        for _,c in ipairs(state.connections) do c:Disconnect() end
        state.connections={} state.roots={} state.rootList={}
    end}
    local function attach(obj,preexisting)
        local root=obj
        for _=1,4 do
            if not root or root==workspace then return end
            if root.Name=="Bobber" and root.Parent==workspace then break end
            root=root.Parent
        end
        if not root or root==workspace or root.Name~="Bobber" or root.Parent~=workspace then return end
        local entry=state.roots[root]
        if not entry then
            if #state.rootList>=24 then d.rootLimit=true return end
            state.rootId=state.rootId+1
            entry={root=root,id=state.rootId,seenAt=now(),preexisting=preexisting==true}
            state.roots[root]=entry state.rootList[#state.rootList+1]=entry
        end
        if obj:IsA("BasePart") and (obj.Name=="Ball" or not entry.ball) then entry.ball=obj end
        local ball=root:FindFirstChild("Ball")
        if ball and ball:IsA("BasePart") then entry.ball=ball end
    end
    for _,root in ipairs(workspace:GetChildren()) do
        if root.Name=="Bobber" then attach(root,true) end
    end
    listen(workspace.DescendantAdded,function(obj) if active() then attach(obj,false) end end)
    observeDropEvent=function(action,...)
        if not active() then return end
        local args=table.pack(...) local t=now()
        if action=="Cast" then
            if #d.cycles>=8 then d.cycleLimit=true state.current=nil return end
            local target=args[1]
            local row={index=#d.cycles+1,castAt=t,serverValue=safe(args[2],0,{left=3}),autoFlag=args[3]}
            if typeof(target)=="Vector3" then row.target={x=target.X,y=target.Y,z=target.Z} end
            if state.lastCaught then row.recastGap=t-state.lastCaught end
            d.cycles[#d.cycles+1]=row state.current=row
        elseif state.current then
            local row=state.current
            if action=="Bite" then
                row.biteAt=t row.castToBite=t-row.castAt row.rarity=tostring(args[1])
                if row.landedAt then row.landToBite=t-row.landedAt end
            elseif action=="Caught" then
                row.caughtAt=t row.castToCaught=t-row.castAt row.fish=tostring(args[1]) state.lastCaught=t
            elseif action=="Escaped" then row.escapedAt=t end
        end
    end
    listen(UIS.InputBegan,function(input,processed)
        local row=state.current
        if not active() or not row or not row.biteAt or row.hookInputAt or processed then return end
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then row.hookInputAt=now() row.biteToInput=row.hookInputAt-row.biteAt end
    end)
    listen(Run.RenderStepped,function()
        if not active() then return end
        local row=state.current if not row then return end
        local shown,percent=progress()
        local t=now()
        if shown and not row.barAt then row.barAt=t if row.biteAt then row.biteToBar=t-row.biteAt end end
        if shown and percent and percent>=99.95 and row.barAt and not row.fullAt then row.fullAt=t end
        if not row.target or row.caughtAt or row.escapedAt then return end
        for _,entry in ipairs(state.rootList) do
            local ball=entry.ball
            if not entry.preexisting and entry.seenAt>=row.castAt-.15 and not entry.owner and ball and ball.Parent and entry.root.Parent==workspace then
                local p=ball.Position local target=row.target
                local dx,dz=p.X-target.x,p.Z-target.z
                local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                local nearPlayer=not root or (p-root.Position).Magnitude<18
                if nearPlayer or dx*dx+dz*dz<9 then
                    entry.owner=row entry.data={id=entry.id,cycle=row.index,path=ball:GetFullName(),class=ball.ClassName,samples={},association="near_player_then_target"}
                    d.parts[#d.parts+1]=entry.data
                end
            end
            if entry.owner==row and ball and ball.Parent and entry.root.Parent==workspace then
                local p=ball.Position local target=row.target local data=entry.data
                if p.Y-target.y>.5 then
                    data.sawAir=true
                    if row.bobberId==entry.id and row.landedAt and not row.biteAt then
                        -- Algumas criacoes comecam no alvo antes de iniciar o arco visual.
                        row.landedAt=nil row.castToLand=nil row.bobberId=nil row.landToBite=nil
                        data.earlyTargetDiscarded=true
                    end
                end
                if t-(entry.sampleAt or -math.huge)>=.04 and #data.samples<24 and (not row.landedAt or t-row.landedAt<.15) then
                    data.samples[#data.samples+1]={t=t-row.castAt,x=p.X,y=p.Y,z=p.Z} entry.sampleAt=t
                end
                local dx,dz=p.X-target.x,p.Z-target.z
                if dx*dx+dz*dz<=1 and math.abs(p.Y-target.y)<=.3 then
                    entry.contactAt=entry.contactAt or t
                    if not row.landedAt and t-entry.contactAt>=.02 then
                        row.landedAt=entry.contactAt row.castToLand=row.landedAt-row.castAt row.bobberId=entry.id
                        data.association="reached_server_target"
                        if row.biteAt then row.landToBite=row.biteAt-row.landedAt end
                    end
                else entry.contactAt=nil end
            end
        end
    end)
    task.spawn(function() scanFallFunctions(d,active) end)
    task.spawn(function()
        while active() and now()-d.started<12 do task.wait(.1) end
        if active() then stopDropDebug(true) end
    end)
end

local function resetCycle(reason)
    release()
    cycle=cycle+1 stage="idle" stateAt=os.clock() castAt=nil biteAt=nil hookAt=nil
    autoOwned=false completionSent=false geometry={}
    nextClick=os.clock()+math.min(frameDuration,.04) phase=reason or "Aguardando"
end
local function controlBar(dt)
    local bar=reelBar()
    local track=bar and bar:FindFirstChild("Track")
    local lane=track and track:FindFirstChild("Lane")
    local zone=lane and lane:FindFirstChild("Zone")
    local fish=lane and lane:FindFirstChild("Fish")
    if not lane or not zone or not fish or lane.AbsoluteSize.X<=0 or zone.AbsoluteSize.X<=0 then
        phase="Aguardando os elementos da barra"
        return
    end
    local left,width=lane.AbsolutePosition.X,lane.AbsoluteSize.X
    local zx=(zone.AbsolutePosition.X+zone.AbsoluteSize.X*.5-left)/width
    local fx=(fish.AbsolutePosition.X+fish.AbsoluteSize.X*.5-left)/width
    local zw=zone.AbsoluteSize.X/width
    dt=math.clamp(dt or 1/60,.004,.08)
    local g=geometry
    local zv=g.zone and (zx-g.zone)/dt or 0
    local fv=g.fish and (fx-g.fish)/dt or 0
    g.zv=(g.zv or 0)*.55+math.clamp(zv,-4,4)*.45
    g.fv=(g.fv or 0)*.7+math.clamp(fv,-4,4)*.3
    local target=math.clamp(fx+g.fv*.035,0,1)
    local projected=zx+g.zv*.045
    local error=target-projected
    local dead=math.clamp(zw*.045,.003,.014)
    local desired=held
    if error>dead then desired=true elseif error< -dead then desired=false end
    if g.resyncUntil and os.clock()<g.resyncUntil then desired=false end
    if not setHeld(desired) then
        if pointBlocked then phase="Ponto de clique coberto pela interface" g.lastMove=os.clock()
        elseif chooseMode("Segurar/soltar recusado") then setHeld(desired,true) end
    end
    if g.zone and math.abs(zx-g.zone)>.001 then
        g.lastMove=os.clock() inputWorking=true
    end
    g.lastMove=g.lastMove or os.clock()
    g.zone,g.fish,g.width=zx,fx,zw
    g.error=error g.inside=math.abs(fx-zx)<=zw*.5
    local _,percent=progress()
    if percent then g.peak=math.max(g.peak or 0,percent) if percent<99 then g.sawBelowFull=true end end
    local atLimit=(desired and zx>=1-zw*.5-.04) or (not desired and zx<=zw*.5+.04)
    if not g.inside and not atLimit and os.clock()-g.lastMove>1.2 and os.clock()-(g.lastResync or -math.huge)>1.5 then
        -- Ressincroniza soltar/segurar; nao abandona o metodo que ja pescou.
        release(true) g.lastResync=os.clock() g.resyncUntil=os.clock()+math.min(frameDuration,.04)
        g.lastMove=os.clock() report.holdResyncs=report.holdResyncs+1
    end
    report.controller={t=now(),fish=fx,zone=zx,width=zw,held=held,inside=g.inside,peak=g.peak,inputWorking=inputWorking}
end
local function onServer(action,...)
    if not alive then return end
    if enabled or (dropDebug and dropDebug.running) then record("server",action,...) end
    if observeDropEvent then
        local ok,err=pcall(observeDropEvent,action,...)
        if not ok and dropDebug then dropDebug.observationError=tostring(err) end
    end
    if not enabled then return end
    local args=table.pack(...)
    if action=="Cast" then
        if autoOwned then
            stage="waitingBite" stateAt=os.clock()
            castAt=castAt or os.clock() inputWorking=true castCheckAt=os.clock()
            report.castsAccepted=report.castsAccepted+1
            phase="Lancou; clicando ate fisgar"
        end
    elseif action=="Bite" then
        report.bites=report.bites+1 biteAt=os.clock()
        if autoOwned then
            stage="hooking" stateAt=os.clock() phase="Fisgando"
            hookAt=os.clock() release(true) nextClick=os.clock()+math.min(frameDuration,.04)
            record("input","Hook agendado no !")
        end
    elseif action=="Caught" then
        -- Touch sintetico no mobile nao identifica autoria. Conta apenas o evento real,
        -- sem classificar centenas de eventos injetados como intervencao manual.
        report.caught=report.caught+1
            report.catches[#report.catches+1]={t=now(),fish=safe(args[1],0,{left=8}),value2=safe(args[2],0,{left=8}),
                value3=safe(args[3],0,{left=8}),autoFlag=args[4],seconds=castAt and os.clock()-castAt,
                localPeak=geometry.peak,mode=modes[modeIndex] and modes[modeIndex].name}
            if #report.catches>8 then table.remove(report.catches,1) end
        resetCycle("Captura confirmada; relancando")
        castCheckAt=os.clock() attemptsSinceCheck=0
    elseif action=="Escaped" then
        report.escaped=report.escaped+1 resetCycle("Peixe escapou; relancando")
        castCheckAt=os.clock() attemptsSinceCheck=0
    end
end
connect(fishing.OnClientEvent,onServer)
toggle=function(value)
    if not alive then return end
    if value==nil then value=not enabled end
    release(true) enabled=value==true resetCycle(enabled and "Chegue perto do lago" or "OFF")
    if enabled then
        refreshModes() castCheckAt=os.clock() attemptsSinceCheck=0
        if #modes==0 then enabled=false phase="Executor sem clique virtual. Copie o resultado."
        elseif rod() then phase="Clicando rapido para lancar"
        else phase="Auto ligado; aproxime-se do lago para equipar a vara" end
    end
    autoButton.Text=enabled and "Auto Fish: ON" or "Auto Fish: OFF"
end
copy=function()
    report.enabled=enabled report.phase=phase report.stage=stage report.seconds=now() report.interval=interval
    report.hasRod=rod()~=nil
    local shown,n=progress() report.ui={barVisible=shown,percent=n}
    local export={} for k,v in pairs(report) do export[k]=v end
    local payload=Http:JSONEncode(export)
    if #payload>18000 and dropDebug then
        local d={} for k,v in pairs(dropDebug) do if k~="parts" then d[k]=v end end d.parts={}
        for _,part in ipairs(dropDebug.parts) do
            local samples={}
            for i,sample in ipairs(part.samples) do if i<=3 or i>#part.samples-6 then samples[#samples+1]=sample end end
            d.parts[#d.parts+1]={path=part.path,class=part.class,samples=samples}
        end
        export.dropDebug=d export.trimmed=true payload=Http:JSONEncode(export)
    end
    if #payload>18000 and export.dropDebug then
        -- Prioriza tempos por ciclo e funcoes; nao repete o historico em dois campos.
        local full=export.dropDebug local compact={}
        for k,v in pairs(full) do if k~="events" and k~="parts" and k~="functions" then compact[k]=v end end
        compact.parts={} compact.functions={}
        for i,part in ipairs(full.parts or {}) do
            if i>math.max(0,#full.parts-2) then
                local samples={}
                for n,sample in ipairs(part.samples or {}) do if n<=3 or n>#part.samples-3 then samples[#samples+1]=sample end end
                compact.parts[#compact.parts+1]={id=part.id,cycle=part.cycle,path=part.path,class=part.class,association=part.association,samples=samples}
            end
        end
        for i,fn in ipairs(full.functions or {}) do
            if i>7 then break end
            local row={} for k,v in pairs(fn) do if k~="constants" and k~="upvalues" then row[k]=v end end
            row.constants={} row.upvalues={}
            for n,v in ipairs(fn.constants or {}) do if n<=24 then row.constants[#row.constants+1]=v end end
            for n,v in ipairs(fn.upvalues or {}) do if n<=6 then row.upvalues[#row.upvalues+1]=v end end
            compact.functions[#compact.functions+1]=row
        end
        export.events=nil export.dropDebug=compact export.trimmed=true
        payload=Http:JSONEncode(export)
        while #payload>18000 and #compact.functions>2 do
            table.remove(compact.functions) payload=Http:JSONEncode(export)
        end
        if #payload>18000 then
            compact.parts={}
            for _,fn in ipairs(compact.functions) do
                local small={}
                for n,value in ipairs(fn.upvalues or {}) do
                    if n>3 then break end
                    if value.fields then
                        local fields={} for i,field in ipairs(value.fields) do if i<=2 then fields[#fields+1]=field end end
                        small[#small+1]={index=value.index,fields=fields}
                    else small[#small+1]=value end
                end
                fn.upvalues=small
            end
            payload=Http:JSONEncode(export)
        end
    end
    env.FishingAutoTestReport=payload
    local clip=setclipboard or toclipboard or env.setclipboard or env.toclipboard
    local ok,result=false,nil
    if type(clip)=="function" then ok,result=pcall(clip,payload) end
    output.Text=payload output.Visible=not (ok and result~=false)
    if output.Visible then panel.Visible=true mini.Visible=false end
    return payload
end
close=function()
    if not alive then return end
    if dropDebug and dropDebug.running then stopDropDebug(false) end
    toggle(false) alive=false
    for _,c in ipairs(links) do c:Disconnect() end
    gui:Destroy()
end
env.FishingAutoTest={Toggle=toggle,Copy=copy,Close=close,Report=report,StartDropDebug=function() startDropDebug() end,StopDropDebug=function() stopDropDebug(true) end}
connect(autoButton.Activated,function() toggle() end)
connect(copyButton.Activated,copy)
connect(dropButton.Activated,function() if dropDebug and dropDebug.running then stopDropDebug(true) else startDropDebug() end end)
connect(exit.Activated,close)
connect(minimize.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true clickPoint.at=-math.huge end)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false clickPoint.at=-math.huge end)
connect(intervalBox.FocusLost,function()
    local n=tonumber((intervalBox.Text:gsub(",",".")))
    if n and n==n then interval=math.clamp(n,.001,3) end
    intervalBox.Text=tostring(interval) report.interval=interval
end)
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
    if focused or dragging then release() phase="Pausado enquanto voce usa o painel" castCheckAt=os.clock() return end
    if tool~=lastRod then release() lastRod=tool castCheckAt=os.clock() attemptsSinceCheck=0 end
    if modeFault then if not chooseMode("Falha no clique virtual") then return end end
    local shown,n=progress()
    if shown then
        if pulse then release() end
        if stage~="reeling" and stage~="waitingCaught" then
            -- Cancela a soltura atrasada de um clique antes de segurar a barra.
            release() stage="reeling" stateAt=os.clock() geometry={} completionSent=false
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
        phase="Clicando rapido; aguardando !"
        if os.clock()-stateAt>15 then recover("Sem mordida; soltando e tentando relancar") end
    elseif stage=="hooking" and os.clock()-stateAt>4 then
        recover("Sem barra; soltando e tentando relancar")
    end
    -- Fora da barra, continua clicando durante queda, espera do ! e relancamento.
    if os.clock()>=nextClick then click() end
end
connect(Run.RenderStepped,function(dt)
    if not enabled then return end
    local ok,err=pcall(step,dt)
    if not ok then report.error=tostring(err) toggle(false) phase="Erro. Copie o resultado." end
    if not enabled then autoButton.Text="Auto Fish: OFF" end
end)
local dragInput,inputStart,panelStart
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true dragInput=input.UserInputType==Enum.UserInputType.Touch and input or nil
        inputStart=input.Position panelStart=panel.Position
    end
end)
connect(UIS.InputChanged,function(input)
    if not dragging then return end
    if (dragInput and input==dragInput) or (not dragInput and input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-inputStart
        local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000,700)
        panel.Position=UDim2.fromOffset(math.clamp(panelStart.X.Offset+delta.X,0,math.max(0,view.X-312)),
            math.clamp(panelStart.Y.Scale*view.Y+panelStart.Y.Offset+delta.Y,0,math.max(0,view.Y-262)))
    end
end)
connect(UIS.InputEnded,function(input) if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
task.spawn(function()
    while alive do label.Text=phase task.wait(.2) end
end)
print("Teste de pesca por clique e controle de barra pronto. Inicia OFF.")
