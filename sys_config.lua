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
    self:AddControlEvent(self, "OnPawnRespawnDelegate", self.OnRespawnRehideCheck, self)
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

function BRPlayerCharacterBase:OnRespawnRehideCheck()
  if not self:GetEnsure() then
    return
  end
  self:AddGameTimer(0.5, false, function()
    if not slua.isValid(self.Object) then
      return
    end
    if self:HasState(EPawnState.InPlane) then
      self:SetCharacterHideInGame(true, true, true, 1, ECharacterHideMovementAcive.Normal)
      print(bWriteLog and "BRPlayerCharacterBase:OnRespawnRehideCheck re-hide AI on plane, PlayerKey:", self.PlayerKey)
    end
  end)
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
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
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

-- ==========================================
-- Emote resolve (safe wrapped)
-- ==========================================
local VICTORY_DANCE_FX_MAP = {
  [12219601] = 22010089
}

local isFitVersion = false
pcall(function()
  local PRM = require("client.slua.config.ClientMacros.PublishRegionMacros")
  if PRM and type(PRM.IsFITVersion) == "function" then
    isFitVersion = PRM.IsFITVersion()
  end
end)

local ResolveEmoteResID = function(ItemID)
  local FxID = VICTORY_DANCE_FX_MAP[ItemID]
  if not FxID or FxID == ItemID then return ItemID end
  local model_util = nil
  pcall(function() model_util = require("client.common.model_util") end)
  if not model_util then return ItemID end
  local FxBPID = nil
  pcall(function() FxBPID = model_util.GetBPID(FxID) end)
  local ResID = ItemID
  if FxBPID and 0 < FxBPID and model_util.IsBattleItemHandleExist
     and model_util.IsBattleItemHandleExist("Emote", FxBPID, false, false) then
    ResID = FxID
  end
  if isFitVersion and ResID == 12219601 then return 12222069 end
  return ResID
end

function BRPlayerCharacterBase:GetEmoteHandlePath(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then return self.Super:GetEmoteHandlePath(ResID) end
  local model_util = nil
  pcall(function() model_util = require("client.common.model_util") end)
  if not model_util then return "" end
  local BPID = nil
  pcall(function() BPID = model_util.GetBPID(ResID) end)
  if not BPID or BPID <= 0 then return "" end
  local p = nil
  pcall(function() p = model_util.GetPath("Emote", BPID, false, false) end)
  return p or ""
end

function BRPlayerCharacterBase:GetEmoteHandle(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then return self.Super:GetEmoteHandle(ResID) end
  local model_util = nil
  pcall(function() model_util = require("client.common.model_util") end)
  if not model_util then return nil end
  local BPID = nil
  pcall(function() BPID = model_util.GetBPID(ResID) end)
  if not BPID or BPID <= 0 then return nil end
  local HandleClass = nil
  pcall(function() HandleClass = model_util.GetClass("Emote", BPID, false, false) end)
  if not HandleClass then return nil end
  local Handle = nil
  pcall(function() Handle = HandleClass() end)
  if not Handle or not slua.isValid(Handle) then return nil end
  return Handle
end

-- ==========================================
-- Silent HUD (stealth, no globals, no hooks)
-- ==========================================

-- Double-init guard, innocuous key
local _h_guard = nil
pcall(function()
  if _G._h then _h_guard = _G._h end
  if not _h_guard then
    _h_guard = { started = false }
    _G._h = _h_guard
  end
end)
if not _h_guard then _h_guard = { started = false } end

local _h_already = _h_guard.started == true
_h_guard.started = true

if not _h_already then

local FVector2D = _G.FVector2D or import("Vector2D")
local FLinearColor = _G.FLinearColor or import("LinearColor")
local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local SlateColor = nil
local GameplayStaticsESP = nil
local KismetSystemLibraryESP = nil
local HitResultClassESP = nil
pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") end)
pcall(function() SlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
pcall(function() GameplayStaticsESP = import("GameplayStatics") end)
pcall(function() KismetSystemLibraryESP = import("KismetSystemLibrary") end)
pcall(function() HitResultClassESP = import("HitResult") end)

local TraceStartPos = { X = 0, Y = 0, Z = 0 }
local CachedHitResult = nil
pcall(function()
  if HitResultClassESP then CachedHitResult = HitResultClassESP()
  else CachedHitResult = {} end
end)

local function V(obj)
  if obj == nil then return false end
  local ok, v = pcall(function() return slua.isValid(obj) end)
  return ok and v == true
end

local function V2(x, y)
  if FVector2D then return FVector2D(x, y) end
  return { X = x, Y = y }
end

local function MKC(r, g, b, a)
  if FLinearColor then return FLinearColor(r, g, b, a) end
  return { R = r, G = g, B = b, A = a }
end

local CFG = {
  MaxTracked = 15,
  ScreenMargin = 500,
  TopTextY = 6.0,
  SnapOriginY = 0.0,
  SnapThickness = 1.8,
  BoxMinWidth = 22,
  BoxMaxWidth = 320,
  BoxWidthFactor = 0.62,
  HeadExtra = 0.06,
  FootExtra = 0.02,
  SideBarWidth = 3.5,
  SideBgAlpha = 0.55,
  NameFontSize = 15,
  DistFontSize = 13,
  StateFontSize = 13,
  CounterFontSize = 17,
  CounterW = 300.0,
  CounterH = 28.0,
  DeadZone = 0.5,
  VisInterval = 0.1,
  SizeHyst = 2.0,
}

local C_WHITE  = MKC(1.0, 1.0, 1.0, 1.0)
local C_BLACK  = MKC(0.0, 0.0, 0.0, 1.0)
local C_GREEN  = MKC(0.12, 1.0, 0.25, 1.0)
local C_RED    = MKC(1.0, 0.15, 0.15, 1.0)

local TEAM_COLORS = {
  MKC(0.20, 0.65, 1.00, 1.00),
  MKC(1.00, 0.28, 0.28, 1.00),
  MKC(0.25, 0.90, 0.40, 1.00),
  MKC(1.00, 0.72, 0.18, 1.00),
  MKC(0.72, 0.40, 1.00, 1.00),
  MKC(0.10, 0.88, 0.85, 1.00),
  MKC(1.00, 0.42, 0.78, 1.00),
  MKC(0.72, 0.82, 0.92, 1.00),
}

local function TC(teamID, isBot, fallback)
  local n = tonumber(teamID)
  if n then n = math.abs(math.floor(n))
  else
    local s = tostring(fallback or "x")
    local h = 0
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 2147483647 end
    n = h
  end
  return TEAM_COLORS[(n % #TEAM_COLORS) + 1]
end

local function RND(v)
  if v ~= v then return 0 end
  return math.floor(v + 0.5)
end

local function Lerp(a, b, t) return a + (b - a) * t end

local function HC(pct)
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
  return MKC(r, g, b, 1.0)
end

local E = {}
E.Canvas = nil
E.Lines = {}
E.HealthBg = {}
E.HealthFill = {}
E.Infos = {}
E.Counter = nil
E.EnemyCache = {}
E.VisCache = {}
E.ScaleX = 1.0
E.ScaleY = 1.0
E.OffsetX = 0.0
E.OffsetY = 0.0
E.ViewW = 1920
E.ViewH = 1080
E.ScanInterval = 0.3
E.LightInterval = 0.016
E.TransformInterval = 1.0
E.LastScan = -999.0
E.LastTransform = -999.0
E.LastWorld = nil
E.bActive = false
E._GDP = nil

function E.GDP()
  if E._GDP then return E._GDP end
  local ok, G = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
  if ok and G then E._GDP = G return G end
  return nil
end

function E.PC()
  local pc = nil
  -- Method 1: GameplayData
  pcall(function()
    local G = E.GDP()
    if G then
      if type(G.GetPlayerController) == "function" then pc = G.GetPlayerController() end
      if not V(pc) and type(G.GetLocalPC) == "function" then pc = G.GetLocalPC() end
    end
  end)
  -- Method 2: slua_GameFrontendHUD
  if not V(pc) then
    pcall(function()
      if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
        pc = slua_GameFrontendHUD:GetPlayerController()
      end
    end)
  end
  -- Method 3: GameplayStatics
  if not V(pc) then
    pcall(function()
      local GS = GameplayStaticsESP
      local w = E.World()
      if GS and w and GS.GetPlayerController then
        pc = GS.GetPlayerController(w, 0)
      end
    end)
  end
  return V(pc) and pc or nil
end

function E.Local()
  local c = nil
  pcall(function()
    local G = E.GDP()
    if G then
      if G.GetPlayerCharacter then c = G.GetPlayerCharacter() end
      if not V(c) and G.GetLocalCharacter then c = G.GetLocalCharacter() end
    end
  end)
  if not V(c) then
    local pc = E.PC()
    pcall(function() if pc and pc.GetPawn then c = pc:GetPawn() end end)
  end
  return V(c) and c or nil
end

function E.AllChars()
  local out = {}
  local function merge(cs)
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
  pcall(function()
    if Game then
      if type(Game.GetAllPlayerPawns) == "function" then merge(Game:GetAllPlayerPawns()) end
      if type(Game.GetAllPawns) == "function" then merge(Game:GetAllPawns()) end
    end
  end)
  pcall(function()
    local G = E.GDP()
    if G and type(G.GetAllCharacters) == "function" then merge(G:GetAllCharacters()) end
  end)
  pcall(function()
    local GS = require("GameLua.GameCore.Data.CGameState")
    if GS and type(GS.GetAllCharacters) == "function" then merge(GS:GetAllCharacters()) end
  end)
  return out
end

function E.TeamID(c)
  if not V(c) then return nil end
  local id = nil
  pcall(function() if c.GetTeamID then id = c:GetTeamID() end end)
  if id == nil then pcall(function() id = c.TeamID end) end
  if id == nil then
    local ps = nil
    pcall(function()
      if c.GetPlayerStateSafety then ps = c:GetPlayerStateSafety()
      elseif c.GetPlayerState then ps = c:GetPlayerState() end
    end)
    if not V(ps) then pcall(function() ps = c.PlayerState end) end
    if V(ps) then
      pcall(function() if ps.GetTeamID then id = ps:GetTeamID() end end)
      if id == nil then pcall(function() id = ps.TeamID end) end
    end
  end
  return id
end

function E.Alive(c)
  if not V(c) then return false end
  local a = nil
  pcall(function() if c.IsAlive then a = c:IsAlive() end end)
  if type(a) == "boolean" then return a end
  local hp = nil
  pcall(function() hp = c.Health end)
  if type(hp) ~= "number" then pcall(function() hp = c.HP end) end
  if type(hp) == "number" then return hp > 0 end
  return true
end

function E.IsBot(c)
  if not V(c) then return false end
  local b = false
  pcall(function()
    if Game and Game.IsAI then b = Game:IsAI(c) end
    if not b and c then
      if c.bEnsure == true or c.bMEnsure == true then b = true
      elseif c.PlayerState and c.PlayerState.bPSEnsure == true then b = true
      elseif c.Controller then
        if c.Controller.IsMLAI == true or c.Controller.FakePlayerBornType == 1 then b = true end
      end
    end
  end)
  if not b then
    pcall(function() if c.bIsAI == true then b = true end end)
  end
  return b
end

function E.Key(c)
  local k = nil
  pcall(function() if c.GetPlayerKey then k = c:GetPlayerKey() end end)
  if k == nil then pcall(function() k = c.PlayerKey end) end
  return tostring(k or c)
end

function E.HPPct(c)
  if not V(c) then return 1.0 end
  local hp, mhp = nil, nil
  pcall(function() hp = c.Health end)
  if type(hp) ~= "number" then pcall(function() hp = c.HP end) end
  pcall(function() mhp = c.MaxHealth end)
  if type(mhp) ~= "number" then pcall(function() mhp = c.MaxHP end) end
  if type(hp) ~= "number" then return 1.0 end
  if type(mhp) ~= "number" or mhp <= 0 then mhp = 100 end
  local p = hp / mhp
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

function E.Name(c, isBot)
  if isBot then return "Bot" end
  local n = nil
  local function take(v) if not n then n = NN(v) end end
  pcall(function() if c.GetPlayerNameSafety then take(c:GetPlayerNameSafety()) end end)
  pcall(function() if not n and c.GetPlayerName then take(c:GetPlayerName()) end end)
  pcall(function() if not n then take(c.PlayerName) end end)
  pcall(function() if not n then take(c.NickName) end end)
  return n or "Player"
end

function E.BonePos(c, bn)
  if not V(c) or not bn then return nil end
  local p = nil
  pcall(function()
    if type(c.GetBonePos) == "function" then
      p = c:GetBonePos(bn, { X = 0, Y = 0, Z = 0 })
    end
    if not p or (p.X == 0 and p.Y == 0 and p.Z == 0) then
      if type(c.GetSocketLocation) == "function" then p = c:GetSocketLocation(bn) end
    end
    if (not p or (p.X == 0 and p.Y == 0 and p.Z == 0)) and V(c.Mesh) and c.Mesh.GetSocketLocation then
      local mp = c.Mesh:GetSocketLocation(bn)
      if mp and not (mp.X == 0 and mp.Y == 0 and mp.Z == 0) then p = mp end
    end
  end)
  return p
end

function E.CamLoc(pc)
  local l = nil
  pcall(function()
    if GameplayStaticsESP and GameplayStaticsESP.GetPlayerCameraManager then
      local m = GameplayStaticsESP.GetPlayerCameraManager(pc, 0)
      if V(m) and m.GetCameraLocation then l = m:GetCameraLocation() end
    end
  end)
  return l
end

function E.BoneVis(pc, cam, target, bp)
  if not V(pc) or not V(target) or not bp or not cam then return false end
  if not KismetSystemLibraryESP or not KismetSystemLibraryESP.LineTraceSingle then return true end
  local dx = bp.X - cam.X
  local dy = bp.Y - cam.Y
  local dz = bp.Z - cam.Z
  local d = math.sqrt(dx*dx + dy*dy + dz*dz)
  if d < 300 then return true end
  TraceStartPos.X = cam.X + (dx/d)*60
  TraceStartPos.Y = cam.Y + (dy/d)*60
  TraceStartPos.Z = cam.Z + (dz/d)*60
  local bVis = false
  pcall(function()
    local bHit = KismetSystemLibraryESP.LineTraceSingle(
      pc, TraceStartPos, bp, 0, false, nil, 0, CachedHitResult, true)
    if bHit then
      local ha = nil
      if CachedHitResult then
        if type(CachedHitResult.GetActor) == "function" then ha = CachedHitResult:GetActor()
        elseif CachedHitResult.Actor then ha = CachedHitResult.Actor end
      end
      if V(ha) and ha == target then bVis = true end
    else
      bVis = true
    end
  end)
  return bVis
end

function E.Visible(key, pc, cam, c)
  local now = E.Now()
  local cached = E.VisCache[key]
  if cached and (now - (cached.t or 0)) < (CFG.VisInterval or 0.1) then
    return cached.b
  end
  local bVis = false
  if V(c) and V(pc) and cam then
    for _, bn in ipairs({"head", "spine_03", "pelvis"}) do
      local bp = E.BonePos(c, bn)
      if bp and (bp.X ~= 0 or bp.Y ~= 0 or bp.Z ~= 0) then
        if E.BoneVis(pc, cam, c, bp) then bVis = true break end
      end
    end
  else
    bVis = true
  end
  E.VisCache[key] = { b = bVis, t = now }
  return bVis
end

function E.Pos(c)
  local l = nil
  if not V(c) then return nil end
  pcall(function()
    if c.K2_GetActorLocation then l = c:K2_GetActorLocation()
    elseif Game and Game.GetActorLocation then l = Game:GetActorLocation(c) end
  end)
  return l
end

function E.DistM(a, b)
  if not a or not b then return math.huge end
  local dx, dy, dz = a.X-b.X, a.Y-b.Y, a.Z-b.Z
  return math.sqrt(dx*dx + dy*dy + dz*dz) / 100.0
end

function E.VBounds(c)
  if not V(c) then return nil, nil end
  local ctr, hh = nil, nil
  local cap = nil
  pcall(function()
    if c.GetCapsuleComponent then cap = c:GetCapsuleComponent()
    elseif c.CapsuleComponent then cap = c.CapsuleComponent end
  end)
  if cap and V(cap) then
    pcall(function()
      if cap.K2_GetComponentLocation then ctr = cap:K2_GetComponentLocation()
      elseif cap.GetComponentLocation then ctr = cap:GetComponentLocation() end
      if cap.GetScaledCapsuleHalfHeight then hh = cap:GetScaledCapsuleHalfHeight()
      elseif cap.GetUnscaledCapsuleHalfHeight then hh = cap:GetUnscaledCapsuleHalfHeight()
      elseif cap.CapsuleHalfHeight then hh = cap.CapsuleHalfHeight end
    end)
  end
  if not ctr then pcall(function() if c.K2_GetActorLocation then ctr = c:K2_GetActorLocation() end end) end
  if not ctr then return nil, nil end
  if not hh or hh < 10 or hh > 200 then
    hh = 85
    pcall(function()
      if c.bIsCrouched then hh = 60 end
      if c.IsProne and c:IsProne() then hh = 25 end
    end)
  end
  return ctr, hh
end

function E.HeadFeet(c)
  local ctr, hh = E.VBounds(c)
  if not ctr or not hh then return nil, nil end
  return { X=ctr.X, Y=ctr.Y, Z=ctr.Z+hh }, { X=ctr.X, Y=ctr.Y, Z=ctr.Z-hh }
end

function E.Now()
  local t = nil
  pcall(function()
    local w = E.World()
    if GameplayStaticsESP and w and GameplayStaticsESP.GetRealTimeSeconds then
      t = GameplayStaticsESP.GetRealTimeSeconds(w)
    end
  end)
  if tonumber(t) then return tonumber(t) end
  pcall(function() if os and os.clock then t = os.clock() end end)
  return tonumber(t) or 0.0
end

function E.World()
  local w = nil
  pcall(function() if slua and slua.getWorld then w = slua.getWorld() end end)
  return w
end

function E.Canvas()
  if V(E.Canvas) then return E.Canvas end
  local root = nil
  pcall(function()
    local T = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
    if T and T.GetMainControlBaseUI then root = T.GetMainControlBaseUI() end
  end)
  if not V(root) then return nil end
  local c = nil
  pcall(function()
    if V(root.CanvasPanel_0) then c = root.CanvasPanel_0
    elseif V(root.CanvasPanel_42) then c = root.CanvasPanel_42 end
  end)
  if V(c) then E.Canvas = c return c end
  return nil
end

function E.UpdateTransform(pc)
  local cnv = E.Canvas()
  if not V(cnv) then return false end
  local ok = false
  pcall(function()
    if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
      local geo = cnv:GetCachedGeometry()
      if geo then
        local p0 = SlateBlueprintLibrary.AbsoluteToLocal(geo, V2(0,0))
        local p1 = SlateBlueprintLibrary.AbsoluteToLocal(geo, V2(100,100))
        if p0 and p1 and tonumber(p0.X) and tonumber(p1.X) and p1.X ~= p0.X and p1.Y ~= p0.Y then
          E.ScaleX = (p1.X-p0.X)/100.0
          E.ScaleY = (p1.Y-p0.Y)/100.0
          E.OffsetX = p0.X
          E.OffsetY = p0.Y
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
    E.ScaleX = 1.0/s
    E.ScaleY = 1.0/s
    E.OffsetX = 0.0
    E.OffsetY = 0.0
  end
  return true
end

function E.Viewport(pc)
  local w, h = 1920.0, 1080.0
  pcall(function()
    if pc and pc.GetViewportSize then
      local v = V2(0,0)
      pc:GetViewportSize(v)
      if v and tonumber(v.X) and v.X > 200 then w, h = v.X, v.Y end
    end
  end)
  return w, h
end

function E.Project(pc, wl)
  if not pc or not wl then return nil end
  local pix = V2(0,0)
  local ok = false
  pcall(function()
    local r = pc:ProjectWorldLocationToScreen(wl, pix, true)
    ok = (r == true or r == 1 or (pix and (pix.X ~= 0 or pix.Y ~= 0)))
  end)
  if not ok then return nil end
  return V2(pix.X * (E.ScaleX or 1.0) + (E.OffsetX or 0.0),
            pix.Y * (E.ScaleY or 1.0) + (E.OffsetY or 0.0)), pix
end

function E.SetFont(w, sz)
  if not V(w) then return end
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
    if w.SetShadowOffset then w:SetShadowOffset(V2(1.0,1.0)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(C_BLACK) end
  end)
end

function E.SetColor(w, c)
  if not V(w) then return end
  pcall(function()
    if SlateColor then w:SetColorAndOpacity(SlateColor(c))
    else w:SetColorAndOpacity(c) end
  end)
end

function E.NewLine(c, z)
  local cnv = E.Canvas()
  if not V(cnv) then return nil end
  local b = nil
  pcall(function() b = CGame:NewObjectFromPath("/Script/UMG.Border", cnv) end)
  if not V(b) then return nil end
  pcall(function()
    b:SetBrushColor(c)
    b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    b:SetRenderTransformPivot(V2(0.0,0.5))
  end)
  local sl = nil
  pcall(function() sl = cnv:AddChildToCanvas(b) end)
  if not sl then
    pcall(function() b:RemoveFromParent() end)
    return nil
  end
  pcall(function() sl:SetAutoSize(false) sl:SetZOrder(z or 30) end)
  return { W = b, S = sl }
end

function E.Line(d, x1, y1, x2, y2, th)
  if not d or not V(d.W) or not d.S then return false end
  if x1 ~= x1 or y1 ~= y1 or x2 ~= x2 or y2 ~= y2 then return false end
  x1, y1, x2, y2 = RND(x1), RND(y1), RND(x2), RND(y2)
  local dz = CFG.DeadZone or 0.5
  if d.x1 and d.th == th then
    if math.abs((d.x1 or 0)-x1) < dz and math.abs((d.y1 or 0)-y1) < dz
    and math.abs((d.x2 or 0)-x2) < dz and math.abs((d.y2 or 0)-y2) < dz then
      if d.hid ~= true then return true end
    end
  end
  local dx, dy = x2-x1, y2-y1
  local len = math.sqrt(dx*dx + dy*dy)
  if len < 1 then E.Hide(d) return false end
  local angle = ((math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)) * 180.0 / math.pi
  angle = math.floor(angle * 10 + 0.5) / 10
  len = RND(len)
  if d.x1 == x1 and d.y1 == y1 and d.x2 == x2 and d.y2 == y2 and d.th == th then
    if d.hid == true then
      pcall(function() d.W:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
      d.hid = false
    end
    return true
  end
  local ok = pcall(function()
    d.S:SetPosition(V2(x1, y1 - th*0.5))
    d.S:SetSize(V2(len, th))
    d.W:SetRenderAngle(angle)
    d.W:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if ok then
    d.x1, d.y1, d.x2, d.y2, d.th = x1, y1, x2, y2, th
    d.hid = false
  end
  return true
end

function E.Hide(d)
  if d and V(d.W) and d.hid ~= true then
    pcall(function() d.W:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    d.hid = true
    d.x1, d.y1, d.x2, d.y2, d.th = nil, nil, nil, nil, nil
  end
end

function E.SetBrush(d, c, ck)
  if not d or not V(d.W) then return end
  if ck and d.ck == ck then return end
  pcall(function() d.W:SetBrushColor(c) end)
  if ck then d.ck = ck end
end

function E.Destroy(d)
  if not d then return end
  local w = d.W or d.C
  if V(w) then
    pcall(function() w:RemoveFromParent() end)
    pcall(function() w:ConditionalBeginDestroy() end)
  end
end

function E.CreateCounter()
  local cnv = E.Canvas()
  if not V(cnv) then return nil end
  local cont = nil
  pcall(function() cont = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", cnv) end)
  if not V(cont) then return nil end
  local txt = nil
  pcall(function() txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", cont) end)
  if not V(txt) then E.Destroy({ W = cont }) return nil end
  pcall(function()
    txt:SetText("Players: 0 | Bots: 0")
    txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if txt.SetJustification then txt:SetJustification(1) end
  end)
  E.SetColor(txt, C_WHITE)
  E.SetFont(txt, CFG.CounterFontSize)
  local ts, ms = nil, nil
  pcall(function() ts = cont:AddChildToCanvas(txt) end)
  pcall(function() ms = cnv:AddChildToCanvas(cont) end)
  if not ts or not ms then E.Destroy({ W = cont }) return nil end
  local W, H = CFG.CounterW, CFG.CounterH
  pcall(function()
    ts:SetAutoSize(true)
    ts:SetAlignment(V2(0.5,0.5))
    ts:SetPosition(V2(W*0.5, H*0.5))
    ts:SetZOrder(5)
    ms:SetAutoSize(false)
    ms:SetAlignment(V2(0.5,0.0))
    ms:SetSize(V2(W,H))
    ms:SetZOrder(60)
  end)
  return { C = cont, T = txt, S = ms, W = W, H = H }
end

function E.CenterX(viewW)
  local cw = nil
  pcall(function()
    local cnv = E.Canvas()
    if V(cnv) then
      local geo = cnv:GetCachedGeometry()
      if geo and geo.GetLocalSize then
        local s = geo:GetLocalSize()
        if s and tonumber(s.X) and s.X > 1 then cw = tonumber(s.X) end
      end
    end
  end)
  if tonumber(cw) and cw > 1 then return cw * 0.5 end
  return (viewW * 0.5) * (E.ScaleX or 1.0) + (E.OffsetX or 0.0)
end

function E.UpdateCounter(np, nb, viewW)
  local d = E.Counter
  if not d or not V(d.C) then
    E.Destroy(d)
    d = E.CreateCounter()
    E.Counter = d
  end
  if not d then return nil end
  local lab = string.format("Players: %d | Bots: %d", np or 0, nb or 0)
  pcall(function()
    if d.L ~= lab then d.T:SetText(lab) d.L = lab end
  end)
  local cx = E.CenterX(viewW)
  if cx then
    cx = RND(cx)
    if d.px == nil or math.abs(d.px - cx) >= 1.0 then
      d.px = cx
      pcall(function()
        d.S:SetPosition(V2(cx, CFG.TopTextY))
        d.C:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    else
      pcall(function()
        d.C:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    end
  end
  return V2(cx, CFG.SnapOriginY)
end

function E.CreateInfo()
  local cnv = E.Canvas()
  if not V(cnv) then return nil end
  local cont, tb, tn, td, tst = nil, nil, nil, nil, nil
  pcall(function() cont = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", cnv) end)
  if not V(cont) then return nil end
  pcall(function() tb = CGame:NewObjectFromPath("/Script/UMG.Border", cont) end)
  pcall(function() tn = CGame:NewObjectFromPath("/Script/UMG.TextBlock", cont) end)
  pcall(function() td = CGame:NewObjectFromPath("/Script/UMG.TextBlock", cont) end)
  pcall(function() tst = CGame:NewObjectFromPath("/Script/UMG.TextBlock", cont) end)
  if not V(tb) or not V(tn) or not V(td) or not V(tst) then
    E.Destroy({ W = cont })
    return nil
  end
  pcall(function()
    tb:SetBrushColor(TEAM_COLORS[1])
    tb:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tn:SetText("Player")
    td:SetText("0m")
    tst:SetText("Open")
    tn:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    td:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tst:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if tn.SetJustification then tn:SetJustification(1) end
    if td.SetJustification then td:SetJustification(1) end
    if tst.SetJustification then tst:SetJustification(1) end
  end)
  E.SetColor(tn, C_WHITE)
  E.SetColor(td, C_WHITE)
  E.SetColor(tst, C_GREEN)
  E.SetFont(tn, CFG.NameFontSize)
  E.SetFont(td, CFG.DistFontSize)
  E.SetFont(tst, CFG.StateFontSize)
  local bs, ns, s2, s3, ms = nil, nil, nil, nil, nil
  pcall(function() bs = cont:AddChildToCanvas(tb) end)
  pcall(function() ns = cont:AddChildToCanvas(tn) end)
  pcall(function() s2 = cont:AddChildToCanvas(td) end)
  pcall(function() s3 = cont:AddChildToCanvas(tst) end)
  pcall(function() ms = cnv:AddChildToCanvas(cont) end)
  if not bs or not ns or not s2 or not s3 or not ms then
    E.Destroy({ W = cont })
    return nil
  end
  pcall(function()
    bs:SetAutoSize(false) bs:SetSize(V2(120.0,22.0)) bs:SetAlignment(V2(0.5,0.5)) bs:SetZOrder(34)
    ns:SetAutoSize(false) ns:SetSize(V2(120.0,22.0)) ns:SetAlignment(V2(0.5,0.5)) ns:SetZOrder(36)
    s2:SetAutoSize(true) s2:SetAlignment(V2(0.5,0.5)) s2:SetZOrder(36)
    s3:SetAutoSize(true) s3:SetAlignment(V2(0.5,0.5)) s3:SetZOrder(36)
    ms:SetAutoSize(false) ms:SetZOrder(35)
  end)
  return { C=cont, TB=tb, N=tn, D=td, S=tst, S0=bs, S1=ns, S2=s2, S3=s3, Slot=ms }
end

function E.UpdateInfo(key, c, isBot, tid, dm, bVis, hx, hy, cx, B, L, R)
  local d = E.Infos[key]
  if not d or not V(d.C) then
    E.Destroy(d)
    d = E.CreateInfo()
    E.Infos[key] = d
  end
  if not d then return end
  local name = d.CN
  if not name then
    name = E.Name(c, isBot)
    d.CN = name
  end
  if isBot then name = "Bot" d.CN = "Bot" end
  local dl = string.format("%dm", math.max(0, math.floor((tonumber(dm) or 0) + 0.5)))
  local st = bVis and "Open" or "Close"
  local tc = TC(tid, isBot, key)
  pcall(function()
    if d.LN ~= name then d.N:SetText(name) d.LN = name end
    if d.LD ~= dl then d.D:SetText(dl) d.LD = dl end
    if d.LS ~= st then d.S:SetText(st) d.LS = st end
    if d.LT ~= tostring(tid)..":"..tostring(isBot) then
      d.TB:SetBrushColor(tc)
      d.LT = tostring(tid)..":"..tostring(isBot)
    end
    if bVis then E.SetColor(d.S, C_GREEN) else E.SetColor(d.S, C_RED) end
  end)
  local bw = 100.0
  local bh = 22.0
  local bx = RND(hx)
  local by = RND(hy - 18.0)
  pcall(function()
    d.Slot:SetPosition(V2(bx, by))
    d.Slot:SetSize(V2(bw, 70.0))
    d.S0:SetPosition(V2(0.0, 0.0))
    d.S0:SetSize(V2(bw, bh))
    d.S1:SetPosition(V2(0.0, 0.0))
    d.S1:SetSize(V2(bw, bh))
    d.S2:SetPosition(V2(bw*0.5, bh+12.0))
    d.S3:SetPosition(V2(bw*0.5, bh+30.0))
    d.C:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
end

function E.HBg(key)
  local d = E.HealthBg[key]
  if d and V(d.W) then return d end
  d = E.NewLine(MKC(0.0,0.0,0.0,CFG.SideBgAlpha), 31)
  E.HealthBg[key] = d
  return d
end

function E.HFill(key)
  local d = E.HealthFill[key]
  if d and V(d.W) then return d end
  d = E.NewLine(C_GREEN, 32)
  E.HealthFill[key] = d
  return d
end

function E.HBar(key, pct, x, y, w)
  local bg = E.HBg(key)
  local fl = E.HFill(key)
  if not bg or not fl then return end
  local th = CFG.SideBarWidth
  w = math.max(1, tonumber(w) or 1)
  E.Line(bg, x, y, x+w, y, th)
  pct = tonumber(pct) or 1.0
  if pct < 0 then pct = 0 end
  if pct > 1 then pct = 1 end
  local bk
  if pct >= 0.7 then bk = "g" .. math.floor(pct*20+0.5)
  elseif pct >= 0.4 then bk = "y" .. math.floor(pct*20+0.5)
  else bk = "r" .. math.floor(pct*20+0.5) end
  E.SetBrush(fl, HC(pct), bk)
  local fw = w * pct
  if fw < 1 then E.Hide(fl) return end
  E.Line(fl, x, y, x+fw, y, th)
end

function E.Snap(key)
  local d = E.Lines[key]
  if d and V(d.W) then return d end
  d = E.NewLine(C_GREEN, 30)
  E.Lines[key] = d
  return d
end

function E.HideTarget(key)
  E.Hide(E.HealthBg[key])
  E.Hide(E.HealthFill[key])
  E.Hide(E.Lines[key])
  local inf = E.Infos[key]
  if inf and V(inf.C) then
    pcall(function() inf.C:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
  end
end

function E.ReleaseTarget(key)
  E.Destroy(E.HealthBg[key]) E.HealthBg[key] = nil
  E.Destroy(E.HealthFill[key]) E.HealthFill[key] = nil
  E.Destroy(E.Lines[key]) E.Lines[key] = nil
  E.Destroy(E.Infos[key]) E.Infos[key] = nil
  E.VisCache[key] = nil
end

function E.Reset()
  for _, d in pairs(E.Lines) do E.Destroy(d) end
  for _, d in pairs(E.HealthBg) do E.Destroy(d) end
  for _, d in pairs(E.HealthFill) do E.Destroy(d) end
  for _, d in pairs(E.Infos) do E.Destroy(d) end
  E.Lines = {} E.HealthBg = {} E.HealthFill = {} E.Infos = {} E.VisCache = {}
  if E.Counter then E.Destroy(E.Counter) end
  E.Counter = nil
  E.Canvas = nil
  E.EnemyCache = {}
end

function E.Scan()
  local pc = E.PC()
  local me = E.Local()
  if not pc or not me then E.EnemyCache = {} return pc, 0, 0 end
  local myLoc = E.Pos(me)
  if not myLoc then E.EnemyCache = {} return pc, 0, 0 end
  local myTeam = E.TeamID(me)
  local list = {}
  local nR, nB = 0, 0
  local pawns = E.AllChars()
  local seen = {}
  for _, ch in pairs(pawns) do
    if V(ch) and ch ~= me and E.Alive(ch) then
      local key = E.Key(ch)
      if not seen[key] then
        local team = E.TeamID(ch)
        if not (myTeam ~= nil and team ~= nil and tostring(team) == tostring(myTeam)) then
          local loc = E.Pos(ch)
          local dm = E.DistM(myLoc, loc)
          seen[key] = true
          local isBot = E.IsBot(ch)
          if isBot then nB = nB + 1 else nR = nR + 1 end
          list[#list+1] = { C=ch, K=key, B=isBot, T=team, D=dm }
        end
      end
    end
  end
  table.sort(list, function(a,b) return (a.D or 99999) < (b.D or 99999) end)
  local trim = {}
  for i, it in ipairs(list) do
    if i > CFG.MaxTracked then break end
    trim[#trim+1] = it
  end
  E.EnemyCache = trim
  return pc, nR, nB
end

function E.Update()
  local world = E.World()
  if world ~= E.LastWorld then
    E.Reset()
    E.LastWorld = world
    E.LastScan = -999.0
    E.LastTransform = -999.0
  end
  local cnv = E.Canvas()
  if not cnv then return end
  local now = E.Now()
  local pc = E.PC()
  if (now - E.LastScan) >= E.ScanInterval then
    local r, b
    pc, r, b = E.Scan()
    E.LastScan = now
    E.RC, E.BC = r or 0, b or 0
  end
  pc = pc or E.PC()
  if not pc then return end
  if (now - (E.LastTransform or -999.0)) >= E.TransformInterval then
    E.UpdateTransform(pc)
    E.LastTransform = now
  end
  local vw, vh = E.Viewport(pc)
  local hyst = CFG.SizeHyst
  if math.abs(vw - (E.ViewW or 0)) > hyst or math.abs(vh - (E.ViewH or 0)) > hyst then
    E.ViewW, E.ViewH = vw, vh
  else
    vw, vh = E.ViewW, E.ViewH
  end
  local origin = E.UpdateCounter(E.RC or 0, E.BC or 0, vw)
  if not origin then return end
  local cam = E.CamLoc(pc)
  local active = {}
  for _, it in ipairs(E.EnemyCache) do
    local c = it.C
    local key = it.K
    if V(c) and E.Alive(c) then
      local head, feet = E.HeadFeet(c)
      if head and feet then
        local hS, hp = E.Project(pc, head)
        local fS, fp = E.Project(pc, feet)
        if hS and fS and hp and fp then
          local m = CFG.ScreenMargin
          local on = hp.X > -m and hp.X < vw+m and hp.Y > -m and hp.Y < vh+m
                     and fp.X > -m and fp.X < vw+m and fp.Y > -m and fp.Y < vh+m
          if on then
            local H = fS.Y - hS.Y
            if H >= 1 and H <= vh*1.5 then
              active[key] = true
              local W = H * CFG.BoxWidthFactor
              W = math.max(CFG.BoxMinWidth, math.min(CFG.BoxMaxWidth, W))
              local cx = (hS.X + fS.X) * 0.5
              local L = cx - W*0.5
              local R = cx + W*0.5
              local pct = E.HPPct(c)
              local hbY = hS.Y + 8.0
              E.HBar(key, pct, L, hbY, R-L)
              E.Line(E.Snap(key), origin.X, origin.Y, hS.X, hS.Y, CFG.SnapThickness)
              local bVis = E.Visible(key, pc, cam, c)
              E.UpdateInfo(key, c, it.B, it.T, it.D, bVis, hS.X, hS.Y, cx, fS.Y, L, R)
            else
              E.HideTarget(key)
            end
          else
            E.HideTarget(key)
          end
        else
          E.HideTarget(key)
        end
      else
        E.HideTarget(key)
      end
    end
  end
  local seen = {}
  for _, it in ipairs(E.EnemyCache) do seen[it.K] = true end
  for k in pairs(E.Lines) do if not active[k] then E.HideTarget(k) end end
  for k in pairs(E.HealthBg) do if not active[k] and not seen[k] then E.ReleaseTarget(k) end end
end

function E.Tick()
  pcall(E.Update)
end

function E.Attach()
  pcall(function()
    local pc = E.PC()
    if V(pc) and type(pc.AddGameTimer) == "function" then
      if E._TPC == pc and E._THooked then return end
      E._TPC = pc
      E._THooked = true
      local interval = 0.016 + math.random() * 0.002
      pc:AddGameTimer(interval, true, function()
        if E.bActive then pcall(E.Tick) end
      end)
    else
      pcall(function()
        require("timer").SetGameTimer(1.0, false, function()
          E._THooked = false
          E.Attach()
        end)
      end)
    end
    pcall(function() require("timer").SetGameTimer(5.0, false, function() E.Attach() end) end)
  end)
end

function E.Start()
  if E.bActive then return end
  E.bActive = true
  pcall(E.Update)
  E.Attach()
end

local _startedPC = nil
local function E_StartAll()
  pcall(function()
    local pc = nil
    if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
      pc = slua_GameFrontendHUD:GetPlayerController()
    end
    if not V(pc) then pc = E.PC() end
    if V(pc) then
      if pc ~= _startedPC then
        _startedPC = pc
        E._THooked = false
        E._TPC = nil
        E.Start()
      else
        E.Attach()
      end
    end
  end)
end

pcall(function()
  E_StartAll()
  local tk = nil
  pcall(function() tk = require("common.time_ticker") end)
  if tk and tk.AddTimerOnce then
    pcall(function() tk.AddTimerOnce(1.0, E_StartAll) end)
  else
    pcall(function() require("timer").SetGameTimer(1.0, false, E_StartAll) end)
  end
end)

E.bActive = true
E.Attach()

end -- if not _h_already

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
