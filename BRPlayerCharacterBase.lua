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
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", { AttrName = { "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1] = "FinishedState" }, self.HandleFinishedState, self)
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
    local EDynamicSimpleQueryConfigDisableMask = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(EDynamicSimpleQueryConfigDisableMask.Bit0, true)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState() end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI() end
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
  if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function BRPlayerCharacterBase:BPOnRespawned()
  if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
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
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then return end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then return end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then return end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        uCurPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then return end
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
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then uPlayerController:DisplayGameTipWithMsgID(48532) end
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
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then return end
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
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  local function loadLater() uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0) end
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt) end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID) self:SetAttrValue("AreaID", AreaID, -1) end
function BRPlayerCharacterBase:GetAreaID() return math.floor(self:GetAttrValue("AreaID") + 0.5) end
function BRPlayerCharacterBase:CannotChangeIntoPetSpectator() return self.bCannotChangeIntoPetSpectator end

function BRPlayerCharacterBase:DoModChangeToBT()
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
  end
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
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(SpiderSwingObj) then
      local nCurState = SpiderSwingObj:GetCurMoveState()
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ============================================================================
--  ESP MODULE  (fixed — safe imports, no dangling HitResult, no ghost traces,
--               single timer, no IsAlive native calls)
-- ============================================================================

local ESP_Enabled = true

-- IMPORTANT: correct UE asset paths, and never fall back to plain Lua tables.
local FVector2D, FLinearColor
pcall(function() FVector2D = _G.FVector2D or import("/Script/CoreUObject.Vector2D") end)
pcall(function() FLinearColor = _G.FLinearColor or import("/Script/CoreUObject.LinearColor") end)

if not FVector2D or not FLinearColor then
  print("[ESP] Disabled: Vector2D/LinearColor unavailable")
  ESP_Enabled = false
end

local SlateBlueprintLibrary, WidgetLayoutLibrary, SlateColor, GameplayStaticsESP
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
  if not FVector2D then return nil end
  local ok, v = pcall(function() return FVector2D(x, y) end)
  return ok and v or nil
end

local function ESPMKC(r, g, b, a)
  if not FLinearColor then return nil end
  local ok, v = pcall(function() return FLinearColor(r, g, b, a) end)
  return ok and v or nil
end

-- ============================================================================
--  CONFIG
-- ============================================================================
local CFG = {
  MaxDistance            = 100000,  -- 1000 m hard cap (scan filter)
  RenderTrackingDistance = 80000,   -- 800 m render distance
  MaxTracked             = 20,      -- fewer targets = less widget churn
  ScreenMargin           = 500,
  TopTextY               = 6.0,
  SnapOriginY            = 0.0,
  SnapThickness          = 1.8,
  CornerThickness        = 2.2, CornerLen = 0.28, CornerMin = 6, CornerMax = 28,
  BoxMinWidth            = 22, BoxMaxWidth = 320, BoxMinHeight = 1,
  BoxWidthFactor         = 0.62, WidthScale = 1.22, HeadExtra = 0.06, FootExtra = 0.02,
  SideBarWidth           = 3.5, SideBarGap = 5.0, SideBgAlpha = 0.55,
  MarkGap                = 8.0, MarkW = 15.0, MarkH = 10.0, MarkGapV = 6.0, MarkThickness = 2.4,
  NameFontSize           = 15, DistFontSize = 13, StateFontSize = 13, TextGap = 1.0,
  CounterFontSize        = 17, CounterW = 300.0, CounterH = 28.0,
  DeadZone               = 0.5,
  LightInterval          = 0.033,   -- 30 fps — visually identical, half the load
  ScanInterval           = 0.15,    -- 6.7 Hz
  TransformInterval      = 0.05,    -- 20 Hz
  VisInterval            = 0.20,    -- 5 Hz
  SizeHyst               = 2.0,
  UseVisibility          = false,   -- ← tracing off by default (was #1 crasher)
  VisibilityMaxDist      = 60000,
}

local C_WHITE  = ESPMKC(1.0, 1.0, 1.0, 1.0)
local C_BLACK  = ESPMKC(0.0, 0.0, 0.0, 1.0)
local C_GREEN  = ESPMKC(0.12, 1.0, 0.25, 1.0)
local C_RED    = ESPMKC(1.0, 0.15, 0.15, 1.0)
local C_YELLOW = ESPMKC(1.0, 0.90, 0.30, 1.0)
local C_BLUE   = ESPMKC(0.38, 0.72, 1.0, 1.0)

local TEAM_COLORS = {
  ESPMKC(0.20, 0.65, 1.00, 1.00), ESPMKC(1.00, 0.28, 0.28, 1.00),
  ESPMKC(0.25, 0.90, 0.40, 1.00), ESPMKC(1.00, 0.72, 0.18, 1.00),
  ESPMKC(0.72, 0.40, 1.00, 1.00), ESPMKC(0.10, 0.88, 0.85, 1.00),
  ESPMKC(1.00, 0.42, 0.78, 1.00), ESPMKC(0.72, 0.82, 0.92, 1.00),
}

local function TeamColor(teamID, isBot, fallbackKey)
  local n = tonumber(teamID)
  if n then n = math.abs(math.floor(n))
  else
    local str = tostring(fallbackKey or "unknown")
    local h = 0
    for i = 1, #str do h = (h * 31 + string.byte(str, i)) % 2147483647 end
    n = h
  end
  return TEAM_COLORS[(n % #TEAM_COLORS) + 1]
end

local function RND(v) if v ~= v then return 0 end return math.floor(v + 0.5) end
local function Lerp(a, b, t) return a + (b - a) * t end

local function HealthColor(pct)
  pct = tonumber(pct) or 1.0
  if pct < 0 then pct = 0 end
  if pct > 1 then pct = 1 end
  local r, g, b
  if pct >= 0.7 then
    local t = (pct - 0.7) / 0.3
    r = Lerp(0.75, 0.12, t); g = 1.0; b = Lerp(0.15, 0.25, t)
  elseif pct >= 0.4 then
    local t = (pct - 0.4) / 0.3
    r = 1.0; g = Lerp(0.45, 0.95, t); b = Lerp(0.45, 0.20, t)
  else
    local t = pct / 0.4
    r = 1.0; g = Lerp(0.15, 0.45, t); b = Lerp(0.15, 0.45, t)
  end
  return ESPMKC(r, g, b, 1.0)
end

local ESP = {}
ESP.Canvas, ESP.Counter, ESP.LastWorld = nil, nil, nil
ESP.Lines, ESP.Corners, ESP.HealthBg, ESP.HealthFill = {}, {}, {}, {}
ESP.Marks, ESP.Infos, ESP.EnemyCache, ESP.VisCache = {}, {}, {}, {}
ESP.ScaleX, ESP.ScaleY, ESP.OffsetX, ESP.OffsetY = 1.0, 1.0, 0.0, 0.0
ESP.ViewW, ESP.ViewH = 1920, 1080
ESP.LastScan, ESP.LastTransform = -999.0, -999.0
ESP.bActive, ESP._t = false, nil
ESP._TimerHooked = false
ESP._infoAttempts = {}

function ESP.GetGameplayData()
  if ESP._GDP then return ESP._GDP end
  local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
  if ok and GDP then ESP._GDP = GDP return GDP end
  return nil
end

function ESP.GetController()
  local pc = nil
  pcall(function()
    local GDP = ESP.GetGameplayData()
    if GDP and GDP.GetPlayerController then pc = GDP.GetPlayerController() end
  end)
  if not ESPValid(pc) then
    pcall(function() if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end end)
  end
  return ESPValid(pc) and pc or nil
end

function ESP.GetLocalCharacter()
  local c = nil
  pcall(function()
    local GDP = ESP.GetGameplayData()
    if GDP then
      if GDP.GetPlayerCharacter then c = GDP.GetPlayerCharacter() end
      if not ESPValid(c) and GDP.GetLocalCharacter then c = GDP.GetLocalCharacter() end
    end
  end)
  if not ESPValid(c) then
    local pc = ESP.GetController()
    pcall(function() if pc and pc.GetPawn then c = pc:GetPawn() end end)
  end
  return ESPValid(c) and c or nil
end

function ESP.GetAllCharacters()
  local AllChars = {}
  local function merge(chars)
    if not chars then return end
    for k, ch in pairs(chars) do
      if ch and slua.isValid(ch) then
        local pKey = k
        pcall(function()
          if not pKey and ch.GetPlayerKey then pKey = ch:GetPlayerKey() end
          if not pKey and ch.PlayerKey then pKey = ch.PlayerKey end
          if not pKey and ch.PlayerState and ch.PlayerState.PlayerKey then pKey = ch.PlayerState.PlayerKey end
        end)
        if pKey then AllChars[pKey] = ch end
      end
    end
  end
  pcall(function() if Game and Game.GetAllPlayerPawns then merge(Game:GetAllPlayerPawns()) end end)
  pcall(function()
    local GDP = ESP.GetGameplayData()
    if GDP and GDP.GetAllCharacters then merge(GDP:GetAllCharacters()) end
  end)
  pcall(function()
    local GS = require("GameLua.GameCore.Data.CGameState")
    if GS and GS.GetAllCharacters then merge(GS:GetAllCharacters()) end
  end)
  return AllChars
end

function ESP.GetTeamID(Character)
  if not ESPValid(Character) then return nil end
  local id = nil
  pcall(function() if Character.GetTeamID then id = Character:GetTeamID() end end)
  if id == nil then pcall(function() id = Character.TeamID end) end
  if id == nil then
    local ps = nil
    pcall(function()
      if Character.GetPlayerStateSafety then ps = Character:GetPlayerStateSafety()
      elseif Character.GetPlayerState then ps = Character:GetPlayerState() end
    end)
    if not ESPValid(ps) then pcall(function() ps = Character.PlayerState end) end
    if ESPValid(ps) then
      pcall(function() if ps.GetTeamID then id = ps:GetTeamID() end end)
      if id == nil then pcall(function() id = ps.TeamID end) end
    end
  end
  return id
end

-- ============================================================================
--  SAFE IsAlive — read property, never call the native
-- ============================================================================
function ESP.IsAlive(Character)
  if not ESPValid(Character) then return false end
  local hp = nil
  pcall(function() hp = Character.Health end)
  if type(hp) ~= "number" then pcall(function() hp = Character.HP end) end
  if type(hp) == "number" then return hp > 0 end
  return true   -- unknown -> assume alive rather than risk native IsAlive call
end

function ESP.IsBot(Character)
  if not ESPValid(Character) then return false end
  local bAI = false
  pcall(function()
    if Game and Game.IsAI then bAI = Game:IsAI(Character) end
    if not bAI and Character then
      if Character.bEnsure == true or Character.bMEnsure == true then bAI = true
      elseif Character.PlayerState and Character.PlayerState.bPSEnsure == true then bAI = true
      elseif Character.Controller then
        if Character.Controller.IsMLAI == true or Character.Controller.FakePlayerBornType == 1 then bAI = true end
      end
    end
  end)
  if not bAI then pcall(function() if Character.bIsAI == true then bAI = true end end) end
  if not bAI then
    local ps = nil
    pcall(function() if Character.GetPlayerStateSafety then ps = Character:GetPlayerStateSafety() end end)
    if ESPValid(ps) then
      pcall(function()
        if ps.bIsABot == true or ps.bIsBot == true or ps.bIsAI == true then bAI = true end
      end)
    end
  end
  return bAI
end

function ESP.GetPlayerKey(Character)
  local key = nil
  pcall(function() if Character.GetPlayerKey then key = Character:GetPlayerKey() end end)
  if key == nil then pcall(function() key = Character.PlayerKey end) end
  return tostring(key or Character)
end

function ESP.GetHealthPct(Character)
  if not ESPValid(Character) then return 1.0 end
  local hp, maxhp = nil, nil
  pcall(function() hp = Character.Health end)
  if type(hp) ~= "number" then pcall(function() hp = Character.HP end) end
  pcall(function() maxhp = Character.MaxHealth end)
  if type(maxhp) ~= "number" then pcall(function() maxhp = Character.MaxHP end) end
  if type(hp) ~= "number" then return 1.0 end
  if type(maxhp) ~= "number" or maxhp <= 0 then maxhp = 100 end
  local pct = hp / maxhp
  if pct ~= pct then return 1.0 end
  if pct < 0 then pct = 0 end
  if pct > 1 then pct = 1 end
  return pct
end

local function NormalizeName(v)
  if v == nil or v == false then return nil end
  local ok, t = pcall(tostring, v)
  if not ok or not t then return nil end
  t = t:gsub("^%s+", ""):gsub("%s+$", "")
  if t == "" or t == "nil" or t == "None" or t == "NULL" or t == "Unknown" then return nil end
  return t
end

function ESP.ResolveName(Character, isBot)
  if isBot then return "Bot" end
  local name = nil
  local function take(v) if not name then name = NormalizeName(v) end end
  pcall(function() if Character.GetPlayerNameSafety then take(Character:GetPlayerNameSafety()) end end)
  pcall(function() if not name and Character.GetPlayerName then take(Character:GetPlayerName()) end end)
  pcall(function() if not name then take(Character.PlayerName) end end)
  pcall(function() if not name then take(Character.NickName) end end)
  if not name then
    local ps = nil
    pcall(function()
      if Character.GetPlayerStateSafety then ps = Character:GetPlayerStateSafety()
      elseif Character.GetPlayerState then ps = Character:GetPlayerState() end
    end)
    if not ESPValid(ps) then pcall(function() ps = Character.PlayerState end) end
    if ESPValid(ps) then
      pcall(function() if ps.GetPlayerName then take(ps:GetPlayerName()) end end)
      pcall(function() if not name then take(ps.PlayerName) end end)
      pcall(function() if not name then take(ps.PlayerNamePrivate) end end)
      pcall(function() if not name then take(ps.NickName) end end)
    end
  end
  return name or "Player"
end

-- ============================================================================
--  SAFE GetBonePos — prefer Mesh socket, only fall back to native GetBonePos
-- ============================================================================
function ESP.GetBonePos(Character, boneName)
  if not ESPValid(Character) or not boneName then return nil end
  local pos = nil
  pcall(function()
    if ESPValid(Character.Mesh) and Character.Mesh.GetSocketLocation then
      pos = Character.Mesh:GetSocketLocation(boneName)
    end
  end)
  if not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0) then
    pcall(function()
      if type(Character.GetBonePos) == "function" then
        pos = Character:GetBonePos(boneName, { X = 0, Y = 0, Z = 0 })
      end
    end)
  end
  if not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0) then return nil end
  return pos
end

function ESP.GetCamLoc(pc)
  local loc = nil
  pcall(function()
    if GameplayStaticsESP and GameplayStaticsESP.GetPlayerCameraManager then
      local mgr = GameplayStaticsESP.GetPlayerCameraManager(pc, 0)
      if ESPValid(mgr) and mgr.GetCameraLocation then loc = mgr:GetCameraLocation() end
    end
  end)
  if not loc then
    pcall(function()
      if pc and pc.GetPawn then
        local p = pc:GetPawn()
        if ESPValid(p) and p.K2_GetActorLocation then loc = p:K2_GetActorLocation() end
      end
    end)
  end
  return loc
end

function ESP.GetCameraForward(pc)
  local fwd = nil
  pcall(function()
    if GameplayStaticsESP and GameplayStaticsESP.GetPlayerCameraManager then
      local mgr = GameplayStaticsESP.GetPlayerCameraManager(pc, 0)
      if ESPValid(mgr) and mgr.GetCameraRotation then
        local rot = mgr:GetCameraRotation()
        if rot and tonumber(rot.Pitch) and tonumber(rot.Yaw) then
          local p, y = math.rad(rot.Pitch), math.rad(rot.Yaw)
          fwd = { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
        end
      end
    end
    if not fwd then
      local p = ESP.GetLocalCharacter()
      if ESPValid(p) and p.GetActorForwardVector then
        local v = p:GetActorForwardVector()
        if v and tonumber(v.X) then fwd = v end
      end
    end
  end)
  return fwd
end

-- ============================================================================
--  SAFE visibility — one HR per call, always pass target as world context
--  Disabled by default via CFG.UseVisibility = false
-- ============================================================================
function ESP.IsBoneVisible(pc, camLoc, target, bonePos)
  if not CFG.UseVisibility then return true end
  if not ESPValid(pc) or not ESPValid(target) or not bonePos or not camLoc then return false end
  if not KismetSystemLibraryESP or not HitResultClassESP then return true end
  local HR = nil
  pcall(function() HR = HitResultClassESP() end)
  if not HR then return true end
  local dx, dy, dz = bonePos.X - camLoc.X, bonePos.Y - camLoc.Y, bonePos.Z - camLoc.Z
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  if dist < 300 then return true end
  local startP = { X = camLoc.X + (dx / dist) * 60, Y = camLoc.Y + (dy / dist) * 60, Z = camLoc.Z + (dz / dist) * 60 }
  local bHit, bVis = false, false
  pcall(function()
    -- pass the TARGET (not the PC) as world context → stable on all builds
    bHit = KismetSystemLibraryESP.LineTraceSingle(target, startP, bonePos, 0, false, nil, 0, HR, true)
    if bHit == true then
      local act = nil
      if HR.GetActor then act = HR:GetActor() elseif HR.Actor then act = HR.Actor end
      if ESPValid(act) and act == target then bVis = true end
    elseif bHit == false then
      bVis = true
    end
  end)
  return bVis
end

function ESP.IsVisible(key, pc, camLoc, Character)
  if not CFG.UseVisibility then return true end
  local now = ESP.Now()
  local cached = ESP.VisCache[key]
  if cached and (now - (cached.t or 0)) < CFG.VisInterval then return cached.b end
  local bVis = false
  if ESPValid(Character) and ESPValid(pc) and camLoc then
    local loc = ESP.ActorLocation(Character)
    if loc then
      local dx, dy, dz = loc.X - camLoc.X, loc.Y - camLoc.Y, loc.Z - camLoc.Z
      if (dx*dx + dy*dy + dz*dz) > CFG.VisibilityMaxDist ^ 2 then
        ESP.VisCache[key] = { b = false, t = now }
        return false
      end
    end
    local bp = ESP.GetBonePos(Character, "head")
    if bp then bVis = ESP.IsBoneVisible(pc, camLoc, Character, bp) end
  else
    bVis = true
  end
  ESP.VisCache[key] = { b = bVis, t = now }
  return bVis
end

function ESP.ActorLocation(Character)
  local loc = nil
  if not ESPValid(Character) then return nil end
  pcall(function()
    if Character.K2_GetActorLocation then loc = Character:K2_GetActorLocation()
    elseif Game and Game.GetActorLocation then loc = Game:GetActorLocation(Character) end
  end)
  return loc
end

function ESP.DistMeters(a, b)
  if not a or not b then return math.huge end
  local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
  return math.sqrt(dx * dx + dy * dy + dz * dz) / 100.0
end

function ESP.GetVerticalBounds(Character)
  if not ESPValid(Character) then return nil, nil end
  local center, halfHeight = nil, nil
  local capsule = nil
  pcall(function()
    if Character.GetCapsuleComponent then capsule = Character:GetCapsuleComponent()
    elseif Character.CapsuleComponent then capsule = Character.CapsuleComponent end
  end)
  if capsule and ESPValid(capsule) then
    pcall(function()
      if capsule.K2_GetComponentLocation then center = capsule:K2_GetComponentLocation()
      elseif capsule.GetComponentLocation then center = capsule:GetComponentLocation() end
      if capsule.GetScaledCapsuleHalfHeight then halfHeight = capsule:GetScaledCapsuleHalfHeight()
      elseif capsule.GetUnscaledCapsuleHalfHeight then halfHeight = capsule:GetUnscaledCapsuleHalfHeight()
      elseif capsule.CapsuleHalfHeight then halfHeight = capsule.CapsuleHalfHeight end
    end)
  end
  if not center then pcall(function() if Character.K2_GetActorLocation then center = Character:K2_GetActorLocation() end end) end
  if not center then pcall(function() if Game and Game.GetActorLocation then center = Game:GetActorLocation(Character) end end) end
  if not center then return nil, nil end
  if not halfHeight or halfHeight < 10 or halfHeight > 200 then
    halfHeight = 85
    pcall(function()
      if Character.bIsCrouched then halfHeight = 60 end
      if Character.IsProne and Character:IsProne() then halfHeight = 25 end
    end)
  end
  return center, halfHeight
end

function ESP.GetHeadFeet(Character)
  local center, half = ESP.GetVerticalBounds(Character)
  if not center or not half then return nil, nil end
  return { X = center.X, Y = center.Y, Z = center.Z + half },
         { X = center.X, Y = center.Y, Z = center.Z - half }
end

function ESP.Now()
  local t = nil
  pcall(function()
    local w = slua and slua.getWorld and slua.getWorld() or nil
    if w and GameplayStaticsESP and GameplayStaticsESP.GetRealTimeSeconds then
      t = GameplayStaticsESP.GetRealTimeSeconds(w)
    end
  end)
  if tonumber(t) then
    ESP._t = tonumber(t)
    return ESP._t
  end
  local ot = nil
  pcall(function() if os and os.clock then ot = os.clock() end end)
  if ot then
    ESP._t = ot
    return ot
  end
  return ESP._t or 0.0
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
    local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
    if InGameUITools and InGameUITools.GetMainControlBaseUI then root = InGameUITools.GetMainControlBaseUI() end
  end)
  if not ESPValid(root) then return nil end
  local canvas = nil
  pcall(function()
    if ESPValid(root.CanvasPanel_0) then canvas = root.CanvasPanel_0
    elseif ESPValid(root.CanvasPanel_42) then canvas = root.CanvasPanel_42 end
  end)
  if ESPValid(canvas) then ESP.Canvas = canvas return canvas end
  return nil
end

function ESP.UpdateCanvasTransform(pc)
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return false end
  local calibrated = false
  pcall(function()
    if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
      local geo = canvas:GetCachedGeometry()
      if geo then
        local p0 = SlateBlueprintLibrary.AbsoluteToLocal(geo, ESPV2(0, 0))
        local p1 = SlateBlueprintLibrary.AbsoluteToLocal(geo, ESPV2(100, 100))
        if p0 and p1 and tonumber(p0.X) and tonumber(p1.X) and p1.X ~= p0.X and p1.Y ~= p0.Y then
          ESP.ScaleX = (p1.X - p0.X) / 100.0
          ESP.ScaleY = (p1.Y - p0.Y) / 100.0
          ESP.OffsetX, ESP.OffsetY = p0.X, p0.Y
          calibrated = true
        end
      end
    end
  end)
  if not calibrated then
    local scale = 1.0
    pcall(function()
      if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
        local s = WidgetLayoutLibrary.GetViewportScale(pc)
        if tonumber(s) and s > 0 then scale = s end
      end
    end)
    ESP.ScaleX, ESP.ScaleY = 1.0 / scale, 1.0 / scale
    ESP.OffsetX, ESP.OffsetY = 0.0, 0.0
  end
  return true
end

function ESP.Viewport(pc)
  local w, h = 1920.0, 1080.0
  pcall(function()
    if pc and pc.GetViewportSize then
      local v = ESPV2(0, 0)
      if v then
        pc:GetViewportSize(v)
        if v and tonumber(v.X) and v.X > 200 then w, h = v.X, v.Y end
      end
    end
  end)
  return w, h
end

-- ============================================================================
--  SAFE Project — 3rd arg false, dot-check against camera forward,
--  reject NaN / inf / absurd values.
-- ============================================================================
function ESP.Project(pc, worldLoc, camFwd, camLoc)
  if not pc or not worldLoc then return nil end
  if camLoc and camFwd then
    local dx = worldLoc.X - camLoc.X
    local dy = worldLoc.Y - camLoc.Y
    local dz = worldLoc.Z - camLoc.Z
    local dot = dx*camFwd.X + dy*camFwd.Y + dz*camFwd.Z
    if dot <= 0.1 then return nil end  -- behind camera → no ghost box
  end
  local pix = ESPV2(0, 0)
  if not pix then return nil end
  local ok = false
  pcall(function()
    ok = (pc:ProjectWorldLocationToScreen(worldLoc, pix, false) == true)
  end)
  if not ok then return nil end
  local px, py = tonumber(pix.X), tonumber(pix.Y)
  if not px or not py or px ~= px or py ~= py then return nil end
  if math.abs(px) > 1e6 or math.abs(py) > 1e6 then return nil end
  local x = px * (ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0)
  local y = py * (ESP.ScaleY or 1.0) + (ESP.OffsetY or 0.0)
  if x ~= x or y ~= y then return nil end
  return ESPV2(x, y), pix
end

function ESP.SetFont(w, size)
  if not ESPValid(w) then return end
  pcall(function()
    local f = w.Font
    if f then
      f.Size = size
      if f.OutlineSettings then
        pcall(function() f.OutlineSettings.OutlineSize = 1 end)
        pcall(function() f.OutlineSettings.OutlineColor = C_BLACK end)
      end
      w:SetFont(f)
    end
    if w.SetShadowOffset then w:SetShadowOffset(ESPV2(1.0, 1.0)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(C_BLACK) end
  end)
end

function ESP.SetTextColor(w, color)
  if not ESPValid(w) or not color then return end
  pcall(function()
    if SlateColor then w:SetColorAndOpacity(SlateColor(color))
    else w:SetColorAndOpacity(color) end
  end)
end

function ESP.NewLine(color, z)
  if not color then return nil end
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local border = nil
  pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", canvas) end)
  if not ESPValid(border) then return nil end
  pcall(function()
    border:SetBrushColor(color)
    border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    border:SetRenderTransformPivot(ESPV2(0.0, 0.5))
  end)
  local slot = nil
  pcall(function() slot = canvas:AddChildToCanvas(border) end)
  if not slot then
    pcall(function() border:RemoveFromParent() end)
    return nil
  end
  pcall(function() slot:SetAutoSize(false) slot:SetZOrder(z or 30) end)
  return { Widget = border, Slot = slot }
end

function ESP.DrawLine(data, x1, y1, x2, y2, thickness)
  if not data or not ESPValid(data.Widget) or not data.Slot then return false end
  if x1 ~= x1 or y1 ~= y1 or x2 ~= x2 or y2 ~= y2 then return false end
  x1, y1, x2, y2 = RND(x1), RND(y1), RND(x2), RND(y2)
  local dz = CFG.DeadZone
  if data.lx1 and data.th == thickness then
    if math.abs((data.lx1 or 0) - x1) < dz and math.abs((data.ly1 or 0) - y1) < dz
    and math.abs((data.lx2 or 0) - x2) < dz and math.abs((data.ly2 or 0) - y2) < dz then
      if data.hidden ~= true then return true end
    end
  end
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then ESP.Hide(data) return false end
  local angle = 0
  if math.abs(dx) + math.abs(dy) > 0.001 then
    angle = math.deg(math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx))
  end
  if angle ~= angle or math.abs(angle) > 3600 then angle = 0 end
  angle = math.floor(angle * 10 + 0.5) / 10
  len = RND(len)
  if data.lx1 == x1 and data.ly1 == y1 and data.lx2 == x2 and data.ly2 == y2 and data.th == thickness then
    if data.hidden == true then
      pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
      data.hidden = false
    end
    return true
  end
  local ok = pcall(function()
    data.Slot:SetPosition(ESPV2(x1, y1 - thickness * 0.5))
    data.Slot:SetSize(ESPV2(len, thickness))
    data.Widget:SetRenderAngle(angle)
    data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if ok then
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = x1, y1, x2, y2, thickness
    data.hidden = false
  else
    ESP.Hide(data)
  end
  return true
end

function ESP.Hide(data)
  if data and ESPValid(data.Widget) and data.hidden ~= true then
    pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    data.hidden = true
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = nil, nil, nil, nil, nil
  end
end

function ESP.SetBrush(data, color, colorKey)
  if not data or not ESPValid(data.Widget) or not color then return end
  if colorKey and data.colorKey == colorKey then return end
  pcall(function() data.Widget:SetBrushColor(color) end)
  if colorKey then data.colorKey = colorKey end
end

function ESP.Destroy(data)
  if not data then return end
  local w = data.Widget or data.Container
  if w then
    pcall(function()
      if slua.isValid(w) then
        w:RemoveFromParent()
        w:ConditionalBeginDestroy()
      end
    end)
  end
  if data.Widget then data.Widget = nil end
  if data.Container then data.Container = nil end
end

function ESP.CreateCounter()
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local container = nil
  pcall(function() container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
  if not ESPValid(container) then return nil end
  local txt = nil
  pcall(function() txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
  if not ESPValid(txt) then ESP.Destroy({ Widget = container }) return nil end
  pcall(function()
    txt:SetText("Players: 0 | Bots: 0")
    txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if txt.SetJustification then txt:SetJustification(1) end
  end)
  ESP.SetTextColor(txt, C_WHITE)
  ESP.SetFont(txt, CFG.CounterFontSize)
  local tSlot, mSlot = nil, nil
  pcall(function() tSlot = container:AddChildToCanvas(txt) end)
  pcall(function() mSlot = canvas:AddChildToCanvas(container) end)
  if not tSlot or not mSlot then ESP.Destroy({ Widget = container }) return nil end
  local W, H = CFG.CounterW, CFG.CounterH
  pcall(function()
    tSlot:SetAutoSize(true)
    tSlot:SetAlignment(ESPV2(0.5, 0.5))
    tSlot:SetPosition(ESPV2(W * 0.5, H * 0.5))
    tSlot:SetZOrder(5)
    mSlot:SetAutoSize(false)
    mSlot:SetAlignment(ESPV2(0.5, 0.0))
    mSlot:SetSize(ESPV2(W, H))
    mSlot:SetZOrder(60)
  end)
  return { Container = container, Text = txt, Slot = mSlot, W = W, H = H }
end

function ESP.CanvasCenterX(viewW)
  local cw = nil
  pcall(function()
    local canvas = ESP.GetCanvas()
    if ESPValid(canvas) then
      local geo = canvas:GetCachedGeometry()
      if geo and geo.GetLocalSize then
        local s = geo:GetLocalSize()
        if s and tonumber(s.X) and s.X > 1 then cw = tonumber(s.X) end
      end
    end
  end)
  if tonumber(cw) and cw > 1 then return cw * 0.5 end
  return (viewW * 0.5) * (ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0)
end

function ESP.UpdateCounter(nPlayers, nBots, pc, viewW)
  local d = ESP.Counter
  if not d or not ESPValid(d.Container) then
    ESP.Destroy(d)
    d = ESP.CreateCounter()
    ESP.Counter = d
  end
  if not d then return nil end
  local label = string.format("Players: %d | Bots: %d", nPlayers or 0, nBots or 0)
  pcall(function()
    if d.Last ~= label then d.Text:SetText(label) d.Last = label end
  end)
  local cx = ESP.CanvasCenterX(viewW)
  if cx then
    cx = RND(cx)
    if d.px == nil or math.abs(d.px - cx) >= 1.0 then
      d.px = cx
      pcall(function()
        d.Slot:SetPosition(ESPV2(cx, CFG.TopTextY))
        d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    else
      pcall(function() d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    end
  end
  return ESPV2(cx, CFG.SnapOriginY)
end

function ESP.CreateInfo()
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local container, teamBox, tName, tDist, tState = nil, nil, nil, nil, nil
  pcall(function() container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
  if not ESPValid(container) then return nil end
  pcall(function() teamBox = CGame:NewObjectFromPath("/Script/UMG.Border", container) end)
  pcall(function() tName = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
  pcall(function() tDist = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
  pcall(function() tState = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
  if not ESPValid(teamBox) or not ESPValid(tName) or not ESPValid(tDist) or not ESPValid(tState) then
    ESP.Destroy({ Widget = container })
    return nil
  end
  pcall(function()
    teamBox:SetBrushColor(TEAM_COLORS[1])
    teamBox:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tName:SetText("Player"); tDist:SetText("0m"); tState:SetText("Open")
    tName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tDist:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tState:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if tName.SetJustification then tName:SetJustification(1) end
    if tDist.SetJustification then tDist:SetJustification(1) end
    if tState.SetJustification then tState:SetJustification(1) end
  end)
  ESP.SetTextColor(tName, C_WHITE); ESP.SetTextColor(tDist, C_WHITE); ESP.SetTextColor(tState, C_GREEN)
  ESP.SetFont(tName, CFG.NameFontSize); ESP.SetFont(tDist, CFG.DistFontSize); ESP.SetFont(tState, CFG.StateFontSize)
  local bSlot, nSlot, s2, s3, ms = nil, nil, nil, nil, nil
  pcall(function() bSlot = container:AddChildToCanvas(teamBox) end)
  pcall(function() nSlot = container:AddChildToCanvas(tName) end)
  pcall(function() s2 = container:AddChildToCanvas(tDist) end)
  pcall(function() s3 = container:AddChildToCanvas(tState) end)
  pcall(function() ms = canvas:AddChildToCanvas(container) end)
  if not bSlot or not nSlot or not s2 or not s3 or not ms then
    ESP.Destroy({ Widget = container })
    return nil
  end
  pcall(function()
    bSlot:SetAutoSize(false); bSlot:SetSize(ESPV2(120.0, 22.0)); bSlot:SetAlignment(ESPV2(0.5, 0.5)); bSlot:SetZOrder(34)
    nSlot:SetAutoSize(false); nSlot:SetSize(ESPV2(120.0, 22.0)); nSlot:SetAlignment(ESPV2(0.5, 0.5)); nSlot:SetZOrder(36)
    s2:SetAutoSize(true); s2:SetAlignment(ESPV2(0.5, 0.5)); s2:SetZOrder(36)
    s3:SetAutoSize(true); s3:SetAlignment(ESPV2(0.5, 0.5)); s3:SetZOrder(36)
    ms:SetAutoSize(false); ms:SetZOrder(35)
  end)
  return { Container = container, TeamBox = teamBox, Name = tName, Dist = tDist, State = tState,
           S0 = bSlot, S1 = nSlot, S2 = s2, S3 = s3, Slot = ms }
end

function ESP.UpdateInfo(key, Character, isBot, teamID, distM, bVisible, headX, headY, footX, footY, boxL, boxR)
  local d = ESP.Infos[key]
  if not d or not ESPValid(d.Container) then
    local now = ESP.Now()
    local lastT = ESP._infoAttempts[key]
    if lastT and (now - lastT) < 0.5 then return end
    ESP._infoAttempts[key] = now
    ESP.Destroy(d)
    d = ESP.CreateInfo()
    ESP.Infos[key] = d
    if d then ESP._infoAttempts[key] = nil end
  end
  if not d then return end
  local name = d.CachedName
  if not name then name = ESP.ResolveName(Character, isBot); d.CachedName = name end
  if isBot then name = "Bot" d.CachedName = "Bot" end
  local dl = string.format("%dm", math.max(0, math.floor((tonumber(distM) or 0) + 0.5)))
  local st = bVisible and "Open" or "Close"
  local teamColor = TeamColor(teamID, isBot, key)
  pcall(function()
    if d.LastN ~= name then d.Name:SetText(name) d.LastN = name end
    if d.LastD ~= dl then d.Dist:SetText(dl) d.LastD = dl end
    if d.LastS ~= st then d.State:SetText(st) d.LastS = st end
    if d.LastTeam ~= tostring(teamID) .. ":" .. tostring(isBot) then
      d.TeamBox:SetBrushColor(teamColor)
      d.LastTeam = tostring(teamID) .. ":" .. tostring(isBot)
    end
    ESP.SetTextColor(d.State, bVisible and C_GREEN or C_RED)
  end)
  local bannerW = 100.0
  local bannerH = 22.0
  local bx = RND(headX)
  local by = RND(headY - 18.0)
  pcall(function()
    d.Slot:SetPosition(ESPV2(bx, by))
    d.Slot:SetSize(ESPV2(bannerW, 70.0))
    d.S0:SetPosition(ESPV2(0.0, 0.0)); d.S0:SetSize(ESPV2(bannerW, bannerH))
    d.S1:SetPosition(ESPV2(0.0, 0.0)); d.S1:SetSize(ESPV2(bannerW, bannerH))
    d.S2:SetPosition(ESPV2(bannerW * 0.5, bannerH + 12.0))
    d.S3:SetPosition(ESPV2(bannerW * 0.5, bannerH + 30.0))
    d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  d.ix, d.iy = bx, by
end

function ESP.EnsureHealthBg(key)
  local d = ESP.HealthBg[key]
  if d and ESPValid(d.Widget) then return d end
  if d then ESP.Destroy(d) end
  d = ESP.NewLine(ESPMKC(0.0, 0.0, 0.0, CFG.SideBgAlpha), 31)
  ESP.HealthBg[key] = d
  return d
end

function ESP.EnsureHealthFill(key)
  local d = ESP.HealthFill[key]
  if d and ESPValid(d.Widget) then return d end
  if d then ESP.Destroy(d) end
  d = ESP.NewLine(C_GREEN, 32)
  ESP.HealthFill[key] = d
  return d
end

function ESP.UpdateHealthBar(key, pct, x, y, w)
  local bg = ESP.EnsureHealthBg(key)
  if not bg then return end
  local fill = ESP.EnsureHealthFill(key)
  if not fill then return end
  local thickness = CFG.SideBarWidth
  w = math.max(1, tonumber(w) or 1)
  ESP.DrawLine(bg, x, y, x + w, y, thickness)
  pct = tonumber(pct) or 1.0
  if pct < 0 then pct = 0 end
  if pct > 1 then pct = 1 end
  local bucket
  if pct >= 0.7 then bucket = "g_" .. math.floor(pct * 20 + 0.5)
  elseif pct >= 0.4 then bucket = "y_" .. math.floor(pct * 20 + 0.5)
  else bucket = "r_" .. math.floor(pct * 20 + 0.5) end
  ESP.SetBrush(fill, HealthColor(pct), bucket)
  local fw = w * pct
  if fw < 1 then ESP.Hide(fill) return end
  ESP.DrawLine(fill, x, y, x + fw, y, thickness)
end

function ESP.EnsureSnap(key)
  local d = ESP.Lines[key]
  if d and ESPValid(d.Widget) then return d end
  if d then ESP.Destroy(d) end
  d = ESP.NewLine(C_GREEN, 30)
  ESP.Lines[key] = d
  return d
end

function ESP.HideTarget(key)
  ESP.Hide(ESP.HealthBg[key])
  ESP.Hide(ESP.HealthFill[key])
  ESP.Hide(ESP.Lines[key])
  local inf = ESP.Infos[key]
  if inf and ESPValid(inf.Container) then
    pcall(function() inf.Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
  end
end

function ESP.ReleaseTarget(key)
  ESP.Destroy(ESP.HealthBg[key]); ESP.HealthBg[key] = nil
  ESP.Destroy(ESP.HealthFill[key]); ESP.HealthFill[key] = nil
  ESP.Destroy(ESP.Lines[key]); ESP.Lines[key] = nil
  ESP.Destroy(ESP.Infos[key]); ESP.Infos[key] = nil
  ESP.VisCache[key] = nil
  ESP._infoAttempts[key] = nil
end

function ESP.HideAll()
  for k in pairs(ESP.Infos)    do ESP.HideTarget(k) end
  for k in pairs(ESP.Lines)    do ESP.HideTarget(k) end
  for k in pairs(ESP.HealthBg) do ESP.HideTarget(k) end
  if ESP.Counter and ESPValid(ESP.Counter.Container) then
    pcall(function() ESP.Counter.Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
  end
end

function ESP.ResetWidgets()
  for _, d in pairs(ESP.Lines) do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthBg) do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthFill) do ESP.Destroy(d) end
  for _, d in pairs(ESP.Infos) do ESP.Destroy(d) end
  ESP.Lines, ESP.Corners, ESP.HealthBg, ESP.HealthFill = {}, {}, {}, {}
  ESP.Marks, ESP.Infos, ESP.VisCache, ESP._infoAttempts = {}, {}, {}, {}
  if ESP.Counter then ESP.Destroy(ESP.Counter) end
  ESP.Counter, ESP.Canvas, ESP.EnemyCache = nil, nil, {}
end

function ESP.Scan()
  local pc = ESP.GetController()
  local me = ESP.GetLocalCharacter()
  if not pc or not me then ESP.EnemyCache = {} return pc, 0, 0 end
  local myLoc = ESP.ActorLocation(me)
  if not myLoc then ESP.EnemyCache = {} return pc, 0, 0 end
  local myTeam = ESP.GetTeamID(me)
  local list = {}
  local nReal, nBot = 0, 0
  local pawns = ESP.GetAllCharacters()
  local seen = {}
  local maxDistM = CFG.RenderTrackingDistance / 100.0
  local function addPawn(ch)
    if not ESPValid(ch) or ch == me or not ESP.IsAlive(ch) then return end
    local key = ESP.GetPlayerKey(ch)
    if seen[key] then return end
    local team = ESP.GetTeamID(ch)
    if myTeam ~= nil and team ~= nil and tostring(team) == tostring(myTeam) then return end
    local loc = ESP.ActorLocation(ch)
    if not loc then return end
    local dm = ESP.DistMeters(myLoc, loc)
    if dm > maxDistM then return end
    seen[key] = true
    local isBot = ESP.IsBot(ch)
    if isBot then nBot = nBot + 1 else nReal = nReal + 1 end
    list[#list + 1] = { Character = ch, Key = key, IsBot = isBot, TeamID = team, Distance = dm }
  end
  if pawns then for _, ch in pairs(pawns) do addPawn(ch) end end
  table.sort(list, function(a, b) return (a.Distance or 99999) < (b.Distance or 99999) end)
  local trimmed = {}
  local maxR = CFG.MaxTracked
  for i, it in ipairs(list) do
    if i > maxR then break end
    trimmed[#trimmed + 1] = it
  end
  ESP.EnemyCache = trimmed
  return pc, nReal, nBot
end

function ESP.Update()
  if not ESP_Enabled then ESP.ResetWidgets() return end
  local world = ESP.World()
  if world ~= ESP.LastWorld then
    ESP.ResetWidgets()
    ESP.LastWorld = world
    ESP.LastScan, ESP.LastTransform = -999.0, -999.0
  end
  local canvas = ESP.GetCanvas()
  if not canvas then ESP.HideAll() return end
  local now = ESP.Now()
  local pc = ESP.GetController()
  if not pc then ESP.HideAll() return end
  if (now - ESP.LastScan) >= CFG.ScanInterval then
    local r, b
    pc, r, b = ESP.Scan()
    ESP.LastScan = now
    ESP.RealCount, ESP.BotCount = r or 0, b or 0
  end
  if not pc then ESP.HideAll() return end
  if (now - (ESP.LastTransform or -999.0)) >= CFG.TransformInterval then
    ESP.UpdateCanvasTransform(pc)
    ESP.LastTransform = now
  end
  local vw, vh = ESP.Viewport(pc)
  local hyst = CFG.SizeHyst
  if math.abs(vw - (ESP.ViewW or 0)) > hyst or math.abs(vh - (ESP.ViewH or 0)) > hyst then
    ESP.ViewW, ESP.ViewH = vw, vh
  else
    vw, vh = ESP.ViewW, ESP.ViewH
  end
  local origin = ESP.UpdateCounter(ESP.RealCount or 0, ESP.BotCount or 0, pc, vw)
  if not origin then return end
  local camLoc = ESP.GetCamLoc(pc)
  local camFwd = ESP.GetCameraForward(pc)
  local active = {}

  for _, item in ipairs(ESP.EnemyCache) do
    local c = item.Character
    local key = item.Key
    if not ESP.IsAlive(c) then
      ESP.HideTarget(key)
    else
      local head, feet = ESP.GetHeadFeet(c)
      if head and feet then
        local headS, headPix = ESP.Project(pc, head, camFwd, camLoc)
        local feetS, feetPix = ESP.Project(pc, feet, camFwd, camLoc)
        if headS and feetS and headPix and feetPix then
          local m = CFG.ScreenMargin
          local on = headPix.X > -m and headPix.X < vw + m
            and headPix.Y > -m and headPix.Y < vh + m
            and feetPix.X > -m and feetPix.X < vw + m
            and feetPix.Y > -m and feetPix.Y < vh + m
          local H = feetS.Y - headS.Y
          if on and H >= CFG.BoxMinHeight and H <= vh * 1.5 then
            active[key] = true
            local W = math.max(CFG.BoxMinWidth, math.min(CFG.BoxMaxWidth, H * CFG.BoxWidthFactor))
            local cx = (headS.X + feetS.X) * 0.5
            local L = cx - W * 0.5
            local R = cx + W * 0.5
            local pct = ESP.GetHealthPct(c)
            ESP.UpdateHealthBar(key, pct, L, headS.Y + 8.0, R - L)
            local snap = ESP.EnsureSnap(key)
            if snap then ESP.DrawLine(snap, origin.X, origin.Y, headS.X, headS.Y, CFG.SnapThickness) end
            local bVis = ESP.IsVisible(key, pc, camLoc, c)
            ESP.UpdateInfo(key, c, item.IsBot, item.TeamID, item.Distance, bVis,
                          headS.X, headS.Y, cx, feetS.Y, L, R)
          else
            ESP.HideTarget(key)
          end
        else
          ESP.HideTarget(key)
        end
      else
        ESP.HideTarget(key)
      end
    end
  end

  local seenCache = {}
  for _, it in ipairs(ESP.EnemyCache) do seenCache[it.Key] = true end
  for k in pairs(ESP.Lines)    do if active[k] ~= true then ESP.HideTarget(k) end end
  for k in pairs(ESP.Infos)    do if active[k] ~= true then ESP.HideTarget(k) end end
  for k in pairs(ESP.HealthBg) do if active[k] ~= true then ESP.HideTarget(k) end end
  local toRelease = {}
  for k in pairs(ESP.HealthBg) do if not active[k] and not seenCache[k] then toRelease[k] = true end end
  for k in pairs(ESP.Infos)    do if not active[k] and not seenCache[k] then toRelease[k] = true end end
  for k in pairs(ESP.Lines)    do if not active[k] and not seenCache[k] then toRelease[k] = true end end
  for k in pairs(toRelease)    do ESP.ReleaseTarget(k) end
end

-- ============================================================================
--  TIMER — single repeating timer, no self-re-registration.
--  Falls back to global timer if PC timer not available. Detects world
--  change and re-attaches (old timer early-outs harmlessly).
-- ============================================================================
function ESP.TickLoop()
  if not ESP.bActive then return end
  local ok, err = pcall(ESP.Update)
  if not ok and bWriteLog then print("[ESP] update error:", err) end
end

function ESP.AttachTimers()
  if ESP._TimerHooked then return end
  ESP._TimerHooked = true
  local ok = pcall(function()
    require("timer").SetGameTimer(CFG.LightInterval, true, ESP.TickLoop)
  end)
  if not ok then
    local pc = ESP.GetController()
    ok = ESPValid(pc) and pcall(function() pc:AddGameTimer(CFG.LightInterval, true, ESP.TickLoop) end)
  end
  if not ok then ESP._TimerHooked = false end
end

function ESP.Start()
  if ESP.bActive then return end
  ESP.bActive = true
  pcall(ESP.Update)
  ESP.AttachTimers()
end

_G.ESP = ESP
_G.PlayerMapMarker = ESP

local function ESPLater(sec, fn)
  local tk = nil
  pcall(function() tk = require("common.time_ticker") end)
  if tk and tk.AddTimerOnce then pcall(function() tk.AddTimerOnce(sec, fn) end) return end
  pcall(function() require("timer").SetGameTimer(sec, false, fn) end)
end

local function ESPStartAll()
  if not ESP_Enabled then return end
  pcall(function()
    local pc = nil
    if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
    if not ESPValid(pc) then pc = ESP.GetController() end
    if ESPValid(pc) then
      if not ESP.bActive then ESP.Start() end
      ESP.AttachTimers()
    end
  end)
end

pcall(function()
  ESPStartAll()
  ESPLater(1.0, ESPStartAll)
  ESPLater(3.0, ESPStartAll)
end)

-- ============================================================================
--  END ESP MODULE
-- ============================================================================

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
