-- ============================================================================
-- MERGED FILE: BRPlayerCharacterBase + ESP Overlay + Shield/Bypass Layers
-- ============================================================================
-- Contains:
--   [1] Utility helpers + namespace (was missing in script 2)
--   [2] BRPlayerCharacterBase class definition (script 1, unchanged)
--   [3] ESP overlay implementation (script 1, unchanged)
--   [4] Shield / BanShield / Esp tables (script 2, unchanged)
--   [5] Layer functions L01..L39 (script 2 + new L39 + installer)
--   [6] Boot scheduler (new)
--   [7] Class return (script 1)
-- ============================================================================

-- ============================================================
-- [1] UTILITY HELPERS + NAMESPACE
-- ============================================================
local A = _G.__SHIELD_NS or {}
_G.__SHIELD_NS = A
A.Up = A.Up or {}
A.Up.Shielded = A.Up.Shielded or false
A.Up.BanShielded = A.Up.BanShielded or false
A.Up.NativeReady = A.Up.NativeReady or false
A.Up.NativePriming = A.Up.NativePriming or false
A.Up.Layers = A.Up.Layers or {}
A.Up.LayersInstalled = A.Up.LayersInstalled or false
A.Up.Verbose = A.Up.Verbose or false

local function nop() end
local function retTrue() return true end
local function retFalse() return false end
local function retNil() return nil end
local function retZero() return 0 end
local function retEmpty() return {} end
local function retEmptyString() return "" end

local function safe_require(name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
  return nil
end

local function MarkLayer(name, ok)
  A.Up.Layers[name] = ok and "OK" or "FAIL"
  if A.Up.Verbose then print("[SHIELD] " .. tostring(name) .. ": " .. (ok and "OK" or "FAIL")) end
end

local function Later(sec, fn)
  local scheduled = false
  pcall(function()
    local tk = require("common.time_ticker")
    if tk and tk.AddTimerOnce then tk.AddTimerOnce(sec, fn) scheduled = true end
  end)
  if not scheduled then
    pcall(function()
      local timer = require("timer")
      if timer and timer.SetGameTimer then timer.SetGameTimer(sec, false, fn) scheduled = true end
    end)
  end
  if not scheduled then
    pcall(function()
      local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
      if pc and slua.isValid(pc) and pc.AddGameTimer then
        pc:AddGameTimer(sec, false, fn)
      end
    end)
  end
end

local FILE_KEYWORDS = {
  "report", "tlog", "anti", "cheat", "verify", "integrity",
  "signature", "ban", "kick", "suspicious", "hawk", "crash", "buggly"
}

local BLACKLIST_URL_PATTERNS = {
  "tlog", "report", "cheat", "ban", "verify", "integrity", "anti",
  "stats", "hawk", "logupload", "buggly", "crash", "sight"
}

local function isBlacklisted(url)
  if type(url) ~= "string" then return false end
  local low = url:lower()
  for _, pat in ipairs(BLACKLIST_URL_PATTERNS) do
    if low:find(pat, 1, true) then return true end
  end
  return false
end

local REAL_SECURITY_SUBSYSTEMS = {
  "AntiCheatSubsystem", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem",
  "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem",
  "AFKReportorSubsystem", "BehaviorScoreSubsystem", "ClientDataStatistcsSubsystem",
  "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem",
  "FileCheckSubsystem", "CoronaLabSubsystem", "PlayerSecurityInfoSubsystem",
  "ModifierExceptionSubsystem", "ShootVerifySubSystemClient",
  "OperationalStatsSubsystem", "GameReportSubsystem", "ReplaySubsystem",
  "SwiftHawkSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem",
  "MD5CheckSubsystem", "PakVerifySubsystem", "ClientSecMrpcsFlowSubsystem",
  "ClientCircleFlowSubsystem", "ClientESPDetectionSubsystem",
  "ClientAimTrackingSubsystem", "ClientRenderCheckSubsystem",
  "ClientMemoryGuardSubsystem", "ClientKernelCheckSubsystem",
  "ClientWallhackDetectionSubsystem", "ClientAntiCheatSubsystem"
}

local FakeData = {
  _cache = {},
  deviceID = function()
    if not FakeData._cache.deviceID then
      FakeData._cache.deviceID = string.format("%016x%016x",
        math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
    end
    return FakeData._cache.deviceID
  end,
  ipAddress = function()
    if not FakeData._cache.ipAddress then
      FakeData._cache.ipAddress = string.format("%d.%d.%d.%d",
        math.random(1, 223), math.random(0, 255),
        math.random(0, 255), math.random(1, 254))
    end
    return FakeData._cache.ipAddress
  end,
  macAddress = function()
    if not FakeData._cache.macAddress then
      FakeData._cache.macAddress = string.format("02:%02X:%02X:%02X:%02X:%02X",
        math.random(0, 255), math.random(0, 255), math.random(0, 255),
        math.random(0, 255), math.random(0, 255))
    end
    return FakeData._cache.macAddress
  end,
  buildFingerprint = function()
    if not FakeData._cache.buildFingerprint then
      FakeData._cache.buildFingerprint = string.format("fp_%08x_%08x",
        math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
    end
    return FakeData._cache.buildFingerprint
  end,
}

-- ============================================================
-- [2] BRPlayerCharacterBase CLASS DEFINITION (unchanged)
-- ============================================================
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
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
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
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
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
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
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
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then
    return
  end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then
    return
  end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then
    return
  end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
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
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
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
  if not slua.isValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
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
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
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
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")

  local function loadLater()
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
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
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
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
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
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
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
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked by SpiderSwing state: " .. tostring(nCurState))
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ============================================================
-- [3] ESP OVERLAY (unchanged)
-- ============================================================
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
local KismetSystemLibraryESP = nil
local HitResultClassESP = nil
pcall(function() KismetSystemLibraryESP = import("KismetSystemLibrary") end)
pcall(function() HitResultClassESP = import("HitResult") end)
local TraceStartPos = { X = 0, Y = 0, Z = 0 }
local CachedHitResult = nil
pcall(function()
  if HitResultClassESP then CachedHitResult = HitResultClassESP()
  else CachedHitResult = {} end
end)

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
  MaxDistance = 50000,
  RenderTrackingDistance = 50000,
  MaxTracked = 128,
  ScreenMargin = 500,
  TopTextY = 6.0,
  SnapOriginY = 0.0,
  SnapThickness = 1.8,
  CornerThickness = 2.2,
  CornerLen = 0.28,
  CornerMin = 6,
  CornerMax = 28,
  BoxMinWidth = 22,
  BoxMaxWidth = 320,
  BoxMinHeight = 1,
  BoxWidthFactor = 0.62,
  WidthScale = 1.22,
  HeadExtra = 0.06,
  FootExtra = 0.02,
  SideBarWidth = 3.5,
  SideBarGap = 5.0,
  SideBgAlpha = 0.55,
  MarkGap = 8.0,
  MarkW = 15.0,
  MarkH = 10.0,
  MarkGapV = 6.0,
  MarkThickness = 2.4,
  NameFontSize = 15,
  DistFontSize = 13,
  StateFontSize = 13,
  TextGap = 1.0,
  CounterFontSize = 17,
  CounterW = 300.0,
  CounterH = 28.0,
  DeadZone = 0.5,
  VisInterval = 0.008333,
  SizeHyst = 2.0,
}

local C_WHITE  = ESPMKC(1.0, 1.0, 1.0, 1.0)
local C_BLACK  = ESPMKC(0.0, 0.0, 0.0, 1.0)
local C_GREEN  = ESPMKC(0.12, 1.0, 0.25, 1.0)
local C_RED    = ESPMKC(1.0, 0.15, 0.15, 1.0)
local C_YELLOW = ESPMKC(1.0, 0.90, 0.30, 1.0)
local C_BLUE   = ESPMKC(0.38, 0.72, 1.0, 1.0)

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

local function TeamColor(teamID, isBot, fallbackKey)
  local n = tonumber(teamID)
  if n then
    n = math.abs(math.floor(n))
  else
    local str = tostring(fallbackKey or "unknown")
    local h = 0
    for i = 1, #str do h = (h * 31 + string.byte(str, i)) % 2147483647 end
    n = h
  end
  return TEAM_COLORS[(n % #TEAM_COLORS) + 1]
end

local function RND(v)
  if v ~= v then return 0 end
  return math.floor(v + 0.5)
end

local function Lerp(a, b, t) return a + (b - a) * t end

local function HealthColor(pct)
  pct = tonumber(pct) or 1.0
  if pct < 0 then pct = 0 end
  if pct > 1 then pct = 1 end
  local r, g, b
  if pct >= 0.7 then
    local t = (pct - 0.7) / 0.3
    r = Lerp(0.75, 0.12, t)
    g = 1.0
    b = Lerp(0.15, 0.25, t)
  elseif pct >= 0.4 then
    local t = (pct - 0.4) / 0.3
    r = 1.0
    g = Lerp(0.45, 0.95, t)
    b = Lerp(0.45, 0.20, t)
  else
    local t = pct / 0.4
    r = 1.0
    g = Lerp(0.15, 0.45, t)
    b = Lerp(0.15, 0.45, t)
  end
  return ESPMKC(r, g, b, 1.0)
end

local ESP = {}
ESP.Canvas = nil
ESP.Lines = {}
ESP.Corners = {}
ESP.HealthBg = {}
ESP.HealthFill = {}
ESP.Marks = {}
ESP.Infos = {}
ESP.Counter = nil
ESP.EnemyCache = {}
ESP.VisCache = {}
ESP.ScaleX = 1.0
ESP.ScaleY = 1.0
ESP.OffsetX = 0.0
ESP.OffsetY = 0.0
ESP.ViewW = 1920
ESP.ViewH = 1080
ESP.ScanInterval = 0.008333
ESP.LightInterval = 0.008333
ESP.TransformInterval = 0.008333
ESP.LastScan = -999.0
ESP.LastTransform = -999.0
ESP.LastWorld = nil
ESP.bActive = false

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
    pcall(function()
      if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
    end)
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
          if not pKey and ch.PlayerState and ch.PlayerState.PlayerKey then
            pKey = ch.PlayerState.PlayerKey
          end
        end)
        if pKey then AllChars[pKey] = ch end
      end
    end
  end

  pcall(function()
    if Game and Game.GetAllPlayerPawns then
      merge(Game:GetAllPlayerPawns())
    end
  end)

  pcall(function()
    local GDP = ESP.GetGameplayData()
    if GDP and GDP.GetAllCharacters then
      merge(GDP:GetAllCharacters())
    end
  end)

  pcall(function()
    local GS = require("GameLua.GameCore.Data.CGameState")
    if GS and GS.GetAllCharacters then
      merge(GS:GetAllCharacters())
    end
  end)

  return AllChars
end

function ESP.GetMyPlayerKey()
  local pc = ESP.GetController()
  if not ESPValid(pc) then return nil end
  local k = nil
  pcall(function()
    if pc.GetPlayerKey then k = pc:GetPlayerKey()
    elseif pc.PlayerState and pc.PlayerState.PlayerKey then k = pc.PlayerState.PlayerKey end
  end)
  return k
end

function ESP.IsMe(Character, PlayerKey, MyKey)
  local me = false
  pcall(function()
    local GDP = ESP.GetGameplayData()
    if GDP and GDP.GetLocalCharacter then
      local mc = GDP.GetLocalCharacter()
      if mc and Character == mc then me = true return end
    end
    local pc = ESP.GetController()
    if pc and pc.GetPawn then
      local p = pc:GetPawn()
      if p and Character == p then me = true return end
    end
  end)
  if not me and MyKey ~= nil and PlayerKey ~= nil then
    me = (tostring(PlayerKey) == tostring(MyKey))
  end
  return me
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

function ESP.IsAlive(Character)
  if not ESPValid(Character) then return false end
  local alive = nil
  pcall(function() if Character.IsAlive then alive = Character:IsAlive() end end)
  if type(alive) == "boolean" then return alive end
  local hp = nil
  pcall(function() hp = Character.Health end)
  if type(hp) ~= "number" then pcall(function() hp = Character.HP end) end
  if type(hp) == "number" then return hp > 0 end
  return true
end

function ESP.IsKnocked(Character)
  if not ESPValid(Character) then return false end
  local k = false
  pcall(function()
    if Character.HealthStatus == 1 then k = true end
  end)
  if not k then pcall(function()
    if Character.IsNearDeath and Character:IsNearDeath() then k = true end
  end) end
  return k
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
  if not bAI then
    pcall(function()
      if Character.bIsAI == true then bAI = true end
    end)
  end
  if not bAI then
    local ps = nil
    pcall(function()
      if Character.GetPlayerStateSafety then ps = Character:GetPlayerStateSafety() end
    end)
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
  local function take(v)
    if not name then name = NormalizeName(v) end
  end
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

function ESP.GetBonePos(Character, boneName)
  if not ESPValid(Character) or not boneName then return nil end
  local pos = nil
  pcall(function()
    if type(Character.GetBonePos) == "function" then
      pos = Character:GetBonePos(boneName, { X = 0, Y = 0, Z = 0 })
    end
    if not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0) then
      if type(Character.GetSocketLocation) == "function" then
        pos = Character:GetSocketLocation(boneName)
      end
    end
    if (not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0)) and ESPValid(Character.Mesh) then
      local mesh = Character.Mesh
      if mesh and mesh.GetSocketLocation then
        local mp = mesh:GetSocketLocation(boneName)
        if mp and not (mp.X == 0 and mp.Y == 0 and mp.Z == 0) then pos = mp end
      end
    end
  end)
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

function ESP.IsBoneVisible(pc, camLoc, target, bonePos)
  if not ESPValid(pc) or not ESPValid(target) or not bonePos or not camLoc then return false end
  if not KismetSystemLibraryESP or not KismetSystemLibraryESP.LineTraceSingle then return true end
  local dx = bonePos.X - camLoc.X
  local dy = bonePos.Y - camLoc.Y
  local dz = bonePos.Z - camLoc.Z
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  if dist < 300 then return true end
  TraceStartPos.X = camLoc.X + (dx / dist) * 60
  TraceStartPos.Y = camLoc.Y + (dy / dist) * 60
  TraceStartPos.Z = camLoc.Z + (dz / dist) * 60
  local bVis = false
  pcall(function()
    local bHit = KismetSystemLibraryESP.LineTraceSingle(
      pc, TraceStartPos, bonePos, 0, false, nil, 0, CachedHitResult, true)
    if bHit then
      local hitActor = nil
      if CachedHitResult then
        if type(CachedHitResult.GetActor) == "function" then
          hitActor = CachedHitResult:GetActor()
        elseif CachedHitResult.Actor then
          hitActor = CachedHitResult.Actor
        end
      end
      if ESPValid(hitActor) then
        if hitActor == target then bVis = true end
      end
    else
      bVis = true
    end
  end)
  return bVis
end

function ESP.IsVisible(key, pc, camLoc, Character)
  local now = ESP.Now()
  local cached = ESP.VisCache[key]
  if cached and (now - (cached.t or 0)) < (CFG.VisInterval or 0.15) then
    return cached.b
  end
  local bVis = false
  if ESPValid(Character) and ESPValid(pc) and camLoc then
    local bones = { "head", "spine_03", "pelvis" }
    for _, bn in ipairs(bones) do
      local bp = ESP.GetBonePos(Character, bn)
      if bp and (bp.X ~= 0 or bp.Y ~= 0 or bp.Z ~= 0) then
        if ESP.IsBoneVisible(pc, camLoc, Character, bp) then bVis = true break end
      end
    end
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
  if not center then
    pcall(function() if Character.K2_GetActorLocation then center = Character:K2_GetActorLocation() end end)
  end
  if not center then
    pcall(function() if Game and Game.GetActorLocation then center = Game:GetActorLocation(Character) end end)
  end
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
  local head = { X = center.X, Y = center.Y, Z = center.Z + half }
  local feet = { X = center.X, Y = center.Y, Z = center.Z - half }
  return head, feet
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
          ESP.OffsetX = p0.X
          ESP.OffsetY = p0.Y
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
    ESP.ScaleX = 1.0 / scale
    ESP.ScaleY = 1.0 / scale
    ESP.OffsetX = 0.0
    ESP.OffsetY = 0.0
  end
  return true
end

function ESP.Viewport(pc)
  local w, h = 1920.0, 1080.0
  pcall(function()
    if pc and pc.GetViewportSize then
      local v = ESPV2(0, 0)
      pc:GetViewportSize(v)
      if v and tonumber(v.X) and v.X > 200 then w, h = v.X, v.Y end
    end
  end)
  return w, h
end

function ESP.Project(pc, worldLoc)
  if not pc or not worldLoc then return nil end
  local pix = ESPV2(0, 0)
  local ok = false
  pcall(function()
    local res = pc:ProjectWorldLocationToScreen(worldLoc, pix, true)
    ok = (res == true or res == 1 or (pix and (pix.X ~= 0 or pix.Y ~= 0)))
  end)
  if not ok then return nil end
  return ESPV2(pix.X * (ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0),
               pix.Y * (ESP.ScaleY or 1.0) + (ESP.OffsetY or 0.0)), pix
end

function ESP.SnapOrigin(pc, viewW)
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
  local cx = nil
  if tonumber(cw) and cw > 1 then cx = cw * 0.5
  else cx = (viewW * 0.5) * (ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0) end
  return ESPV2(cx, (CFG.SnapOriginY or 0.0))
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
  if not ESPValid(w) then return end
  pcall(function()
    if SlateColor then w:SetColorAndOpacity(SlateColor(color))
    else w:SetColorAndOpacity(color) end
  end)
end

function ESP.NewLine(color, z)
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
  local dz = CFG.DeadZone or 0.5
  if data.lx1 and data.th == thickness then
    if math.abs((data.lx1 or 0) - x1) < dz and math.abs((data.ly1 or 0) - y1) < dz
    and math.abs((data.lx2 or 0) - x2) < dz and math.abs((data.ly2 or 0) - y2) < dz then
      if data.hidden ~= true then return true end
    end
  end
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then
    ESP.Hide(data)
    return false
  end
  local angle = ((math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)) * 180.0 / math.pi
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
  end
  return true
end

function ESP.DrawVBar(data, x, top, h, thickness)
  if not data or not ESPValid(data.Widget) or not data.Slot then return false end
  if h ~= h or h < 1 then ESP.Hide(data) return false end
  x, top, h = RND(x), RND(top), RND(h)
  local dz = CFG.DeadZone or 0.5
  if data.bx ~= nil then
    if math.abs(data.bx - x) < dz and math.abs(data.bt - top) < dz and math.abs(data.bh - h) < dz then
      if data.hidden ~= true then return true end
    end
  end
  if data.bx == x and data.bt == top and data.bh == h then
    if data.hidden == true then
      pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
      data.hidden = false
    end
    return true
  end
  local ok = pcall(function()
    data.Slot:SetPosition(ESPV2(x, top))
    data.Slot:SetSize(ESPV2(thickness, h))
    data.Widget:SetRenderAngle(0)
    data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if ok then data.bx, data.bt, data.bh = x, top, h data.hidden = false end
  return true
end

function ESP.Hide(data)
  if data and ESPValid(data.Widget) and data.hidden ~= true then
    pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    data.hidden = true
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = nil, nil, nil, nil, nil
    data.bx, data.bt, data.bh = nil, nil, nil
  end
end

function ESP.SetBrush(data, color, colorKey)
  if not data or not ESPValid(data.Widget) then return end
  if colorKey and data.colorKey == colorKey then return end
  pcall(function() data.Widget:SetBrushColor(color) end)
  if colorKey then data.colorKey = colorKey end
end

function ESP.Destroy(data)
  if not data then return end
  local w = data.Widget or data.Container
  if ESPValid(w) then
    pcall(function() w:RemoveFromParent() end)
    pcall(function() w:ConditionalBeginDestroy() end)
  end
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
  local W, H = CFG.CounterW or 300.0, CFG.CounterH or 28.0
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
      pcall(function()
        d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    end
  end
  return ESPV2(cx, (CFG.SnapOriginY or 0.0))
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
    tName:SetText("Player")
    tDist:SetText("0m")
    tState:SetText("Open")
    tName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tDist:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tState:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if tName.SetJustification then tName:SetJustification(1) end
    if tDist.SetJustification then tDist:SetJustification(1) end
    if tState.SetJustification then tState:SetJustification(1) end
  end)

  ESP.SetTextColor(tName, C_WHITE)
  ESP.SetTextColor(tDist, C_WHITE)
  ESP.SetTextColor(tState, C_GREEN)
  ESP.SetFont(tName, CFG.NameFontSize)
  ESP.SetFont(tDist, CFG.DistFontSize)
  ESP.SetFont(tState, CFG.StateFontSize)

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
    bSlot:SetAutoSize(false)
    bSlot:SetSize(ESPV2(120.0, 22.0))
    bSlot:SetAlignment(ESPV2(0.5, 0.5))
    bSlot:SetZOrder(34)

    nSlot:SetAutoSize(false)
    nSlot:SetSize(ESPV2(120.0, 22.0))
    nSlot:SetAlignment(ESPV2(0.5, 0.5))
    nSlot:SetZOrder(36)

    s2:SetAutoSize(true)
    s2:SetAlignment(ESPV2(0.5, 0.5))
    s2:SetZOrder(36)
    s3:SetAutoSize(true)
    s3:SetAlignment(ESPV2(0.5, 0.5))
    s3:SetZOrder(36)
    ms:SetAutoSize(false)
    ms:SetZOrder(35)
  end)
  return { Container = container, TeamBox = teamBox, Name = tName, Dist = tDist, State = tState,
           S0 = bSlot, S1 = nSlot, S2 = s2, S3 = s3, Slot = ms }
end

function ESP.UpdateInfo(key, Character, isBot, teamID, distM, bVisible, headX, headY, footX, footY, boxL, boxR)
  local d = ESP.Infos[key]
  if not d or not ESPValid(d.Container) then
    ESP.Destroy(d)
    d = ESP.CreateInfo()
    ESP.Infos[key] = d
  end
  if not d then return end

  local name = d.CachedName
  if not name then
    name = ESP.ResolveName(Character, isBot)
    d.CachedName = name
  end
  if isBot then name = "Bot" d.CachedName = "Bot" end

  local dl = string.format("%dm", math.max(0, math.floor((tonumber(distM) or 0) + 0.5)))
  local st = bVisible and "Open" or "Close"
  local teamColor = TeamColor(teamID, isBot, key)

  pcall(function()
    if d.LastN ~= name then
      d.Name:SetText(name)
      d.LastN = name
    end
    if d.LastD ~= dl then d.Dist:SetText(dl) d.LastD = dl end
    if d.LastS ~= st then d.State:SetText(st) d.LastS = st end
    if d.LastTeam ~= tostring(teamID) .. ":" .. tostring(isBot) then
      d.TeamBox:SetBrushColor(teamColor)
      d.LastTeam = tostring(teamID) .. ":" .. tostring(isBot)
    end
    if bVisible then ESP.SetTextColor(d.State, C_GREEN)
    else ESP.SetTextColor(d.State, C_RED) end
  end)

  local bannerW = 100.0
  local bannerH = 22.0
  local bx = RND(headX)
  local by = RND(headY - 18.0)
  local barY = RND(footY + 8.0)

  pcall(function()
    d.Slot:SetPosition(ESPV2(bx, by))
    d.Slot:SetSize(ESPV2(bannerW, 70.0))
    d.S0:SetPosition(ESPV2(0.0, 0.0))
    d.S0:SetSize(ESPV2(bannerW, bannerH))
    d.S1:SetPosition(ESPV2(0.0, 0.0))
    d.S1:SetSize(ESPV2(bannerW, bannerH))
    d.S2:SetPosition(ESPV2(bannerW * 0.5, bannerH + 12.0))
    d.S3:SetPosition(ESPV2(bannerW * 0.5, bannerH + 30.0))
    d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)

  d.ix, d.iy = bx, by
end

function ESP.EnsureCorner(key, idx, color)
  local t = ESP.Corners[key]
  if not t then t = {} ESP.Corners[key] = t end
  local d = t[idx]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(color or C_WHITE, 32)
  t[idx] = d
  return d
end

function ESP.EnsureHealthBg(key)
  local d = ESP.HealthBg[key]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(ESPMKC(0.0, 0.0, 0.0, CFG.SideBgAlpha or 0.55), 31)
  ESP.HealthBg[key] = d
  return d
end

function ESP.EnsureHealthFill(key)
  local d = ESP.HealthFill[key]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(C_GREEN, 32)
  ESP.HealthFill[key] = d
  return d
end

function ESP.UpdateHealthBar(key, pct, x, y, w)
  local bg = ESP.EnsureHealthBg(key)
  local fill = ESP.EnsureHealthFill(key)
  if not bg or not fill then return end
  local thickness = CFG.SideBarWidth or 3.5
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
  if fw < 1 then
    ESP.Hide(fill)
    return
  end
  ESP.DrawLine(fill, x, y, x + fw, y, thickness)
end

function ESP.EnsureMark(key, idx)
  return nil
end

function ESP.EnsureSnap(key)
  local d = ESP.Lines[key]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(C_GREEN, 30)
  ESP.Lines[key] = d
  return d
end

function ESP.HideTarget(key)
  local c = ESP.Corners[key]
  if c then for i = 1, 8 do ESP.Hide(c[i]) end end
  ESP.Hide(ESP.HealthBg[key])
  ESP.Hide(ESP.HealthFill[key])
  local m = ESP.Marks[key]
  if m then for i = 1, 4 do ESP.Hide(m[i]) end end
  ESP.Hide(ESP.Lines[key])
  local inf = ESP.Infos[key]
  if inf and ESPValid(inf.Container) then
    pcall(function() inf.Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
  end
end

function ESP.ReleaseTarget(key)
  local c = ESP.Corners[key]
  if c then for i = 1, 8 do ESP.Destroy(c[i]) end end
  ESP.Corners[key] = nil
  ESP.Destroy(ESP.HealthBg[key])
  ESP.HealthBg[key] = nil
  ESP.Destroy(ESP.HealthFill[key])
  ESP.HealthFill[key] = nil
  local m = ESP.Marks[key]
  if m then for i = 1, 4 do ESP.Destroy(m[i]) end end
  ESP.Marks[key] = nil
  ESP.Destroy(ESP.Lines[key])
  ESP.Lines[key] = nil
  ESP.Destroy(ESP.Infos[key])
  ESP.Infos[key] = nil
  ESP.VisCache[key] = nil
end

function ESP.ResetWidgets()
  for _, d in pairs(ESP.Lines) do ESP.Destroy(d) end
  for _, t in pairs(ESP.Corners) do for _, d in pairs(t) do ESP.Destroy(d) end end
  for _, d in pairs(ESP.HealthBg) do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthFill) do ESP.Destroy(d) end
  for _, t in pairs(ESP.Marks) do for _, d in pairs(t) do ESP.Destroy(d) end end
  for _, d in pairs(ESP.Infos) do ESP.Destroy(d) end
  ESP.Lines = {}
  ESP.Corners = {}
  ESP.HealthBg = {}
  ESP.HealthFill = {}
  ESP.Marks = {}
  ESP.Infos = {}
  ESP.VisCache = {}
  if ESP.Counter then ESP.Destroy(ESP.Counter) end
  ESP.Counter = nil
  ESP.Canvas = nil
  ESP.EnemyCache = {}
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
  local function addPawn(ch)
    if not ESPValid(ch) or ch == me or not ESP.IsAlive(ch) then return end
    local key = ESP.GetPlayerKey(ch)
    if seen[key] then return end
    local team = ESP.GetTeamID(ch)
    if myTeam ~= nil and team ~= nil and tostring(team) == tostring(myTeam) then return end
    local loc = ESP.ActorLocation(ch)
    local dm = ESP.DistMeters(myLoc, loc)
    seen[key] = true
    local isBot = ESP.IsBot(ch)
    if isBot then nBot = nBot + 1 else nReal = nReal + 1 end
    list[#list + 1] = { Character = ch, Key = key, IsBot = isBot, TeamID = team, Distance = dm }
  end

  if pawns then
    for _, ch in pairs(pawns) do addPawn(ch) end
  end
  table.sort(list, function(a, b) return (a.Distance or 99999) < (b.Distance or 99999) end)
  local trimmed = {}
  local maxR = CFG.MaxTracked or 16
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
    ESP.LastScan = -999.0
    ESP.LastTransform = -999.0
  end
  local canvas = ESP.GetCanvas()
  if not canvas then return end
  local now = ESP.Now()
  local pc = ESP.GetController()
  if (now - ESP.LastScan) >= (ESP.ScanInterval or 0.35) then
    local r, b
    pc, r, b = ESP.Scan()
    ESP.LastScan = now
    ESP.RealCount, ESP.BotCount = r or 0, b or 0
  end
  pc = pc or ESP.GetController()
  if not pc then return end
  if (now - (ESP.LastTransform or -999.0)) >= (ESP.TransformInterval or 0.50) then
    ESP.UpdateCanvasTransform(pc)
    ESP.LastTransform = now
  end
  local vw, vh = ESP.Viewport(pc)
  local hyst = CFG.SizeHyst or 2.0
  if math.abs(vw - (ESP.ViewW or 0)) > hyst or math.abs(vh - (ESP.ViewH or 0)) > hyst then
    ESP.ViewW, ESP.ViewH = vw, vh
  else
    vw, vh = ESP.ViewW, ESP.ViewH
  end
  local origin = ESP.UpdateCounter(ESP.RealCount or 0, ESP.BotCount or 0, pc, vw)
  if not origin then return end
  local camLoc = ESP.GetCamLoc(pc)

  local active = {}
  for _, item in ipairs(ESP.EnemyCache) do
    local c = item.Character
    local key = item.Key
    if ESPValid(c) and ESP.IsAlive(c) then
      local head, feet = ESP.GetHeadFeet(c)
      if head and feet then
        local headS, headPix = ESP.Project(pc, head)
        local feetS, feetPix = ESP.Project(pc, feet)
        if headS and feetS and headPix and feetPix then
          local m = CFG.ScreenMargin or 500
          local on = headPix.X > -m and headPix.X < vw + m
            and headPix.Y > -m and headPix.Y < vh + m
            and feetPix.X > -m and feetPix.X < vw + m
            and feetPix.Y > -m and feetPix.Y < vh + m
          if on then
            local H = feetS.Y - headS.Y
            if H >= (CFG.BoxMinHeight or 1) and H <= vh * 1.5 then
              active[key] = true
              local W = H * (CFG.BoxWidthFactor or 0.62)
              W = math.max(CFG.BoxMinWidth or 22, math.min(CFG.BoxMaxWidth or 320, W))
              local padT = H * (CFG.HeadExtra or 0)
              local padB = H * (CFG.FootExtra or 0)
              local cx = (headS.X + feetS.X) * 0.5
              local L = cx - W * 0.5
              local R = cx + W * 0.5
              local T = headS.Y - padT
              local B = feetS.Y + padB

              local corners = ESP.Corners[key]
              if corners then for i = 1, 8 do ESP.Hide(corners[i]) end end

              local pct = ESP.GetHealthPct(c)
              local hbY = headS.Y + 8.0
              ESP.UpdateHealthBar(key, pct, L, hbY, R - L)

              local marks = ESP.Marks[key]
              if marks then for i = 1, 4 do ESP.Hide(marks[i]) end end

              ESP.DrawLine(ESP.EnsureSnap(key), origin.X, origin.Y, headS.X, headS.Y,
                           CFG.SnapThickness or 1.8)

              local bVis = ESP.IsVisible(key, pc, camLoc, c)
              ESP.UpdateInfo(key, c, item.IsBot, item.TeamID, item.Distance, bVis,
                            headS.X, headS.Y, cx, B, L, R)
            else
              ESP.HideTarget(key)
            end
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
  local function stillActive(k)
    return active[k] == true
  end
  for k, _ in pairs(ESP.Lines) do if not stillActive(k) then ESP.HideTarget(k) end end
  for k, _ in pairs(ESP.Infos) do if not stillActive(k) then ESP.HideTarget(k) end end
  for k, _ in pairs(ESP.Corners) do
    if not stillActive(k) and not seenCache[k] then ESP.ReleaseTarget(k) end
  end
  for k, _ in pairs(ESP.HealthBg) do
    if not seenCache[k] and not stillActive(k) then ESP.ReleaseTarget(k) end
  end
end

function ESP.Tick()
  pcall(ESP.Update)
end

function ESP.AttachTimers()
  pcall(function()
    local pc = ESP.GetController()
    if ESPValid(pc) and pc.AddGameTimer then
      if ESP._TimerPC == pc and ESP._TimerHooked then return end
      ESP._TimerPC = pc
      ESP._TimerHooked = true
      pc:AddGameTimer(ESP.LightInterval or 0.033, true, function()
        if ESP.bActive then pcall(ESP.Tick) end
      end)
    else
      pcall(function()
        require("timer").SetGameTimer(1.0, false, function()
          ESP._TimerHooked = false
          ESP.AttachTimers()
        end)
      end)
    end
    pcall(function() require("timer").SetGameTimer(5.0, false, function() ESP.AttachTimers() end) end)
  end)
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

local _ESPStartedPC = nil
local function ESPStartAll()
  pcall(function()
    local pc = nil
    if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
    if not ESPValid(pc) then pc = ESP.GetController() end
    if ESPValid(pc) then
      if pc ~= _ESPStartedPC then
        _ESPStartedPC = pc
        ESP._TimerHooked = false
        ESP._TimerPC = nil
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

-- ============================================================
-- [4] SHIELD / BANSHIELD / ESP-NATIVE TABLES
-- ============================================================
local Shield = {}

local function NoOp() return true end
local function NoFalse() return false end
local function NoZero() return 0 end
local function NoNil() return nil end
local function NoList() return {} end
local function NoString() return "" end

local function MuteObject(obj)
  if type(obj) ~= "table" then return end
  for k, v in pairs(obj) do
    if type(v) == "function" and type(k) == "string" and
      (k:find("Report") or k:find("Send") or k:find("Upload") or k:find("Verify") or
       k:find("Check") or k:find("Validate") or k:find("Scan") or k:find("Detect") or
       k:find("Collect") or k:find("Flow") or k:find("Heartbeat") or k:find("Record") or
       k:find("Trace") or k:find("Replay") or k:find("Save")) then
      pcall(function() obj[k] = NoOp end)
    end
  end
end

local BanShield = {}

function BanShield.KillBanFunctions()
  pcall(function()
    local banFuncs = {
      "BanPlayer", "BanUser", "ReportBan", "SendBanReport",
      "DetectBan", "CheckBan", "ValidateBan", "ProcessBan",
      "BanKick", "KickPlayer", "ForceLogout", "DisconnectPlayer",
      "ReportSuspicious", "ReportCheat", "ReportHack",
      "OnCheatDetected", "OnHackDetected", "OnViolationDetected",
      "AntiCheatReport", "CheatDetection", "ViolationReport",
      "SecurityViolation", "IntegrityCheck", "SignatureVerify",
      "TssSdkReport", "TssSdkBan", "TssSdkKick",
      "ReportModifierException", "ReportMemoryException",
      "ReportAvatarException", "ReportSpeedHack",
      "ReportWallHack", "ReportAimBot", "ReportESP",
      "ReportModdedFiles", "DetectCheat", "OnBanNotice", "OnKickNotice",
      "ProcessBanNotice", "HandleBanNotice", "ShowBanUI", "ShowKickUI"
    }
    for _, fn in ipairs(banFuncs) do
      if _G[fn] then _G[fn] = function() return true end end
      if _G.GameplayCallbacks and _G.GameplayCallbacks[fn] then
        _G.GameplayCallbacks[fn] = function() return true end
      end
    end
  end)
end

function BanShield.SpoofSubsystems()
  pcall(function()
    local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if not mgr then return end
    local banSubs = {
      "AntiCheatSubsystem", "BanSubsystem", "PlayerBanSubsystem",
      "CheatDetectionSubsystem", "SecuritySubsystem",
      "BanManagerSubsystem", "KickBanSubsystem",
      "TssSdkSubsystem", "HiggsBosonSubsystem",
      "IntegrityCheckSubsystem", "SignatureVerifySubsystem",
      "PlayerSecurityInfoSubsystem", "OperationalStatsSubsystem",
      "ModifierExceptionSubsystem", "MemoryCheckSubsystem"
    }
    for _, name in ipairs(banSubs) do
      local sub = mgr:Get(name)
      if sub then
        pcall(function()
          for k, v in pairs(sub) do
            if type(v) == "function" and type(k) == "string" then
              if k:find("Ban") or k:find("Kick") or k:find("Report") or
                 k:find("Detect") or k:find("Check") or k:find("Verify") or
                 k:find("Validate") or k:find("Process") or k:find("Send") or
                 k:find("Upload") or k:find("Notify") or k:find("Warn") then
                sub[k] = function() return true end
              end
            end
          end
          sub.bBanned = false
          sub.bKicked = false
          sub.bSuspended = false
          sub.BanCount = 0
          sub.WarningCount = 0
          sub.SuspicionScore = 0
        end)
      end
    end
  end)
end

function BanShield.BlockNet()
  pcall(function()
    if NetUtil and NetUtil.SendPacket then
      local orig = NetUtil.SendPacket
      local banPackets = {
        ["ReportCheat"]=1, ["ReportHack"]=1, ["ReportSuspicious"]=1,
        ["ReportBan"]=1, ["SendBanReport"]=1, ["BanPlayer"]=1,
        ["KickPlayer"]=1, ["CheatDetection"]=1, ["AntiCheatReport"]=1,
        ["ViolationReport"]=1, ["SecurityViolation"]=1,
        ["IntegrityCheck"]=1, ["SignatureVerify"]=1,
        ["TssSdkReport"]=1, ["TssSdkBan"]=1, ["TssSdkKick"]=1,
        ["tss_sdk_report"]=1, ["tss_sdk_ban"]=1, ["tss_sdk_kick"]=1,
        ["detect_cheat"]=1, ["ban_player"]=1, ["kick_player"]=1,
        ["report_aim_bot"]=1, ["report_esp"]=1, ["report_speed_hack"]=1,
        ["report_wall_hack"]=1, ["report_modded_files"]=1,
        ["client_anti_cheat_report"]=1, ["report_memory_exception"]=1,
        ["report_avatar_exception"]=1, ["report_script_exception"]=1,
        ["report_lua_violation"]=1, ["report_pak_modified"]=1,
        ["report_signature_fail"]=1, ["report_integrity_fail"]=1,
        ["OperationalStats"]=1, ["ReportOperationalStats"]=1,
        ["on_tss_sdk_anti_data"]=1, ["on_ban_notice"]=1, ["on_kick_notice"]=1,
        ["report_players_ping"]=1, ["report_player_ip"]=1,
        ["report_net_saturate"]=1, ["report_unrealnet_exception"]=1
      }
      NetUtil.SendPacket = function(packetName, ...)
        if banPackets[packetName] then return nil end
        return orig(packetName, ...)
      end
    end

    if _G.SendRPC then
      local origRpc = _G.SendRPC
      _G.SendRPC = function(rpcName, ...)
        if not rpcName then return origRpc(rpcName, ...) end
        local lower = string.lower(tostring(rpcName))
        if lower:find("ban") or lower:find("kick") or lower:find("report")
          or lower:find("cheat") or lower:find("hack") or lower:find("violation")
          or lower:find("verify") or lower:find("integrity") then
          return nil
        end
        return origRpc(rpcName, ...)
      end
    end
  end)
end

function BanShield.KillTssSdk()
  pcall(function()
    local tss = package.loaded["TssSdk"] or _G.TssSdk
    if tss then
      tss.GetFileMD5 = function() return "00000000000000000000000000000000" end
      tss.VerifyFileSignature = function() return true end
      tss.SendReportInfo = function() return true end
      tss.ScanMemory = function() return true end
      tss.IsEmulator = function() return false end
      tss.GetTssSdkReportInfo = function() return "" end
      tss.CheckEnvironment = function() return true end
      tss.VerifyProcess = function() return true end
      tss.ReportBan = function() return true end
      tss.ReportCheat = function() return true end
      tss.BanPlayer = function() return true end
      tss.KickPlayer = function() return true end
      tss.OnRecvData = function() return end
    end
  end)
end

function BanShield.KillGameState()
  pcall(function()
    local GD = require("GameLua.GameCore.Data.GameplayData")
    if not GD then return end
    local gs = GD.GetGameState and GD.GetGameState()
    if not gs then return end
    pcall(function()
      gs.BanPlayer = function() return true end
      gs.KickPlayer = function() return true end
      gs.ReportCheat = function() return true end
      gs.ReportHack = function() return true end
      gs.OnCheatDetected = function() return true end
      gs.OnHackDetected = function() return true end
      gs.AntiCheatReport = function() return true end
      gs.ShowBanNotice = function() return end
      gs.ShowKickNotice = function() return end
      gs.ProcessBanNotice = function() return end
    end)
  end)
end

function BanShield.SpoofBanStatus()
  pcall(function()
    local GD = require("GameLua.GameCore.Data.GameplayData")
    if not GD then return end
    local pc = GD.GetPlayerController and GD.GetPlayerController()
    if not pc then return end
    pcall(function()
      pc.bBanned = false
      pc.bKicked = false
      pc.bSuspended = false
      pc.BanReason = nil
      pc.BanTime = 0
      pc.BanCount = 0
      pc.WarningCount = 0
      pc.SuspicionScore = 0
    end)
    pcall(function()
      local ps = pc.GetPlayerStateSafety and pc:GetPlayerStateSafety()
      if ps then
        ps.bBanned = false
        ps.bKicked = false
        ps.bSuspended = false
        ps.BanCount = 0
        ps.WarningCount = 0
        ps.SuspicionScore = 0
      end
    end)
  end)
end

function BanShield.Install()
  if A.Up.BanShielded then return end
  A.Up.BanShielded = true
  BanShield.KillBanFunctions()
  BanShield.SpoofSubsystems()
  BanShield.BlockNet()
  BanShield.KillTssSdk()
  BanShield.KillGameState()
  BanShield.SpoofBanStatus()
  print("[BAN BYPASS 4.6] All ban systems neutralized")
end

function Shield.NeutralizeLoaders()
  pcall(function()
    if slua and slua.getSignature then slua.getSignature = NoZero end
    local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
    if loader then
      loader.verifyBytecode = NoOp
      loader.checkIntegrity = NoOp
      if loader.disableSignatureCheck then loader.disableSignatureCheck = NoOp end
    end
    local ser = package.loaded["slua.serialize"]
    if ser then ser.check = NoOp; ser.verify = NoOp end
    if jit and jit.attach then jit.attach(function() end, "bc") end
    if _G.slua_verify then _G.slua_verify = NoOp end
    if _G.check_slua_integrity then _G.check_slua_integrity = NoOp end
  end)
end

function Shield.NeutralizeHashes()
  pcall(function()
    local console = import("KismetSystemLibrary")
    if console then
      console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
      console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
      console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
      console.ExecuteConsoleCommand(nil, "sig.Check 0")
      console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
    end
    local CMode = import("CreativeModeBlueprintLibrary")
    if CMode then
      CMode.MD5HashByteArray = NoString
      CMode.MD5HashFile = NoString
      CMode.GetContentDiffData = function() return true, "OK" end
      CMode.VerifyFileIntegrity = NoOp
    end
    if _G.MD5Hash then _G.MD5Hash = NoString end
    if _G.CRC32 then _G.CRC32 = NoZero end
    if _G.SHA1 then _G.SHA1 = NoString end
    local fhc = package.loaded["common.file_hash_checker"]
    if fhc then
      fhc.CheckFileMD5 = NoOp
      fhc.VerifyAll = NoOp
      fhc.GetHash = NoString
    end
    local tss = package.loaded["TssSdk"] or _G.TssSdk
    if tss then
      tss.GetFileMD5 = NoString
      tss.VerifyFileSignature = NoOp
      tss.OnRecvData = function(data)
        if type(data) ~= "string" then return end
        local lower = string.lower(data)
        if lower:find("report", 1, true) or lower:find("exception", 1, true) or lower:find("cheat", 1, true) or lower:find("violation", 1, true) or lower:find("hack", 1, true) or lower:find("verify", 1, true) then return end
      end
      tss.SendReportInfo = NoNil
      tss.ScanMemory = NoOp
      tss.IsEmulator = NoFalse
      tss.GetTssSdkReportInfo = NoString
      tss.CheckEnvironment = NoOp
      tss.VerifyProcess = NoOp
    end
    local stx = import("STExtraBlueprintFunctionLibrary")
    if stx then
      stx.CheckMD5 = NoOp
      stx.GetMD5 = NoString
      stx.VerifyFile = NoOp
    end
  end)
end

function Shield.NeutralizeLogs()
  pcall(function()
    local SMTD = import("ScreenshotMTDer")
    if SMTD then
      SMTD.MTDePicture = NoString
      SMTD.ReMTDePicture = NoString
      SMTD.HasCaptured = NoOp
      SMTD.TakeScreenshot = NoNil
    end
    local tl = package.loaded["TLog"] or _G.TLog
    if tl then
      tl.Info, tl.Warning, tl.Error, tl.Debug = NoOp, NoOp, NoOp, NoOp
      tl.Report, tl.Send, tl.Flush = NoOp, NoOp, NoOp
    end
    local cs = package.loaded["CrashSight"] or _G.CrashSight
    if cs then
      cs.ReportException, cs.SetCustomData, cs.Log = NoOp, NoOp, NoOp
      cs.SendCrash, cs.ReportUserException = NoOp, NoOp
    end
    local gr = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
    if gr then
      gr.BugglyPostExceptionFull = NoFalse
      gr.CheckCanBugglyPostException = NoFalse
      gr.ReplayReportData, gr.ReportGameException, gr.PostException = NoOp, NoOp, NoOp
    end
    local ctr = package.loaded["client.slua.logic.report.ClientToolsReport"]
    if ctr then ctr.SendReport, ctr.SendException, ctr.UploadLog = NoOp, NoOp, NoOp end
    for _, sdk in ipairs({"Firebase", "Adjust", "AppsFlyer", "FacebookAnalytics", "GameAnalytics"}) do
      local s = _G[sdk]
      if s then
        s.logEvent, s.trackEvent = NoOp, NoOp
        s.setEnabled = NoFalse
        s.sendEvent, s.report = NoOp, NoOp
      end
    end
  end)
end

function Shield.NeutralizeSkins()
  pcall(function()
    local pt = package.loaded["client.slua.logic.download.report.puffer_tlog"]
    if pt then
      pt.ReportEvent, pt.ReportDownloadResult = NoOp, NoOp
      pt.ReportODPTDError, pt.ReportSkinError = NoOp, NoOp
    end
    local av = package.loaded["AvatarUtils"]
    if av then
      av.CheckIsWeaponInBlackList = NoFalse
      av.IsValidAvatar = NoOp
      av.CheckAvatarIntegrity = NoOp
      av.ReportInvalidAvatar = NoNil
    end
    local eq = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
    if eq then eq.Report, eq.SendException = NoOp, NoOp end
  end)
end

local ReportFlowNames = {
  "ReportAimFlow", "ReportHitFlow", "ReportAttackFlow", "ReportSecAttackFlow",
  "ReportFireArms", "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior",
  "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick",
  "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow",
  "ReportSecTgameMovingFlow", "ReportParachuteData", "ReportEquipmentFlow",
  "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord",
  "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate",
  "ReportCircleFlow", "ReportSecMrpcsFlow", "SendTssSdkAntiDataToLobby",
  "SendClientStats", "SendServerAvgTickDelta", "SwiftHawk", "ClientSwiftHawk",
  "ClientSwiftHawkWithParams", "ClientSecMrpcsFlow", "MrpcsData"
}
local BlockPacketNames = {
  ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportFireArms"]=1,
  ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1, ["ReportPlayerBehavior"]=1,
  ["ReportTeammatHurt"]=1, ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1,
  ["report_parachute_data"]=1, ["on_tss_sdk_anti_data"]=1, ["ReportAimFlow"]=1,
  ["ReportHitFlow"]=1, ["ReportCircleFlow"]=1, ["report_players_ping"]=1,
  ["report_player_ip"]=1, ["report_net_saturate"]=1, ["report_speed_hack"]=1,
  ["report_wall_hack"]=1, ["report_aim_bot"]=1, ["report_esp_usage"]=1,
  ["report_modded_files"]=1, ["detect_cheat"]=1, ["ban_player"]=1,
  ["client_anti_cheat_report"]=1, ["ClientSecMrpcsFlow"]=1, ["MrpcsData"]=1,
  ["CheckReportSecAttackFlow"]=1, ["CheckReportSecAttackFlowWithAttackFlow"]=1,
  ["RPC_ClientCoronaLab"]=1, ["CoronaLabReport"]=1, ["CoronaLabData"]=1,
  ["PlayerSecurityInfo"]=1, ["ReportSecurityInfo"]=1, ["SendSecurityData"]=1,
  ["ClientCircleFlow"]=1, ["bReportedModifierException"]=1, ["ReportModifierException"]=1,
  ["RPC_Server_ReportSimulateCharacterLocation"]=1, ["ReportSimulateCharacterLocation"]=1,
  ["RPC_Client_ShootVertifyRes"]=1, ["BulletHitInfoUploadData"]=1, ["ShootVerifyFailed"]=1,
  ["report_unrealnet_exception"]=1, ["tss_sdk_report"]=1, ["SwiftHawk"]=1,
  ["ClientSwiftHawk"]=1, ["ClientSwiftHawkWithParams"]=1, ["SwiftHawkReport"]=1,
  ["SwiftHawkData"]=1, ["AntiCheatReport"]=1, ["CheatDetection"]=1, ["ViolationReport"]=1,
  ["SecurityViolation"]=1, ["IntegrityCheck"]=1, ["SignatureVerify"]=1,
  ["OperationalStats"]=1, ["ReportOperationalStats"]=1, ["OperationalStatsReport"]=1
}
local BlockRpcNames = {
  "RPC_Server_ClientSecMrpcsFlow", "RPC_Server_SwiftHawk",
  "RPC_Server_ClientSwiftHawkWithParams", "RPC_Server_ReportSimulateCharacterLocation",
  "RPC_Client_ShootVertifyRes", "RPC_ClientCoronaLab", "RPC_OperationalStats"
}
local KillSubSystems = {
  "AFKReportorSubsystem", "ClientDataStatistcsSubsystem", "AvatarExceptionSubsystem",
  "ShootVerifySubSystemClient", "MemoryCheckSubsystem", "SpeedCheckSubsystem",
  "WallCheckSubsystem", "FileCheckSubsystem", "BehaviorScoreSubsystem",
  "CoronaLabSubsystem", "PlayerSecurityInfoSubsystem", "ClientCircleFlowSubsystem",
  "ModifierExceptionSubsystem", "SimulateCharacterSubsystem",
  "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem",
  "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem",
  "GameReportSubsystem", "ReplaySubsystem", "SwiftHawkSubsystem",
  "AntiCheatSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem",
  "MD5CheckSubsystem", "PakVerifySubsystem", "OperationalStatsSubsystem",
  "MrpcsFlowSubsystem", "CircleFlowSubsystem",
  "ClientESPDetectionSubsystem", "ClientAimTrackingSubsystem",
  "ClientRenderCheckSubsystem", "ClientMemoryGuardSubsystem",
  "ClientKernelCheckSubsystem", "ClientWallhackDetectionSubsystem",
  "ClientAntiCheatSubsystem", "ClientSecMrpcsFlowSubsystem",
  "ShootVerifySubSystemClient"
}

function Shield.NeutralizeSubSystems()
  pcall(function()
    local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if mgr then
      for _, name in ipairs(KillSubSystems) do
        local sub = mgr:Get(name)
        if sub then
          MuteObject(sub)
          for _, tm in ipairs({"timer", "heartbeatTimer", "reportTimer"}) do
            if sub[tm] then pcall(function() sub:RemoveGameTimer(sub[tm]) end) end
          end
        end
      end
    end
    local flowRunner = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
    if flowRunner then
      flowRunner.CheckAvatarException, flowRunner.CheckAvatarExceptionOnce = NoOp, NoOp
      flowRunner.ReportAvatarException = NoNil
      flowRunner.CheckSlotMeshVisible, flowRunner.CheckPawnVisible = NoFalse, NoFalse
      flowRunner.CheckCanBugglyPostException = NoFalse
    end
    local rep = package.loaded["client.slua.logic.replay.logic_report_replay"]
    if rep then rep.ReportReplay, rep.SendReportReq, rep.UploadReplay = NoOp, NoOp, NoOp end
  end)
end

function Shield.NeutralizeGlobalFlows()
  pcall(function()
    if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
    local GC = _G.GameplayCallbacks
    for _, f in ipairs(ReportFlowNames) do
      if _G[f] then _G[f] = NoOp end
      GC[f] = NoOp
    end
    GC.CheckReportSecAttackFlowWithAttackFlow = NoFalse
    GC.CheckReportSecAttackFlow = NoFalse
    for _, f in ipairs({"IsEnableReportMrpcsInCircleFlow", "IsEnableReportMrpcsInPartCircleFlow", "IsEnableReportMrpcsFlow", "IsEnableReportAttackFlow", "IsEnableReportHitFlow", "IsEnableReportCircleFlow"}) do
      if _G[f] then _G[f] = NoFalse end
    end
    local origState = GC.OnDSPlayerStateChanged
    GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
      local s = State and string.lower(tostring(State)) or ""
      local danger = {
        ["cheatdetected"]=1, ["connectionlost"]=1, ["connectiontimeout"]=1,
        ["connectionexception"]=1, ["netdrivererror"]=1, ["banned"]=1, ["kicked"]=1,
        ["suspended"]=1, ["violationdetected"]=1, ["integrityfailure"]=1, ["securityviolation"]=1
      }
      if danger[s] then return end
      if origState and type(origState) == "function" then
        return origState(UID, State, bPure, bSafe, Param)
      end
    end
    GC.OnPlayerNetConnectionClosed = NoNil
    GC.OnPlayerActorChannelError = NoNil
    GC.OnPlayerRPCValidateFailed = NoNil
    GC.OnPlayerSpectateException = NoNil
    GC.OnShutdownAfterError = NoNil
  end)
end

local _NetShielded = false
function Shield.NeutralizeNet()
  if _NetShielded then return end
  pcall(function()
    if NetUtil and NetUtil.SendPacket then
      local original = NetUtil.SendPacket
      NetUtil.SendPacket = function(packetName, ...)
        if BlockPacketNames[packetName] then return nil end
        return original(packetName, ...)
      end
    end
    if _G.SendRPC then
      local originalRpc = _G.SendRPC
      _G.SendRPC = function(rpcName, ...)
        for _, b in ipairs(BlockRpcNames) do
          if rpcName == b then return nil end
        end
        return originalRpc(rpcName, ...)
      end
    end
    _NetShielded = true
  end)
end

function Shield.NeutralizeHiggs()
  pcall(function()
    local Higgs = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
    if Higgs then
      local methods = {
        "ControlMHActive", "Tick", "OnTick", "MHActiveLogic", "TriggerAvatarCheck",
        "StartAvatarCheck", "ReportItemID", "ReceiveAnyDamage", "OnWeaponHitRecord",
        "ShowSecurityAlert", "ServerReportAvatar", "ClientReportNetAvatar", "SendHisarData",
        "ValidateSecurityData", "StaticShowSecurityAlertInDev", "RPC_Client_ShootVertifyRes",
        "RPC_Server_ReportSimulateCharacterLocation", "DisableHiggsBoson", "CheckMHActive",
        "ReportViolation", "ProcessSecurityEvent", "ValidatePlayer", "CheckIntegrity"
      }
      for _, m in ipairs(methods) do if Higgs[m] then Higgs[m] = NoNil end end
      Higgs.GetNetAvatarItemIDs = NoList
      Higgs.GetCurWeaponSkinID = NoZero
      Higgs.IsMHActive = NoFalse
      Higgs.bMHActive = false
      Higgs.bCallPreReplication = false
      if Higgs.BlackList then
        local keys = {}
        for k in pairs(Higgs.BlackList) do table.insert(keys, k) end
        for _, k in ipairs(keys) do Higgs.BlackList[k] = nil end
      end
    end
    _G.BlackList = {}
    if _G.AvatarCheckCallback then
      _G.AvatarCheckCallback.StartAvatarCheck = NoNil
      _G.AvatarCheckCallback.OnReportItemID = NoNil
      _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(pc)
        if pc and slua.isValid(pc) then
          if pc.HiggsBosonComponent then
            pcall(function() pc.HiggsBosonComponent:ControlMHActive(0) end)
            pc.HiggsBosonComponent.bMHActive = false
          end
          if pc.HiggsBoson then
            pcall(function() pc.HiggsBoson:ControlMHActive(0) end)
            pc.HiggsBoson.bMHActive = false
          end
        end
      end
    end
  end)
end

function Shield.NeutralizePlayers()
  pcall(function()
    for _, c in ipairs({"PlayerSecurityInfoCollector", "PlayerSecurityInfo", "SecurityInfoCollector", "ClientSecurityCollector", "PlayerAntiCheatCollector"}) do
      if _G[c] then MuteObject(_G[c]) end
    end
    local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if mgr then
      local sec = mgr:Get("PlayerSecurityInfoSubsystem")
      if sec then
        sec.ReportData, sec.CollectData, sec.SendToServer = NoNil, NoNil, NoNil
        sec.CheckCheat = NoFalse
        sec.ValidatePlayer = NoOp
      end
      local sw = mgr:Get("SwiftHawkSubsystem")
      if sw then sw.ReportData, sw.SendReport, sw.CollectTelemetry = NoNil, NoNil, NoNil end
      local cr = mgr:Get("ModifierExceptionSubsystem")
      if cr then
        cr.ReportException, cr.ReportModifierError = NoNil, NoNil
        cr.CheckModifier, cr.ValidateModifier = NoOp, NoOp
      end
      local sm = mgr:Get("SimulateCharacterSubsystem")
      if sm then sm.ReportLocation, sm.SendLocationData = NoNil, NoNil; sm.VerifyLocation = NoOp end
      local sv = mgr:Get("ShootVerifySubSystemClient")
      if sv then
        sv.OnShootVerifyFailed, sv.SendVerifyData, sv.ReportBulletHit, sv.UploadHitInfo = NoNil, NoNil, NoNil, NoNil
        sv.VerifyShot = NoOp
      end
    end
    if _G.bReportedModifierException then _G.bReportedModifierException = false end
    if _G.BulletHitInfoUploadData then MuteObject(_G.BulletHitInfoUploadData) end
  end)
end

function Shield.NeutralizeStats()
  pcall(function()
    local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    local ops = (mgr and mgr:Get("OperationalStatsSubsystem")) or _G.OperationalStatsSubsystem
    if ops then
      ops.ReportOperationalStats, ops.AddOperationalStats = NoNil, NoNil
      ops.HandleTouchBegin, ops.HandleTouchEnd = NoNil, NoNil
      ops.OnInit, ops.HandleEnterFighting, ops.OnBattleResult = NoNil, NoNil, NoNil
      ops.StatsData = {}
    end
  end)
end

function Shield.NeutralizeLoading()
  pcall(function()
    local flags = {"ENABLE_REPORT", "ENABLE_ANTI_CHEAT", "ENABLE_SECURITY", "ENABLE_TELEMETRY", "ENABLE_ANALYTICS", "ENABLE_CRASH_REPORT", "ENABLE_PERFORMANCE_REPORT"}
    for _, f in ipairs(flags) do if _G[f] then _G[f] = false end end
    if _G._RequireHijacked then return end
    _G._RequireHijacked = true
    local realRequire = require
    local poisoned = {"HiggsBosonComponent", "PlayerSecurityInfoSubsystem", "CoronaLabSubsystem", "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "ShootVerifySubSystemClient", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem", "OperationalStatsSubsystem"}
    _G.require = function(moduleName)
      if package.loaded[moduleName] then return realRequire(moduleName) end
      for _, bad in ipairs(poisoned) do
        if moduleName:find(bad, 1, true) then return {} end
      end
      return realRequire(moduleName)
    end
  end)
end

function Shield.NeutralizeSweep()
  local needle = {"verify", "integrity", "signature", "filecheck", "file_check", "hashcheck", "hash_check", "tss", "security", "report"}
  local seen = {}
  pcall(function()
    local function Watch(mod)
      if type(mod) ~= "table" or seen[mod] then return end
      seen[mod] = true
      MuteObject(mod)
    end
    for key, mod in pairs(package.loaded) do
      if type(key) == "string" then
        local low = string.lower(key)
        for _, n in ipairs(needle) do
          if string.find(low, n, 1, true) then Watch(mod) break end
        end
      end
    end
    for key, mod in pairs(_G) do
      if type(key) == "string" then
        local low = string.lower(key)
        for _, n in ipairs(needle) do
          if string.find(low, n, 1, true) then Watch(mod) break end
        end
      end
    end
  end)
end

function Shield.Hum()
  A.Up.Heartbeat = math.random(15, 45)
  A.Up.PingJitter = math.random(-12, 18)
  A.Up.FakeKd = 0.9 + math.random() * 1.9
  A.Up.FakeHead = 9 + math.random() * 22
  pcall(function()
    if debug and debug.getinfo then
      local origin = debug.getinfo
      debug.getinfo = function(level, what)
        local info = origin(level, what)
        if info and info.source then
          local src = info.source
          if string.find(src, "BRPlayerCharacterBase", 1, true) or string.find(src, "AegisShell", 1, true) then
            info.source = "ProtectedSource"
            info.short_src = "ProtectedSource"
          end
        end
        return info
      end
    end
  end)
  pcall(function()
    if debug then
      if debug.sethook then debug.sethook = function() end end
      if debug.getlocal then debug.getlocal = function() end end
      if debug.setupvalue then debug.setupvalue = function() end end
    end
    if string and string.dump then
      string.dump = function() return "" end
    end
  end)
end

function Shield.InstallAll()
  if A.Up.Shielded then return end
  A.Up.Shielded = true
  BanShield.Install()
  Shield.NeutralizeLoaders()
  Shield.NeutralizeHashes()
  Shield.NeutralizeLogs()
  Shield.NeutralizeSkins()
  Shield.NeutralizeSubSystems()
  Shield.NeutralizeGlobalFlows()
  Shield.NeutralizeNet()
  Shield.NeutralizeHiggs()
  Shield.NeutralizePlayers()
  Shield.NeutralizeStats()
  Shield.NeutralizeSweep()
  Shield.NeutralizeLoading()
  Shield.Hum()
  pcall(function() import("KismetSystemLibrary").ExecuteConsoleCommand(nil, "r.ShaderPipelineCache 0") end)
  print("[SAMEER] ALL PROTECTION + BAN BYPASS 4.6 ACTIVE")
end

-- ============================================================
-- [5] LAYER FUNCTIONS L01..L39
-- ============================================================

-- L01: SLUA signature bypass
local function L01_SLUA()
    local ok = false
    pcall(function()
        if slua and type(slua.getSignature) == "function" then
            slua.getSignature = function() return 0xDEADBEEF end
            ok = true
        end
        local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
        if loader then
            loader.verifyBytecode = retTrue
            loader.checkIntegrity = retTrue
            loader.disableSignatureCheck = retTrue
            ok = true
        end
        local ser = package.loaded["slua.serialize"]
        if ser then ser.check = retTrue; ser.verify = retTrue; ok = true end
        if _G.slua_verify then _G.slua_verify = retTrue; ok = true end
        if _G.check_slua_integrity then _G.check_slua_integrity = retTrue; ok = true end
        if jit and jit.attach then
            jit.attach(function() end, "bc")
            ok = true
        end
    end)
    MarkLayer("L01_SLUA", ok)
end

-- L02: MD5/pak signature bypass
local function L02_MD5()
    local ok = false
    pcall(function()
        local console = import("KismetSystemLibrary")
        if console then
            console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
            console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
            console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
            console.ExecuteConsoleCommand(nil, "sig.Check 0")
            console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
            ok = true
        end
        local CMode = import("CreativeModeBlueprintLibrary")
        if CMode then
            CMode.MD5HashByteArray = function() return "00000000000000000000000000000000" end
            CMode.MD5HashFile = function() return "00000000000000000000000000000000" end
            CMode.GetContentDiffData = function() return true, "OK" end
            CMode.VerifyFileIntegrity = retTrue
            ok = true
        end
        if _G.MD5Hash then _G.MD5Hash = function() return "00000000000000000000000000000000" end; ok = true end
        if _G.CRC32 then _G.CRC32 = function() return 0 end; ok = true end
        if _G.SHA1 then _G.SHA1 = function() return "0000000000000000" end; ok = true end
        local FHC = package.loaded["common.file_hash_checker"]
        if FHC then
            FHC.CheckFileMD5 = retTrue
            FHC.VerifyAll = retTrue
            FHC.GetHash = function() return "0000000000000000" end
            ok = true
        end
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then
            TssSdk.GetFileMD5 = function() return "0000000000000000" end
            TssSdk.VerifyFileSignature = retTrue
            ok = true
        end
        local STExtra = import("STExtraBlueprintFunctionLibrary")
        if STExtra then
            STExtra.CheckMD5 = retTrue
            STExtra.GetMD5 = function() return "0000000000000000" end
            STExtra.VerifyFile = retTrue
            ok = true
        end
    end)
    MarkLayer("L02_MD5", ok)
end

-- L03: skin/avatar exception bypass
local function L03_SKIN()
    local ok = false
    pcall(function()
        local ptlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
        if ptlog then
            ptlog.ReportEvent = nop
            ptlog.ReportDownloadResult = nop
            ptlog.ReportODPTDError = nop
            ptlog.ReportSkinError = nop
            ok = true
        end
        local AvatarUtils = package.loaded["AvatarUtils"]
        if AvatarUtils then
            AvatarUtils.CheckIsWeaponInBlackList = retFalse
            AvatarUtils.IsValidAvatar = retTrue
            AvatarUtils.CheckAvatarIntegrity = retTrue
            AvatarUtils.ReportInvalidAvatar = nop
            ok = true
        end
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local sub = SubMgr:Get("FileCheckSubsystem")
            if sub then
                sub.StartCheck = nop
                sub.ReportAbnormalFile = nop
                sub.StopCheck = nop
                ok = true
            end
        end
        local eqEx = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
        if eqEx then
            eqEx.Report = nop
            eqEx.SendException = nop
            ok = true
        end
        local AvaEx = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
        if AvaEx then
            AvaEx.CheckAvatarException = nop
            AvaEx.CheckAvatarExceptionOnce = nop
            AvaEx.ReportAvatarException = nop
            AvaEx.CheckSlotMeshVisible = retFalse
            AvaEx.CheckPawnVisible = retFalse
            AvaEx.CheckCanBugglyPostException = retFalse
            ok = true
        end
    end)
    MarkLayer("L03_SKIN", ok)
end

-- L04: log/crash reporter bypass
local function L04_LOG()
    local ok = false
    pcall(function()
        local SMTD = import("ScreenshotMTDer")
        if SMTD then
            SMTD.MTDePicture = function() return "" end
            SMTD.ReMTDePicture = function() return "" end
            SMTD.HasCaptured = retTrue
            SMTD.TakeScreenshot = nop
            ok = true
        end
        local TLog = package.loaded["TLog"] or _G.TLog
        if TLog then
            TLog.Info = nop; TLog.Warning = nop; TLog.Error = nop
            TLog.Debug = nop; TLog.Report = nop; TLog.Send = nop; TLog.Flush = nop
            ok = true
        end
        local CrashSight = package.loaded["CrashSight"] or _G.CrashSight
        if CrashSight then
            CrashSight.ReportException = nop
            CrashSight.SetCustomData = nop
            CrashSight.Log = nop
            CrashSight.SendCrash = nop
            CrashSight.ReportUserException = nop
            ok = true
        end
        local GRU = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
        if GRU then
            GRU.BugglyPostExceptionFull = retFalse
            GRU.CheckCanBugglyPostException = retFalse
            GRU.ReplayReportData = nop
            GRU.ReportGameException = nop
            GRU.PostException = nop
            ok = true
        end
        local CTR = package.loaded["client.slua.logic.report.ClientToolsReport"]
        if CTR then
            CTR.SendReport = nop
            CTR.SendException = nop
            CTR.UploadLog = nop
            ok = true
        end
        for _, sdk in ipairs({"Firebase","Adjust","AppsFlyer","FacebookAnalytics","GameAnalytics"}) do
            local s = _G[sdk]
            if s then
                s.logEvent = nop; s.trackEvent = nop
                s.setEnabled = retFalse; s.sendEvent = nop; s.report = nop
                ok = true
            end
        end
    end)
    MarkLayer("L04_LOG", ok)
end

-- L05: subsystem scanner bypass
local function L05_SCANNER()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not SubMgr then return end
        for _, name in ipairs(REAL_SECURITY_SUBSYSTEMS) do
            local sub = SubMgr:Get(name)
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Send") or k:find("Upload") or
                        k:find("Verify") or k:find("Check") or k:find("Validate") or
                        k:find("Scan") or k:find("Detect") or k:find("Heartbeat") or
                        k:find("Flow")) then
                        pcall(function() sub[k] = nop end)
                    end
                end
                if sub.ReportPingDelayTimer then
                    pcall(function() sub:RemoveGameTimer(sub.ReportPingDelayTimer) end)
                    sub.ReportPingDelayTimer = nil
                end
                sub.DelayCount = 0
                ok = true
            end
        end
    end)
    MarkLayer("L05_SCANNER", ok)
end

-- L06: replay telemetry bypass
local function L06_REPLAY()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            for _, name in ipairs({"GameReportSubsystem","ReplaySubsystem","RescueBtnReplayTraceSubsystem","SpectateAndReplaySubsystem"}) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and
                           (k:find("Report") or k:find("Trace") or k:find("Replay") or
                            k:find("Record") or k:find("Save") or k:find("Heartbeat")) then
                            pcall(function() sub[k] = nop end)
                        end
                    end
                    ok = true
                end
            end
        end
        local logRep = package.loaded["client.slua.logic.replay.logic_report_replay"]
        if logRep then
            logRep.ReportReplay = nop
            logRep.SendReportReq = nop
            logRep.UploadReplay = nop
            ok = true
        end
        if _G.ClientReplayDataReporter then
            _G.ClientReplayDataReporter.ReportIntArrayData = nop
            _G.ClientReplayDataReporter.ReportUInt8ArrayData = nop
            _G.ClientReplayDataReporter.ReportFloatArrayData = nop
            ok = true
        end
    end)
    MarkLayer("L06_REPLAY", ok)
end

-- L07: report flow callback blocker
local function L07_REPORT_FLOW()
    local ok = false
    pcall(function()
        local flows = {
            "ReportAimFlow","ReportHitFlow","ReportAttackFlow","ReportSecAttackFlow",
            "ReportFireArms","ReportVerifyInfoFlow","ReportMrpcsFlow","ReportPlayerBehavior",
            "ReportTeammatHurt","ReportMisKillByTeammate","ReportForbitPick","ReportPlayerMoveRoute",
            "ReportPlayerPosition","ReportVehicleMoveFlow","ReportSecTgameMovingFlow","ReportParachuteData",
            "ReportEquipmentFlow","ReportPlayersPing","ReportPlayerIP","ReportPlayerFramePingRecord",
            "ReportDSNetSaturation","ReportNetContinuousSaturate","ReportDSNetRate","ReportCircleFlow",
            "ReportSecMrpcsFlow","SendTssSdkAntiDataToLobby","SendDSErrorLogToLobby",
            "SendDSHawkEyePatrolLogToLobby","SendSecTLog","SendDataMiningTLog","SendActivityTLog",
            "SendClientMemUsage","SendClientFPS","OnClientCrashReport","OnNetworkLossDetected",
            "ReportMatchRoomData","SendClientStats","SendServerAvgTickDelta","SendClientDeviceInfo",
            "ReportDeviceFingerprint","SendNetworkInfo","ReportIPAddress","SendMACAddress","ReportHardwareID"
        }
        for _, f in ipairs(flows) do
            if _G[f] then _G[f] = nop; ok = true end
            if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then
                _G.GameplayCallbacks[f] = nop
                ok = true
            end
        end
        for _, f in ipairs({"CheckReportSecAttackFlowWithAttackFlow","CheckReportSecAttackFlow"}) do
            if _G[f] then _G[f] = retFalse; ok = true end
            if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then
                _G.GameplayCallbacks[f] = retFalse
                ok = true
            end
        end
        for _, f in ipairs({"IsEnableReportMrpcsInCircleFlow","IsEnableReportMrpcsInPartCircleFlow",
                            "IsEnableReportMrpcsFlow","IsEnableReportAttackFlow",
                            "IsEnableReportHitFlow","IsEnableReportCircleFlow"}) do
            if _G[f] then _G[f] = retFalse; ok = true end
        end
    end)
    MarkLayer("L07_REPORT_FLOW", ok)
end

-- L08: player security info bypass
local function L08_PLAYER_SEC()
    local ok = false
    pcall(function()
        local SecSub = safe_require("GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem")
        if SecSub then
            SecSub.ReportData = nop
            SecSub.CheckCheat = retFalse
            SecSub.ValidatePlayer = retTrue
            SecSub.CollectData = nop
            SecSub.SendToServer = nop
            ok = true
        end
        for _, c in ipairs({"PlayerSecurityInfoCollector","PlayerSecurityInfo","SecurityInfoCollector",
                            "ClientSecurityCollector","PlayerAntiCheatCollector"}) do
            if _G[c] then
                for k, v in pairs(_G[c]) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Collect") or k:find("Send") or
                        k:find("Upload") or k:find("Record")) then
                        _G[c][k] = nop
                        ok = true
                    end
                end
            end
        end
    end)
    MarkLayer("L08_PLAYER_SEC", ok)
end

-- L09: client flow bypass
local function L09_CLIENT_FLOW()
    local ok = false
    pcall(function()
        for _, name in ipairs({"ClientSecMrpcsFlow","MrpcsFlow","MrpcsData",
                                "ClientCircleFlowSubsystem","ClientKillFlowSubsystem",
                                "ClientSecPlayerKillFlow"}) do
            local sub = package.loaded[name] or _G[name]
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Send") or k:find("Flow") or
                        k:find("Record") or k:find("Process")) then
                        pcall(function() sub[k] = nop end)
                        ok = true
                    end
                end
            end
        end
    end)
    MarkLayer("L09_CLIENT_FLOW", ok)
end

-- L10: swift hawk bypass
local function L10_SWIFT_HAWK()
    local ok = false
    pcall(function()
        for _, f in ipairs({"SwiftHawk","ClientSwiftHawk","ClientSwiftHawkWithParams","SendSwiftHawkData"}) do
            if _G[f] then _G[f] = nop; ok = true end
            if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then
                _G.GameplayCallbacks[f] = nop
                ok = true
            end
        end
        local sub = safe_require("GameLua.Mod.BaseMod.Client.Security.SwiftHawkSubsystem")
        if sub then
            sub.ReportData = nop
            sub.SendReport = nop
            sub.CollectTelemetry = nop
            ok = true
        end
    end)
    MarkLayer("L10_SWIFT_HAWK", ok)
end

-- L11: corona lab bypass
local function L11_CORONA()
    local ok = false
    pcall(function()
        if _G.CoronaLab then
            _G.CoronaLab.ReportData = nop
            _G.CoronaLab.SendData = nop
            _G.CoronaLab.CollectData = nop
            _G.CoronaLab.Telemetry = nop
            ok = true
        end
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        local sub = SubMgr and SubMgr:Get("CoronaLabSubsystem")
        if sub then
            sub.ReportData = nop
            sub.SendToServer = nop
            sub.CollectTelemetry = nop
            sub.StopCollection = nop
            ok = true
        end
        _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
        local mt = getmetatable(_G.GlobalPlayerCoronaData) or {}
        mt.__newindex = function() end
        setmetatable(_G.GlobalPlayerCoronaData, mt)
        _G.BlackList = {}
        ok = true
    end)
    MarkLayer("L11_CORONA", ok)
end

-- L12: modifier exception bypass
local function L12_MODIFIER()
    local ok = false
    pcall(function()
        _G.bReportedModifierException = false
        local sub = safe_require("GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem")
        if sub then
            sub.ReportException = nop
            sub.CheckModifier = retTrue
            sub.ValidateModifier = retTrue
            sub.ReportModifierError = nop
            ok = true
        end
    end)
    MarkLayer("L12_MODIFIER", ok)
end

-- L13: simulate character location bypass
local function L13_SIMULATE_CHAR()
    local ok = false
    pcall(function()
        local sub = safe_require("GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem")
        if sub then
            sub.ReportLocation = nop
            sub.SendLocationData = nop
            sub.VerifyLocation = retTrue
            ok = true
        end
    end)
    MarkLayer("L13_SIMULATE_CHAR", ok)
end

-- L14: shoot verification bypass
local function L14_SHOOT_VERIFY()
    local ok = false
    pcall(function()
        local sub = safe_require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if sub then
            sub.OnShootVerifyFailed = nop
            sub.SendVerifyData = nop
            sub.ReportBulletHit = nop
            sub.UploadHitInfo = nop
            sub.VerifyShot = retTrue
            ok = true
        end
        if _G.BulletHitInfoUploadData then
            _G.BulletHitInfoUploadData.Report = nop
            _G.BulletHitInfoUploadData.Send = nop
            _G.BulletHitInfoUploadData.Upload = nop
            ok = true
        end
    end)
    MarkLayer("L14_SHOOT_VERIFY", ok)
end

-- L15: network packet block
local function L15_NET_PACKET()
    local ok = false
    pcall(function()
        if NetUtil and NetUtil.SendPacket and not NetUtil._IsBypassed then
            local orig = NetUtil.SendPacket
            local blocked = {
                ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportFireArms"]=1,
                ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1, ["ReportPlayerBehavior"]=1,
                ["ReportTeammatHurt"]=1, ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1,
                ["ReportSecVehicleMoveFlow"]=1, ["ReportVehicleMoveFlow"]=1, ["ReportParachuteData"]=1,
                ["ReportEquipmentFlow"]=1, ["ReportJumpFlow"]=1, ["ReportHurtFlow"]=1,
                ["on_tss_sdk_anti_data"]=1, ["ReportAimFlow"]=1, ["ReportHitFlow"]=1,
                ["ReportCircleFlow"]=1, ["report_players_ping"]=1, ["report_player_ip"]=1,
                ["report_net_saturate"]=1, ["report_speed_hack"]=1, ["report_wall_hack"]=1,
                ["report_aim_bot"]=1, ["report_esp_usage"]=1, ["report_modded_files"]=1,
                ["detect_cheat"]=1, ["ban_player"]=1, ["client_anti_cheat_report"]=1,
                ["ClientSecMrpcsFlow"]=1, ["MrpcsData"]=1,
                ["CheckReportSecAttackFlow"]=1, ["CheckReportSecAttackFlowWithAttackFlow"]=1,
                ["RPC_ClientCoronaLab"]=1, ["CoronaLabReport"]=1, ["CoronaLabData"]=1,
                ["PlayerSecurityInfo"]=1, ["ReportSecurityInfo"]=1, ["SendSecurityData"]=1,
                ["ClientCircleFlow"]=1, ["IsEnableReportMrpcsInCircleFlow"]=1,
                ["IsEnableReportMrpcsInPartCircleFlow"]=1, ["bReportedModifierException"]=1,
                ["ReportModifierException"]=1, ["RPC_Server_ReportSimulateCharacterLocation"]=1,
                ["ReportSimulateCharacterLocation"]=1, ["RPC_Client_ShootVertifyRes"]=1,
                ["BulletHitInfoUploadData"]=1, ["ShootVerifyFailed"]=1,
                ["report_unrealnet_exception"]=1, ["tss_sdk_report"]=1,
                ["SwiftHawk"]=1, ["ClientSwiftHawk"]=1, ["ClientSwiftHawkWithParams"]=1,
                ["SwiftHawkReport"]=1, ["SwiftHawkData"]=1,
                ["AntiCheatReport"]=1, ["CheatDetection"]=1, ["ViolationReport"]=1,
                ["SecurityViolation"]=1, ["IntegrityCheck"]=1, ["SignatureVerify"]=1,
                ["ReportSecTLog"]=1, ["report_client_scan_result"]=1,
                ["report_memory_exception"]=1, ["report_avatar_exception"]=1,
                ["report_character_state"]=1, ["report_vehicle_exception"]=1,
                ["report_camera_exception"]=1,
                ["ReportHeavyWeaponBoxSpawnFlow"]=1, ["ReportHeavyWeaponBoxActivationFlow"]=1,
                ["report_player_frame_ping_record"]=1,
                ["report_ds_net_saturation"]=1,
            }
            NetUtil.SendPacket = function(packetName, ...)
                if blocked[packetName] then return nil end
                return orig(packetName, ...)
            end
            NetUtil._IsBypassed = true
            ok = true
        end
        if _G.SendRPC and not _G._SendRPCBypassed then
            local origRPC = _G.SendRPC
            local blockedRPC = {
                "RPC_Server_ClientSecMrpcsFlow","RPC_Server_SwiftHawk",
                "RPC_Server_ClientSwiftHawkWithParams",
                "RPC_Server_ReportSimulateCharacterLocation",
                "RPC_Client_ShootVertifyRes","RPC_ClientCoronaLab"
            }
            _G.SendRPC = function(rpcName, ...)
                for _, b in ipairs(blockedRPC) do
                    if rpcName == b then return nil end
                end
                return origRPC(rpcName, ...)
            end
            _G._SendRPCBypassed = true
            ok = true
        end
    end)
    MarkLayer("L15_NET_PACKET", ok)
end

-- L16: Higgs Boson full bypass
local function L16_HIGGS()
    local ok = false
    pcall(function()
        local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            local methods = {
                "ControlMHActive","Tick","OnTick","MHActiveLogic","TriggerAvatarCheck",
                "StartAvatarCheck","ReportItemID","ReceiveAnyDamage","OnWeaponHitRecord",
                "ShowSecurityAlert","ServerReportAvatar","ClientReportNetAvatar",
                "SendHisarData","ValidateSecurityData","StaticShowSecurityAlertInDev",
                "RPC_Client_ShootVertifyRes","RPC_Server_ReportSimulateCharacterLocation",
                "DisableHiggsBoson","CheckMHActive","ReportViolation","ProcessSecurityEvent",
                "ValidatePlayer","CheckIntegrity"
            }
            for _, m in ipairs(methods) do
                if Higgs[m] then Higgs[m] = nop end
            end
            Higgs.GetNetAvatarItemIDs = retEmpty
            Higgs.GetCurWeaponSkinID = retZero
            Higgs.IsMHActive = retFalse
            Higgs.bMHActive = false
            Higgs.bCallPreReplication = false
            if Higgs.BlackList then
                for k in pairs(Higgs.BlackList) do Higgs.BlackList[k] = nil end
            end
            ok = true
        end
        _G.BlackList = {}
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(pc) then
            if pc.HiggsBoson then
                pc.HiggsBoson.bMHActive = false
                pc.HiggsBoson.bCallPreReplication = false
                if pc.HiggsBoson.ControlMHActive then
                    pcall(function() pc.HiggsBoson:ControlMHActive(0) end)
                end
            end
            if pc.HiggsBosonComponent then
                pc.HiggsBosonComponent.bMHActive = false
                pc.HiggsBosonComponent.bCallPreReplication = false
                pcall(function() pc.HiggsBosonComponent:ControlMHActive(0) end)
            end
            ok = true
        end
        local hia = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientGlueHiaSystem")
        if hia then
            hia.CheckHitIntegrity = nop
            hia.InitSession = nop
            hia.OnBattleEnd = nop
            ok = true
        end
    end)
    MarkLayer("L16_HIGGS", ok)
end

-- L17: anti-cheat callback hooks
local function L17_ANTICHEAT_HOOKS()
    local ok = false
    pcall(function()
        local HBC = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if HBC and HBC.StaticShowSecurityAlertInDev then
            HBC.StaticShowSecurityAlertInDev = nop
            ok = true
        end
        if _G.AvatarCheckCallback then
            _G.AvatarCheckCallback.StartAvatarCheck = nop
            _G.AvatarCheckCallback.OnReportItemID = nop
            _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(PlayerController)
                if slua.isValid(PlayerController) and PlayerController.HiggsBosonComponent then
                    PlayerController.HiggsBosonComponent:ControlMHActive(0)
                    PlayerController.HiggsBosonComponent.bMHActive = false
                end
            end
            ok = true
        end
    end)
    MarkLayer("L17_ANTICHEAT_HOOKS", ok)
end

-- L18: anti-report player subsystem bypass
local function L18_ANTI_REPORT()
    local ok = false
    pcall(function()
        for _, path in ipairs({
            "GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem",
            "Client.Security.ClientReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.Common.Security.DSReportPlayerSubsystem"
        }) do
            local sub = package.loaded[path]
            if not sub then
                local s, r = pcall(require, path)
                if s and r then sub = r end
            end
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Record") or k:find("Send") or
                        k:find("Upload") or k:find("Notify") or k:find("Submit")) then
                        pcall(function() sub[k] = nop end)
                        ok = true
                    end
                end
            end
        end
    end)
    MarkLayer("L18_ANTI_REPORT", ok)
end

-- L19: gameplay callbacks
local function L19_GAMEPLAY_CALLBACKS()
    local ok = false
    pcall(function()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        local GC = _G.GameplayCallbacks

        if not GC._BypassV5Applied then
            local reports = {
                "ReportAttackFlow","ReportSecAttackFlow","ReportFireArms","ReportVerifyInfoFlow",
                "ReportMrpcsFlow","ReportPlayerBehavior","ReportTeammatHurt","ReportMisKillByTeammate",
                "ReportForbitPick","ReportPlayerMoveRoute","ReportPlayerPosition","ReportVehicleMoveFlow",
                "ReportSecTgameMovingFlow","ReportParachuteData","SendTssSdkAntiDataToLobby",
                "ReportEquipmentFlow","ReportAimFlow","ReportPlayersPing","ReportPlayerIP",
                "ReportPlayerFramePingRecord","OnDSConnectionSaturated","ReportDSNetSaturation",
                "ReportNetContinuousSaturate","ReportDSNetRate","SendClientStats",
                "SendServerAvgTickDelta","ReportCircleFlow","ClientSecMrpcsFlow","SwiftHawk",
                "ClientSwiftHawk","ClientSwiftHawkWithParams","ReportHitFlow","ReportJumpFlow",
                "ReportHurtFlow","ReportHeavyWeaponBoxSpawnFlow","ReportHeavyWeaponBoxActivationFlow"
            }
            for _, f in ipairs(reports) do GC[f] = nop end

            GC.CheckReportSecAttackFlowWithAttackFlow = retFalse
            GC.CheckReportSecAttackFlow = retFalse

            local origState = GC.OnDSPlayerStateChanged
            GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
                local s = State and string.lower(tostring(State)) or ""
                local block = {
                    ["cheatdetected"]=1, ["connectionlost"]=1, ["connectiontimeout"]=1,
                    ["connectionexception"]=1, ["netdrivererror"]=1, ["banned"]=1,
                    ["kicked"]=1, ["suspended"]=1, ["violationdetected"]=1,
                    ["integrityfailure"]=1, ["securityviolation"]=1
                }
                if block[s] then return end
                if origState then pcall(origState, UID, State, bPure, bSafe, Param) end
            end

            GC.OnPlayerNetConnectionClosed = nop
            GC.OnPlayerActorChannelError = nop
            GC.OnPlayerRPCValidateFailed = nop
            GC.OnPlayerSpectateException = nop
            GC.OnShutdownAfterError = nop

            GC._BypassV5Applied = true
            ok = true
        else
            ok = true
        end
    end)
    MarkLayer("L19_GAMEPLAY_CALLBACKS", ok)
end

-- L20: kill subsystems
local function L20_KILL_SUBSYSTEMS()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not SubMgr then return end
        for _, name in ipairs(REAL_SECURITY_SUBSYSTEMS) do
            local sub = SubMgr:Get(name)
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and
                       (k:find("Report") or k:find("Send") or k:find("Upload") or
                        k:find("Verify") or k:find("Check") or k:find("Validate") or
                        k:find("Scan") or k:find("Detect") or k:find("Collect") or
                        k:find("Flow") or k:find("Heartbeat") or k:find("Tick")) then
                        pcall(function() sub[k] = nop end)
                    end
                end
                if sub.timer then pcall(function() sub:RemoveGameTimer(sub.timer) end) end
                if sub.heartbeatTimer then pcall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
                if sub.reportTimer then pcall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
                ok = true
            end
        end
    end)
    MarkLayer("L20_KILL_SUBSYSTEMS", ok)
end

-- L21: targeted module stubbing
local function L21_MODULE_STUBS()
    local ok = false
    pcall(function()
        local stubPaths = {
            "GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent",
            "GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem",
            "GameLua.GameCore.Module.Subsystem.CoronaLabSubsystem",
            "GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem",
            "GameLua.Dev.Subsystem.ShootVerifySubSystemClient",
            "GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem",
        }
        for _, path in ipairs(stubPaths) do
            local existing = package.loaded[path]
            if existing and type(existing) == "table" then
                for k, v in pairs(existing) do
                    if type(v) == "function" then
                        pcall(function() existing[k] = nop end)
                    end
                end
                ok = true
            end
        end
    end)
    MarkLayer("L21_MODULE_STUBS", ok)
end

-- L22: operational stats bypass
local function L22_OPERATIONAL_STATS()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        local OSS = (SubMgr and SubMgr:Get("OperationalStatsSubsystem")) or _G.OperationalStatsSubsystem
        if OSS then
            OSS.ReportOperationalStats = nop
            OSS.AddOperationalStats = nop
            OSS.HandleTouchBegin = nop
            OSS.HandleTouchEnd = nop
            OSS.OnInit = nop
            OSS.HandleEnterFighting = nop
            OSS.OnBattleResult = nop
            if OSS.TimerHandle then
                pcall(function() OSS:RemoveGameTimer(OSS.TimerHandle) end)
                OSS.TimerHandle = nil
            end
            OSS.StatsData = {}
            ok = true
        end
    end)
    MarkLayer("L22_OPERATIONAL_STATS", ok)
end

-- L23: base bypass (dev/shipping flags)
local function L23_BASE()
    local ok = false
    pcall(function()
        local stExtra = import("STExtraBlueprintFunctionLibrary")
        if stExtra and stExtra.IsDevelopment then stExtra.IsDevelopment = nop; ok = true end
        if Client then Client.IsDevelopment = nop; Client.IsShipping = retFalse; ok = true end
        if Server then Server.IsShipping = retFalse; ok = true end

        local ToolReport = safe_require("client.slua.logic.report.ToolReportUtil")
        if ToolReport then
            ToolReport.IsReleaseVersion = retFalse
            ToolReport.IsWhite = retFalse
            ToolReport.GetReportSwitch = retFalse
            ok = true
        end

        local callbacks = _G.GameplayCallbacks
        if callbacks then
            local extra = {
                "ReportHitFlow","SendClientStats","SendServerAvgTickDelta"
            }
            for _, fn in ipairs(extra) do
                if callbacks[fn] then callbacks[fn] = nop end
            end
            ok = true
        end

        if _G.TApmHelper then _G.TApmHelper.postEvent = nop; ok = true end

        local PC = _G.PacketCallbacks
        if PC then
            PC.player_report_cheat = nop
            PC.upload_loots_rsp = nop
            PC.watch_player_exit = nop
            PC.player_login_report = nop
            PC.player_logout_report = nop
            PC.server_time_report = nop
            ok = true
        end

        local sdm = _G.ServerDataMgr
        if sdm and sdm.DeletablePlayerResultKey then
            sdm.DeletablePlayerResultKey["SuspiciousHitCount"] = true
            sdm.DeletablePlayerResultKey["EspTotalSimTraceCnt"] = true
            sdm.DeletablePlayerResultKey["EspTotalImeFocusCnt"] = true
            sdm.DeletablePlayerResultKey["ClientGravityAnomalyCount"] = true
            ok = true
        end

        local pcNotify = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature")
        if pcNotify then
            pcNotify.ClientRPC_SyncBanID = nop
            pcNotify.ClientRPC_StrongTips = nop
            pcNotify.ClientRPC_NormalTips = nop
            pcNotify.Notify = nop
            pcNotify.ClientRPC_NotifyBan = nop
            pcNotify.ClientRPC_NotifyPunish = nop
            pcNotify.ClientRPC_NotifyIllegalProgram = nop
            ok = true
        end

        local secUtils = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
        if secUtils and secUtils.EStrategyTypeInReplay then
            secUtils.EStrategyTypeInReplay.EspTotalSimTraceCnt = 0
            secUtils.EStrategyTypeInReplay.EspTotalImeFocusCnt = 0
            secUtils.EStrategyTypeInReplay.ClientGravityAnomalyCount = 0
            secUtils.EStrategyTypeInReplay.FlyingErrorCnt = 0
            ok = true
        end
    end)
    MarkLayer("L23_BASE", ok)
end

-- L24: ban system bypass (all ban types)
local function L24_BAN_SYSTEM()
    local ok = false
    pcall(function()
        local BanLogic = safe_require("client.slua.logic.ban.ClientBanLogic")
        if BanLogic then
            BanLogic.OnSyncBanInfo = nop
            BanLogic.OnVoiceBanNotify = nop
            BanLogic.OnRealTimeVoiceBanNotify = nop
            BanLogic.OnVoiceBanSuccess = nop
            BanLogic.OnSyncMicSuspicious = nop
            BanLogic.OnSyncMicPreFilter = nop
            BanLogic.OnNotifyWarningTips = nop
            BanLogic.ReqBanInfo = nop
            BanLogic.OnReceiveBanInfo = nop
            BanLogic.ShowBanUI = nop
            BanLogic.OnKickPlayer = nop
            ok = true
        end

        local BanUtil = safe_require("client.common.ban_util") or _G.ban_util
        if BanUtil then
            BanUtil.CheckBanStatus = retFalse
            BanUtil.GetBanTime = retZero
            BanUtil.IsBanForever = retFalse
            BanUtil.GetBanEndTime = retZero
            BanUtil.IsDeviceBanned = retFalse
            BanUtil.IsHWIDBanned = retFalse
            BanUtil.IsIPBanned = retFalse
            ok = true
        end

        local TTBan = safe_require("client.logic.login.logic_tt_ban") or _G.logic_tt_ban
        if TTBan then
            TTBan.CheckIfCanCreateRole = nop
            TTBan.GetCarrierInfo = function() return "[{\"mcc\":\"000\"}]" end
            TTBan.OnBanNotify = nop
            ok = true
        end

        local GodzillaBan = safe_require("client.network.Protocol.GodzillaBanHandler")
        if GodzillaBan then
            GodzillaBan.send_godzilla_ban_req = nop
            GodzillaBan.send_godzilla_unban_req = nop
            GodzillaBan.on_godzilla_ban_notify = nop
            ok = true
        end

        local AntiAddiction = safe_require("client.network.Protocol.AntiaddctionHandler")
        if AntiAddiction then
            AntiAddiction.send_anti_addiction_req = nop
            AntiAddiction.send_anti_addiction_notify = nop
            AntiAddiction.on_anti_addiction_notify = nop
            ok = true
        end

        local AccessRestrict = safe_require("client.network.Protocol.AccessRestrictionHandler")
        if AccessRestrict then
            AccessRestrict.send_access_restriction_req = nop
            AccessRestrict.send_access_restriction_notify = nop
            AccessRestrict.on_player_cheat_state_notify = nop
            AccessRestrict.on_access_restriction_notify = nop
            ok = true
        end

        local DeleteAccount = safe_require("client.slua.logic.gdpr.logic_deleteaccount")
        if DeleteAccount then
            DeleteAccount.ForceDeleteAccount = retFalse
            DeleteAccount.OnReceiveDeleteNotify = nop
            ok = true
        end

        local ComplianceUtil = safe_require("client.slua.logic.gdpr.compliance_util")
        if ComplianceUtil then ComplianceUtil.CheckCompliance = nop; ok = true end

        local pcNotify = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature")
        if pcNotify then
            pcNotify.ClientRPC_SyncBanID = nop
            pcNotify.ClientRPC_StrongTips = nop
            pcNotify.ClientRPC_NormalTips = nop
            pcNotify.Notify = nop
            pcNotify.ClientRPC_NotifyBan = nop
            pcNotify.ClientRPC_NotifyPunish = nop
            pcNotify.ClientRPC_NotifyIllegalProgram = nop
            pcNotify.ClientRPC_ShowBanUI = nop
            ok = true
        end
    end)
    MarkLayer("L24_BAN_SYSTEM", ok)
end

-- L25: full report systems bypass
local function L25_REPORT_SYSTEMS()
    local ok = false
    pcall(function()
        local clientReport = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem")
        if clientReport then
            for _, fn in ipairs({
                "OnInit","_OnPlayerKilledOtherPlayer","_RecordFatalDamager","SendPacket",
                "ReportSuspiciousPlayer","SubmitReport","_OnBattleResult",
                "_RecordTeammatePlayerInfo","_OnDeathReplayDataWhenFatalDamaged",
                "_RecordMurdererFromDeathReplayData"
            }) do
                if clientReport[fn] then clientReport[fn] = nop end
            end
            ok = true
        end

        local dsReport = safe_require("GameLua.Mod.BaseMod.Common.Security.DSReportPlayerSubsystem")
            or safe_require("GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem")
        if dsReport then
            for _, fn in ipairs({
                "_OnNearDeathOrRescued","_OnPlayerSettlementStart","_OnTeammateDamage",
                "_OnCharacterDied","_AddEnemyMapToBattleResult","_AddTeammateMapToBattleResult",
                "_SubmitAbnormalData"
            }) do
                if dsReport[fn] then dsReport[fn] = nop end
            end
            ok = true
        end

        local reportUtils = safe_require("GameLua.Mod.BaseMod.Common.Security.ReportPlayerUtils")
        if reportUtils then
            reportUtils.GetBotType = retZero
            reportUtils.IsCharacterDeliverAI = retFalse
            ok = true
        end

        local AvatarSub = safe_require("GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionSubsystem")
        if AvatarSub then
            AvatarSub.OnClickReportCheckAvatar = nop
            AvatarSub.RegisterTickCheckCharacterAvatar = nop
            ok = true
        end

        if _G.AvatarExceptionPlayerInst then
            _G.AvatarExceptionPlayerInst.ReportAvatarException = nop
            _G.AvatarExceptionPlayerInst.CheckAvatarException = nop
            _G.AvatarExceptionPlayerInst.CheckCanBugglyPostException = nop
            ok = true
        end

        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local hawk = SubMgr:Get("DSHawkEyePatrolSubsystem")
            if hawk then
                hawk.MarkSuspiciousPlayer = nop
                hawk._OnHawkReport = nop
                hawk._OnHawkImprison = nop
                hawk.CheckPunishPlayer = nop
                ok = true
            end
        end

        local ClientHawk = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem")
        if ClientHawk then
            for _, fn in ipairs({
                "_OnHawkSync","_OnHawkReportSuccess","_StartExitGameTimer",
                "_OnRecvInspectorBroadcastCount","SendReportTLog","ReportCheat"
            }) do
                if ClientHawk[fn] then ClientHawk[fn] = nop end
            end
            ClientHawk.CanInspectorBroadcast = retFalse
            ok = true
        end

        local InspectClient = safe_require("GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem")
        if InspectClient then
            for _, fn in ipairs({
                "AskForInspector","ReportEnemy","KickOutOneTeam","OnReceiveInspectCmd",
                "ClientReportData","SendReportToInspector","SendKickOutOneTeam",
                "ClientNotifyInspectorImplementation","RecvNotifyInspector"
            }) do
                if InspectClient[fn] then InspectClient[fn] = nop end
            end
            ok = true
        end

        local InspectDS = safe_require("GameLua.Mod.BaseMod.DS.Security.InspectionSystemReportDSLogicSubsystem")
        if InspectDS then
            for _, fn in ipairs({
                "ServerKickOutOneTeamByPlayerImplementation","AddReportedCount",
                "AddInspectionRecord","BanPlayerByInspection","BroadCastToAllInspector",
                "ServerReportToInspectorImplementation","InitPlayerInspectionInfo"
            }) do
                if InspectDS[fn] then InspectDS[fn] = nop end
            end
            ok = true
        end
    end)
    MarkLayer("L25_REPORT_SYSTEMS", ok)
end

-- L26: TLOG bypass
local function L26_TLOG()
    local ok = false
    pcall(function()
        local tlogMods = {
            "client.network.Protocol.ClientTlogHandler",
            "client.network.Protocol.BattleReportHandler",
            "client.network.Protocol.ClientErrorReportHandler",
            "client.network.Protocol.LobbyPingReportHandler",
            "client.slua.config.tlog.tlog_report_utils",
            "client.slua.data.BasicData.BasicDataTLogReport",
            "client.slua.data.BasicData.BasicDataClientReport",
            "client.slua.data.BasicData.BasicDataReport",
            "GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem",
            "GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem",
            "GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem",
        }
        for _, path in ipairs(tlogMods) do
            local mod = package.loaded[path]
            if mod then
                for k, v in pairs(mod) do
                    if type(v) == "function" and
                       (k:find("Log") or k:find("Report") or k:find("Send") or k:find("Tlog")) then
                        pcall(function() mod[k] = nop end)
                    end
                end
                ok = true
            end
        end

        local AmphibiousBoat = safe_require("GameLua.GameCore.Module.Vehicle.VehicleFeatures.TLog.AmphibiousBoatTLogFeature")
        if AmphibiousBoat then
            AmphibiousBoat.RecordMovement = nop
            AmphibiousBoat.StartRecordMovement = nop
            ok = true
        end

        local ICTLog = safe_require("GameLua.Mod.BaseMod.DS.Security.ICTLogSubsystem")
        if ICTLog then ICTLog.SendICExceptionTLog = nop; ok = true end

        local DSFight = safe_require("GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem")
        if DSFight then
            DSFight.GetSimpleFightData = retEmpty
            DSFight.ReportFightData = nop
            DSFight.ReportPlayerWeapon = nop
            ok = true
        end

        local DSSec = safe_require("GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem")
        if DSSec then
            DSSec._OnReportServerJumpFlow = nop
            DSSec._OnReportTeleportFlow = nop
            DSSec._OnReportSpeedHackFlow = nop
            ok = true
        end

        local DSCommon = safe_require("GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem")
        if DSCommon then DSCommon.HandleKillTlog = nop; ok = true end

        local PufferTlog = safe_require("client.slua.logic.download.report.puffer_tlog")
        if PufferTlog then PufferTlog.report_download_tlog = nop; ok = true end
    end)
    MarkLayer("L26_TLOG", ok)
end

-- L27: network handler bypass
local function L27_NET_HANDLERS()
    local ok = false
    pcall(function()
        local ClientError = safe_require("client.network.Protocol.ClientErrorReportHandler")
        if ClientError then
            ClientError.send_client_error_report = nop
            ClientError.send_client_crash_report = nop
            ClientError.send_client_tools_batch_report_req = nop
            ok = true
        end

        local BattleReport = safe_require("client.network.Protocol.BattleReportHandler")
        if BattleReport then
            for _, fn in ipairs({
                "send_battle_report","send_battle_result","send_vod_game_report_req",
                "send_batch_get_vod_info_req","send_get_game_report_req",
                "send_batch_get_game_report_req","send_get_game_report_by_uid_req"
            }) do
                if BattleReport[fn] then BattleReport[fn] = nop end
            end
            ok = true
        end

        local BugHandler = safe_require("client.network.Protocol.BugHandler")
        if BugHandler then
            BugHandler.send_report_bug_info = nop
            BugHandler.send_report_bug_feedback = nop
            ok = true
        end

        local PingReport = safe_require("client.network.Protocol.LobbyPingReportHandler")
        if PingReport then
            PingReport.send_lobby_ping_report = nop
            PingReport.send_ingame_ping_report = nop
            ok = true
        end

        local WeekReport = safe_require("client.network.Protocol.WeekRportHandler")
        if WeekReport then
            WeekReport.send_week_report = nop
            WeekReport.send_week_detail = nop
            ok = true
        end

        local LogicComplaint = safe_require("client.logic.battle.logic_complaint")
        if LogicComplaint then
            LogicComplaint.SendComplaintReq = nop
            LogicComplaint.Submit = nop
            LogicComplaint.ReportPlayer = nop
            LogicComplaint.ShowComplaint = nop
            LogicComplaint.ShowHandle = nop
            ok = true
        end

        local OBResult = safe_require("GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.EscapeBattleResultShowOBResultLogic")
        if OBResult then
            OBResult.OnBattleResult = nop
            OBResult.OnResultProcessStart = nop
            ok = true
        end

        local NormalOBResult = safe_require("GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowOBResultLogic")
        if NormalOBResult then
            NormalOBResult.OnBattleResult = nop
            NormalOBResult.OnResultProcessStart = nop
            ok = true
        end

        local ShowResult = safe_require("GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowResultLogic")
        if ShowResult then
            for _, fn in ipairs({
                "OnBattleResult","OnResultProcessStart","OnResultProcessContinue",
                "ReceiveData","SendEndFlow","OnReport","ShowResult",
                "ShowResultInternal","StopResultProcess"
            }) do
                if ShowResult[fn] then ShowResult[fn] = nop end
            end
            ok = true
        end
    end)
    MarkLayer("L27_NET_HANDLERS", ok)
end

-- L28: misc bypass
local function L28_MISC()
    local ok = false
    pcall(function()
        local EmuHandler = safe_require("client.network.Protocol.EmulatorHandler")
        if EmuHandler then EmuHandler.send_emulator_info = nop; ok = true end

        local EmuScanner = safe_require("client.logic.login.emulator_scanner")
        if EmuScanner then
            EmuScanner.StartScan = nop
            EmuScanner.GetScanResult = retFalse
            EmuScanner.ReportScanResult = nop
            ok = true
        end

        local LoginVerify = safe_require("client.network.Protocol.LoginVerifyHandler")
        if LoginVerify then
            LoginVerify.send_login_verify_req = nop
            LoginVerify.send_device_verify_req = nop
            ok = true
        end

        local DSMonitor = safe_require("client.logic.data.logic_ds_monitor")
        if DSMonitor then
            DSMonitor.OnRecordMsg = nop
            DSMonitor.OnReportMsg = nop
            ok = true
        end

        local ClientDataStat = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem")
        if ClientDataStat then
            ClientDataStat.StartToCheck = nop
            ClientDataStat.OnReceiveRTT = nop
            ClientDataStat.OnReceiveJitter = nop
            ClientDataStat.ReportAbnormal = nop
            ClientDataStat.ResetData = nop
            ok = true
        end

        local shootVerify = safe_require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if shootVerify then
            shootVerify.OnShootVerifyFailed = nop
            shootVerify.SendVerifyData = nop
            ok = true
        end

        local HighlightDS = safe_require("GameLua.Mod.BaseMod.DS.Security.HighlightMomentSubsystem_DSChecker")
        if HighlightDS then HighlightDS.CheckFuncUpgradedWeaponKill = nop; ok = true end

        local ProfileReport = safe_require("client.logic.data.profile_report_cfg")
        if ProfileReport then ProfileReport.SendReport = nop; ok = true end

        local VoiceReport = safe_require("client.slua.logic.chat_voice.logic_chat_voice_report")
        if VoiceReport then
            VoiceReport.ReportVoiceData = nop
            VoiceReport.ReportVoiceText = nop
            ok = true
        end

        local VoiceDoctor = safe_require("client.slua.logic.chat_voice.logic_chat_voice_doctor")
        if VoiceDoctor then
            VoiceDoctor.UploadVoiceLog = nop
            VoiceDoctor.UploadVoiceException = nop
            ok = true
        end

        local HomeAudit = safe_require("client.slua.logic.home.Audit.logic_home_audit_state")
        if HomeAudit then
            HomeAudit.SendAuditState = nop
            HomeAudit.ReportAuditResult = nop
            ok = true
        end

        local HomeReport = safe_require("client.slua.logic.home.logic_home_report")
        if HomeReport then
            HomeReport.ReportHomeData = nop
            HomeReport.ReportHomeVisitor = nop
            ok = true
        end

        local GemReport = safe_require("client.logic.store.gem_report_utils")
        if GemReport then
            GemReport.ReportGemData = nop
            GemReport.ReportGemPurchase = nop
            ok = true
        end

        local SafeStation = safe_require("client.slua.logic.CustomerService.LogicSafeStation")
        if SafeStation then
            SafeStation.UploadVideoEvidence = nop
            SafeStation.ReportPlayerBehavior = nop
            ok = true
        end

        local CustomerService = safe_require("client.slua.logic.CustomerService.LogicCustomerService")
        if CustomerService then
            CustomerService.SendComplaint = nop
            CustomerService.SendFeedback = nop
            ok = true
        end
    end)
    MarkLayer("L28_MISC", ok)
end

-- L29: extra subsystems bypass
local function L29_EXTRA_SUBSYSTEMS()
    local ok = false
    pcall(function()
        local znq6Revive = safe_require("GameLua.Mod.TDEvent.ZNQ6th.DS.ZNQ6thDSReviveSubsystem")
        if znq6Revive then znq6Revive.HaveNewItemForRevive = nop; ok = true end

        local znq7Revive = safe_require("GameLua.Mod.TDEvent.ZNQ7th.DS.ZNQ7DSReviveSubsystem")
        if znq7Revive then znq7Revive.HaveChanceRevival = nop; ok = true end

        local DataLayer = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.DataLayerSubsystem")
        if DataLayer then
            local orig = DataLayer.OnSpectatorReplayChanged
            if orig and not DataLayer._WrappedV5 then
                DataLayer.OnSpectatorReplayChanged = function(dlSelf)
                    _G.IsBeingWatched = true
                    orig(dlSelf)
                end
                DataLayer._WrappedV5 = true
            end
            ok = true
        end

        local DSActive = safe_require("GameLua.Mod.PlanBT.Gameplay.Subsystem.DSActiveSubsystem")
        if DSActive then
            DSActive.DelayKickOutPlayer = nop
            DSActive.ActiveKickNotify = nop
            ok = true
        end

        local CreativeDev = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeDevDebugSubsystem")
        if CreativeDev then CreativeDev.IsDebugPanelEnalbedCli = nop; ok = true end

        local CreativeDeath = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeModeDeathRecordSubsystem")
        if CreativeDeath then CreativeDeath.OnPlayerKilled = nop; ok = true end

        local SpectateReplay = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem")
        if SpectateReplay then
            SpectateReplay.RequestGotoSpectatingImp = nop
            SpectateReplay.RequestGotoSpectating = nop
            ok = true
        end

        local AIReplay = safe_require("GameLua.ExtraModule.MLAI.Client.AIReplaySubsystem")
        if AIReplay then
            AIReplay.ReportAllPlayerInfo = nop
            AIReplay.ReportFrameData = nop
            AIReplay.ReportPlayerInput = nop
            if AIReplay.uCompletePlayBack then
                AIReplay.uCompletePlayBack.AddRecordMLAIInfo = nop
                AIReplay.uCompletePlayBack.StopRecording = nop
            end
            ok = true
        end

        local AITracking = safe_require("GameLua.Mod.BaseMod.GamePlay.AI.AITrackingLogSubsystem")
        if AITracking then
            AITracking.RealLogoutTimer = nop
            AITracking.LogQueue = {}
            AITracking.AddToLogQue = nop
            AITracking.DoPrint = nop
            AITracking.OnAIPawnDied = nop
            AITracking.OnAIPawnReceiveDamage = nop
            AITracking.OnAIPawnEnemyChange = nop
            ok = true
        end

        local TDMAFK = safe_require("GameLua.Mod.TDM.Gameplay.Subsystem.TDMAFKReportorSubsystem")
        if TDMAFK then
            TDMAFK.SendAFKTips = nop
            TDMAFK.OnHandleLostConnection = nop
            ok = true
        end

        local DataMgr = safe_require("client.slua.logic.data.data_mgr")
        if DataMgr then DataMgr.GetWeaponSkinSoundVolumeInfoByGroup = retZero; ok = true end

        local CreditLogic = safe_require("GameLua.Mod.BaseMod.Client.ClientInGameCreditLogic")
        if CreditLogic then
            CreditLogic._SendUserReaction2ExitTeamBeforeBoardingReturnLobbyNotice = nop
            CreditLogic.ShowReturnLobbyIfFirstExitTeamBeforeBoarding = retFalse
            CreditLogic.OnReceiveCreditScoreChange = nop
            CreditLogic._IsFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = retFalse
            CreditLogic.SetFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = nop
            ok = true
        end
    end)
    MarkLayer("L29_EXTRA_SUBSYSTEMS", ok)
end

-- L30: network blacklist (HTTP layer)
local function L30_NET_BLACKLIST()
    local ok = false
    pcall(function()
        if _G.HttpRequest and not _G._HttpBypassed then
            local orig = _G.HttpRequest
            _G.HttpRequest = function(url, ...)
                if isBlacklisted(url) then return nil end
                return orig(url, ...)
            end
            _G._HttpBypassed = true
            ok = true
        end

        if _G.FHttpModule and _G.FHttpModule.CreateRequest and not _G._FHttpBypassed then
            local orig = _G.FHttpModule.CreateRequest
            _G.FHttpModule.CreateRequest = function(...)
                local url = select(1, ...)
                if isBlacklisted(url) then return nil end
                return orig(...)
            end
            _G._FHttpBypassed = true
            ok = true
        end

        local netMods = {
            "client.slua.logic.network.logic_network",
            "client.slua.logic.download.report.puffer_tlog",
            "client.slua.data.BasicData.BasicDataClientReport",
            "GameLua.GameCore.Module.Network.NetworkManager",
            "client.network.Protocol.ClientTlogHandler",
            "client.network.Protocol.BattleReportHandler",
            "client.network.Protocol.ClientErrorReportHandler",
        }
        for _, mp in ipairs(netMods) do
            local mod = package.loaded[mp]
            if mod then
                for k, v in pairs(mod) do
                    if type(v) == "function" and
                       (k:find("Http") or k:find("Request") or k:find("Send") or
                        k:find("Upload") or k:find("Post") or k:find("Get") or k:find("Report")) then
                        local origf = v
                        mod[k] = function(...)
                            local args = {...}
                            for _, arg in ipairs(args) do
                                if type(arg) == "string" and isBlacklisted(arg) then return nil end
                            end
                            return pcall(origf, ...)
                        end
                    end
                end
                ok = true
            end
        end
    end)
    MarkLayer("L30_NET_BLACKLIST", ok)
end

-- L31: file IO + crash write block
local function L31_FILEIO()
    local ok = false
    pcall(function()
        if not _G._IoOpenHooked then
            local orig_io_open = io.open
            io.open = function(path, mode)
                if type(path) == "string" then
                    local lp = path:lower()
                    for _, kw in ipairs(FILE_KEYWORDS) do
                        if lp:find(kw) then
                            if mode and (mode == "w" or mode == "a" or mode == "w+" or mode == "a+") then
                                return nil, "Blocked"
                            end
                        end
                    end
                    if lp:find("tdm") or lp:find("gcloud") or lp:find("beacon") then
                        if mode and (mode == "w" or mode == "a" or mode == "w+") then
                            return nil
                        end
                    end
                end
                return orig_io_open(path, mode)
            end
            _G._IoOpenHooked = true
            ok = true
        end

        if _G.UnrealEngine and _G.UnrealEngine.CrashContext then
            _G.UnrealEngine.CrashContext = nil
            _G.UnrealEngine.CrashContext = {
                SetCrashContext = nop,
                ReportCrash = nop,
                AddCrashData = nop
            }
            ok = true
        end
    end)
    MarkLayer("L31_FILEIO", ok)
end

-- L32: TSS SDK total silence
local function L32_TSS_SDK()
    local ok = false
    pcall(function()
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then
            TssSdk.SendReportInfo = nop
            TssSdk.ScanMemory = function() return true, {code=0, msg="clean"} end
            TssSdk.ScanSo = function() return true, {code=0, msg="clean"} end
            TssSdk.ScanFile = function() return true, {code=0} end
            TssSdk.GetRiskFlag = function() return 0 end
            TssSdk.VerifyFileHash = function() return true end
            TssSdk.IsEmulator = retFalse
            TssSdk.GetTssSdkReportInfo = retEmptyString
            TssSdk.CheckEnvironment = retTrue
            TssSdk.VerifyProcess = retTrue
            TssSdk.CheckKernel = function() return true, {status="verified", tampered=false} end
            TssSdk.VerifyBoot = function() return true, {locked=true, verified=true} end

            local origData = TssSdk.OnRecvData
            if origData and not TssSdk._DataFiltered then
                TssSdk.OnRecvData = function(data)
                    if type(data) == "string" then
                        local low = data:lower()
                        if low:find("report", 1, true) or low:find("exception", 1, true) or
                           low:find("cheat", 1, true) or low:find("violation", 1, true) or
                           low:find("hack", 1, true) or low:find("verify", 1, true) then
                            return
                        end
                    end
                    origData(data)
                end
                TssSdk._DataFiltered = true
            end
            ok = true
        end
    end)
    MarkLayer("L32_TSS_SDK", ok)
end

-- L33: behavior/afk/speed/wall heuristic bypass
local function L33_HEURISTICS()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not SubMgr then return end

        local Behavior = SubMgr:Get("BehaviorScoreSubsystem")
            or safe_require("GameLua.Mod.Escape.Gameplay.Subsystem.BehaviorScoreSubsystem")
        if Behavior then
            Behavior.OnHandleBehaviorScore = nop
            Behavior.AIPerceptionScore = nop
            Behavior.ReportBehavior = nop
            Behavior.CalcFinalScore = retZero
            Behavior.GetRiskLevel = retZero
            Behavior.IsSuspicious = retFalse
            ok = true
        end

        local AFK = SubMgr:Get("AFKReportorSubsystem")
            or safe_require("GameLua.Mod.BaseMod.DS.Security.AFKReportorSubsystem")
        if AFK then
            AFK.HandleEnterFighting = nop
            AFK.InitializePlayerInputInfo = nop
            AFK.AddOneAFKInfo = nop
            AFK.SetPlayerAFKState = nop
            AFK.ResetPlayerInputInfo = nop
            AFK.PlayerHaveAction = nop
            ok = true
        end

        if _G.GameplayCallbacks then
            for _, k in ipairs({
                "ReportServerJumpFlow","ReportTeleportFlow","ReportSpeedHackFlow",
                "ReportClientMemUsage","ReportMemoryInfo"
            }) do
                _G.GameplayCallbacks[k] = nop
            end
            ok = true
        end
    end)
    MarkLayer("L33_HEURISTICS", ok)
end

-- L34: HWID / device fingerprint spoof
local function L34_HWID_SPOOF()
    local ok = false
    pcall(function()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local deviceInfo = SubMgr:Get("ClientDeviceInfoSubsystem")
            if deviceInfo then
                deviceInfo.GetDeviceID = function() return FakeData.deviceID() end
                deviceInfo.GetIPAddress = function() return FakeData.ipAddress() end
                deviceInfo.GetMACAddress = function() return FakeData.macAddress() end
                deviceInfo.GetBuildFingerprint = function() return FakeData.buildFingerprint() end
                ok = true
            end
        end
        if _G.GetDeviceID then _G.GetDeviceID = function() return FakeData.deviceID() end; ok = true end
        if _G.GetDeviceUniqueIdentifier then
            _G.GetDeviceUniqueIdentifier = function() return FakeData.deviceID() end
            ok = true
        end
    end)
    MarkLayer("L34_HWID_SPOOF", ok)
end

-- Forward declaration for L39 (referenced by L35)
local L39_SKIN_ANTI_DETECTION

-- L35: persistent hunt timer (re-arms itself)
local function L35_HUNT_TICK()
    pcall(function()
        L19_GAMEPLAY_CALLBACKS()
        L20_KILL_SUBSYSTEMS()
        L39_SKIN_ANTI_DETECTION()
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            for _, name in ipairs({"ClientHawkEyePatrolSubsystem","DSHawkEyePatrolSubsystem",
                                    "ClientReportPlayerSubsystem","DSReportPlayerSubsystem",
                                    "AFKReportorSubsystem","BehaviorScoreSubsystem",
                                    "ClientDataStatistcsSubsystem"}) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and
                           (k:find("Report") or k:find("Send") or k:find("Tick") or k:find("Log")) then
                            pcall(function() sub[k] = nop end)
                        end
                    end
                end
            end
        end

        local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            for _, m in ipairs({"ControlMHActive","Tick","OnTick","MHActiveLogic",
                                "TriggerAvatarCheck","StartAvatarCheck","ReportItemID",
                                "ReceiveAnyDamage","OnWeaponHitRecord","ShowSecurityAlert",
                                "ServerReportAvatar","ClientReportNetAvatar","SendHisarData",
                                "ValidateSecurityData"}) do
                if Higgs[m] then Higgs[m] = nop end
            end
            Higgs.GetNetAvatarItemIDs = retEmpty
            Higgs.GetCurWeaponSkinID = retZero
        end
    end)
end

local function L35_START_HUNT_TIMER()
    local ok = false
    pcall(function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if pc and slua.isValid(pc) then
            if _G._V5HuntTimer then
                pcall(function() pc:RemoveGameTimer(_G._V5HuntTimer) end)
            end
            _G._V5HuntTimer = pc:AddGameTimer(3.0, true, L35_HUNT_TICK)
            ok = true
        end
    end)
    MarkLayer("L35_HUNT_TIMER", ok)
end

-- L36: anti-replay ban trap
local function L36_REPLAY_BAN()
    local ok = false
    pcall(function()
        local rs = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem")
        if rs then
            rs.StartReplayRecord = nop
            rs.StopReplayRecord = nop
            rs.UploadReplayData = nop
            rs.SubmitReplayForReview = nop
            ok = true
        end
        local SubMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local Review = SubMgr:Get("ReplayReviewSubsystem")
            if Review then
                Review.SubmitForReview = nop
                Review.UploadClip = nop
                Review.FlagPlayer = nop
                ok = true
            end
        end
    end)
    MarkLayer("L36_REPLAY_BAN", ok)
end

-- L37: login-time ban check silence
local function L37_LOGIN_BAN()
    local ok = false
    pcall(function()
        local LoginBan = safe_require("client.logic.login.logic_ban_check")
        if LoginBan then
            LoginBan.CheckBanOnLogin = retFalse
            LoginBan.QueryBanStatus = retNil
            LoginBan.OnBanResponse = nop
            ok = true
        end
        local LoginFlow = safe_require("client.logic.login.login_flow")
        if LoginFlow then
            LoginFlow.HandleBanMessage = nop
            LoginFlow.ShowBanDialog = nop
            LoginFlow.KickOutOnBan = nop
            ok = true
        end
        local LobbyBan = safe_require("client.logic.lobby.lobby_ban_check")
        if LobbyBan then
            LobbyBan.OnLobbyBanCheck = retFalse
            LobbyBan.ProcessBanData = nop
            ok = true
        end
    end)
    MarkLayer("L37_LOGIN_BAN", ok)
end

-- L38: kick/disconnect/forced-exit block
local function L38_KICK_BLOCK()
    local ok = false
    pcall(function()
        local KickHandler = safe_require("client.network.Protocol.KickHandler")
        if KickHandler then
            KickHandler.on_kick_notify = nop
            KickHandler.handle_kick = nop
            ok = true
        end
        local DSMgr = safe_require("GameLua.Mod.BaseMod.DS.Subsystem.DSKickSubsystem")
        if DSMgr then
            DSMgr.KickPlayer = nop
            DSMgr.KickPlayerFromMatch = nop
            DSMgr.DelayKickOutPlayer = nop
            ok = true
        end
        local FlowMgr = safe_require("client.logic.flow.exit_game_flow")
        if FlowMgr then
            FlowMgr.ForceExitGame = nop
            FlowMgr.ForceReturnToLobby = nop
            ok = true
        end
    end)
    MarkLayer("L38_KICK_BLOCK", ok)
end

-- L39: skin anti-detection (re-application)
L39_SKIN_ANTI_DETECTION = function()
    local ok = false
    pcall(function()
        local AvaEx = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
        if AvaEx then
            AvaEx.CheckAvatarException = nop
            AvaEx.CheckAvatarExceptionOnce = nop
            AvaEx.ReportAvatarException = nop
            AvaEx.CheckSlotMeshVisible = retFalse
            AvaEx.CheckPawnVisible = retFalse
            AvaEx.CheckCanBugglyPostException = retFalse
            ok = true
        end

        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if pc and slua.isValid(pc) then
            if pc.HiggsBoson then
                pc.HiggsBoson.bMHActive = false
                pc.HiggsBoson.bCallPreReplication = false
                if pc.HiggsBoson.ControlMHActive then
                    pcall(function() pc.HiggsBoson:ControlMHActive(0) end)
                end
                ok = true
            end
            if pc.HiggsBosonComponent then
                pc.HiggsBosonComponent.bMHActive = false
                pc.HiggsBosonComponent.bCallPreReplication = false
                if pc.HiggsBosonComponent.ControlMHActive then
                    pcall(function() pc.HiggsBosonComponent:ControlMHActive(0) end)
                end
                ok = true
            end
        end

        _G.BlackList = _G.BlackList or {}
        local keys = {}
        for k in pairs(_G.BlackList) do keys[#keys + 1] = k end
        for _, k in ipairs(keys) do _G.BlackList[k] = nil end
    end)
    MarkLayer("L39_SKIN_ANTI_DETECTION", ok)
end

-- ============================================================
-- [6] ESP NATIVE MARKS (ScreenMarkConfig blend)
-- ============================================================
local Esp = {}

local _MarkRetryCount = 0
local _MarkRetryDelay = 0.5

function Esp.PrimeNativeMarks()
  if A.Up.NativeReady then
    A.Up.NativePriming = false
    return
  end
  if _MarkRetryCount > 20 then
    A.Up.NativePriming = false
    return
  end
  local ok, result = pcall(function()
    local tools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
    local cfg = tools.GetCurrentConfig("ScreenMarkConfig")
    if not cfg then
      _MarkRetryCount = _MarkRetryCount + 1
      _MarkRetryDelay = math.min(_MarkRetryDelay * 1.5, 5.0)
      Later(_MarkRetryDelay, function()
        A.Up.NativePriming = false
        Esp.PrimeNativeMarks()
      end)
      return false
    end
    local function Blend(t)
      if not t then return end
      if t[1006] then
        t[1006].bBindBlocked = true
        t[1006].bBindOutScreen = true
        t[1006].MaxWidgetNum = 99
        t[1006].MaxShowDistance = 6000000
        t[1006].bScaleByDistance = false
        t[1006].BindSocketName = "root"
        t[1006].bUseLuaWorldSocketName = true
        t[1006].WorldPositionOffset = {X=0, Y=0, Z=-30}
      end
      t[9999] = {
        UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
        MaxWidgetNum = 99, MaxShowDistance = 6000000, bBindOutScreen = true,
        bBindBlocked = true, bIsBindingActor = true, BindSocketName = "head",
        bUseLuaWorldSocketName = true, WorldPositionOffset = {X=0, Y=0, Z=50},
        bNeedPreLoad = true, Priority = 2
      }
    end
    Blend(cfg)
    for key, mod in pairs(package.loaded) do
      if type(key) == "string" and string.find(key, "ScreenMarkConfig") and type(mod) == "table" then
        Blend(mod)
      end
    end
    _MarkRetryCount = 0
    _MarkRetryDelay = 0.5
    return true
  end)
  if ok and result then
    A.Up.NativeReady = true
    A.Up.NativePriming = false
  end
end

-- ============================================================
-- [7] INSTALLER + BOOT SCHEDULER
-- ============================================================
local function InstallAllLayers()
  if A.Up.LayersInstalled then return end
  A.Up.LayersInstalled = true

  pcall(L01_SLUA)
  pcall(L02_MD5)
  pcall(L03_SKIN)
  pcall(L04_LOG)
  pcall(L05_SCANNER)
  pcall(L06_REPLAY)
  pcall(L07_REPORT_FLOW)
  pcall(L08_PLAYER_SEC)
  pcall(L09_CLIENT_FLOW)
  pcall(L10_SWIFT_HAWK)
  pcall(L11_CORONA)
  pcall(L12_MODIFIER)
  pcall(L13_SIMULATE_CHAR)
  pcall(L14_SHOOT_VERIFY)
  pcall(L15_NET_PACKET)
  pcall(L16_HIGGS)
  pcall(L17_ANTICHEAT_HOOKS)
  pcall(L18_ANTI_REPORT)
  pcall(L19_GAMEPLAY_CALLBACKS)
  pcall(L20_KILL_SUBSYSTEMS)
  pcall(L21_MODULE_STUBS)
  pcall(L22_OPERATIONAL_STATS)
  pcall(L23_BASE)
  pcall(L24_BAN_SYSTEM)
  pcall(L25_REPORT_SYSTEMS)
  pcall(L26_TLOG)
  pcall(L27_NET_HANDLERS)
  pcall(L28_MISC)
  pcall(L29_EXTRA_SUBSYSTEMS)
  pcall(L30_NET_BLACKLIST)
  pcall(L31_FILEIO)
  pcall(L32_TSS_SDK)
  pcall(L33_HEURISTICS)
  pcall(L34_HWID_SPOOF)
  pcall(L39_SKIN_ANTI_DETECTION)
  pcall(L36_REPLAY_BAN)
  pcall(L37_LOGIN_BAN)
  pcall(L38_KICK_BLOCK)
  pcall(L35_START_HUNT_TIMER)

  pcall(function()
    import("KismetSystemLibrary"):ExecuteConsoleCommand(nil, "r.ShaderPipelineCache 0")
  end)
  print("[MERGED-SHIELD] All 39 layers installed")
end

local function BootShield()
  pcall(Shield.InstallAll)
  pcall(InstallAllLayers)
  pcall(function() Esp.PrimeNativeMarks() end)
end

pcall(function() Later(0.1, BootShield) end)
pcall(function() Later(2.0, BootShield) end)
pcall(function() Later(6.0, BootShield) end)

-- ============================================================
-- [8] CLASS RETURN
-- ============================================================
local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  {
    SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature"
  },
  {
    CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature"
  },
  {
    SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature"
  },
  {
    TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature"
  },
  {
    LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature"
  },
  {
    FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature"
  },
  {
    CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature"
  },
  {
    BuildAircraftVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"
  },
  {
    UnifiedBuildVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.UnifiedBuildVehicleFeature"
  },
  {
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
  },
  {
    ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"
  },
  {
    ParachuteSprint = "GameLua.Mod.BaseMod.GamePlay.Feature.Parachute.ParachuteSprintFeature"
  },
  {
    GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature"
  },
  {
    FPPAnimMonitor = "GameLua.Mod.BaseMod.GamePlay.Feature.Player.FPPAnimMonitorFeature"
  }
}, "BRPlayerCharacterBase")
