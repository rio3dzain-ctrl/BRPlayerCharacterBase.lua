local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
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
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode
      or GameModeType == EGameModeType.EFourInOneGameMode
      or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
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
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
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
      Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll),
      tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement)
    and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking
    and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord() end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  if not UKismetSystemLibrary.IsDedicatedServer(self) then return end
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
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump
        and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
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
  if not slua.isValid(Lifter) or not Lifter.AddCharacter then return end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then return false end
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
  if not Client then return end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then return end
  require("common.log_filter").SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then return end
  local EmoteHandleAsset = slua.loadObject(animCfg.Path)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  require("common.asset_util").GetAssetsArrayAsyncParallel(tb, function()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s",
    tostring(self.Role), tostring(self.PlayerKey), tostring(self:GetPlayerNameSafety())))
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s",
    tostring(self.Role), tostring(self.PlayerKey), tostring(self:GetPlayerNameSafety()), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt) end
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

-- ================================================================
-- ESP  (Crash-Proof + 60 FPS Optimized)
-- ================================================================
local ESP_Enabled = true

-- ═══ Cached requires — CRITICAL FIX: require() was inside hot loop ═══
local InGameUITools_C   = nil
local GameplayData_C    = nil
local TimeTicker_C      = nil
pcall(function() InGameUITools_C = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
pcall(function() GameplayData_C  = require("GameLua.GameCore.Data.GameplayData")          end)
pcall(function() TimeTicker_C    = require("common.time_ticker")                          end)

-- ═══ Type imports (cached once) ═══
local FVector2D          = _G.FVector2D or import("Vector2D")
local FLinearColor       = _G.FLinearColor or import("LinearColor")
local SlateBlueprintLibrary   = nil
local WidgetLayoutLibrary     = nil
local SlateColor              = nil
local GameplayStaticsESP      = nil
local KismetSystemLibraryESP  = nil
local HitResultClassESP       = nil
pcall(function() SlateBlueprintLibrary    = import("SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary      = import("WidgetLayoutLibrary") end)
pcall(function() SlateColor               = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
pcall(function() GameplayStaticsESP       = import("GameplayStatics") end)
pcall(function() KismetSystemLibraryESP   = import("KismetSystemLibrary") end)
pcall(function() HitResultClassESP        = import("HitResult") end)

-- ═══ atan2 compatibility (math.atan2 removed in Lua 5.3+) ═══
local _atan2 = math.atan2 or math.atan

local TraceStartPos   = { X = 0, Y = 0, Z = 0 }
local CachedHitResult = nil
pcall(function() CachedHitResult = HitResultClassESP and HitResultClassESP() or {} end)

local function ESPValid(obj)
  if obj == nil then return false end
  local ok, v = pcall(slua.isValid, obj)
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
  MaxDistance = 50000, RenderTrackingDistance = 50000,
  MaxTracked = 64,                -- was 128 → 2× fewer projections & traces
  ScreenMargin = 500, TopTextY = 6.0, SnapOriginY = 0.0,
  SnapThickness = 1.8, CornerThickness = 2.2, CornerLen = 0.28,
  CornerMin = 6, CornerMax = 28, BoxMinWidth = 22, BoxMaxWidth = 320,
  BoxMinHeight = 1, BoxWidthFactor = 0.62, WidthScale = 1.22,
  HeadExtra = 0.06, FootExtra = 0.02, SideBarWidth = 3.5, SideBarGap = 5.0,
  SideBgAlpha = 0.55, MarkGap = 8.0, MarkW = 15.0, MarkH = 10.0,
  MarkGapV = 6.0, MarkThickness = 2.4, NameFontSize = 15, DistFontSize = 13,
  StateFontSize = 13, TextGap = 1.0, CounterFontSize = 17,
  CounterW = 300.0, CounterH = 28.0, DeadZone = 0.5,
  -- ═══ OPTIMIZED TIMINGS — big FPS win ═══
  VisInterval        = 0.12,      -- 8 Hz visibility trace (was 16 Hz)
  ScanInterval       = 0.10,      -- 10 Hz enemy refresh (was 30 Hz)
  TransformInterval  = 1.0,       -- 1 Hz canvas transform refresh
  LightInterval      = 0.016667,  -- 60 FPS render tick
  SizeHyst = 2.0,
  PosEpsilon = 2.0,               -- skip widget writes if pos shift < 2 px
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
local TEAM_HASH_CACHE = {}

local function TeamColor(teamID, isBot, fallbackKey)
  local n = tonumber(teamID)
  if n then
    if n ~= n then n = 0 end                     -- CRASH FIX: NaN guard
    n = math.abs(math.floor(n))
  else
    local key = tostring(fallbackKey or "unknown")
    n = TEAM_HASH_CACHE[key]
    if not n then
      local h = 0
      for i = 1, #key do h = (h * 31 + string.byte(key, i)) % 2147483647 end
      n = h
      TEAM_HASH_CACHE[key] = n
    end
  end
  return TEAM_COLORS[(n % #TEAM_COLORS) + 1] or C_WHITE   -- CRASH FIX: never nil
end

local function RND(v)
  if v ~= v then return 0 end
  return math.floor(v + 0.5)
end
local function Lerp(a, b, t) return a + (b - a) * t end

-- ═══ Health color buckets — safe index [0..40] ═══
local HEALTH_COLOR_BUCKETS = {}
local function _buildHealthColor(pct)
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
for i = 0, 40 do HEALTH_COLOR_BUCKETS[i] = _buildHealthColor(i / 40) end

local function HealthColorBucket(pct)
  pct = tonumber(pct) or 1.0
  if pct ~= pct then pct = 1.0 end
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
  local i = math.floor(pct * 40 + 0.5)
  if i < 0 then i = 0 elseif i > 40 then i = 40 end
  return i
end

local ESP = {
  Canvas = nil, CanvasGeoW = nil,
  Lines = {}, Corners = {}, HealthBg = {}, HealthFill = {},
  Marks = {}, Infos = {}, Counter = nil,
  EnemyCache = {}, VisCache = {},
  ScaleX = 1.0, ScaleY = 1.0, OffsetX = 0.0, OffsetY = 0.0,
  ViewW = 1920, ViewH = 1080,
  LastScan = -999.0, LastTransform = -999.0, LastWorld = nil,
  bActive = false, _now = 0,
  _pc = nil, _me = nil, _world = nil,
}

-- ═════════ World / Time / Controller ═════════
function ESP.GetGameplayData()
  return GameplayData_C
end

function ESP.World()
  local w = ESP._world
  if w and ESPValid(w) then return w end
  w = nil
  pcall(function() w = slua and slua.getWorld and slua.getWorld() end)
  ESP._world = w
  return w
end

function ESP.Now()
  local w = ESP._world
  if w and GameplayStaticsESP and GameplayStaticsESP.GetRealTimeSeconds then
    local ok, t = pcall(function() return GameplayStaticsESP.GetRealTimeSeconds(w) end)
    if ok and t then return t end
  end
  if os and os.clock then return os.clock() end
  return 0.0
end

function ESP.GetController()
  local pc = ESP._pc
  if ESPValid(pc) then return pc end
  pc = nil
  pcall(function()
    local GDP = GameplayData_C
    if GDP and GDP.GetPlayerController then pc = GDP.GetPlayerController() end
  end)
  if not ESPValid(pc) then
    pcall(function() if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end end)
  end
  ESP._pc = ESPValid(pc) and pc or nil
  return ESP._pc
end

function ESP.GetLocalCharacter()
  local c = ESP._me
  if ESPValid(c) then return c end
  c = nil
  pcall(function()
    local GDP = GameplayData_C
    if GDP then
      if GDP.GetPlayerCharacter then c = GDP.GetPlayerCharacter() end
      if not ESPValid(c) and GDP.GetLocalCharacter then c = GDP.GetLocalCharacter() end
    end
  end)
  if not ESPValid(c) then
    local pc = ESP.GetController()
    pcall(function() if pc and pc.GetPawn then c = pc:GetPawn() end end)
  end
  ESP._me = ESPValid(c) and c or nil
  return ESP._me
end

-- ═══ Character list cache (100ms) — simpler, single pass ═══
function ESP.GetAllCharacters()
  local now = ESP._now
  local cache = ESP._charsCache
  if cache and (now - (ESP._charsCacheTime or 0)) < 0.1 then return cache end
  local AllChars = {}
  local seen = {}
  local function merge(chars)
    if not chars then return end
    for _, ch in pairs(chars) do
      if ch and ESPValid(ch) and not seen[ch] then
        seen[ch] = true
        local pk = nil
        pcall(function() if ch.GetPlayerKey then pk = ch:GetPlayerKey() end end)
        if pk == nil then pk = ch.PlayerKey end
        if pk == nil then pk = tostring(ch) end
        AllChars[pk] = ch
      end
    end
  end
  pcall(function() if Game and Game.GetAllPlayerPawns then merge(Game:GetAllPlayerPawns()) end end)
  pcall(function() if GameplayData_C and GameplayData_C.GetAllCharacters then merge(GameplayData_C:GetAllCharacters()) end end)
  ESP._charsCache = AllChars
  ESP._charsCacheTime = now
  return AllChars
end

function ESP.GetMyPlayerKey()
  local k = ESP._myKey
  if k ~= nil then return k end
  local pc = ESP.GetController()
  if not ESPValid(pc) then return nil end
  pcall(function()
    if pc.GetPlayerKey then k = pc:GetPlayerKey()
    elseif pc.PlayerState and pc.PlayerState.PlayerKey then k = pc.PlayerState.PlayerKey end
  end)
  ESP._myKey = k
  return k
end

function ESP.GetTeamID(Character)
  if not ESPValid(Character) then return nil end
  local id = nil
  pcall(function() if Character.GetTeamID then id = Character:GetTeamID() end end)
  if id == nil then id = Character.TeamID end
  if id == nil then
    local ps = nil
    pcall(function()
      if Character.GetPlayerStateSafety then ps = Character:GetPlayerStateSafety()
      elseif Character.GetPlayerState then ps = Character:GetPlayerState() end
    end)
    if not ESPValid(ps) then ps = Character.PlayerState end
    if ESPValid(ps) then
      pcall(function() if ps.GetTeamID then id = ps:GetTeamID() end end)
      if id == nil then id = ps.TeamID end
    end
  end
  return id
end

function ESP.IsAlive(Character)
  if not ESPValid(Character) then return false end
  local alive = nil
  pcall(function() if Character.IsAlive then alive = Character:IsAlive() end end)
  if type(alive) == "boolean" then return alive end
  local hp = Character.Health or Character.HP
  if type(hp) == "number" then return hp > 0 end
  return true
end

function ESP.IsBot(Character)
  if not ESPValid(Character) then return false end
  if Character.bIsAI == true then return true end
  if Character.bEnsure == true or Character.bMEnsure == true then return true end
  if Character.PlayerState and Character.PlayerState.bPSEnsure == true then return true end
  local ctrl = Character.Controller
  if ctrl then
    if ctrl.IsMLAI == true or ctrl.FakePlayerBornType == 1 then return true end
  end
  return false
end

function ESP.GetPlayerKey(Character)
  local key = nil
  pcall(function() if Character.GetPlayerKey then key = Character:GetPlayerKey() end end)
  if key == nil then key = Character.PlayerKey end
  return tostring(key or Character)
end

function ESP.GetHealthPct(Character)
  if not ESPValid(Character) then return 1.0 end
  local hp = Character.Health
  if type(hp) ~= "number" then hp = Character.HP end
  local maxhp = Character.MaxHealth
  if type(maxhp) ~= "number" then maxhp = Character.MaxHP end
  if type(hp) ~= "number" then return 1.0 end
  if type(maxhp) ~= "number" or maxhp <= 0 then maxhp = 100 end
  local pct = hp / maxhp
  if pct ~= pct then return 1.0 end
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
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
  if not name then pcall(function() if Character.GetPlayerName then take(Character:GetPlayerName()) end end) end
  if not name then take(Character.PlayerName) end
  if not name then take(Character.NickName) end
  if not name then
    local ps = nil
    pcall(function()
      if Character.GetPlayerStateSafety then ps = Character:GetPlayerStateSafety()
      elseif Character.GetPlayerState then ps = Character:GetPlayerState() end
    end)
    if not ESPValid(ps) then ps = Character.PlayerState end
    if ESPValid(ps) then
      pcall(function() if ps.GetPlayerName then take(ps:GetPlayerName()) end end)
      if not name then take(ps.PlayerName) end
      if not name then take(ps.PlayerNamePrivate) end
      if not name then take(ps.NickName) end
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
  if not KismetSystemLibraryESP or not KismetSystemLibraryESP.LineTraceSingle then return true end
  if not camLoc or not bonePos then return true end
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
      if ESPValid(hitActor) and hitActor == target then bVis = true end
    else
      bVis = true
    end
  end)
  return bVis
end

function ESP.IsVisible(key, pc, camLoc, Character)
  local now = ESP._now
  local cached = ESP.VisCache[key]
  if cached and (now - cached.t) < CFG.VisInterval then return cached.b end
  local bVis = false
  if ESPValid(Character) and ESPValid(pc) and camLoc then
    local bp = ESP.GetBonePos(Character, "head")
    if bp and (bp.X ~= 0 or bp.Y ~= 0 or bp.Z ~= 0) then
      bVis = ESP.IsBoneVisible(pc, camLoc, Character, bp)
    else
      bVis = true
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
  local capsule = Character.CapsuleComponent
  if not capsule and Character.GetCapsuleComponent then
    pcall(function() capsule = Character:GetCapsuleComponent() end)
  end
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
  if not center then return nil, nil end
  if not halfHeight or halfHeight < 10 or halfHeight > 200 then
    halfHeight = 85
    if Character.bIsCrouched then halfHeight = 60 end
    if Character.IsProne then
      pcall(function() if Character:IsProne() then halfHeight = 25 end end)
    end
  end
  return center, halfHeight
end

function ESP.GetHeadFeet(Character)
  local center, half = ESP.GetVerticalBounds(Character)
  if not center or not half then return nil, nil end
  return { X = center.X, Y = center.Y, Z = center.Z + half },
         { X = center.X, Y = center.Y, Z = center.Z - half }
end

-- ═══ Canvas (cached, single lookup on miss) ═══
function ESP.GetCanvas()
  if ESPValid(ESP.Canvas) then return ESP.Canvas end
  local root = nil
  if InGameUITools_C and InGameUITools_C.GetMainControlBaseUI then
    pcall(function() root = InGameUITools_C.GetMainControlBaseUI() end)
  end
  if not ESPValid(root) then return nil end
  local canvas = nil
  pcall(function()
    if ESPValid(root.CanvasPanel_0) then canvas = root.CanvasPanel_0
    elseif ESPValid(root.CanvasPanel_42) then canvas = root.CanvasPanel_42 end
  end)
  if ESPValid(canvas) then
    ESP.Canvas = canvas
    ESP.CanvasGeoW = nil
    return canvas
  end
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
        if p0 and p1 and tonumber(p0.X) and tonumber(p1.X)
          and p1.X ~= p0.X and p1.Y ~= p0.Y then
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
    ok = (res == true or res == 1)
  end)
  if not ok or not pix or type(pix.X) ~= "number" or type(pix.Y) ~= "number" then
    return nil
  end
  return ESPV2(pix.X * ESP.ScaleX + ESP.OffsetX, pix.Y * ESP.ScaleY + ESP.OffsetY), pix
end

function ESP.GetCanvasWidth()
  if ESP.CanvasGeoW and ESP.CanvasGeoW > 1 then return ESP.CanvasGeoW end
  local canvas = ESP.GetCanvas()
  if not ESPValid(canvas) then return nil end
  local cw = nil
  pcall(function()
    local geo = canvas:GetCachedGeometry()
    if geo and geo.GetLocalSize then
      local s = geo:GetLocalSize()
      if s and tonumber(s.X) and s.X > 1 then cw = tonumber(s.X) end
    end
  end)
  ESP.CanvasGeoW = cw
  return cw
end

function ESP.SnapOrigin(pc, viewW)
  local cw = ESP.GetCanvasWidth()
  local cx
  if cw and cw > 1 then
    cx = cw * 0.5
  else
    cx = (viewW * 0.5) * ESP.ScaleX + ESP.OffsetX
  end
  return ESPV2(cx, CFG.SnapOriginY)
end

function ESP.CanvasCenterX(viewW)
  local cw = ESP.GetCanvasWidth()
  if cw and cw > 1 then return cw * 0.5 end
  return (viewW * 0.5) * ESP.ScaleX + ESP.OffsetX
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

-- CRASH FIX: pass color struct directly; SlateColor(class) would error
function ESP.SetTextColor(w, color)
  if not ESPValid(w) or not color then return end
  pcall(function() w:SetColorAndOpacity(color) end)
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
  local dz = CFG.DeadZone
  if data.lx1 and data.th == thickness then
    if math.abs(data.lx1 - x1) < dz and math.abs(data.ly1 - y1) < dz
      and math.abs(data.lx2 - x2) < dz and math.abs(data.ly2 - y2) < dz then
      if data.hidden ~= true then return true end
    end
  end
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then ESP.Hide(data) return false end
  local angle = _atan2(dy, dx) * 180.0 / math.pi
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

function ESP.Hide(data)
  if data and ESPValid(data.Widget) and data.hidden ~= true then
    pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    data.hidden = true
    data.lx1, data.ly1, data.lx2, data.ly2, data.th = nil, nil, nil, nil, nil
  end
end

function ESP.SetBrush(data, color, colorKey)
  if not data or not ESPValid(data.Widget) or not color then return end  -- nil-color crash guard
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

function ESP.UpdateCounter(nPlayers, nBots, pc, viewW)
  local d = ESP.Counter
  if not d or not ESPValid(d.Container) then
    ESP.Destroy(d)
    d = ESP.CreateCounter()
    ESP.Counter = d
  end
  if not d then return nil end
  local label = string.format("Players: %d | Bots: %d", nPlayers or 0, nBots or 0)
  if d.Last ~= label then
    pcall(function() d.Text:SetText(label) end)
    d.Last = label
  end
  local cx = RND(ESP.CanvasCenterX(viewW))
  if d.px == nil or math.abs(d.px - cx) >= 1.0 then
    d.px = cx
    pcall(function()
      d.Slot:SetPosition(ESPV2(cx, CFG.TopTextY))
      d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
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
    ESP.Destroy({ Widget = container }); return nil
  end
  pcall(function()
    bSlot:SetAutoSize(false) bSlot:SetSize(ESPV2(120.0, 22.0))
    bSlot:SetAlignment(ESPV2(0.5, 0.5)) bSlot:SetZOrder(34)
    nSlot:SetAutoSize(false) nSlot:SetSize(ESPV2(120.0, 22.0))
    nSlot:SetAlignment(ESPV2(0.5, 0.5)) nSlot:SetZOrder(36)
    s2:SetAutoSize(true) s2:SetAlignment(ESPV2(0.5, 0.5)) s2:SetZOrder(36)
    s3:SetAutoSize(true) s3:SetAlignment(ESPV2(0.5, 0.5)) s3:SetZOrder(36)
    ms:SetAutoSize(false) ms:SetZOrder(35)
  end)
  return { Container = container, TeamBox = teamBox, Name = tName, Dist = tDist, State = tState,
           S0 = bSlot, S1 = nSlot, S2 = s2, S3 = s3, Slot = ms }
end

-- CRASH FIX: all SetText/SetBrushColor wrapped in pcall + epsilon-based skip
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
  if isBot and name ~= "Bot" then name = "Bot" d.CachedName = "Bot" end

  local bx  = RND(headX)
  local by  = RND(headY - 18.0)
  local dm  = math.floor((tonumber(distM) or 0) + 0.5)

  -- Wider fast-path (epsilon px) — avoids widget layout churn on tiny camera jitter
  local px_d = d._lx and math.abs(d._lx - bx) or 9999
  local py_d = d._ly and math.abs(d._ly - by) or 9999
  if px_d < CFG.PosEpsilon and py_d < CFG.PosEpsilon
     and d._dm == dm and d._lv == bVisible and d._ln == name
     and d._tID == teamID and d._tBot == isBot then
    return
  end

  local dl = dm .. "m"
  local st = bVisible and "Open" or "Close"
  local teamColor = TeamColor(teamID, isBot, key)

  if d.LastN ~= name then pcall(function() d.Name:SetText(name) end) d.LastN = name end
  if d.LastD ~= dl   then pcall(function() d.Dist:SetText(dl) end)   d.LastD = dl   end
  if d.LastS ~= st   then pcall(function() d.State:SetText(st) end)  d.LastS = st   end
  if d._tID ~= teamID or d._tBot ~= isBot then
    pcall(function() d.TeamBox:SetBrushColor(teamColor) end)
    d._tID, d._tBot = teamID, isBot
  end
  ESP.SetTextColor(d.State, bVisible and C_GREEN or C_RED)

  pcall(function()
    d.Slot:SetPosition(ESPV2(bx, by))
    d.Slot:SetSize(ESPV2(100.0, 70.0))
    d.S0:SetPosition(ESPV2(0.0, 0.0))
    d.S0:SetSize(ESPV2(100.0, 22.0))
    d.S1:SetPosition(ESPV2(0.0, 0.0))
    d.S1:SetSize(ESPV2(100.0, 22.0))
    d.S2:SetPosition(ESPV2(50.0, 34.0))
    d.S3:SetPosition(ESPV2(50.0, 52.0))
    d.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)

  d._lx, d._ly, d._dm, d._lv, d._ln = bx, by, dm, bVisible, name
end

function ESP.EnsureHealthBg(key)
  local d = ESP.HealthBg[key]
  if d and ESPValid(d.Widget) then return d end
  d = ESP.NewLine(ESPMKC(0.0, 0.0, 0.0, CFG.SideBgAlpha), 31)
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
  local thickness = CFG.SideBarWidth
  w = math.max(1, tonumber(w) or 1)
  ESP.DrawLine(bg, x, y, x + w, y, thickness)
  local bucket = HealthColorBucket(pct)
  ESP.SetBrush(fill, HEALTH_COLOR_BUCKETS[bucket], bucket)
  if bucket <= 0 then ESP.Hide(fill) return end
  local fw = w * (bucket / 40)
  if fw < 1 then ESP.Hide(fill) return end
  ESP.DrawLine(fill, x, y, x + fw, y, thickness)
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
    inf._lx = inf._ly = inf._dm = inf._lv = inf._ln = nil
  end
end

function ESP.ReleaseTarget(key)
  local c = ESP.Corners[key]
  if c then for i = 1, 8 do ESP.Destroy(c[i]) end end
  ESP.Corners[key] = nil
  ESP.Destroy(ESP.HealthBg[key])   ESP.HealthBg[key] = nil
  ESP.Destroy(ESP.HealthFill[key]) ESP.HealthFill[key] = nil
  local m = ESP.Marks[key]
  if m then for i = 1, 4 do ESP.Destroy(m[i]) end end
  ESP.Marks[key] = nil
  ESP.Destroy(ESP.Lines[key]) ESP.Lines[key] = nil
  ESP.Destroy(ESP.Infos[key]) ESP.Infos[key] = nil
  ESP.VisCache[key] = nil
end

function ESP.ResetWidgets()
  for _, d in pairs(ESP.Lines)     do ESP.Destroy(d) end
  for _, t in pairs(ESP.Corners)   do for _, d in pairs(t) do ESP.Destroy(d) end end
  for _, d in pairs(ESP.HealthBg)  do ESP.Destroy(d) end
  for _, d in pairs(ESP.HealthFill)do ESP.Destroy(d) end
  for _, t in pairs(ESP.Marks)     do for _, d in pairs(t) do ESP.Destroy(d) end end
  for _, d in pairs(ESP.Infos)     do ESP.Destroy(d) end
  ESP.Lines, ESP.Corners, ESP.HealthBg, ESP.HealthFill, ESP.Marks, ESP.Infos = {}, {}, {}, {}, {}, {}
  ESP.VisCache = {}
  if ESP.Counter then ESP.Destroy(ESP.Counter) end
  ESP.Counter, ESP.Canvas, ESP.CanvasGeoW = nil, nil, nil
  ESP.EnemyCache = {}
  ESP._charsCache = nil
end

-- ═══ Scan (10 Hz — was 30 Hz) ═══
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
  for _, ch in pairs(pawns) do
    if ESPValid(ch) and ch ~= me and ESP.IsAlive(ch) then
      local key = ESP.GetPlayerKey(ch)
      if not seen[key] then
        local team = ESP.GetTeamID(ch)
        if myTeam == nil or team == nil or tostring(team) ~= tostring(myTeam) then
          local loc = ESP.ActorLocation(ch)
          local dm  = ESP.DistMeters(myLoc, loc)
          seen[key] = true
          local isBot = ESP.IsBot(ch)
          if isBot then nBot = nBot + 1 else nReal = nReal + 1 end
          list[#list + 1] = { Character = ch, Key = key, IsBot = isBot, TeamID = team, Distance = dm }
        end
      end
    end
  end
  if #list > CFG.MaxTracked then
    table.sort(list, function(a, b) return (a.Distance or 1e9) < (b.Distance or 1e9) end)
    while #list > CFG.MaxTracked do list[#list] = nil end
  end
  ESP.EnemyCache = list
  return pc, nReal, nBot
end

-- ═══ Main Update (60 Hz) ═══
function ESP.Update()
  if not ESP_Enabled then ESP.ResetWidgets() return end

  ESP.World()
  ESP._now = ESP.Now()
  local now = ESP._now

  if ESP.LastWorld ~= ESP._world then
    ESP.ResetWidgets()
    ESP.LastWorld   = ESP._world
    ESP.LastScan    = -999.0
    ESP.LastTransform = -999.0
    ESP._pc, ESP._me, ESP._myKey = nil, nil, nil
  end

  -- Single canvas fetch per frame (was 5–10×)
  local canvas = ESP.GetCanvas()
  if not canvas then return end

  if ESP._pc and not ESPValid(ESP._pc) then ESP._pc = nil end
  if ESP._me and not ESPValid(ESP._me) then ESP._me = nil end

  local pc = ESP.GetController()
  if not pc then return end

  if (now - ESP.LastScan) >= CFG.ScanInterval then
    local r, b
    pc, r, b = ESP.Scan()
    ESP.LastScan = now
    ESP.RealCount, ESP.BotCount = r or 0, b or 0
  end
  pc = pc or ESP.GetController()
  if not pc then return end

  if (now - ESP.LastTransform) >= CFG.TransformInterval then
    ESP.UpdateCanvasTransform(pc)
    ESP.CanvasGeoW = nil
    ESP.LastTransform = now
  end

  local vw, vh = ESP.Viewport(pc)
  local hyst = CFG.SizeHyst
  if math.abs(vw - ESP.ViewW) > hyst or math.abs(vh - ESP.ViewH) > hyst then
    ESP.ViewW, ESP.ViewH = vw, vh
  else
    vw, vh = ESP.ViewW, ESP.ViewH
  end

  local origin = ESP.UpdateCounter(ESP.RealCount or 0, ESP.BotCount or 0, pc, vw)
  if not origin then return end
  local camLoc = ESP.GetCamLoc(pc)

  local active = {}
  local margin = CFG.ScreenMargin
  for _, item in ipairs(ESP.EnemyCache) do
    local c = item.Character
    local key = item.Key
    if ESPValid(c) and ESP.IsAlive(c) then
      local head, feet = ESP.GetHeadFeet(c)
      if head and feet then
        local headS, headPix = ESP.Project(pc, head)
        local feetS, feetPix = ESP.Project(pc, feet)
        if headS and feetS and headPix and feetPix then
          local on = headPix.X > -margin and headPix.X < vw + margin
            and headPix.Y > -margin and headPix.Y < vh + margin
            and feetPix.X > -margin and feetPix.X < vw + margin
            and feetPix.Y > -margin and feetPix.Y < vh + margin
          if on then
            local H = feetS.Y - headS.Y
            if H >= CFG.BoxMinHeight and H <= vh * 1.5 then
              active[key] = true
              local W = H * CFG.BoxWidthFactor
              W = math.max(CFG.BoxMinWidth, math.min(CFG.BoxMaxWidth, W))
              local cx = (headS.X + feetS.X) * 0.5
              local L  = cx - W * 0.5
              local R  = cx + W * 0.5

              local corners = ESP.Corners[key]
              if corners then for i = 1, 8 do ESP.Hide(corners[i]) end end

              local pct = ESP.GetHealthPct(c)
              ESP.UpdateHealthBar(key, pct, L, headS.Y + 8.0, R - L)

              local marks = ESP.Marks[key]
              if marks then for i = 1, 4 do ESP.Hide(marks[i]) end end

              ESP.DrawLine(ESP.EnsureSnap(key), origin.X, origin.Y, headS.X, headS.Y, CFG.SnapThickness)

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
      else
        ESP.HideTarget(key)
      end
    end
  end

  -- ═══ Consolidated GC — one pass instead of 3 ═══
  local seenCache = {}
  for _, it in ipairs(ESP.EnemyCache) do seenCache[it.Key] = true end
  for k, v in pairs(ESP.Lines) do
    if not active[k] then ESP.HideTarget(k) end
  end
  for k in pairs(ESP.Infos) do
    if not active[k] then ESP.HideTarget(k) end
  end
  for k in pairs(ESP.Corners) do
    if not active[k] and not seenCache[k] then ESP.ReleaseTarget(k) end
  end
  for k in pairs(ESP.HealthBg) do
    if not seenCache[k] and not active[k] then ESP.ReleaseTarget(k) end
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
      ESP._TimerPC, ESP._TimerHooked = pc, true
      pc:AddGameTimer(CFG.LightInterval, true, function()
        if ESP.bActive then pcall(ESP.Update) end
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
  ESP.World()
  pcall(ESP.Update)
  ESP.AttachTimers()
end

_G.ESP = ESP
_G.PlayerMapMarker = ESP

local function ESPLater(sec, fn)
  if TimeTicker_C and TimeTicker_C.AddTimerOnce then
    pcall(function() TimeTicker_C.AddTimerOnce(sec, fn) end)
    return
  end
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
        ESP._TimerHooked, ESP._TimerPC = false, nil
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
