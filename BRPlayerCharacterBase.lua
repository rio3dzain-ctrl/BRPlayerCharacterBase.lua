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
    if slua and slua.isValid then
        return slua.isValid(obj)
    end
    return true
end

-- safe wrappers: widgets can be nil
local function SafeSetText(w, s)
    if w and IsValid(w) then pcall(function() w:SetText(s) end) end
end
local function SafeSetColor(w, c)
    if w and IsValid(w) and c then pcall(function() w:SetColorAndOpacity(c) end) end
end
local function SafeSetPos(slot, x, y)
    if slot and IsValid(slot) and FVector2D then
        pcall(function() slot:SetPosition(FVector2D(x, y)) end)
    end
end
local function SafeSetSize(slot, x, y)
    if slot and IsValid(slot) and FVector2D then
        pcall(function() slot:SetSize(FVector2D(x, y)) end)
    end
end
local function SafeSetVis(w, v)
    if w and IsValid(w) then pcall(function() w:SetWidgetVisibility(v) end) end
end

local TempProjVec2D = FVector2D and FVector2D(0, 0) or nil
local ColorWhite = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or nil
local ColorRed = FLinearColor and FLinearColor(1.0, 0.15, 0.15, 1.0) or nil
local ColorGreen = FLinearColor and FLinearColor(0.0, 1.0, 0.05, 1.0) or nil
local ColorYellow = FLinearColor and FLinearColor(1.0, 0.95, 0.0, 1.0) or nil
local ColorBlue = FLinearColor and FLinearColor(0.18, 0.62, 1.0, 1.0) or nil

local SlateColorRed = (FSlateColor and ColorRed) and FSlateColor(ColorRed) or ColorRed
local SlateColorGreen = (FSlateColor and ColorGreen) and FSlateColor(ColorGreen) or ColorGreen

-- ========== Enemy Counter Image Loader ==========
local ENEMY_COUNTER_PLAYER_URLS = {
}
local ENEMY_COUNTER_BOT_URLS = {
}
local EnemyCounterTextureCache = {}
local BADGE_WIDTH = 48
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
            if typeKey == "Bot" then counterData.BotLoaded = true end
        end
        return
    end

    local function applyTex(tex)
        if tex and IsValid(tex) and IsValid(imgWidget) then
            EnemyCounterTextureCache[typeKey] = tex
            if counterData then
                if typeKey == "Player" then counterData.PlayerLoaded = true end
                if typeKey == "Bot" then counterData.BotLoaded = true end
            end
            pcall(function()
                imgWidget:SetBrushFromTexture(tex, false)
                imgWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            return true
        end
        return false
    end

    local localPaths = GetPossibleLocalPaths(filename)
    for _, localPath in ipairs(localPaths) do
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
                        if not bDownloaded and tex then
                            bDownloaded = true
                            applyTex(tex)
                        end
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

        if not bDownloaded then
            pcall(function()
                local util = package.loaded["client.slua_ui_framework.util"]
                if not util then pcall(function() util = require("client.slua_ui_framework.util") end) end
                if util and util.SetTexture then
                    util.SetTexture(imgWidget, url, {
                        sync = false,
                        onDownloadSuccess = function(tex)
                            if not bDownloaded and tex then bDownloaded = true; applyTex(tex) end
                        end
                    })
                end
            end)
        end
    end

    tryDownloadUrl(1)
end

-- ========== BoxESP Master Table ==========
local BoxESP = {
    bActive = true,
    bShowLines = true,
    bShowCounter = true,
    ESPCanvas = nil,
    BoxWidgets = {},
    LineWidgets = {},

    CounterData = {
        ImgPlayer = nil,
        SlotPlayer = nil,
        ImgBot = nil,
        SlotBot = nil,
        TxtPlayer = nil,
        SlotTxtPlayer = nil,
        TxtBot = nil,
        SlotTxtBot = nil,
        LastPlayerCount = -1,
        LastBotCount = -1,
        PlayerLoaded = false,
        BotLoaded = false,
        LastDownloadRetry = 0,
        bCreated = false
    },

    HealthColor = { R = 0.0, G = 1.0, B = 0.0, A = 1.0 },
    HealthBgColor = { R = 0.0, G = 0.0, B = 0.0, A = 0.85 },
    HealthBarWidth = 2.0,
    CornerColor = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 },
    CornerThickness = 1.0,
    CornerLengthRatio = 0.28,
    SnapLineThickness = 1.0,
    SnapLineOriginY = 72,

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

function BoxESP.GetMainCanvas()
    if BoxESP.ESPCanvas and IsValid(BoxESP.ESPCanvas) then
        return BoxESP.ESPCanvas
    end

    local InGameUITools = package.loaded["GameLua.Mod.BaseMod.Common.UI.InGameUITools"]
    if not InGameUITools then
        pcall(function() InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
    end
    if not InGameUITools then return nil end

    local MainUI = nil
    if InGameUITools.GetMainControlBaseUI then
        MainUI = InGameUITools.GetMainControlBaseUI()
    end
    if not IsValid(MainUI) then return nil end

    local ParentCanvas = nil
    if MainUI.CanvasPanel_0 and IsValid(MainUI.CanvasPanel_0) then
        ParentCanvas = MainUI.CanvasPanel_0
    elseif MainUI.CanvasPanel_42 and IsValid(MainUI.CanvasPanel_42) then
        ParentCanvas = MainUI.CanvasPanel_42
    end

    if ParentCanvas then
        BoxESP.ESPCanvas = ParentCanvas
        BoxESP._LastCanvas = ParentCanvas
    end
    return ParentCanvas
end

function BoxESP.CreateESPWidget(ParentCanvas)
    if not FLinearColor or not FVector2D then return nil end

    local CornerContainer = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas)
    if not IsValid(CornerContainer) then return nil end

    local CornerMainSlot = ParentCanvas:AddChildToCanvas(CornerContainer)
    if not CornerMainSlot then return nil end

    CornerMainSlot:SetAutoSize(false)
    CornerMainSlot:SetZOrder(995)
    CornerMainSlot:SetAlignment(FVector2D(0.5, 0.5))

    local whiteColor = FLinearColor(
        BoxESP.CornerColor.R,
        BoxESP.CornerColor.G,
        BoxESP.CornerColor.B,
        BoxESP.CornerColor.A
    )

    local function CreateBorderLine()
        local border = CGame:NewObjectFromPath("/Script/UMG.Border", CornerContainer)
        if border and IsValid(border) then
            border:SetBrushColor(whiteColor)
            border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local slot = CornerContainer:AddChildToCanvas(border)
            if slot then slot:SetAutoSize(false) end
            return { widget = border, slot = slot }
        end
        return nil
    end

    local CornerLines = {
        TopLeft_H = CreateBorderLine(),
        TopLeft_V = CreateBorderLine(),
        TopRight_H = CreateBorderLine(),
        TopRight_V = CreateBorderLine(),
        BottomLeft_H = CreateBorderLine(),
        BottomLeft_V = CreateBorderLine(),
        BottomRight_H = CreateBorderLine(),
        BottomRight_V = CreateBorderLine()
    }

    local BgImage = CGame:NewObjectFromPath("/Script/UMG.Image", ParentCanvas)
    if not IsValid(BgImage) then return nil end
    BgImage:SetColorAndOpacity(FLinearColor(BoxESP.HealthBgColor.R, BoxESP.HealthBgColor.G, BoxESP.HealthBgColor.B, BoxESP.HealthBgColor.A))
    BgImage:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)

    local BgSlot = ParentCanvas:AddChildToCanvas(BgImage)
    if not BgSlot then return nil end
    BgSlot:SetAutoSize(false)
    BgSlot:SetZOrder(998)
    BgSlot:SetAlignment(FVector2D(0.5, 1.0))

    local HealthImage = CGame:NewObjectFromPath("/Script/UMG.Image", ParentCanvas)
    if not IsValid(HealthImage) then return nil end
    HealthImage:SetColorAndOpacity(FLinearColor(BoxESP.HealthColor.R, BoxESP.HealthColor.G, BoxESP.HealthColor.B, BoxESP.HealthColor.A))
    HealthImage:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)

    local HealthSlot = ParentCanvas:AddChildToCanvas(HealthImage)
    if not HealthSlot then return nil end
    HealthSlot:SetAutoSize(false)
    HealthSlot:SetZOrder(999)
    HealthSlot:SetAlignment(FVector2D(0.5, 1.0))

    local function CreateStyledTextBlock(defaultColor, fontSize, alignment)
        local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", ParentCanvas)
        local slot = nil
        if txt and IsValid(txt) then
            txt:SetText("")
            local intSize = math.floor(fontSize or 10)
            if txt.Font then
                local newFont = txt.Font
                newFont.Size = intSize
                if newFont.OutlineSettings then
                    newFont.OutlineSettings.OutlineSize = 1
                    newFont.OutlineSettings.OutlineColor = FLinearColor(0.0, 0.0, 0.0, 1.0)
                end
                if txt.SetFont then txt:SetFont(newFont) else txt.Font = newFont end
            end

            if txt.SetFontSize then txt:SetFontSize(intSize) end
            txt:SetJustification(1)
            if txt.SetHorizontalAlignment then txt:SetHorizontalAlignment(1) end
            if txt.SetVerticalAlignment then txt:SetVerticalAlignment(1) end
            if txt.SetAutoWrapText then txt:SetAutoWrapText(false) end

            if FSlateColor then
                txt:SetColorAndOpacity(FSlateColor(defaultColor))
            else
                txt:SetColorAndOpacity(defaultColor)
            end

            if txt.SetShadowOffset then txt:SetShadowOffset(FVector2D(0.0, 0.0)) end
            if txt.SetShadowColorAndOpacity then txt:SetShadowColorAndOpacity(FLinearColor(0.0, 0.0, 0.0, 0.0)) end
            txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)

            slot = ParentCanvas:AddChildToCanvas(txt)
            if slot then
                slot:SetAutoSize(true)
                slot:SetZOrder(1000)
                slot:SetAlignment(alignment or FVector2D(0.5, 0.0))
            end
        end
        return txt, slot
    end

    local WeaponWidget, WeaponSlot = CreateStyledTextBlock(ColorYellow, 10, FVector2D(0.5, 1.0))
    local NameWidget, NameSlot = CreateStyledTextBlock(ColorBlue, 10, FVector2D(0.5, 0.0))
    local DistWidget, DistSlot = CreateStyledTextBlock(ColorWhite, 10, FVector2D(0.5, 0.0))
    local StateWidget, StateSlot = CreateStyledTextBlock(ColorGreen, 10, FVector2D(0.5, 0.0))

    local FlagImage = CGame:NewObjectFromPath("/Script/UMG.Image", ParentCanvas)
    local FlagSlot = nil
    if FlagImage and IsValid(FlagImage) then
        FlagImage:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        FlagSlot = ParentCanvas:AddChildToCanvas(FlagImage)
        if FlagSlot then
            FlagSlot:SetAutoSize(false)
            FlagSlot:SetSize(FVector2D(14, 16))
            FlagSlot:SetZOrder(1000)
            FlagSlot:SetAlignment(FVector2D(0.5, 1.0))
        end
    end

    return {
        CornerContainer = CornerContainer,
        CornerSlot = CornerMainSlot,
        Corners = CornerLines,
        BgWidget = BgImage,
        BgSlot = BgSlot,
        HealthWidget = HealthImage,
        HealthSlot = HealthSlot,
        WeaponWidget = WeaponWidget,
        WeaponSlot = WeaponSlot,
        FlagWidget = FlagImage,
        FlagSlot = FlagSlot,
        NameWidget = NameWidget,
        NameSlot = NameSlot,
        DistWidget = DistWidget,
        DistSlot = DistSlot,
        StateWidget = StateWidget,
        StateSlot = StateSlot,
        _cachedWeapon = "",
        _cachedNation = nil,
        _cachedName = "",
        _cachedDist = "",
        _cachedState = "",
        _cachedIsCover = false,
        _cachedIsKnocked = false,
        _lastScanTime = 0,
        lastW = 0,
        lastH = 0,
        bVisible = true
    }
end

function BoxESP.UpdateCornerDimensions(boxData, width, height)
    if not boxData or not boxData.CornerSlot then return end
    if boxData.lastW and boxData.lastH then
        if math.abs(width - boxData.lastW) < 1.5 and math.abs(height - boxData.lastH) < 1.5 then
            return
        end
    end
    boxData.lastW = width
    boxData.lastH = height

    local t = BoxESP.CornerThickness
    local cLen = math.max(7, math.min(width, height) * BoxESP.CornerLengthRatio)
    local C = boxData.Corners or {}

    SafeSetSize(boxData.CornerSlot, width, height)

    if C.TopLeft_H and C.TopLeft_H.slot then
        SafeSetPos(C.TopLeft_H.slot, 0, 0)
        SafeSetSize(C.TopLeft_H.slot, cLen, t)
    end
    if C.TopLeft_V and C.TopLeft_V.slot then
        SafeSetPos(C.TopLeft_V.slot, 0, 0)
        SafeSetSize(C.TopLeft_V.slot, t, cLen)
    end

    if C.TopRight_H and C.TopRight_H.slot then
        SafeSetPos(C.TopRight_H.slot, width - cLen, 0)
        SafeSetSize(C.TopRight_H.slot, cLen, t)
    end
    if C.TopRight_V and C.TopRight_V.slot then
        SafeSetPos(C.TopRight_V.slot, width - t, 0)
        SafeSetSize(C.TopRight_V.slot, t, cLen)
    end

    if C.BottomLeft_H and C.BottomLeft_H.slot then
        SafeSetPos(C.BottomLeft_H.slot, 0, height - t)
        SafeSetSize(C.BottomLeft_H.slot, cLen, t)
    end
    if C.BottomLeft_V and C.BottomLeft_V.slot then
        SafeSetPos(C.BottomLeft_V.slot, 0, height - cLen)
        SafeSetSize(C.BottomLeft_V.slot, t, cLen)
    end

    if C.BottomRight_H and C.BottomRight_H.slot then
        SafeSetPos(C.BottomRight_H.slot, width - cLen, height - t)
        SafeSetSize(C.BottomRight_H.slot, cLen, t)
    end
    if C.BottomRight_V and C.BottomRight_V.slot then
        SafeSetPos(C.BottomRight_V.slot, width - t, height - cLen)
        SafeSetSize(C.BottomRight_V.slot, t, cLen)
    end
end

function BoxESP.UpdateCanvasTransform(PC)
    if not BoxESP.ESPCanvas or not IsValid(BoxESP.ESPCanvas) then return end
    if not FVector2D then return end

    local success = false
    pcall(function()
        if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
            local cg = BoxESP.ESPCanvas:GetCachedGeometry()
            if cg then
                local pt0 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(0, 0))
                local pt1 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(100, 100))
                if pt0 and pt1 then
                    BoxESP._CanvasScaleX = (pt1.X - pt0.X) / 100
                    BoxESP._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                    BoxESP._CanvasOffsetX = pt0.X
                    BoxESP._CanvasOffsetY = pt0.Y
                    success = true
                end
            end
        end
    end)

    if not success and WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
        local scale = 1.0
        pcall(function() scale = WidgetLayoutLibrary.GetViewportScale(PC) or 1.0 end)
        BoxESP._CanvasScaleX = 1.0 / scale
        BoxESP._CanvasScaleY = 1.0 / scale
        BoxESP._CanvasOffsetX = 0
        BoxESP._CanvasOffsetY = 0
    end
end

function BoxESP.ProjectWorldToCanvasLocal(PC, WorldLoc)
    if not IsValid(PC) or not WorldLoc or not TempProjVec2D then return false, 0, 0 end

    local res = PC:ProjectWorldLocationToScreen(WorldLoc, TempProjVec2D, true)
    if (res == true or res == 1) and (TempProjVec2D.X ~= 0 or TempProjVec2D.Y ~= 0) then
        local finalX = TempProjVec2D.X * BoxESP._CanvasScaleX + BoxESP._CanvasOffsetX
        local finalY = TempProjVec2D.Y * BoxESP._CanvasScaleY + BoxESP._CanvasOffsetY
        return true, finalX, finalY
    end
    return false, 0, 0
end

-- ========== Snap Line Functionality ==========
function BoxESP.GetSnapLineStartPos(PC, ParentCanvas)
    local screenPixelW, screenPixelH = 0, 0
    local scale = 1.0

    pcall(function()
        if PC and PC.GetViewportSize and FVector2D then
            local vs = FVector2D(0, 0)
            PC:GetViewportSize(vs)
            if vs and vs.X and vs.X > 200 then
                screenPixelW = vs.X
                screenPixelH = vs.Y
            end
        end
    end)

    if screenPixelW <= 200 then
        pcall(function()
            if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportSize then
                local vs = WidgetLayoutLibrary.GetViewportSize(PC)
                if vs and vs.X and vs.X > 200 then
                    screenPixelW = vs.X
                    screenPixelH = vs.Y
                end
            end
        end)
    end

    pcall(function()
        if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
            local s = WidgetLayoutLibrary.GetViewportScale(PC)
            if s and type(s) == "number" and s > 0 then scale = s end
        end
    end)

    if screenPixelW <= 200 then
        screenPixelW = 1920 * scale
        screenPixelH = 1080 * scale
    end

    local centerPixelX = screenPixelW / 2.0
    local centerPixelY = BoxESP.SnapLineOriginY * scale

    local fromX = centerPixelX * BoxESP._CanvasScaleX + BoxESP._CanvasOffsetX
    local fromY = centerPixelY * BoxESP._CanvasScaleY + BoxESP._CanvasOffsetY
    return fromX, fromY
end

function BoxESP.CreateSnapLine(ParentCanvas)
    if not IsValid(ParentCanvas) or not FVector2D then return nil end
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

function BoxESP.UpdateSnapLine(KeyStr, toX, toY, fromX, fromY, CustomColor, ParentCanvas)
    local lineData = BoxESP.LineWidgets[KeyStr]
    if not lineData or not IsValid(lineData.Widget) then
        lineData = BoxESP.CreateSnapLine(ParentCanvas)
        if not lineData or not lineData.Widget or not lineData.Slot then return end
        BoxESP.LineWidgets[KeyStr] = lineData
    end

    if not lineData.bVisible then
        SafeSetVis(lineData.Widget, UEnums.ESlateVisibility.SelfHitTestInvisible)
        lineData.bVisible = true
    end

    if CustomColor then
        pcall(function() lineData.Widget:SetBrushColor(CustomColor) end)
    end

    local dx = toX - fromX
    local dy = toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    local angle = (math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)) * (180.0 / math.pi)
    local t = BoxESP.SnapLineThickness or 1.0

    if not lineData._CachedPosVec and FVector2D then
        lineData._CachedPosVec = FVector2D(fromX, fromY - t * 0.5)
        lineData._CachedSizeVec = FVector2D(length, t)
    elseif lineData._CachedPosVec then
        lineData._CachedPosVec.X = fromX
        lineData._CachedPosVec.Y = fromY - t * 0.5
        lineData._CachedSizeVec.X = length
        lineData._CachedSizeVec.Y = t
    end

    pcall(function()
        if lineData._CachedPosVec then
            lineData.Slot:SetPosition(lineData._CachedPosVec)
            lineData.Slot:SetSize(lineData._CachedSizeVec)
        end
        lineData.Widget:SetRenderAngle(angle)
    end)
end

function BoxESP.HideSnapLine(KeyStr)
    local lineData = BoxESP.LineWidgets[KeyStr]
    if lineData and lineData.Widget and IsValid(lineData.Widget) and lineData.bVisible then
        lineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        lineData.bVisible = false
    end
end

-- ========== Enemy Counter with Images ==========
function BoxESP.CreateEnemyCounter(ParentCanvas, centerX, topY)
    if not FVector2D then return false end
    local CD = BoxESP.CounterData
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
            if FSlateColor then
                txt:SetColorAndOpacity(FSlateColor(ColorWhite))
            else
                txt:SetColorAndOpacity(ColorWhite)
            end
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
    local txtBot, slotTxtBot = MakeCounterText(centerX + (BADGE_WIDTH * 0.65), topY + (BADGE_HEIGHT * 0.5))

    LoadBadgeTexture(imgPlayer, ENEMY_COUNTER_PLAYER_URLS, "ic_danger_enemy.png", "Player", CD)
    LoadBadgeTexture(imgBot, ENEMY_COUNTER_BOT_URLS, "ic_clear_boot.png", "Bot", CD)

    CD.ImgPlayer = imgPlayer
    CD.SlotPlayer = slotPlayer
    CD.ImgBot = imgBot
    CD.SlotBot = slotBot
    CD.TxtPlayer = txtPlayer
    CD.SlotTxtPlayer = slotTxtPlayer
    CD.TxtBot = txtBot
    CD.SlotTxtBot = slotTxtBot
    CD.bCreated = true
    return true
end

function BoxESP.UpdateEnemyCounterDisplay(realCount, botCount, ParentCanvas, centerX, topY)
    local CD = BoxESP.CounterData
    if not BoxESP.bShowCounter then
        local col = UEnums.ESlateVisibility.Collapsed
        SafeSetVis(CD.ImgPlayer, col)
        SafeSetVis(CD.ImgBot, col)
        SafeSetVis(CD.TxtPlayer, col)
        SafeSetVis(CD.TxtBot, col)
        return
    end

    if not BoxESP.CreateEnemyCounter(ParentCanvas, centerX, topY) then return end

    local now = os.clock()
    if (not CD.PlayerLoaded or not CD.BotLoaded) and (now - CD.LastDownloadRetry > 2.0) then
        CD.LastDownloadRetry = now
        if not CD.PlayerLoaded and CD.ImgPlayer then LoadBadgeTexture(CD.ImgPlayer, ENEMY_COUNTER_PLAYER_URLS, "ic_danger_enemy.png", "Player", CD) end
        if not CD.BotLoaded and CD.ImgBot then LoadBadgeTexture(CD.ImgBot, ENEMY_COUNTER_BOT_URLS, "ic_clear_boot.png", "Bot", CD) end
    end

    pcall(function()
        SafeSetSize(CD.SlotPlayer, BADGE_WIDTH, BADGE_HEIGHT)
        SafeSetPos(CD.SlotPlayer, centerX - BADGE_WIDTH, topY)
        SafeSetSize(CD.SlotBot, BADGE_WIDTH, BADGE_HEIGHT)
        SafeSetPos(CD.SlotBot, centerX, topY)
        SafeSetPos(CD.SlotTxtPlayer, centerX - (BADGE_WIDTH * 0.25), topY + (BADGE_HEIGHT * 0.5))
        SafeSetPos(CD.SlotTxtBot, centerX + (BADGE_WIDTH * 0.65), topY + (BADGE_HEIGHT * 0.5))

        if CD.LastPlayerCount ~= realCount then
            SafeSetText(CD.TxtPlayer, tostring(realCount))
            CD.LastPlayerCount = realCount
        end

        if CD.LastBotCount ~= botCount then
            SafeSetText(CD.TxtBot, tostring(botCount))
            CD.LastBotCount = botCount
        end

        local vis = UEnums.ESlateVisibility.SelfHitTestInvisible
        SafeSetVis(CD.ImgPlayer, vis)
        SafeSetVis(CD.ImgBot, vis)
        SafeSetVis(CD.TxtPlayer, vis)
        SafeSetVis(CD.TxtBot, vis)
    end)
end

function BoxESP.HideWidget(boxData)
    if not boxData or not boxData.bVisible then return end
    boxData.bVisible = false
    local collapsed = UEnums.ESlateVisibility.Collapsed
    SafeSetVis(boxData.CornerContainer, collapsed)
    SafeSetVis(boxData.BgWidget, collapsed)
    SafeSetVis(boxData.HealthWidget, collapsed)
    SafeSetVis(boxData.WeaponWidget, collapsed)
    SafeSetVis(boxData.FlagWidget, collapsed)
    SafeSetVis(boxData.NameWidget, collapsed)
    SafeSetVis(boxData.DistWidget, collapsed)
    SafeSetVis(boxData.StateWidget, collapsed)
end

function BoxESP.ShowWidget(boxData)
    if not boxData or boxData.bVisible then return end
    boxData.bVisible = true
    local visible = UEnums.ESlateVisibility.SelfHitTestInvisible
    SafeSetVis(boxData.CornerContainer, visible)
    SafeSetVis(boxData.BgWidget, visible)
    SafeSetVis(boxData.HealthWidget, visible)
    SafeSetVis(boxData.WeaponWidget, visible)
    SafeSetVis(boxData.FlagWidget, visible)
    SafeSetVis(boxData.NameWidget, visible)
    SafeSetVis(boxData.DistWidget, visible)
    SafeSetVis(boxData.StateWidget, visible)
end

function BoxESP.UpdateESP()
    if not BoxESP.bActive then return end

    local ParentCanvas = BoxESP.GetMainCanvas()
    if not ParentCanvas then return end

    local GameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"] or _G.GameplayData
    if not GameplayData then return end

    local LocalPlayer = GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
    if not IsValid(LocalPlayer) then return end

    local PC = GameplayData.GetPlayerController and GameplayData.GetPlayerController()
    if not IsValid(PC) then return end

    local curTime = os.clock and os.clock() or 0
    if BoxESP._LastCanvas ~= ParentCanvas or (curTime - BoxESP._LastTransformTime > 1.0) then
        BoxESP.UpdateCanvasTransform(PC)
        BoxESP._LastCanvas = ParentCanvas
        BoxESP._LastTransformTime = curTime
    end

    local bRunHeavyTasks = (curTime - BoxESP._LastHeavyUpdateTime > 0.15)
    if bRunHeavyTasks then
        BoxESP._LastHeavyUpdateTime = curTime
    end

    local bUpdateVisCheck = (curTime - BoxESP._LastVisCheckTime > 0.12)
    if bUpdateVisCheck then
        BoxESP._LastVisCheckTime = curTime
    end

    local fromX, fromY = BoxESP.GetSnapLineStartPos(PC, ParentCanvas)

    local TeamID = LocalPlayer.TeamID or (LocalPlayer.GetTeamID and LocalPlayer:GetTeamID()) or 0
    local AllPawns = (Game and Game.GetAllPlayerPawns and Game:GetAllPlayerPawns()) or {}
    local SeenKeys = {}
    local RealPlayerCount = 0
    local BotCount = 0

    for Key, Pawn in pairs(AllPawns) do
        if IsValid(Pawn) and Pawn ~= LocalPlayer then
            local pawnTeam = Pawn.TeamID or (Pawn.GetTeamID and Pawn:GetTeamID()) or -1
            local isAlive = (Pawn.Health and Pawn.Health > 0) or (Pawn.IsAlive and Pawn:IsAlive())

            if isAlive and pawnTeam ~= TeamID then
                local KeyStr = tostring(Key)
                SeenKeys[KeyStr] = true

                local ping = (Pawn.PlayerState and Pawn.PlayerState.Ping) or Pawn.Ping or (Pawn.GetPing and Pawn:GetPing()) or -1
                ping = tonumber(ping) or -1
                local isBot = (ping >= 0 and ping <= 3) or Pawn.bIsAI or Pawn.bIsAIBot or Pawn.bIsABot or (Game and Game.IsAI and Game:IsAI(Pawn))

                if isBot then
                    BotCount = BotCount + 1
                else
                    RealPlayerCount = RealPlayerCount + 1
                end

                local Loc = Pawn.K2_GetActorLocation and Pawn:K2_GetActorLocation()
                if not Loc and Pawn.RootComponent then
                    pcall(function() Loc = Pawn.RootComponent:K2_GetComponentLocation() end)
                end

                if Loc then
                    local topWorldPos = nil
                    local bottomWorldPos = nil

                    local mesh = Pawn.Mesh or (Pawn.GetMesh and Pawn:GetMesh()) or Pawn.CharacterMesh0
                    if mesh and mesh.GetSocketLocation then
                        local hLoc = nil
                        pcall(function() hLoc = mesh:GetSocketLocation("Head") or mesh:GetSocketLocation("head") end)
                        if hLoc and (hLoc.X ~= 0 or hLoc.Y ~= 0 or hLoc.Z ~= 0) and FVector then
                            topWorldPos = FVector(hLoc.X, hLoc.Y, hLoc.Z + 15)
                        end
                        local rLoc = nil
                        pcall(function() rLoc = mesh:GetSocketLocation("root") or mesh:GetSocketLocation("Root") end)
                        if rLoc and (rLoc.X ~= 0 or rLoc.Y ~= 0 or rLoc.Z ~= 0) then
                            bottomWorldPos = rLoc
                        end
                    end

                    local isProne = false
                    local isCrouch = false
                    if Pawn.bIsProning or Pawn.bIsProne or (Pawn.IsProne and Pawn:IsProne()) or Pawn.PoseState == 2 or Pawn.PoseState == "Prone" then
                        isProne = true
                    elseif Pawn.bIsCrouched or (Pawn.IsCrouched and Pawn:IsCrouched()) or Pawn.PoseState == 1 or Pawn.PoseState == "Crouch" then
                        isCrouch = true
                    end

                    if (not topWorldPos or not bottomWorldPos) and FVector then
                        local topOffset = isProne and 18 or (isCrouch and 50 or 88)
                        local bottomOffset = isProne and -22 or (isCrouch and -68 or -90)
                        topWorldPos = topWorldPos or FVector(Loc.X, Loc.Y, Loc.Z + topOffset)
                        bottomWorldPos = bottomWorldPos or FVector(Loc.X, Loc.Y, Loc.Z + bottomOffset)
                    end

                    if topWorldPos and bottomWorldPos then
                        local bTopOk, topX, topY = BoxESP.ProjectWorldToCanvasLocal(PC, topWorldPos)
                        local bBottomOk, bottomX, bottomY = BoxESP.ProjectWorldToCanvasLocal(PC, bottomWorldPos)

                        local boxData = BoxESP.BoxWidgets[KeyStr]
                        if not boxData then
                            boxData = BoxESP.CreateESPWidget(ParentCanvas)
                            if boxData then BoxESP.BoxWidgets[KeyStr] = boxData end
                        end

                        if boxData and IsValid(boxData.CornerContainer) then
                            if bTopOk and bBottomOk then
                                local boxHeight = math.max(28, math.abs(bottomY - topY))
                                local boxWidth = math.max(15, boxHeight * (isProne and 1.1 or (isCrouch and 0.7 or 0.55)))

                                local centerX = (topX + bottomX) * 0.5
                                local centerY = (topY + bottomY) * 0.5
                                local boxTopY = centerY - (boxHeight * 0.5)
                                local boxBottomY = centerY + (boxHeight * 0.5)

                                BoxESP.UpdateCornerDimensions(boxData, boxWidth, boxHeight)
                                SafeSetPos(boxData.CornerSlot, centerX, centerY)
                                BoxESP.ShowWidget(boxData)

                                local healthBarWidth = BoxESP.HealthBarWidth or 2.0
                                local healthCenterX = centerX - (boxWidth * 0.5) - 2.5 - (healthBarWidth * 0.5)
                                local health = Pawn.Health or (Pawn.GetHealth and Pawn:GetHealth()) or 100
                                local healthMax = Pawn.HealthMax or (Pawn.GetHealthMax and Pawn:GetHealthMax()) or 100
                                if healthMax <= 0 then healthMax = 100 end

                                local healthPercent = math.max(0, math.min(1, health / healthMax))
                                local currentHealthHeight = boxHeight * healthPercent

                                SafeSetSize(boxData.BgSlot, healthBarWidth, boxHeight)
                                SafeSetPos(boxData.BgSlot, healthCenterX, boxBottomY)
                                SafeSetSize(boxData.HealthSlot, healthBarWidth, currentHealthHeight)
                                SafeSetPos(boxData.HealthSlot, healthCenterX, boxBottomY)

                                if bRunHeavyTasks or boxData._cachedWeapon == "" then
                                    local wep = (Pawn.GetCurrentWeapon and Pawn:GetCurrentWeapon())
                                        or (Pawn.GetCurrentShootWeapon and Pawn:GetCurrentShootWeapon())
                                        or (Pawn.WeaponManagerComponent and Pawn.WeaponManagerComponent.CurrentWeaponReplicated)
                                    local weaponName = "Fist"
                                    if wep and IsValid(wep) then
                                        local wn = (type(wep.GetWeaponName) == "function" and wep:GetWeaponName()) or wep.WeaponName
                                        if wn and wn ~= "" then
                                            weaponName = tostring(wn):gsub("^BP_", ""):gsub("_C$", ""):gsub("_Wrapper$", "")
                                        end
                                    end
                                    if boxData._cachedWeapon ~= weaponName then
                                        SafeSetText(boxData.WeaponWidget, weaponName)
                                        boxData._cachedWeapon = weaponName
                                    end
                                end
                                SafeSetPos(boxData.WeaponSlot, centerX, boxTopY - 3.5)

                                if bRunHeavyTasks or not boxData._cachedNation then
                                    local playerNation = (Pawn.PlayerState and Pawn.PlayerState.Nation) or Pawn.Nation or ""
                                    playerNation = tostring(playerNation or "")
                                    if playerNation == "" or playerNation == "nil" or playerNation == "0" then
                                        playerNation = "G1"
                                    end

                                    if boxData._cachedNation ~= playerNation then
                                        local cfg = nil
                                        pcall(function()
                                            if CDataTable and CDataTable.GetTableData then
                                                cfg = CDataTable.GetTableData("RegionConfig", playerNation)
                                                if not cfg or not cfg.res_path or cfg.res_path == "" then
                                                    cfg = CDataTable.GetTableData("RegionConfig", "G1")
                                                end
                                            end
                                        end)
                                        local flagPath = (cfg and cfg.res_path) or "/Game/UMG/Texture/Atlas/NationalflagUI/Frames/T_icon_flag_iland_png.T_icon_flag_iland_png"

                                        if boxData.FlagWidget and IsValid(boxData.FlagWidget) then
                                            pcall(function()
                                                local bSet = false
                                                if boxData.FlagWidget.SetBrushResourceFromPathSync then
                                                    boxData.FlagWidget:SetBrushResourceFromPathSync(flagPath, false)
                                                    bSet = true
                                                end
                                                if not bSet and boxData.FlagWidget.SetBrushFromPathAsync then
                                                    boxData.FlagWidget:SetBrushFromPathAsync(flagPath, false)
                                                    bSet = true
                                                end
                                                if not bSet then
                                                    local util = package.loaded["client.slua_ui_framework.util"]
                                                    if not util then pcall(function() util = require("client.slua_ui_framework.util") end) end
                                                    if util and util.SetTexture then
                                                        util.SetTexture(boxData.FlagWidget, flagPath, { sync = true })
                                                        bSet = true
                                                    end
                                                end
                                                if not bSet then
                                                    local asset_util = package.loaded["common.asset_util"]
                                                    if not asset_util then pcall(function() asset_util = require("common.asset_util") end) end
                                                    local flagTex = (asset_util and asset_util.GetAssetSync and asset_util.GetAssetSync(flagPath))
                                                                 or (CGame and CGame.LoadObject and CGame:LoadObject(flagPath))
                                                    if flagTex and boxData.FlagWidget.SetBrushFromTexture then
                                                        boxData.FlagWidget:SetBrushFromTexture(flagTex, false)
                                                    end
                                                end
                                                boxData.FlagWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                                            end)
                                        end
                                        boxData._cachedNation = playerNation
                                    end
                                end
                                if boxData.FlagSlot then
                                    SafeSetPos(boxData.FlagSlot, centerX, boxTopY - 22.0)
                                end

                                if bRunHeavyTasks or boxData._cachedName == "" then
                                    local playerName = isBot and "Bot" or (Pawn.PlayerName or Pawn.PlayerNamePublic or (Pawn.GetPlayerName and Pawn:GetPlayerName()) or "Player")
                                    playerName = tostring(playerName)
                                    if boxData._cachedName ~= playerName then
                                        SafeSetText(boxData.NameWidget, playerName)
                                        boxData._cachedName = playerName
                                    end
                                end
                                SafeSetPos(boxData.NameSlot, centerX, boxBottomY + 4.0)

                                local distRaw = 0
                                pcall(function() distRaw = LocalPlayer:GetDistanceTo(Pawn) or 0 end)
                                local distVal = math.floor((distRaw or 0) / 100.0)
                                local distStr = tostring(distVal) .. "m"
                                if boxData._cachedDist ~= distStr then
                                    SafeSetText(boxData.DistWidget, distStr)
                                    boxData._cachedDist = distStr
                                end
                                SafeSetPos(boxData.DistSlot, centerX, boxBottomY + 20.5)

                                if bUpdateVisCheck or BoxESP._VisCheckCache[KeyStr] == nil then
                                    local visResult = false
                                    pcall(function() visResult = (PC and PC.LineOfSightTo and PC:LineOfSightTo(Pawn)) or false end)
                                    BoxESP._VisCheckCache[KeyStr] = visResult
                                end
                                local isVisible = BoxESP._VisCheckCache[KeyStr]

                                if bRunHeavyTasks or boxData._cachedState == "" then
                                    local isKnocked = (Pawn.HealthStatus == 1 or Pawn.bIsKnocked or (Pawn.IsKnocked and Pawn:IsKnocked()))
                                    local stateStr = "Open"
                                    local slateCol = SlateColorGreen
                                    if isKnocked then
                                        stateStr = "Knocked"
                                        slateCol = SlateColorRed
                                    elseif not isVisible then
                                        stateStr = "Cover"
                                        slateCol = SlateColorRed
                                    end

                                    if boxData._cachedState ~= stateStr then
                                        SafeSetText(boxData.StateWidget, stateStr)
                                        SafeSetColor(boxData.StateWidget, slateCol)
                                        boxData._cachedState = stateStr
                                    end
                                end
                                SafeSetPos(boxData.StateSlot, centerX, boxBottomY + 37.0)

                                if BoxESP.bShowLines then
                                    local lineColor = isVisible and ColorGreen or ColorRed
                                    BoxESP.UpdateSnapLine(KeyStr, centerX, boxTopY, fromX, fromY, lineColor, ParentCanvas)
                                else
                                    BoxESP.HideSnapLine(KeyStr)
                                end
                            else
                                BoxESP.HideWidget(boxData)
                                BoxESP.HideSnapLine(KeyStr)
                            end
                        end
                    end
                end
            end
        end
    end

    for KeyStr, boxData in pairs(BoxESP.BoxWidgets) do
        if not SeenKeys[KeyStr] then
            BoxESP.HideWidget(boxData)
            BoxESP._VisCheckCache[KeyStr] = nil
        end
    end
    for KeyStr, _ in pairs(BoxESP.LineWidgets) do
        if not SeenKeys[KeyStr] then
            BoxESP.HideSnapLine(KeyStr)
            BoxESP._VisCheckCache[KeyStr] = nil
        end
    end

    local counterTopY = fromY - BADGE_HEIGHT - 2
    if counterTopY < 10 then counterTopY = 48 end
    BoxESP.UpdateEnemyCounterDisplay(RealPlayerCount, BotCount, ParentCanvas, fromX, counterTopY)
end

pcall(function()
    local PC = nil
    if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
        PC = slua_GameFrontendHUD:GetPlayerController()
    end
    if IsValid(PC) and PC.AddGameTimer then
        PC:AddGameTimer(0.02, true, BoxESP.UpdateESP)
    end
end)

pcall(function()
    local Ticker = package.loaded["common.time_ticker"] or require("common.time_ticker")
    if Ticker and Ticker.AddTimerLoop then
        Ticker.AddTimerLoop(function()
            BoxESP.UpdateESP()
            return true
        end, 0.02)
    end
end)

_G.BoxESP = BoxESP
