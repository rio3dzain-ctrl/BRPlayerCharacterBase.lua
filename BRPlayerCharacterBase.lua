-- SnapLineESP.lua
-- Slim ESP: snap lines + player/bot counter + distance labels

local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local FVector2D = nil
local FVector = nil
local FLinearColor = nil
local FSlateColor = nil

pcall(function()
    SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary")
    WidgetLayoutLibrary = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary")
    FVector2D = import("Vector2D")
    FVector = import("Vector")
    FLinearColor = import("LinearColor")
    FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
end)

local function IsValid(obj)
    if not obj then return false end
    if slua and slua.isValid then return slua.isValid(obj) end
    return true
end

local TempProjVec2D = FVector2D and FVector2D(0, 0) or nil
local ColorWhite  = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or nil
local ColorRed    = FLinearColor and FLinearColor(1.0, 0.15, 0.15, 1.0) or nil
local ColorGreen  = FLinearColor and FLinearColor(0.0, 1.0, 0.05, 1.0) or nil

-- ========== Enemy Counter Image Loader ==========
local ENEMY_COUNTER_PLAYER_URLS = {}
local ENEMY_COUNTER_BOT_URLS = {}
local EnemyCounterTextureCache = {}
local BADGE_WIDTH  = 48
local BADGE_HEIGHT = 22

local function FileExists(path)
    if not path or path == "" then return false end
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function GetPossibleLocalPaths(filename)
    return {
        "/storage/emulated/0/Android/data/com.tencent.ig/files/" .. filename,
        "/storage/emulated/0/Android/data/com.pubg.krmobile/files/" .. filename,
        "/storage/emulated/0/Android/data/com.vng.pubgmobile/files/" .. filename,
        "/storage/emulated/0/Android/data/com.rekoo.pubgm/files/" .. filename,
        "/storage/emulated/0/Android/data/com.tencent.tmgp.pubgmhd/files/" .. filename,
        filename
    }
end

local function LoadBadgeTexture(imgWidget, urls, filename, typeKey, counterData)
    if not imgWidget or not IsValid(imgWidget) then return end

    if EnemyCounterTextureCache[typeKey] and IsValid(EnemyCounterTextureCache[typeKey]) then
        pcall(function()
            imgWidget:SetBrushFromTexture(EnemyCounterTextureCache[typeKey], false)
            imgWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        if counterData then
            if typeKey == "Player" then counterData.PlayerLoaded = true end
            if typeKey == "Bot"    then counterData.BotLoaded    = true end
        end
        return
    end

    local function applyTex(tex)
        if tex and IsValid(tex) and IsValid(imgWidget) then
            EnemyCounterTextureCache[typeKey] = tex
            if counterData then
                if typeKey == "Player" then counterData.PlayerLoaded = true end
                if typeKey == "Bot"    then counterData.BotLoaded    = true end
            end
            pcall(function()
                imgWidget:SetBrushFromTexture(tex, false)
                imgWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            return true
        end
        return false
    end

    for _, localPath in ipairs(GetPossibleLocalPaths(filename)) do
        if FileExists(localPath) then
            local tex = nil
            pcall(function()
                local asset_util = package.loaded["common.asset_util"] or require("common.asset_util")
                if asset_util and asset_util.GetAssetSync then tex = asset_util.GetAssetSync(localPath) end
            end)
            if not tex then
                pcall(function() if CGame and CGame.LoadObject then tex = CGame:LoadObject(localPath) end end)
            end
            if tex and applyTex(tex) then return end
        end
    end

    local function tryDownloadUrl(urlIndex)
        if urlIndex > #urls then return end
        local url = urls[urlIndex]
        local bDownloaded = false

        pcall(function()
            local AsyncTaskDownloadImage = import("AsyncTaskDownloadImage") or import("/Script/UMG.AsyncTaskDownloadImage")
            if AsyncTaskDownloadImage and AsyncTaskDownloadImage.DownloadImage then
                local task = AsyncTaskDownloadImage.DownloadImage(url)
                if task and task.OnSuccess then
                    task.OnSuccess:Add(function(tex)
                        if not bDownloaded and tex then bDownloaded = true; applyTex(tex) end
                    end)
                    if task.OnFail then
                        task.OnFail:Add(function()
                            if not bDownloaded then tryDownloadUrl(urlIndex + 1) end
                        end)
                    end
                end
            end
        end)

        if not bDownloaded then
            pcall(function()
                local mm = _G.ModuleManager or package.loaded["GameLua.GameCore.Module.ModuleManager"]
                if not mm then pcall(function() mm = require("GameLua.GameCore.Module.ModuleManager") end) end
                local imgMgr = nil
                if mm and mm.GetModule and mm.CommonModuleConfig then
                    imgMgr = mm.GetModule(mm.CommonModuleConfig.image_download_mgr)
                end
                if not imgMgr then pcall(function() imgMgr = require("client.slua.logic.image_download.image_download_mgr") end) end
                if imgMgr and imgMgr.DownloadImageByHttpWrapper then
                    imgMgr:DownloadImageByHttpWrapper(url, function(tex)
                        if not bDownloaded and tex then bDownloaded = true; applyTex(tex) end
                    end, function()
                        if not bDownloaded then tryDownloadUrl(urlIndex + 1) end
                    end)
                end
            end)
        end
    end

    tryDownloadUrl(1)
end

-- ========== SnapLineESP Master Table ==========
local SnapLineESP = {
    bActive = true,
    bShowLines = true,
    bShowCounter = true,
    bShowDistance = true,
    ESPCanvas = nil,
    LineWidgets = {},
    DistWidgets = {},

    CounterData = {
        ImgPlayer = nil, SlotPlayer = nil,
        ImgBot    = nil, SlotBot    = nil,
        TxtPlayer = nil, SlotTxtPlayer = nil,
        TxtBot    = nil, SlotTxtBot    = nil,
        LastPlayerCount = -1,
        LastBotCount    = -1,
        PlayerLoaded    = false,
        BotLoaded       = false,
        LastDownloadRetry = 0,
        bCreated = false
    },

    SnapLineThickness = 1.0,
    SnapLineOriginY   = 72,

    _CanvasScaleX = 1.0,
    _CanvasScaleY = 1.0,
    _CanvasOffsetX = 0.0,
    _CanvasOffsetY = 0.0,
    _LastCanvas = nil,
    _LastTransformTime = 0,
    _LastHeavyUpdateTime = 0,
    _LastVisCheckTime = 0,
    _VisCheckCache = {}
}

function SnapLineESP.GetMainCanvas()
    if SnapLineESP.ESPCanvas and IsValid(SnapLineESP.ESPCanvas) then
        return SnapLineESP.ESPCanvas
    end
    local InGameUITools = package.loaded["GameLua.Mod.BaseMod.Common.UI.InGameUITools"]
    if not InGameUITools then
        pcall(function() InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
    end
    if not InGameUITools then return nil end
    local MainUI = InGameUITools.GetMainControlBaseUI and InGameUITools.GetMainControlBaseUI()
    if not IsValid(MainUI) then return nil end

    local ParentCanvas = nil
    if MainUI.CanvasPanel_0 and IsValid(MainUI.CanvasPanel_0) then
        ParentCanvas = MainUI.CanvasPanel_0
    elseif MainUI.CanvasPanel_42 and IsValid(MainUI.CanvasPanel_42) then
        ParentCanvas = MainUI.CanvasPanel_42
    end
    if ParentCanvas then
        SnapLineESP.ESPCanvas = ParentCanvas
        SnapLineESP._LastCanvas = ParentCanvas
    end
    return ParentCanvas
end

function SnapLineESP.UpdateCanvasTransform(PC)
    if not SnapLineESP.ESPCanvas or not IsValid(SnapLineESP.ESPCanvas) then return end
    local success = false
    if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
        local cg = SnapLineESP.ESPCanvas:GetCachedGeometry()
        if cg then
            local pt0 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(0, 0))
            local pt1 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(100, 100))
            if pt0 and pt1 then
                SnapLineESP._CanvasScaleX = (pt1.X - pt0.X) / 100
                SnapLineESP._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                SnapLineESP._CanvasOffsetX = pt0.X
                SnapLineESP._CanvasOffsetY = pt0.Y
                success = true
            end
        end
    end
    if not success and WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
        local scale = WidgetLayoutLibrary.GetViewportScale(PC) or 1.0
        SnapLineESP._CanvasScaleX = 1.0 / scale
        SnapLineESP._CanvasScaleY = 1.0 / scale
        SnapLineESP._CanvasOffsetX = 0
        SnapLineESP._CanvasOffsetY = 0
    end
end

function SnapLineESP.ProjectWorldToCanvasLocal(PC, WorldLoc)
    if not IsValid(PC) or not WorldLoc or not TempProjVec2D then return false, 0, 0 end
    local res = PC:ProjectWorldLocationToScreen(WorldLoc, TempProjVec2D, true)
    if (res == true or res == 1) and (TempProjVec2D.X ~= 0 or TempProjVec2D.Y ~= 0) then
        return true,
            TempProjVec2D.X * SnapLineESP._CanvasScaleX + SnapLineESP._CanvasOffsetX,
            TempProjVec2D.Y * SnapLineESP._CanvasScaleY + SnapLineESP._CanvasOffsetY
    end
    return false, 0, 0
end

-- ========== Snap Line ==========
function SnapLineESP.GetSnapLineStartPos(PC)
    local screenPixelW, screenPixelH = 0, 0
    local scale = 1.0

    pcall(function()
        if PC and PC.GetViewportSize then
            local vs = FVector2D(0, 0)
            PC:GetViewportSize(vs)
            if vs and vs.X and vs.X > 200 then screenPixelW, screenPixelH = vs.X, vs.Y end
        end
    end)
    if screenPixelW <= 200 then
        pcall(function()
            if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportSize then
                local vs = WidgetLayoutLibrary.GetViewportSize(PC)
                if vs and vs.X and vs.X > 200 then screenPixelW, screenPixelH = vs.X, vs.Y end
            end
        end)
    end
    pcall(function()
        if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
            local s = WidgetLayoutLibrary.GetViewportScale(PC)
            if s and type(s) == "number" and s > 0 then scale = s end
        end
    end)
    if screenPixelW <= 200 then screenPixelW, screenPixelH = 1920 * scale, 1080 * scale end

    local fromX = (screenPixelW / 2.0) * SnapLineESP._CanvasScaleX + SnapLineESP._CanvasOffsetX
    local fromY = (SnapLineESP.SnapLineOriginY * scale) * SnapLineESP._CanvasScaleY + SnapLineESP._CanvasOffsetY
    return fromX, fromY
end

function SnapLineESP.CreateSnapLine(ParentCanvas)
    if not IsValid(ParentCanvas) then return nil end
    local border = CGame:NewObjectFromPath("/Script/UMG.Border", ParentCanvas)
    if not IsValid(border) then return nil end
    border:SetBrushColor(ColorWhite)
    border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    border.RenderTransformPivot = FVector2D(0.0, 0.5)
    border:SetRenderTransformPivot(FVector2D(0.0, 0.5))
    local slot = ParentCanvas:AddChildToCanvas(border)
    if slot then
        slot:SetAutoSize(false)
        slot:SetZOrder(990)
    end
    return { Widget = border, Slot = slot, bVisible = true }
end

function SnapLineESP.UpdateSnapLine(KeyStr, toX, toY, fromX, fromY, CustomColor, ParentCanvas)
    local lineData = SnapLineESP.LineWidgets[KeyStr]
    if not lineData or not IsValid(lineData.Widget) then
        lineData = SnapLineESP.CreateSnapLine(ParentCanvas)
        if not lineData or not lineData.Widget or not lineData.Slot then return end
        SnapLineESP.LineWidgets[KeyStr] = lineData
    end
    if not lineData.bVisible then
        lineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        lineData.bVisible = true
    end
    if CustomColor then pcall(function() lineData.Widget:SetBrushColor(CustomColor) end) end

    local dx, dy = toX - fromX, toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    local angle = (math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)) * (180.0 / math.pi)
    local t = SnapLineESP.SnapLineThickness or 1.0

    if not lineData._CachedPosVec then
        lineData._CachedPosVec  = FVector2D(fromX, fromY - t * 0.5)
        lineData._CachedSizeVec = FVector2D(length, t)
    else
        lineData._CachedPosVec.X  = fromX
        lineData._CachedPosVec.Y  = fromY - t * 0.5
        lineData._CachedSizeVec.X = length
        lineData._CachedSizeVec.Y = t
    end
    pcall(function()
        lineData.Slot:SetPosition(lineData._CachedPosVec)
        lineData.Slot:SetSize(lineData._CachedSizeVec)
        lineData.Widget:SetRenderAngle(angle)
    end)
end

function SnapLineESP.HideSnapLine(KeyStr)
    local lineData = SnapLineESP.LineWidgets[KeyStr]
    if lineData and lineData.Widget and IsValid(lineData.Widget) and lineData.bVisible then
        lineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        lineData.bVisible = false
    end
end

-- ========== Distance Label ==========
function SnapLineESP.CreateDistWidget(ParentCanvas)
    if not IsValid(ParentCanvas) then return nil end
    local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", ParentCanvas)
    local slot = nil
    if txt and IsValid(txt) then
        txt:SetText("")
        if txt.Font then
            local font = txt.Font
            font.Size = 10
            if font.OutlineSettings then
                font.OutlineSettings.OutlineSize = 1
                font.OutlineSettings.OutlineColor = FLinearColor(0, 0, 0, 1)
            end
            if txt.SetFont then txt:SetFont(font) else txt.Font = font end
        end
        if txt.SetFontSize then txt:SetFontSize(10) end
        txt:SetJustification(1)
        if txt.SetAutoWrapText then txt:SetAutoWrapText(false) end
        if FSlateColor then txt:SetColorAndOpacity(FSlateColor(ColorWhite)) else txt:SetColorAndOpacity(ColorWhite) end
        txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        slot = ParentCanvas:AddChildToCanvas(txt)
        if slot then
            slot:SetAutoSize(true)
            slot:SetZOrder(1000)
            slot:SetAlignment(FVector2D(0.5, 0.0))
        end
    end
    return { Widget = txt, Slot = slot, _cached = "", bVisible = true }
end

function SnapLineESP.UpdateDistWidget(KeyStr, x, y, distStr, ParentCanvas)
    local dw = SnapLineESP.DistWidgets[KeyStr]
    if not dw or not IsValid(dw.Widget) then
        dw = SnapLineESP.CreateDistWidget(ParentCanvas)
        if not dw then return end
        SnapLineESP.DistWidgets[KeyStr] = dw
    end
    if not dw.bVisible then
        dw.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        dw.bVisible = true
    end
    if dw._cached ~= distStr then
        dw.Widget:SetText(distStr)
        dw._cached = distStr
    end
    if dw.Slot then
        pcall(function() dw.Slot:SetPosition(FVector2D(x, y)) end)
    end
end

function SnapLineESP.HideDistWidget(KeyStr)
    local dw = SnapLineESP.DistWidgets[KeyStr]
    if dw and dw.Widget and IsValid(dw.Widget) and dw.bVisible then
        dw.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        dw.bVisible = false
    end
end

-- ========== Enemy Counter ==========
function SnapLineESP.CreateEnemyCounter(ParentCanvas, centerX, topY)
    local CD = SnapLineESP.CounterData
    if CD.ImgPlayer and IsValid(CD.ImgPlayer) and CD.ImgBot and IsValid(CD.ImgBot) then
        return true
    end

    local imgPlayer = CGame:NewObjectFromPath("/Script/UMG.Image", ParentCanvas)
    local slotPlayer = nil
    if imgPlayer and IsValid(imgPlayer) then
        imgPlayer:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        slotPlayer = ParentCanvas:AddChildToCanvas(imgPlayer)
        if slotPlayer then
            slotPlayer:SetAutoSize(false)
            slotPlayer:SetSize(FVector2D(BADGE_WIDTH, BADGE_HEIGHT))
            slotPlayer:SetPosition(FVector2D(centerX - BADGE_WIDTH, topY))
            slotPlayer:SetZOrder(1005)
        end
    end

    local imgBot = CGame:NewObjectFromPath("/Script/UMG.Image", ParentCanvas)
    local slotBot = nil
    if imgBot and IsValid(imgBot) then
        imgBot:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        slotBot = ParentCanvas:AddChildToCanvas(imgBot)
        if slotBot then
            slotBot:SetAutoSize(false)
            slotBot:SetSize(FVector2D(BADGE_WIDTH, BADGE_HEIGHT))
            slotBot:SetPosition(FVector2D(centerX, topY))
            slotBot:SetZOrder(1005)
        end
    end

    local function MakeCounterText(posX, posY)
        local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", ParentCanvas)
        local sl = nil
        if txt and IsValid(txt) then
            txt:SetText("0")
            if txt.Font then
                local font = txt.Font
                font.Size = 10
                if font.OutlineSettings then
                    font.OutlineSettings.OutlineSize = 0.0
                    font.OutlineSettings.OutlineColor = FLinearColor(0, 0, 0, 0)
                end
                txt.Font = font
            end
            if txt.SetFontSize then txt:SetFontSize(10) end
            txt:SetJustification(1)
            pcall(function() txt:SetAutoWrapText(false) end)
            if FSlateColor then txt:SetColorAndOpacity(FSlateColor(ColorWhite)) else txt:SetColorAndOpacity(ColorWhite) end
            txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            sl = ParentCanvas:AddChildToCanvas(txt)
            if sl then
                sl:SetAutoSize(true)
                sl:SetAlignment(FVector2D(0.5, 0.5))
                sl:SetPosition(FVector2D(posX, posY))
                sl:SetZOrder(1010)
            end
        end
        return txt, sl
    end

    local txtPlayer, slotTxtPlayer = MakeCounterText(centerX - (BADGE_WIDTH * 0.25), topY + (BADGE_HEIGHT * 0.5))
    local txtBot,    slotTxtBot    = MakeCounterText(centerX + (BADGE_WIDTH * 0.65), topY + (BADGE_HEIGHT * 0.5))

    LoadBadgeTexture(imgPlayer, ENEMY_COUNTER_PLAYER_URLS, "ic_danger_enemy.png", "Player", CD)
    LoadBadgeTexture(imgBot,    ENEMY_COUNTER_BOT_URLS,    "ic_clear_boot.png",   "Bot",    CD)

    CD.ImgPlayer, CD.SlotPlayer = imgPlayer, slotPlayer
    CD.ImgBot,    CD.SlotBot    = imgBot,    slotBot
    CD.TxtPlayer, CD.SlotTxtPlayer = txtPlayer, slotTxtPlayer
    CD.TxtBot,    CD.SlotTxtBot    = txtBot,    slotTxtBot
    CD.bCreated = true
    return true
end

function SnapLineESP.UpdateEnemyCounterDisplay(realCount, botCount, ParentCanvas, centerX, topY)
    local CD = SnapLineESP.CounterData
    if not SnapLineESP.bShowCounter then
        local col = UEnums.ESlateVisibility.Collapsed
        if CD.ImgPlayer and IsValid(CD.ImgPlayer) then CD.ImgPlayer:SetWidgetVisibility(col) end
        if CD.ImgBot    and IsValid(CD.ImgBot)    then CD.ImgBot:SetWidgetVisibility(col)    end
        if CD.TxtPlayer and IsValid(CD.TxtPlayer) then CD.TxtPlayer:SetWidgetVisibility(col) end
        if CD.TxtBot    and IsValid(CD.TxtBot)    then CD.TxtBot:SetWidgetVisibility(col)    end
        return
    end
    if not SnapLineESP.CreateEnemyCounter(ParentCanvas, centerX, topY) then return end

    local now = os.clock()
    if (not CD.PlayerLoaded or not CD.BotLoaded) and (now - CD.LastDownloadRetry > 2.0) then
        CD.LastDownloadRetry = now
        if not CD.PlayerLoaded and CD.ImgPlayer then
            LoadBadgeTexture(CD.ImgPlayer, ENEMY_COUNTER_PLAYER_URLS, "ic_danger_enemy.png", "Player", CD)
        end
        if not CD.BotLoaded and CD.ImgBot then
            LoadBadgeTexture(CD.ImgBot, ENEMY_COUNTER_BOT_URLS, "ic_clear_boot.png", "Bot", CD)
        end
    end

    pcall(function()
        if CD.SlotPlayer then
            CD.SlotPlayer:SetSize(FVector2D(BADGE_WIDTH, BADGE_HEIGHT))
            CD.SlotPlayer:SetPosition(FVector2D(centerX - BADGE_WIDTH, topY))
        end
        if CD.SlotBot then
            CD.SlotBot:SetSize(FVector2D(BADGE_WIDTH, BADGE_HEIGHT))
            CD.SlotBot:SetPosition(FVector2D(centerX, topY))
        end
        if CD.SlotTxtPlayer then CD.SlotTxtPlayer:SetPosition(FVector2D(centerX - (BADGE_WIDTH * 0.25), topY + (BADGE_HEIGHT * 0.5))) end
        if CD.SlotTxtBot    then CD.SlotTxtBot:SetPosition(FVector2D(centerX + (BADGE_WIDTH * 0.65), topY + (BADGE_HEIGHT * 0.5))) end

        if CD.LastPlayerCount ~= realCount then
            if CD.TxtPlayer and IsValid(CD.TxtPlayer) then CD.TxtPlayer:SetText(tostring(realCount)) end
            CD.LastPlayerCount = realCount
        end
        if CD.LastBotCount ~= botCount then
            if CD.TxtBot and IsValid(CD.TxtBot) then CD.TxtBot:SetText(tostring(botCount)) end
            CD.LastBotCount = botCount
        end

        local vis = UEnums.ESlateVisibility.SelfHitTestInvisible
        if CD.ImgPlayer and IsValid(CD.ImgPlayer) then CD.ImgPlayer:SetWidgetVisibility(vis) end
        if CD.ImgBot    and IsValid(CD.ImgBot)    then CD.ImgBot:SetWidgetVisibility(vis)    end
        if CD.TxtPlayer and IsValid(CD.TxtPlayer) then CD.TxtPlayer:SetWidgetVisibility(vis) end
        if CD.TxtBot    and IsValid(CD.TxtBot)    then CD.TxtBot:SetWidgetVisibility(vis)    end
    end)
end

-- ========== Main Update ==========
function SnapLineESP.UpdateESP()
    if not SnapLineESP.bActive then return end

    local ParentCanvas = SnapLineESP.GetMainCanvas()
    if not ParentCanvas then return end

    local GameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"] or _G.GameplayData
    if not GameplayData then return end

    local LocalPlayer = GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
    if not IsValid(LocalPlayer) then return end

    local PC = GameplayData.GetPlayerController and GameplayData.GetPlayerController()
    if not IsValid(PC) then return end

    local curTime = os.clock and os.clock() or 0
    if SnapLineESP._LastCanvas ~= ParentCanvas or (curTime - SnapLineESP._LastTransformTime > 1.0) then
        SnapLineESP.UpdateCanvasTransform(PC)
        SnapLineESP._LastCanvas = ParentCanvas
        SnapLineESP._LastTransformTime = curTime
    end

    local bRunHeavyTasks    = (curTime - SnapLineESP._LastHeavyUpdateTime > 0.15)
    local bUpdateVisCheck   = (curTime - SnapLineESP._LastVisCheckTime  > 0.12)
    if bRunHeavyTasks  then SnapLineESP._LastHeavyUpdateTime = curTime end
    if bUpdateVisCheck then SnapLineESP._LastVisCheckTime    = curTime end

    local fromX, fromY = SnapLineESP.GetSnapLineStartPos(PC)

    local TeamID = LocalPlayer.TeamID or (LocalPlayer.GetTeamID and LocalPlayer:GetTeamID()) or 0
    local AllPawns = (Game and Game.GetAllPlayerPawns and Game:GetAllPlayerPawns()) or {}
    local SeenKeys = {}
    local RealPlayerCount, BotCount = 0, 0

    for Key, Pawn in pairs(AllPawns) do
        if IsValid(Pawn) and Pawn ~= LocalPlayer then
            local pawnTeam = Pawn.TeamID or (Pawn.GetTeamID and Pawn:GetTeamID()) or -1
            local isAlive  = (Pawn.Health and Pawn.Health > 0) or (Pawn.IsAlive and Pawn:IsAlive())

            if isAlive and pawnTeam ~= TeamID then
                local KeyStr = tostring(Key)
                SeenKeys[KeyStr] = true

                local ping = (Pawn.PlayerState and Pawn.PlayerState.Ping) or Pawn.Ping
                          or (Pawn.GetPing and Pawn:GetPing()) or -1
                ping = tonumber(ping) or -1
                local isBot = (ping >= 0 and ping <= 3)
                           or Pawn.bIsAI or Pawn.bIsAIBot or Pawn.bIsABot
                           or (Game and Game.IsAI and Game:IsAI(Pawn))

                if isBot then BotCount = BotCount + 1 else RealPlayerCount = RealPlayerCount + 1 end

                local Loc = Pawn.K2_GetActorLocation and Pawn:K2_GetActorLocation()
                if not Loc and Pawn.RootComponent then
                    Loc = Pawn.RootComponent:K2_GetComponentLocation()
                end

                if Loc then
                    local isProne, isCrouch = false, false
                    if Pawn.bIsProning or Pawn.bIsProne or (Pawn.IsProne and Pawn:IsProne())
                        or Pawn.PoseState == 2 or Pawn.PoseState == "Prone" then
                        isProne = true
                    elseif Pawn.bIsCrouched or (Pawn.IsCrouched and Pawn:IsCrouched())
                        or Pawn.PoseState == 1 or Pawn.PoseState == "Crouch" then
                        isCrouch = true
                    end

                    local topOffset    = isProne and 18 or (isCrouch and 50 or 88)
                    local bottomOffset = isProne and -22 or (isCrouch and -68 or -90)

                    local topWorldPos    = FVector(Loc.X, Loc.Y, Loc.Z + topOffset)
                    local bottomWorldPos = FVector(Loc.X, Loc.Y, Loc.Z + bottomOffset)

                    local bTopOk, topX, topY       = SnapLineESP.ProjectWorldToCanvasLocal(PC, topWorldPos)
                    local bBottomOk, bottomX, bottomY = SnapLineESP.ProjectWorldToCanvasLocal(PC, bottomWorldPos)

                    if bTopOk and bBottomOk then
                        local centerX = (topX + bottomX) * 0.5
                        local boxTopY = math.min(topY, bottomY)
                        local boxBottomY = math.max(topY, bottomY)

                        if bUpdateVisCheck or SnapLineESP._VisCheckCache[KeyStr] == nil then
                            SnapLineESP._VisCheckCache[KeyStr] =
                                (PC and PC.LineOfSightTo and PC:LineOfSightTo(Pawn)) or false
                        end
                        local isVisible = SnapLineESP._VisCheckCache[KeyStr]

                        if SnapLineESP.bShowLines then
                            local lineColor = isVisible and ColorGreen or ColorRed
                            SnapLineESP.UpdateSnapLine(KeyStr, centerX, boxTopY, fromX, fromY, lineColor, ParentCanvas)
                        else
                            SnapLineESP.HideSnapLine(KeyStr)
                        end

                        if SnapLineESP.bShowDistance then
                            local distVal = math.floor(LocalPlayer:GetDistanceTo(Pawn) / 100.0)
                            SnapLineESP.UpdateDistWidget(KeyStr, centerX, boxBottomY + 4.0, tostring(distVal) .. "m", ParentCanvas)
                        else
                            SnapLineESP.HideDistWidget(KeyStr)
                        end
                    else
                        SnapLineESP.HideSnapLine(KeyStr)
                        SnapLineESP.HideDistWidget(KeyStr)
                    end
                end
            end
        end
    end

    for KeyStr, _ in pairs(SnapLineESP.LineWidgets) do
        if not SeenKeys[KeyStr] then
            SnapLineESP.HideSnapLine(KeyStr)
            SnapLineESP._VisCheckCache[KeyStr] = nil
        end
    end
    for KeyStr, _ in pairs(SnapLineESP.DistWidgets) do
        if not SeenKeys[KeyStr] then
            SnapLineESP.HideDistWidget(KeyStr)
        end
    end

    local counterTopY = fromY - BADGE_HEIGHT - 2
    if counterTopY < 10 then counterTopY = 48 end
    SnapLineESP.UpdateEnemyCounterDisplay(RealPlayerCount, BotCount, ParentCanvas, fromX, counterTopY)
end

pcall(function()
    local PC = nil
    if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
        PC = slua_GameFrontendHUD:GetPlayerController()
    end
    if IsValid(PC) and PC.AddGameTimer then
        PC:AddGameTimer(0.02, true, SnapLineESP.UpdateESP)
    end
end)

pcall(function()
    local Ticker = package.loaded["common.time_ticker"] or require("common.time_ticker")
    if Ticker and Ticker.AddTimerLoop then
        Ticker.AddTimerLoop(function()
            SnapLineESP.UpdateESP()
            return true
        end, 0.02)
    end
end)

_G.SnapLineESP = SnapLineESP
