local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}

-- [ESP ADD] begin — SnapLineESP module
local SnapLineESP = nil
pcall(function()
  local SlateBlueprintLibrary, WidgetLayoutLibrary
  local FVector2D, FVector, FLinearColor, FSlateColor

  SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary")
  WidgetLayoutLibrary  = import("WidgetLayoutLibrary")  or import("/Script/UMG.WidgetLayoutLibrary")
  FVector2D    = import("Vector2D")
  FVector      = import("Vector")
  FLinearColor = import("LinearColor")
  FSlateColor  = import("SlateColor") or import("/Script/SlateCore.SlateColor")

  local function IsValid(obj)
    if not obj then return false end
    if slua and slua.isValid then return slua.isValid(obj) end
    return true
  end

  local GameplayData = nil
  pcall(function()
    GameplayData = _G.GameplayData
       or package.loaded["GameLua.GameCore.Data.GameplayData"]
       or require("GameLua.GameCore.Data.GameplayData")
  end)

  local TempProjVec2D = FVector2D and FVector2D(0, 0) or nil
  local ColorWhite  = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or nil
  local ColorRed    = FLinearColor and FLinearColor(1.0, 0.15, 0.15, 1.0) or nil
  local ColorGreen  = FLinearColor and FLinearColor(0.0, 1.0, 0.05, 1.0) or nil

  local ENEMY_COUNTER_PLAYER_URLS = {}
  local ENEMY_COUNTER_BOT_URLS    = {}
  local EnemyCounterTextureCache  = {}
  local BADGE_WIDTH, BADGE_HEIGHT = 48, 22

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
    local function tryDownloadUrl(i)
      if i > #urls then return end
      local url = urls[i]
      local done = false
      pcall(function()
        local AsyncTaskDownloadImage = import("AsyncTaskDownloadImage") or import("/Script/UMG.AsyncTaskDownloadImage")
        if AsyncTaskDownloadImage and AsyncTaskDownloadImage.DownloadImage then
          local task = AsyncTaskDownloadImage.DownloadImage(url)
          if task and task.OnSuccess then
            task.OnSuccess:Add(function(tex) if not done and tex then done = true; applyTex(tex) end end)
            if task.OnFail then
              task.OnFail:Add(function() if not done then tryDownloadUrl(i + 1) end end)
            end
          end
        end
      end)
      if not done then
        pcall(function()
          local mm = _G.ModuleManager or package.loaded["GameLua.GameCore.Module.ModuleManager"]
          if not mm then pcall(function() mm = require("GameLua.GameCore.Module.ModuleManager") end) end
          local imgMgr = nil
          if mm and mm.GetModule and mm.CommonModuleConfig then
            imgMgr = mm.GetModule(mm.CommonModuleConfig.image_download_mgr)
          end
          if not imgMgr then pcall(function() imgMgr = require("client.slua.logic.image_download.image_download_mgr") end) end
          if imgMgr and imgMgr.DownloadImageByHttpWrapper then
            imgMgr:DownloadImageByHttpWrapper(url,
              function(tex) if not done and tex then done = true; applyTex(tex) end end,
              function() if not done then tryDownloadUrl(i + 1) end end)
          end
        end)
      end
    end
    tryDownloadUrl(1)
  end

  local M = {
    bActive = true, bShowLines = true, bShowCounter = true, bShowDistance = true,
    bBootstrapped = false,
    ESPCanvas = nil,
    LineWidgets = {}, DistWidgets = {},
    CounterData = {
      ImgPlayer = nil, SlotPlayer = nil,
      ImgBot = nil, SlotBot = nil,
      TxtPlayer = nil, SlotTxtPlayer = nil,
      TxtBot = nil, SlotTxtBot = nil,
      LastPlayerCount = -1, LastBotCount = -1,
      PlayerLoaded = false, BotLoaded = false,
      LastDownloadRetry = 0, bCreated = false
    },
    SnapLineThickness = 1.0, SnapLineOriginY = 72,
    _CanvasScaleX = 1.0, _CanvasScaleY = 1.0,
    _CanvasOffsetX = 0.0, _CanvasOffsetY = 0.0,
    _LastCanvas = nil, _LastTransformTime = 0,
    _LastHeavyUpdateTime = 0, _LastVisCheckTime = 0,
    _VisCheckCache = {},
    _tick = 0
  }

  function M.GetMainCanvas()
    if M.ESPCanvas and IsValid(M.ESPCanvas) then return M.ESPCanvas end
    local InGameUITools = package.loaded["GameLua.Mod.BaseMod.Common.UI.InGameUITools"]
    if not InGameUITools then
      pcall(function() InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
    end
    if not InGameUITools then return nil end
    local MainUI = InGameUITools.GetMainControlBaseUI and InGameUITools.GetMainControlBaseUI()
    if not IsValid(MainUI) then return nil end
    local P = nil
    if MainUI.CanvasPanel_0  and IsValid(MainUI.CanvasPanel_0)  then P = MainUI.CanvasPanel_0
    elseif MainUI.CanvasPanel_42 and IsValid(MainUI.CanvasPanel_42) then P = MainUI.CanvasPanel_42 end
    if P then M.ESPCanvas = P; M._LastCanvas = P end
    return P
  end

  function M.UpdateCanvasTransform(PC)
    if not M.ESPCanvas or not IsValid(M.ESPCanvas) then return end
    local ok = false
    if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
      local cg = M.ESPCanvas:GetCachedGeometry()
      if cg then
        local pt0 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(0, 0))
        local pt1 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(100, 100))
        if pt0 and pt1 then
          M._CanvasScaleX = (pt1.X - pt0.X) / 100
          M._CanvasScaleY = (pt1.Y - pt0.Y) / 100
          M._CanvasOffsetX, M._CanvasOffsetY = pt0.X, pt0.Y
          ok = true
        end
      end
    end
    if not ok and WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
      local s = WidgetLayoutLibrary.GetViewportScale(PC) or 1.0
      M._CanvasScaleX, M._CanvasScaleY = 1.0 / s, 1.0 / s
      M._CanvasOffsetX, M._CanvasOffsetY = 0, 0
    end
  end

  function M.ProjectWorldToCanvasLocal(PC, WorldLoc)
    if not IsValid(PC) or not WorldLoc or not TempProjVec2D then return false, 0, 0 end
    local res = PC:ProjectWorldLocationToScreen(WorldLoc, TempProjVec2D, true)
    if (res == true or res == 1) and (TempProjVec2D.X ~= 0 or TempProjVec2D.Y ~= 0) then
      return true,
        TempProjVec2D.X * M._CanvasScaleX + M._CanvasOffsetX,
        TempProjVec2D.Y * M._CanvasScaleY + M._CanvasOffsetY
    end
    return false, 0, 0
  end

  function M.GetSnapLineStartPos(PC)
    local w, h, scale = 0, 0, 1.0
    pcall(function()
      if PC and PC.GetViewportSize then
        local vs = FVector2D(0, 0)
        PC:GetViewportSize(vs)
        if vs and vs.X and vs.X > 200 then w, h = vs.X, vs.Y end
      end
    end)
    if w <= 200 then
      pcall(function()
        if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportSize then
          local vs = WidgetLayoutLibrary.GetViewportSize(PC)
          if vs and vs.X and vs.X > 200 then w, h = vs.X, vs.Y end
        end
      end)
    end
    pcall(function()
      if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
        local s = WidgetLayoutLibrary.GetViewportScale(PC)
        if s and type(s) == "number" and s > 0 then scale = s end
      end
    end)
    if w <= 200 then w, h = 1920 * scale, 1080 * scale end
    return (w / 2.0) * M._CanvasScaleX + M._CanvasOffsetX,
           (M.SnapLineOriginY * scale) * M._CanvasScaleY + M._CanvasOffsetY
  end

  function M.CreateSnapLine(ParentCanvas)
    if not IsValid(ParentCanvas) then return nil end
    local border = CGame:NewObjectFromPath("/Script/UMG.Border", ParentCanvas)
    if not IsValid(border) then return nil end
    border:SetBrushColor(ColorWhite)
    border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    border.RenderTransformPivot = FVector2D(0.0, 0.5)
    border:SetRenderTransformPivot(FVector2D(0.0, 0.5))
    local slot = ParentCanvas:AddChildToCanvas(border)
    if slot then slot:SetAutoSize(false); slot:SetZOrder(990) end
    return { Widget = border, Slot = slot, bVisible = true }
  end

  function M.UpdateSnapLine(KeyStr, toX, toY, fromX, fromY, CustomColor, ParentCanvas)
    local lineData = M.LineWidgets[KeyStr]
    if not lineData or not IsValid(lineData.Widget) then
      lineData = M.CreateSnapLine(ParentCanvas)
      if not lineData or not lineData.Widget or not lineData.Slot then return end
      M.LineWidgets[KeyStr] = lineData
    end
    if not lineData.bVisible then
      lineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      lineData.bVisible = true
    end
    if CustomColor then pcall(function() lineData.Widget:SetBrushColor(CustomColor) end) end
    local dx, dy = toX - fromX, toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    local angle = (math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)) * (180.0 / math.pi)
    local t = M.SnapLineThickness or 1.0
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

  function M.HideSnapLine(KeyStr)
    local ld = M.LineWidgets[KeyStr]
    if ld and ld.Widget and IsValid(ld.Widget) and ld.bVisible then
      ld.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      ld.bVisible = false
    end
  end

  function M.CreateDistWidget(ParentCanvas)
    if not IsValid(ParentCanvas) then return nil end
    local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", ParentCanvas)
    local slot = nil
    if txt and IsValid(txt) then
      txt:SetText("")
      if txt.Font then
        local font = txt.Font
        font.Size = 10
        if font.OutlineSettings then
          font.OutlineSettings.OutlineSize  = 1
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

  function M.UpdateDistWidget(KeyStr, x, y, distStr, ParentCanvas)
    local dw = M.DistWidgets[KeyStr]
    if not dw or not IsValid(dw.Widget) then
      dw = M.CreateDistWidget(ParentCanvas)
      if not dw then return end
      M.DistWidgets[KeyStr] = dw
    end
    if not dw.bVisible then
      dw.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      dw.bVisible = true
    end
    if dw._cached ~= distStr then dw.Widget:SetText(distStr); dw._cached = distStr end
    if dw.Slot then pcall(function() dw.Slot:SetPosition(FVector2D(x, y)) end) end
  end

  function M.HideDistWidget(KeyStr)
    local dw = M.DistWidgets[KeyStr]
    if dw and dw.Widget and IsValid(dw.Widget) and dw.bVisible then
      dw.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      dw.bVisible = false
    end
  end

  function M.CreateEnemyCounter(ParentCanvas, centerX, topY)
    local CD = M.CounterData
    if CD.ImgPlayer and IsValid(CD.ImgPlayer) and CD.ImgBot and IsValid(CD.ImgBot) then return true end
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
    local function MakeText(posX, posY)
      local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", ParentCanvas)
      local sl = nil
      if txt and IsValid(txt) then
        txt:SetText("0")
        if txt.Font then
          local font = txt.Font
          font.Size = 10
          if font.OutlineSettings then
            font.OutlineSettings.OutlineSize  = 0.0
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
    local txtPlayer, slotTxtPlayer = MakeText(centerX - (BADGE_WIDTH * 0.25), topY + (BADGE_HEIGHT * 0.5))
    local txtBot,    slotTxtBot    = MakeText(centerX + (BADGE_WIDTH * 0.65), topY + (BADGE_HEIGHT * 0.5))
    LoadBadgeTexture(imgPlayer, ENEMY_COUNTER_PLAYER_URLS, "ic_danger_enemy.png", "Player", CD)
    LoadBadgeTexture(imgBot,    ENEMY_COUNTER_BOT_URLS,    "ic_clear_boot.png",   "Bot",    CD)
    CD.ImgPlayer, CD.SlotPlayer = imgPlayer, slotPlayer
    CD.ImgBot,    CD.SlotBot    = imgBot,    slotBot
    CD.TxtPlayer, CD.SlotTxtPlayer = txtPlayer, slotTxtPlayer
    CD.TxtBot,    CD.SlotTxtBot    = txtBot,    slotTxtBot
    CD.bCreated = true
    return true
  end

  function M.UpdateEnemyCounterDisplay(realCount, botCount, ParentCanvas, centerX, topY)
    local CD = M.CounterData
    if not M.bShowCounter then return end
    if not M.CreateEnemyCounter(ParentCanvas, centerX, topY) then return end
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

  local function GetAllPawns()
    local list = nil
    if Game and Game.GetAllPlayerPawns then
      local ok, r = pcall(function() return Game:GetAllPlayerPawns() end)
      if ok and r then list = r end
    end
    if (not list or next(list) == nil) and GameplayData and GameplayData.GetAllPlayerPawns then
      local ok, r = pcall(function() return GameplayData:GetAllPlayerPawns() end)
      if ok and r then list = r end
    end
    return list or {}
  end

  function M.UpdateESP()
    if not M.bActive then return end
    M._tick = M._tick + 1

    local ParentCanvas = M.GetMainCanvas()
    if not ParentCanvas then return end
    if not GameplayData then return end
    local LocalPlayer = GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
    if not IsValid(LocalPlayer) then return end
    local PC = GameplayData.GetPlayerController and GameplayData.GetPlayerController()
    if not IsValid(PC) then return end

    local curTime = os.clock and os.clock() or 0
    if M._LastCanvas ~= ParentCanvas or (curTime - M._LastTransformTime > 1.0) then
      M.UpdateCanvasTransform(PC)
      M._LastCanvas = ParentCanvas
      M._LastTransformTime = curTime
    end
    local bRunHeavy = (curTime - M._LastHeavyUpdateTime > 0.15)
    local bVisCheck = (curTime - M._LastVisCheckTime   > 0.12)
    if bRunHeavy then M._LastHeavyUpdateTime = curTime end
    if bVisCheck then M._LastVisCheckTime    = curTime end

    local fromX, fromY = M.GetSnapLineStartPos(PC)

    local TeamID = LocalPlayer.TeamID or (LocalPlayer.GetTeamID and LocalPlayer:GetTeamID()) or 0
    local AllPawns = GetAllPawns()
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
              or Pawn.PoseState == 2 or Pawn.PoseState == "Prone" then isProne = true
            elseif Pawn.bIsCrouched or (Pawn.IsCrouched and Pawn:IsCrouched())
              or Pawn.PoseState == 1 or Pawn.PoseState == "Crouch" then isCrouch = true end

            local topOffset    = isProne and 18 or (isCrouch and 50 or 88)
            local bottomOffset = isProne and -22 or (isCrouch and -68 or -90)
            local topWorld    = FVector(Loc.X, Loc.Y, Loc.Z + topOffset)
            local bottomWorld = FVector(Loc.X, Loc.Y, Loc.Z + bottomOffset)

            local bTopOk, topX, topY  = M.ProjectWorldToCanvasLocal(PC, topWorld)
            local bBotOk, botX, botY  = M.ProjectWorldToCanvasLocal(PC, bottomWorld)

            if bTopOk and bBotOk then
              local centerX = (topX + botX) * 0.5
              local boxTopY = math.min(topY, botY)
              local boxBotY = math.max(topY, botY)

              if bVisCheck or M._VisCheckCache[KeyStr] == nil then
                M._VisCheckCache[KeyStr] = (PC and PC.LineOfSightTo and PC:LineOfSightTo(Pawn)) or false
              end
              local isVisible = M._VisCheckCache[KeyStr]

              if M.bShowLines then
                local lineColor = isVisible and ColorGreen or ColorRed
                M.UpdateSnapLine(KeyStr, centerX, boxTopY, fromX, fromY, lineColor, ParentCanvas)
              else
                M.HideSnapLine(KeyStr)
              end

              if M.bShowDistance then
                local d = math.floor(LocalPlayer:GetDistanceTo(Pawn) / 100.0)
                M.UpdateDistWidget(KeyStr, centerX, boxBotY + 4.0, tostring(d) .. "m", ParentCanvas)
              else
                M.HideDistWidget(KeyStr)
              end
            else
              M.HideSnapLine(KeyStr)
              M.HideDistWidget(KeyStr)
            end
          end
        end
      end
    end

    for KeyStr, _ in pairs(M.LineWidgets) do
      if not SeenKeys[KeyStr] then
        M.HideSnapLine(KeyStr)
        M._VisCheckCache[KeyStr] = nil
      end
    end
    for KeyStr, _ in pairs(M.DistWidgets) do
      if not SeenKeys[KeyStr] then M.HideDistWidget(KeyStr) end
    end

    local counterTopY = fromY - BADGE_HEIGHT - 2
    if counterTopY < 10 then counterTopY = 48 end
    M.UpdateEnemyCounterDisplay(RealPlayerCount, BotCount, ParentCanvas, fromX, counterTopY)
  end

  SnapLineESP = M
end)

_G.SnapLineESP = SnapLineESP

-- Register tickers at file-load time (mirrors the working original pattern)
if SnapLineESP then
  pcall(function()
    local Ticker = package.loaded["common.time_ticker"] or require("common.time_ticker")
    if Ticker and Ticker.AddTimerLoop then
      Ticker.AddTimerLoop(function()
        SnapLineESP.UpdateESP()
        return true
      end, 0.02)
      print("[SnapLineESP] ticker registered via common.time_ticker")
    end
  end)

  pcall(function()
    local PC = nil
    if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
      PC = slua_GameFrontendHUD:GetPlayerController()
    end
    if PC and slua.isValid(PC) and PC.AddGameTimer then
      PC:AddGameTimer(0.02, true, SnapLineESP.UpdateESP)
      print("[SnapLineESP] ticker registered via PC:AddGameTimer")
    end
  end)
end
-- [ESP ADD] end

local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local ECharacterHideMovementAcive = import("ECharacterHideMovementAcive")
local ESpecialMovementType = import("ESpecialMovementType")
local ESpiderSwingMoveState = import("ESpiderSwingMoveState")
local ESurviveWeaponPropSlot = import("ESurviveWeaponPropSlot")
local EParachuteState = import("EParachuteState")
local EMovementMode = import("EMovementMode")
local EStateType = import("EStateType")
local ESTEPoseState = import("ESTEPoseState")
local EGameModeType = import("EGameModeType")
local STExtraGameStateBase = import("STExtraGameStateBase")
local UKismetSystemLibrary = import("KismetSystemLibrary")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")

function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = { "bCanSelfRescue" }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
    self:AddControlEvent(self, "OnPawnRespawnDelegate", self.OnRespawnRehideCheck, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local Mask = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(Mask.Bit0, true)
  end
end

function BRPlayerCharacterBase:OnRespawnRehideCheck()
  if not self:GetEnsure() then return end
  self:AddGameTimer(0.5, false, function()
    if not slua.isValid(self.Object) then return end
    if self:HasState(EPawnState.InPlane) then
      self:SetCharacterHideInGame(true, true, true, 1, ECharacterHideMovementAcive.Normal)
      print(bWriteLog and "BRPlayerCharacterBase:OnRespawnRehideCheck re-hide AI on plane, PlayerKey:", self.PlayerKey)
    end
  end)
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID   = tonumber(CGameState.GameModeID)
    local bType = GameModeType == EGameModeType.ETypicalGameMode
               or GameModeType == EGameModeType.EFourInOneGameMode
               or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bID = not MatchModeIds[GameModeID]
    print(bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bType, bID)
    return bType and bID
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  if not Client then
    local PC = self:GetPlayerControllerSafety()
    if slua.isValid(PC) and PC.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if PC.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          PC.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if PC.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          PC.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if PC.CheckParachuteOpenFeature.ClearTimerAndState then
          PC.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
  if not Client then
    local PC = self:GetPlayerControllerSafety()
    if slua.isValid(PC) and PC.CheckParachuteOpenFeature then
      if PC.CheckParachuteOpenFeature.ClearTimerAndState then PC.CheckParachuteOpenFeature:ClearTimerAndState() end
      if PC.CheckParachuteOpenFeature.ResetCheckShowUI  then PC.CheckParachuteOpenFeature:ResetCheckShowUI()  end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then GameplayData.RemoveCharacter(self.Object) end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  end
  return false
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ",
      Game:GetPlainName(self.Object),
      tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll),
      tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  if Game:IsValid(self.STCharacterMovement)
    and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming
    and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy
    and Game:IsValid(self.STCharacterMovement)
    and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking
    and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then return end
  local PC = self:GetPlayerControllerSafety()
  if not slua.isValid(PC) then return end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then return end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(PC, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
        uPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPC = self:GetControllerSafety()
  if slua.isValid(uPC) then
    if not self:GetEnsure() then
      if uPC:GetCurrentStateType() ~= EStateType.State_ParachuteJump
        and uPC:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPC:ReInitParachuteItem()
        uPC:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then return end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then return end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then return end
  if not Lifter.AddCharacter then return end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then return false end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPC = self:GetPlayerControllerSafety()
    if slua.isValid(uPC) then uPC:DisplayGameTipWithMsgID(48532) end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then uPlayerState:AddGeneralCount(1613, 1, false) end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then return end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then return end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then return end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  local loadLater = function()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s",
    tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s",
    tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox)
    and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox"))
    and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera
    and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera
    and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList
        and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local uPC = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPC) and uPC.Role == ENetRole.ROLE_AutonomousProxy then
          uPC:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None
    and slua.isValid(self.STCharacterMovement) then
    local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(SpiderSwingObj) then
      local nCurState = SpiderSwingObj:GetCurMoveState()
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked by SpiderSwing state: " .. tostring(nCurState))
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

local VICTORY_DANCE_FX_MAP = { [12219601] = 22010089 }
local PublishRegionMacros = require("client.slua.config.ClientMacros.PublishRegionMacros")
local isFitVersion = PublishRegionMacros.IsFITVersion()
local ResolveEmoteResID = function(ItemID)
  local FxID = VICTORY_DANCE_FX_MAP[ItemID]
  if not FxID or FxID == ItemID then return ItemID end
  local model_util = require("client.common.model_util")
  local FxBPID = model_util.GetBPID(FxID)
  local ResID = ItemID
  if FxBPID and 0 < FxBPID and model_util.IsBattleItemHandleExist("Emote", FxBPID, false, false) then
    ResID = FxID
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase 11 ResolveEmoteResID ItemID:%s, FxID:%s, FxBPID:%s, ResID:%s",
    tostring(ItemID), tostring(FxID), tostring(FxBPID), tostring(ResID)))
  if isFitVersion and ResID == 12219601 then
    print(bWriteLog and "BRPlayerCharacterBase ResolveEmoteResID 12219601 to 12222069")
    return 12222069
  end
  return ResID
end

function BRPlayerCharacterBase:GetEmoteHandlePath(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then return self.Super:GetEmoteHandlePath(ResID) end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then return "" end
  return model_util.GetPath("Emote", BPID, false, false) or ""
end

function BRPlayerCharacterBase:GetEmoteHandle(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then return self.Super:GetEmoteHandle(ResID) end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then return nil end
  local HandleClass = model_util.GetClass("Emote", BPID, false, false)
  if not HandleClass then return nil end
  local Handle = HandleClass()
  if not slua.isValid(Handle) then return nil end
  return Handle
end

local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  { SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature" },
  { CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature" },
  { SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature" },
  { TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature" },
  { LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature" },
  { FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature" },
  { CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature" },
  { BuildAircraftVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature" },
  { UnifiedBuildVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.UnifiedBuildVehicleFeature" },
  { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },
  { ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature" },
  { ParachuteSprint = "GameLua.Mod.BaseMod.GamePlay.Feature.Parachute.ParachuteSprintFeature" },
  { GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature" },
  { FPPAnimMonitor = "GameLua.Mod.BaseMod.GamePlay.Feature.Player.FPPAnimMonitorFeature" }
}, "BRPlayerCharacterBase")
