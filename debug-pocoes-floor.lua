-- Auto Fish / controlador local. Mantem o mesmo nome do arquivo de teste.
-- Chama somente funcoes locais de entrada; nunca injeta cliques fisicos na tela.
-- Nao forja Zone, nao altera a UI e nao conta capturas manuais como sucesso do auto.
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
local ownCallbacks=setmetatable({}, {__mode="k"})
local started=os.clock()
local phase="OFF"
local stage="idle"
local cycle=0
local stateAt=os.clock()
local rodCache,uiCache=nil,nil
local nextCast=0
local recastDelay=0
local castAt,biteAt,hookAt=nil,nil,nil
local lastClick=-math.huge
local clickCount=0
local completionSent=false
local held=false
local inputEpoch=0
local activeInput=nil
local lastRealInput=nil
local injecting=0
local injectedInputs=setmetatable({}, {__mode="k"})
local nextModeScan=0
local inputUnavailableAt=nil
local modeIndex=1
local modes={}
local inputWorking=false
local modeFault=false
local autoOwned=false
local manualAssisted=false
local boundFunctions={}
local observedFunctions={}
local fingerprintCache=setmetatable({}, {__mode="k"})
local dropDebug=nil
local dropConnection=nil
local startDropDebug,stopDropDebug
local geometry={}
local autoButton=nil
local toggle,close,copy,setHeld,click,chooseMode
local report={format="fishing-controller-v5-native-bridge",placeId=game.PlaceId,
    note="Chama funcoes locais, sem ponteiro virtual. Controla a barra real. Caught so conta no ciclo iniciado/controlado pelo auto. Nao comprova remocao dos tempos de queda/mordida.",
    caught=0,escaped=0,manualOrUnownedCaught=0,manualTouches=0,castsAccepted=0,bites=0,clicks=0,holdChanges=0,catchRequests=0,
    events={},catches={},inputErrors={},capabilities={},recastDelay=0}
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
    if dropDebug and dropDebug.running and #dropDebug.events<30 then
        if tostring(action):find("Cast",1,true) or action=="Bite" or tostring(action):find("Hook",1,true) then
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
local function sourceOf(fn,c)
    local source
    pcall(function()
        if type(getfenv)=="function" then
            local scope=getfenv(fn)
            if scope and typeof(scope.script)=="Instance" then source=scope.script:GetFullName() end
        end
    end)
    if not source then pcall(function() if c.Thread and type(getscriptfromthread)=="function" then source=getscriptfromthread(c.Thread):GetFullName() end end) end
    if not source then pcall(function() if debug and debug.info then source=debug.info(fn,"s") end end) end
    return tostring(source or "")
end
local function constantsOf(fn)
    local reader=debug and debug.getconstants
    if type(reader)~="function" then return {} end
    local ok,result=pcall(reader,fn)
    return ok and type(result)=="table" and result or {}
end
local function field(obj,key,errors)
    local ok,value=pcall(function() return obj[key] end)
    if not ok and errors then errors[key]=tostring(value):sub(1,110) end
    if ok then return value end
    return nil
end
local function fishingFingerprint(root)
    local cached=fingerprintCache[root] if cached then return cached.score,cached.evidence end
    local queue={{value=root,depth=0,label="fn"}}
    local seen={} local index,budget,score=1,44,0
    local evidence={}
    local function hit(points,label)
        score=math.max(score,points)
        if #evidence<5 then evidence[#evidence+1]=label end
    end
    while index<=#queue and budget>0 and score<85 do
        local item=queue[index] index=index+1
        local v=item.value
        if not seen[v] then
            seen[v]=true budget=budget-1
            if type(v)=="function" and not ownCallbacks[v] then
                local fish,action=false,false
                for _,x in pairs(constantsOf(v)) do
                    if x=="Fishing" or x=="FishingRod" or x=="ReelBar" then fish=true end
                    if x=="Cast" or x=="Hook" or x=="Catch" or x=="Bite" then action=true end
                end
                if fish and action then hit(85,item.label..": fishing actions")
                elseif fish then hit(65,item.label..": fishing reference") end
                if item.depth<3 and debug and type(debug.getupvalues)=="function" then
                    local ok,values=pcall(debug.getupvalues,v)
                    if ok and type(values)=="table" then
                        local n=0
                        for key,x in next,values do
                            n=n+1 if n>32 or #queue>=80 then break end
                            if type(key)=="string" and (key:lower():find("fish",1,true) or key:lower():find("reel",1,true)) then hit(65,item.label..":"..key) end
                            if type(x)=="function" or type(x)=="table" or typeof(x)=="Instance" then
                                queue[#queue+1]={value=x,depth=item.depth+1,label=item.label.."/uv"..tostring(key):sub(1,25)}
                            end
                        end
                    end
                end
            elseif typeof(v)=="Instance" then
                if v==fishing then hit(85,item.label..": Fishing remote")
                else
                    local name=v.Name:lower()
                    if name=="reelbar" or name=="fishingrod" then hit(70,item.label..": "..v.Name) end
                end
            elseif type(v)=="table" and item.depth<3 and v~=_G and v~=env then
                local n=0
                for key,x in next,v do
                    n=n+1 if n>32 or #queue>=80 then break end
                    if key=="Fishing" or key=="ReelBar" or key=="FishingRod" then hit(65,item.label..":"..tostring(key)) end
                    if type(x)=="function" or (type(x)=="table" and item.depth<2) or typeof(x)=="Instance" then
                        queue[#queue+1]={value=x,depth=item.depth+1,label=item.label.."/"..tostring(key):sub(1,25)}
                    end
                end
            end
        end
    end
    fingerprintCache[root]={score=score,evidence=evidence}
    return score,evidence
end
local function callbacks(signal,origin)
    local list=getconnections or env.getconnections
    origin=origin or "unknown"
    report.discovery=report.discovery or {}
    local summary={total=0,accessible=0,selected=0,records={}}
    report.discovery[origin]=summary
    if type(list)~="function" or not signal then summary.error="getconnections/sinal indisponivel" return {} end
    local ok,all=pcall(list,signal)
    if not ok or type(all)~="table" then summary.error=tostring(all):sub(1,160) return {} end
    local candidates,best={},0
    for key,c in pairs(all) do
        summary.total=summary.total+1
        if summary.total>1024 then summary.truncated=true break end
        local errors={}
        -- Campos opcionais NAO podem invalidar Function. Alguns executores lancam erro ao le-los.
        local fn=type(c)=="function" and c or field(c,"Function",errors)
        if type(fn)~="function" and type(c)~="function" then fn=field(c,"Callback",errors) end
        local on,foreign
        if type(c)~="function" then on=field(c,"Enabled",errors) foreign=field(c,"ForeignState",errors) end
        local row={index=tostring(key),functionType=type(fn),enabled=on,foreign=foreign}
        if next(errors) then row.fieldErrors=errors end
        if type(fn)=="function" and not ownCallbacks[fn] and on~=false and foreign~=true then
            summary.accessible=summary.accessible+1
            local source=sourceOf(fn,type(c)=="function" and {} or c)
            local lower=source:lower()
            local score=(lower:find("playerscripts.client.main",1,true) and 100)
                or (lower:find("playerscripts",1,true) and lower:find("fish",1,true) and 90)
                or (lower:find("client.main",1,true) and 85) or 0
            local evidence={}
            if not lower:find("corepackages",1,true) and not lower:find("playermodule",1,true) then
                local match,why=fishingFingerprint(fn)
                if match>=60 then score=200+match evidence=why end
            end
            row.source=source:sub(1,180) row.score=score row.evidence=evidence
            local entry={fn=fn,source=source,score=score,origin=origin,evidence=evidence}
            observedFunctions[fn]=entry
            if score>=60 then candidates[#candidates+1]=entry best=math.max(best,score) end
        end
        if #summary.records<8 then summary.records[#summary.records+1]=row
        elseif row.score and row.score>=60 then
            for i,old in ipairs(summary.records) do if not old.score or old.score<60 then summary.records[i]=row break end end
        end
    end
    local selected={}
    for _,c in ipairs(candidates) do
        if c.score==best then selected[#selected+1]=c boundFunctions[c.fn]=c end
    end
    summary.selected=#selected
    return selected
end
local function inputError(message)
    modeFault=true
    report.inputErrors[#report.inputErrors+1]={t=now(),mode=modes[modeIndex] and modes[modeIndex].name,error=tostring(message):sub(1,230)}
    if #report.inputErrors>6 then table.remove(report.inputErrors,1) end
end
local function position()
    local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000,700)
    return math.floor(view.X*.78),math.floor(view.Y*.30)
end
-- Pontes nativas disparam sinais/funcoes da vara, sem mover mouse ou gerar toque na tela.
local function nativeBindings(signal,origin)
    local list=getconnections or env.getconnections
    local summary={total=0,lua=0,foreignLua=0,defer=0,fire=0}
    report.nativeDiscovery=report.nativeDiscovery or {} report.nativeDiscovery[origin]=summary
    if type(list)~="function" or not signal then return {} end
    local ok,all=pcall(list,signal)
    if not ok or type(all)~="table" then summary.error=tostring(all):sub(1,120) return {} end
    local result={}
    for _,c in pairs(all) do
        summary.total=summary.total+1 if summary.total>1024 then summary.truncated=true break end
        if type(c)~="function" then
            local lua=field(c,"LuaConnection")
            local foreign=field(c,"ForeignState")
            local on=field(c,"Enabled")
            if lua==true and on~=false then
                summary.lua=summary.lua+1
                if foreign==true then
                    summary.foreignLua=summary.foreignLua+1
                    local method=field(c,"Defer") local methodName="Defer"
                    if type(method)~="function" then method=field(c,"Fire") methodName="Fire" end
                    if type(method)=="function" and #result<64 then
                        result[#result+1]={connection=c,method=method,name=methodName}
                        summary[methodName:lower()]=summary[methodName:lower()]+1
                    end
                end
            end
        end
    end
    return result
end
local function emitForeign(bindings,...)
    local count,last=0,nil
    for _,binding in ipairs(bindings) do
        local ok,err=pcall(binding.method,binding.connection,...)
        if ok then count=count+1 else last=err end
    end
    if count==0 then error(last or "Nenhuma conexao estrangeira foi acionada.") end
end
local function inputPacket(down,kind,reuse)
    local input
    if reuse and lastRealInput then input=lastRealInput
    else
        local x,y=position()
        if down or not activeInput then activeInput={UserInputType=kind,KeyCode=Enum.KeyCode.Unknown,
            Position=Vector3.new(x,y,0),Delta=Vector3.new(0,0,0)} end
        activeInput.UserInputState=down and Enum.UserInputState.Begin or Enum.UserInputState.End
        input=activeInput
    end
    injectedInputs[input]=os.clock()
    return input
end
local function signalPair(name,beginSignal,endSignal)
    if not beginSignal or not endSignal then return end
    local nativeBegin=nativeBindings(beginSignal,name..".Begin")
    local nativeEnd=nativeBindings(endSignal,name..".End")
    if #nativeBegin>0 and #nativeEnd>0 then
        modes[#modes+1]={name=name.." / conexoes nativas",press=function(down)
            emitForeign(down and nativeBegin or nativeEnd)
        end}
    end
    local fire=firesignal or env.firesignal
    local b=report.nativeDiscovery[name..".Begin"]
    local e=report.nativeDiscovery[name..".End"]
    local listenersUnknown=type(getconnections or env.getconnections)~="function"
    if type(fire)=="function" and (listenersUnknown or (b and e and b.total>0 and e.total>0)) then
        modes[#modes+1]={name=name.." / sinal local",press=function(down)
            injecting=injecting+1
            local ok,err=pcall(fire,down and beginSignal or endSignal)
            injecting=injecting-1
            if not ok then error(err) end
        end}
    end
end
local function addNativeModes(tool)
    if not tool then return end
    -- Activate/Deactivate pertencem a ferramenta; nao fazem hit-test de botoes da tela.
    modes[#modes+1]={name="FishingRod / Activate",press=function(down)
        local r=rod() or tool
        if down then r:Activate() else r:Deactivate() end
    end}
    pcall(function()
        local mouse=player:GetMouse()
        if mouse then signalPair("Mouse.Button1",mouse.Button1Down,mouse.Button1Up) end
    end)
    signalPair("FishingRod.Events",tool.Activated,tool.Deactivated)
    local begins=nativeBindings(UIS.InputBegan,"UIS.InputBegan")
    local ends=nativeBindings(UIS.InputEnded,"UIS.InputEnded")
    local kinds={Enum.UserInputType.MouseButton1,Enum.UserInputType.Touch}
    if #begins>0 and #ends>0 then
        local variants=lastRealInput and {"real","mouse","touch"} or {"mouse","touch"}
        for _,variant in ipairs(variants) do
            local mode=variant
            modes[#modes+1]={name="UIS / conexoes nativas / "..mode,press=function(down)
                local kind=mode=="touch" and kinds[2] or kinds[1]
                emitForeign(down and begins or ends,inputPacket(down,kind,mode=="real"),false)
            end}
        end
    end
    local fire=firesignal or env.firesignal
    if type(fire)=="function" then
        local variants=lastRealInput and {"real","mouse","touch"} or {"mouse","touch"}
        for _,variant in ipairs(variants) do
            local mode=variant
            modes[#modes+1]={name="UIS / sinal local / "..mode,press=function(down)
                local kind=mode=="touch" and kinds[2] or kinds[1]
                local packet=inputPacket(down,kind,mode=="real")
                injecting=injecting+1
                local ok,err=pcall(fire,down and UIS.InputBegan or UIS.InputEnded,packet,false)
                injecting=injecting-1
                if not ok then error(err) end
            end}
        end
    end
end

local function refreshModes()
    modes={}
    local begins,ends=callbacks(UIS.InputBegan,"InputBegan"),callbacks(UIS.InputEnded,"InputEnded")
    report.bindings={began={},ended={}}
    for _,c in ipairs(begins) do report.bindings.began[#report.bindings.began+1]=c.source end
    for _,c in ipairs(ends) do report.bindings.ended[#report.bindings.ended+1]=c.source end
    if #begins>0 and #ends>0 then
        for _,kind in ipairs({Enum.UserInputType.MouseButton1,Enum.UserInputType.Touch}) do
            local inputKind=kind
            modes[#modes+1]={name="Client.Main / "..tostring(inputKind),press=function(down)
                local x,y=position()
                if down then
                    activeInput={UserInputType=inputKind,UserInputState=Enum.UserInputState.Begin,KeyCode=Enum.KeyCode.Unknown,
                        Position=Vector3.new(x,y,0),Delta=Vector3.new(0,0,0)}
                end
                local input=activeInput
                if not input then return end
                input.UserInputState=down and Enum.UserInputState.Begin or Enum.UserInputState.End
                local selected=down and begins or ends
                local epoch=inputEpoch
                for _,binding in ipairs(selected) do
                    task.spawn(function()
                        if down and (not alive or not enabled or epoch~=inputEpoch) then return end
                        local ok,err=pcall(binding.fn,input,false)
                        if not ok then inputError(err) end
                    end)
                end
                if not down then activeInput=nil end
            end}
        end
    end
    local tool=rod()
    if tool then
        local beginsTool,endsTool=callbacks(tool.Activated,"Tool.Activated"),callbacks(tool.Deactivated,"Tool.Deactivated")
        if #beginsTool>0 and #endsTool>0 then
            modes[#modes+1]={name="FishingRod / funcoes locais",press=function(down)
                local selected=down and beginsTool or endsTool
                local epoch=inputEpoch
                for _,binding in ipairs(selected) do task.spawn(function()
                    if down and (not alive or not enabled or epoch~=inputEpoch) then return end
                    local ok,err=pcall(binding.fn)
                    if not ok then inputError(err) end
                end) end
            end}
        end
    end
    addNativeModes(tool)
    local preferred=env.__NetoFishingInputMethod
    for i,mode in ipairs(modes) do if mode.name==preferred then table.remove(modes,i) table.insert(modes,1,mode) break end end
    modeIndex=1 modeFault=false
    report.capabilities={getconnections=type(getconnections or env.getconnections)=="function",getconstants=debug and type(debug.getconstants)=="function",getupvalues=debug and type(debug.getupvalues)=="function",inputModes=#modes,physicalInput=false,firesignal=type(firesignal or env.firesignal)=="function",realInput=lastRealInput~=nil,nativeMethods=true,actorBridge=type(run_on_actor or env.run_on_actor)=="function",actorInventory=type(getactors or env.getactors)=="function"}
end
setHeld=function(down,force)
    if down and (not alive or not enabled) then return false end
    if held==down and not force then return true end
    local mode=modes[modeIndex]
    if not mode then return false end
    local ok,err=pcall(mode.press,down)
    if not ok then
        if down then pcall(mode.press,false) end
        inputError(err) return false
    end
    held=down report.holdChanges=report.holdChanges+1
    report.inputMode=mode.name
    return true
end
local function release()
    inputEpoch=inputEpoch+1
    if held then setHeld(false,true) end
    held=false activeInput=nil
end
chooseMode=function(reason)
    release()
    record("input","Switch",reason)
    modeIndex=modeIndex+1
    if modeIndex>#modes then
        enabled=false phase="Controle nativo nao confirmou o clique. Copie o resultado."
        if autoButton then autoButton.Text="Auto Fish: OFF" end
        return false
    end
    report.inputMode=modes[modeIndex].name
    modeFault=false inputWorking=false geometry={}
    return true
end
click=function(reason)
    if held then release() end
    if not setHeld(true) then
        if chooseMode("Input recusado") then return click(reason) end
        return false
    end
    report.clicks=report.clicks+1 lastClick=os.clock() clickCount=clickCount+1
    record("input",reason)
    local epoch=inputEpoch
    task.delay(.025,function() if epoch==inputEpoch then release() end end)
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
local title=Instance.new("TextLabel") title.Text="AUTO FISH / FUNCOES LOCAIS" title.Font=Enum.Font.GothamBold title.TextSize=13
 title.TextColor3=Color3.new(1,1,1) title.BackgroundTransparency=1 title.Active=true
 title.Position=UDim2.fromOffset(10,3) title.Size=UDim2.fromOffset(224,30) title.Parent=panel
local minimize=button("-",242,6,26,26) local exit=button("X",276,6,26,26)
autoButton=button("Auto Fish: OFF",10,42,292,36)
local intervalLabel=Instance.new("TextLabel") intervalLabel.Text="Relancar apos captura (s)" intervalLabel.Font=Enum.Font.Gotham intervalLabel.TextSize=12
 intervalLabel.TextColor3=Color3.new(1,1,1) intervalLabel.BackgroundTransparency=1
 intervalLabel.Position=UDim2.fromOffset(10,85) intervalLabel.Size=UDim2.fromOffset(190,30) intervalLabel.Parent=panel
local intervalBox=Instance.new("TextBox") intervalBox.Text="0" intervalBox.ClearTextOnFocus=false intervalBox.Font=Enum.Font.Code intervalBox.TextSize=13
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
-- Diagnostico opcional da queda. Somente leitura; nao altera closures, tweens ou posicoes.
local function dropRelevant(s)
    s=tostring(s):lower()
    for _,word in ipairs({"cast","fish","rod","bait","bobber","float","bite","hook","reel","tween","duration","delay","travel","flight","gravity","velocity","fall","drop","animation","lerp"}) do
        if s:find(word,1,true) then return true end
    end
    return false
end
stopDropDebug=function(shouldCopy)
    local d=dropDebug
    if not d or not d.running then return end
    d.running=false d.seconds=now()-d.started
    if dropConnection then dropConnection:Disconnect() dropConnection=nil end
    dropButton.Text="Debug queda (12 s)"
    report.dropDebug=d
    if shouldCopy and copy then copy() end
end
startDropDebug=function()
    if not alive or (dropDebug and dropDebug.running) then return end
    local d={running=true,started=now(),events={},functions={},parts={},states={},capabilities={
        getconstants=debug and type(debug.getconstants)=="function",
        getupvalues=debug and type(debug.getupvalues)=="function"}}
    dropDebug=d report.dropDebug=d
    dropButton.Text="Parar debug / copiar"
    local physical,stateSources,fnSeen={},{},{}
    local function watch(obj)
        if typeof(obj)~="Instance" or not obj:IsA("BasePart") then return end
        for _,entry in ipairs(physical) do if entry.obj==obj then return end end
        local name=obj.Name:lower()
        local priority=name:find("bobber",1,true) or name:find("bait",1,true) or name:find("float",1,true)
        if #physical>=6 then
            if not priority then return end
            local replace
            for i,entry in ipairs(physical) do if not entry.priority then replace=i break end end
            if not replace then return end
            table.remove(physical,replace) table.remove(d.parts,replace)
        end
        local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root and (obj.Position-root.Position).Magnitude>90 then return end
        local entry={path=obj:GetFullName(),class=obj.ClassName,samples={}}
        physical[#physical+1]={obj=obj,data=entry,priority=priority}
        d.parts[#d.parts+1]=entry
    end
    local function maybeWatch(obj)
        local p=obj local related=false
        for _=1,4 do
            if not p or p==workspace or p==game then break end
            local n=p.Name:lower()
            if n:find("bobber",1,true) or n:find("bait",1,true) or n:find("float",1,true) or n:find("fishingrod",1,true) then related=true break end
            p=p.Parent
        end
        if related then watch(obj) end
    end
    dropConnection=workspace.DescendantAdded:Connect(function(obj) if d.running then maybeWatch(obj) end end)
    local tool=rod()
    if tool then for i,obj in ipairs(tool:GetDescendants()) do if i>80 then break end maybeWatch(obj) end end
    local function stateTable(value)
        local out,n={},0
        for k,v in next,value do
            n=n+1 if n>60 then break end
            if dropRelevant(k) then out[tostring(k)]=safe(v,0,{left=8}) end
        end
        return next(out) and out or nil
    end
    boundFunctions={} observedFunctions={}
    callbacks(UIS.InputBegan,"InputBegan")
    callbacks(UIS.InputEnded,"InputEnded")
    if tool then callbacks(tool.Activated,"Tool.Activated") callbacks(tool.Deactivated,"Tool.Deactivated") end
    local queue={}
    for fn,entry in pairs(boundFunctions) do queue[#queue+1]={fn=fn,origin=entry.origin or "Input",depth=0} end
    for _,entry in ipairs(callbacks(fishing.OnClientEvent,"Fishing.OnClientEvent")) do queue[#queue+1]={fn=entry.fn,origin=entry.origin,depth=0} end
    for fn,entry in pairs(observedFunctions) do
        if not boundFunctions[fn] and #queue<28 then queue[#queue+1]={fn=fn,origin=entry.origin.." / unclassified",depth=0} end
    end
    task.spawn(function()
        local index=1
        while alive and d.running and index<=#queue and #d.functions<12 do
            local item=queue[index] index=index+1
            if not fnSeen[item.fn] then
                fnSeen[item.fn]=true
                local name="" pcall(function() if debug and debug.info then name=debug.info(item.fn,"n") end end)
                local entry={origin=item.origin,name=name,source=sourceOf(item.fn,{}),constants={},upvalues={}}
                local const=constantsOf(item.fn)
                for k,v in pairs(const) do
                    if #entry.constants>=18 then break end
                    if type(v)=="number" or (type(v)=="string" and dropRelevant(v)) then
                        entry.constants[#entry.constants+1]={index=k,value=safe(v,0,{left=2})}
                    end
                end
                local reader=debug and debug.getupvalues
                if type(reader)=="function" then
                    local ok,values=pcall(reader,item.fn)
                    if ok and type(values)=="table" then
                        local inspected=0
                        for key,v in pairs(values) do
                            inspected=inspected+1 if inspected>40 then break end
                            local kind=typeof(v)
                            if type(v)=="function" and item.depth<2 and #queue<32 then
                                queue[#queue+1]={fn=v,origin=tostring(item.origin).."/uv"..tostring(key),depth=item.depth+1}
                            elseif kind=="table" then
                                local snap=stateTable(v)
                                if snap then
                                    if #stateSources<4 then stateSources[#stateSources+1]={value=v,origin=item.origin,key=tostring(key)} end
                                    if #entry.upvalues<8 then entry.upvalues[#entry.upvalues+1]={key=tostring(key),type=kind,value=snap} end
                                end
                            elseif kind=="Instance" then
                                if dropRelevant(v.Name) then watch(v) end
                                if dropRelevant(v.Name) and #entry.upvalues<8 then entry.upvalues[#entry.upvalues+1]={key=tostring(key),value=safe(v,0,{left=3})} end
                            elseif kind=="number" or kind=="Vector3" or (kind=="string" and dropRelevant(v)) then
                                if #entry.upvalues<8 then entry.upvalues[#entry.upvalues+1]={key=tostring(key),type=kind,value=safe(v,0,{left=4})} end
                            end
                        end
                    end
                end
                d.functions[#d.functions+1]=entry
            end
            if index%3==0 then task.wait() end
        end
    end)
    task.spawn(function()
        while alive and d.running and now()-d.started<12 do
            local t=now()-d.started
            for _,entry in ipairs(physical) do
                local obj=entry.obj
                if obj.Parent then
                    local pos=obj.Position
                    local last=entry.last
                    if not last or (pos-last).Magnitude>.03 then
                        local sample={t=t,x=pos.X,y=pos.Y,z=pos.Z}
                        local samples=entry.data.samples
                        if #samples<12 then samples[#samples+1]=sample else samples[12]=sample end
                        entry.last=pos
                    end
                end
            end
            if #d.states<8 and #stateSources>0 then
                local snapshot={t=t,values={}}
                for _,source in ipairs(stateSources) do
                    snapshot.values[#snapshot.values+1]={origin=source.origin,key=source.key,value=stateTable(source.value)}
                end
                if t>=(d.nextState or 0) then d.states[#d.states+1]=snapshot d.nextState=t+1.5 end
            end
            task.wait(.1)
        end
        if alive and d.running then stopDropDebug(true) end
    end)
end

local function resetCycle(reason)
    release()
    cycle=cycle+1 stage="idle" stateAt=os.clock() castAt=nil biteAt=nil hookAt=nil
    autoOwned=false manualAssisted=false clickCount=0 completionSent=false geometry={}
    nextCast=os.clock()+recastDelay phase=reason or "Aguardando"
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
    if not setHeld(desired) then
        if chooseMode("Segurar/soltar recusado") then setHeld(desired,true) end
    end
    if g.zone and math.abs(zx-g.zone)>.001 then
        g.lastMove=os.clock() inputWorking=true
    end
    g.lastMove=g.lastMove or os.clock()
    g.zone,g.fish,g.width=zx,fx,zw
    g.error=error g.inside=math.abs(fx-zx)<=zw*.5
    local _,percent=progress()
    if percent then g.peak=math.max(g.peak or 0,percent) if percent<99 then g.sawBelowFull=true end end
    if not g.inside and os.clock()-g.lastMove>.65 then
        chooseMode("Barra nao respondeu ao segurar/soltar")
        g.lastMove=os.clock()
    end
    report.controller={t=now(),fish=fx,zone=zx,width=zw,held=held,inside=g.inside,peak=g.peak,inputWorking=inputWorking}
end
local function onServer(action,...)
    if not alive then return end
    if not enabled then
        if dropDebug and dropDebug.running then record("server",action,...) end
        return
    end
    local args=table.pack(...)
    record("server",action,...)
    if action=="Cast" then
        if stage=="casting" and autoOwned then
            stage="waitingBite" stateAt=os.clock() clickCount=0
            report.castsAccepted=report.castsAccepted+1
            inputWorking=true phase="Lancamento confirmado; aguardando !"
            if modes[modeIndex] then env.__NetoFishingInputMethod=modes[modeIndex].name end
        end
    elseif action=="Bite" then
        if autoOwned and stage~="idle" then
            biteAt=os.clock() stage="hooking" stateAt=os.clock() clickCount=0
            report.bites=report.bites+1 phase="Fisgando no !"
            local id=cycle
            local defer=task.defer or task.spawn
            defer(function()
                if alive and enabled and cycle==id and stage=="hooking" then click("Hook click") hookAt=os.clock() end
            end)
        end
    elseif action=="Caught" then
        if autoOwned and stage~="idle" then
            if not manualAssisted then
            report.caught=report.caught+1
            local result={t=now(),fish=safe(args[1],0,{left=8}),value2=safe(args[2],0,{left=8}),
                value3=safe(args[3],0,{left=8}),autoFlag=args[4],seconds=castAt and os.clock()-castAt,
                localPeak=geometry.peak,mode=modes[modeIndex] and modes[modeIndex].name}
            report.catches[#report.catches+1]=result
            if #report.catches>8 then table.remove(report.catches,1) end
            else report.manualOrUnownedCaught=report.manualOrUnownedCaught+1 record("input","Manual-assisted catch") end
            resetCycle("Captura confirmada; relancando")
        else report.manualOrUnownedCaught=report.manualOrUnownedCaught+1 end
    elseif action=="Escaped" then
        if autoOwned then report.escaped=report.escaped+1 resetCycle("Peixe escapou; relancando") end
    end
end
connect(fishing.OnClientEvent,onServer)
connect(UIS.InputBegan,function(input,processed)
    if injecting>0 or (injectedInputs[input] and os.clock()-injectedInputs[input]<.2) then return end
    if typeof(input)=="InputObject" then lastRealInput=input end
    if not enabled or processed or not autoOwned then return end
    if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    manualAssisted=true report.manualTouches=report.manualTouches+1
end)
toggle=function(value)
    if not alive then return end
    if value==nil then value=not enabled end
    release()
    enabled=value==true
    resetCycle(enabled and "Chegue perto do lago" or "OFF")
    inputUnavailableAt=nil nextModeScan=0
    if enabled then
        if rod() then
            refreshModes()
            if #modes==0 then phase="Aguardando inicializacao dos controles da vara" end
        else phase="Auto ligado; aproxime-se do lago para equipar a vara" end
    end
    autoButton.Text=enabled and "Auto Fish: ON" or "Auto Fish: OFF"
end
copy=function()
    report.enabled=enabled report.phase=phase report.stage=stage report.seconds=now() report.recastDelay=recastDelay
    report.hasRod=rod()~=nil
    local shown,n=progress()
    report.ui={barVisible=shown,percent=n}
    local export={}
    for k,v in pairs(report) do export[k]=v end
    local payload=Http:JSONEncode(export)
    if #payload>18000 and report.dropDebug then
        local d={} for k,v in pairs(report.dropDebug) do if k~="connection" then d[k]=v end end
        d.states=nil export.dropDebug=d export.trimmed=true export.events=nil
        payload=Http:JSONEncode(export)
        if #payload>18000 then
            local functions={}
            for _,fn in ipairs(d.functions) do functions[#functions+1]={origin=fn.origin,name=fn.name,source=fn.source,constants=fn.constants} end
            d.functions=functions payload=Http:JSONEncode(export)
        end
        if #payload>18000 then
            local partSummary={}
            for _,part in ipairs(d.parts) do
                local samples={}
                for i,sample in ipairs(part.samples) do if i<=3 or i>#part.samples-3 then samples[#samples+1]=sample end end
                partSummary[#partSummary+1]={path=part.path,class=part.class,samples=samples}
            end
            d.parts=partSummary
            local ev={} for i,event in ipairs(d.events) do if i<=5 or i>#d.events-5 then ev[#ev+1]=event end end d.events=ev
            payload=Http:JSONEncode(export)
        end
    end
    if #payload>18000 and export.events then
        local recent={} for i,event in ipairs(export.events) do if i>#export.events-10 then recent[#recent+1]=event end end
        export.events=recent export.trimmed=true payload=Http:JSONEncode(export)
    end
    if #payload>18000 and export.discovery then
        local compact={}
        for origin,data in pairs(export.discovery) do
            local entry={total=data.total,accessible=data.accessible,selected=data.selected,error=data.error,records={}}
            for i,row in ipairs(data.records or {}) do if i<=2 or (row.score and row.score>=60) then entry.records[#entry.records+1]=row end end
            compact[origin]=entry
        end
        export.discovery=compact export.trimmed=true payload=Http:JSONEncode(export)
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
connect(autoButton.Activated,function(input) if typeof(input)=="InputObject" then lastRealInput=input end toggle() end)
connect(copyButton.Activated,copy)
connect(dropButton.Activated,function() if dropDebug and dropDebug.running then stopDropDebug(true) else startDropDebug() end end)
connect(exit.Activated,close)
connect(minimize.Activated,function() mini.Position=panel.Position panel.Visible=false mini.Visible=true end)
connect(mini.Activated,function() panel.Position=mini.Position panel.Visible=true mini.Visible=false end)
connect(intervalBox.FocusLost,function()
    local n=tonumber((intervalBox.Text:gsub(",",".")))
    if n and n==n then recastDelay=math.clamp(n,0,3) end
    intervalBox.Text=tostring(recastDelay)
end)
local lastRod=nil
local function step(dt)
    if not alive or not enabled then return end
    local tool=rod()
    if not tool then
        if autoOwned or held then resetCycle("Aguardando vara perto do lago") end
        lastRod=nil phase="Aguardando vara perto do lago" return
    end
    if tool~=lastRod then
        release() refreshModes() lastRod=tool
        inputUnavailableAt=nil nextModeScan=os.clock()+.5
    end
    if #modes==0 then
        inputUnavailableAt=inputUnavailableAt or os.clock()
        if os.clock()>=nextModeScan then refreshModes() nextModeScan=os.clock()+.5 end
        if #modes==0 then
            phase="Vara equipada; procurando controle nativo"
            if os.clock()-inputUnavailableAt>3 then toggle(false) phase="Controle nativo indisponivel. Copie o resultado." end
            return
        end
    end
    if modeFault then
        if not chooseMode("Falha no callback de entrada") then return end
        if stage=="casting" then stage="idle" autoOwned=false nextCast=os.clock() end
        if stage=="hooking" then stateAt=os.clock() lastClick=-math.huge clickCount=0 end
    end
    local shown,n=progress()
    if shown and n and n<99.95 and stage~="reeling" and stage~="waitingCaught" then
        stage="reeling" stateAt=os.clock() autoOwned=true geometry={} completionSent=false
        if not castAt then castAt=os.clock() end
        phase="Completando a barra automaticamente"
    end
    if stage=="reeling" then
        if shown then
            if n and n>=99.95 and geometry.sawBelowFull then
                geometry.peak=n
                release() stage="waitingCaught" stateAt=os.clock() phase="100%; aguardando captura"
            else controlBar(dt) end
        else
            release()
            stage="waitingCaught" stateAt=os.clock() phase="Aguardando confirmacao do servidor"
        end
    elseif stage=="waitingCaught" then
        release()
        -- O cliente normalmente envia Catch sozinho ao completar. Um reforco so apos 100% real.
        if not completionSent and geometry.sawBelowFull and (geometry.peak or 0)>=99 and os.clock()-stateAt>.2 then
            completionSent=true report.catchRequests=report.catchRequests+1 record("send","Catch after 100%")
            fishing:FireServer("Catch")
        elseif os.clock()-stateAt>3 then
            resetCycle("Sem confirmacao; tentando novo ciclo")
        end
    elseif stage=="idle" and os.clock()>=nextCast then
        cycle=cycle+1 autoOwned=true manualAssisted=false stage="casting" stateAt=os.clock() castAt=os.clock()
        geometry={} completionSent=false clickCount=0 phase="Clicando para lancar"
        click("Cast click")
    elseif stage=="casting" then
        if os.clock()-stateAt>2.3 then
            if chooseMode("Nenhum Cast confirmado apos os cliques") then stage="idle" nextCast=os.clock() autoOwned=false end
        elseif os.clock()-lastClick>.65 and clickCount<3 then click("Cast retry") end
    elseif stage=="waitingBite" then
        phase="Aguardando ! para fisgar"
        if os.clock()-stateAt>10 then resetCycle("Sem mordida; relancando") end
    elseif stage=="hooking" then
        if os.clock()-stateAt>2 then
            if chooseMode("Clique de fisgada sem barra") then stage="idle" autoOwned=false nextCast=os.clock()+.1 end
        elseif os.clock()-lastClick>.16 and clickCount<6 then click("Hook retry") end
    end
end
connect(Run.RenderStepped,function(dt)
    if not enabled then return end
    local ok,err=pcall(step,dt)
    if not ok then report.error=tostring(err) toggle(false) phase="Erro. Copie o resultado." end
    if not enabled then autoButton.Text="Auto Fish: OFF" end
end)
local dragging,dragInput,inputStart,panelStart
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
