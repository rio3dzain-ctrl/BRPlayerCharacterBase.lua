local BRPlayerCharacterBase = {
  ServerRPC = {}, ClientRPC = {}, MulticastRPC = {}, LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }

local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local ECharacterHideMovementAcive = nil
pcall(function() ECharacterHideMovementAcive = import("ECharacterHideMovementAcive") end)
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

function BRPlayerCharacterBase:ctor() end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local C = import("CheckFallingDistanceComponent")
    if slua.isValid(C) and not slua.isValid(self:GetComponentByClass(C)) then
      Game:AddComponent(C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then self.STCharacterMovement.bPositiveBlowUp = true end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", { AttrName = { "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1] = "FinishedState" }, self.HandleFinishedState, self)
    self:AddControlEvent(self, "OnPawnRespawnDelegate", self.OnRespawnRehideCheck, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) then pc:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "") end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(s)
  if s == EPawnState.SwitchPP then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) then pc:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "") end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local M = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(M.Bit0, true)
  end
end

function BRPlayerCharacterBase:OnRespawnRehideCheck()
  if not self:GetEnsure() then return end
  self:AddGameTimer(0.5, false, function()
    if not slua.isValid(self.Object) then return end
    if self:HasState(EPawnState.InPlane) then
      if ECharacterHideMovementAcive and ECharacterHideMovementAcive.Normal then
        self:SetCharacterHideInGame(true, true, true, 1, ECharacterHideMovementAcive.Normal)
      end
    end
  end)
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local t = CGameMode.GameModeType
    local id = tonumber(CGameState.GameModeID)
    local ok = t == EGameModeType.ETypicalGameMode or t == EGameModeType.EFourInOneGameMode or t == EGameModeType.EHeavyWeaponGameMode
    return ok and not MatchModeIds[id]
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(L, N)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, L, N)
  if not Client then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) and pc.CheckParachuteOpenFeature then
      if N == EParachuteState.PS_Opening and pc.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
        pc.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
      elseif N == EParachuteState.PS_None then
        if pc.CheckParachuteOpenFeature.RecoverParachuteOpenParam then pc.CheckParachuteOpenFeature:RecoverParachuteOpenParam() end
        if pc.CheckParachuteOpenFeature.ClearTimerAndState then pc.CheckParachuteOpenFeature:ClearTimerAndState() end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
  if not Client then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) and pc.CheckParachuteOpenFeature then
      if pc.CheckParachuteOpenFeature.ClearTimerAndState then pc.CheckParachuteOpenFeature:ClearTimerAndState() end
      if pc.CheckParachuteOpenFeature.ResetCheckShowUI then pc.CheckParachuteOpenFeature:ResetCheckShowUI() end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(R)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, R)
  if Client then GameplayData.RemoveCharacter(self.Object) end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local gs = GameplayData:GetGameState()
  if slua.isValid(gs) and Game:IsClassOf(gs, STExtraGameStateBase) then
    return gs.GameModeType == EGameModeType.EWarGameMode
  end
  return false
end

function BRPlayerCharacterBase:BPOnRecycled() if Client then self:ResetMeshRelativeLocationAndRotation() end end
function BRPlayerCharacterBase:BPOnRespawned() if Client then self:ResetMeshRelativeLocationAndRotation() end end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  if Client then self:ResetMeshRelativeLocationAndRotation() GameplayData.RemoveCharacter(self.Object) end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  if Client then self:ResetMeshRelativeLocationAndRotation() GameplayData.AddCharacter(self.Object) end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local r = FRotator(0, -90, 0)
    local l = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then self.Mesh:K2_SetRelativeRotation(r, false, nil, false) end
    self:CacheInitialMeshOffset(l, r)
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord() end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  if not UKismetSystemLibrary.IsDedicatedServer(self) then return end
  local pc = self:GetPlayerControllerSafety()
  if not slua.isValid(pc) then return end
  local av = self.CharacterAvatarComp2_BP
  if not slua.isValid(av) then return end
  local U = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local vID = U:ChangeVehicleSkinByClothes(pc, av)
  local S = import("ESTExtraVehicleShapeType")
  if vID then
    local AU = import("AvatarUtils")
    if AU.GetVehicleShapeBySkinID(vID) == S.VST_Horse then
      local ps = self:GetPlayerStateSafety()
      if slua.isValid(ps) then ps:AddGeneralCount(468, 1, false) end
    end
  end
end

function BRPlayerCharacterBase:ParachuteJump()
  local pc = self:GetControllerSafety()
  if slua.isValid(pc) then
    if not self:GetEnsure() then
      if pc:GetCurrentStateType() ~= EStateType.State_ParachuteJump and pc:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        pc:ReInitParachuteItem()
        pc:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uC, uN, uO)
  if uC ~= self.Object then return end
  local M = self:GetMedievalCraneFromBase(uN)
  if M and M.AddCharacter then M:AddCharacter(self.Object)
  else
    M = self:GetMedievalCraneFromBase(uO)
    if M and M.RemoveCharacter then M:RemoveCharacter(self.Object) end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(B)
  if not slua.isValid(B) or not B.GetOwner then return end
  local L = B:GetOwner()
  if not slua.isValid(L) or not L.AddCharacter then return end
  return L
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local ps = self:GetPlayerStateSafety()
  if not slua.isValid(ps) then return false end
  if ps.CanUseFlaregun == false and self:IsLocallyControlled() then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) then pc:DisplayGameTipWithMsgID(48532) end
  end
  return not ps.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue() self:HandleNearDeathGiveupRescue() end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local c = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(c) and self.bCanNearDeathGiveup == true then
    local ps = self:GetPlayerStateSafety()
    if slua.isValid(ps) then ps:AddGeneralCount(1613, 1, false) end
    c:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(id)
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then self:MulticastRPC_GmPlayAction(id) end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(id)
  if not Client then return end
  local c = self:GetPlayEmoteComponent()
  if not slua.isValid(c) then return end
  local LF = require("common.log_filter")
  LF.SetLogTreeEnable(true)
  local cfg = CDataTable.GetTableData("EmoteBPTable", id)
  if not cfg then return end
  local H = slua.loadObject(cfg.Path)
  local A = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local h = H()
  c:OnLoadEmoteAssetBegin(h, id, A, "")
  local tb = FuncUtil.LuaArrayToTable(A)
  local AU = require("common.asset_util")
  local function done() c:OnLoadEmoteAssetEnd(h, id, 0) end
  AU.GetAssetsArrayAsyncParallel(tb, done)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(v)
  if slua.isValid(self.ParachuteComponent) then self.ParachuteComponent.bServerSyncShouldCheckPassWall = v end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(b)
  self.Super:OnPlayerLeaveCarryBoxState(b)
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(b) end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(box)
  if slua.isValid(box) and Game:IsClassOf(box, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(box)
  end
end

function BRPlayerCharacterBase:SetAreaID(id) self:SetAttrValue("AreaID", id, -1) end
function BRPlayerCharacterBase:GetAreaID() return math.floor(self:GetAttrValue("AreaID") + 0.5) end
function BRPlayerCharacterBase:CannotChangeIntoPetSpectator() return self.bCannotChangeIntoPetSpectator end

function BRPlayerCharacterBase:DoModChangeToBT()
  if self:HasState(EPawnState.SpecialSuit) then self:TriggerEntrySkillWithID(4301101, true) end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local W = self:GetWeaponBySlot(Slot)
    if slua.isValid(W) then
      local id = W:GetWeaponID()
      local cfg = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if cfg and cfg.CheckIsWeaponInBlackList and cfg.CheckIsWeaponInBlackList(id) then
        local pc = self:GetPlayerControllerSafety()
        if Client and slua.isValid(pc) and pc.Role == ENetRole.ROLE_AutonomousProxy then pc:DisplayGameTipWithMsgID(47306) end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local S = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(S) then
      local st = S:GetCurMoveState()
      if st == ESpiderSwingMoveState.Launching or st == ESpiderSwingMoveState.Swinging then return false end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- Emote resolve
local VICTORY_DANCE_FX_MAP = { [12219601] = 22010089 }
local isFitVersion = false
pcall(function()
  local P = require("client.slua.config.ClientMacros.PublishRegionMacros")
  if P and type(P.IsFITVersion) == "function" then isFitVersion = P.IsFITVersion() end
end)

local ResolveEmoteResID = function(ItemID)
  local FxID = VICTORY_DANCE_FX_MAP[ItemID]
  if not FxID or FxID == ItemID then return ItemID end
  local mu = nil
  pcall(function() mu = require("client.common.model_util") end)
  if not mu then return ItemID end
  local bp = nil
  pcall(function() bp = mu.GetBPID(FxID) end)
  local r = ItemID
  if bp and bp > 0 and mu.IsBattleItemHandleExist and mu.IsBattleItemHandleExist("Emote", bp, false, false) then r = FxID end
  if isFitVersion and r == 12219601 then return 12222069 end
  return r
end

function BRPlayerCharacterBase:GetEmoteHandlePath(id)
  local r = ResolveEmoteResID(id)
  if self.Super then return self.Super:GetEmoteHandlePath(r) end
  local mu = nil
  pcall(function() mu = require("client.common.model_util") end)
  if not mu then return "" end
  local bp = nil
  pcall(function() bp = mu.GetBPID(r) end)
  if not bp or bp <= 0 then return "" end
  local p = nil
  pcall(function() p = mu.GetPath("Emote", bp, false, false) end)
  return p or ""
end

function BRPlayerCharacterBase:GetEmoteHandle(id)
  local r = ResolveEmoteResID(id)
  if self.Super then return self.Super:GetEmoteHandle(r) end
  local mu = nil
  pcall(function() mu = require("client.common.model_util") end)
  if not mu then return nil end
  local bp = nil
  pcall(function() bp = mu.GetBPID(r) end)
  if not bp or bp <= 0 then return nil end
  local C = nil
  pcall(function() C = mu.GetClass("Emote", bp, false, false) end)
  if not C then return nil end
  local h = nil
  pcall(function() h = C() end)
  if not h or not slua.isValid(h) then return nil end
  return h
end

-- ==========================================
-- ESP SYSTEM — NO GHOSTING
-- ==========================================
local ESP_Enabled = true

local FVector2D = _G.FVector2D or import("Vector2D")
local FLinearColor = _G.FLinearColor or import("LinearColor")
local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local SlateColor = nil
local GameplayStaticsESP = nil
pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") end)
pcall(function() SlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
pcall(function() GameplayStaticsESP = import("GameplayStatics") end)

local function ESPValid(obj)
  if obj == nil then return false end
  local ok, v = pcall(function() return slua.isValid(obj) end)
  return ok and v == true
end

local function ESPV2(x, y)
  if FVector2D then return FVector2D(x, y) end
  return { X = x, Y = y }
end

local function ESPMKC(r, g, b, a)
  if FLinearColor then return FLinearColor(r, g, b, a) end
  return { R = r, G = g, B = b, A = a }
end

local CFG = {
  MaxTracked = 30,
  ScreenMargin = 150,
  TopTextY = 6.0,
  SnapOriginY = 0.0,
  SnapThickness = 1.8,
  BoxMinWidth = 22,
  BoxMaxWidth = 320,
  BoxWidthFactor = 0.62,
  SideBarWidth = 3.5,
  SideBgAlpha = 0.55,
  NameFontSize = 15,
  DistFontSize = 13,
  StateFontSize = 13,
  CounterFontSize = 17,
  CounterW = 300.0,
  CounterH = 28.0,
  DeadZone = 0.05,
  SizeHyst = 2.0,
}

local C_WHITE  = ESPMKC(1.0, 1.0, 1.0, 1.0)
local C_BLACK  = ESPMKC(0.0, 0.0, 0.0, 1.0)
local C_GREEN  = ESPMKC(0.12, 1.0, 0.25, 1.0)
local C_RED    = ESPMKC(1.0, 0.15, 0.15, 1.0)

local TEAM_COLORS = {
  ESPMKC(0.20, 0.65, 1.00, 1.00),
  ESPMKC(1.00, 0.28, 0.28, 1.00),
  ESPMKC(0.25, 0.90, 0.40, 1.00),
  ESPMKC(1.00, 0.72, 0.18, 1.00),
  ESPMKC(0.72, 0.40, 1.00, 1.00),
  ESPMKC(0.10, 0.88, 0.85, 1.00),
  ESPMKC(1.00, 0.42, 0.78, 1.00),
  ESPMKC(0.72, 0.82, 0.92, 1.00),
}

local function TeamColor(tid, bot, fb)
  local n = tonumber(tid)
  if n then n = math.abs(math.floor(n))
  else
    local s = tostring(fb or "x")
    local h = 0
    for i = 1, #s do h = (h*31 + string.byte(s, i)) % 2147483647 end
    n = h
  end
  return TEAM_COLORS[(n % #TEAM_COLORS) + 1]
end

local function RND(v) if v ~= v then return 0 end return math.floor(v + 0.5) end
local function Lerp(a, b, t) return a + (b - a) * t end

local function HealthColor(p)
  p = tonumber(p) or 1.0
  if p < 0 then p = 0 end
  if p > 1 then p = 1 end
  local r, g, b
  if p >= 0.7 then local t=(p-0.7)/0.3 r=Lerp(0.75,0.12,t) g=1.0 b=Lerp(0.15,0.25,t)
  elseif p >= 0.4 then local t=(p-0.4)/0.3 r=1.0 g=Lerp(0.45,0.95,t) b=Lerp(0.45,0.20,t)
  else local t=p/0.4 r=1.0 g=Lerp(0.15,0.45,t) b=Lerp(0.15,0.45,t) end
  return ESPMKC(r, g, b, 1.0)
end

local ESP = {}
ESP.Canvas = nil
ESP.Lines = {}
ESP.HealthBg = {}
ESP.HealthFill = {}
ESP.Infos = {}
ESP.Counter = nil
ESP.EnemyCache = {}
ESP.ScaleX = 1.0
ESP.ScaleY = 1.0
ESP.OffsetX = 0.0
ESP.OffsetY = 0.0
ESP.ViewW = 1920
ESP.ViewH = 1080

-- CRITICAL FIXES
ESP.ScanInterval = 0.6
ESP.LightInterval = 0.03        -- 33fps update
ESP.TransformInterval = 0.15    -- 6-7x/sec scale refresh (was 2s — root ghost cause)

ESP.LastScan = -999.0
ESP.LastTransform = -999.0
ESP.LastWorld = nil
ESP.bActive = false

function ESP.GetGameplayData()
  if ESP._GDP then return ESP._GDP end
  local ok, G = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
  if ok and G then ESP._GDP = G return G end
  return nil
end

function ESP.GetController()
  local pc = nil
  pcall(function()
    local G = ESP.GetGameplayData()
    if G and G.GetPlayerController then pc = G.GetPlayerController() end
  end)
  if not ESPValid(pc) then
    pcall(function()
      if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
    end)
  end
  return ESPValid(pc) and pc or nil
end

function ESP.GetLocalCharacter()
  local c = nil
  pcall(function()
    local G = ESP.GetGameplayData()
    if G then
      if G.GetPlayerCharacter then c = G.GetPlayerCharacter() end
      if not ESPValid(c) and G.GetLocalCharacter then c = G.GetLocalCharacter() end
    end
  end)
  if not ESPValid(c) then
    local pc = ESP.GetController()
    pcall(function() if pc and pc.GetPawn then c = pc:GetPawn() end end)
  end
  return ESPValid(c) and c or nil
end

function ESP.GetAllCharacters()
  local out = {}
  local function mg(cs)
    if not cs then return end
    for k, ch in pairs(cs) do
      if ch and slua.isValid(ch) then
        local pk = k
        pcall(function()
          if not pk and ch.GetPlayerKey then pk = ch:GetPlayerKey() end
          if not pk and ch.PlayerKey then pk = ch.PlayerKey end
        end)
        if pk then out[pk] = ch end
      end
    end
  end
  pcall(function() if Game and Game.GetAllPlayerPawns then mg(Game:GetAllPlayerPawns()) end end)
  pcall(function() local G = ESP.GetGameplayData() if G and G.GetAllCharacters then mg(G:GetAllCharacters()) end end)
  pcall(function()
    local GS = require("GameLua.GameCore.Data.CGameState")
    if GS and GS.GetAllCharacters then mg(GS:GetAllCharacters()) end
  end)
  return out
end

function ESP.GetTeamID(c)
  if not ESPValid(c) then return nil end
  local id = nil
  pcall(function() if c.GetTeamID then id = c:GetTeamID() end end)
  if id == nil then pcall(function() id = c.TeamID end) end
  if id == nil then
    local ps = nil
    pcall(function()
      if c.GetPlayerStateSafety then ps = c:GetPlayerStateSafety()
      elseif c.GetPlayerState then ps = c:GetPlayerState() end
    end)
    if not ESPValid(ps) then pcall(function() ps = c.PlayerState end) end
    if ESPValid(ps) then
      pcall(function() if ps.GetTeamID then id = ps:GetTeamID() end end)
      if id == nil then pcall(function() id = ps.TeamID end) end
    end
  end
  return id
end

function ESP.IsAlive(c)
  if not ESPValid(c) then return false end
  local a = nil
  pcall(function() if c.IsAlive then a = c:IsAlive() end end)
  if type(a) == "boolean" then return a end
  local hp = nil
  pcall(function() hp = c.Health end)
  if type(hp) ~= "number" then pcall(function() hp = c.HP end) end
  if type(hp) == "number" then return hp > 0 end
  return true
end

function ESP.IsBot(c)
  if not ESPValid(c) then return false end
  local b = false
  pcall(function()
    if Game and Game.IsAI then b = Game:IsAI(c) end
    if not b then
      if c.bEnsure == true or c.bMEnsure == true then b = true
      elseif c.PlayerState and c.PlayerState.bPSEnsure == true then b = true
      elseif c.Controller then
        if c.Controller.IsMLAI == true or c.Controller.FakePlayerBornType == 1 then b = true end
      end
    end
  end)
  if not b then pcall(function() if c.bIsAI == true then b = true end end) end
  return b
end

function ESP.GetPlayerKey(c)
  local k = nil
  pcall(function() if c.GetPlayerKey then k = c:GetPlayerKey() end end)
  if k == nil then pcall(function() k = c.PlayerKey end) end
  return tostring(k or c)
end

function ESP.GetHealthPct(c)
  if not ESPValid(c) then return 1.0 end
  local hp, mx = nil, nil
  pcall(function() hp = c.Health end)
  if type(hp) ~= "number" then pcall(function() hp = c.HP end) end
  pcall(function() mx = c.MaxHealth end)
  if type(mx) ~= "number" then pcall(function() mx = c.MaxHP end) end
  if type(hp) ~= "number" then return 1.0 end
  if type(mx) ~= "number" or mx <= 0 then mx = 100 end
  local p = hp / mx
  if p ~= p then return 1.0 end
  if p < 0 then p = 0 end
  if p > 1 then p = 1 end
  return p
end

local function NN(v)
  if v == nil or v == false then return nil end
  local ok, t = pcall(tostring, v)
  if not ok or not t then return nil end
  t = t:gsub("^%s+", ""):gsub("%s+$", "")
  if t == "" or t == "nil" or t == "None" or t == "NULL" then return nil end
  return t
end

function ESP.ResolveName(c, bot)
  if bot then return "Bot" end
  local n = nil
  local function tk(v) if not n then n = NN(v) end end
  pcall(function() if c.GetPlayerNameSafety then tk(c:GetPlayerNameSafety()) end end)
  pcall(function() if not n and c.GetPlayerName then tk(c:GetPlayerName()) end end)
  pcall(function() if not n then tk(c.PlayerName) end end)
  return n or "Player"
end

function ESP.ActorLocation(c)
  local l = nil
  if not ESPValid(c) then return nil end
  pcall(function()
    if c.K2_GetActorLocation then l = c:K2_GetActorLocation()
    elseif Game and Game.GetActorLocation then l = Game:GetActorLocation(c) end
  end)
  return l
end

function ESP.DistMeters(a, b)
  if not a or not b then return math.huge end
  local dx, dy, dz = a.X-b.X, a.Y-b.Y, a.Z-b.Z
  return math.sqrt(dx*dx + dy*dy + dz*dz) / 100.0
end

function ESP.GetVerticalBounds(c)
  if not ESPValid(c) then return nil, nil end
  local ct, hh = nil, nil
  local cap = nil
  pcall(function()
    if c.GetCapsuleComponent then cap = c:GetCapsuleComponent()
    elseif c.CapsuleComponent then cap = c.CapsuleComponent end
  end)
  if cap and ESPValid(cap) then
    pcall(function()
      if cap.K2_GetComponentLocation then ct = cap:K2_GetComponentLocation()
      elseif cap.GetComponentLocation then ct = cap:GetComponentLocation() end
      if cap.GetScaledCapsuleHalfHeight then hh = cap:GetScaledCapsuleHalfHeight()
      elseif cap.GetUnscaledCapsuleHalfHeight then hh = cap:GetUnscaledCapsuleHalfHeight()
      elseif cap.CapsuleHalfHeight then hh = cap.CapsuleHalfHeight end
    end)
  end
  if not ct then pcall(function() if c.K2_GetActorLocation then ct = c:K2_GetActorLocation() end end) end
  if not ct then return nil, nil end
  if not hh or hh < 10 or hh > 200 then hh = 85 end
  return ct, hh
end

function ESP.GetHeadFeet(c)
  local ct, hh = ESP.GetVerticalBounds(c)
  if not ct or not hh then return nil, nil end
  return { X=ct.X, Y=ct.Y, Z=ct.Z+hh }, { X=ct.X, Y=ct.Y, Z=ct.Z-hh }
end

function ESP.Now()
  local t = nil
  pcall(function()
    local w = (slua and slua.getWorld and slua.getWorld()) or nil
    if GameplayStaticsESP and w and GameplayStaticsESP.GetRealTimeSeconds then
      t = GameplayStaticsESP.GetRealTimeSeconds(w)
    end
  end)
  if tonumber(t) then return tonumber(t) end
  pcall(function() if os and os.clock then t = os.clock() end end)
  return tonumber(t) or 0.0
end

function ESP.World()
  local w = nil
  pcall(function() if slua and slua.getWorld then w = slua.getWorld() end end)
  return w
end

function ESP.GetCanvas()
  if ESPValid(ESP.Canvas) then return ESP.Canvas end
  local root = nil
  pcall(function()
    local T = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
    if T and T.GetMainControlBaseUI then root = T.GetMainControlBaseUI() end
  end)
  if not ESPValid(root) then return nil end
  local c = nil
  pcall(function()
    if ESPValid(root.CanvasPanel_0) then c = root.CanvasPanel_0
    elseif ESPValid(root.CanvasPanel_42) then c = root.CanvasPanel_42 end
  end)
  if ESPValid(c) then ESP.Canvas = c return c end
  return nil
end

-- CRITICAL: refresh scale every 0.15s — stale scale = ghosting
function ESP.UpdateCanvasTransform(pc)
  local cnv = ESP.GetCanvas()
  if not ESPValid(cnv) then return false end
  local ok = false
  pcall(function()
    if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
      local geo = cnv:GetCachedGeometry()
      if geo then
        local p0 = SlateBlueprintLibrary.AbsoluteToLocal(geo, ESPV2(0,0))
        local p1 = SlateBlueprintLibrary.AbsoluteToLocal(geo, ESPV2(100,100))
        if p0 and p1 and tonumber(p0.X) and tonumber(p1.X) and p1.X ~= p0.X and p1.Y ~= p0.Y then
          local nx = (p1.X-p0.X)/100.0
          local ny = (p1.Y-p0.Y)/100.0
          if math.abs(nx - ESP.ScaleX) > 0.001 or math.abs(ny - ESP.ScaleY) > 0.001 then
            ESP.ScaleX = nx ESP.ScaleY = ny
            ESP.OffsetX = p0.X ESP.OffsetY = p0.Y
            -- invalidate cached positions so every widget re-projects
            for _, d in pairs(ESP.Lines) do d.x1 = nil end
            for _, d in pairs(ESP.HealthBg) do d.x1 = nil end
            for _, d in pairs(ESP.HealthFill) do d.x1 = nil end
          end
          ok = true
        end
      end
    end
  end)
  if not ok then
    local s = 1.0
    pcall(function()
      if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
        local v = WidgetLayoutLibrary.GetViewportScale(pc)
        if tonumber(v) and v > 0 then s = v end
      end
    end)
    local ns = 1.0/s
    if math.abs(ns - ESP.ScaleX) > 0.001 then
      ESP.ScaleX = ns ESP.ScaleY = ns ESP.OffsetX = 0 ESP.OffsetY = 0
      for _, d in pairs(ESP.Lines) do d.x1 = nil end
      for _, d in pairs(ESP.HealthBg) do d.x1 = nil end
      for _, d in pairs(ESP.HealthFill) do d.x1 = nil end
    end
  end
  return true
end

function ESP.Viewport(pc)
  local w, h = 1920.0, 1080.0
  pcall(function()
    if pc and pc.GetViewportSize then
      local v = ESPV2(0,0)
      pc:GetViewportSize(v)
      if v and tonumber(v.X) and v.X > 200 then w, h = v.X, v.Y end
    end
  end)
  return w, h
end

function ESP.Project(pc, wl)
  if not pc or not wl then return nil end
  local p = ESPV2(0,0)
  local ok = false
  pcall(function()
    local r = pc:ProjectWorldLocationToScreen(wl, p, true)
    ok = (r == true or r == 1 or (p and (p.X ~= 0 or p.Y ~= 0)))
  end)
  if not ok then return nil end
  return ESPV2(p.X*(ESP.ScaleX or 1)+(ESP.OffsetX or 0), p.Y*(ESP.ScaleY or 1)+(ESP.OffsetY or 0)), p
end

function ESP.SetFont(w, sz)
  if not ESPValid(w) then return end
  pcall(function()
    local f = w.Font
    if f then
      f.Size = sz
      if f.OutlineSettings then
        pcall(function() f.OutlineSettings.OutlineSize = 1 end)
        pcall(function() f.OutlineSettings.OutlineColor = C_BLACK end)
      end
      w:SetFont(f)
    end
    if w.SetShadowOffset then w:SetShadowOffset(ESPV2(1,1)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(C_BLACK) end
  end)
end

function ESP.SetColor(w, c)
  if not ESPValid(w) then return end
  pcall(function()
    if SlateColor then w:SetColorAndOpacity(SlateColor(c))
    else w:SetColorAndOpacity(c) end
  end)
end

function ESP.NewLine(c, z)
  local cnv = ESP.GetCanvas()
  if not ESPValid(cnv) then return nil end
  local b = nil
  pcall(function() b = CGame:NewObjectFromPath("/Script/UMG.Border", cnv) end)
  if not ESPValid(b) then return nil end
  pcall(function()
    b:SetBrushColor(c)
    b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    b:SetRenderTransformPivot(ESPV2(0,0.5))
  end)
  local s = nil
  pcall(function() s = cnv:AddChildToCanvas(b) end)
  if not s then pcall(function() b:RemoveFromParent() end) return nil end
  pcall(function() s:SetAutoSize(false) s:SetZOrder(z or 30) end)
  return { W = b, S = s }
end

-- CRITICAL: always re-set visibility + always update when position changed
function ESP.Line(d, x1, y1, x2, y2, th)
  if not d or not ESPValid(d.W) or not d.S then return false end
  if x1~=x1 or y1~=y1 or x2~=x2 or y2~=y2 then return false end
  x1, y1, x2, y2 = RND(x1), RND(y1), RND(x2), RND(y2)
  local dz = CFG.DeadZone
  local same = (d.x1==x1 and d.y1==y1 and d.x2==x2 and d.y2==y2 and d.th==th)
  if same and d.hid ~= true then
    -- still force visibility in case game hid it
    pcall(function() d.W:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    return true
  end
  local dx, dy = x2-x1, y2-y1
  local ln = math.sqrt(dx*dx+dy*dy)
  if ln < 1 then ESP.Hide(d) return false end
  local ang = ((math.atan2 and math.atan2(dy,dx)) or math.atan(dy,dx))*180.0/math.pi
  ang = math.floor(ang*10+0.5)/10
  ln = RND(ln)
  local ok = pcall(function()
    d.S:SetPosition(ESPV2(x1, y1-th*0.5))
    d.S:SetSize(ESPV2(ln, th))
    d.W:SetRenderAngle(ang)
    d.W:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if ok then d.x1,d.y1,d.x2,d.y2,d.th = x1,y1,x2,y2,th d.hid = false end
  return true
end

function ESP.Hide(d)
  if d and ESPValid(d.W) and d.hid ~= true then
    pcall(function() d.W:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    d.hid = true
    d.x1,d.y1,d.x2,d.y2,d.th = nil,nil,nil,nil,nil
  end
end

function ESP.SetBrush(d, c, ck)
  if not d or not ESPValid(d.W) then return end
  if ck and d.ck == ck then return end
  pcall(function() d.W:SetBrushColor(c) end)
  if ck then d.ck = ck end
end

function ESP.Destroy(d)
  if not d then return end
  local w = d.W or d.C
  if ESPValid(w) then
    pcall(function() w:RemoveFromParent() end)
    pcall(function() w:ConditionalBeginDestroy() end)
  end
end

function ESP.CreateCounter()
  local cnv = ESP.GetCanvas()
  if not ESPValid(cnv) then return nil end
  local c = nil
  pcall(function() c = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", cnv) end)
  if not ESPValid(c) then return nil end
  local t = nil
  pcall(function() t = CGame:NewObjectFromPath("/Script/UMG.TextBlock", c) end)
  if not ESPValid(t) then ESP.Destroy({ W = c }) return nil end
  pcall(function()
    t:SetText("Players: 0 | Bots: 0")
    t:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if t.SetJustification then t:SetJustification(1) end
  end)
  ESP.SetColor(t, C_WHITE)
  ESP.SetFont(t, CFG.CounterFontSize)
  local ts, ms = nil, nil
  pcall(function() ts = c:AddChildToCanvas(t) end)
  pcall(function() ms = cnv:AddChildToCanvas(c) end)
  if not ts or not ms then ESP.Destroy({ W = c }) return nil end
  local W, H = CFG.CounterW, CFG.CounterH
  pcall(function()
    ts:SetAutoSize(true) ts:SetAlignment(ESPV2(0.5,0.5))
    ts:SetPosition(ESPV2(W*0.5,H*0.5)) ts:SetZOrder(5)
    ms:SetAutoSize(false) ms:SetAlignment(ESPV2(0.5,0.0))
    ms:SetSize(ESPV2(W,H)) ms:SetZOrder(60)
  end)
  return { C = c, T = t, S = ms, W = W, H = H }
end

function ESP.CenterX(viewW)
  local cw = nil
  pcall(function()
    local cnv = ESP.GetCanvas()
    if ESPValid(cnv) then
      local g = cnv:GetCachedGeometry()
      if g and g.GetLocalSize then
        local s = g:GetLocalSize()
        if s and tonumber(s.X) and s.X > 1 then cw = tonumber(s.X) end
      end
    end
  end)
  if tonumber(cw) and cw > 1 then return cw * 0.5 end
  return (viewW * 0.5) * (ESP.ScaleX or 1) + (ESP.OffsetX or 0)
end

function ESP.UpdateCounter(np, nb, viewW)
  local d = ESP.Counter
  if not d or not ESPValid(d.C) then
    ESP.Destroy(d)
    d = ESP.CreateCounter()
    ESP.Counter = d
  end
  if not d then
    local cx = RND((viewW * 0.5) * (ESP.ScaleX or 1) + (ESP.OffsetX or 0))
    return ESPV2(cx, CFG.SnapOriginY)
  end
  local lab = string.format("Players: %d | Bots: %d", np or 0, nb or 0)
  pcall(function()
    if d.L ~= lab then d.T:SetText(lab) d.L = lab end
  end)
  local cx = ESP.CenterX(viewW)
  if not cx then cx = (viewW * 0.5) * (ESP.ScaleX or 1) + (ESP.OffsetX or 0) end
  cx = RND(cx)
  if d.px == nil or math.abs(d.px - cx) >= 1.0 then
    d.px = cx
    pcall(function() d.S:SetPosition(ESPV2(cx, CFG.TopTextY)) end)
  end
  pcall(function() d.C:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
  return ESPV2(cx, CFG.SnapOriginY)
end

function ESP.CreateInfo()
  local cnv = ESP.GetCanvas()
  if not ESPValid(cnv) then return nil end
  local c, tb, tn, td, ts = nil, nil, nil, nil, nil
  pcall(function() c = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", cnv) end)
  if not ESPValid(c) then return nil end
  pcall(function() tb = CGame:NewObjectFromPath("/Script/UMG.Border", c) end)
  pcall(function() tn = CGame:NewObjectFromPath("/Script/UMG.TextBlock", c) end)
  pcall(function() td = CGame:NewObjectFromPath("/Script/UMG.TextBlock", c) end)
  pcall(function() ts = CGame:NewObjectFromPath("/Script/UMG.TextBlock", c) end)
  if not ESPValid(tb) or not ESPValid(tn) or not ESPValid(td) or not ESPValid(ts) then
    ESP.Destroy({ W = c })
    return nil
  end
  pcall(function()
    tb:SetBrushColor(TEAM_COLORS[1]) tb:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tn:SetText("Player") td:SetText("0m") ts:SetText("")
    tn:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    td:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    ts:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if tn.SetJustification then tn:SetJustification(1) end
    if td.SetJustification then td:SetJustification(1) end
    if ts.SetJustification then ts:SetJustification(1) end
  end)
  ESP.SetColor(tn, C_WHITE) ESP.SetColor(td, C_WHITE) ESP.SetColor(ts, C_GREEN)
  ESP.SetFont(tn, CFG.NameFontSize) ESP.SetFont(td, CFG.DistFontSize) ESP.SetFont(ts, CFG.StateFontSize)
  local bs, ns, s2, s3, ms = nil, nil, nil, nil, nil
  pcall(function() bs = c:AddChildToCanvas(tb) end)
  pcall(function() ns = c:AddChildToCanvas(tn) end)
  pcall(function() s2 = c:AddChildToCanvas(td) end)
  pcall(function() s3 = c:AddChildToCanvas(ts) end)
  pcall(function() ms = cnv:AddChildToCanvas(c) end)
  if not bs or not ns or not s2 or not s3 or not ms then
    ESP.Destroy({ W = c })
    return nil
  end
  pcall(function()
    bs:SetAutoSize(false) bs:SetSize(ESPV2(120,22)) bs:SetAlignment(ESPV2(0.5,0.5)) bs:SetZOrder(34)
    ns:SetAutoSize(false) ns:SetSize(ESPV2(120,22)) ns:SetAlignment(ESPV2(0.5,0.5)) ns:SetZOrder(36)
    s2:SetAutoSize(true) s2:SetAlignment(ESPV2(0.5,0.5)) s2:SetZOrder(36)
    s3:SetAutoSize(true) s3:SetAlignment(ESPV2(0.5,0.5)) s3:SetZOrder(36)
    ms:SetAutoSize(false) ms:SetZOrder(35)
  end)
  return { C=c, TB=tb, N=tn, D=td, S=ts, S0=bs, S1=ns, S2=s2, S3=s3, Slot=ms }
end

function ESP.UpdateInfo(k, c, bot, tid, dm, hx, hy)
  local d = ESP.Infos[k]
  if not d or not ESPValid(d.C) then
    ESP.Destroy(d)
    d = ESP.CreateInfo()
    ESP.Infos[k] = d
  end
  if not d then return end
  local n = d.CN
  if not n then n = ESP.ResolveName(c, bot) d.CN = n end
  if bot then n = "Bot" d.CN = "Bot" end
  local dl = string.format("%dm", math.max(0, math.floor((tonumber(dm) or 0)+0.5)))
  local tc = TeamColor(tid, bot, k)
  pcall(function()
    if d.LN ~= n then d.N:SetText(n) d.LN = n end
    if d.LD ~= dl then d.D:SetText(dl) d.LD = dl end
    if d.LT ~= tostring(tid)..":"..tostring(bot) then d.TB:SetBrushColor(tc) d.LT = tostring(tid)..":"..tostring(bot) end
  end)
  local bw, bh = 100.0, 22.0
  local bx, by = RND(hx), RND(hy - 18.0)
  pcall(function()
    d.Slot:SetPosition(ESPV2(bx, by))
    d.Slot:SetSize(ESPV2(bw, 70.0))
    d.S0:SetPosition(ESPV2(0,0)) d.S0:SetSize(ESPV2(bw,bh))
    d.S1:SetPosition(ESPV2(0,0)) d.S1:SetSize(ESPV2(bw,bh))
    d.S2:SetPosition(ESPV2(bw*0.5, bh+12)) d.S3:SetPosition(ESPV2(bw*0.5, bh+30))
    d.C:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
end

function ESP.HBgk(k)
  local d = ESP.HealthBg[k]
  if d and ESPValid(d.W) then return d end
  d = ESP.NewLine(ESPMKC(0,0,0,CFG.SideBgAlpha), 31) ESP.HealthBg[k] = d return d
end

function ESP.HFlk(k)
  local d = ESP.HealthFill[k]
  if d and ESPValid(d.W) then return d end
  d = ESP.NewLine(C_GREEN, 32) ESP.HealthFill[k] = d return d
end

function ESP.HBar(k, p, x, y, w)
  local bg = ESP.HBgk(k) local fl = ESP.HFlk(k)
  if not bg or not fl then return end
  w = math.max(1, tonumber(w) or 1)
  ESP.Line(bg, x, y, x+w, y, CFG.SideBarWidth)
  p = tonumber(p) or 1.0
  if p < 0 then p = 0 end
  if p > 1 then p = 1 end
  local bk
  if p >= 0.7 then bk = "g"..math.floor(p*20+0.5)
  elseif p >= 0.4 then bk = "y"..math.floor(p*20+0.5)
  else bk = "r"..math.floor(p*20+0.5) end
  ESP.SetBrush(fl, HealthColor(p), bk)
  local fw = w * p
  if fw < 1 then ESP.Hide(fl) return end
  ESP.Line(fl, x, y, x+fw, y, CFG.SideBarWidth)
end

function ESP.Snap(k)
  local d = ESP.Lines[k]
  if d and ESPValid(d.W) then return d end
  d = ESP.NewLine(C_GREEN, 30) ESP.Lines[k] = d return d
end

function ESP.HideTarget(k)
  ESP.Hide(ESP.HealthBg[k]) ESP.Hide(ESP.HealthFill[k]) ESP.Hide(ESP.Lines[k])
  local inf = ESP.Infos[k]
  if inf and ESPValid(inf.C) then pcall(function() inf.C:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end
end

function ESP.Reset()
  for _, d in pairs(ESP.Lines) do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthBg) do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthFill) do ESP.Destroy(d) end
  for _, d in pairs(ESP.Infos) do ESP.Destroy(d) end
  ESP.Lines = {} ESP.HealthBg = {} ESP.HealthFill = {} ESP.Infos = {}
  if ESP.Counter then ESP.Destroy(ESP.Counter) end
  ESP.Counter = nil ESP.Canvas = nil ESP.EnemyCache = {}
end

function ESP.Scan()
  local pc = ESP.GetController()
  local me = ESP.GetLocalCharacter()
  if not pc or not me then ESP.EnemyCache = {} return pc, 0, 0 end
  local ml = ESP.ActorLocation(me)
  if not ml then ESP.EnemyCache = {} return pc, 0, 0 end
  local mt = ESP.GetTeamID(me)
  local list = {}
  local nR, nB = 0, 0
  local all = ESP.GetAllCharacters()
  local seen = {}
  for _, ch in pairs(all) do
    if ESPValid(ch) and ch ~= me and ESP.IsAlive(ch) then
      local k = ESP.GetPlayerKey(ch)
      if not seen[k] then
        local t = ESP.GetTeamID(ch)
        if not (mt ~= nil and t ~= nil and tostring(t) == tostring(mt)) then
          local l = ESP.ActorLocation(ch)
          local dm = ESP.DistMeters(ml, l)
          seen[k] = true
          local b = ESP.IsBot(ch)
          if b then nB = nB+1 else nR = nR+1 end
          list[#list+1] = { C=ch, K=k, B=b, T=t, D=dm }
        end
      end
    end
  end
  table.sort(list, function(a,b) return (a.D or 99999) < (b.D or 99999) end)
  local tr = {}
  for i, it in ipairs(list) do if i > CFG.MaxTracked then break end tr[#tr+1] = it end
  ESP.EnemyCache = tr
  return pc, nR, nB
end

function ESP.Update()
  if not ESP_Enabled then return end

  local world = ESP.World()
  if world ~= ESP.LastWorld then
    ESP.Reset()
    ESP.LastWorld = world
    ESP.LastScan = -999.0
    ESP.LastTransform = -999.0
  end

  local cnv = ESP.GetCanvas()
  if not cnv then return end

  local now = ESP.Now()
  local pc = ESP.GetController()
  if not pc then return end

  if (now - ESP.LastScan) >= ESP.ScanInterval then
    local r, b
    pc, r, b = ESP.Scan()
    ESP.LastScan = now
    ESP.RC, ESP.BC = r or 0, b or 0
  end
  if not pc then return end

  -- CRITICAL: 0.15s interval — stale scale = ghost
  if (now - (ESP.LastTransform or -999.0)) >= ESP.TransformInterval then
    ESP.UpdateCanvasTransform(pc)
    ESP.LastTransform = now
  end

  local vw, vh = ESP.Viewport(pc)
  local h = CFG.SizeHyst
  if math.abs(vw - (ESP.ViewW or 0)) > h or math.abs(vh - (ESP.ViewH or 0)) > h then
    ESP.ViewW, ESP.ViewH = vw, vh
  else vw, vh = ESP.ViewW, ESP.ViewH end

  local origin = ESP.UpdateCounter(ESP.RC or 0, ESP.BC or 0, vw)

  local active = {}

  for _, it in ipairs(ESP.EnemyCache) do
    local c = it.C local k = it.K
    if ESPValid(c) and ESP.IsAlive(c) then
      local hd, ft = ESP.GetHeadFeet(c)
      if hd and ft then
        local hs, hp = ESP.Project(pc, hd)
        local fs, fp = ESP.Project(pc, ft)
        if hs and fs and hp and fp then
          local m = CFG.ScreenMargin
          local on = hp.X>-m and hp.X<vw+m and hp.Y>-m and hp.Y<vh+m
                     and fp.X>-m and fp.X<vw+m and fp.Y>-m and fp.Y<vh+m
          if on then
            local H = fs.Y - hs.Y
            if H >= 1 and H <= vh*1.5 then
              active[k] = true
              local W = H * CFG.BoxWidthFactor
              W = math.max(CFG.BoxMinWidth, math.min(CFG.BoxMaxWidth, W))
              local cx = (hs.X+fs.X)*0.5
              local L = cx - W*0.5
              local R = cx + W*0.5
              ESP.HBar(k, ESP.GetHealthPct(c), L, hs.Y+8, R-L)
              ESP.Line(ESP.Snap(k), origin.X, origin.Y, hs.X, hs.Y, CFG.SnapThickness)
              ESP.UpdateInfo(k, c, it.B, it.T, it.D, hs.X, hs.Y)
            end
          end
        end
      end
    end
  end

  for k in pairs(ESP.Lines) do if not active[k] then ESP.HideTarget(k) end end
  for k in pairs(ESP.HealthBg) do if not active[k] then ESP.HideTarget(k) end end
  for k in pairs(ESP.Infos) do
    if not active[k] then
      local inf = ESP.Infos[k]
      if inf and ESPValid(inf.C) then
        pcall(function() inf.C:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
      end
    end
  end
end

function ESP.Tick() pcall(ESP.Update) end

function ESP.AttachTimers()
  pcall(function()
    local pc = ESP.GetController()
    if ESPValid(pc) and pc.AddGameTimer then
      if ESP._TPC == pc and ESP._Th then return end
      ESP._TPC = pc ESP._Th = true
      pc:AddGameTimer(ESP.LightInterval or 0.03, true, function()
        if ESP.bActive then pcall(ESP.Tick) end
      end)
    else
      pcall(function()
        require("timer").SetGameTimer(2.0, false, function()
          ESP._Th = false ESP.AttachTimers()
        end)
      end)
    end
    pcall(function() require("timer").SetGameTimer(10.0, false, function() ESP.AttachTimers() end) end)
  end)
end

function ESP.Start()
  if ESP.bActive then return end
  ESP.bActive = true
  pcall(ESP.Update)
  ESP.AttachTimers()
end

-- Bypass
local function ApplyBypass()
  _G.ESP = nil
  _G.PlayerMapMarker = nil
  if io and io.open then
    local o = io.open
    io.open = function(p, m)
      if p and (string.find(p, "mod_chunk") or string.find(p, "skinios")) then return nil end
      return o(p, m)
    end
  end
  if Game and Game.ReadFile then
    local o = Game.ReadFile
    Game.ReadFile = function(self, p)
      if p and string.find(p, "mod_chunk") then return nil end
      return o(self, p)
    end
  end
  if os and os.getenv then
    local o = os.getenv
    os.getenv = function(k)
      local v = o(k)
      if v and (string.find(v, "magisk") or string.find(v, "supersu") or string.find(v, "root")) then return nil end
      return v
    end
  end
  local op = print
  print = function(...)
    local a = {...}
    if a[1] and type(a[1]) == "string" then
      if string.find(a[1], "ESP") or string.find(a[1], "PlayerMapMarker") then return end
    end
    op(...)
  end
end
pcall(ApplyBypass)

local function ESPLater(sec, fn)
  local tk = nil
  pcall(function() tk = require("common.time_ticker") end)
  if tk and tk.AddTimerOnce then pcall(function() tk.AddTimerOnce(sec, fn) end) return end
  pcall(function() require("timer").SetGameTimer(sec, false, fn) end)
end

local _spc = nil
local function ESPStartAll()
  pcall(function()
    local pc = nil
    if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
    if not ESPValid(pc) then pc = ESP.GetController() end
    if ESPValid(pc) then
      if pc ~= _spc then
        _spc = pc
        ESP._Th = false
        ESP._TPC = nil
        ESP.Start()
      else
        ESP.AttachTimers()
      end
    end
  end)
end

pcall(function()
  ESPStartAll()
  ESPLater(1.0, ESPStartAll)
end)
if not _G.__ESPLookTickStarted then
  _G.__ESPLookTickStarted = true
  ESP.bActive = true
  ESP.AttachTimers()
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
