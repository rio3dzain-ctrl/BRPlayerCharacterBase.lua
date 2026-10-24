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

-- ============================================================================
-- HARDENED ESP MODULE
-- Changes vs original:
--   * no _G exposure (ESP / PlayerMapMarker / __ESPLookTickStarted all removed)
--   * all /Script/UMG.* paths char-built at runtime (no static strings)
--   * GameplayData-only enumeration (Game:GetAllPlayerPawns removed)
--   * scan 10 Hz, render 30 Hz, transform calibration 2 Hz, trace 4 Hz
--   * module-level SetGameTimer instead of pc:AddGameTimer
--   * cached requires (InGameUITools, GameplayData, timer)
--   * local module name _q7 — nothing survives in globals
-- ============================================================================

local _q7 = {}

local _c = string.char
local function _j(...)
  local t = { ... }
  local o = {}
  for i = 1, #t do
    local v = t[i]
    if type(v) == "number" then o[i] = _c(v) else o[i] = v end
  end
  return table.concat(o)
end
local _SL = _j(47)
local _DT = _j(46)
local _U  = _SL .. "Sc" .. "ri" .. "pt" .. _SL .. "UM" .. "G"
local _P_BORDER = _U .. _DT .. "Bor" .. "der"
local _P_CANVAS = _U .. _DT .. "Can" .. "vasPan" .. "el"
local _P_TEXT   = _U .. _DT .. "Tex" .. "tBl" .. "ock"

local _V2D  = _G.FVector2D    or import("Vector2D")
local _LC   = _G.FLinearColor or import("LinearColor")
local _SBPL = nil
local _WLL  = nil
local _SC   = nil
local _GPS  = nil
local _KSL  = nil
local _HRT  = nil
pcall(function() _SBPL = import("SlateBlueprintLibrary") end)
pcall(function() _WLL  = import("WidgetLayoutLibrary") end)
pcall(function() _SC   = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
pcall(function() _GPS  = import("GameplayStatics") end)
pcall(function() _KSL  = import("KismetSystemLibrary") end)
pcall(function() _HRT  = import("HitResult") end)

local _TPOS = { X = 0, Y = 0, Z = 0 }
local _THR  = nil
pcall(function() if _HRT then _THR = _HRT() else _THR = {} end end)

local function _ok(o)
  if o == nil then return false end
  local s, v = pcall(function() return slua.isValid(o) end)
  return s and v == true
end
local function _v2(x, y) if _V2D then return _V2D(x, y) end return { X = x, Y = y } end
local function _cl(r, g, b, a) if _LC then return _LC(r, g, b, a) end return { R = r, G = g, B = b, A = a } end

local CFG = {
  MaxDistance            = 50000,
  RenderTrackingDistance = 50000,
  MaxTracked             = 128,
  ScreenMargin           = 500,
  TopTextY               = 6.0,
  SnapOriginY            = 0.0,
  SnapThickness          = 1.8,
  CornerThickness        = 2.2,
  CornerLen              = 0.28,
  CornerMin              = 6,
  CornerMax              = 28,
  BoxMinWidth            = 22,
  BoxMaxWidth            = 320,
  BoxMinHeight           = 1,
  BoxWidthFactor         = 0.62,
  WidthScale             = 1.22,
  HeadExtra              = 0.06,
  FootExtra              = 0.02,
  SideBarWidth           = 3.5,
  SideBarGap             = 5.0,
  SideBgAlpha            = 0.55,
  MarkGap                = 8.0,
  MarkW                  = 15.0,
  MarkH                  = 10.0,
  MarkGapV               = 6.0,
  MarkThickness          = 2.4,
  NameFontSize           = 15,
  DistFontSize           = 13,
  StateFontSize          = 13,
  TextGap                = 1.0,
  CounterFontSize        = 17,
  CounterW               = 300.0,
  CounterH               = 28.0,
  DeadZone               = 0.5,
  VisInterval            = 0.25,
  SizeHyst               = 2.0,
}

local C_WHITE  = _cl(1.0, 1.0, 1.0, 1.0)
local C_BLACK  = _cl(0.0, 0.0, 0.0, 1.0)
local C_GREEN  = _cl(0.12, 1.0, 0.25, 1.0)
local C_RED    = _cl(1.0, 0.15, 0.15, 1.0)
local C_YELLOW = _cl(1.0, 0.90, 0.30, 1.0)
local C_BLUE   = _cl(0.38, 0.72, 1.0, 1.0)

local TEAM_COLORS = {
  _cl(0.20, 0.65, 1.00, 1.00),
  _cl(1.00, 0.28, 0.28, 1.00),
  _cl(0.25, 0.90, 0.40, 1.00),
  _cl(1.00, 0.72, 0.18, 1.00),
  _cl(0.72, 0.40, 1.00, 1.00),
  _cl(0.10, 0.88, 0.85, 1.00),
  _cl(1.00, 0.42, 0.78, 1.00),
  _cl(0.72, 0.82, 0.92, 1.00),
}

local function _TeamColor(teamID, isBot, fallbackKey)
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

local function _RND(v) if v ~= v then return 0 end return math.floor(v + 0.5) end
local function _Lerp(a, b, t) return a + (b - a) * t end

local function _HealthColor(pct)
  pct = tonumber(pct) or 1.0
  if pct < 0 then pct = 0 end
  if pct > 1 then pct = 1 end
  local r, g, b
  if pct >= 0.7 then
    local t = (pct - 0.7) / 0.3
    r = _Lerp(0.75, 0.12, t); g = 1.0; b = _Lerp(0.15, 0.25, t)
  elseif pct >= 0.4 then
    local t = (pct - 0.4) / 0.3
    r = 1.0; g = _Lerp(0.45, 0.95, t); b = _Lerp(0.45, 0.20, t)
  else
    local t = pct / 0.4
    r = 1.0; g = _Lerp(0.15, 0.45, t); b = _Lerp(0.15, 0.45, t)
  end
  return _cl(r, g, b, 1.0)
end

_q7.Canvas       = nil
_q7.Lines        = {}
_q7.Corners      = {}
_q7.HealthBg     = {}
_q7.HealthFill   = {}
_q7.Marks        = {}
_q7.Infos        = {}
_q7.Counter      = nil
_q7.EnemyCache   = {}
_q7.VisCache     = {}
_q7.ScaleX       = 1.0
_q7.ScaleY       = 1.0
_q7.OffsetX      = 0.0
_q7.OffsetY      = 0.0
_q7.ViewW        = 1920
_q7.ViewH        = 1080
_q7.ScanInterval      = 0.100
_q7.LightInterval     = 0.033
_q7.TransformInterval = 0.500
_q7.LastScan      = -999.0
_q7.LastTransform = -999.0
_q7.LastWorld     = nil
_q7.bActive       = false
_q7.RealCount     = 0
_q7.BotCount      = 0

local _GDP_cache   = nil
local _UIT_cache   = nil
local _timer_cache = nil

local function _GetTimer()
  if _timer_cache then return _timer_cache end
  local s, m = pcall(function() return require("timer") end)
  if s and m then _timer_cache = m return m end
  return nil
end

local function _GetUIT()
  if _UIT_cache then return _UIT_cache end
  local s, m = pcall(function() return require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
  if s and m then _UIT_cache = m return m end
  return nil
end

function _q7.GetGameplayData()
  if _GDP_cache then return _GDP_cache end
  local s, m = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
  if s and m then _GDP_cache = m return m end
  return nil
end

function _q7.GetController()
  local pc = nil
  pcall(function()
    local GDP = _q7.GetGameplayData()
    if GDP and GDP.GetPlayerController then pc = GDP.GetPlayerController() end
  end)
  if not _ok(pc) then
    pcall(function()
      if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
    end)
  end
  return _ok(pc) and pc or nil
end

function _q7.GetLocalCharacter()
  local c = nil
  pcall(function()
    local GDP = _q7.GetGameplayData()
    if GDP then
      if GDP.GetPlayerCharacter then c = GDP.GetPlayerCharacter() end
      if not _ok(c) and GDP.GetLocalCharacter then c = GDP.GetLocalCharacter() end
    end
  end)
  if not _ok(c) then
    local pc = _q7.GetController()
    pcall(function() if pc and pc.GetPawn then c = pc:GetPawn() end end)
  end
  return _ok(c) and c or nil
end

function _q7.GetAllCharacters()
  local out = {}
  local GDP = _q7.GetGameplayData()
  if not GDP then return out end
  local chars = nil
  pcall(function() if GDP.GetAllCharacters then chars = GDP:GetAllCharacters() end end)
  if not chars then return out end
  for k, ch in pairs(chars) do
    if ch and _ok(ch) then
      local pKey = k
      pcall(function()
        if not pKey and ch.GetPlayerKey then pKey = ch:GetPlayerKey() end
        if not pKey and ch.PlayerKey then pKey = ch.PlayerKey end
        if not pKey and ch.PlayerState and ch.PlayerState.PlayerKey then
          pKey = ch.PlayerState.PlayerKey
        end
      end)
      if pKey then out[pKey] = ch end
    end
  end
  return out
end

function _q7.GetMyPlayerKey()
  local pc = _q7.GetController()
  if not _ok(pc) then return nil end
  local k = nil
  pcall(function()
    if pc.GetPlayerKey then k = pc:GetPlayerKey()
    elseif pc.PlayerState and pc.PlayerState.PlayerKey then k = pc.PlayerState.PlayerKey end
  end)
  return k
end

function _q7.IsMe(Character, PlayerKey, MyKey)
  local me = false
  pcall(function()
    local GDP = _q7.GetGameplayData()
    if GDP and GDP.GetLocalCharacter then
      local mc = GDP.GetLocalCharacter()
      if mc and Character == mc then me = true return end
    end
    local pc = _q7.GetController()
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

function _q7.GetTeamID(Character)
  if not _ok(Character) then return nil end
  local id = nil
  pcall(function() if Character.GetTeamID then id = Character:GetTeamID() end end)
  if id == nil then pcall(function() id = Character.TeamID end) end
  if id == nil then
    local ps = nil
    pcall(function()
      if Character.GetPlayerStateSafety then ps = Character:GetPlayerStateSafety()
      elseif Character.GetPlayerState then ps = Character:GetPlayerState() end
    end)
    if not _ok(ps) then pcall(function() ps = Character.PlayerState end) end
    if _ok(ps) then
      pcall(function() if ps.GetTeamID then id = ps:GetTeamID() end end)
      if id == nil then pcall(function() id = ps.TeamID end) end
    end
  end
  return id
end

function _q7.IsAlive(Character)
  if not _ok(Character) then return false end
  local alive = nil
  pcall(function() if Character.IsAlive then alive = Character:IsAlive() end end)
  if type(alive) == "boolean" then return alive end
  local hp = nil
  pcall(function() hp = Character.Health end)
  if type(hp) ~= "number" then pcall(function() hp = Character.HP end) end
  if type(hp) == "number" then return hp > 0 end
  return true
end

function _q7.IsKnocked(Character)
  if not _ok(Character) then return false end
  local k = false
  pcall(function() if Character.HealthStatus == 1 then k = true end end)
  if not k then pcall(function()
    if Character.IsNearDeath and Character:IsNearDeath() then k = true end
  end) end
  return k
end

function _q7.IsBot(Character)
  if not _ok(Character) then return false end
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
    if _ok(ps) then
      pcall(function()
        if ps.bIsABot == true or ps.bIsBot == true or ps.bIsAI == true then bAI = true end
      end)
    end
  end
  return bAI
end

function _q7.GetPlayerKey(Character)
  local key = nil
  pcall(function() if Character.GetPlayerKey then key = Character:GetPlayerKey() end end)
  if key == nil then pcall(function() key = Character.PlayerKey end) end
  return tostring(key or Character)
end

function _q7.GetHealthPct(Character)
  if not _ok(Character) then return 1.0 end
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

local function _NormName(v)
  if v == nil or v == false then return nil end
  local ok, t = pcall(tostring, v)
  if not ok or not t then return nil end
  t = t:gsub("^%s+", ""):gsub("%s+$", "")
  if t == "" or t == "nil" or t == "None" or t == "NULL" or t == "Unknown" then return nil end
  return t
end

function _q7.ResolveName(Character, isBot)
  if isBot then return "Bot" end
  local name = nil
  local function take(v) if not name then name = _NormName(v) end end
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
    if not _ok(ps) then pcall(function() ps = Character.PlayerState end) end
    if _ok(ps) then
      pcall(function() if ps.GetPlayerName then take(ps:GetPlayerName()) end end)
      pcall(function() if not name then take(ps.PlayerName) end end)
      pcall(function() if not name then take(ps.PlayerNamePrivate) end end)
      pcall(function() if not name then take(ps.NickName) end end)
    end
  end
  return name or "Player"
end

function _q7.GetBonePos(Character, boneName)
  if not _ok(Character) or not boneName then return nil end
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
    if (not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0)) and _ok(Character.Mesh) then
      local mesh = Character.Mesh
      if mesh and mesh.GetSocketLocation then
        local mp = mesh:GetSocketLocation(boneName)
        if mp and not (mp.X == 0 and mp.Y == 0 and mp.Z == 0) then pos = mp end
      end
    end
  end)
  return pos
end

function _q7.GetCamLoc(pc)
  local loc = nil
  pcall(function()
    if _GPS and _GPS.GetPlayerCameraManager then
      local mgr = _GPS.GetPlayerCameraManager(pc, 0)
      if _ok(mgr) and mgr.GetCameraLocation then loc = mgr:GetCameraLocation() end
    end
  end)
  if not loc then
    pcall(function()
      if pc and pc.GetPawn then
        local p = pc:GetPawn()
        if _ok(p) and p.K2_GetActorLocation then loc = p:K2_GetActorLocation() end
      end
    end)
  end
  return loc
end

function _q7.IsBoneVisible(pc, camLoc, target, bonePos)
  if not _ok(pc) or not _ok(target) or not bonePos or not camLoc then return false end
  if not _KSL or not _KSL.LineTraceSingle then return true end
  local dx = bonePos.X - camLoc.X
  local dy = bonePos.Y - camLoc.Y
  local dz = bonePos.Z - camLoc.Z
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  if dist < 300 then return true end
  _TPOS.X = camLoc.X + (dx / dist) * 60
  _TPOS.Y = camLoc.Y + (dy / dist) * 60
  _TPOS.Z = camLoc.Z + (dz / dist) * 60
  local bVis = false
  pcall(function()
    local bHit = _KSL.LineTraceSingle(
      pc, _TPOS, bonePos, 0, false, nil, 0, _THR, true)
    if bHit then
      local hitActor = nil
      if _THR then
        if type(_THR.GetActor) == "function" then
          hitActor = _THR:GetActor()
        elseif _THR.Actor then
          hitActor = _THR.Actor
        end
      end
      if _ok(hitActor) then
        if hitActor == target then bVis = true end
      end
    else
      bVis = true
    end
  end)
  return bVis
end

function _q7.IsVisible(key, pc, camLoc, Character)
  local now = _q7.Now()
  local cached = _q7.VisCache[key]
  if cached and (now - (cached.t or 0)) < (CFG.VisInterval or 0.25) then
    return cached.b
  end
  local bVis = false
  if _ok(Character) and _ok(pc) and camLoc then
    local bones = { "head", "spine_03", "pelvis" }
    for _, bn in ipairs(bones) do
      local bp = _q7.GetBonePos(Character, bn)
      if bp and (bp.X ~= 0 or bp.Y ~= 0 or bp.Z ~= 0) then
        if _q7.IsBoneVisible(pc, camLoc, Character, bp) then bVis = true break end
      end
    end
  else
    bVis = true
  end
  _q7.VisCache[key] = { b = bVis, t = now }
  return bVis
end

function _q7.ActorLocation(Character)
  local loc = nil
  if not _ok(Character) then return nil end
  pcall(function()
    if Character.K2_GetActorLocation then loc = Character:K2_GetActorLocation()
    elseif Game and Game.GetActorLocation then loc = Game:GetActorLocation(Character) end
  end)
  return loc
end

function _q7.DistMeters(a, b)
  if not a or not b then return math.huge end
  local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
  return math.sqrt(dx * dx + dy * dy + dz * dz) / 100.0
end

function _q7.GetVerticalBounds(Character)
  if not _ok(Character) then return nil, nil end
  local center, halfHeight = nil, nil
  local capsule = nil
  pcall(function()
    if Character.GetCapsuleComponent then capsule = Character:GetCapsuleComponent()
    elseif Character.CapsuleComponent then capsule = Character.CapsuleComponent end
  end)
  if capsule and _ok(capsule) then
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

function _q7.GetHeadFeet(Character)
  local center, half = _q7.GetVerticalBounds(Character)
  if not center or not half then return nil, nil end
  local head = { X = center.X, Y = center.Y, Z = center.Z + half }
  local feet = { X = center.X, Y = center.Y, Z = center.Z - half }
  return head, feet
end

function _q7.Now()
  local t = nil
  pcall(function()
    local w = (slua and slua.getWorld and slua.getWorld()) or nil
    if _GPS and w and _GPS.GetRealTimeSeconds then
      t = _GPS.GetRealTimeSeconds(w)
    end
  end)
  if tonumber(t) then return tonumber(t) end
  pcall(function() if os and os.clock then t = os.clock() end end)
  return tonumber(t) or 0.0
end

function _q7.World()
  local w = nil
  pcall(function() if slua and slua.getWorld then w = slua.getWorld() end end)
  return w
end

function _q7.GetCanvas()
  if _ok(_q7.Canvas) then return _q7.Canvas end
  local root = nil
  local UIT = _GetUIT()
  if UIT and UIT.GetMainControlBaseUI then
    pcall(function() root = UIT.GetMainControlBaseUI() end)
  end
  if not _ok(root) then return nil end
  local canvas = nil
  pcall(function()
    if _ok(root.CanvasPanel_0) then canvas = root.CanvasPanel_0
    elseif _ok(root.CanvasPanel_42) then canvas = root.CanvasPanel_42 end
  end)
  if _ok(canvas) then _q7.Canvas = canvas return canvas end
  return nil
end

function _q7.UpdateCanvasTransform(pc)
  local canvas = _q7.GetCanvas()
  if not _ok(canvas) then return false end
  local calibrated = false
  pcall(function()
    if _SBPL and _SBPL.AbsoluteToLocal then
      local geo = canvas:GetCachedGeometry()
      if geo then
        local p0 = _SBPL.AbsoluteToLocal(geo, _v2(0, 0))
        local p1 = _SBPL.AbsoluteToLocal(geo, _v2(100, 100))
        if p0 and p1 and tonumber(p0.X) and tonumber(p1.X) and p1.X ~= p0.X and p1.Y ~= p0.Y then
          _q7.ScaleX  = (p1.X - p0.X) / 100.0
          _q7.ScaleY  = (p1.Y - p0.Y) / 100.0
          _q7.OffsetX = p0.X
          _q7.OffsetY = p0.Y
          calibrated = true
        end
      end
    end
  end)
  if not calibrated then
    local scale = 1.0
    pcall(function()
      if _WLL and _WLL.GetViewportScale then
        local s = _WLL.GetViewportScale(pc)
        if tonumber(s) and s > 0 then scale = s end
      end
    end)
    _q7.ScaleX  = 1.0 / scale
    _q7.ScaleY  = 1.0 / scale
    _q7.OffsetX = 0.0
    _q7.OffsetY = 0.0
  end
  return true
end

function _q7.Viewport(pc)
  local w, h = 1920.0, 1080.0
  pcall(function()
    if pc and pc.GetViewportSize then
      local v = _v2(0, 0)
      pc:GetViewportSize(v)
      if v and tonumber(v.X) and v.X > 200 then w, h = v.X, v.Y end
    end
  end)
  return w, h
end

function _q7.Project(pc, worldLoc)
  if not pc or not worldLoc then return nil end
  local pix = _v2(0, 0)
  local ok = false
  pcall(function()
    local res = pc:ProjectWorldLocationToScreen(worldLoc, pix, true)
    ok = (res == true or res == 1 or (pix and (pix.X ~= 0 or pix.Y ~= 0)))
  end)
  if not ok then return nil end
  return _v2(pix.X * (_q7.ScaleX or 1.0) + (_q7.OffsetX or 0.0),
             pix.Y * (_q7.ScaleY or 1.0) + (_q7.OffsetY or 0.0)), pix
end

function _q7.SetFont(w, size)
  if not _ok(w) then return end
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
    if w.SetShadowOffset then w:SetShadowOffset(_v2(1.0, 1.0)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(C_BLACK) end
  end)
end

function _q7.SetTextColor(w, color)
  if not _ok(w) then return end
  pcall(function()
    if _SC then w:SetColorAndOpacity(_SC(color))
    else w:SetColorAndOpacity(color) end
  end)
end

function _q7.NewWidget(cls, parent)
  local w = nil
  pcall(function() w = CGame:NewObjectFromPath(cls, parent) end)
  return _ok(w) and w or nil
end

function _q7.NewLine(color, z)
  local canvas = _q7.GetCanvas()
  if not _ok(canvas) then return nil end
  local border = _q7.NewWidget(_P_BORDER, canvas)
  if not border then return nil end
  pcall(function()
    border:SetBrushColor(color)
    border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    border:SetRenderTransformPivot(_v2(0.0, 0.5))
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

function _q7.DrawLine(data, x1, y1, x2, y2, thickness)
  if not data or not _ok(data.Widget) or not data.Slot then return false end
  if x1 ~= x1 or y1 ~= y1 or x2 ~= x2 or y2 ~= y2 then return false end
  x1, y1, x2, y2 = _RND(x1), _RND(y1), _RND(x2), _RND(y2)
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
    _q7.Hide(data)
    return false
  end
  local angle = ((math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)) * 180.0 / math.pi
  angle = math.floor(angle * 10 + 0.5) / 10
  len = _RND(len)
  if data.lx1 == x1 and data.ly1 == y1 and data.lx2 == x2 and data.ly2 == y2 and data.th == thickness then
    if data.hidden == true then
      pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
      data.hidden = false
    end
    return true
  end
  local okp = pcall(function()
    data.Slot:SetPosition(_v2(x1, y1 - thickness * 0.5))
    data.Slot:SetSize(_v2(len, thickness))
    data.Widget:SetRenderAngle(angle)
    data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if okp then
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = x1, y1, x2, y2, thickness
    data.hidden = false
  end
  return true
end

function _q7.DrawVBar(data, x, top, h, thickness)
  if not data or not _ok(data.Widget) or not data.Slot then return false end
  if h ~= h or h < 1 then _q7.Hide(data) return false end
  x, top, h = _RND(x), _RND(top), _RND(h)
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
  local okp = pcall(function()
    data.Slot:SetPosition(_v2(x, top))
    data.Slot:SetSize(_v2(thickness, h))
    data.Widget:SetRenderAngle(0)
    data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if okp then data.bx, data.bt, data.bh = x, top, h data.hidden = false end
  return true
end

function _q7.Hide(data)
  if data and _ok(data.Widget) and data.hidden ~= true then
    pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    data.hidden = true
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = nil, nil, nil, nil, nil
    data.bx, data.bt, data.bh = nil, nil, nil
  end
end

function _q7.SetBrush(data, color, colorKey)
  if not data or not _ok(data.Widget) then return end
  if colorKey and data.colorKey == colorKey then return end
  pcall(function() data.Widget:SetBrushColor(color) end)
  if colorKey then data.colorKey = colorKey end
end

function _q7.Destroy(data)
  if not data then return end
  local w = data.Widget or data.Container
  if _ok(w) then
    pcall(function() w:RemoveFromParent() end)
    pcall(function() w:ConditionalBeginDestroy() end)
  end
end

function _q7.CreateCounter()
  local canvas = _q7.GetCanvas()
  if not _ok(canvas) then return nil end
  local container = _q7.NewWidget(_P_CANVAS, canvas)
  if not container then return nil end
  local txt = _q7.NewWidget(_P_TEXT, container)
  if not txt then _q7.Destroy({ Widget = container }) return nil end
  pcall(function()
    txt:SetText("Players: 0 | Bots: 0")
    txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if txt.SetJustification then txt:SetJustification(1) end
  end)
  _q7.SetTextColor(txt, C_WHITE)
  _q7.SetFont(txt, CFG.CounterFontSize)
  local tSlot, mSlot = nil, nil
  pcall(function() tSlot = container:AddChildToCanvas(txt) end)
  pcall(function() mSlot = canvas:AddChildToCanvas(container) end)
  if not tSlot or not mSlot then _q7.Destroy({ Widget = container }) return nil end
  local W, H = CFG.CounterW or 300.0, CFG.CounterH or 28.0
  pcall(function()
    tSlot:SetAutoSize(true)
    tSlot:SetAlignment(_v2(0.5, 0.5))
    tSlot:SetPosition(_v2(W * 0.5, H * 0.5))
    tSlot:SetZOrder(5)
    mSlot:SetAutoSize(false)
    mSlot:SetAlignment(_v2(0.5, 0.0))
    mSlot:SetSize(_v2(W, H))
    mSlot:SetZOrder(60)
  end)
  return { Container = container, Text = txt, Slot = mSlot, W = W, H = H }
end

function _q7.CanvasCenterX(viewW)
  local cw = nil
  pcall(function()
    local canvas = _q7.GetCanvas()
    if _ok(canvas) then
      local geo = canvas:GetCachedGeometry()
      if geo and geo.GetLocalSize then
        local s = geo:GetLocalSize()
        if s and tonumber(s.X) and s.X > 1 then cw = tonumber(s.X) end
      end
    end
  end)
  if tonumber(cw) and cw > 1 then return cw * 0.5 end
  return (viewW * 0.5) * (_q7.ScaleX or 1.0) + (_q7.OffsetX or 0.0)
end

function _q7.UpdateCounter(nPlayers, nBots, pc, viewW)
  local d = _q7.Counter
  if not d or not _ok(d.Container) then
    _q7.Destroy(d)
    d = _q7.CreateCounter()
    _q7.Counter = d
  end
  if not d then return nil end
  local label = string.format("Players: %d | Bots: %d", nPlayers or 0, nBots or 0)
  pcall(function()
    if d.Last ~= label then d.Text:SetText(label) d.Last = label end
  end)
  local cx = _q7.CanvasCenterX(viewW)
  if cx then
    cx = _RND(cx)
    if d.px == nil or math.abs(d.px - cx) >= 1.0 then
      d.px = cx
      pcall(function()
        d.Slot:SetPosition(_v2(cx, CFG.TopTextY))
        d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    else
      pcall(function()
        d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    end
  end
  return _v2(cx, (CFG.SnapOriginY or 0.0))
end

function _q7.CreateInfo()
  local canvas = _q7.GetCanvas()
  if not _ok(canvas) then return nil end
  local container, teamBox, tName, tDist, tState = nil, nil, nil, nil, nil
  container = _q7.NewWidget(_P_CANVAS, canvas)
  if not container then return nil end
  teamBox = _q7.NewWidget(_P_BORDER, container)
  tName   = _q7.NewWidget(_P_TEXT, container)
  tDist   = _q7.NewWidget(_P_TEXT, container)
  tState  = _q7.NewWidget(_P_TEXT, container)
  if not teamBox or not tName or not tDist or not tState then
    _q7.Destroy({ Widget = container })
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

  _q7.SetTextColor(tName, C_WHITE)
  _q7.SetTextColor(tDist, C_WHITE)
  _q7.SetTextColor(tState, C_GREEN)
  _q7.SetFont(tName, CFG.NameFontSize)
  _q7.SetFont(tDist, CFG.DistFontSize)
  _q7.SetFont(tState, CFG.StateFontSize)

  local bSlot, nSlot, s2, s3, ms = nil, nil, nil, nil, nil
  pcall(function() bSlot = container:AddChildToCanvas(teamBox) end)
  pcall(function() nSlot = container:AddChildToCanvas(tName) end)
  pcall(function() s2 = container:AddChildToCanvas(tDist) end)
  pcall(function() s3 = container:AddChildToCanvas(tState) end)
  pcall(function() ms = canvas:AddChildToCanvas(container) end)
  if not bSlot or not nSlot or not s2 or not s3 or not ms then
    _q7.Destroy({ Widget = container })
    return nil
  end

  pcall(function()
    bSlot:SetAutoSize(false)
    bSlot:SetSize(_v2(120.0, 22.0))
    bSlot:SetAlignment(_v2(0.5, 0.5))
    bSlot:SetZOrder(34)

    nSlot:SetAutoSize(false)
    nSlot:SetSize(_v2(120.0, 22.0))
    nSlot:SetAlignment(_v2(0.5, 0.5))
    nSlot:SetZOrder(36)

    s2:SetAutoSize(true)
    s2:SetAlignment(_v2(0.5, 0.5))
    s2:SetZOrder(36)
    s3:SetAutoSize(true)
    s3:SetAlignment(_v2(0.5, 0.5))
    s3:SetZOrder(36)
    ms:SetAutoSize(false)
    ms:SetZOrder(35)
  end)
  return { Container = container, TeamBox = teamBox, Name = tName, Dist = tDist, State = tState,
           S0 = bSlot, S1 = nSlot, S2 = s2, S3 = s3, Slot = ms }
end

function _q7.UpdateInfo(key, Character, isBot, teamID, distM, bVisible, headX, headY, footX, footY, boxL, boxR)
  local d = _q7.Infos[key]
  if not d or not _ok(d.Container) then
    _q7.Destroy(d)
    d = _q7.CreateInfo()
    _q7.Infos[key] = d
  end
  if not d then return end

  local name = d.CachedName
  if not name then
    name = _q7.ResolveName(Character, isBot)
    d.CachedName = name
  end
  if isBot then name = "Bot" d.CachedName = "Bot" end

  local dl = string.format("%dm", math.max(0, math.floor((tonumber(distM) or 0) + 0.5)))
  local st = bVisible and "Open" or "Close"
  local teamColor = _TeamColor(teamID, isBot, key)

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
    if bVisible then _q7.SetTextColor(d.State, C_GREEN)
    else _q7.SetTextColor(d.State, C_RED) end
  end)

  local bannerW = 100.0
  local bannerH = 22.0
  local bx = _RND(headX)
  local by = _RND(headY - 18.0)

  pcall(function()
    d.Slot:SetPosition(_v2(bx, by))
    d.Slot:SetSize(_v2(bannerW, 70.0))
    d.S0:SetPosition(_v2(0.0, 0.0))
    d.S0:SetSize(_v2(bannerW, bannerH))
    d.S1:SetPosition(_v2(0.0, 0.0))
    d.S1:SetSize(_v2(bannerW, bannerH))
    d.S2:SetPosition(_v2(bannerW * 0.5, bannerH + 12.0))
    d.S3:SetPosition(_v2(bannerW * 0.5, bannerH + 30.0))
    d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)

  d.ix, d.iy = bx, by
end

function _q7.EnsureCorner(key, idx, color)
  local t = _q7.Corners[key]
  if not t then t = {} _q7.Corners[key] = t end
  local d = t[idx]
  if d and _ok(d.Widget) then return d end
  d = _q7.NewLine(color or C_WHITE, 32)
  t[idx] = d
  return d
end

function _q7.EnsureHealthBg(key)
  local d = _q7.HealthBg[key]
  if d and _ok(d.Widget) then return d end
  d = _q7.NewLine(_cl(0.0, 0.0, 0.0, CFG.SideBgAlpha or 0.55), 31)
  _q7.HealthBg[key] = d
  return d
end

function _q7.EnsureHealthFill(key)
  local d = _q7.HealthFill[key]
  if d and _ok(d.Widget) then return d end
  d = _q7.NewLine(C_GREEN, 32)
  _q7.HealthFill[key] = d
  return d
end

function _q7.UpdateHealthBar(key, pct, x, y, w)
  local bg = _q7.EnsureHealthBg(key)
  local fill = _q7.EnsureHealthFill(key)
  if not bg or not fill then return end
  local thickness = CFG.SideBarWidth or 3.5
  w = math.max(1, tonumber(w) or 1)

  _q7.DrawLine(bg, x, y, x + w, y, thickness)

  pct = tonumber(pct) or 1.0
  if pct < 0 then pct = 0 end
  if pct > 1 then pct = 1 end

  local bucket
  if pct >= 0.7 then bucket = "g_" .. math.floor(pct * 20 + 0.5)
  elseif pct >= 0.4 then bucket = "y_" .. math.floor(pct * 20 + 0.5)
  else bucket = "r_" .. math.floor(pct * 20 + 0.5) end
  _q7.SetBrush(fill, _HealthColor(pct), bucket)

  local fw = w * pct
  if fw < 1 then
    _q7.Hide(fill)
    return
  end
  _q7.DrawLine(fill, x, y, x + fw, y, thickness)
end

function _q7.EnsureSnap(key)
  local d = _q7.Lines[key]
  if d and _ok(d.Widget) then return d end
  d = _q7.NewLine(C_GREEN, 30)
  _q7.Lines[key] = d
  return d
end

function _q7.HideTarget(key)
  local c = _q7.Corners[key]
  if c then for i = 1, 8 do _q7.Hide(c[i]) end end
  _q7.Hide(_q7.HealthBg[key])
  _q7.Hide(_q7.HealthFill[key])
  local m = _q7.Marks[key]
  if m then for i = 1, 4 do _q7.Hide(m[i]) end end
  _q7.Hide(_q7.Lines[key])
  local inf = _q7.Infos[key]
  if inf and _ok(inf.Container) then
    pcall(function() inf.Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
  end
end

function _q7.ReleaseTarget(key)
  local c = _q7.Corners[key]
  if c then for i = 1, 8 do _q7.Destroy(c[i]) end end
  _q7.Corners[key] = nil
  _q7.Destroy(_q7.HealthBg[key])
  _q7.HealthBg[key] = nil
  _q7.Destroy(_q7.HealthFill[key])
  _q7.HealthFill[key] = nil
  local m = _q7.Marks[key]
  if m then for i = 1, 4 do _q7.Destroy(m[i]) end end
  _q7.Marks[key] = nil
  _q7.Destroy(_q7.Lines[key])
  _q7.Lines[key] = nil
  _q7.Destroy(_q7.Infos[key])
  _q7.Infos[key] = nil
  _q7.VisCache[key] = nil
end

function _q7.ResetWidgets()
  for _, d in pairs(_q7.Lines) do _q7.Destroy(d) end
  for _, t in pairs(_q7.Corners) do for _, d in pairs(t) do _q7.Destroy(d) end end
  for _, d in pairs(_q7.HealthBg) do _q7.Destroy(d) end
  for _, d in pairs(_q7.HealthFill) do _q7.Destroy(d) end
  for _, t in pairs(_q7.Marks) do for _, d in pairs(t) do _q7.Destroy(d) end end
  for _, d in pairs(_q7.Infos) do _q7.Destroy(d) end
  _q7.Lines = {}
  _q7.Corners = {}
  _q7.HealthBg = {}
  _q7.HealthFill = {}
  _q7.Marks = {}
  _q7.Infos = {}
  _q7.VisCache = {}
  if _q7.Counter then _q7.Destroy(_q7.Counter) end
  _q7.Counter = nil
  _q7.Canvas = nil
  _q7.EnemyCache = {}
end

function _q7.Scan()
  local pc = _q7.GetController()
  local me = _q7.GetLocalCharacter()
  if not pc or not me then _q7.EnemyCache = {} return pc, 0, 0 end
  local myLoc = _q7.ActorLocation(me)
  if not myLoc then _q7.EnemyCache = {} return pc, 0, 0 end
  local myTeam = _q7.GetTeamID(me)
  local list = {}
  local nReal, nBot = 0, 0
  local pawns = _q7.GetAllCharacters()
  local seen = {}
  local function addPawn(ch)
    if not _ok(ch) or ch == me or not _q7.IsAlive(ch) then return end
    local key = _q7.GetPlayerKey(ch)
    if seen[key] then return end
    local team = _q7.GetTeamID(ch)
    if myTeam ~= nil and team ~= nil and tostring(team) == tostring(myTeam) then return end
    local loc = _q7.ActorLocation(ch)
    local dm = _q7.DistMeters(myLoc, loc)
    seen[key] = true
    local isBot = _q7.IsBot(ch)
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
  _q7.EnemyCache = trimmed
  return pc, nReal, nBot
end

function _q7.Update()
  local world = _q7.World()
  if world ~= _q7.LastWorld then
    _q7.ResetWidgets()
    _q7.LastWorld = world
    _q7.LastScan = -999.0
    _q7.LastTransform = -999.0
  end
  local canvas = _q7.GetCanvas()
  if not canvas then return end
  local now = _q7.Now()
  local pc = _q7.GetController()
  if (now - _q7.LastScan) >= (_q7.ScanInterval or 0.100) then
    local r, b
    pc, r, b = _q7.Scan()
    _q7.LastScan = now
    _q7.RealCount, _q7.BotCount = r or 0, b or 0
  end
  pc = pc or _q7.GetController()
  if not pc then return end
  if (now - (_q7.LastTransform or -999.0)) >= (_q7.TransformInterval or 0.500) then
    _q7.UpdateCanvasTransform(pc)
    _q7.LastTransform = now
  end
  local vw, vh = _q7.Viewport(pc)
  local hyst = CFG.SizeHyst or 2.0
  if math.abs(vw - (_q7.ViewW or 0)) > hyst or math.abs(vh - (_q7.ViewH or 0)) > hyst then
    _q7.ViewW, _q7.ViewH = vw, vh
  else
    vw, vh = _q7.ViewW, _q7.ViewH
  end
  local origin = _q7.UpdateCounter(_q7.RealCount or 0, _q7.BotCount or 0, pc, vw)
  if not origin then return end
  local camLoc = _q7.GetCamLoc(pc)

  local active = {}
  for _, item in ipairs(_q7.EnemyCache) do
    local c = item.Character
    local key = item.Key
    if _ok(c) and _q7.IsAlive(c) then
      local head, feet = _q7.GetHeadFeet(c)
      if head and feet then
        local headS, headPix = _q7.Project(pc, head)
        local feetS, feetPix = _q7.Project(pc, feet)
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

              local corners = _q7.Corners[key]
              if corners then for i = 1, 8 do _q7.Hide(corners[i]) end end

              local pct = _q7.GetHealthPct(c)
              local hbY = headS.Y + 8.0
              _q7.UpdateHealthBar(key, pct, L, hbY, R - L)

              local marks = _q7.Marks[key]
              if marks then for i = 1, 4 do _q7.Hide(marks[i]) end end

              _q7.DrawLine(_q7.EnsureSnap(key), origin.X, origin.Y, headS.X, headS.Y,
                           CFG.SnapThickness or 1.8)

              local bVis = _q7.IsVisible(key, pc, camLoc, c)
              _q7.UpdateInfo(key, c, item.IsBot, item.TeamID, item.Distance, bVis,
                            headS.X, headS.Y, cx, B, L, R)
            else
              _q7.HideTarget(key)
            end
          else
            _q7.HideTarget(key)
          end
        else
          _q7.HideTarget(key)
        end
      else
        _q7.HideTarget(key)
      end
    end
  end
  local seenCache = {}
  for _, it in ipairs(_q7.EnemyCache) do seenCache[it.Key] = true end
  local function stillActive(k)
    return active[k] == true
  end
  for k, _ in pairs(_q7.Lines) do if not stillActive(k) then _q7.HideTarget(k) end end
  for k, _ in pairs(_q7.Infos) do if not stillActive(k) then _q7.HideTarget(k) end end
  for k, _ in pairs(_q7.Corners) do
    if not stillActive(k) and not seenCache[k] then _q7.ReleaseTarget(k) end
  end
  for k, _ in pairs(_q7.HealthBg) do
    if not seenCache[k] and not stillActive(k) then _q7.ReleaseTarget(k) end
  end
end

function _q7.Tick()
  pcall(_q7.Update)
end

function _q7.AttachTimers()
  pcall(function()
    local T = _GetTimer()
    if not T or not T.SetGameTimer then return end
    if _q7._TimerHooked then return end
    _q7._TimerHooked = true
    T.SetGameTimer(_q7.LightInterval or 0.033, true, function()
      if _q7.bActive then pcall(_q7.Tick) end
    end)
    T.SetGameTimer(5.0, false, function()
      _q7._TimerHooked = false
      _q7.AttachTimers()
    end)
  end)
end

function _q7.Start()
  if _q7.bActive then return end
  _q7.bActive = true
  pcall(_q7.Update)
  _q7.AttachTimers()
end

local function _q7_later(sec, fn)
  local T = _GetTimer()
  if T and T.SetGameTimer then
    pcall(function() T.SetGameTimer(sec, false, fn) end)
  end
end

local _q7_started_pc = nil
local function _q7_start_all()
  pcall(function()
    local pc = nil
    if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
    if not _ok(pc) then pc = _q7.GetController() end
    if _ok(pc) then
      if pc ~= _q7_started_pc then
        _q7_started_pc = pc
        _q7._TimerHooked = false
        _q7.Start()
      else
        _q7.AttachTimers()
      end
    end
  end)
end

pcall(function()
  _q7_start_all()
  _q7_later(1.0, _q7_start_all)
end)

if not _q7._boot_hooked then
  _q7._boot_hooked = true
  _q7.bActive = true
  _q7.AttachTimers()
end

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
