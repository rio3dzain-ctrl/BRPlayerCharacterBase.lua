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
    return
  end

  -- FIX: When entering or leaving a transformation state (Bat / Vampire /
  -- Zombie / SpecialSuit / AttachToOther) the pawn may lose possession or
  -- get stuck in a non-walking movement mode. Re-establish possession and
  -- restore a sane movement mode so input works again.
  if self.Role ~= ENetRole.ROLE_AutonomousProxy then return end

  local uPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(uPlayerController) then return end

  local bRepossess = false
  pcall(function()
    if uPlayerController.GetPawn then
      local cur = uPlayerController:GetPawn()
      if cur ~= self.Object then bRepossess = true end
    end
  end)
  if bRepossess then
    pcall(function() uPlayerController:Possess(self.Object) end)
    print(bWriteLog and "BRPlayerCharacterBase:OnPawnStateChange - repossessed pawn after state change")
  end

  if not self:HasState(EPawnState.SpecialSuit) and slua.isValid(self.STCharacterMovement) then
    pcall(function()
      local mode = self.STCharacterMovement.MovementMode
      if mode ~= EMovementMode.MOVE_Walking
        and mode ~= EMovementMode.MOVE_Falling
        and mode ~= EMovementMode.MOVE_Swimming
        and mode ~= EMovementMode.MOVE_Flying then
        self.STCharacterMovement:SetMovementMode(EMovementMode.MOVE_Walking, 0)
      end
    end)
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

  -- FIX: Do NOT clear base while a SpecialSuit transformation is active.
  -- Bat / Vampire / Zombie forms use Swimming as an internal transition mode
  -- and detaching the base kills their input pipeline.
  if Game:IsValid(self.STCharacterMovement)
    and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming
    and self:CheckBaseIsMoveable()
    and not self:HasState(EPawnState.SpecialSuit) then
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

  -- FIX: forward to the base class. The base is responsible for rebinding
  -- input, retargeting the camera, and setting up the new form's movement
  -- component. Skipping it leaves the pawn without an input pipeline after
  -- a Bat / Vampire / Zombie transform.
  local superFn = BRPlayerCharacterBase.__super and BRPlayerCharacterBase.__super.DoModChangeToBT
  if type(superFn) == "function" then
    superFn(self)
  elseif self.Super and type(self.Super.DoModChangeToBT) == "function" then
    pcall(function() self.Super:DoModChangeToBT() end)
  end

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

-- =======================================================================
--  ESP / PlayerMapMarker  —  CRASH-HARDENED, THROTTLED
-- =======================================================================
local ESP_Enabled = true

local FVector2D = _G.FVector2D or import("Vector2D")
local FLinearColor = _G.FLinearColor or import("LinearColor")
local SlateBlueprintLibrary, WidgetLayoutLibrary, SlateColor, GameplayStaticsESP
pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary  = import("WidgetLayoutLibrary")  end)
pcall(function() SlateColor           = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
pcall(function() GameplayStaticsESP   = import("GameplayStatics") end)
local KismetSystemLibraryESP, HitResultClassESP
pcall(function() KismetSystemLibraryESP = import("KismetSystemLibrary") end)
pcall(function() HitResultClassESP     = import("HitResult") end)
local TraceStartPos = { X = 0, Y = 0, Z = 0 }
local CachedHitResult = nil
pcall(function()
  CachedHitResult = HitResultClassESP and HitResultClassESP() or {}
end)

local _sluaIsValid = nil
pcall(function() if slua and slua.isValid then _sluaIsValid = slua.isValid end end)

local function ESPValid(obj)
  if obj == nil then return false end
  if not _sluaIsValid then return false end
  local ok, v = pcall(_sluaIsValid, obj)
  if not ok or v ~= true then return false end
  local ok2, v2 = pcall(function() return Game:IsValid(obj) end)
  if ok2 then return v2 ~= false end
  return true
end

local function ESPV2(x, y) if FVector2D then return FVector2D(x, y) end return { X = x, Y = y } end
local function ESPMKC(r, g, b, a) if FLinearColor then return FLinearColor(r, g, b, a) end return { R=r,G=g,B=b,A=a } end

local CFG = {
  MaxDistance = 50000, RenderTrackingDistance = 50000,
  MaxTracked = 16,
  ScreenMargin = 500,
  TopTextY = 6.0, SnapOriginY = 0.0, SnapThickness = 1.8,
  CornerThickness = 2.2, CornerLen = 0.28, CornerMin = 6, CornerMax = 28,
  BoxMinWidth = 22, BoxMaxWidth = 320, BoxMinHeight = 1, BoxWidthFactor = 0.62,
  WidthScale = 1.22, HeadExtra = 0.06, FootExtra = 0.02,
  SideBarWidth = 3.5, SideBarGap = 5.0, SideBgAlpha = 0.55,
  MarkGap = 8.0, MarkW = 15.0, MarkH = 10.0, MarkGapV = 6.0, MarkThickness = 2.4,
  NameFontSize = 15, DistFontSize = 13, StateFontSize = 13, TextGap = 1.0,
  CounterFontSize = 17, CounterW = 300.0, CounterH = 28.0,
  DeadZone = 0.5, VisInterval = 0.30, SizeHyst = 2.0,
}

local C_WHITE  = ESPMKC(1.0, 1.0, 1.0, 1.0)
local C_BLACK  = ESPMKC(0.0, 0.0, 0.0, 1.0)
local C_GREEN  = ESPMKC(0.12, 1.0, 0.25, 1.0)
local C_RED    = ESPMKC(1.0, 0.15, 0.15, 1.0)

local TEAM_COLORS = {
  ESPMKC(0.20,0.65,1.00,1.00), ESPMKC(1.00,0.28,0.28,1.00), ESPMKC(0.25,0.90,0.40,1.00),
  ESPMKC(1.00,0.72,0.18,1.00), ESPMKC(0.72,0.40,1.00,1.00), ESPMKC(0.10,0.88,0.85,1.00),
  ESPMKC(1.00,0.42,0.78,1.00), ESPMKC(0.72,0.82,0.92,1.00),
}
local function TeamColor(teamID, isBot, fallbackKey)
  local n = tonumber(teamID)
  if n then n = math.abs(math.floor(n)) else
    local s = tostring(fallbackKey or "unknown"); local h = 0
    for i=1,#s do h = (h*31 + string.byte(s,i)) % 2147483647 end
    n = h
  end
  return TEAM_COLORS[(n % #TEAM_COLORS) + 1]
end
local function RND(v) if v ~= v then return 0 end return math.floor(v + 0.5) end
local function Lerp(a,b,t) return a + (b-a)*t end
local function HealthColor(pct)
  pct = math.max(0, math.min(1, tonumber(pct) or 1.0))
  if pct >= 0.7 then local t=(pct-0.7)/0.3 return ESPMKC(Lerp(0.75,0.12,t),1.0,Lerp(0.15,0.25,t),1.0)
  elseif pct >= 0.4 then local t=(pct-0.4)/0.3 return ESPMKC(1.0,Lerp(0.45,0.95,t),Lerp(0.45,0.20,t),1.0)
  else local t=pct/0.4 return ESPMKC(1.0,Lerp(0.15,0.45,t),Lerp(0.15,0.45,t),1.0) end
end

local ESP = {
  Canvas=nil, Lines={}, Corners={}, HealthBg={}, HealthFill={}, Marks={}, Infos={},
  Counter=nil, EnemyCache={}, VisCache={},
  ScaleX=1.0, ScaleY=1.0, OffsetX=0.0, OffsetY=0.0, ViewW=1920, ViewH=1080,
  ScanInterval=0.20, LightInterval=0.050, TransformInterval=1.0,
  LastScan=-999.0, LastTransform=-999.0,
  bActive=false, _isUpdating=false,
  _InGameUITools=nil, _GDP=nil,
  LastLocalPawn=nil, PauseUntil=0,
  _TimerPC=nil, _TimerHooked=false,
  RealCount=0, BotCount=0,
}

local ScratchActive = {}

function ESP.GetGameplayData()
  if ESP._GDP then return ESP._GDP end
  local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
  if ok and GDP then ESP._GDP = GDP end
  return ESP._GDP
end

function ESP.GetInGameUITools()
  if ESP._InGameUITools then return ESP._InGameUITools end
  local ok, m = pcall(function() return require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
  if ok and m then ESP._InGameUITools = m end
  return ESP._InGameUITools
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
    pcall(function()
      for k, ch in pairs(chars) do
        if ch and ESPValid(ch) then
          local pKey = k
          if not pKey then pcall(function() pKey = ch:GetPlayerKey() end) end
          if not pKey then pcall(function() pKey = ch.PlayerKey end) end
          if pKey then AllChars[pKey] = ch end
        end
      end
    end)
  end
  pcall(function() if Game and Game.GetAllPlayerPawns then merge(Game:GetAllPlayerPawns()) end end)
  if next(AllChars) == nil then
    pcall(function()
      local GDP = ESP.GetGameplayData()
      if GDP and GDP.GetAllCharacters then merge(GDP:GetAllCharacters()) end
    end)
  end
  return AllChars
end

function ESP.GetTeamID(Character)
  if not ESPValid(Character) then return nil end
  local id = nil
  pcall(function() if Character.GetTeamID then id = Character:GetTeamID() end end)
  if id == nil then pcall(function() id = Character.TeamID end) end
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

function ESP.IsBot(Character)
  if not ESPValid(Character) then return false end
  local bAI = false
  pcall(function()
    if Game and Game.IsAI then bAI = Game:IsAI(Character) end
    if not bAI and Character then
      if Character.bEnsure == true or Character.bMEnsure == true then bAI = true
      elseif Character.bIsAI == true then bAI = true end
    end
  end)
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
  local hp, maxhp
  pcall(function() hp = Character.Health end)
  if type(hp) ~= "number" then pcall(function() hp = Character.HP end) end
  pcall(function() maxhp = Character.MaxHealth end)
  if type(maxhp) ~= "number" then pcall(function() maxhp = Character.MaxHP end) end
  if type(hp) ~= "number" then return 1.0 end
  if type(maxhp) ~= "number" or maxhp <= 0 then maxhp = 100 end
  local pct = hp / maxhp
  if pct ~= pct then return 1.0 end
  return math.max(0, math.min(1, pct))
end

function ESP.ResolveName(Character, isBot)
  if isBot then return "Bot" end
  local name = nil
  local function take(v)
    if name then return end
    if v == nil or v == false then return end
    local ok, t = pcall(tostring, v); if not ok or not t then return end
    t = t:gsub("^%s+",""):gsub("%s+$","")
    if t ~= "" and t ~= "nil" and t ~= "None" and t ~= "NULL" then name = t end
  end
  pcall(function() if Character.GetPlayerNameSafety then take(Character:GetPlayerNameSafety()) end end)
  pcall(function() if not name then take(Character.PlayerName) end end)
  pcall(function() if not name then take(Character.NickName) end end)
  return name or "Player"
end

local _BonePosScratch = { X = 0, Y = 0, Z = 0 }
function ESP.GetBonePos(Character, boneName)
  if not ESPValid(Character) or not boneName then return nil end
  local pos = nil
  pcall(function()
    if type(Character.GetBonePos) == "function" then
      pos = Character:GetBonePos(boneName, _BonePosScratch)
    end
    if (not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0)) and ESPValid(Character.Mesh) then
      local mesh = Character.Mesh
      if mesh and mesh.GetSocketLocation then pos = mesh:GetSocketLocation(boneName) end
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

function ESP.IsVisible(key, pc, camLoc, Character)
  local now = ESP.Now()
  local cached = ESP.VisCache[key]
  if cached and (now - (cached.t or 0)) < CFG.VisInterval then return cached.b end
  local bVis = false
  if ESPValid(Character) and ESPValid(pc) and camLoc and KismetSystemLibraryESP then
    local bp = ESP.GetBonePos(Character, "head")
    if bp and (bp.X ~= 0 or bp.Y ~= 0 or bp.Z ~= 0) then
      pcall(function()
        local dx, dy, dz = bp.X - camLoc.X, bp.Y - camLoc.Y, bp.Z - camLoc.Z
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        if dist < 300 then bVis = true return end
        TraceStartPos.X = camLoc.X + (dx/dist)*60
        TraceStartPos.Y = camLoc.Y + (dy/dist)*60
        TraceStartPos.Z = camLoc.Z + (dz/dist)*60
        local hit = KismetSystemLibraryESP.LineTraceSingle(pc, TraceStartPos, bp, 0, false, nil, 0, CachedHitResult, true)
        if hit then
          local ha = nil
          if CachedHitResult then
            if type(CachedHitResult.GetActor) == "function" then ha = CachedHitResult:GetActor()
            elseif CachedHitResult.Actor then ha = CachedHitResult.Actor end
          end
          bVis = (ha == Character)
        else bVis = true end
      end)
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
  local dx, dy, dz = a.X-b.X, a.Y-b.Y, a.Z-b.Z
  return math.sqrt(dx*dx+dy*dy+dz*dz) / 100.0
end

function ESP.GetVerticalBounds(Character)
  if not ESPValid(Character) then return nil, nil end
  local center, halfHeight
  pcall(function()
    local capsule = nil
    if Character.GetCapsuleComponent then capsule = Character:GetCapsuleComponent()
    elseif Character.CapsuleComponent then capsule = Character.CapsuleComponent end
    if ESPValid(capsule) then
      if capsule.K2_GetComponentLocation then center = capsule:K2_GetComponentLocation()
      elseif capsule.GetComponentLocation then center = capsule:GetComponentLocation() end
      if capsule.GetScaledCapsuleHalfHeight then halfHeight = capsule:GetScaledCapsuleHalfHeight()
      elseif capsule.GetUnscaledCapsuleHalfHeight then halfHeight = capsule:GetUnscaledCapsuleHalfHeight() end
    end
  end)
  if not center then pcall(function() if Character.K2_GetActorLocation then center = Character:K2_GetActorLocation() end end) end
  if not center then return nil, nil end
  if not halfHeight or halfHeight < 10 or halfHeight > 200 then halfHeight = 85 end
  return center, halfHeight
end

function ESP.GetHeadFeet(Character)
  local c, h = ESP.GetVerticalBounds(Character)
  if not c or not h then return nil, nil end
  return { X=c.X, Y=c.Y, Z=c.Z+h }, { X=c.X, Y=c.Y, Z=c.Z-h }
end

function ESP.Now()
  local t = nil
  pcall(function()
    local w = slua and slua.getWorld and slua.getWorld()
    if GameplayStaticsESP and w and GameplayStaticsESP.GetRealTimeSeconds then
      t = GameplayStaticsESP.GetRealTimeSeconds(w)
    end
  end)
  if tonumber(t) then return tonumber(t) end
  pcall(function() if os and os.clock then t = os.clock() end end)
  return tonumber(t) or 0.0
end

function ESP.GetCanvas()
  if ESPValid(ESP.Canvas) then return ESP.Canvas end
  if ESP.Canvas ~= nil then ESP.DropWidgetRefs() end
  local tools = ESP.GetInGameUITools()
  if not tools then return nil end
  local root = nil
  pcall(function() if tools.GetMainControlBaseUI then root = tools.GetMainControlBaseUI() end end)
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
        if p0 and p1 and p1.X ~= p0.X and p1.Y ~= p0.Y then
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
    local s = 1.0
    pcall(function()
      if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
        local v = WidgetLayoutLibrary.GetViewportScale(pc)
        if tonumber(v) and v > 0 then s = v end
      end
    end)
    ESP.ScaleX, ESP.ScaleY = 1.0/s, 1.0/s
    ESP.OffsetX, ESP.OffsetY = 0.0, 0.0
  end
  return true
end

function ESP.Viewport(pc)
  local w, h = 1920.0, 1080.0
  pcall(function()
    if pc and pc.GetViewportSize then
      local v = ESPV2(0, 0); pc:GetViewportSize(v)
      if v and tonumber(v.X) and v.X > 200 then w, h = v.X, v.Y end
    end
  end)
  return w, h
end

function ESP.Project(pc, worldLoc)
  if not pc or not worldLoc then return nil end
  local pix = ESPV2(0, 0); local ok = false
  pcall(function()
    local res = pc:ProjectWorldLocationToScreen(worldLoc, pix, true)
    ok = (res == true or res == 1 or (pix and (pix.X ~= 0 or pix.Y ~= 0)))
  end)
  if not ok then return nil end
  return ESPV2(pix.X*(ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0),
               pix.Y*(ESP.ScaleY or 1.0) + (ESP.OffsetY or 0.0)), pix
end

function ESP.SetFont(w, size)
  if not ESPValid(w) then return end
  pcall(function()
    local f = w.Font
    if f then
      f.Size = size
      w:SetFont(f)
    end
    if w.SetShadowOffset then w:SetShadowOffset(ESPV2(1.0, 1.0)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(C_BLACK) end
  end)
end

function ESP.SetTextColor(w, color)
  if not ESPValid(w) then return end
  pcall(function()
    if SlateColor then w:SetColorAndOpacity(SlateColor(color)) else w:SetColorAndOpacity(color) end
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
  if not slot then pcall(function() border:RemoveFromParent() end) return nil end
  pcall(function() slot:SetAutoSize(false) slot:SetZOrder(z or 30) end)
  return { Widget = border, Slot = slot }
end

function ESP.DrawLine(data, x1, y1, x2, y2, thickness)
  if not data or not ESPValid(data.Widget) or not data.Slot then return false end
  if x1 ~= x1 or y1 ~= y1 or x2 ~= x2 or y2 ~= y2 then return false end
  x1, y1, x2, y2 = RND(x1), RND(y1), RND(x2), RND(y2)
  local dz = CFG.DeadZone
  if data.lx1 and data.th == thickness
    and math.abs((data.lx1 or 0)-x1) < dz and math.abs((data.ly1 or 0)-y1) < dz
    and math.abs((data.lx2 or 0)-x2) < dz and math.abs((data.ly2 or 0)-y2) < dz
    and data.hidden ~= true then return true end
  local dx, dy = x2-x1, y2-y1
  local len = math.sqrt(dx*dx + dy*dy)
  if len < 1 then ESP.Hide(data) return false end
  local angle = ((math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)) * 180.0 / math.pi
  angle = math.floor(angle*10 + 0.5) / 10
  len = RND(len)
  if data.lx1 == x1 and data.ly1 == y1 and data.lx2 == x2 and data.ly2 == y2 and data.th == thickness then
    if data.hidden == true then
      pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
      data.hidden = false
    end
    return true
  end
  local ok = pcall(function()
    data.Slot:SetPosition(ESPV2(x1, y1 - thickness*0.5))
    data.Slot:SetSize(ESPV2(len, thickness))
    data.Widget:SetRenderAngle(angle)
    data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if ok then data.lx1, data.ly1, data.lx2, data.ly2, data.th = x1, y1, x2, y2, thickness data.hidden = false end
  return ok
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
  if ESPValid(w) then pcall(function() w:RemoveFromParent() end) end
end

function ESP.CreateCounter()
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local container = nil
  pcall(function() container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
  if not ESPValid(container) then return nil end
  pcall(function() container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
  local txt = nil
  pcall(function() txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
  if not ESPValid(txt) then pcall(function() container:RemoveFromParent() end) return nil end
  pcall(function()
    txt:SetText("Players: 0 | Bots: 0")
    txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if txt.SetJustification then txt:SetJustification(1) end
  end)
  ESP.SetTextColor(txt, C_WHITE)
  ESP.SetFont(txt, CFG.CounterFontSize)
  local tSlot, mSlot
  pcall(function() tSlot = container:AddChildToCanvas(txt) end)
  pcall(function() mSlot = canvas:AddChildToCanvas(container) end)
  if not tSlot or not mSlot then pcall(function() container:RemoveFromParent() end) return nil end
  local W, H = CFG.CounterW, CFG.CounterH
  pcall(function()
    tSlot:SetAutoSize(true) tSlot:SetAlignment(ESPV2(0.5,0.5)) tSlot:SetPosition(ESPV2(W*0.5,H*0.5)) tSlot:SetZOrder(5)
    mSlot:SetAutoSize(false) mSlot:SetAlignment(ESPV2(0.5,0.0)) mSlot:SetSize(ESPV2(W,H)) mSlot:SetZOrder(60)
  end)
  return { Container=container, Text=txt, Slot=mSlot, W=W, H=H }
end

function ESP.UpdateCounter(nPlayers, nBots, pc, viewW)
  local d = ESP.Counter
  if not d or not ESPValid(d.Container) then ESP.Destroy(d) d = ESP.CreateCounter() ESP.Counter = d end
  if not d then return nil end
  local label = string.format("Players: %d | Bots: %d", nPlayers or 0, nBots or 0)
  pcall(function() if d.Last ~= label then d.Text:SetText(label) d.Last = label end end)
  local cw = nil
  pcall(function()
    local canvas = ESP.GetCanvas()
    if ESPValid(canvas) then
      local geo = canvas:GetCachedGeometry()
      if geo and geo.GetLocalSize then local s = geo:GetLocalSize() if s and tonumber(s.X) and s.X > 1 then cw = tonumber(s.X) end end
    end
  end)
  local cx = cw and (cw*0.5) or ((viewW*0.5)*(ESP.ScaleX or 1.0) + (ESP.OffsetX or 0.0))
  if cx then
    cx = RND(cx)
    if d.px ~= cx then d.px = cx
      pcall(function() d.Slot:SetPosition(ESPV2(cx, CFG.TopTextY)) d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    end
  end
  return ESPV2(cx or 0, CFG.SnapOriginY)
end

function ESP.CreateInfo()
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local container, teamBox, tName, tDist, tState
  pcall(function() container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
  if not ESPValid(container) then return nil end
  pcall(function() container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
  pcall(function() teamBox = CGame:NewObjectFromPath("/Script/UMG.Border", container) end)
  pcall(function() tName   = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
  pcall(function() tDist   = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
  pcall(function() tState  = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
  if not ESPValid(teamBox) or not ESPValid(tName) or not ESPValid(tDist) or not ESPValid(tState) then
    pcall(function() container:RemoveFromParent() end) return nil
  end
  pcall(function()
    teamBox:SetBrushColor(TEAM_COLORS[1])
    teamBox:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tName:SetText("Player") tDist:SetText("0m") tState:SetText("Open")
    tName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tDist:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    tState:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if tName.SetJustification then tName:SetJustification(1) end
    if tDist.SetJustification then tDist:SetJustification(1) end
    if tState.SetJustification then tState:SetJustification(1) end
  end)
  ESP.SetTextColor(tName, C_WHITE) ESP.SetTextColor(tDist, C_WHITE) ESP.SetTextColor(tState, C_GREEN)
  ESP.SetFont(tName, CFG.NameFontSize) ESP.SetFont(tDist, CFG.DistFontSize) ESP.SetFont(tState, CFG.StateFontSize)
  local bSlot,nSlot,s2,s3,ms
  pcall(function() bSlot=container:AddChildToCanvas(teamBox) end)
  pcall(function() nSlot=container:AddChildToCanvas(tName) end)
  pcall(function() s2=container:AddChildToCanvas(tDist) end)
  pcall(function() s3=container:AddChildToCanvas(tState) end)
  pcall(function() ms=canvas:AddChildToCanvas(container) end)
  if not bSlot or not nSlot or not s2 or not s3 or not ms then
    pcall(function() container:RemoveFromParent() end) return nil
  end
  pcall(function()
    bSlot:SetAutoSize(false) bSlot:SetSize(ESPV2(120,22)) bSlot:SetAlignment(ESPV2(0.5,0.5)) bSlot:SetZOrder(34)
    nSlot:SetAutoSize(false) nSlot:SetSize(ESPV2(120,22)) nSlot:SetAlignment(ESPV2(0.5,0.5)) nSlot:SetZOrder(36)
    s2:SetAutoSize(true) s2:SetAlignment(ESPV2(0.5,0.5)) s2:SetZOrder(36)
    s3:SetAutoSize(true) s3:SetAlignment(ESPV2(0.5,0.5)) s3:SetZOrder(36)
    ms:SetAutoSize(false) ms:SetZOrder(35)
  end)
  return { Container=container, TeamBox=teamBox, Name=tName, Dist=tDist, State=tState,
           S0=bSlot, S1=nSlot, S2=s2, S3=s3, Slot=ms }
end

function ESP.UpdateInfo(key, Character, isBot, teamID, distM, bVisible, headX, headY, footX, footY, boxL, boxR)
  local d = ESP.Infos[key]
  if not d or not ESPValid(d.Container) then ESP.Destroy(d) d = ESP.CreateInfo() ESP.Infos[key] = d end
  if not d then return end
  local name = d.CachedName
  if not name then name = ESP.ResolveName(Character, isBot) d.CachedName = name end
  if isBot then name = "Bot" d.CachedName = "Bot" end
  local dl = string.format("%dm", math.max(0, math.floor((tonumber(distM) or 0)+0.5)))
  local st = bVisible and "Open" or "Close"
  local teamColor = TeamColor(teamID, isBot, key)
  pcall(function()
    if d.LastN ~= name then d.Name:SetText(name) d.LastN = name end
    if d.LastD ~= dl then d.Dist:SetText(dl) d.LastD = dl end
    if d.LastS ~= st then d.State:SetText(st) d.LastS = st end
    if d.LastTeam ~= tostring(teamID)..":"..tostring(isBot) then d.TeamBox:SetBrushColor(teamColor) d.LastTeam = tostring(teamID)..":"..tostring(isBot) end
    ESP.SetTextColor(d.State, bVisible and C_GREEN or C_RED)
  end)
  local bannerW, bannerH = 100.0, 22.0
  local bx, by = RND(headX), RND(headY - 18.0)
  if d.ix ~= bx or d.iy ~= by then
    d.ix, d.iy = bx, by
    pcall(function()
      d.Slot:SetPosition(ESPV2(bx, by))
      d.Slot:SetSize(ESPV2(bannerW, 70.0))
      d.S0:SetPosition(ESPV2(0,0)) d.S0:SetSize(ESPV2(bannerW,bannerH))
      d.S1:SetPosition(ESPV2(0,0)) d.S1:SetSize(ESPV2(bannerW,bannerH))
      d.S2:SetPosition(ESPV2(bannerW*0.5, bannerH+12.0))
      d.S3:SetPosition(ESPV2(bannerW*0.5, bannerH+30.0))
      d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
  else
    pcall(function() d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
  end
end

function ESP.EnsureSnap(key)
  local d = ESP.Lines[key]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(C_GREEN, 30); ESP.Lines[key] = d; return d
end
function ESP.EnsureHealthBg(key)
  local d = ESP.HealthBg[key]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(ESPMKC(0,0,0,CFG.SideBgAlpha), 31); ESP.HealthBg[key] = d; return d
end
function ESP.EnsureHealthFill(key)
  local d = ESP.HealthFill[key]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(C_GREEN, 32); ESP.HealthFill[key] = d; return d
end

function ESP.UpdateHealthBar(key, pct, x, y, w)
  local bg, fill = ESP.EnsureHealthBg(key), ESP.EnsureHealthFill(key)
  if not bg or not fill then return end
  local th = CFG.SideBarWidth
  w = math.max(1, tonumber(w) or 1)
  ESP.DrawLine(bg, x, y, x+w, y, th)
  pct = math.max(0, math.min(1, tonumber(pct) or 1.0))
  local bucket = (pct>=0.7 and "g_" or pct>=0.4 and "y_" or "r_") .. math.floor(pct*20+0.5)
  ESP.SetBrush(fill, HealthColor(pct), bucket)
  local fw = w * pct
  if fw < 1 then ESP.Hide(fill) return end
  ESP.DrawLine(fill, x, y, x+fw, y, th)
end

function ESP.HideTarget(key)
  local c = ESP.Corners[key]; if c then for i=1,8 do ESP.Hide(c[i]) end end
  ESP.Hide(ESP.HealthBg[key]) ESP.Hide(ESP.HealthFill[key])
  ESP.Hide(ESP.Lines[key])
  local inf = ESP.Infos[key]
  if inf and ESPValid(inf.Container) then
    pcall(function() inf.Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
  end
end

function ESP.DropWidgetRefs()
  local canvasValid = ESPValid(ESP.Canvas)
  if canvasValid then
    for _, d in pairs(ESP.Lines) do ESP.Destroy(d) end
    for _, d in pairs(ESP.HealthBg) do ESP.Destroy(d) end
    for _, d in pairs(ESP.HealthFill) do ESP.Destroy(d) end
    for _, t in pairs(ESP.Corners) do for _, d in pairs(t) do ESP.Destroy(d) end end
    for _, t in pairs(ESP.Marks) do for _, d in pairs(t) do ESP.Destroy(d) end end
    for _, d in pairs(ESP.Infos) do ESP.Destroy(d) end
    if ESP.Counter then ESP.Destroy(ESP.Counter) end
  end
  ESP.Lines = {} ESP.Corners = {} ESP.HealthBg = {} ESP.HealthFill = {}
  ESP.Marks = {} ESP.Infos = {} ESP.VisCache = {} ESP.Counter = nil
  ESP.Canvas = nil ESP.EnemyCache = {}
end

function ESP.Scan()
  local pc = ESP.GetController()
  local me = ESP.GetLocalCharacter()
  if not pc or not me then ESP.EnemyCache = {} return pc, 0, 0 end
  local myLoc = ESP.ActorLocation(me)
  if not myLoc then ESP.EnemyCache = {} return pc, 0, 0 end
  local myTeam = ESP.GetTeamID(me)
  local list, seen = {}, {}
  local nReal, nBot = 0, 0
  local pawns = ESP.GetAllCharacters()
  for _, ch in pairs(pawns or {}) do
    if ESPValid(ch) and ch ~= me and ESP.IsAlive(ch) then
      local key = ESP.GetPlayerKey(ch)
      if not seen[key] then
        local team = ESP.GetTeamID(ch)
        if not (myTeam ~= nil and team ~= nil and tostring(team) == tostring(myTeam)) then
          seen[key] = true
          local dm = ESP.DistMeters(myLoc, ESP.ActorLocation(ch))
          local isBot = ESP.IsBot(ch)
          if isBot then nBot = nBot + 1 else nReal = nReal + 1 end
          list[#list+1] = { Character=ch, Key=key, IsBot=isBot, TeamID=team, Distance=dm }
        end
      end
    end
  end
  table.sort(list, function(a,b) return (a.Distance or 99999) < (b.Distance or 99999) end)
  local trimmed = {}
  for i=1, math.min(#list, CFG.MaxTracked) do trimmed[#trimmed+1] = list[i] end
  ESP.EnemyCache = trimmed
  return pc, nReal, nBot
end

function ESP.Update()
  if not ESP_Enabled then return end
  if ESP._isUpdating then return end
  ESP._isUpdating = true
  local ok, err = pcall(ESP._UpdateInternal)
  ESP._isUpdating = false
  if not ok and bWriteLog then print("[ESP] Update error: "..tostring(err)) end
end

function ESP._UpdateInternal()
  local now = ESP.Now()
  if ESP.PauseUntil and now < ESP.PauseUntil then return end

  local pc = ESP.GetController()
  if not ESPValid(pc) then return end

  local curPawn = nil
  pcall(function() curPawn = pc:GetPawn() end)
  if curPawn ~= ESP.LastLocalPawn then
    ESP.LastLocalPawn = curPawn
    ESP.PauseUntil = now + 1.0
    ESP.DropWidgetRefs()
    return
  end

  local canvas = ESP.GetCanvas()
  if not canvas then return end

  if (now - ESP.LastScan) >= ESP.ScanInterval then
    local scanOk, r, b = pcall(ESP.Scan)
    if scanOk then ESP.RealCount, ESP.BotCount = r or 0, b or 0 end
    ESP.LastScan = now
  end

  if (now - ESP.LastTransform) >= ESP.TransformInterval then
    pcall(ESP.UpdateCanvasTransform, pc)
    ESP.LastTransform = now
  end

  local vw, vh = ESP.Viewport(pc)
  if math.abs(vw - ESP.ViewW) > CFG.SizeHyst or math.abs(vh - ESP.ViewH) > CFG.SizeHyst then
    ESP.ViewW, ESP.ViewH = vw, vh
  else vw, vh = ESP.ViewW, ESP.ViewH end

  local origin = ESP.UpdateCounter(ESP.RealCount or 0, ESP.BotCount or 0, pc, vw)
  if not origin then return end

  local camLoc = ESP.GetCamLoc(pc)
  for k in pairs(ScratchActive) do ScratchActive[k] = nil end
  local cache = ESP.EnemyCache or {}
  for i = 1, #cache do
    local item = cache[i]
    local c = item.Character
    if ESPValid(c) and ESP.IsAlive(c) then
      local ok2 = pcall(function()
        local head, feet = ESP.GetHeadFeet(c)
        if not head or not feet then ESP.HideTarget(item.Key) return end
        local hs, hp = ESP.Project(pc, head)
        local fs, fp = ESP.Project(pc, feet)
        if not hs or not fs or not hp or not fp then ESP.HideTarget(item.Key) return end
        local m = CFG.ScreenMargin
        if not (hp.X > -m and hp.X < vw+m and hp.Y > -m and hp.Y < vh+m
              and fp.X > -m and fp.X < vw+m and fp.Y > -m and fp.Y < vh+m) then
          ESP.HideTarget(item.Key) return
        end
        local H = fs.Y - hs.Y
        if H < CFG.BoxMinHeight or H > vh*1.5 then ESP.HideTarget(item.Key) return end
        ScratchActive[item.Key] = true
        local W = math.max(CFG.BoxMinWidth, math.min(CFG.BoxMaxWidth, H*CFG.BoxWidthFactor))
        local cx = (hs.X + fs.X)*0.5
        local L, R = cx - W*0.5, cx + W*0.5
        ESP.UpdateHealthBar(item.Key, ESP.GetHealthPct(c), L, hs.Y+8, R-L)
        local snap = ESP.EnsureSnap(item.Key)
        if snap then ESP.DrawLine(snap, origin.X, origin.Y, hs.X, hs.Y, CFG.SnapThickness) end
        local bVis = ESP.IsVisible(item.Key, pc, camLoc, c)
        ESP.UpdateInfo(item.Key, c, item.IsBot, item.TeamID, item.Distance, bVis,
                       hs.X, hs.Y, cx, fs.Y, L, R)
      end)
      if not ok2 then ESP.HideTarget(item.Key) end
    end
  end

  local seenCache = {}
  for i = 1, #cache do seenCache[cache[i].Key] = true end
  local toRelease = nil
  for k in pairs(ESP.Corners) do
    if not ScratchActive[k] and not seenCache[k] then toRelease = toRelease or {} toRelease[k] = true end
  end
  for k in pairs(ESP.HealthBg) do
    if not ScratchActive[k] and not seenCache[k] then toRelease = toRelease or {} toRelease[k] = true end
  end
  if toRelease then
    for k in pairs(toRelease) do
      local c = ESP.Corners[k]; if c then for i=1,8 do ESP.Destroy(c[i]) end end
      ESP.Corners[k] = nil
      ESP.Destroy(ESP.HealthBg[k]) ESP.HealthBg[k] = nil
      ESP.Destroy(ESP.HealthFill[k]) ESP.HealthFill[k] = nil
      ESP.Destroy(ESP.Lines[k]) ESP.Lines[k] = nil
      ESP.Destroy(ESP.Infos[k]) ESP.Infos[k] = nil
      ESP.VisCache[k] = nil
    end
  end
  for k in pairs(ESP.Lines) do if not ScratchActive[k] then ESP.HideTarget(k) end end
  for k in pairs(ESP.Infos) do if not ScratchActive[k] then ESP.HideTarget(k) end end
end

function ESP.Tick() pcall(ESP.Update) end

function ESP.AttachTimers()
  pcall(function()
    local pc = ESP.GetController()
    if not ESPValid(pc) or not pc.AddGameTimer then
      pcall(function()
        require("timer").SetGameTimer(1.0, false, function()
          if not ESP._TimerHooked then ESP.AttachTimers() end
        end)
      end)
      return
    end
    if ESP._TimerPC == pc and ESP._TimerHooked then return end
    ESP._TimerPC = pc
    local ok = pcall(function()
      pc:AddGameTimer(ESP.LightInterval, true, function()
        if ESP.bActive then pcall(ESP.Tick) end
      end)
    end)
    ESP._TimerHooked = ok
  end)
end

function ESP.Start()
  ESP.bActive = true
  if not ESP._TimerHooked then
    pcall(ESP.Update)
    ESP.AttachTimers()
  end
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
      end
      ESP.Start()
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
