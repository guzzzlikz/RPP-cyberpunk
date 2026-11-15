local config=ContextMenuConfig
local resource=GetCurrentResourceName()
local page,ready,active,busy=nil,false,false,false
-- Whether this menu holds the input lease. Kept from the surface's own events, not
-- polled: the WebUI page's focus was moved by other surfaces (a NativeUI HUD or chat
-- taking the keyboard) and the menu closed on its own while ALT was still held.
local focused=false
local lostForeground=0 -- consecutive polls with the game window in the background
local VERSION="1.2.0"
local epoch,selection,lastPickAt,nextCheck=0,nil,-1,0
local visibleActions={}
local armed=true -- A captured key is reported as released by the key-mapping host.
local disabledOwners={}
local now=function() return Open77.time.monotonic()*1000 end
local registry=ContextMenuRegistry.new(function(owner,generation)
    return GetResourceState(owner)=="running" and Open77.resource.generation(owner)==generation
end)
local function owner()
    return GetInvokingResource(),GetInvokingResourceGeneration()
end
exports("register",function(definition) local r,g=owner();return registry.register(r,g,definition) end)
exports("registerMany",function(definitions) local r,g=owner();return registry.registerMany(r,g,definitions) end)
exports("unregister",function(token) local r=owner();return registry.unregister(r,token) end)
exports("unregisterMany",function(tokens) local r=owner();return registry.unregisterMany(r,tokens) end)
exports("update",function(token,patch) local r,g=owner();return registry.update(r,g,token,patch) end)
exports("get",function(token) local r=owner();return registry.describe(r,token) end)
exports("clear",function() local r=owner();if not r then return false,"export_call_required" end;registry.removeOwner(r);return true end)
exports("setEnabled",function(token,value) local r=owner();return registry.setEnabled(r,token,value) end)
exports("list",function() local r=owner();return registry.list(r) end)
exports("isOpen",function() return active end)
exports("isReady",function() return ready and page~=nil end)
exports("getVersion",function() return VERSION end)
exports("getContext",function() return selection end)
exports("getTarget",function() return selection and selection.target end)

-- Helpers are just validated filters over the same owner-scoped registry.
-- A single definition returns one token; an array returns an atomic token array.
local function scoped(definitions,filter)
    if type(definitions)~="table" then return nil,"invalid_actions" end
    local single=definitions.id~=nil
    local input=single and {definitions} or definitions
    local batch={}
    for k,d in pairs(input) do
        if type(d)~="table" then return nil,"invalid_action" end
        local action={};for field,value in pairs(d) do action[field]=value end
        for field,value in pairs(filter) do action[field]=value end
        batch[k]=action
    end
    local r,g=owner();local tokens,err=registry.registerMany(r,g,batch)
    if not tokens then return nil,err end
    return single and tokens[1] or tokens
end
exports("registerPlayers",function(d) return scoped(d,{types={"player"}}) end)
exports("registerVehicles",function(d) return scoped(d,{types={"vehicle"}}) end)
exports("registerNpcs",function(d) return scoped(d,{types={"npc"}}) end)
exports("registerProps",function(d) return scoped(d,{types={"prop"}}) end)
exports("registerDoors",function(d) return scoped(d,{types={"door"}}) end)
exports("registerWorld",function(d) return scoped(d,{types={"world"}}) end)
exports("registerSky",function(d) return scoped(d,{types={"sky"}}) end)
exports("registerSelf",function(definitions) return scoped(definitions,{types={"player"},allowSelf=true,selfOnly=true}) end)
exports("registerModels",function(records,definitions)
    if records==nil then return nil,"invalid_records" end
    return scoped(definitions,{records=records})
end)
exports("registerEntities",function(entities,definitions)
    if entities==nil then return nil,"invalid_entities" end
    return scoped(definitions,{entities=entities})
end)
local function targetingEnabled()
    for r,g in pairs(disabledOwners) do
        if GetResourceState(r)~="running" or Open77.resource.generation(r)~=g then disabledOwners[r]=nil end
    end
    return next(disabledOwners)==nil
end
exports("isTargetingEnabled",targetingEnabled)

local function send(event,payload) if page then page:send(event,payload or {}) end end
local function key() return Open77.input.keyFor("contextmenu.activate") or config.key end
local function alive()
    local state=Open77.character.state()
    return state and state.attached and state.alive and state.health and state.health>0 and state
end
-- RPP: страховка от «замёрзшей камеры». Меню замораживает поворот камеры
-- (freezeRotation). Если сброс не дошёл (меню закрылось посреди открытия,
-- закрытие пришлось на Alt+Tab, когда окно в фоне), поворот оставался
-- замороженным: бегать можно, крутить камеру нельзя. controlsHeld помнит,
-- что управление ещё не возвращено, и цикл ниже возвращает его ещё раз.
local controlsHeld=false
local function diag(text) print("[contextmenu] "..text) end
local inputState -- снимок ввода/камеры, задаётся ниже (у /camfix)
local function releaseControls(why)
    local f1,f2,r1,r2="-","-","-","-"
    if Open77.players and Open77.players.freezeRotation then f1,f2=pcall(Open77.players.freezeRotation,false) end
    if Open77.players and Open77.players.resetControls then r1,r2=pcall(Open77.players.resetControls) end
    -- В фоне игра может не принять сброс: повторим, когда окно вернётся.
    controlsHeld=Open77.input.cursor()==nil
    diag(("release(%s): freezeRotation(false)=%s/%s resetControls=%s/%s foreground=%s keyDown=%s")
        :format(tostring(why),tostring(f1),tostring(f2),tostring(r1),tostring(r2),tostring(not controlsHeld),
            tostring(Open77.input.isDown(Open77.input.keyFor("contextmenu.activate") or config.key))))
end
local function close(reason)
    epoch=epoch+1
    local wasOpen=active
    active,busy,selection,visibleActions=false,false,nil,{}
    focused,lostForeground=false,0
    if page then page:setFocus(false,false);send("context:close");page:hide() end
    releaseControls("close:"..tostring(reason))
    -- RPP: через полсекунды после закрытия — кто держит ввод. menuFocus=true:
    -- невидимое меню держит мышь; captured=true при menuFocus=false: другое окно.
    local closedEpoch=epoch
    SetTimeout(500,function()
        if active or epoch~=closedEpoch then return end
        local c=Open77.input.cursor()
        diag(("after-close(%s): menuFocus=%s captured=%s cursorCaptured=%s keyDown=%s")
            :format(tostring(reason),tostring(page and page:hasFocus()),tostring(Open77.input.isCaptured()),
                tostring(c and c.captured),tostring(Open77.input.isDown(key()))))
        if inputState then diag("after-close state: "..inputState()) end
        if page and page:hasFocus() then page:setFocus(false,false);releaseControls("after_close_focus") end
    end)
    if wasOpen then TriggerEvent("open77:contextmenu:closed",reason or "closed") end
end
exports("close",function() close("provider_closed");return true end)
-- RPP: цель «уехала» (машина качнулась, луч ушёл в стекло), а ALT ещё зажат.
-- Не закрываем меню посреди нажатия — после такого закрытия отпускание ALT
-- приходит без меню и камера зависает. Возвращаемся к выбору цели; меню
-- закроется, когда игрок отпустит ALT.
local function lostTarget()
    if not active then return end
    if not Open77.input.isDown(key()) then close("target_changed");return end
    epoch=epoch+1;selection,busy,visibleActions=nil,false,{}
    send("context:open",{epoch=epoch,key=key(),appearance=config.appearance})
    diag("target lost, back to picking epoch="..tostring(epoch))
end
exports("setTargetingEnabled",function(value)
    local r,g=owner()
    if not r or not g then return false,"export_call_required" end
    if type(value)~="boolean" then return false,"expected_boolean" end
    disabledOwners[r]=not value and g or nil
    if not value and active then close("provider_disabled") end
    return true
end)
local function call(action,export,context,request,budget)
    local observation={};for k,v in pairs(context) do observation[k]=v end
    observation.action={id=action.id,owner=action.owner,token=action.token,data=action.data}
    local promise,reason=Open77.exports.call(action.owner,export,observation)
    if not promise then return nil,reason end
    local deadline=math.min(now()+config.exportTimeoutMs,budget or math.huge)
    while promise:status()=="pending" and now()<deadline and active and request==epoch do Wait(10) end
    if not active or request~=epoch then return nil,"cancelled" end
    if promise:status()=="pending" then return nil,"export_timeout" end
    return promise:await()
end
local function contextAt(x,y)
    local state=alive()
    if not state then return nil,"player_not_ready" end
    local hit,reason=Open77.camera.screenRaycast(x,y,config.rayDistance,{self=true})
    if not hit then return nil,reason end
    hit.screen={x=x,y=y}
    hit.hasSurface=hit.hit==true and hit.hitSource~="self_presentation"
    if not hit.hit then
        hit.target={kind="sky",networked=false};hit.kind="sky"
        hit.playerDistance=nil
        return hit
    end
    if not hit.entityLookupAvailable then return nil,"Выбор объектов недоступен в этой версии клиента." end
    local p,s=hit.position,state.position
    hit.playerDistance=math.sqrt((p.x-s.x)^2+(p.y-s.y)^2+(p.z-s.z)^2)
    hit.target=hit.target or {kind="world",networked=false}
    hit.kind=hit.target.isLocalPlayer and "self" or hit.target.kind
    return hit
end
local function sameTarget(a,b)
    if not a or not b then return false end
    if a.kind~=b.kind then return false end
    if a.kind=="sky" then
        local p,q=a.direction,b.direction
        return p and q and p.x*q.x+p.y*q.y+p.z*q.z>0.9998
    end
    if a.target.engineEntity or b.target.engineEntity then return a.target.engineEntity==b.target.engineEntity end
    local p,q=a.position,b.position
    return (p.x-q.x)^2+(p.y-q.y)^2+(p.z-q.z)^2<0.04
end
local function validRequest(request)
    return active and request==epoch and page and focused and Open77.input.isDown(key())
end
local function pick(payload)
    if not active or busy or now()-lastPickAt<150 or type(payload)~="table" or payload.epoch~=epoch then return end
    lastPickAt=now()
    -- The click's coordinates, from the document (the lease's own pointer, not the
    -- system cursor). They are observations only: the target is resolved by a fresh
    -- native trace.
    local x,y=payload.x,payload.y
    local cursor
    if type(x)~="number" or type(y)~="number" or x~=x or y~=y or x<0 or x>1 or y<0 or y>1 then return end
    cursor={x=x,y=y}
    epoch=epoch+1;local request=epoch
    selection,visibleActions,busy=nil,{},true
    send("context:loading",{epoch=request,x=cursor.x,y=cursor.y})
    local context,reason=contextAt(cursor.x,cursor.y)
    if not context then busy=false;send("context:empty",{epoch=request,message=reason});return end
    local rows={}
    local budget=now()+config.lookupBudgetMs
    for _,action in ipairs(registry.candidates(context)) do
        if not validRequest(request) then return end
        if now()>=budget then break end
        local allowed=not action.canInteract or call(action,action.canInteract,context,request,budget)==true
        if not validRequest(request) then return end
        if allowed and registry.get(action.token)==action and registry.matches(action,context) then
            rows[#rows+1]={token=action.token,label=action.label,description=action.description,
                group=action.group,icon=action.icon,danger=action.danger}
            visibleActions[action.token]=true
            if #rows>=config.maxActions then break end
        end
    end
    if not validRequest(request) then return end
    selection,busy=context,false
    send("context:menu",{epoch=request,x=cursor.x,y=cursor.y,target=context.target, distance=context.playerDistance,actions=rows})
end
local function selectAction(payload)
    if not active or busy or type(payload)~="table" or payload.epoch~=epoch or not visibleActions[payload.token] then return end
    local action=registry.get(payload.token)
    if not action or not selection then close("action_unavailable");return end
    local request=epoch
    busy=true;send("context:busy",{epoch=request,token=payload.token})
    local current=contextAt(selection.screen.x,selection.screen.y)
    if not sameTarget(selection,current) or not registry.matches(action,current) then lostTarget();return end
    local allowed=not action.canInteract or call(action,action.canInteract,current,request)==true
    if not validRequest(request) then return end
    -- Revalidate after a yielding predicate, not just before it.
    local fresh=contextAt(selection.screen.x,selection.screen.y)
    if not allowed or registry.get(action.token)~=action or not sameTarget(current,fresh) or not registry.matches(action,fresh) then
        busy=false;send("context:error",{epoch=request,message="Это действие больше недоступно."});return
    end
    -- Resolve the callback from the registered owner, never from the UI payload.
    fresh.action={id=action.id,owner=action.owner,token=action.token,data=action.data}
    local promise,reason=Open77.exports.call(action.owner,action.onSelect,fresh)
    if not promise then busy=false;send("context:error",{epoch=request,message=tostring(reason)});return end
    -- Release input before the provider opens another UI or starts an interaction.
    close("selected")
    TriggerEvent("open77:contextmenu:selected",fresh)
    local result,err=promise:await()
    if result==false or err then print("[contextmenu] action failed: "..tostring(err or "provider_rejected")) end
end
local function open()
    if not armed or not Open77.input.isDown(key()) then return end
    armed=false -- Never reopen after selection/Escape until a real key release.
    if active or not ready or not page or not targetingEnabled() or Open77.input.isCaptured() or not alive() then return end
    local cursor=Open77.input.cursor()
    if not cursor or cursor.captured then return end
    epoch=epoch+1;active=true;selection=nil;visibleActions={}
    send("context:open",{epoch=epoch,key=key(),appearance=config.appearance})
    page:show()
    if not page:setFocus(true,true) then close("focus_refused");return end
    focused,lostForeground=true,0
    local opened=epoch
    controlsHeld=true
    if not Open77.players.allowAim(false) or not Open77.players.allowShoot(false) or
       not Open77.players.allowInteraction(false) or not Open77.players.freezeRotation(true) then
        close("controls_unavailable");return
    end
    -- RPP: меню успело закрыться, пока мы забирали управление (быстрый ALT+ЛКМ,
    -- потеря фокуса): вернуть управление, иначе камера останется замороженной.
    if not active or epoch~=opened then releaseControls("closed_while_opening");return end
    diag("opened epoch="..tostring(epoch))
    TriggerEvent("open77:contextmenu:opened")
end
AddEventHandler("open77:pauseKey",function() if active then close("pause") end end)
-- RPP: ручной выход, если камера всё же замёрзла (например, Windows «съела»
-- отпускание ALT при Shift+Alt — это системное переключение раскладки).
-- RPP: снимок «кто держит мышь» на момент /camfix — для разбора зависания.
local function snap(label,fn,...)
    local ok,a,b=pcall(fn,...)
    if not ok then return label.."=err" end
    local function s(v) if type(v)=="table" then local ok2,j=pcall(json.encode,v);return ok2 and j or "table" end;return tostring(v) end
    return label.."="..s(a)..(b~=nil and ("/"..s(b)) or "")
end
inputState=function()
    local I,P,C=Open77.input or {},Open77.perspective or {},Open77.camera or {}
    local parts={}
    local function add(label,fn,...) if type(fn)=="function" then parts[#parts+1]=snap(label,fn,...) end end
    add("captured",I.isCaptured);add("cursor",I.cursor)
    for _,k in ipairs({"ALT","LSHIFT","LCONTROL","MOUSE_LEFT","MOUSE_RIGHT","TAB"}) do add("down."..k,I.isDown,k) end
    for _,a in ipairs({"CameraMouseX","CameraMouseY","Camera","Look","Movement","RadialWheels","Attack"}) do add("blocked."..a,I.isActionBlocked,a) end
    add("mouseX",I.axis,"mouseX");add("mouseY",I.axis,"mouseY")
    add("perspective",P.state);add("cameras",C.cameras)
    return table.concat(parts," ")
end
RegisterCommand("camfix",function()
    diag("camfix: active="..tostring(active).." controlsHeld="..tostring(controlsHeld)
        .." menuFocus="..tostring(page and page:hasFocus()))
    diag("camfix state: "..inputState())
    if active then close("camfix") else
        if page then page:setFocus(false,false) end
        releaseControls("camfix")
    end
    armed=true
    -- RPP: при зависании клики проходят, а движение мыши — нет: игра осталась
    -- в «курсорном» режиме мыши. Берём курсор на миг и отдаём — Open77 при
    -- отдаче возвращает игре относительную мышь. Ждём, пока закроется чат,
    -- из которого набрали команду.
    CreateThread(function()
        Wait(400)
        if active or not page then return end
        page:show()
        local took=page:setFocus(true,true)
        Wait(150)
        page:setFocus(false,false)
        page:hide()
        releaseControls("camfix_cursor_cycle")
        diag("camfix: cursor cycle took="..tostring(took).." state: "..inputState())
    end)
    -- RPP: по логам ввод свободен, а камера от 3-го лица (open77_rig) не берёт
    -- мышь. Пересоздаём её: вид от 1-го лица и обратно.
    local P=Open77.perspective
    if P and type(P.set)=="function" then
        local mode
        if type(P.state)=="function" then local ok,s=pcall(P.state);mode=ok and type(s)=="table" and s.mode or nil end
        if not mode and type(P.get)=="function" then local ok,g=pcall(P.get);mode=ok and (type(g)=="table" and g.mode or g) or nil end
        if mode=="tps" or mode=="third" then
            CreateThread(function()
                local function set(a,b) local ok,r=pcall(P.set,a);if ok and r~=false then return true end;ok,r=pcall(P.set,b);return ok and r~=false end
                Wait(800) -- после цикла с курсором
                local first=set("fpp","first")
                Wait(300)
                local third=set("tps","third")
                diag(("camfix: perspective reseat first=%s third=%s"):format(tostring(first),tostring(third)))
            end)
        end
    end
    pcall(Open77.exports.call,"open77_chat","addMessage",{type="system",author="КАМЕРА",
        text="Управление камерой возвращено.",color={252,238,10}})
end,false)
AddEventHandler("onClientResourceStop",function(name)
    if name==resource then
        close("resource_stopped")
        if Open77.input.setNativeActionBlocked then Open77.input.setNativeActionBlocked("WeaponWheel",false) end
        page,ready=nil,false
    else registry.removeOwner(name);disabledOwners[name]=nil end
end)
AddEventHandler("onClientResourceStart",function(name)
    if name~=resource then return end
    if type(Open77.camera.screenRaycast)~="function" or type(Open77.input.cursor)~="function" then
        print("[contextmenu] Requires a client with the screen-picking APIs; package disabled.");return
    end
    local reason
    -- A NativeUI document (client/ui.lua, ui/contextmenu.rml) drawn by the game's
    -- renderer, speaking the page API the WebUI page used.
    page,reason=ContextMenuUi.create(config)
    if not page then print("[contextmenu] Requires a client with NativeUI: "..tostring(reason));return end
    if config.blockNativeWeaponWheel then
        local blocked,err=false,"native_action_unavailable"
        if Open77.input.setNativeActionBlocked then blocked,err=Open77.input.setNativeActionBlocked("WeaponWheel",true) end
        if not blocked then
            print("[contextmenu] Cannot reserve the native weapon wheel: "..tostring(err))
            page:destroy();page=nil;return
        end
    end
    page:on("context:ready",function() ready=true;page:hide() end)
    page:on("context:pick",pick)
    page:on("context:select",selectAction)
    page:on("context:cancel",function(payload) if active and payload and payload.epoch==epoch then close("cancelled") end end)
    -- The lease went to someone else (a WebUI page opened, the document reloaded) or
    -- could not be taken: nothing else closes the menu behind the player's back.
    page:on("context:blur",function(reason)
        if active then focused=false;close("focus_lost:"..tostring(reason or "blur")) end
    end)
    RegisterKeyMapping("contextmenu.activate","Context menu (hold)",config.key,open)
    CreateThread(function()
        while page do
            if not Open77.input.isDown(key()) then armed=true end
            if active then
                -- A background window for one poll is a tooltip or an overlay blinking:
                -- only a lasting one (about 75 ms) closes the menu.
                lostForeground=Open77.input.cursor() and 0 or lostForeground+1
                if not Open77.input.isDown(key()) or not alive() or lostForeground>=3 then close("input_released")
                elseif selection and not busy and now()>=nextCheck then
                    nextCheck=now()+config.revalidateMs
                    local current=contextAt(selection.screen.x,selection.screen.y)
                    if not sameTarget(selection,current) then lostTarget() end
                end
            else
                -- RPP: меню закрыто, а управление не вернулось (окно было в фоне) — вернуть.
                if controlsHeld and Open77.input.cursor() then releaseControls("foreground_back") end
                -- RPP: при Alt+Tab / Shift+Alt NativeUI запоминает фокус меню
                -- («restored when it is in front again») и возвращает его, когда
                -- окно снова активно, хотя меню уже закрыто. Невидимое меню
                -- держит мышь: камера не крутится, а бегать можно. Снимаем.
                if page and Open77.input.cursor() and page:hasFocus() then
                    page:setFocus(false,false)
                    releaseControls("stale_focus")
                end
                registry.sweep()
            end
            Wait(active and config.activePollMs or config.idlePollMs)
        end
    end)
end)
