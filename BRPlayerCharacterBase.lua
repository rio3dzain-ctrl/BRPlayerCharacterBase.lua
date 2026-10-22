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

--=============================================================================
-- ESP (FIXED: no lag, no crash)
--=============================================================================
local ESP_Enabled = true

local FVector2D     = _G.FVector2D     or import("Vector2D")
local FLinearColor  = _G.FLinearColor  or import("LinearColor")
local SlateBlueprintLibrary, WidgetLayoutLibrary, SlateColor, GameplayStaticsESP
local KismetSystemLibraryESP, HitResultClassESP
pcall(function() SlateBlueprintLibrary  = import("SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary    = import("WidgetLayoutLibrary") end)
pcall(function() SlateColor             = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
pcall(function() GameplayStaticsESP     = import("GameplayStatics") end)
pcall(function() KismetSystemLibraryESP = import("KismetSystemLibrary") end)
pcall(function() HitResultClassESP      = import("HitResult") end)

local TraceStartPos  = { X = 0, Y = 0, Z = 0 }
local CachedHitResult
pcall(function()
  CachedHitResult = HitResultClassESP and HitResultClassESP() or {}
end)

local function ESPValid(obj)
  if obj == nil then return false end
  local ok, v = pcall(function() return slua.isValid(obj) end)
  return ok and v == true
end
local function ESPV2(x, y)     if FVector2D    then return FVector2D(x, y)       end return { X = x, Y = y } end
local function ESPMKC(r,g,b,a) if FLinearColor then return FLinearColor(r,g,b,a) end return { R=r,G=g,B=b,A=a } end

local CFG = {
  MaxDistance      = 50000,
  MaxTracked       = 32,
  ScreenMargin     = 500,
  TopTextY         = 6.0,
  SnapOriginY      = 0.0,
  SnapThickness    = 1.8,
  BoxMinHeight     = 1,
  BoxWidthFactor   = 0.62,
  BoxMinWidth      = 22,
  BoxMaxWidth      = 320,
  HeadExtra        = 0.06,
  FootExtra        = 0.02,
  SideBarWidth     = 3.5,
  SideBgAlpha      = 0.55,
  DeadZone         = 0.5,
  SizeHyst         = 2.0,
  NameFontSize     = 15,
  DistFontSize     = 13,
  StateFontSize    = 13,
  CounterFontSize  = 17,
  CounterW         = 300.0,
  CounterH         = 28.0,
  VisInterval      = 0.25,
}

local C_WHITE  = ESPMKC(1,1,1,1)
local C_BLACK  = ESPMKC(0,0,0,1)
local C_GREEN  = ESPMKC(0.12,1.0,0.25,1)
local C_RED    = ESPMKC(1.0,0.15,0.15,1)

local TEAM_COLORS = {
  ESPMKC(0.20,0.65,1.00,1), ESPMKC(1.00,0.28,0.28,1),
  ESPMKC(0.25,0.90,0.40,1), ESPMKC(1.00,0.72,0.18,1),
  ESPMKC(0.72,0.40,1.00,1), ESPMKC(0.10,0.88,0.85,1),
  ESPMKC(1.00,0.42,0.78,1), ESPMKC(0.72,0.82,0.92,1),
}
local function TeamColor(teamID, isBot, fallbackKey)
  local n = tonumber(teamID)
  if n then n = math.abs(math.floor(n)) else
    local s = tostring(fallbackKey or "x"); n = 0
    for i = 1, #s do n = (n * 31 + string.byte(s,i)) % 2147483647 end
  end
  return TEAM_COLORS[(n % #TEAM_COLORS) + 1]
end
local function RND(v) if v ~= v then return 0 end return math.floor(v + 0.5) end
local function Lerp(a,b,t) return a + (b - a) * t end
local function HealthColor(p)
  p = math.max(0, math.min(1, tonumber(p) or 1))
  local r,g,b
  if p >= 0.7 then
    local t = (p - 0.7)/0.3; r = Lerp(0.75,0.12,t); g = 1; b = Lerp(0.15,0.25,t)
  elseif p >= 0.4 then
    local t = (p - 0.4)/0.3; r = 1; g = Lerp(0.45,0.95,t); b = Lerp(0.45,0.20,t)
  else
    local t = p/0.4; r = 1; g = Lerp(0.15,0.45,t); b = Lerp(0.15,0.45,t)
  end
  return ESPMKC(r,g,b,1)
end

local ESP = {
  Canvas = nil, Lines = {}, HealthBg = {}, HealthFill = {}, Infos = {},
  Counter = nil, EnemyCache = {}, VisCache = {},
  ScaleX = 1.0, ScaleY = 1.0, OffsetX = 0.0, OffsetY = 0.0,
  ViewW = 1920, ViewH = 1080,

  LightInterval     = 0.1,
  ScanInterval      = 0.5,
  TransformInterval = 1.0,

  LastScan      = -999.0,
  LastTransform = -999.0,
  LastWorld     = nil,
  bActive       = false,
  _nowOverride  = nil,
}

function ESP.Now()
  if ESP._nowOverride then return ESP._nowOverride end
  local t
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
  local w; pcall(function() if slua and slua.getWorld then w = slua.getWorld() end end)
  return w
end

function ESP.GetGameplayData()
  if ESP._GDP then return ESP._GDP end
  local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
  if ok and GDP then ESP._GDP = GDP return GDP end
  return nil
end
function ESP.GetController()
  local pc
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
  local c
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
  local result, got = {}, false
  pcall(function()
    if Game and Game.GetAllPlayerPawns then
      local pawns = Game:GetAllPlayerPawns()
      if pawns then
        for k, ch in pairs(pawns) do
          if ch and slua.isValid(ch) then result[k] = ch got = true end
        end
      end
    end
  end)
  if got then return result end
  pcall(function()
    local GDP = ESP.GetGameplayData()
    if GDP and GDP.GetAllCharacters then
      local chars = GDP:GetAllCharacters()
      if chars then
        for k, ch in pairs(chars) do
          if ch and slua.isValid(ch) then result[k] = ch end
        end
      end
    end
  end)
  return result
end

function ESP.GetMyPlayerKey()
  local pc = ESP.GetController()
  if not ESPValid(pc) then return nil end
  local k
  pcall(function()
    if pc.GetPlayerKey then k = pc:GetPlayerKey()
    elseif pc.PlayerState then k = pc.PlayerState.PlayerKey end
  end)
  return k
end
function ESP.GetTeamID(C)
  if not ESPValid(C) then return nil end
  local id
  pcall(function() if C.GetTeamID then id = C:GetTeamID() end end)
  if id == nil then pcall(function() id = C.TeamID end) end
  if id == nil then
    local ps
    pcall(function()
      if C.GetPlayerStateSafety then ps = C:GetPlayerStateSafety()
      elseif C.GetPlayerState then ps = C:GetPlayerState() end
    end)
    if not ESPValid(ps) then pcall(function() ps = C.PlayerState end) end
    if ESPValid(ps) then
      pcall(function() if ps.GetTeamID then id = ps:GetTeamID() end end)
      if id == nil then pcall(function() id = ps.TeamID end) end
    end
  end
  return id
end
function ESP.IsAlive(C)
  if not ESPValid(C) then return false end
  local alive
  pcall(function() if C.IsAlive then alive = C:IsAlive() end end)
  if type(alive) == "boolean" then return alive end
  local hp
  pcall(function() hp = C.Health end)
  if type(hp) ~= "number" then pcall(function() hp = C.HP end) end
  if type(hp) == "number" then return hp > 0 end
  return true
end
function ESP.IsBot(C)
  if not ESPValid(C) then return false end
  local b = false
  pcall(function()
    if Game and Game.IsAI then b = Game:IsAI(C) end
    if not b then
      if C.bEnsure or C.bMEnsure then b = true
      elseif C.bIsAI then b = true
      elseif C.PlayerState and C.PlayerState.bPSEnsure then b = true end
    end
  end)
  return b
end
function ESP.GetPlayerKey(C)
  local k
  pcall(function() if C.GetPlayerKey then k = C:GetPlayerKey() end end)
  if k == nil then pcall(function() k = C.PlayerKey end) end
  return tostring(k or C)
end
function ESP.GetHealthPct(C)
  if not ESPValid(C) then return 1.0 end
  local hp, mx
  pcall(function() hp = C.Health end)
  if type(hp) ~= "number" then pcall(function() hp = C.HP end) end
  pcall(function() mx = C.MaxHealth end)
  if type(mx) ~= "number" then pcall(function() mx = C.MaxHP end) end
  if type(hp) ~= "number" then return 1.0 end
  if type(mx) ~= "number" or mx <= 0 then mx = 100 end
  local p = hp / mx
  if p ~= p then return 1.0 end
  return math.max(0, math.min(1, p))
end
local function NormalizeName(v)
  if v == nil or v == false then return nil end
  local ok, t = pcall(tostring, v)
  if not ok or not t then return nil end
  t = t:gsub("^%s+", ""):gsub("%s+$", "")
  if t == "" or t == "nil" or t == "None" or t == "NULL" or t == "Unknown" then return nil end
  return t
end
function ESP.ResolveName(C, isBot)
  if isBot then return "Bot" end
  local name
  local function take(v) if not name then name = NormalizeName(v) end end
  pcall(function() if C.GetPlayerNameSafety then take(C:GetPlayerNameSafety()) end end)
  if not name then pcall(function() if C.GetPlayerName then take(C:GetPlayerName()) end end) end
  if not name then pcall(function() take(C.PlayerName) end) end
  if not name then pcall(function() take(C.NickName) end) end
  if not name then
    local ps
    pcall(function()
      if C.GetPlayerStateSafety then ps = C:GetPlayerStateSafety()
      elseif C.GetPlayerState then ps = C:GetPlayerState() end
    end)
    if not ESPValid(ps) then pcall(function() ps = C.PlayerState end) end
    if ESPValid(ps) then
      pcall(function() if ps.GetPlayerName then take(ps:GetPlayerName()) end end)
      if not name then pcall(function() take(ps.PlayerName) end) end
      if not name then pcall(function() take(ps.NickName) end) end
    end
  end
  return name or "Player"
end
function ESP.GetBonePos(C, bone)
  if not ESPValid(C) or not bone then return nil end
  local p
  pcall(function()
    if type(C.GetBonePos) == "function" then
      p = C:GetBonePos(bone, { X=0, Y=0, Z=0 })
    end
    if (not p or (p.X==0 and p.Y==0 and p.Z==0)) and type(C.GetSocketLocation)=="function" then
      p = C:GetSocketLocation(bone)
    end
    if (not p or (p.X==0 and p.Y==0 and p.Z==0)) and ESPValid(C.Mesh) and C.Mesh.GetSocketLocation then
      local mp = C.Mesh:GetSocketLocation(bone)
      if mp and not (mp.X==0 and mp.Y==0 and mp.Z==0) then p = mp end
    end
  end)
  return p
end
function ESP.GetCamLoc(pc)
  local loc
  pcall(function()
    if GameplayStaticsESP and GameplayStaticsESP.GetPlayerCameraManager then
      local m = GameplayStaticsESP.GetPlayerCameraManager(pc, 0)
      if ESPValid(m) and m.GetCameraLocation then loc = m:GetCameraLocation() end
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
function ESP.ActorLocation(C)
  if not ESPValid(C) then return nil end
  local loc
  pcall(function()
    if C.K2_GetActorLocation then loc = C:K2_GetActorLocation()
    elseif Game and Game.GetActorLocation then loc = Game:GetActorLocation(C) end
  end)
  return loc
end
function ESP.DistMeters(a, b)
  if not a or not b then return math.huge end
  local dx,dy,dz = a.X-b.X, a.Y-b.Y, a.Z-b.Z
  return math.sqrt(dx*dx+dy*dy+dz*dz) / 100.0
end

function ESP.IsBoneVisible(pc, camLoc, target, bonePos)
  if not ESPValid(pc) or not ESPValid(target) or not bonePos or not camLoc then return false end
  if not KismetSystemLibraryESP or not KismetSystemLibraryESP.LineTraceSingle then return true end
  local dx,dy,dz = bonePos.X-camLoc.X, bonePos.Y-camLoc.Y, bonePos.Z-camLoc.Z
  local d = math.sqrt(dx*dx+dy*dy+dz*dz)
  if d < 300 then return true end
  TraceStartPos.X = camLoc.X + (dx/d)*60
  TraceStartPos.Y = camLoc.Y + (dy/d)*60
  TraceStartPos.Z = camLoc.Z + (dz/d)*60
  local bVis = false
  pcall(function()
    local hit = KismetSystemLibraryESP.LineTraceSingle(
      pc, TraceStartPos, bonePos, 0, false, nil, 0, CachedHitResult, false)
    if hit then
      local ha
      if CachedHitResult then
        if type(CachedHitResult.GetActor) == "function" then ha = CachedHitResult:GetActor()
        elseif CachedHitResult.Actor then ha = CachedHitResult.Actor end
      end
      if ESPValid(ha) and ha == target then bVis = true end
    else
      bVis = true
    end
  end)
  return bVis
end

function ESP.IsVisible(key, pc, camLoc, C)
  local now = ESP.Now()
  local c = ESP.VisCache[key]
  if c and (now - (c.t or 0)) < CFG.VisInterval then return c.b end
  local bVis = true
  if ESPValid(C) and ESPValid(pc) and camLoc then
    local bp = ESP.GetBonePos(C, "head")
    if not bp or (bp.X==0 and bp.Y==0 and bp.Z==0) then
      bp = ESP.GetBonePos(C, "spine_03")
    end
    if bp and (bp.X~=0 or bp.Y~=0 or bp.Z~=0) then
      bVis = ESP.IsBoneVisible(pc, camLoc, C, bp)
    end
  end
  ESP.VisCache[key] = { b = bVis, t = now }
  return bVis
end

function ESP.GetVerticalBounds(C)
  if not ESPValid(C) then return nil, nil end
  local center, half
  local cap
  pcall(function()
    if C.GetCapsuleComponent then cap = C:GetCapsuleComponent()
    elseif C.CapsuleComponent then cap = C.CapsuleComponent end
  end)
  if cap and ESPValid(cap) then
    pcall(function()
      if cap.K2_GetComponentLocation then center = cap:K2_GetComponentLocation()
      elseif cap.GetComponentLocation then center = cap:GetComponentLocation() end
      if cap.GetScaledCapsuleHalfHeight then half = cap:GetScaledCapsuleHalfHeight()
      elseif cap.GetUnscaledCapsuleHalfHeight then half = cap:GetUnscaledCapsuleHalfHeight()
      elseif cap.CapsuleHalfHeight then half = cap.CapsuleHalfHeight end
    end)
  end
  if not center then pcall(function() if C.K2_GetActorLocation then center = C:K2_GetActorLocation() end end) end
  if not center then
    pcall(function() if Game and Game.GetActorLocation then center = Game:GetActorLocation(C) end end)
  end
  if not center then return nil, nil end
  if not half or half < 10 or half > 200 then
    half = 85
    pcall(function()
      if C.bIsCrouched then half = 60 end
      if C.IsProne and C:IsProne() then half = 25 end
    end)
  end
  return center, half
end
function ESP.GetHeadFeet(C)
  local center, half = ESP.GetVerticalBounds(C)
  if not center or not half then return nil, nil end
  return { X=center.X, Y=center.Y, Z=center.Z+half },
         { X=center.X, Y=center.Y, Z=center.Z-half }
end

function ESP.GetCanvas()
  if ESPValid(ESP.Canvas) then return ESP.Canvas end
  local root
  pcall(function()
    local T = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
    if T and T.GetMainControlBaseUI then root = T.GetMainControlBaseUI() end
  end)
  if not ESPValid(root) then return nil end
  local c
  pcall(function()
    if ESPValid(root.CanvasPanel_0) then c = root.CanvasPanel_0
    elseif ESPValid(root.CanvasPanel_42) then c = root.CanvasPanel_42 end
  end)
  if ESPValid(c) then ESP.Canvas = c return c end
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
        if p0 and p1 and tonumber(p1.X) and p1.X ~= p0.X and p1.Y ~= p0.Y then
          ESP.ScaleX = (p1.X-p0.X)/100
          ESP.ScaleY = (p1.Y-p0.Y)/100
          ESP.OffsetX, ESP.OffsetY = p0.X, p0.Y
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
    ESP.ScaleX = 1/s; ESP.ScaleY = 1/s; ESP.OffsetX = 0; ESP.OffsetY = 0
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
function ESP.Project(pc, world)
  if not pc or not world then return nil end
  local pix = ESPV2(0, 0)
  local ok = false
  pcall(function()
    local r = pc:ProjectWorldLocationToScreen(world, pix, true)
    ok = (r == true or r == 1 or (pix and (pix.X ~= 0 or pix.Y ~= 0)))
  end)
  if not ok then return nil end
  return ESPV2(pix.X*(ESP.ScaleX or 1)+ (ESP.OffsetX or 0),
               pix.Y*(ESP.ScaleY or 1)+ (ESP.OffsetY or 0)), pix
end
function ESP.CanvasCenterX(viewW)
  local cw
  pcall(function()
    local c = ESP.GetCanvas()
    if ESPValid(c) then
      local g = c:GetCachedGeometry()
      if g and g.GetLocalSize then
        local s = g:GetLocalSize()
        if s and tonumber(s.X) and s.X > 1 then cw = tonumber(s.X) end
      end
    end
  end)
  if tonumber(cw) and cw > 1 then return cw*0.5 end
  return (viewW*0.5)*(ESP.ScaleX or 1) + (ESP.OffsetX or 0)
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
    if w.SetShadowOffset then w:SetShadowOffset(ESPV2(1, 1)) end
    if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(C_BLACK) end
  end)
end
function ESP.SetTextColor(w, c)
  if not ESPValid(w) then return end
  pcall(function()
    if SlateColor then w:SetColorAndOpacity(SlateColor(c))
    else w:SetColorAndOpacity(c) end
  end)
end
function ESP.NewLine(color, z)
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local b
  pcall(function() b = CGame:NewObjectFromPath("/Script/UMG.Border", canvas) end)
  if not ESPValid(b) then return nil end
  pcall(function()
    b:SetBrushColor(color)
    b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    b:SetRenderTransformPivot(ESPV2(0, 0.5))
  end)
  local slot
  pcall(function() slot = canvas:AddChildToCanvas(b) end)
  if not slot then pcall(function() b:RemoveFromParent() end) return nil end
  pcall(function() slot:SetAutoSize(false); slot:SetZOrder(z or 30) end)
  return { Widget = b, Slot = slot }
end
function ESP.Hide(d)
  if d and ESPValid(d.Widget) and d.hidden ~= true then
    pcall(function() d.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    d.hidden = true
    d.lx1, d.ly1, d.lx2, d.ly2, d.th = nil, nil, nil, nil, nil
    d.bx, d.bt, d.bh = nil, nil, nil
  end
end
function ESP.Destroy(d)
  if not d then return end
  local w = d.Widget or d.Container
  if ESPValid(w) then pcall(function() w:RemoveFromParent() end) end
end
function ESP.DrawLine(d, x1, y1, x2, y2, thickness)
  if not d or not ESPValid(d.Widget) or not d.Slot then return false end
  if x1~=x1 or y1~=y1 or x2~=x2 or y2~=y2 then return false end
  x1, y1, x2, y2 = RND(x1), RND(y1), RND(x2), RND(y2)
  local dz = CFG.DeadZone
  if d.lx1 == x1 and d.ly1 == y1 and d.lx2 == x2 and d.ly2 == y2 and d.th == thickness then
    if d.hidden == true then
      pcall(function() d.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
      d.hidden = false
    end
    return true
  end
  local dx, dy = x2-x1, y2-y1
  local len = math.sqrt(dx*dx+dy*dy)
  if len < 1 then ESP.Hide(d) return false end
  local ang = math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx)
  ang = math.floor((ang * 180 / math.pi) * 10 + 0.5) / 10
  len = RND(len)
  local ok = pcall(function()
    d.Slot:SetPosition(ESPV2(x1, y1 - thickness*0.5))
    d.Slot:SetSize(ESPV2(len, thickness))
    d.Widget:SetRenderAngle(ang)
    d.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if ok then
    d.lx1, d.ly1, d.lx2, d.ly2, d.th = x1, y1, x2, y2, thickness
    d.hidden = false
  end
  return true
end
function ESP.SetBrush(d, color, key)
  if not d or not ESPValid(d.Widget) then return end
  if key and d.colorKey == key then return end
  pcall(function() d.Widget:SetBrushColor(color) end)
  if key then d.colorKey = key end
end

function ESP.EnsureHealthBg(key)
  local d = ESP.HealthBg[key]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(ESPMKC(0,0,0, CFG.SideBgAlpha), 31)
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
  local bg   = ESP.EnsureHealthBg(key)
  local fill = ESP.EnsureHealthFill(key)
  if not bg or not fill then return end
  local t = CFG.SideBarWidth
  w = math.max(1, tonumber(w) or 1)
  ESP.DrawLine(bg, x, y, x + w, y, t)
  pct = math.max(0, math.min(1, tonumber(pct) or 1))
  local bucket =
    (pct >= 0.7 and "g_" or pct >= 0.4 and "y_" or "r_") .. math.floor(pct*20+0.5)
  ESP.SetBrush(fill, HealthColor(pct), bucket)
  local fw = w * pct
  if fw < 1 then ESP.Hide(fill) return end
  ESP.DrawLine(fill, x, y, x + fw, y, t)
end

function ESP.EnsureSnap(key)
  local d = ESP.Lines[key]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(C_GREEN, 30)
  ESP.Lines[key] = d
  return d
end

function ESP.CreateInfo()
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local box, nName, nDist, nState
  pcall(function() box   = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
  pcall(function() nName = CGame:NewObjectFromPath("/Script/UMG.TextBlock",  box) end)
  pcall(function() nDist = CGame:NewObjectFromPath("/Script/UMG.TextBlock",  box) end)
  pcall(function() nState= CGame:NewObjectFromPath("/Script/UMG.TextBlock",  box) end)
  if not (ESPValid(box) and ESPValid(nName) and ESPValid(nDist) and ESPValid(nState)) then
    ESP.Destroy({ Widget = box }); return nil
  end
  pcall(function()
    nName:SetText("Player"); nDist:SetText("0m"); nState:SetText("Open")
    for _, w in ipairs({nName, nDist, nState}) do
      w:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      if w.SetJustification then w:SetJustification(1) end
    end
  end)
  ESP.SetTextColor(nName, C_WHITE)
  ESP.SetTextColor(nDist, C_WHITE)
  ESP.SetTextColor(nState, C_GREEN)
  ESP.SetFont(nName,  CFG.NameFontSize)
  ESP.SetFont(nDist,  CFG.DistFontSize)
  ESP.SetFont(nState, CFG.StateFontSize)
  local s0, s1, s2, ms
  pcall(function() s0 = box:AddChildToCanvas(nName)  end)
  pcall(function() s1 = box:AddChildToCanvas(nDist)  end)
  pcall(function() s2 = box:AddChildToCanvas(nState) end)
  pcall(function() ms = canvas:AddChildToCanvas(box) end)
  if not (s0 and s1 and s2 and ms) then ESP.Destroy({ Widget = box }) return nil end
  pcall(function()
    s0:SetAutoSize(false); s0:SetSize(ESPV2(100, 22)); s0:SetAlignment(ESPV2(0.5,0.5))
    s1:SetAutoSize(true);  s1:SetAlignment(ESPV2(0.5,0.5))
    s2:SetAutoSize(true);  s2:SetAlignment(ESPV2(0.5,0.5))
    ms:SetAutoSize(false); ms:SetZOrder(35)
  end)
  return { Container = box, Name = nName, Dist = nDist, State = nState,
           S0 = s0, S1 = s1, S2 = s2, Slot = ms }
end
function ESP.UpdateInfo(key, C, isBot, teamID, distM, bVis, headX, headY)
  local d = ESP.Infos[key]
  if not d or not ESPValid(d.Container) then
    ESP.Destroy(d); d = ESP.CreateInfo(); ESP.Infos[key] = d
  end
  if not d then return end
  if not d.CachedName then d.CachedName = ESP.ResolveName(C, isBot) end
  local name = isBot and "Bot" or d.CachedName
  local dl   = string.format("%dm", math.max(0, math.floor((tonumber(distM) or 0) + 0.5)))
  local st   = bVis and "Open" or "Close"
  pcall(function()
    if d.LastN ~= name then d.Name:SetText(name) d.LastN = name end
    if d.LastD ~= dl   then d.Dist:SetText(dl)   d.LastD = dl   end
    if d.LastS ~= st   then d.State:SetText(st)  d.LastS = st   end
    if bVis then ESP.SetTextColor(d.State, C_GREEN) else ESP.SetTextColor(d.State, C_RED) end
  end)
  local bx = RND(headX)
  local by = RND(headY - 18)
  pcall(function()
    d.Slot:SetPosition(ESPV2(bx, by))
    d.Slot:SetSize(ESPV2(100, 70))
    d.S0:SetPosition(ESPV2(0, 0))
    d.S1:SetPosition(ESPV2(50, 34))
    d.S2:SetPosition(ESPV2(50, 52))
    d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
end

function ESP.CreateCounter()
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local box, txt
  pcall(function() box = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
  pcall(function() txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock",  box) end)
  if not (ESPValid(box) and ESPValid(txt)) then ESP.Destroy({ Widget = box }) return nil end
  pcall(function()
    txt:SetText("Players: 0 | Bots: 0")
    txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    if txt.SetJustification then txt:SetJustification(1) end
  end)
  ESP.SetTextColor(txt, C_WHITE); ESP.SetFont(txt, CFG.CounterFontSize)
  local s0, ms
  pcall(function() s0 = box:AddChildToCanvas(txt) end)
  pcall(function() ms = canvas:AddChildToCanvas(box) end)
  if not (s0 and ms) then ESP.Destroy({ Widget = box }) return nil end
  pcall(function()
    s0:SetAutoSize(true); s0:SetAlignment(ESPV2(0.5,0.5)); s0:SetPosition(ESPV2(150, 14)); s0:SetZOrder(5)
    ms:SetAutoSize(false); ms:SetAlignment(ESPV2(0.5,0.0)); ms:SetSize(ESPV2(300, 28)); ms:SetZOrder(60)
  end)
  return { Container = box, Text = txt, Slot = ms }
end
function ESP.UpdateCounter(nP, nB, viewW)
  local d = ESP.Counter
  if not d or not ESPValid(d.Container) then
    ESP.Destroy(d); d = ESP.CreateCounter(); ESP.Counter = d
  end
  if not d then return nil end
  local label = string.format("Players: %d | Bots: %d", nP or 0, nB or 0)
  pcall(function() if d.Last ~= label then d.Text:SetText(label) d.Last = label end end)
  local cx = RND(ESP.CanvasCenterX(viewW))
  if d.px == nil or math.abs(d.px - cx) >= 1.0 then
    d.px = cx
    pcall(function()
      d.Slot:SetPosition(ESPV2(cx, CFG.TopTextY))
      d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
  else
    pcall(function() d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
  end
  return cx, CFG.SnapOriginY
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
  ESP.Destroy(ESP.HealthBg[key]);   ESP.HealthBg[key]   = nil
  ESP.Destroy(ESP.HealthFill[key]); ESP.HealthFill[key] = nil
  ESP.Destroy(ESP.Lines[key]);      ESP.Lines[key]      = nil
  ESP.Destroy(ESP.Infos[key]);      ESP.Infos[key]      = nil
  ESP.VisCache[key] = nil
end
function ESP.ResetWidgets()
  for _, d in pairs(ESP.Lines)      do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthBg)   do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthFill) do ESP.Destroy(d) end
  for _, d in pairs(ESP.Infos)      do ESP.Destroy(d) end
  if ESP.Counter then ESP.Destroy(ESP.Counter) end
  ESP.Lines, ESP.HealthBg, ESP.HealthFill, ESP.Infos = {}, {}, {}, {}
  ESP.VisCache, ESP.Counter, ESP.Canvas, ESP.EnemyCache = {}, nil, nil, {}
end

function ESP.Scan()
  local pc = ESP.GetController()
  local me = ESP.GetLocalCharacter()
  if not pc or not me then ESP.EnemyCache = {} return pc, 0, 0 end
  local myLoc = ESP.ActorLocation(me)
  if not myLoc then ESP.EnemyCache = {} return pc, 0, 0 end
  local myTeam = ESP.GetTeamID(me)
  local list, seen, nR, nB = {}, {}, 0, 0
  local maxSq = (CFG.MaxDistance * 100) * (CFG.MaxDistance * 100)
  for _, ch in pairs(ESP.GetAllCharacters()) do
    if ESPValid(ch) and ch ~= me and ESP.IsAlive(ch) then
      local loc = ESP.ActorLocation(ch)
      if loc then
        local dx, dy, dz = myLoc.X-loc.X, myLoc.Y-loc.Y, myLoc.Z-loc.Z
        local sq = dx*dx + dy*dy + dz*dz
        if sq <= maxSq then
          local key = ESP.GetPlayerKey(ch)
          if not seen[key] then
            local team = ESP.GetTeamID(ch)
            if myTeam == nil or team == nil or tostring(team) ~= tostring(myTeam) then
              seen[key] = true
              local isBot = ESP.IsBot(ch)
              if isBot then nB = nB + 1 else nR = nR + 1 end
              list[#list+1] = { Character = ch, Key = key, IsBot = isBot,
                                TeamID = team, Distance = math.sqrt(sq)/100.0 }
            end
          end
        end
      end
    end
  end
  table.sort(list, function(a,b) return a.Distance < b.Distance end)
  local trimmed = {}
  for i = 1, math.min(#list, CFG.MaxTracked) do trimmed[i] = list[i] end
  ESP.EnemyCache = trimmed
  return pc, nR, nB
end

function ESP.Update()
  if not ESP_Enabled then ESP.ResetWidgets() return end
  local world = ESP.World()
  if world ~= ESP.LastWorld then
    ESP.ResetWidgets()
    ESP.LastWorld = world
    ESP.LastScan, ESP.LastTransform = -999.0, -999.0
  end
  if not ESP.GetCanvas() then return end

  ESP._nowOverride = ESP.Now()
  local now = ESP._nowOverride

  local pc = ESP.GetController()
  if not pc then ESP._nowOverride = nil return end

  if (now - ESP.LastScan) >= ESP.ScanInterval then
    local _, r, b = ESP.Scan()
    ESP.LastScan = now
    ESP.RealCount, ESP.BotCount = r or 0, b or 0
  end

  if (now - ESP.LastTransform) >= ESP.TransformInterval then
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

  local originX, originY = ESP.UpdateCounter(ESP.RealCount or 0, ESP.BotCount or 0, vw)
  if not originX then ESP._nowOverride = nil return end
  local camLoc = ESP.GetCamLoc(pc)

  local active = {}
  for _, item in ipairs(ESP.EnemyCache) do
    local c, key = item.Character, item.Key
    if ESPValid(c) and ESP.IsAlive(c) then
      local head, feet = ESP.GetHeadFeet(c)
      if head and feet then
        local hs, hpix = ESP.Project(pc, head)
        local fs, fpix = ESP.Project(pc, feet)
        if hs and fs and hpix and fpix then
          local m = CFG.ScreenMargin
          local on = hpix.X > -m and hpix.X < vw + m
                 and hpix.Y > -m and hpix.Y < vh + m
                 and fpix.X > -m and fpix.X < vw + m
                 and fpix.Y > -m and fpix.Y < vh + m
          if on then
            local H = fs.Y - hs.Y
            if H >= CFG.BoxMinHeight and H <= vh * 1.5 then
              active[key] = true
              local W  = math.max(CFG.BoxMinWidth, math.min(CFG.BoxMaxWidth, H * CFG.BoxWidthFactor))
              local cx = (hs.X + fs.X) * 0.5
              local L, R = cx - W * 0.5, cx + W * 0.5
              ESP.UpdateHealthBar(key, ESP.GetHealthPct(c), L, hs.Y + 8.0, R - L)
              ESP.DrawLine(ESP.EnsureSnap(key), originX, originY, hs.X, hs.Y, CFG.SnapThickness)
              local bVis = ESP.IsVisible(key, pc, camLoc, c)
              ESP.UpdateInfo(key, c, item.IsBot, item.TeamID, item.Distance, bVis, hs.X, hs.Y)
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

  for k in pairs(ESP.Lines)    do if not active[k] then ESP.HideTarget(k) end end
  for k in pairs(ESP.Infos)    do if not active[k] then ESP.HideTarget(k) end end

  local cacheKeys = {}
  for _, it in ipairs(ESP.EnemyCache) do cacheKeys[it.Key] = true end
  for k in pairs(ESP.VisCache) do
    if not cacheKeys[k] and not active[k] then ESP.ReleaseTarget(k) end
  end

  ESP._nowOverride = nil
end

function ESP.Tick()
  pcall(ESP.Update)
end

function ESP.AttachTimers()
  local pc = ESP.GetController()
  if not ESPValid(pc) or not pc.AddGameTimer then
    if not ESP._TimerRetry then
      ESP._TimerRetry = true
      pcall(function()
        require("timer").SetGameTimer(2.0, false, function()
          ESP._TimerRetry = false
          ESP.AttachTimers()
        end)
      end)
    end
    return
  end
  if ESP._TimerPC == pc and ESP._TimerHooked then return end
  ESP._TimerPC = pc
  ESP._TimerHooked = true
  pc:AddGameTimer(ESP.LightInterval, true, function()
    if ESP.bActive then pcall(ESP.Tick) end
  end)
end

function ESP.Start()
  ESP.bActive = true
  ESP.AttachTimers()
  pcall(ESP.Update)
end

_G.ESP = ESP
_G.PlayerMapMarker = ESP

local function ESPLater(sec, fn)
  local tk
  pcall(function() tk = require("common.time_ticker") end)
  if tk and tk.AddTimerOnce then pcall(function() tk.AddTimerOnce(sec, fn) end) return end
  pcall(function() require("timer").SetGameTimer(sec, false, fn) end)
end

local _startedPC = nil
local function ESPStartAll()
  local pc
  pcall(function()
    if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
  end)
  if not ESPValid(pc) then pc = ESP.GetController() end
  if not ESPValid(pc) then return end
  if pc ~= _startedPC then
    _startedPC   = pc
    ESP._TimerPC = nil
    ESP._TimerHooked = false
    ESP.Start()
  else
    ESP.AttachTimers()
  end
end

pcall(ESPStartAll)
if not _G.__ESPLookTickStarted then
  _G.__ESPLookTickStarted = true
  pcall(ESP.AttachTimers)
end

--=============================================================================
-- Class registration (unchanged)
--=============================================================================
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
