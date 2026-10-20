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
    pcall(function()
      local isLocal = false
      if self.Role and ENetRole and self.Role == ENetRole.ROLE_AutonomousProxy then
        isLocal = true
      end
      if not isLocal and self.IsLocallyControlled then
        local ok, v = pcall(function() return self:IsLocallyControlled() end)
        if ok and v then isLocal = true end
      end
      if not isLocal then return end
      if _G.__AegisStartScheduled == true then return end
      _G.__AegisStartScheduled = true
      self:AddGameTimer(1.0, false, function()
        pcall(function()
          if _G.__AegisStartAfterLicense then
            _G.__AegisStartAfterLicense()
          end
        end)
      end)
    end)
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

local VICTORY_DANCE_FX_MAP = {
  [12219601] = 22010089
}

local function ResolveEmoteResID(ItemID)
  local FxID = VICTORY_DANCE_FX_MAP[ItemID]
  if not FxID or FxID == ItemID then
    return ItemID
  end
  local model_util = require("client.common.model_util")
  local FxBPID = model_util.GetBPID(FxID)
  local ResID = ItemID
  if FxBPID and 0 < FxBPID and model_util.IsBattleItemHandleExist("Emote", FxBPID, false, false) then
    ResID = FxID
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase 11 ResolveEmoteResID ItemID:%s, FxID:%s, FxBPID:%s, ResID:%s", tostring(ItemID), tostring(FxID), tostring(FxBPID), tostring(ResID)))
  return ResID
end

function BRPlayerCharacterBase:GetEmoteHandlePath(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then
    return self.Super:GetEmoteHandlePath(ResID)
  end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then
    return ""
  end
  return model_util.GetPath("Emote", BPID, false, false) or ""
end

function BRPlayerCharacterBase:GetEmoteHandle(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then
    return self.Super:GetEmoteHandle(ResID)
  end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then
    return nil
  end
  local HandleClass = model_util.GetClass("Emote", BPID, false, false)
  if not HandleClass then
    return nil
  end
  local Handle = HandleClass()
  if not slua.isValid(Handle) then
    return nil
  end
  return Handle
end

local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")

local _slua = rawget(_G, "slua")

local function Chars(...)
  local n = select("#", ...)
  if n == 0 then return "" end
  local buf = {}
  for i = 1, n do
    buf[i] = string.char(select(i, ...))
  end
  return table.concat(buf)
end

local function Around(obj)
  if not obj then return false end
  if _slua and _slua.isValid then
    local ok, v = pcall(_slua.isValid, obj)
    if not ok or not v then return false end
  end
  return true
end

local function OnScreen(msg)
  local s = "" .. tostring(msg)
  pcall(function()
    local sh = import("ScriptHelperClient")
    if sh and sh.AddOnScreenDebugMessage then
      sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1, G=1, B=0, A=1}, {X=1.2, Y=1.2})
    end
  end)
  print(s)
end

local function GetSafeTime()
  local ok, t = pcall(function() return os.time(os.date("!*t")) end)
  if ok and t and t > 0 then return t end
  local ok2, t2 = pcall(os.time)
  if ok2 and t2 and t2 > 0 then return t2 end
  return 1728000000
end

_G.Aegis = _G.Aegis or {}
_G.Aegis.Up = _G.Aegis.Up or {}
local A = _G.Aegis

A.Config = A.Config or {
  Chams = false,
  WallVehicle = false,
  Antenna = false,
  MeterMarks = false,
  Ipad = false,
  IpadFov = 120,
  HighFps = false,
  Weapons = false
}

local tick = nil
pcall(function() tick = require("common.time_ticker") end)
local function Later(seconds, fn, allowSync)
  if tick and tick.AddTimerOnce then
    tick.AddTimerOnce(seconds, fn)
  elseif allowSync then
    fn()
  end
end

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
        if Around(pc) then
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
    local realRequire = require
    local poisoned = {"HiggsBosonComponent", "PlayerSecurityInfoSubsystem", "CoronaLabSubsystem", "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "ShootVerifySubSystemClient", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem", "OperationalStatsSubsystem"}
    _G.require = function(moduleName)
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
  print("[MOHSIN] ALL PROTECTION + BAN BYPASS 4.6 ACTIVE")
end

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
      end, true)
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

local function PlaceMark(id, pos, z, str, size, actor)
  local mark = nil
  pcall(function()
    local marks = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
    if marks and marks.ClientAddMapMark then
      mark = marks.ClientAddMapMark(id, pos, z, str, size, actor)
      if mark then A.Up.TrackedMarks[mark] = true end
    end
  end)
  return mark
end

local function LiftMark(mark)
  if not mark then return end
  pcall(function()
    local marks = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
    if marks then
      if marks.HideMapMark then marks.HideMapMark(mark) end
      if marks.RemoveMapMark then marks.RemoveMapMark(mark) end
    end
  end)
  A.Up.TrackedMarks[mark] = nil
end

local function EnemyId(enemy)
  if Around(enemy) then
    if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
    if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
  end
  return tostring(enemy)
end

local function MeshBag(enemy, stamp)
  local now = os.clock()
  if stamp.CachedMesh and stamp.CachedMeshAt and (now - stamp.CachedMeshAt < 3.0) then
    local keep = {}
    for _, m in ipairs(stamp.CachedMesh) do
      if Around(m) then table.insert(keep, m) end
    end
    stamp.CachedMesh = keep
    return keep
  end
  local meshes = {}
  if Around(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
  pcall(function()
    local skel = import("SkeletalMeshComponent")
    if skel and type(enemy.GetComponentsByClass) == "function" then
      local list = enemy:GetComponentsByClass(skel)
      if list then
        local n = type(list.Num) == "function" and list:Num() or #list
        for i = 1, n do
          local comp = type(list.Get) == "function" and list:Get(i - 1) or list[i]
          if Around(comp) and comp ~= enemy.Mesh then table.insert(meshes, comp) end
        end
      end
    end
  end)
  stamp.CachedMesh = meshes
  stamp.CachedMeshAt = now
  return meshes
end

local function ArmMeshes(enemy, stamp)
  pcall(function()
    if not A.Up.DyeingArmed then
      local lib = import("KismetSystemLibrary")
      local world = nil
      pcall(function()
        local GD = require("GameLua.GameCore.Data.GameplayData")
        local pc = GD.GetPlayerController()
        if slua.isValid(pc) then world = pc:GetWorld() end
      end)
      if not world then world = slua.getWorld() end
      if lib and world then
        lib.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        lib.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        lib.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        lib.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
        A.Up.DyeingArmed = true
      end
    end
    local meshes = MeshBag(enemy, stamp)
    pcall(function()
      local weapon = enemy:GetCurrentWeapon()
      if Around(weapon) and Around(weapon.Mesh) then table.insert(meshes, weapon.Mesh) end
    end)
    local bot = stamp.IsBot or false
    local sig = (bot and "B" or "P") .. ":" .. tostring(#meshes)
    if stamp.Sig == sig and stamp.Dyed then return end
    stamp.Sig = sig
    stamp.Dyed = true
    local L = import("LinearColor") or _G.FLinearColor
    local vis = L and L(0, 1, 0, 1) or {R=0, G=255, B=0, A=1}
    local occ = L and L(1, 0, 0, 1) or {R=255, G=0, B=0, A=1}
    for _, m in ipairs(meshes) do
      if Around(m) then
        pcall(function()
          if type(m.SetDrawDyeing) == "function" then
            m:SetDrawDyeing(true)
            m:SetDrawDyeingMode(1)
            m:SetVisibleDyeingColor(vis)
            m:SetOccludedDyeingColor(occ)
            m:SetDyeingColorFadeDistance(99999.0)
            m:SetDyeingColorMinMaxDistance(0.0, 99999.0)
            m:SetDrawHighlight(true)
            m:OverrideHighlightColor(vis)
            m:SetHighlightCanBeOccluded(false)
            m:SetDrawIdeaOutline(true)
            m:SetIdeaOutlineNew(true)
            m:SetIdeaOutlineOcclusionHighlight(true)
            m:OverrideIdeaOutlineColor(vis)
            m:SetIdeaOutlineOcclusionColor(occ)
            m:OverrideIdeaOutlineThickness(20.0)
            m:SetIdeaOverrideOutlineAndOcclusion(true)
            m:SetRenderCustomDepth(true)
            m:SetCustomDepthStencilValue(255)
          end
        end)
        pcall(function()
          m.LDMaxDrawDistance = -99999
          m.MaxDrawDistanceOffset = -99999
          m.CachedMaxDrawDistance = -99999
        end)
      end
    end
  end)
end

local function StripMeshes(enemy, stamp)
  pcall(function()
    if not stamp.Dyed then return end
    for _, m in ipairs(MeshBag(enemy, stamp)) do
      if Around(m) then
        pcall(function()
          if type(m.SetDrawDyeing) == "function" then
            m:SetDrawDyeing(false)
            m:SetDrawDyeingMode(0)
            m:SetDrawHighlight(false)
            m:SetDrawIdeaOutline(false)
            m:SetRenderCustomDepth(false)
          end
        end)
      end
    end
    stamp.Dyed = false
    stamp.Sig = ""
  end)
end

local function DrawAntenna(me, foe, pc)
  if not Around(me) or not Around(foe) then return end
  local hud = nil
  pcall(function()
    if Around(pc) then hud = pc.MyHUD end
  end)
  if not Around(hud) or type(hud.AddDebugText) ~= "function" then return end
  local black = { R = 0, G = 0, B = 0, A = 255 }
  local baseZ = 105
  local step = 120
  for i = 1, 20 do
    local z = baseZ + i * step
    local at = { X = 0, Y = 0, Z = z }
    hud:AddDebugText("|", foe, 0.06, at, at, black, true, false, true, nil, 0.4, true)
  end
  local tip = { X = 0, Y = 0, Z = baseZ + 20 * step + 60 }
  hud:AddDebugText("I", foe, 0.06, tip, tip, black, true, false, true, nil, 0.5, true)
end

local Vhc = {}
function Vhc.StripAll()
  pcall(function()
    if not A.Up.VhcDone then return end
    for id, mesh in pairs(A.Up.VhcDone) do
      if Around(mesh) then
        pcall(function()
          if type(mesh.SetDrawDyeing) == "function" then
            mesh:SetDrawDyeing(false)
            mesh:SetDrawDyeingMode(0)
            mesh:SetDrawHighlight(false)
            mesh:SetDrawIdeaOutline(false)
            mesh:SetRenderCustomDepth(false)
          end
        end)
        pcall(function()
          if type(mesh.GetMaterial) == "function" then
            local mat = mesh:GetMaterial(0)
            if Around(mat) and mat.GetBaseMaterial then
              local baseMat = mat:GetBaseMaterial()
              if Around(baseMat) then
                baseMat.bDisableDepthTest = false
                baseMat.BlendMode = 0
              end
            end
          end
        end)
      end
    end
    A.Up.VhcDone = {}
  end)
end

function Vhc.WallScan(pc)
  if not Around(pc) then return end
  pcall(function()
    local now = os.clock()
    if A.Up.VhcScanAt and (now - A.Up.VhcScanAt) < 1.0 then return end
    A.Up.VhcScanAt = now
    local player = pc:GetPlayerCharacterSafety()
    if not Around(player) then return end
    local base = import("STExtraVehicleBase")
    if not base then return end
    local list = nil
    pcall(function()
      if Game.GetActorsByClass then
        list = Game:GetActorsByClass(base)
      elseif Game.GetAllActorsOfClass then
        list = Game:GetAllActorsOfClass(base)
      end
    end)
    if not list then return end
    local n = type(list.Num) == "function" and list:Num() or #list
    for i = 0, n - 1 do
      local vehicle = type(list.Get) == "function" and list:Get(i) or list[i]
      if Around(vehicle) and type(vehicle.GetMesh) == "function" then
        local id = tostring(vehicle)
        if A.Up.VhcDone and A.Up.VhcDone[id] then goto continue end
        local dist = 0
        pcall(function()
          if type(player.GetDistanceTo) == "function" then dist = player:GetDistanceTo(vehicle) end
        end)
        if dist <= 200000 then
          local mesh = vehicle:GetMesh()
          if Around(mesh) and type(mesh.GetMaterial) == "function" then
            pcall(function()
              local mat = mesh:GetMaterial(0)
              if Around(mat) and mat.GetBaseMaterial then
                local baseMat = mat:GetBaseMaterial()
                if Around(baseMat) then
                  baseMat.bDisableDepthTest = true
                  baseMat.BlendMode = 2
                end
              end
            end)
            pcall(function()
              local L = import("LinearColor") or _G.FLinearColor
              local vis = L and L(1, 1, 0, 1) or {R=255, G=255, B=0, A=1}
              local occ = L and L(1, 1, 0, 1) or {R=255, G=255, B=0, A=1}
              if type(mesh.SetDrawDyeing) == "function" then
                mesh:SetDrawDyeing(true)
                mesh:SetDrawDyeingMode(1)
                mesh:SetVisibleDyeingColor(vis)
                mesh:SetOccludedDyeingColor(occ)
                mesh:SetDyeingColorFadeDistance(99999.0)
                mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
                mesh:SetDrawHighlight(true)
                mesh:OverrideHighlightColor(vis)
                mesh:SetHighlightCanBeOccluded(false)
                mesh:OverrideOutlineColor(vis)
                mesh:OverrideIdeaOutlineColor(vis)
                mesh:SetDrawIdeaOutline(true)
                mesh:SetIdeaOutlineNew(true)
                mesh:OverrideIdeaOutlineThickness(12.0)
                mesh:SetIdeaOverrideOutlineAndOcclusion(true)
                mesh:SetRenderCustomDepth(true)
                mesh:SetCustomDepthStencilValue(255)
              end
            end)
            A.Up.VhcDone = A.Up.VhcDone or {}
            A.Up.VhcDone[id] = mesh
            for k, v in pairs(A.Up.VhcDone) do
              if not Around(v) then A.Up.VhcDone[k] = nil end
            end
          end
        end
      end
      ::continue::
    end
  end)
end

local Weapons = {}
local WpnColors = {
  AR = {R=255, G=255, B=0, A=255},
  SMG = {R=0, G=255, B=255, A=255},
  Sniper = {R=255, G=0, B=0, A=255},
  Shotgun = {R=0, G=255, B=0, A=255},
  LMG = {R=255, G=255, B=255, A=255},
  Pistol = {R=200, G=200, B=200, A=255},
  Melee = {R=150, G=150, B=150, A=255},
  Special = {R=255, G=0, B=255, A=255},
  Scope = {R=0, G=0, B=255, A=255}
}
local WpnDb = {
  [101001] = {"AKM","AR"}, [101002] = {"M16A4","AR"}, [101003] = {"SCAR-L","AR"},
  [101004] = {"M416","AR"}, [101005] = {"Groza","AR"}, [101006] = {"AUG","AR"},
  [101007] = {"QBZ","AR"}, [101008] = {"M762","AR"}, [101009] = {"Mk47 Mutant","AR"},
  [101010] = {"G36C","AR"}, [101011] = {"AC-VAL","AR"}, [101012] = {"Honey Badger","AR"},
  [101100] = {"FAMAS","AR"}, [101101] = {"ASM Abakan AR","AR"}, [101102] = {"ACE32","AR"},
  [102001] = {"UZI","SMG"}, [102002] = {"UMP45","SMG"}, [102003] = {"Vector","SMG"},
  [102004] = {"Thompson SMG","SMG"}, [102005] = {"PP-19 Bizon","SMG"}, [102007] = {"MP5K","SMG"},
  [102008] = {"JS9","SMG"}, [102105] = {"P90","SMG"},
  [103001] = {"Kar98K","Sniper"}, [103002] = {"M24","Sniper"}, [103003] = {"AWM","Sniper"},
  [103004] = {"SKS","Sniper"}, [103005] = {"VSS","Sniper"}, [103006] = {"Mini14","Sniper"},
  [103007] = {"Mk14","Sniper"}, [103008] = {"Win94","Sniper"}, [103009] = {"SLR","Sniper"},
  [103010] = {"QBU","Sniper"}, [103011] = {"Mosin Nagant","Sniper"}, [103012] = {"AMR","Sniper"},
  [103100] = {"Mk12","Sniper"}, [103101] = {"TR-2A Air Gun","Sniper"}, [103102] = {"DSR","Sniper"},
  [103103] = {"Sniper Rifle","Sniper"}, [103104] = {"Sniper Rifle","Sniper"}, [103105] = {"SR","Sniper"},
  [104001] = {"S686","Shotgun"}, [104002] = {"S1897","Shotgun"}, [104003] = {"S12K","Shotgun"},
  [104004] = {"DBS","Shotgun"}, [104100] = {"SPAS-12","Shotgun"}, [104101] = {"M1014","Shotgun"},
  [104102] = {"NS2000","Shotgun"},
  [105001] = {"M249","LMG"}, [105002] = {"DP-28","LMG"}, [105003] = {"M134","LMG"},
  [105010] = {"MG3","LMG"},
  [106001] = {"P92","Pistol"}, [106002] = {"P1911","Pistol"}, [106003] = {"R1895","Pistol"},
  [106004] = {"P18C","Pistol"}, [106005] = {"R45","Pistol"}, [106006] = {"Sawed-off","Pistol"},
  [106008] = {"Skorpion","Pistol"}, [106010] = {"Desert Eagle","Pistol"},
  [106007] = {"Flare Gun","Pistol"}, [106009] = {"Flare Gun","Pistol"},
  [107001] = {"Crossbow","Special"}, [107002] = {"RPG-7","Special"}, [107003] = {"Riot Shield","Special"},
  [108001] = {"Machete","Melee"}, [108002] = {"Crowbar","Melee"}, [108003] = {"Sickle","Melee"},
  [108004] = {"Pan","Melee"}, [108005] = {"Dagger","Melee"},
  [203001] = {"Red Dot Sight","Scope"}, [203002] = {"Holographic Sight","Scope"}, [203003] = {"2x Scope","Scope"},
  [203004] = {"4x Scope","Scope"}, [203005] = {"8x Scope","Scope"}, [203014] = {"3x Scope","Scope"},
  [203015] = {"6x Scope","Scope"}
}

function Weapons.Scan(pc)
  if not Around(pc) then return end
  pcall(function()
    local now = os.clock()
    if A.Up.WpnScanAt and (now - A.Up.WpnScanAt) < 1.0 then return end
    A.Up.WpnScanAt = now
    A.Up.NearbyWeapons = {}
    local player = pc:GetPlayerCharacterSafety()
    if not Around(player) then return end
    local cls = import("PickUpWrapperActor") or import("STPickupWrapperActor")
    if not cls then return end
    local list = nil
    pcall(function()
      if Game.GetActorsByClass then
        list = Game:GetActorsByClass(cls)
      elseif Game.GetAllActorsOfClass then
        list = Game:GetAllActorsOfClass(cls)
      end
    end)
    if not list then return end
    local n = type(list.Num) == "function" and list:Num() or #list
    for i = 0, n - 1 do
      local item = type(list.Get) == "function" and list:Get(i) or list[i]
      if Around(item) then
        local dist = 0
        pcall(function()
          if type(player.GetDistanceTo) == "function" then dist = player:GetDistanceTo(item) end
        end)
        if dist <= 7000 then
          local itemId = nil
          pcall(function()
            if item.DefineID then itemId = item.DefineID.TypeSpecificID or item.DefineID end
          end)
          if not itemId and item.DefineId then itemId = item.DefineId end
          if WpnDb[itemId] then
            A.Up.NearbyWeapons[#A.Up.NearbyWeapons + 1] = { actor = item, id = itemId }
          end
        end
      end
    end
  end)
end

function Weapons.Draw(pc)
  if not Around(pc) then return end
  local hud = nil
  pcall(function() hud = pc.MyHUD end)
  if not Around(hud) or type(hud.AddDebugText) ~= "function" then return end
  local player = pc:GetPlayerCharacterSafety()
  if not Around(player) or not A.Up.NearbyWeapons then return end
  for _, entry in ipairs(A.Up.NearbyWeapons) do
    local item = entry.actor
    if Around(item) then
      local info = WpnDb[entry.id]
      if info then
        pcall(function()
          local distM = 0
          if type(player.GetDistanceTo) == "function" then distM = math.floor(player:GetDistanceTo(item) / 100) end
          local text = info[1] .. " [" .. tostring(distM) .. "m]"
          local color = WpnColors[info[2]]
          hud:AddDebugText(text, item, 0.06, {X=0, Y=0, Z=50}, {X=0, Y=0, Z=50}, color, true, false, true, nil, 0.8, true)
        end)
      end
    end
  end
end

local Gfx = {}

function Gfx.PushFps(target)
  pcall(function()
    local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
    local inst = db and db.GetGameInstance and db.GetGameInstance()
    if inst and type(inst.ExecuteCMD) == "function" then
      inst:ExecuteCMD("t.MaxFPS", tostring(target))
      inst:ExecuteCMD("r.FrameRateLimit", tostring(target))
    end
  end)
end

function Gfx.Unlock()
  if A.Up.GfxReady then return end
  pcall(function()
    local sc = require("client.logic.setting.setting_config")
    if sc then
      if sc.TpViewValue then sc.TpViewValue.max = 160 end
      if sc.FpViewValue then sc.FpViewValue.max = 160 end
    end
    local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
    if db and db.TpViewValue then db.TpViewValue.max = 160 end
  end)
  pcall(function()
    local lgs = require("client.slua.logic.setting.logic_setting_graphics")
    if lgs and lgs.SetFPS and not lgs._AegisFpsHooked then
      local prev = lgs.SetFPS
      lgs.SetFPS = function(gameInstance, FPSLevel)
        if prev then prev(gameInstance, FPSLevel) end
        if FPSLevel == 8 then Gfx.PushFps(165) end
      end
      lgs._AegisFpsHooked = true
    end
  end)
  pcall(function()
    local fps = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
    local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
    if fps and fps.__inner_impl then
      local impl = fps.__inner_impl
      impl.GetMaxFPSLevel = function() return 8, 8 end
      impl.InitRealSupportFPS = function()
        local tiers = {}
        for i = 1, 8 do tiers[i] = {true, true} end
        if db then pcall(function() db:UpdateUIData(db.RealSupportFPS, tiers, false) end) end
        return tiers
      end
      impl.UpdateSelectedFPSState = function(self, level)
        if not Around(self.UIRoot) then return end
        local names = {[2]=20, [3]=25, [4]=30, [5]=40, [6]=60, [7]=90, [8]=120}
        for lvl = 2, 8 do
          local node = self.UIRoot["NodeFps" .. (names[lvl] or 120)]
          if Around(node) then
            node:SetIsEnabled(true)
            pcall(function() node:SetRenderOpacity(1.0) end)
            local switcher = self.UIRoot["WidgetSwitcher_" .. lvl]
            if Around(switcher) then switcher:SetActiveWidgetIndex(lvl == level and 0 or 1) end
          end
        end
      end
    end
  end)
  pcall(function()
    local ft = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
    local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
    local kmath = import("KismetMathLibrary") or _G.KismetMathLibrary
    local L = import("LinearColor") or _G.FLinearColor
    if ft and ft.__inner_impl then
      local impl = ft.__inner_impl
      local floorFps, step = 90, 5
      local function Pin(v, lo, hi)
        if v < lo then return lo end
        if hi < v then return hi end
        return v
      end
      local function BlendColor(a, b, t)
        if not L then return nil end
        return L(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t, a.A + (b.A - a.A) * t)
      end
      impl.ShowOrHide = function(self)
        self:SelfHitTestInvisible()
        if self.InitFPSFTSwitch then self:InitFPSFTSwitch() end
      end
      impl.InitFPSFTSwitch = function(self)
        if not db then return end
        local on = db:GetUIData(db.FPSFineTuneSwitch)
        local root = self.UIRoot
        if root.Setting_Switch then root.Setting_Switch:SetSwitcherEnable2(on, true) end
        if root.CanvasPanel_8 then self:SetWidgetVisible(root.CanvasPanel_8, on) end
        if root.WidgetSwitcher_0 then root.WidgetSwitcher_0:SetActiveWidgetIndex(2) end
        if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
      end
      impl.InitFPSFTValue165 = function(self)
        if not db then return end
        local root = self.UIRoot
        local on = db:GetUIData(db.FPSFineTuneSwitch)
        local value = 165
        if on then
          value = db:GetUIData(db.FPSFineTuneNum) or 165
          root.Slider_screen3:SetLocked(false)
          if L then
            root.ProgressBar_screen3:SetFillColorAndOpacity(L(1, 1, 1, 1))
            root.Slider_screen3:SetSliderHandleColor(L(1, 1, 1, 1))
          end
        else
          root.Slider_screen3:SetLocked(true)
          if L then
            root.ProgressBar_screen3:SetFillColorAndOpacity(L(1.0, 0.625, 0.6, 1))
            root.Slider_screen3:SetSliderHandleColor(L(1.0, 0.625, 0.6, 1))
          end
        end
        local ratio = (value - floorFps) / (165 - floorFps)
        root.Veihclescreen3:SetText(tostring(value))
        root.Slider_screen3:SetValue(ratio)
        root.ProgressBar_screen3:SetPercent(ratio)
        if L then
          local a = L(1, 1, 1, 1)
          local mid = L(1, 0.54, 0.11, 1)
          local z = L(1, 0.23, 0.15, 1)
          root.Slider_screen3:SetSliderHandleColor(ratio < 0.4 and a or BlendColor(mid, z, (ratio - 0.4) / 0.6))
        end
      end
      impl.OnFPSFTValueChange3 = function(self, fpsNum)
        db:UpdateUIData(db.FPSFineTuneNum, fpsNum)
        if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
        if self:GetParentUI() then self:GetParentUI():SetDirty(true) end
        Gfx.PushFps(fpsNum)
      end
      impl.OnFPSFTSliderValueChange3 = function(self, value)
        if db:GetUIData(db.FPSFineTuneSwitch) and kmath then
          local fpsNum = kmath.FCeil(value * (165 - floorFps) / step) * step + floorFps
          self:OnFPSFTValueChange3(Pin(fpsNum, floorFps, 165))
        end
      end
      if impl.OnFPSFTAdd3 then impl.OnFPSFTAdd = impl.OnFPSFTAdd3 end
      if impl.OnFPSFTMinus3 then impl.OnFPSFTMinus = impl.OnFPSFTMinus3 end
      if impl.OnFPSFTAdd3 then impl.OnFPSFTAdd2 = impl.OnFPSFTAdd3 end
      if impl.OnFPSFTMinus3 then impl.OnFPSFTMinus2 = impl.OnFPSFTMinus3 end
      impl.OnFPSFTSliderValueChange = impl.OnFPSFTSliderValueChange3
      impl.OnFPSFTSliderValueChange2 = impl.OnFPSFTSliderValueChange3
    end
  end)
  A.Up.GfxReady = true
  OnScreen("165 FPS UNLOCKED")
end

local Menu = {}

function Menu.Wire()
  if A.Up.MenuWired then return end
  local loc = _G.LocUtil
  if not loc then
    local ok, m = pcall(require, "client.common.LocUtil")
    if ok and m then loc = m end
  end
  if not loc then
    local ok, m = pcall(require, "common.LocUtil")
    if ok and m then loc = m end
  end
  if loc and not loc._AegisLocHooked then
    local FakeText = {
      [999000] = "MOHSIN MENU",
      [999001] = "Visuals (ESP)"
    }
    for _, fn in ipairs({"GetLocalizeResStr", "GetText", "GetTextByID", "GetLocalText", "GetLocalizeStr"}) do
      if loc[fn] then
        local old = loc[fn]
        loc[fn] = function(id, ...)
          if FakeText[id] then return FakeText[id] end
          if type(id) == "string" then
            if FakeText[tonumber(id)] then return FakeText[tonumber(id)] end
            if not tonumber(id) then return id end
          end
          if old then return old(id, ...) end
          return ""
        end
      end
    end
    loc._AegisLocHooked = true
  end
  local okPd, pageDef = pcall(require, "client.logic.NewSetting.SettingPageDefine")
  local okCat, catalog = pcall(require, "client.logic.NewSetting.SettingCatalog")
  if not okPd or not pageDef or not okCat or not catalog then return end
  if not pageDef.ModMenu then
    local okAlias, alias = pcall(require, "client.slua.umg.NewSetting.Item.AliasMap")
    if not okAlias or not alias then return end
    local stack = {
      { Key = "ModMenu_Wallhack", UI = alias.Switcher, Text = "Wallhack",
        GetFunc = function() return A.Config.Chams end,
        SetFunc = function(c, v) A.Config.Chams = v return true end },
      { Key = "ModMenu_WallVehicle", UI = alias.Switcher, Text = "Wallhack Vichel",
        GetFunc = function() return A.Config.WallVehicle end,
        SetFunc = function(c, v) A.Config.WallVehicle = v return true end },
      { Key = "ModMenu_Antenna", UI = alias.Switcher, Text = "Antenna",
        GetFunc = function() return A.Config.Antenna end,
        SetFunc = function(c, v) A.Config.Antenna = v return true end },
      { Key = "ModMenu_Meter", UI = alias.Switcher, Text = "Distance/Meter/Name",
        GetFunc = function() return A.Config.MeterMarks end,
        SetFunc = function(c, v) A.Config.MeterMarks = v return true end },
      { Key = "ModMenu_165FPS", UI = alias.Switcher, Text = "165FPS",
        GetFunc = function() return A.Config.HighFps end,
        SetFunc = function(c, v) A.Config.HighFps = v; A.Up.GfxReady = false return true end },
      { Key = "ModMenu_IpadView", UI = alias.TitleSwitcher, Text = "Ipad View", ExpandIndex = 0,
        GetFunc = function() return A.Config.Ipad end,
        SetFunc = function(c, v) A.Config.Ipad = v return true end },
      { Key = "ModMenu_IpadFOV", UI = alias.Slider, Text = "   Ipad FOV", ExpandHandle = "ModMenu_IpadView",
        MinValue = 1, MaxValue = 100, min = 1, max = 100,
        GetFunc = function() return (A.Config.IpadFov or 120) - 90 end,
        SetFunc = function(c, v) A.Config.IpadFov = 90 + v return true end },
      { Key = "ModMenu_Weapons", UI = alias.Switcher, Text = "Weapons",
        GetFunc = function() return A.Config.Weapons end,
        SetFunc = function(c, v) A.Config.Weapons = v return true end }
    }
    pageDef.ModMenu = {
      Key = "ModMenu", Text = 999000, UIKey = "Setting_Page_Privacy",
      Category = { { Key = "Cat_ESP", Text = 999001, Stack = stack } }
    }
    for i = #catalog, 1, -1 do
      if type(catalog[i]) == "table" and catalog[i].Key == "ModMenu" then table.remove(catalog, i) end
    end
    table.insert(catalog, 1, pageDef.ModMenu)
  end

  if _G.UIManager and not _G.UIManager._AegisUiHooked then
    local manager = _G.UIManager
    local base = manager.ShowUI
    manager.ShowUI = function(config, ...)
      local args = {...}
      local n = select("#", ...)
      if config and config.keyName then
        local low = string.lower(config.keyName)
        if string.find(low, "setting_main") and not string.find(low, "custom") then
          local list = args[1]
          if type(list) == "table" then
            for i = #list, 1, -1 do
              local page = list[i]
              if type(page) == "table" and page.Key == "ModMenu" then
                table.remove(list, i)
              end
            end
            table.insert(list, 1, pageDef.ModMenu)
          end
        end
      end
      local tUnpack = table.unpack or unpack
      return base(config, tUnpack(args, 1, n))
    end
    manager._AegisUiHooked = true
  end
  A.Up.MenuWired = true
end

function Menu.Announce()
  if A.Up.Announced then return end
  pcall(function()
    Menu.Wire()
    OnScreen("Mod Menu Added!\nOpen Settings (Gear icon) -> MR FAHAD  MENU.")
    A.Up.Announced = true
  end)
end

local MOKING = {}

function MOKING.ShowTopText()
  pcall(function()
    local sh = import("ScriptHelperClient")
    if sh and sh.AddOnScreenDebugMessage then
      sh.AddOnScreenDebugMessage("OWNER +92 [ 03121808681 ]", -1, 1.0, {R = 0, G = 1, B = 1, A = 1}, {X = 0.85, Y = 0.85})
    end
  end)
end

-- Welcome popup function removed permanently at user request.

function MOKING.OnMatchEnter()
  if MOKING._matchEntered then return end
  MOKING._matchEntered = true
  MOKING.ShowTopText()
  -- MOKING.ShowWelcomePopup() removed — no popup will appear
end

A.Up.Pulse = (A.Up.Pulse or 0) + 1
local myPulse = A.Up.Pulse
A.Up.TrackedMarks = A.Up.TrackedMarks or {}
A.Up.Targets = A.Up.Targets or {}

local function Beat()
  if myPulse ~= A.Up.Pulse then return end

  pcall(function()
    if not A.Up.NativeReady and not A.Up.NativePriming then
      A.Up.NativePriming = true
      Esp.PrimeNativeMarks()
    end
    if A.Config.HighFps and not A.Up.GfxReady then Gfx.Unlock() end
  end)

  local okData, GameplayData = pcall(require, "GameLua.GameCore.Data.GameplayData")
  if not okData or not GameplayData then return end
  local pc = GameplayData.GetPlayerController()
  local me = nil
  if Around(pc) then me = pc:GetPlayerCharacterSafety() end

  if not Around(me) then
    for mark in pairs(A.Up.TrackedMarks) do LiftMark(mark) end
    for key, stamp in pairs(A.Up.Targets) do
      if stamp.enemy then StripMeshes(stamp.enemy, stamp) end
      A.Up.Targets[key] = nil
    end
    MOKING._matchEntered = false
    return
  end

  Menu.Announce()
  MOKING.OnMatchEnter()
  MOKING.ShowTopText()

  if A.Config.WallVehicle then Vhc.WallScan(pc) else Vhc.StripAll() end

  if A.Config.Weapons then
    Weapons.Scan(pc)
    Weapons.Draw(pc)
  else
    A.Up.NearbyWeapons = {}
  end

  pcall(function()
    local cam = me.ThirdPersonCameraComponent
    if Around(cam) and not me.bIsWeaponAiming then
      local target = 90
      if A.Config.Ipad then target = A.Config.IpadFov or 120 end
      if cam.FieldOfView ~= target then cam.FieldOfView = target end
    end
  end)

  local squad = {}
  pcall(function()
    if GameplayData.GetAllPlayerCharacters then
      squad = GameplayData.GetAllPlayerCharacters() or {}
    end
  end)
  local myTeam = me.TeamID or 0

  local aliveKeys = {}
  for _, foe in pairs(squad) do
    if Around(foe) and foe ~= me then aliveKeys[EnemyId(foe)] = true end
  end
  for key, stamp in pairs(A.Up.Targets) do
    if not aliveKeys[key] then
      if stamp.enemy then
        StripMeshes(stamp.enemy, stamp)
        if stamp.healthMark then LiftMark(stamp.healthMark); stamp.healthMark = nil end
        if stamp.meterMark then LiftMark(stamp.meterMark); stamp.meterMark = nil end
      end
      A.Up.Targets[key] = nil
    end
  end

  for _, foe in pairs(squad) do
    if Around(foe) and foe ~= me and foe.TeamID ~= myTeam then
      local gone = false
      pcall(function() if foe.HealthStatus ~= nil and foe.HealthStatus == 2 then gone = true end end)
      local key = EnemyId(foe)
      A.Up.Targets[key] = A.Up.Targets[key] or { enemy = foe, IsBot = false }
      local stamp = A.Up.Targets[key]
      stamp.enemy = foe
      pcall(function()
        local isBot = foe.bIsBot or foe.bIsAI or foe.bIsDummy or false
        if not isBot then
          local pk = foe.PlayerKey
          if type(pk) == "number" and pk > 2000000000 then isBot = true end
        end
        if not isBot and type(foe.GetPlayerName) == "function" then
          local nm = foe:GetPlayerName() or ""
          local low = nm:lower()
          if low:find("bot", 1, true) or low:find("ai_", 1, true) or low:find("dummy", 1, true) or low:find("机器人", 1, true) or low:find("npc", 1, true) then
            isBot = true
          end
        end
        if not isBot then
          pcall(function()
            local ctrl = foe:GetController()
            if ctrl and ctrl.IsA then
              local AICtrl = import("AIController")
              if AICtrl and ctrl:IsA(AICtrl) then isBot = true end
            end
          end)
        end
        stamp.IsBot = isBot
      end)
      if not gone then
        if A.Config.Chams then ArmMeshes(foe, stamp) else StripMeshes(foe, stamp) end
        if A.Config.Antenna then DrawAntenna(me, foe, pc) end
        if A.Config.MeterMarks then
          if not stamp.healthMark then stamp.healthMark = PlaceMark(1006, {X=0,Y=0,Z=0}, 0, "", 4, foe) end
          if not stamp.meterMark then stamp.meterMark = PlaceMark(9999, {X=0,Y=0,Z=0}, 0, "", 4, foe) end
        else
          if stamp.healthMark then LiftMark(stamp.healthMark); stamp.healthMark = nil end
          if stamp.meterMark then LiftMark(stamp.meterMark); stamp.meterMark = nil end
        end
      else
        StripMeshes(foe, stamp)
        if stamp.healthMark then LiftMark(stamp.healthMark); stamp.healthMark = nil end
        if stamp.meterMark then LiftMark(stamp.meterMark); stamp.meterMark = nil end
      end
    end
  end
end

local function Pulse()
  if myPulse ~= A.Up.Pulse then return end
  pcall(Beat)
  local interval = 0.012
  if A.Up.Heartbeat and A.Up.Heartbeat > 0 then interval = A.Up.Heartbeat / 1000 end
  Later(interval, Pulse)
end

_G.__AegisStartAfterLicense = function()
  pcall(function()
    local delay = math.random(150, 450) / 1000
    Later(delay, function()
      pcall(Shield.InstallAll)
    end, true)
  end)
end

pcall(function()
  Later(2.0, Pulse, true)
end)

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
