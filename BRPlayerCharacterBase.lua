-- ═══════════════════════════════════════════════════════════════════════════
-- BRPlayerCharacterBase.lua — FINAL MERGED
--
--  • Hardened base character (every risky call wrapped in pcall / nil-checks)
--  • Inline EnemyPlayerMarkerFeature — simple ESP, wall-piercing, throttled
--
-- ⚠ ESP is for private servers / dev maps ONLY. Do NOT deploy on live
--   competitive matches — violates standard game ToS.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── RPC definitions ────────────────────────────────────────────────────────
local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue    = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox             = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction            = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction       = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall  = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }

-- ─── Imports ────────────────────────────────────────────────────────────────
local ENetRole                     = import("ENetRole")
local EPawnState                   = import("EPawnState")
local ECharacterHideMovementAcive  = import("ECharacterHideMovementAcive")
local ESpecialMovementType         = import("ESpecialMovementType")
local ESpiderSwingMoveState        = import("ESpiderSwingMoveState")
local ESurviveWeaponPropSlot       = import("ESurviveWeaponPropSlot")
local EParachuteState              = import("EParachuteState")
local EMovementMode                = import("EMovementMode")
local EStateType                   = import("EStateType")
local ESTEPoseState                = import("ESTEPoseState")
local EGameModeType                = import("EGameModeType")
local STExtraGameStateBase         = import("STExtraGameStateBase")
local UKismetSystemLibrary         = import("KismetSystemLibrary")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")

local GameplayData                 = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools                = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local MatchModeIds                 = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")
local class                        = require("class")
local CCharacterBase               = require("GameLua.GameCore.Framework.CharacterBase")

-- ═══════════════════════════════════════════════════════════════════════════
-- BRPlayerCharacterBase — character methods (hardened)
-- ═══════════════════════════════════════════════════════════════════════════
function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  if self.__super and self.__super._PostConstruct then
    self.__super._PostConstruct(self)
  end
  pcall(function() self:InitAddSpecialMoveInfo() end)
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  if self.__super and self.__super.ReceiveBeginPlay then
    self.__super.ReceiveBeginPlay(self)
  end

  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)

  -- CheckFallingDistanceComponent
  pcall(function()
    if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
      local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
      if slua.isValid(CheckFallingDistanceComponent_C)
         and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
        print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
        Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
      end
    end
  end)

  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end

  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled",  self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = { "bCanSelfRescue" }
    }, self.CharacterAttrChangeEvent, self)
  end

  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    pcall(function() GameplayData.AddCharacter(self.Object) end)

    -- ▼ ESP init (own character only)
    if self.InitEnemyPlayerMarkerFeature and self._espEnabled == nil then
      pcall(function() self:InitEnemyPlayerMarkerFeature() end)
    end
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE,
      { [1] = "FinishedState" }, self.HandleFinishedState, self)
    self:AddControlEvent(self, "OnPawnRespawnDelegate", self.OnRespawnRehideCheck, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  if self.__super and self.__super.CharacterAttrChangeEvent then
    self.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  end
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    pcall(function()
      local uPlayerController = self:GetPlayerControllerSafety()
      if slua.isValid(uPlayerController) then
        uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
      end
    end)
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  if PawnState == EPawnState.SwitchPP then
    pcall(function()
      local uPlayerController = self:GetPlayerControllerSafety()
      if slua.isValid(uPlayerController) then
        uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
      end
    end)
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    pcall(function()
      local Mask = import("EDynamicSimpleQueryConfigDisableMask")
      if Mask then
        self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(Mask.Bit0, true)
      end
    end)
  end
end

function BRPlayerCharacterBase:OnRespawnRehideCheck()
  if not self:GetEnsure() then return end
  self:AddGameTimer(0.5, false, function()
    if not slua.isValid(self.Object) then return end
    if self:HasState(EPawnState.InPlane) then
      pcall(function()
        self:SetCharacterHideInGame(true, true, true, 1, ECharacterHideMovementAcive.Normal)
      end)
      print(bWriteLog and "BRPlayerCharacterBase:OnRespawnRehideCheck re-hide AI on plane, PlayerKey:", self.PlayerKey)
    end
  end)
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID   = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode
                          or GameModeType == EGameModeType.EFourInOneGameMode
                          or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy   = not MatchModeIds[GameModeID]
    print(bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:",
      GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  if self.__super and self.__super.LuaHandleParachuteStateChanged then
    self.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  end
  if Client then return end
  pcall(function()
    local pc = self:GetPlayerControllerSafety()
    if not (slua.isValid(pc) and pc.CheckParachuteOpenFeature) then return end
    local feat = pc.CheckParachuteOpenFeature
    if NewParachuteState == EParachuteState.PS_Opening then
      if feat.SatrtCheckShowParachuteCloseUI then feat:SatrtCheckShowParachuteCloseUI() end
    elseif NewParachuteState == EParachuteState.PS_None then
      if feat.RecoverParachuteOpenParam then feat:RecoverParachuteOpenParam() end
      if feat.ClearTimerAndState      then feat:ClearTimerAndState()      end
    end
  end)
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    pcall(function() self:HandleOnLanded(-1) end)
  end
  if Client then return end
  pcall(function()
    local pc = self:GetPlayerControllerSafety()
    if not (slua.isValid(pc) and pc.CheckParachuteOpenFeature) then return end
    local feat = pc.CheckParachuteOpenFeature
    if feat.ClearTimerAndState then feat:ClearTimerAndState() end
    if feat.ResetCheckShowUI   then feat:ResetCheckShowUI()   end
  end)
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  if self.__super and self.__super.ReceiveEndPlay then
    self.__super.ReceiveEndPlay(self, EndPlayReason)
  end
  if Client then
    self._espEnabled = false
    pcall(function() GameplayData.RemoveCharacter(self.Object) end)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local ok, result = pcall(function()
    local uGameState = GameplayData:GetGameState()
    if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
      return uGameState.GameModeType == EGameModeType.EWarGameMode
    end
    return false
  end)
  if ok then return result end
  return false
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then pcall(function() self:ResetMeshRelativeLocationAndRotation() end) end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then pcall(function() self:ResetMeshRelativeLocationAndRotation() end) end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    pcall(function()
      self:ResetMeshRelativeLocationAndRotation()
      GameplayData.RemoveCharacter(self.Object)
    end)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    pcall(function()
      self:ResetMeshRelativeLocationAndRotation()
      GameplayData.AddCharacter(self.Object)
    end)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if not (Game:IsValid(self.Object) and Game:IsValid(self.Mesh)) then return end
  pcall(function()
    local rot = FRotator(0, -90, 0)
    local loc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(rot, false, nil, false)
    end
    self:CacheInitialMeshOffset(loc, rot)
    local rr = self.Mesh.RelativeRotation
    local br = Game:QuatToRotator(self.BaseRotationOffset)
    print(bWriteLog and string.format(
      "%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ",
      Game:GetPlainName(self.Object),
      tostring(rr.Pitch), tostring(rr.Yaw), tostring(rr.Roll),
      tostring(br.Pitch), tostring(br.Yaw), tostring(br.Roll)))
  end)
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  pcall(function()
    if Game:IsValid(self.STCharacterMovement)
       and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming
       and self:CheckBaseIsMoveable() then
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
  end)
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  pcall(function()
    if not UKismetSystemLibrary.IsDedicatedServer(self) then return end
    local pc = self:GetPlayerControllerSafety()
    if not slua.isValid(pc) then return end
    local av = self.CharacterAvatarComp2_BP
    if not slua.isValid(av) then return end

    local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
    local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(pc, av)
    if not changedVehicleId then return end

    local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
    local UAvatarUtils             = import("AvatarUtils")
    if not (ESTExtraVehicleShapeType and UAvatarUtils) then return end

    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local ps = self:GetPlayerStateSafety()
      if slua.isValid(ps) then
        print(bWriteLog and "BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
        ps:AddGeneralCount(468, 1, false)
      end
    end
  end)
end

function BRPlayerCharacterBase:ParachuteJump()
  local ok, err = pcall(function()
    local pc = self:GetControllerSafety()
    if not slua.isValid(pc) then return end

    if not self:GetEnsure() then
      if pc:GetCurrentStateType() ~= EStateType.State_ParachuteJump
         and pc:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        pc:ReInitParachuteItem()
        pc:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      local loc = self:K2_GetActorLocation()
      if loc then
        print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(loc:ToString()))
      end
    end
  end)
  if not ok then print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump crashed:", tostring(err)) end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then return end
  print(bWriteLog and string.format(
    "BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s",
    tostring(uCharacter), tostring(uOldMovementBase), tostring(uNewMovementBase)))
  pcall(function()
    local crane = self:GetMedievalCraneFromBase(uNewMovementBase)
    if crane and crane.AddCharacter then
      crane:AddCharacter(self.Object)
    else
      crane = self:GetMedievalCraneFromBase(uOldMovementBase)
      if crane and crane.RemoveCharacter then crane:RemoveCharacter(self.Object) end
    end
  end)
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then return end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) or not Lifter.AddCharacter then return end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local ok, result = pcall(function()
    local ps = self:GetPlayerStateSafety()
    if not slua.isValid(ps) then return false end
    if ps.CanUseFlaregun == false and self:IsLocallyControlled() then
      local pc = self:GetPlayerControllerSafety()
      if slua.isValid(pc) then pc:DisplayGameTipWithMsgID(48532) end
    end
    return not ps.CanUseFlaregun
  end)
  if ok then return result end
  return false
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  pcall(function() self:HandleNearDeathGiveupRescue() end)
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  pcall(function()
    local comp = self.NearDeatchComponent
    if self:IsNearDeath() and slua.isValid(comp) and self.bCanNearDeathGiveup == true then
      local ps = self:GetPlayerStateSafety()
      if slua.isValid(ps) then ps:AddGeneralCount(1613, 1, false) end
      comp:TriggerGotoDieExplictly(self.Object)
    end
  end)
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  if type(actionId) ~= "number" then return end
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. actionId: " .. tostring(actionId))
  local ok = pcall(function()
    if USTExtraBlueprintFunctionLibrary
       and USTExtraBlueprintFunctionLibrary.IsDevelopment
       and USTExtraBlueprintFunctionLibrary.IsDevelopment() then
      log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment")
      self:MulticastRPC_GmPlayAction(actionId)
    end
  end)
  if not ok then log(bWriteLog and "RPC_Server_GmPlayAction failed") end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client or type(actionId) ~= "number" then return end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. actionId: " .. tostring(actionId))
  pcall(function()
    local emoteComp = self:GetPlayEmoteComponent()
    if not slua.isValid(emoteComp) then return end

    local LogFilter = require("common.log_filter")
    LogFilter.SetLogTreeEnable(true)

    local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
    if not animCfg or not animCfg.Path then return end

    local EmoteHandleAsset = slua.loadObject(animCfg.Path)
    if not EmoteHandleAsset then return end

    local assetsArray = slua.Array(UEnums.EPropertyClass.Struct,
      import("/Script/CoreUObject.SoftObjectPath"))
    local handle = EmoteHandleAsset()
    if not handle then return end

    emoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
    log(bWriteLog and "  assetsArray:Num(): " .. tostring(assetsArray:Num()))

    local tb = FuncUtil.LuaArrayToTable(assetsArray)
    local asset_util = require("common.asset_util")
    asset_util.GetAssetsArrayAsyncParallel(tb, function()
      pcall(function() emoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0) end)
    end)
  end)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bShould)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bShould))
  pcall(function()
    if slua.isValid(self.ParachuteComponent) then
      self.ParachuteComponent.bServerSyncShouldCheckPassWall = bShould and true or false
    end
  end)
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  if self.Super and self.Super.OnPlayerEnterCarryBoxState then
    self.Super:OnPlayerEnterCarryBoxState()
  end
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format(
    "DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s",
    tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  pcall(function()
    if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
  end)
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  if self.Super and self.Super.OnPlayerLeaveCarryBoxState then
    self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format(
    "DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s",
    tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  pcall(function()
    if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt) end
  end)
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if not slua.isValid(uInDeadBox) then return end
  local PlayerTombBox = import("/Script/ShadowTrackerExtra.PlayerTombBox")
  if not PlayerTombBox or not Game:IsClassOf(uInDeadBox, PlayerTombBox) then return end
  if not self.CarryDeadBoxFeature then return end
  pcall(function() self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox) end)
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  if type(AreaID) ~= "number" then return end
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
  pcall(function()
    if self:HasState(EPawnState.SpecialSuit) then
      self:TriggerEntrySkillWithID(4301101, true)
      print(bWriteLog and string.format(
        "BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)",
        tostring(self.PlayerKey)))
    end
  end)
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  if self.Super and self.Super.SwitchCameraToParachuteOpening then
    self.Super:SwitchCameraToParachuteOpening()
  end
  pcall(function()
    if self.ParachuteFormation
       and self.ParachuteFormation.ShouldApplyFormationCamera
       and self.ParachuteFormation:ShouldApplyFormationCamera() then
      self.ParachuteFormation:OverlayFormationCameraParams()
    end
  end)
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  if self.Super and self.Super.SwitchCameraToParachuteFalling then
    self.Super:SwitchCameraToParachuteFalling()
  end
  pcall(function()
    if self.ParachuteFormation
       and self.ParachuteFormation.ShouldApplyFormationCamera
       and self.ParachuteFormation:ShouldApplyFormationCamera() then
      self.ParachuteFormation:OverlayFormationCameraParams()
    end
  end)
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  if self.Super and self.Super.SwitchCameraToNormal then
    self.Super:SwitchCameraToNormal()
  end
  pcall(function()
    if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
      self.ParachuteFormation:OnLandingClearFormationCamera()
    end
  end)
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  -- AttachToOther blacklist
  if self:HasState(EPawnState.AttachToOther) then
    local blocked = pcall(function()
      local Weapon = self:GetWeaponBySlot(Slot)
      if not slua.isValid(Weapon) then return false end
      local WeaponID = Weapon:GetWeaponID()
      local cfg = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if cfg and cfg.CheckIsWeaponInBlackList and cfg.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local pc = self:GetPlayerControllerSafety()
        if Client and slua.isValid(pc) and pc.Role == ENetRole.ROLE_AutonomousProxy then
          pc:DisplayGameTipWithMsgID(47306)
        end
        return true
      end
      return false
    end)
    if blocked == true then return false end
  end

  -- SpiderSwing block
  if self:HasState(EPawnState.WebSwing)
     and Slot ~= ESurviveWeaponPropSlot.SWPS_None
     and slua.isValid(self.STCharacterMovement) then
    local blocked = pcall(function()
      local obj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(
        ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
      if not slua.isValid(obj) then return false end
      local st = obj:GetCurMoveState()
      if st == ESpiderSwingMoveState.Launching or st == ESpiderSwingMoveState.Swinging then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked by SpiderSwing state: " .. tostring(st))
        return true
      end
      return false
    end)
    if blocked == true then return false end
  end

  if self.Super and self.Super.SwitchWeaponCheck then
    return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
  end
  return false
end

-- ─── Emote resolution ───────────────────────────────────────────────────────
local VICTORY_DANCE_FX_MAP = { [12219601] = 22010089 }
local PublishRegionMacros  = require("client.slua.config.ClientMacros.PublishRegionMacros")
local isFitVersion         = PublishRegionMacros.IsFITVersion()

local function ResolveEmoteResID(ItemID)
  if type(ItemID) ~= "number" then return ItemID end
  local FxID = VICTORY_DANCE_FX_MAP[ItemID]
  if not FxID or FxID == ItemID then return ItemID end
  local ok, resolved = pcall(function()
    local model_util = require("client.common.model_util")
    local FxBPID = model_util.GetBPID(FxID)
    local ResID  = ItemID
    if FxBPID and 0 < FxBPID and model_util.IsBattleItemHandleExist("Emote", FxBPID, false, false) then
      ResID = FxID
    end
    print(bWriteLog and string.format(
      "BRPlayerCharacterBase 11 ResolveEmoteResID ItemID:%s, FxID:%s, FxBPID:%s, ResID:%s",
      tostring(ItemID), tostring(FxID), tostring(FxBPID), tostring(ResID)))
    if isFitVersion and ResID == 12219601 then
      print(bWriteLog and "BRPlayerCharacterBase ResolveEmoteResID 12219601 -> 12222069")
      return 12222069
    end
    return ResID
  end)
  if ok then return resolved end
  return ItemID
end

function BRPlayerCharacterBase:GetEmoteHandlePath(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super and self.Super.GetEmoteHandlePath then return self.Super:GetEmoteHandlePath(ResID) end
  local ok, path = pcall(function()
    local model_util = require("client.common.model_util")
    local BPID = model_util.GetBPID(ResID)
    if not BPID or BPID <= 0 then return "" end
    return model_util.GetPath("Emote", BPID, false, false) or ""
  end)
  if ok then return path end
  return ""
end

function BRPlayerCharacterBase:GetEmoteHandle(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super and self.Super.GetEmoteHandle then return self.Super:GetEmoteHandle(ResID) end
  local ok, handle = pcall(function()
    local model_util = require("client.common.model_util")
    local BPID = model_util.GetBPID(ResID)
    if not BPID or BPID <= 0 then return nil end
    local H = model_util.GetClass("Emote", BPID, false, false)
    if not H then return nil end
    local h = H()
    if not slua.isValid(h) then return nil end
    return h
  end)
  if ok then return handle end
  return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EnemyPlayerMarkerFeature — SIMPLE ESP (inline)
--
-- Renders "Name [dist] HP:%" over each enemy. Pierces walls via
-- DrawDebugString. Throttled at 10 Hz, closest-first, one bad enemy can
-- never kill the loop.
-- ═══════════════════════════════════════════════════════════════════════════
local EnemyPlayerMarkerFeature = class("EnemyPlayerMarkerFeature")

local ESP_CFG = {
  MaxDistance    = 100000,  -- 1000 m (UE units)
  MinDistance    = 600,
  UpdateInterval = 0.1,     -- 10 Hz
  DrawName       = true,
  DrawDistance   = true,
  DrawHealth     = true,
  DrawLine       = false,
  TextColor      = { R = 1.0, G = 0.3, B = 0.3, A = 1.0 },
  LineColorR     = 255,
  LineColorG     = 40,
  LineColorB     = 40,
  LineDuration   = 0.12,
  TextDuration   = 0.12,
  HeadOffsetZ    = 100,
}

function EnemyPlayerMarkerFeature:InitEnemyPlayerMarkerFeature()
  if not Client then return end
  if not self:IsLocallyControlled() then return end
  if self._espEnabled ~= nil then return end -- already initialised

  self._espEnabled  = true
  self._espEnemies  = {}
  self._espCfg      = ESP_CFG

  -- Repeating update — safe if AddGameTimer(delay, bLoop, cb)
  self:AddGameTimer(ESP_CFG.UpdateInterval, true, function()
    if not self._espEnabled then return end
    if not slua.isValid(self.Object) then self._espEnabled = false; return end
    pcall(function() self:_ESP_Update() end)
  end)

  print(bWriteLog and "[ESP] EnemyPlayerMarkerFeature initialized")
end

function EnemyPlayerMarkerFeature:_ESP_Update()
  self:_ESP_RefreshList()
  self:_ESP_RenderMarkers()
  self:_ESP_PublishToHUD()  -- optional: HUD classes can read pc.EnemyESPList
end

function EnemyPlayerMarkerFeature:_ESP_RefreshList()
  local myLoc = self:K2_GetActorLocation()
  if not myLoc then self._espEnemies = {}; return end

  local myTeamID = self:_ESP_GetMyTeamID()
  local list     = {}

  local chars = nil
  pcall(function() chars = GameplayData:GetAllCharacters() end)
  if not chars then self._espEnemies = list; return end

  for _, char in pairs(chars) do
    if slua.isValid(char) and char ~= self.Object then
      local isEnemyOk, isEnemy = pcall(self._ESP_IsEnemy, self, char, myTeamID)
      if isEnemyOk and isEnemy then
        local loc = char:K2_GetActorLocation()
        if loc then
          local d = (loc - myLoc):Size()
          if d >= ESP_CFG.MinDistance and d <= ESP_CFG.MaxDistance then
            table.insert(list, { character = char, location = loc, distance = d })
          end
        end
      end
    end
  end

  table.sort(list, function(a, b) return a.distance < b.distance end)
  self._espEnemies = list
end

function EnemyPlayerMarkerFeature:_ESP_GetMyTeamID()
  local ok, team = pcall(function()
    local ps = self:GetPlayerStateSafety()
    if slua.isValid(ps) then return ps:GetTeamID() end
  end)
  if ok then return team end
  return nil
end

function EnemyPlayerMarkerFeature:_ESP_IsEnemy(otherChar, myTeamID)
  if not slua.isValid(otherChar) then return false end
  local hp = otherChar:GetAttrValue("Health")
  if hp and hp <= 0 then return false end

  local ok, pc = pcall(function() return otherChar:IsPlayerControlled() end)
  if not ok or not pc then return false end

  if myTeamID then
    local psOk, ps = pcall(function() return otherChar:GetPlayerStateSafety() end)
    if psOk and slua.isValid(ps) then
      local tOk, team = pcall(function() return ps:GetTeamID() end)
      if tOk and team and team == myTeamID then return false end
    end
  end
  return true
end

function EnemyPlayerMarkerFeature:_ESP_RenderMarkers()
  local myLoc = self:K2_GetActorLocation()
  for _, enemy in ipairs(self._espEnemies) do
    if slua.isValid(enemy.character) then
      pcall(function() self:_ESP_RenderOne(enemy, myLoc) end)
    end
  end
end

function EnemyPlayerMarkerFeature:_ESP_BuildLabel(enemy)
  local char = enemy.character
  local parts = {}

  if ESP_CFG.DrawName then
    local name = "Enemy"
    local psOk, ps = pcall(function() return char:GetPlayerStateSafety() end)
    if psOk and slua.isValid(ps) then
      local nOk, n = pcall(function() return ps:GetPlayerNameSafety() end)
      if nOk and type(n) == "string" and n ~= "" then name = n end
    end
    table.insert(parts, name)
  end

  if ESP_CFG.DrawDistance then
    table.insert(parts, string.format("[%dm]", math.floor(enemy.distance / 100)))
  end

  if ESP_CFG.DrawHealth then
    local hp    = char:GetAttrValue("Health") or 0
    local maxHp = char:GetAttrValue("MaxHealth") or 100
    if maxHp and maxHp > 0 then
      local pct = math.max(0, math.min(100, math.floor(hp / maxHp * 100)))
      table.insert(parts, string.format("HP:%d%%", pct))
    end
  end

  return table.concat(parts, " ")
end

function EnemyPlayerMarkerFeature:_ESP_RenderOne(enemy, myLoc)
  local head  = enemy.location + FVector(0, 0, ESP_CFG.HeadOffsetZ)
  local label = self:_ESP_BuildLabel(enemy)
  if label == "" then return end

  -- Primary: world-space (pierces walls)
  local drawOk = pcall(function()
    UKismetSystemLibrary.DrawDebugString(
      self, head, label, nil, 1.0, ESP_CFG.TextColor, ESP_CFG.TextDuration)
  end)

  -- Fallback: screen-space via HUD
  if not drawOk then
    pcall(function() self:_ESP_DrawScreenSpace(head, label) end)
  end

  if ESP_CFG.DrawLine and myLoc then
    pcall(function()
      UKismetSystemLibrary.DrawDebugLine(
        self, myLoc, head,
        ESP_CFG.LineColorR, ESP_CFG.LineColorG, ESP_CFG.LineColorB,
        ESP_CFG.LineDuration)
    end)
  end
end

function EnemyPlayerMarkerFeature:_ESP_DrawScreenSpace(worldLoc, text)
  local pc = self:GetPlayerControllerSafety()
  if not slua.isValid(pc) then return end

  local projOk, sp = pcall(function() return pc:ProjectWorldLocationToScreen(worldLoc, false) end)
  if not projOk or not sp then return end

  local hud = pc:GetHUD()
  if not slua.isValid(hud) or not hud.DrawText then return end

  pcall(function()
    hud:DrawText(text, sp.X, sp.Y, ESP_CFG.TextColor, nil, 1.0)
  end)
end

-- Publish enemy list to PC so any HUD extension can draw it wall-piercing
function EnemyPlayerMarkerFeature:_ESP_PublishToHUD()
  local pc = self:GetPlayerControllerSafety()
  if not slua.isValid(pc) then return end

  local out = {}
  for _, e in ipairs(self._espEnemies) do
    if slua.isValid(e.character) then
      out[#out + 1] = {
        actor    = e.character,
        location = e.location,
        distance = e.distance,
        label    = self:_ESP_BuildLabel(e),
      }
    end
  end
  pcall(function() pc.EnemyESPList = out end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Class registration + DeclareFeature
-- ═══════════════════════════════════════════════════════════════════════════
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)

return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  { SkyTransition                  = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature" },
  { CarryDeadBoxFeature            = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature" },
  { SpecialSuitFeature             = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature" },
  { TeleportPawnFeature            = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature" },
  { LifterControl                  = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature" },
  { FinalKillEffect                = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature" },
  { CampFeature                    = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature" },
  { BuildAircraftVehicleFeature    = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature" },
  { UnifiedBuildVehicleFeature     = "GameLua.Mod.BaseMod.GamePlay.Feature.UnifiedBuildVehicleFeature" },
  { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },
  { ParachuteFormation             = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature" },
  { ParachuteSprint                = "GameLua.Mod.BaseMod.GamePlay.Feature.Parachute.ParachuteSprintFeature" },
  { GeneralShowSpotFeature         = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature" },
  { FPPAnimMonitor                 = "GameLua.Mod.BaseMod.GamePlay.Feature.Player.FPPAnimMonitorFeature" },
  -- ▼ Inline class object (not a string path)
  { EnemyPlayerMarkerFeature       = EnemyPlayerMarkerFeature },
}, "BRPlayerCharacterBase")
