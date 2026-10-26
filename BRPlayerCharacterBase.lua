local BRPlayerCharacterBase = {}
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
local EXPIRY_TIMESTAMP = os.time({
  year = 2026,
  month = 12,
  day = 21,
  hour = 23,
  min = 59,
  sec = 0
})

function CheckExpiration()
  local now = os.time()
  local remaining = EXPIRY_TIMESTAMP - now
  if remaining <= 0 then
    _G._MOD_EXPIRED = true
    _G._MOD_REMAINING_SECONDS = 0
    return false
  end
  _G._MOD_EXPIRED = false
  _G._MOD_REMAINING_SECONDS = remaining
  return true
end

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

local _slua = rawget(_G, "slua")

local function Notify(msg)
  local s = "[MOHSINXFILES] " .. tostring(msg)
  pcall(function()
    print(s)
  end)
  pcall(function()
    local sh = import("ScriptHelperClient")
    if sh and sh.AddOnScreenDebugMessage then
      sh.AddOnScreenDebugMessage(s, -1, 3.0, {
        R = 1,
        G = 1,
        B = 0,
        A = 1
      }, {X = 1.2, Y = 1.2})
    end
  end)
end

local function Valid(obj)
  if not obj then
    return false
  end
  if _slua and _slua.isValid then
    local ok, v = pcall(_slua.isValid, obj)
    if not ok or not v then
      return false
    end
  end
  return true
end

local C_GREEN = {
  R = 0,
  G = 255,
  B = 0,
  A = 255
}
local C_RED = {
  R = 255,
  G = 0,
  B = 0,
  A = 255
}
local C_CYAN = {
  R = 0,
  G = 255,
  B = 255,
  A = 255
}
local C_YELLOW = {
  R = 255,
  G = 255,
  B = 0,
  A = 255
}
local C_WHITE = {
  R = 255,
  G = 255,
  B = 255,
  A = 255
}
local C_BLUE_TEXT = {
  R = 0,
  G = 200,
  B = 255,
  A = 255
}
local SCALE_COLOR_V2 = {
  R = 3,
  G = 3,
  B = 0,
  A = 0
}
local GLOBAL_BONE_LIST = {
  "head",
  "neck_01",
  "pelvis",
  "upperarm_r",
  "lowerarm_r",
  "hand_r",
  "upperarm_l",
  "lowerarm_l",
  "hand_l",
  "thigh_l",
  "calf_l",
  "foot_l",
  "thigh_r",
  "calf_r",
  "foot_r"
}
_G.LexusConfig = _G.LexusConfig or {
  FakeHWID = true,
  NoRecoilEnabled = false,
  RecoilReduction = 100,
  EspLoai6 = false,
  EspLoai7 = false,
  EspLoai9 = false,
  Esp7_VuKhi = true,
  Esp7_TuThe = true,
  Esp9_Count = true,
  Esp9_Name = true,
  Esp9_HP = true,
  Esp9_Team = true,
  Esp9_Weapon = true,
  Esp9_Distance = true,
  Esp9_Line = true,
  EspAntenna = false,
  EspOutline = false,
  OutlineThickness = 10,
  Esp3ShowName = true,
  Esp3ShowHP = true,
  ColorBodyNew = false,
  CustomAimbot = false,
  CustomAimbotClose = false,
  CustomMagicBullet = false,
  CustomHRecoil = false,
  CustomVRecoil = false,
  LessShake = false,
  Accuracy = false,
  Crosshair = false,
  GodMode = false,
  WeaponAimbot = false,
  AimTouchEnable = false,
  AimTouchHipfire = false,
  AimTouchHipIgKnock = false,
  AimTouchHipIgBot = false,
  AimTouchHipVisCheck = false,
  AimTouchSG = false,
  AimTouchSGAutoFire = false,
  AimTouchSGIgKnock = false,
  AimTouchSGIgBot = false,
  AimTouchSGVisCheck = false,
  AimTouchScopeAll = false,
  AimTouchScopeIgKnock = false,
  AimTouchScopeIgBot = false,
  AimTouchScopeVisCheck = false,
  AimTouchScopeSniper = false,
  AimTouchSniperIgKnock = false,
  AimTouchSniperIgBot = false,
  AimTouchSniperVisCheck = false,
  AimTouchMortar = false,
  IpadView = false,
  UnlockFPS = false,
  BugManEnable = false,
  FastCar = false,
  FastCarSpeed = 3000,
  WallVehicle = false,
  WhiteBody = false,
  BlackSky = false,
  RemoveFog = false,
  RemoveGrass = false,
  RemoveTrees = false,
  ModEmote = false,
  ModSkin = false,
  SkinDeadBox = false,
  SkinAttachment = false,
  KillMessage = false,
  KillCountUI = false,
  SkinOpenLink = false
}
_G.SHMenu = _G.SHMenu or {}
do
  local function log(m)
    print("[SRC HUB MENU] " .. tostring(m))
  end
  
  _G.SHMenuBridge = _G.SHMenuBridge or {}
  local B = _G.SHMenuBridge
  B.ReadKey = B.ReadKey or function(key, fallback)
    local c = _G.LexusConfig
    local d = _G.LexusState and _G.LexusState.CustomTextData
    if d and d[key] ~= nil then
      return d[key]
    end
    if c and c[key] ~= nil then
      return c[key]
    end
    return fallback
  end
  B.WriteToggle = B.WriteToggle or function(key, val)
    _G.LexusConfig = _G.LexusConfig or {}
    _G.LexusConfig[key] = val == 1 or val == true
    if _G.SHMenuSave then
      _G.SHMenuSave()
    end
  end
  B.WriteValue = B.WriteValue or function(key, val)
    _G.LexusState = _G.LexusState or {}
    _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {}
    _G.LexusState.CustomTextData[key] = val
    if _G.LexusConfig then
      _G.LexusConfig[key] = val
    end
    if _G.SHMenuSave then
      _G.SHMenuSave()
    end
  end
  
  local function GetConfigPaths(fileName)
    local p = {
      "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
      "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
      "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
      "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
      "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName
    }
    pcall(function()
      if os and os.getenv then
        local h = os.getenv("HOME")
        if h and h ~= "" then
          table.insert(p, 1, h .. "/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName)
        end
      end
    end)
    return p
  end
  
  local CFG = "MOHSINXFILESCheats.txt"
  local lastSave = ""
  
  local function SaveConfig()
    pcall(function()
      local data = [[
return {
LexusConfig = {
]]
      for k, v in pairs(_G.LexusConfig or {}) do
        data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
      end
      data = data .. [[
},
CustomTextData = {
]]
      if _G.LexusState and _G.LexusState.CustomTextData then
        for k, v in pairs(_G.LexusState.CustomTextData) do
          data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
        end
      end
      data = data .. [[
}
}]]
      if data == lastSave then
        return
      end
      lastSave = data
      for _, path in ipairs(GetConfigPaths(CFG)) do
        local f = io.open(path, "w")
        if f then
          f:write(data)
          f:close()
          break
        end
      end
    end)
  end
  
  function _G.SHMenuSave()
    if _G.SaveModSettings then
      _G.SaveModSettings()
    end
  end
  
  local FLC = import("LinearColor") or _G.FLinearColor
  local FV2 = import("Vector2D") or _G.FVector2D
  local FSlate = import("SlateColor") or _G.FSlateColor
  local FMargin = import("Margin") or _G.FMargin
  local FAnchors = import("Anchors") or _G.FAnchors
  FLC = FLC or function(r, g, b, a)
    return {
      R = r,
      G = g,
      B = b,
      A = a
    }
  end
  FV2 = FV2 or function(x, y)
    return {X = x, Y = y}
  end
  
  local function IV(o)
    return o and slua and slua.isValid and slua.isValid(o)
  end
  
  local C = {
    panel_bg = FLC(0.05, 0.06, 0.12, 0.96),
    panel_header = FLC(0.2, 0.05, 0.35, 0.99),
    panel_border = FLC(0.0, 0.95, 1.0, 1.0),
    panel_row = FLC(0.09, 0.1, 0.18, 0.92),
    text_white = FLC(1, 1, 1, 1),
    text_dark = FLC(0.95, 0.98, 1.0, 1.0),
    text_dim = FLC(0.6, 0.65, 0.85, 1.0),
    accent_gold = FLC(1.0, 0.8, 0.2, 1.0),
    accent_dark = FLC(0.15, 0.1, 0.28, 1.0),
    accent_cyan = FLC(0.0, 0.95, 1.0, 1.0),
    accent_purple = FLC(0.68, 0.3, 1.0, 1.0),
    accent_green = FLC(0.2, 1.0, 0.55, 1.0),
    accent_red = FLC(1.0, 0.25, 0.35, 1.0),
    accent_yellow = FLC(1.0, 0.9, 0.2, 1.0),
    toggle_on = FLC(0.2, 1.0, 0.55, 1.0),
    toggle_on_glow = FLC(0.2, 1.0, 0.55, 0.45),
    toggle_off = FLC(0.9, 0.2, 0.35, 1.0),
    toggle_knob = FLC(1.0, 1.0, 1.0, 1.0),
    slider_bg = FLC(0.14, 0.16, 0.26, 1.0),
    slider_fill = FLC(0.68, 0.3, 1.0, 1.0),
    slider_knob = FLC(0.0, 0.95, 1.0, 1.0),
    shadow = FLC(0, 0, 0, 0.55),
    transparent = FLC(0, 0, 0, 0.01),
    online_green = FLC(0.2, 1.0, 0.55, 1.0),
    white = FLC(1, 1, 1, 1)
  }
  local M_W, M_H = 620, 500
  local HEADER_H = 60
  local ROW_H = 40
  local COL_W = (M_W - 40) / 2
  local COL_GAP = 8
  local parentCanvas, bgPanel
  local _dragState = {
    active = false,
    offX = 0,
    offY = 0,
    lastX = 0,
    lastY = 0,
    moved = false
  }
  local floatBtn
  local isMenuOpen, menuBuilt = false, false
  local allWidgets = {}
  
  local function NewObject(path, parent)
    local o
    pcall(function()
      if CGame and CGame.NewObjectFromPath then
        o = CGame:NewObjectFromPath(path, parent)
      end
    end)
    return o
  end
  
  local function Layer(parent, x, y, w, h, color, z)
    local b = NewObject("/Script/UMG.Border", parent)
    if IV(b) then
      pcall(function()
        b:SetBrushColor(color)
      end)
      pcall(function()
        b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
      local slot = parent:AddChildToCanvas(b)
      if slot then
        slot:SetAutoSize(false)
        slot:SetPosition(FV2(x, y))
        slot:SetSize(FV2(w, h))
        slot:SetZOrder(z or 0)
      end
    end
    table.insert(allWidgets, b)
    return b
  end
  
  local function Text(parent, txt, x, y, size, color, z, ax, ay)
    local t = NewObject("/Script/UMG.TextBlock", parent)
    if IV(t) then
      pcall(function()
        t:SetText(txt)
      end)
      pcall(function()
        if FSlate then
          t:SetColorAndOpacity(FSlate(color))
        else
          t:SetColorAndOpacity(color)
        end
      end)
      pcall(function()
        if t.Font then
          local f = t.Font
          f.Size = size
          t.Font = f
        end
      end)
      pcall(function()
        t:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
      local slot = parent:AddChildToCanvas(t)
      if slot then
        slot:SetAutoSize(true)
        slot:SetAlignment(FV2(ax or 0.5, ay or 0.5))
        slot:SetPosition(FV2(x, y))
        slot:SetZOrder(z or 100)
      end
    end
    table.insert(allWidgets, t)
    return t
  end
  
  local function MakeBtn(parent, x, y, w, h, z, onClick)
    local btn = NewObject("/Script/UMG.Button", parent)
    if IV(btn) then
      pcall(function()
        btn:SetColorAndOpacity(C.transparent)
      end)
      pcall(function()
        btn:SetBackgroundColor(C.transparent)
      end)
      pcall(function()
        btn:SetWidgetVisibility(UEnums.ESlateVisibility.Visible)
      end)
      local slot = parent:AddChildToCanvas(btn)
      if slot then
        slot:SetAutoSize(false)
        slot:SetPosition(FV2(x, y))
        slot:SetSize(FV2(w, h))
        slot:SetZOrder(z or 900)
      end
      if onClick then
        pcall(function()
          if btn.OnClicked then
            btn.OnClicked:Add(function()
              pcall(onClick)
            end)
          end
        end)
      end
    end
    table.insert(allWidgets, btn)
    return btn
  end
  
  local function GetCanvas()
    local dedicated = _G.__SRCHUB_CANVAS
    if IV(dedicated) then
      local ok = true
      pcall(function()
        local p = dedicated:GetParent()
        if not p or not slua.isValid(p) then
          ok = false
        end
      end)
      if ok then
        return dedicated
      end
    end
    local base
    pcall(function()
      local T = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
      local M = T.GetMainControlBaseUI()
      if not M or not Game:IsValid(M) then
        return
      end
      if M.CanvasPanel_42 and Game:IsValid(M.CanvasPanel_42) then
        base = M.CanvasPanel_42
      elseif M.CanvasPanel_0 and Game:IsValid(M.CanvasPanel_0) then
        base = M.CanvasPanel_0
      end
    end)
    if not base then
      return nil
    end
    local newCanvas
    pcall(function()
      newCanvas = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", base)
    end)
    if not IV(newCanvas) then
      return base
    end
    local s
    pcall(function()
      s = base:AddChildToCanvas(newCanvas)
    end)
    if s then
      pcall(function()
        s:SetAutoSize(false)
        s:SetZOrder(50000)
        s:SetPosition(FV2(0, 0))
        local vw, vh = 1920, 1080
        pcall(function()
          local u = require("client.common.ui_util")
          if u and u.GetViewportSize then
            local vp = u:GetViewportSize()
            if vp and vp.X and vp.Y and vp.X > 0 then
              vw = vp.X
              vh = vp.Y
            end
          end
        end)
        s:SetSize(FV2(vw, vh))
      end)
    end
    _G.__SRCHUB_CANVAS = newCanvas
    return newCanvas
  end
  
  local function ShowMenu()
    if IV(bgPanel) then
      pcall(function()
        bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    end
  end
  
  local function HideMenu()
    if IV(bgPanel) then
      pcall(function()
        bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      end)
    end
  end
  
  local function MakeToggle(parent, x, y, w, label, key)
    local h = ROW_H
    Layer(parent, x, y, w, h, C.panel_row, 200)
    Layer(parent, x, y, 4, h, C.accent_cyan, 201)
    Text(parent, label, x + 14, y + h * 0.5, 13, C.text_dark, 300, 0, 0.5)
    local tW, tH = 44, 20
    local tX = x + w - tW - 10
    local tY = y + h * 0.5 - tH * 0.5
    local state = B.ReadKey(key, 0) == 1 or B.ReadKey(key, 0) == true
    if state then
      Layer(parent, tX - 3, tY - 3, tW + 6, tH + 6, C.toggle_on_glow, 298)
    end
    local track = Layer(parent, tX, tY, tW, tH, state and C.toggle_on or C.toggle_off, 300)
    local kSize = tH - 4
    local kX = state and tX + tW - kSize - 2 or tX + 2
    local knob = Layer(parent, kX, tY + 2, kSize, kSize, C.toggle_knob, 302)
    local stateText = Text(parent, state and "ON" or "OFF", state and tX + 6 or tX + tW - 6, y + h * 0.5, 9, C.white, 400, state and 0 or 1, 0.5)
    MakeBtn(parent, x, y, w, h, 900, function()
      local cur = B.ReadKey(key, 0)
      local newVal = (cur == 1 or cur == true) and 0 or 1
      B.WriteToggle(key, newVal)
      state = newVal == 1
      pcall(function()
        stateText:SetText(state and "ON" or "OFF")
        local s = stateText.Slot
        if s then
          s:SetPosition(FV2(state and tX + 6 or tX + tW - 6, y + h * 0.5))
          s:SetAlignment(FV2(state and 0 or 1, 0.5))
        end
        local col = state and C.accent_green or C.accent_red
        if FSlate then
          stateText:SetColorAndOpacity(FSlate(col))
        else
          stateText:SetColorAndOpacity(col)
        end
      end)
      pcall(function()
        track:SetBrushColor(state and C.toggle_on or C.toggle_off)
      end)
      local ks = knob.Slot
      if ks then
        local nkX = state and tX + tW - kSize - 2 or tX + 2
        ks:SetPosition(FV2(nkX, tY + 2))
      end
      if _G.SHMenuSave then
        _G.SHMenuSave()
      end
    end)
  end
  
  local function MakeStepper(parent, x, y, w, label, key, minV, maxV)
    local h = ROW_H
    Layer(parent, x, y, w, h, C.panel_row, 200)
    Layer(parent, x, y, 3, h, C.accent_purple, 201)
    Text(parent, label, x + 14, y + h * 0.5, 13, C.text_dark, 300, 0, 0.5)
    local isFOV = key == "IpadViewFOV"
    local curVal
    if isFOV then
      local raw = tonumber(_G.LexusState and _G.LexusState.CustomTextData and _G.LexusState.CustomTextData.IpadViewFOV or 120) or 120
      curVal = raw - 90
    else
      curVal = tonumber(B.ReadKey(key, minV)) or minV
    end
    curVal = math.floor(curVal)
    if minV > curVal then
      curVal = minV
    end
    if maxV < curVal then
      curVal = maxV
    end
    local valText = Text(parent, tostring(curVal), x + w - 14, y + h * 0.5, 13, C.accent_yellow, 301, 1, 0.5)
    local bw = 26
    local bx2 = x + w - bw - 40
    local bx1 = bx2 - bw - 6
    Layer(parent, bx1, y + h * 0.5 - 10, bw, 20, C.accent_red, 298)
    Text(parent, "-", bx1 + bw * 0.5, y + h * 0.5, 14, C.white, 400, 0.5, 0.5)
    MakeBtn(parent, bx1, y + h * 0.5 - 10, bw, 20, 900, function()
      local v
      if isFOV then
        local raw = tonumber(_G.LexusState and _G.LexusState.CustomTextData and _G.LexusState.CustomTextData.IpadViewFOV or 120) or 120
        v = raw - 90 - 1
      else
        v = tonumber(B.ReadKey(key, minV)) or minV
        v = math.floor(v) - 1
      end
      if v < minV then
        v = minV
      end
      if isFOV then
        _G.LexusState = _G.LexusState or {}
        _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {}
        _G.LexusState.CustomTextData.IpadViewFOV = 90 + v
        _G.LexusConfig = _G.LexusConfig or {}
        _G.LexusConfig.IpadViewFOV = 90 + v
      else
        B.WriteValue(key, v)
      end
      pcall(function()
        valText:SetText(tostring(v))
      end)
      if _G.SHMenuSave then
        _G.SHMenuSave()
      end
    end)
    Layer(parent, bx2, y + h * 0.5 - 10, bw, 20, C.accent_green, 298)
    Text(parent, "+", bx2 + bw * 0.5, y + h * 0.5, 14, C.white, 400, 0.5, 0.5)
    MakeBtn(parent, bx2, y + h * 0.5 - 10, bw, 20, 900, function()
      local v
      if isFOV then
        local raw = tonumber(_G.LexusState and _G.LexusState.CustomTextData and _G.LexusState.CustomTextData.IpadViewFOV or 120) or 120
        v = raw - 90 + 1
      else
        v = tonumber(B.ReadKey(key, minV)) or minV
        v = math.floor(v) + 1
      end
      if v > maxV then
        v = maxV
      end
      if v < minV then
        v = minV
      end
      if isFOV then
        _G.LexusState = _G.LexusState or {}
        _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {}
        _G.LexusState.CustomTextData.IpadViewFOV = 90 + v
        _G.LexusConfig = _G.LexusConfig or {}
        _G.LexusConfig.IpadViewFOV = 90 + v
      else
        B.WriteValue(key, v)
      end
      pcall(function()
        valText:SetText(tostring(v))
      end)
      if _G.SHMenuSave then
        _G.SHMenuSave()
      end
    end)
  end
  
  local _sectionRotator = 0
  
  local function SectionHeader(parent, x, y, w, label, colorKey)
    local h = 30
    local pal = {
      C.accent_cyan,
      C.accent_purple,
      C.accent_green,
      C.accent_red,
      C.accent_yellow,
      C.accent_gold
    }
    local col
    if colorKey == "purple" then
      col = C.accent_purple
    elseif colorKey == "green" then
      col = C.accent_green
    elseif colorKey == "red" then
      col = C.accent_red
    elseif colorKey == "yellow" then
      col = C.accent_yellow
    elseif colorKey == "blue" then
      col = C.accent_cyan
    else
      _sectionRotator = _sectionRotator + 1
      col = pal[(_sectionRotator - 1) % #pal + 1]
    end
    Layer(parent, x, y, w, h, C.panel_bg, 200)
    Layer(parent, x, y, 5, h, col, 201)
    Layer(parent, x + 5, y, w - 5, h, FLC(col.R * 0.18, col.G * 0.18, col.B * 0.18, 0.55), 201)
    Text(parent, label, x + 18, y + h * 0.5, 12, C.text_dark, 300, 0, 0.5)
    Layer(parent, x + 16, y + h - 1, w - 22, 1, col, 202)
  end
  
  local StackAIM_L = {
    {
      label = "Aimbot Jarak Jauh",
      key = "CustomAimbot"
    },
    {
      slider = true,
      label = "Kecepatan",
      key = "OuterSpeed",
      min = 1,
      max = 100
    },
    {
      slider = true,
      label = "Recoil Comp",
      key = "OuterRecoil",
      min = 0,
      max = 50
    },
    {
      label = "Aimbot Jarak Dekat",
      key = "CustomAimbotClose"
    },
    {
      slider = true,
      label = "Kecepatan",
      key = "InnerSpeed",
      min = 1,
      max = 100
    },
    {
      label = "Kurangi Recoil H",
      key = "CustomHRecoil"
    },
    {
      slider = true,
      label = "Nilai H",
      key = "HRecoil",
      min = 0,
      max = 100
    },
    {
      label = "Kurangi Recoil V",
      key = "CustomVRecoil"
    },
    {
      slider = true,
      label = "Nilai V",
      key = "VRecoil",
      min = 0,
      max = 100
    },
    {
      label = "Kurangi Guncangan",
      key = "LessShake"
    },
    {
      label = "Akurasi 100%",
      key = "Accuracy"
    },
    {
      label = "Crosshair Kecil",
      key = "Crosshair"
    },
    {
      label = "Aimbot Kepala",
      key = "AutoHead"
    }
  }
  local StackAIM_R = {
    {
      label = "AKTIFKAN AIMBOT V2",
      key = "AimTouchEnable"
    },
    {
      section = true,
      label = "<< HIPFIRE >>",
      color = "blue"
    },
    {
      label = "Ig Knock",
      key = "AimTouchHipIgKnock"
    },
    {
      label = "Ig Bot",
      key = "AimTouchHipIgBot"
    },
    {
      label = "VisCheck",
      key = "AimTouchHipVisCheck"
    },
    {
      label = "Aim Touch Hipfire",
      key = "AimTouchHipfire"
    },
    {
      slider = true,
      label = "Speed",
      key = "AimTouchHipSpeed",
      min = 1,
      max = 100
    },
    {
      slider = true,
      label = "FOV",
      key = "AimTouchHipFOV",
      min = 1,
      max = 100
    },
    {
      slider = true,
      label = "Bone (1-4)",
      key = "AimTouchHipBone",
      min = 1,
      max = 4
    },
    {
      slider = true,
      label = "Prio (1-4)",
      key = "AimTouchHipPrio",
      min = 1,
      max = 4
    },
    {
      section = true,
      label = "<< SCOPE >>",
      color = "purple"
    },
    {
      label = "Aimbot Scope",
      key = "AimTouchScopeAll"
    },
    {
      label = "Ig Knock",
      key = "AimTouchScopeIgKnock"
    },
    {
      label = "Ig Bot",
      key = "AimTouchScopeIgBot"
    },
    {
      label = "VisCheck",
      key = "AimTouchScopeVisCheck"
    },
    {
      slider = true,
      label = "Speed",
      key = "AimTouchScopeSpeed",
      min = 1,
      max = 100
    },
    {
      slider = true,
      label = "FOV",
      key = "AimTouchScopeFOV",
      min = 1,
      max = 100
    },
    {
      slider = true,
      label = "Prediksi",
      key = "AimTouchScopePred",
      min = 0,
      max = 100
    },
    {
      slider = true,
      label = "Recoil Comp",
      key = "AimTouchScopeRecoil",
      min = 0,
      max = 50
    }
  }
  local StackESP_L = {
    {
      label = "ESP Tipe 1 (Peringatan)",
      key = "EspVip"
    },
    {
      label = "ESP Tipe 2 (Jarak)",
      key = "EspDistance"
    },
    {
      label = "ESP Tipe 3 (HP & Nama)",
      key = "EspVipPro"
    },
    {
      label = "ESP Tipe 4 (Radar)",
      key = "EspRadar"
    },
    {
      label = "ESP Tipe 5 (Kotak)",
      key = "EspLoai5"
    },
    {
      label = "ESP Tipe 6 (Kerangka)",
      key = "EspLoai6"
    },
    {
      label = "ESP Tipe 7 (Info Detail)",
      key = "EspLoai7"
    },
    {
      label = "ESP Tipe 8 (HP Head)",
      key = "EspLoai8"
    },
    {
      label = "ESP Tipe 9 (RedBox)",
      key = "EspLoai9"
    },
    {label = "ESP Antena", key = "EspAntenna"},
    {
      label = "ESP Outline",
      key = "EspOutline"
    },
    {
      slider = true,
      label = "Warna (1-6)",
      key = "OutlineColor",
      min = 1,
      max = 6
    },
    {
      slider = true,
      label = "Ketebalan",
      key = "OutlineThickness",
      min = 1,
      max = 20
    }
  }
  local StackESP_R = {
    {
      section = true,
      label = "<< VEHICLE ESP >>",
      color = "green"
    },
    {
      label = "ESP Kendaraan",
      key = "EspVehicle"
    },
    {
      label = "Dacia",
      key = "EspVeh_Dacia"
    },
    {label = "UAZ", key = "EspVeh_UAZ"},
    {
      label = "Buggy",
      key = "EspVeh_Buggy"
    },
    {
      label = "Coupe RB",
      key = "EspVeh_Coupe"
    },
    {
      label = "Mirado",
      key = "EspVeh_Mirado"
    },
    {
      label = "Motor",
      key = "EspVeh_Motor"
    },
    {
      label = "Lainnya",
      key = "EspVeh_Other"
    },
    {
      section = true,
      label = "<< BOM TRACKER >>",
      color = "yellow"
    },
    {
      label = "Peringatan Bom",
      key = "EspBomMaster"
    },
    {
      label = "Lacak Item Bom",
      key = "EspItemBom"
    },
    {
      label = "Peringatan Aktif",
      key = "EspActiveBom"
    },
    {
      section = true,
      label = "<< AIM WARNING >>",
      color = "red"
    },
    {
      label = "Peringatan Musuh Aim",
      key = "EspAimWarning"
    },
    {
      label = "Cek Dinding",
      key = "EspAimWarningVisCheck"
    }
  }
  local StackSKIN_L = {
    {
      label = "Buka Semua Emote VIP",
      key = "ModEmote"
    },
    {
      label = "Sistem Mod Skin VIP",
      key = "ModSkin"
    },
    {
      label = "Skin Peti Mati",
      key = "SkinDeadBox"
    },
    {
      label = "Skin Aksesoris Senjata",
      key = "SkinAttachment"
    },
    {
      label = "Kill Message VIP",
      key = "KillMessage"
    },
    {
      label = "Kill Counter UI",
      key = "KillCountUI"
    },
    {
      label = "Guide Skin",
      key = "SkinOpenLink"
    }
  }
  local StackSKIN_R = {
    {
      section = true,
      label = "<< WALLHACK >>",
      color = "purple"
    },
    {
      label = "Wallhack Rainbow",
      key = "WallhackRainbow"
    },
    {
      label = "Glow Senjata (HDR)",
      key = "WeaponGlow"
    },
    {
      slider = true,
      label = "Warna (1-5)",
      key = "WeaponGlowColor",
      min = 1,
      max = 5
    },
    {
      slider = true,
      label = "Ketebalan",
      key = "WeaponGlowThickness",
      min = 1,
      max = 15
    },
    {
      label = "Lobby Super Car VIP",
      key = "SanhSieuXeVip"
    }
  }
  local StackCOMBAT_L = {
    {
      section = true,
      label = "<< WALLHACK >>",
      color = "purple"
    },
    {
      label = "Wallhack V1 (Tembus)",
      key = "WallXuyenTuong"
    },
    {
      label = "Chams V2 (Warna Dasar)",
      key = "ColorBodyV2"
    },
    {
      label = "Wall Warna New",
      key = "ColorBodyNew"
    },
    {
      label = "Wall V2 + Chams V3",
      key = "ColorBodyV3"
    },
    {
      slider = true,
      label = "Warna Tembus",
      key = "ColorV3Hidden",
      min = 1,
      max = 6
    },
    {
      slider = true,
      label = "Warna Terlihat",
      key = "ColorV3Visible",
      min = 1,
      max = 6
    },
    {
      slider = true,
      label = "Ketebalan",
      key = "ColorV3Thickness",
      min = 1,
      max = 20
    },
    {
      label = "Wallhack Kendaraan",
      key = "WallVehicle"
    },
    {
      section = true,
      label = "<< ENVIRONMENT >>",
      color = "green"
    },
    {
      label = "Karakter Putih",
      key = "WhiteBody"
    },
    {
      label = "Langit Hitam",
      key = "BlackSky"
    },
    {
      label = "Hilangkan Kabut",
      key = "RemoveFog"
    },
    {
      label = "Hilangkan Rumput",
      key = "RemoveGrass"
    },
    {
      label = "Hilangkan Pohon",
      key = "RemoveTrees"
    }
  }
  local StackCOMBAT_R = {
    {
      section = true,
      label = "<< LAIN-LAIN >>",
      color = "blue"
    },
    {label = "HWID Palsu", key = "FakeHWID"},
    {
      label = "Tampilan iPad",
      key = "IpadView"
    },
    {
      slider = true,
      label = "FOV iPad",
      key = "IpadViewFOV",
      min = 1,
      max = 300
    },
    {
      label = "iPad Kendaraan",
      key = "IpadViewVehicle"
    },
    {
      slider = true,
      label = "FOV Kendaraan",
      key = "IpadViewVehicleFOV",
      min = 1,
      max = 100
    },
    {
      label = "iPad Scope",
      key = "IpadViewScope"
    },
    {
      slider = true,
      label = "FOV Scope",
      key = "IpadViewScopeFOV",
      min = 30,
      max = 120
    },
    {
      label = "Buka 165 FPS",
      key = "UnlockFPS"
    },
    {
      label = "Panjat Tembok",
      key = "WallClimb"
    },
    {
      label = "Mobil Cepat",
      key = "FastCar"
    },
    {
      slider = true,
      label = "Kecepatan Mobil",
      key = "FastCarSpeed",
      min = 500,
      max = 8000
    }
  }
  local StackESP9_L = {
    {
      label = "ESP VIP MENU",
      key = "EspLoai9"
    },
    {
      label = "   Show Player Count",
      key = "Esp9_Count"
    },
    {
      label = "   Show Player Name",
      key = "Esp9_Name"
    },
    {
      label = "   Show Distance",
      key = "Esp9_Distance"
    },
    {
      label = "   Show Health Bar",
      key = "Esp9_HP"
    },
    {
      label = "   Show Team Color",
      key = "Esp9_Team"
    },
    {
      label = "   Show Weapon Icon",
      key = "Esp9_Weapon"
    },
    {
      label = "   Show Snapline",
      key = "Esp9_Line"
    },
    {
      label = "   Show Skeleton",
      key = "Esp9_Skeleton"
    },
    {
      slider = true,
      label = "   Line Thick",
      key = "Esp9_LineThick",
      min = 1,
      max = 10
    },
    {
      slider = true,
      label = "   Line Vis Color",
      key = "Esp9_LineVisColor",
      min = 1,
      max = 30
    },
    {
      slider = true,
      label = "   Line Hid Color",
      key = "Esp9_LineHidColor",
      min = 1,
      max = 30
    },
    {
      slider = true,
      label = "   Skel Thick",
      key = "Esp9_SkelThick",
      min = 1,
      max = 10
    },
    {
      slider = true,
      label = "   Skel Vis Color",
      key = "Esp9_SkelVisColor",
      min = 1,
      max = 30
    },
    {
      slider = true,
      label = "   Skel Hid Color",
      key = "Esp9_SkelHidColor",
      min = 1,
      max = 30
    },
    {
      label = "COLOUR BODY (Yellow/Red)",
      key = "ColorBodyNew"
    },
    {
      section = true,
      label = "<< ESP TYPES >>",
      color = "blue"
    },
    {label = "ESP Tipe 1", key = "EspVip"},
    {
      label = "ESP Tipe 2",
      key = "EspDistance"
    },
    {label = "ESP Tipe 3", key = "EspVipPro"},
    {label = "ESP Tipe 4", key = "EspRadar"},
    {label = "ESP Tipe 5", key = "EspLoai5"},
    {label = "ESP Tipe 6", key = "EspLoai6"},
    {label = "ESP Tipe 7", key = "EspLoai7"},
    {label = "ESP Tipe 8", key = "EspLoai8"},
    {label = "ESP Tipe 9", key = "EspLoai9"},
    {
      label = "ESP Antenna",
      key = "EspAntenna"
    },
    {
      label = "ESP Outline",
      key = "EspOutline"
    },
    {
      slider = true,
      label = "Outline Color",
      key = "OutlineColor",
      min = 1,
      max = 6
    },
    {
      slider = true,
      label = "Outline Thick",
      key = "OutlineThickness",
      min = 1,
      max = 20
    }
  }
  local StackESP9_R = {
    {
      section = true,
      label = "<< ESP7 SUB >>",
      color = "yellow"
    },
    {
      label = "ESP7 Show Count",
      key = "Esp7_SoLuong"
    },
    {
      label = "ESP7 Show Weapon",
      key = "Esp7_VuKhi"
    },
    {
      label = "ESP7 Show Posture",
      key = "Esp7_TuThe"
    },
    {
      label = "ESP Aim Warning",
      key = "EspAimWarning"
    },
    {
      label = "ESP Aim VisCheck",
      key = "EspAimWarningVisCheck"
    },
    {
      section = true,
      label = "<< VEHICLE >>",
      color = "green"
    },
    {
      label = "ESP Vehicle",
      key = "EspVehicle"
    },
    {
      label = "Dacia",
      key = "EspVeh_Dacia"
    },
    {label = "UAZ", key = "EspVeh_UAZ"},
    {
      label = "Buggy",
      key = "EspVeh_Buggy"
    },
    {
      label = "Coupe",
      key = "EspVeh_Coupe"
    },
    {
      label = "Mirado",
      key = "EspVeh_Mirado"
    },
    {
      label = "Motor",
      key = "EspVeh_Motor"
    },
    {
      label = "Other",
      key = "EspVeh_Other"
    },
    {
      section = true,
      label = "<< BOMB >>",
      color = "red"
    },
    {
      label = "Bomb Master",
      key = "EspBomMaster"
    },
    {label = "Item Bomb", key = "EspItemBom"},
    {
      label = "Active Bomb",
      key = "EspActiveBom"
    }
  }
  local StackSKINVIP_L = {
    {
      label = "MOD SKIN ON/OFF",
      key = "ModSkin"
    },
    {
      slider = true,
      label = "   Suit Skin",
      key = "SkinSuit",
      min = 1,
      max = 80
    },
    {
      slider = true,
      label = "   Bag Skin",
      key = "SkinBag",
      min = 1,
      max = 15
    },
    {
      slider = true,
      label = "   Helmet Skin",
      key = "SkinHelmet",
      min = 1,
      max = 11
    },
    {
      slider = true,
      label = "   M416 Skin",
      key = "SkinM416",
      min = 1,
      max = 8
    },
    {
      slider = true,
      label = "   AKM Skin",
      key = "SkinAKM",
      min = 1,
      max = 8
    },
    {
      slider = true,
      label = "   SCAR Skin",
      key = "SkinSCAR",
      min = 1,
      max = 8
    },
    {
      slider = true,
      label = "   M762 Skin",
      key = "SkinM762",
      min = 1,
      max = 8
    },
    {
      slider = true,
      label = "   AUG Skin",
      key = "SkinAUG",
      min = 1,
      max = 7
    },
    {
      slider = true,
      label = "   UMP Skin",
      key = "SkinUMP",
      min = 1,
      max = 5
    },
    {
      slider = true,
      label = "   UZI Skin",
      key = "SkinUZI",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   Groza Skin",
      key = "SkinGroza",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   S12K Skin",
      key = "SkinS12K",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   DBS Skin",
      key = "SkinDBS",
      min = 1,
      max = 3
    },
    {
      slider = true,
      label = "   ASM Skin",
      key = "SkinASM",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   QBZ Skin",
      key = "SkinQBZ",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   Honey Skin",
      key = "SkinHoney",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   M16A4 Skin",
      key = "SkinM16A4",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   ACE32 Skin",
      key = "SkinACE32",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   Kar98k Skin",
      key = "SkinKar98k",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   M24 Skin",
      key = "SkinM24",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   AWM Skin",
      key = "SkinAWM",
      min = 1,
      max = 2
    }
  }
  local StackSKINVIP_R = {
    {
      section = true,
      label = "<< VEHICLE SKIN >>",
      color = "green"
    },
    {
      slider = true,
      label = "Dacia Skin",
      key = "SkinDacia",
      min = 1,
      max = 34
    },
    {
      slider = true,
      label = "UAZ Skin",
      key = "SkinUAZ",
      min = 1,
      max = 16
    },
    {
      slider = true,
      label = "Coupe Skin",
      key = "SkinCoupe",
      min = 1,
      max = 55
    },
    {
      slider = true,
      label = "Buggy Skin",
      key = "SkinBuggy",
      min = 1,
      max = 11
    },
    {
      slider = true,
      label = "Mirado Skin",
      key = "SkinMirado",
      min = 1,
      max = 5
    },
    {
      section = true,
      label = "<< EXTRA >>",
      color = "purple"
    },
    {
      label = "DeadBox Skin",
      key = "SkinDeadBox"
    },
    {
      label = "Attachment Skin",
      key = "SkinAttachment"
    },
    {label = "Mod Emote", key = "ModEmote"},
    {
      label = "Kill Message",
      key = "KillMessage"
    },
    {
      label = "Kill Counter UI",
      key = "KillCountUI"
    },
    {
      label = "Guide Skin",
      key = "SkinOpenLink"
    }
  }
  local StackCOMBAT2_L = {
    {label = "IPAD VIEW", key = "IpadView"},
    {
      slider = true,
      label = "   FOV",
      key = "IpadViewFOV",
      min = 1,
      max = 100
    },
    {
      label = "Ipad View Vehicle",
      key = "IpadViewVehicle"
    },
    {
      slider = true,
      label = "   FOV",
      key = "IpadViewVehicleFOV",
      min = 1,
      max = 100
    },
    {
      label = "Ipad View Scope",
      key = "IpadViewScope"
    },
    {
      slider = true,
      label = "   FOV",
      key = "IpadViewScopeFOV",
      min = 30,
      max = 120
    },
    {
      label = "NO RECOIL",
      key = "NoRecoilEnabled"
    },
    {
      slider = true,
      label = "   Reduction",
      key = "RecoilReduction",
      min = 0,
      max = 100
    },
    {
      label = "WEAPON AIMBOT",
      key = "WeaponAimbot"
    },
    {label = "Auto Head", key = "AutoHead"},
    {
      label = "Accuracy 100%",
      key = "Accuracy"
    },
    {label = "Less Shake", key = "LessShake"},
    {
      label = "Crosshair Small",
      key = "Crosshair"
    },
    {label = "God Mode", key = "GodMode"},
    {label = "Fake HWID", key = "FakeHWID"}
  }
  local StackCOMBAT2_R = {
    {
      section = true,
      label = "<< GRAPHICS >>",
      color = "green"
    },
    {label = "Black Sky", key = "BlackSky"},
    {label = "Remove Fog", key = "RemoveFog"},
    {
      label = "Remove Grass",
      key = "RemoveGrass"
    },
    {
      label = "Remove Trees",
      key = "RemoveTrees"
    },
    {label = "White Body", key = "WhiteBody"},
    {label = "Unlock FPS", key = "UnlockFPS"},
    {
      section = true,
      label = "<< GAMEPLAY >>",
      color = "blue"
    },
    {
      label = "Wallhack V1",
      key = "WallXuyenTuong"
    },
    {
      label = "Chams V2",
      key = "ColorBodyV2"
    },
    {
      label = "Wall V2 + V3",
      key = "ColorBodyV3"
    },
    {
      slider = true,
      label = "V3 Hidden",
      key = "ColorV3Hidden",
      min = 1,
      max = 6
    },
    {
      slider = true,
      label = "V3 Visible",
      key = "ColorV3Visible",
      min = 1,
      max = 6
    },
    {
      slider = true,
      label = "V3 Thick",
      key = "ColorV3Thickness",
      min = 1,
      max = 20
    },
    {
      label = "Wall Vehicle",
      key = "WallVehicle"
    },
    {label = "Fast Car", key = "FastCar"},
    {
      slider = true,
      label = "Car Speed",
      key = "FastCarSpeed",
      min = 500,
      max = 8000
    },
    {label = "Wall Climb", key = "WallClimb"},
    {
      label = "Bug Man",
      key = "BugManEnable"
    },
    {
      slider = true,
      label = "Bug Ratio",
      key = "BugManRatio",
      min = 110,
      max = 200
    },
    {
      label = "Weapon Glow",
      key = "WeaponGlow"
    },
    {
      slider = true,
      label = "Glow Color",
      key = "WeaponGlowColor",
      min = 1,
      max = 5
    },
    {
      slider = true,
      label = "Glow Thick",
      key = "WeaponGlowThickness",
      min = 1,
      max = 15
    }
  }
  local StackESP = {
    {
      label = "ESP VIP MENU",
      key = "EspLoai9"
    },
    {
      label = "   Show Player Count",
      key = "Esp9_Count"
    },
    {
      label = "   Show Player Name",
      key = "Esp9_Name"
    },
    {
      label = "   Show Distance",
      key = "Esp9_Distance"
    },
    {
      label = "   Show Health Bar",
      key = "Esp9_HP"
    },
    {
      label = "   Show Team Color Box",
      key = "Esp9_Team"
    },
    {
      label = "   Show Snapline",
      key = "Esp9_Line"
    },
    {
      label = "COLOUR BODY (Green/Pink)",
      key = "ColorBodyNew"
    }
  }
  local StackCombat = {
    {label = "IPAD VIEW", key = "IpadView"},
    {
      slider = true,
      label = "   FOV",
      key = "IpadViewFOV",
      min = 1,
      max = 100
    },
    {
      label = "NO RECOIL",
      key = "NoRecoilEnabled"
    },
    {
      slider = true,
      label = "   Recoil Reduction",
      key = "RecoilReduction",
      min = 0,
      max = 100
    },
    {
      label = "WEAPON AIMBOT",
      key = "WeaponAimbot"
    }
  }
  local StackSkin = {
    {
      label = "MOD SKIN ON/OFF",
      key = "ModSkin"
    },
    {
      slider = true,
      label = "   Suit Skin",
      key = "SkinSuit",
      min = 1,
      max = 80
    },
    {
      slider = true,
      label = "   Bag Skin",
      key = "SkinBag",
      min = 1,
      max = 15
    },
    {
      slider = true,
      label = "   Helmet Skin",
      key = "SkinHelmet",
      min = 1,
      max = 11
    },
    {
      slider = true,
      label = "   M416 Skin",
      key = "SkinM416",
      min = 1,
      max = 8
    },
    {
      slider = true,
      label = "   AKM Skin",
      key = "SkinAKM",
      min = 1,
      max = 8
    },
    {
      slider = true,
      label = "   SCAR Skin",
      key = "SkinSCAR",
      min = 1,
      max = 8
    },
    {
      slider = true,
      label = "   M762 Skin",
      key = "SkinM762",
      min = 1,
      max = 8
    },
    {
      slider = true,
      label = "   AUG Skin",
      key = "SkinAUG",
      min = 1,
      max = 7
    },
    {
      slider = true,
      label = "   UMP Skin",
      key = "SkinUMP",
      min = 1,
      max = 5
    },
    {
      slider = true,
      label = "   UZI Skin",
      key = "SkinUZI",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   Groza Skin",
      key = "SkinGroza",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   S12K Skin",
      key = "SkinS12K",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   DBS Skin",
      key = "SkinDBS",
      min = 1,
      max = 3
    },
    {
      slider = true,
      label = "   ASM Skin",
      key = "SkinASM",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   QBZ Skin",
      key = "SkinQBZ",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   Honey Skin",
      key = "SkinHoney",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   M16A4 Skin",
      key = "SkinM16A4",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   ACE32 Skin",
      key = "SkinACE32",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   Kar98k Skin",
      key = "SkinKar98k",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   M24 Skin",
      key = "SkinM24",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   AWM Skin",
      key = "SkinAWM",
      min = 1,
      max = 2
    },
    {
      slider = true,
      label = "   Dacia Skin",
      key = "SkinDacia",
      min = 1,
      max = 34
    },
    {
      slider = true,
      label = "   UAZ Skin",
      key = "SkinUAZ",
      min = 1,
      max = 16
    },
    {
      slider = true,
      label = "   Coupe Skin",
      key = "SkinCoupe",
      min = 1,
      max = 55
    },
    {
      slider = true,
      label = "   Buggy Skin",
      key = "SkinBuggy",
      min = 1,
      max = 11
    },
    {
      slider = true,
      label = "   Mirado Skin",
      key = "SkinMirado",
      min = 1,
      max = 5
    },
    {
      label = "DeadBox Skin",
      key = "SkinDeadBox"
    },
    {
      label = "Attachment Skin",
      key = "SkinAttachment"
    }
  }
  local PAGES = {
    {
      title = "ESP MENU",
      left = StackESP,
      right = {}
    },
    {
      title = "PLAYER",
      left = StackCombat,
      right = {}
    },
    {
      title = "SKIN MENU",
      left = StackSkin,
      right = {}
    }
  }
  local curPage = 1
  
  local function BuildColumn(scroll, stack)
    local content
    pcall(function()
      content = NewObject("/Script/UMG.VerticalBox", scroll)
      if IV(content) then
        scroll:AddChild(content)
      end
    end)
    if not IV(content) then
      return
    end
    local w = COL_W - 8
    for _, opt in ipairs(stack) do
      if opt.section then
        local sb = NewObject("/Script/UMG.SizeBox", content)
        if IV(sb) then
          sb:SetHeightOverride(30)
          content:AddChildToVerticalBox(sb)
          local cp = NewObject("/Script/UMG.CanvasPanel", sb)
          if IV(cp) then
            sb:AddChild(cp)
            SectionHeader(cp, 0, 0, w, opt.label, opt.color)
          end
        end
      else
        local rb = NewObject("/Script/UMG.SizeBox", content)
        if IV(rb) then
          rb:SetHeightOverride(ROW_H)
          local slot = content:AddChildToVerticalBox(rb)
          if slot and FMargin then
            pcall(function()
              slot:SetPadding(FMargin(0, 1, 0, 1))
            end)
          end
          local rp = NewObject("/Script/UMG.CanvasPanel", rb)
          if IV(rp) then
            rb:AddChild(rp)
            if opt.slider then
              MakeStepper(rp, 0, 0, w, opt.label, opt.key, opt.min or 0, opt.max or 100)
            else
              MakeToggle(rp, 0, 0, w, opt.label, opt.key)
            end
          end
        end
      end
    end
  end
  
  local function OnDragStart(x, y)
    if not IV(bgPanel) then
      return
    end
    local slot
    pcall(function()
      slot = bgPanel.Slot
    end)
    if not slot or not slua.isValid(slot) then
      return
    end
    local pos
    pcall(function()
      pos = slot:GetPosition()
    end)
    if not pos then
      return
    end
    _dragState.active = true
    _dragState.moved = false
    _dragState.offX = (pos.X or 0) - x
    _dragState.offY = (pos.Y or 0) - y
    _dragState.lastX = pos.X or 0
    _dragState.lastY = pos.Y or 0
  end
  
  local function OnDragMove(x, y)
    if not _dragState.active then
      return
    end
    if not IV(bgPanel) then
      return
    end
    local slot
    pcall(function()
      slot = bgPanel.Slot
    end)
    if not slot or not slua.isValid(slot) then
      return
    end
    local nx = x + _dragState.offX
    local ny = y + _dragState.offY
    _dragState.lastX = nx
    _dragState.lastY = ny
    _dragState.moved = true
    pcall(function()
      slot:SetPosition(FV2(nx, ny))
    end)
  end
  
  local function OnDragEnd()
    _dragState.active = false
  end
  
  local function BuildMenu()
    if menuBuilt and IV(bgPanel) then
      ShowMenu()
      return
    end
    local canvas = GetCanvas()
    if not canvas then
      return
    end
    pcall(function()
      bgPanel = NewObject("/Script/UMG.CanvasPanel", canvas)
      if IV(bgPanel) then
        local slot = canvas:AddChildToCanvas(bgPanel)
        if slot then
          slot:SetAutoSize(false)
          slot:SetZOrder(10000)
          do
            local cx, cy
            pcall(function()
              local u = require("client.common.ui_util")
              if u and u.GetViewportSize then
                local vp = u.GetViewportSize()
                if vp and vp.X and vp.Y and vp.X > 0 then
                  cx = (vp.X - M_W) * 0.5
                  cy = (vp.Y - M_H) * 0.5
                  if cx < 0 then
                    cx = 0
                  end
                  if cy < 0 then
                    cy = 0
                  end
                end
              end
            end)
            if cx and cy then
              if FAnchors then
                pcall(function()
                  slot:SetAnchors(FAnchors(0, 0, 0, 0))
                end)
              end
              slot:SetAlignment(FV2(0, 0))
              slot:SetPosition(FV2(cx, cy))
              slot:SetSize(FV2(M_W, M_H))
            else
              if FAnchors then
                pcall(function()
                  slot:SetAnchors(FAnchors(0.5, 0.5, 0.5, 0.5))
                end)
              end
              slot:SetAlignment(FV2(0.5, 0.5))
              slot:SetPosition(FV2(0, 0))
              slot:SetSize(FV2(M_W, M_H))
            end
          end
        end
      end
    end)
    if not IV(bgPanel) then
      return
    end
    pcall(function()
      if not IV(bgPanel) then
        return
      end
      local parent
      pcall(function()
        parent = bgPanel:GetParent()
      end)
      if parent and slua.isValid(parent) then
        return
      end
      local cv = GetCanvas()
      if not cv then
        return
      end
      local s = cv:AddChildToCanvas(bgPanel)
      if s then
        s:SetAutoSize(false)
        s:SetZOrder(10000)
        local cx, cy
        pcall(function()
          local u = require("client.common.ui_util")
          if u and u.GetViewportSize then
            local vp = u.GetViewportSize()
            if vp and vp.X and vp.Y and vp.X > 0 then
              cx = (vp.X - M_W) * 0.5
              cy = (vp.Y - M_H) * 0.5
              if cx < 0 then
                cx = 0
              end
              if cy < 0 then
                cy = 0
              end
            end
          end
        end)
        if cx and cy then
          if FAnchors then
            pcall(function()
              s:SetAnchors(FAnchors(0, 0, 0, 0))
            end)
          end
          s:SetAlignment(FV2(0, 0))
          s:SetPosition(FV2(cx, cy))
          s:SetSize(FV2(M_W, M_H))
        end
      end
    end)
    Layer(bgPanel, 6, 8, M_W, M_H, C.shadow, -2)
    Layer(bgPanel, -4, -4, M_W + 8, M_H + 8, FLC(0.6, 0.2, 1.0, 0.35), 0)
    Layer(bgPanel, -2, -2, M_W + 4, M_H + 4, C.panel_border, 1)
    Layer(bgPanel, 0, 0, M_W, M_H, C.panel_bg, 2)
    Layer(bgPanel, 0, 0, M_W, HEADER_H, C.panel_header, 3)
    Layer(bgPanel, 0, HEADER_H - 4, M_W, 4, C.accent_purple, 3)
    if bgPanel and IV(bgPanel) then
      pcall(function()
        bgPanel:SetVisibility(UEnums.ESlateVisibility.Visible)
      end)
      pcall(function()
        bgPanel.bIsFocusable = true
      end)
    end
    do
      local held = false
      local offX, offY = 0, 0
      local lastX, lastY = 0, 0
      
      local function LocalToScreen(slotX, slotY)
        return slotX, slotY
      end
      
      local function OnDown(x, y)
        if not IV(bgPanel) then
          return
        end
        local slot
        pcall(function()
          slot = bgPanel.Slot
        end)
        if not slot or not slua.isValid(slot) then
          return
        end
        local pos
        pcall(function()
          pos = slot:GetPosition()
        end)
        if not pos then
          return
        end
        held = true
        lastX, lastY = x, y
        offX = (pos.X or 0) - x
        offY = (pos.Y or 0) - y
      end
      
      local function OnMove(x, y)
        if not held then
          return
        end
        if not IV(bgPanel) then
          return
        end
        local slot
        pcall(function()
          slot = bgPanel.Slot
        end)
        if not slot or not slua.isValid(slot) then
          return
        end
        pcall(function()
          slot:SetPosition(FV2(x + offX, y + offY))
        end)
      end
      
      local function OnUp()
        held = false
      end
      
      _G.SHMenuDragDown = OnDown
      _G.SHMenuDragMove = OnMove
      _G.SHMenuDragUp = OnUp
    end
    Layer(bgPanel, 0, HEADER_H - 2, M_W, 2, C.accent_gold, 4)
    Layer(bgPanel, 0, HEADER_H, 3, M_H - HEADER_H, C.accent_gold, 3)
    Layer(bgPanel, M_W - 3, HEADER_H, 3, M_H - HEADER_H, C.accent_gold, 3)
    _debugTitleRef = nil
    Layer(bgPanel, 18, 18, 3, 3, C.white, 5)
    Layer(bgPanel, 18, 26, 3, 3, C.white, 5)
    Layer(bgPanel, 18, 34, 3, 3, C.white, 5)
    Layer(bgPanel, 24, 18, 18, 3, C.white, 5)
    Layer(bgPanel, 24, 26, 18, 3, C.white, 5)
    Layer(bgPanel, 24, 34, 18, 3, C.white, 5)
    do
      local dragBtn = NewObject("/Script/UMG.Button", bgPanel)
      if IV(dragBtn) then
        pcall(function()
          dragBtn:SetColorAndOpacity(FLC(1, 1, 1, 0.02))
        end)
        pcall(function()
          dragBtn:SetBackgroundColor(FLC(1, 1, 1, 0.02))
        end)
        pcall(function()
          dragBtn:SetWidgetVisibility(UEnums.ESlateVisibility.Visible)
        end)
        do
          local s = bgPanel:AddChildToCanvas(dragBtn)
          if s then
            s:SetAutoSize(false)
            s:SetPosition(FV2(0, 0))
            s:SetSize(FV2(M_W - 34, HEADER_H))
            s:SetZOrder(60)
          end
          pcall(function()
            if dragBtn.OnTouchStarted then
              dragBtn.OnTouchStarted:Add(function(_, geom, ev)
                pcall(function()
                  local mx, my = 0, 0
                  if ev and ev.GetScreenSpacePosition then
                    local p = ev:GetScreenSpacePosition()
                    mx, my = p.X, p.Y
                  end
                  if _G.SHMenuDragDown then
                    _G.SHMenuDragDown(mx, my)
                  end
                end)
              end)
            end
            if dragBtn.OnTouchMoved then
              dragBtn.OnTouchMoved:Add(function(_, geom, ev)
                pcall(function()
                  local mx, my = 0, 0
                  if ev and ev.GetScreenSpacePosition then
                    local p = ev:GetScreenSpacePosition()
                    mx, my = p.X, p.Y
                  end
                  if _G.SHMenuDragMove then
                    _G.SHMenuDragMove(mx, my)
                  end
                end)
              end)
            end
            if dragBtn.OnTouchEnded then
              dragBtn.OnTouchEnded:Add(function()
                if _G.SHMenuDragUp then
                  _G.SHMenuDragUp()
                end
              end)
            end
          end)
        end
      end
    end
    _debugTitleRef = Text(bgPanel, "MOHSINXFILES CHEATS", M_W * 0.5, HEADER_H * 0.5 - 6, 18, C.accent_cyan, 6, 0.5, 0.5)
    Text(bgPanel, "PLAYER: 0  |  BOT: 4", M_W * 0.5, HEADER_H * 0.5 + 14, 9, C.accent_yellow, 6, 0.5, 0.5)
    Layer(bgPanel, M_W - 100, HEADER_H * 0.5 - 4, 6, 6, C.online_green, 6)
    Text(bgPanel, "PREMIUM", M_W - 90, HEADER_H * 0.5, 10, C.online_green, 6, 0, 0.5)
    local closeX, closeY = M_W - 34, 14
    Layer(bgPanel, closeX, closeY, 22, 22, C.accent_red, 7)
    Text(bgPanel, "X", closeX + 11, closeY + 11, 12, C.white, 400, 0.5, 0.5)
    MakeBtn(bgPanel, closeX, closeY, 22, 22, 900, function()
      isMenuOpen = false
      HideMenu()
    end)
    local contentY = HEADER_H + 8
    local contentH = M_H - contentY - 44
    local leftX = 12
    local rightX = 12 + COL_W + COL_GAP
    local pageData = PAGES[curPage]
    Text(bgPanel, "\226\151\134 MENU", leftX, contentY - 2, 10, C.accent_gold, 6, 0, 1)
    local scrollL = NewObject("/Script/UMG.ScrollBox", bgPanel)
    if IV(scrollL) then
      local s = bgPanel:AddChildToCanvas(scrollL)
      if s then
        s:SetAutoSize(false)
        s:SetPosition(FV2(leftX, contentY + 10))
        s:SetSize(FV2(COL_W, contentH - 10))
        s:SetZOrder(20)
      end
      pcall(function()
        scrollL:SetScrollBarVisibility(UEnums.ESlateVisibility.Visible)
      end)
      pcall(function()
        scrollL:SetConsumeMouseWheel(true)
      end)
    end
    local scrollR = NewObject("/Script/UMG.ScrollBox", bgPanel)
    if IV(scrollR) then
      local s = bgPanel:AddChildToCanvas(scrollR)
      if s then
        s:SetAutoSize(false)
        s:SetPosition(FV2(rightX, contentY + 10))
        s:SetSize(FV2(COL_W, contentH - 10))
        s:SetZOrder(20)
      end
      pcall(function()
        scrollR:SetScrollBarVisibility(UEnums.ESlateVisibility.Visible)
      end)
      pcall(function()
        scrollR:SetConsumeMouseWheel(true)
      end)
    end
    if IV(scrollL) then
      BuildColumn(scrollL, pageData.left)
    end
    if IV(scrollR) then
      BuildColumn(scrollR, pageData.right)
    end
    local footerY = M_H - 36
    Layer(bgPanel, 0, footerY, M_W, 2, C.accent_purple, 4)
    Layer(bgPanel, 0, footerY + 2, M_W, 34, C.panel_header, 3)
    local prevX, prevY = 20, footerY + 6
    Layer(bgPanel, prevX, prevY, 60, 22, C.accent_dark, 5)
    Text(bgPanel, "< PREV", prevX + 30, prevY + 11, 11, C.white, 6, 0.5, 0.5)
    MakeBtn(bgPanel, prevX, prevY, 60, 22, 900, function()
      curPage = curPage - 1
      if curPage < 1 then
        curPage = #PAGES
      end
      menuBuilt = false
      pcall(function()
        bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      end)
      BuildMenu()
    end)
    Text(bgPanel, "PAGE " .. curPage .. "/" .. #PAGES .. "  -  " .. pageData.title, M_W * 0.5, footerY + 17, 11, C.white, 6, 0.5, 0.5)
    local nextX, nextY = M_W - 80, footerY + 6
    Layer(bgPanel, nextX, nextY, 60, 22, C.accent_gold, 5)
    Text(bgPanel, "NEXT >", nextX + 30, nextY + 11, 11, C.white, 6, 0.5, 0.5)
    MakeBtn(bgPanel, nextX, nextY, 60, 22, 900, function()
      curPage = curPage + 1
      if curPage > #PAGES then
        curPage = 1
      end
      menuBuilt = false
      pcall(function()
        bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      end)
      BuildMenu()
    end)
    if not _G.SHMenuWatchdog then
      _G.SHMenuWatchdog = true
      pcall(function()
        local t = require("common.time_ticker")
        if t and t.AddTimerLoop then
          t.AddTimerLoop(0.5, function()
            if not IV(bgPanel) then
              return
            end
            if not isMenuOpen then
              pcall(function()
                bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
              end)
              return
            end
            pcall(function()
              bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
              bgPanel:SetRenderOpacity(1.0)
            end)
            local slot
            pcall(function()
              slot = bgPanel.Slot
            end)
            if slot and slua.isValid(slot) and slot.SetZOrder then
              pcall(function()
                slot:SetZOrder(20000)
              end)
            end
          end, -1, 0.5)
        end
      end)
    end
    Layer(bgPanel, M_W - 145, footerY + 18, 8, 8, C.accent_gold, 6)
    Layer(bgPanel, M_W - 133, footerY + 18, 8, 8, C.accent_red, 6)
    Layer(bgPanel, M_W - 121, footerY + 18, 8, 8, C.accent_yellow, 6)
    menuBuilt = true
    isMenuOpen = true
  end
  
  local function CreateFloat()
    if floatBtn and IV(floatBtn.btn) then
      return
    end
    floatBtn = nil
    local canvas = GetCanvas()
    if not canvas then
      return
    end
    floatBtn = {}
    local fX, fY, fW, fH = 750, 15, 120, 48
    Layer(canvas, fX + 3, fY + 4, fW, fH, C.shadow, 11898)
    Layer(canvas, fX - 2, fY - 2, fW + 4, fH + 4, FLC(0.0, 0.95, 1.0, 0.4), 11899)
    Layer(canvas, fX - 1, fY - 1, fW + 2, fH + 2, C.panel_border, 11900)
    Layer(canvas, fX, fY, fW, fH, C.panel_header, 11901)
    Layer(canvas, fX, fY, fW, 3, C.accent_cyan, 11902)
    Layer(canvas, fX, fY + fH - 2, fW, 2, C.accent_purple, 11902)
    Text(canvas, "MOHSINXFILES", fX + fW * 0.5, fY + fH * 0.5 - 7, 13, C.accent_cyan, 12001, 0.5, 0.5)
    Text(canvas, "\226\151\134 PREMIUM \226\151\134", fX + fW * 0.5, fY + fH * 0.5 + 9, 8, C.accent_purple, 12001, 0.5, 0.5)
    Layer(canvas, fX + fW - 12, fY + 6, 5, 5, C.online_green, 11905)
    floatBtn.btn = MakeBtn(canvas, fX, fY, fW, fH, 12002, function()
      isMenuOpen = not isMenuOpen
      if isMenuOpen then
        if menuBuilt and IV(bgPanel) then
          ShowMenu()
        else
          BuildMenu()
        end
      else
        HideMenu()
      end
    end)
  end
  
  local _initDone, _retry = false, 0
  
  local function TryInit()
    if _initDone then
      return
    end
    _retry = _retry + 1
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not IV(pc) then
      return
    end
    local canvas = GetCanvas()
    if not canvas then
      return
    end
    CreateFloat()
    if floatBtn and IV(floatBtn.btn) then
      _initDone = true
      log("Init done retry " .. _retry)
    end
    if not _G.SHMenuDragHooked then
      _G.SHMenuDragHooked = true
      local held = false
      local offX, offY = 0, 0
      
      local function ReadPointer()
        local mx, my
        pcall(function()
          local p2 = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
          if not p2 then
            return
          end
          if p2.GetInputTouchState then
            local lx, ly, b = 0, 0, false
            local ok = pcall(function()
              lx, ly, b = p2:GetInputTouchState(0)
            end)
            if ok and lx and ly and (lx ~= 0 or ly ~= 0) then
              mx, my = lx, ly
              return
            end
          end
          if p2.GetMousePosition then
            local v = FV2(0, 0)
            p2:GetMousePosition(v)
            if v.X and v.Y then
              mx, my = v.X, v.Y
            end
          end
        end)
        return mx, my
      end
      
      local function PointerToLocal(x, y)
        local lx, ly = x, y
        pcall(function()
          local p2 = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
          local WLL = import("WidgetLayoutLibrary")
          if WLL and WLL.ScreenToWidgetLocal and p2 and IV(bgPanel) then
            local cg = bgPanel:GetCachedGeometry()
            if cg then
              local out = FV2(0, 0)
              WLL.ScreenToWidgetLocal(p2, cg, FV2(x, y), out)
              lx, ly = out.X, out.Y
            end
          end
        end)
        return lx, ly
      end
      
      local function HeaderHit(x, y)
        if not IV(bgPanel) then
          return false
        end
        local lx, ly = PointerToLocal(x, y)
        return 0 <= lx and lx <= M_W - 34 and 0 <= ly and ly <= HEADER_H
      end
      
      local lastX, lastY
      local t2 = require("common.time_ticker")
      if t2 and t2.AddTimerLoop then
        t2.AddTimerLoop(0, function()
          if not IV(bgPanel) then
            lastX, lastY = nil, nil
            return
          end
          local x, y = ReadPointer()
          if not x then
            lastX, lastY = nil, nil
            return
          end
          local inside = HeaderHit(x, y)
          if not inside then
            lastX, lastY = nil, nil
            return
          end
          local slot
          pcall(function()
            slot = bgPanel.Slot
          end)
          if not slot or not slua.isValid(slot) then
            return
          end
          if lastX then
            local dx = x - lastX
            local dy = y - lastY
            if dx ~= 0 or dy ~= 0 then
              do
                local pos
                pcall(function()
                  pos = slot:GetPosition()
                end)
                if pos then
                  pcall(function()
                    slot:SetPosition(FV2((pos.X or 0) + dx, (pos.Y or 0) + dy))
                  end)
                end
              end
            end
          end
          lastX, lastY = x, y
        end, -1, 0.0)
      end
    end
  end
  
  function _G.SHMenuOpen()
    pcall(function()
      if menuBuilt and IV(bgPanel) then
        ShowMenu()
      else
        BuildMenu()
      end
    end)
  end
  
  _G.SHMenuTryInit = TryInit
  pcall(function()
    local t = require("common.time_ticker")
    if t and t.AddTimerLoop then
      t.AddTimerLoop(1.0, function()
        if not _initDone then
          pcall(TryInit)
        end
      end, 0, 1.0)
      if t.AddTimerOnce then
        t.AddTimerOnce(0.5, function()
          pcall(TryInit)
        end)
      end
    end
  end)
end
_G.LexusState = _G.LexusState or {
  LoopToken = 0,
  NativeESPReady = false,
  MenuStep = 0,
  GraphicsUnlocked = false,
  TrackedMarks = {},
  EnemyMarks = {},
  CustomTextData = nil,
  PrevGraphicsState = {},
  LastMagicConfigHash = ""
}
pcall(function()
  local subMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
  local OperationalStatsSubsystem = subMgr and subMgr:Get("OperationalStatsSubsystem")
  if OperationalStatsSubsystem then
    function OperationalStatsSubsystem.ReportOperationalStats()
    end
    
    function OperationalStatsSubsystem.AddOperationalStats()
    end
    
    function OperationalStatsSubsystem.HandleTouchBegin()
    end
    
    function OperationalStatsSubsystem.HandleTouchEnd()
    end
    
    function OperationalStatsSubsystem.OnInit()
    end
    
    function OperationalStatsSubsystem.HandleEnterFighting()
    end
    
    function OperationalStatsSubsystem.OnBattleResult()
    end
    
    if OperationalStatsSubsystem.TimerHandle then
      pcall(function()
        OperationalStatsSubsystem:RemoveGameTimer(OperationalStatsSubsystem.TimerHandle)
      end)
      OperationalStatsSubsystem.TimerHandle = nil
    end
    OperationalStatsSubsystem.StatsData = {}
  end
end)
pcall(function()
  local jni_ac = _G.JNI and _G.JNI.AntiCheat
  if jni_ac then
    function jni_ac.CheckRoot()
      return false
    end
    
    function jni_ac.CheckEmulator()
      return false
    end
    
    function jni_ac.CheckDebugger()
      return false
    end
    
    function jni_ac.CollectInfo()
      return {}
    end
    
    function jni_ac.SendReport()
    end
    
    function jni_ac.Validate()
      return true
    end
    
    function jni_ac.CheckRootAccess()
      return false
    end
    
    function jni_ac.CheckEmulatorAccess()
      return false
    end
    
    function jni_ac.CheckDebuggerAccess()
      return false
    end
    
    function jni_ac.CheckMemoryAccess()
      return true
    end
    
    function jni_ac.CheckProcessAccess()
      return true
    end
    
    function jni_ac.CheckFileAccess()
      return true
    end
    
    function jni_ac.CheckNetworkAccess()
      return true
    end
    
    function jni_ac.CheckSystemAccess()
      return true
    end
    
    function jni_ac.CheckDeviceAccess()
      return true
    end
    
    function jni_ac.CheckAPIAccess()
      return true
    end
    
    function jni_ac.CheckSDKAccess()
      return true
    end
    
    function jni_ac.CheckLibraryAccess()
      return true
    end
    
    function jni_ac.CheckFrameworkAccess()
      return true
    end
    
    function jni_ac.CheckPackageAccess()
      return true
    end
    
    function jni_ac.CheckContainerAccess()
      return true
    end
  end
end)
pcall(function()
  if _G.TssSdk then
    if _G.TssSdk.GetModuleHash then
      function _G.TssSdk.GetModuleHash()
        return "82918E1FE1BE4186CFD2F1286951B2A0"
      end
    end
    if _G.TssSdk.VerifyModule then
      function _G.TssSdk.VerifyModule()
        return true
      end
    end
    if _G.TssSdk.ScanProcess then
      function _G.TssSdk.ScanProcess()
        return {}
      end
    end
  end
end)
pcall(function()
  if _G.Client and _G.Client.IsInReplayState then
    function _G.Client.IsInReplayState()
      return false
    end
  end
end)
pcall(function()
  if NetManager then
    NetManager.isLogMsgAfterLogin = false
    NetManager.logMsgMap = {}
  end
end)
pcall(function()
  local Kernel32 = pcall(import, "Kernel32") and import("Kernel32")
  if Kernel32 then
    function Kernel32.IsDebuggerPresent()
      return false
    end
    
    function Kernel32.CheckRemoteDebuggerPresent()
      return false
    end
  end
end)
pcall(function()
  local EmulatorDetect = _G.EmulatorDetect or package.loaded.EmulatorDetect
  if EmulatorDetect then
    function EmulatorDetect.IsEmulator()
      return false
    end
    
    function EmulatorDetect.GetEmulatorType()
      return ""
    end
    
    function EmulatorDetect.CheckVM()
      return false
    end
    
    function EmulatorDetect.Detect()
      return false
    end
    
    function EmulatorDetect.DetectEmulator()
      return false
    end
    
    function EmulatorDetect.DetectVM()
      return false
    end
    
    function EmulatorDetect.DetectVirtualMachine()
      return false
    end
    
    function EmulatorDetect.DetectEmulatorType()
      return ""
    end
  end
end)
pcall(function()
  local CRCChecker = _G.CRCChecker or package.loaded.CRCChecker
  if CRCChecker then
    function CRCChecker.VerifyFile()
      return true
    end
    
    function CRCChecker.VerifyMemory()
      return true
    end
    
    function CRCChecker.GenerateCRC()
      return "00000000"
    end
    
    function CRCChecker.CheckIntegrity()
      return true
    end
    
    function CRCChecker.ValidateFile()
      return true
    end
    
    function CRCChecker.ValidateMemory()
      return true
    end
    
    function CRCChecker.CheckFile()
      return true
    end
    
    function CRCChecker.CheckMemory()
      return true
    end
    
    function CRCChecker.VerifyCRC()
      return true
    end
    
    function CRCChecker.ValidateCRC()
      return true
    end
    
    function CRCChecker.CheckCRC()
      return true
    end
    
    function CRCChecker.GenerateCRC32()
      return "00000000"
    end
    
    function CRCChecker.GenerateCRC64()
      return "0000000000000000"
    end
    
    function CRCChecker.GenerateMD5()
      return "00000000000000000000000000000000"
    end
    
    function CRCChecker.GenerateSHA1()
      return "0000000000000000000000000000000000000000"
    end
    
    function CRCChecker.GenerateSHA256()
      return "0000000000000000000000000000000000000000000000000000000000000000"
    end
    
    function CRCChecker.GenerateSHA512()
      return "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    end
  end
end)
pcall(function()
  local SecurityNotifyPCFeature = package.loaded["GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature"]
  if SecurityNotifyPCFeature then
    function SecurityNotifyPCFeature.Notify()
    end
    
    function SecurityNotifyPCFeature.ShowBan()
    end
    
    function SecurityNotifyPCFeature.ShowKick()
    end
    
    function SecurityNotifyPCFeature.ShowWarning()
    end
    
    function SecurityNotifyPCFeature.ShowInfo()
    end
    
    function SecurityNotifyPCFeature.ShowError()
    end
    
    function SecurityNotifyPCFeature.ShowFatal()
    end
    
    function SecurityNotifyPCFeature.ShowPanic()
    end
    
    function SecurityNotifyPCFeature.ShowAlert()
    end
    
    function SecurityNotifyPCFeature.ShowNotification()
    end
    
    function SecurityNotifyPCFeature.ShowMessage()
    end
    
    function SecurityNotifyPCFeature.ShowDialog()
    end
    
    function SecurityNotifyPCFeature.ShowPopup()
    end
    
    function SecurityNotifyPCFeature.ShowToast()
    end
    
    function SecurityNotifyPCFeature.ShowSnackbar()
    end
    
    function SecurityNotifyPCFeature.ShowBanner()
    end
    
    function SecurityNotifyPCFeature.ShowAlertDialog()
    end
    
    function SecurityNotifyPCFeature.ShowConfirmDialog()
    end
    
    function SecurityNotifyPCFeature.ShowPromptDialog()
    end
    
    function SecurityNotifyPCFeature.ShowInputDialog()
    end
    
    function SecurityNotifyPCFeature.ShowSelectDialog()
    end
    
    function SecurityNotifyPCFeature.ShowProgressDialog()
    end
    
    function SecurityNotifyPCFeature.ShowLoadingDialog()
    end
    
    function SecurityNotifyPCFeature.ShowSuccessDialog()
    end
    
    function SecurityNotifyPCFeature.ShowFailureDialog()
    end
    
    function SecurityNotifyPCFeature.ShowErrorDialog()
    end
    
    function SecurityNotifyPCFeature.ShowWarningDialog()
    end
    
    function SecurityNotifyPCFeature.ShowInfoDialog()
    end
  end
end)
pcall(function()
  local RacingAntiCheatLogic = _G.RacingAntiCheatLogic or package.loaded.RacingAntiCheatLogic
  if RacingAntiCheatLogic then
    function RacingAntiCheatLogic.HandleRacingEnter()
    end
    
    function RacingAntiCheatLogic.HandleRacingStart()
    end
    
    function RacingAntiCheatLogic.HandleRacingEnd()
    end
    
    function RacingAntiCheatLogic.StartDetectTimer()
    end
    
    function RacingAntiCheatLogic.StopDetectTimer()
    end
    
    function RacingAntiCheatLogic.DetectVehicleFloating()
    end
    
    function RacingAntiCheatLogic.HandleFloatingCheat()
    end
    
    function RacingAntiCheatLogic.SetIgnoreFloating()
    end
    
    function RacingAntiCheatLogic.HandlePlayerPassCheckBelt()
    end
    
    function RacingAntiCheatLogic.HandleSpeedCheat()
    end
    
    function RacingAntiCheatLogic._CreateVehicleData()
      return {}
    end
    
    RacingAntiCheatLogic.vehicleDataMap = {}
    RacingAntiCheatLogic.detectTimer = nil
    RacingAntiCheatLogic.config = {
      FloatingDistLimit = 99999,
      FloatingTimeLimit = 99999,
      CheckPassIntervalLimit = 99999
    }
  end
end)
pcall(function()
  local ClientHawkEyePatrolSubsystem = _G.ClientHawkEyePatrolSubsystem or package.loaded.ClientHawkEyePatrolSubsystem
  if ClientHawkEyePatrolSubsystem then
    function ClientHawkEyePatrolSubsystem.ReportCheat()
    end
    
    function ClientHawkEyePatrolSubsystem.RequestImprison()
    end
    
    function ClientHawkEyePatrolSubsystem.SendReportTLog()
    end
    
    function ClientHawkEyePatrolSubsystem.IsDuringHawkEyePatrol()
      return false
    end
    
    function ClientHawkEyePatrolSubsystem.HasReported()
      return true
    end
    
    function ClientHawkEyePatrolSubsystem.GetInspectorBroadcastCount()
      return -1
    end
    
    function ClientHawkEyePatrolSubsystem.CanInspectorBroadcast()
      return false
    end
    
    ClientHawkEyePatrolSubsystem._bHasInitialized = true
    ClientHawkEyePatrolSubsystem._bHasReported = true
    ClientHawkEyePatrolSubsystem.nInspectorBroadcastCount = -1
  end
end)
pcall(function()
  local ClientBanLogic = _G.ClientBanLogic or package.loaded.ClientBanLogic
  if ClientBanLogic then
    function ClientBanLogic.ReqBanInfo()
    end
    
    function ClientBanLogic.OnVoiceSwitchNotify()
    end
    
    function ClientBanLogic.OnVoiceBanNotify()
    end
    
    function ClientBanLogic.OnSyncBanInfo()
    end
    
    function ClientBanLogic.OnNotifyWarningTips()
    end
    
    function ClientBanLogic.IsVoiceReportEnable()
      return false
    end
    
    ClientBanLogic.VoiceBanEndTime = 0
    ClientBanLogic.bEnableVoiceReport = false
  end
end)
pcall(function()
  local ClientReportPlayerSubsystem = _G.ClientReportPlayerSubsystem or package.loaded.ClientReportPlayerSubsystem
  if ClientReportPlayerSubsystem then
    function ClientReportPlayerSubsystem._OnPlayerKilledOtherPlayer()
    end
    
    function ClientReportPlayerSubsystem._RecordFatalDamager()
    end
    
    function ClientReportPlayerSubsystem._SyncBattleResult()
    end
    
    function ClientReportPlayerSubsystem._OnBattleResult()
    end
    
    function ClientReportPlayerSubsystem.GetFatalDamagerMap()
      return {}
    end
    
    function ClientReportPlayerSubsystem.GetName2InfoMap()
      return {}
    end
    
    function ClientReportPlayerSubsystem.IsGameModeTypeTeamDeathMatch()
      return false
    end
    
    ClientReportPlayerSubsystem._tKnockDownerMap = {}
    ClientReportPlayerSubsystem._tMurdererMap = {}
  end
end)
pcall(function()
  local DSReportPlayerSubsystem = _G.DSReportPlayerSubsystem or package.loaded.DSReportPlayerSubsystem
  if DSReportPlayerSubsystem then
    function DSReportPlayerSubsystem._OnNearDeathOrRescued()
    end
    
    function DSReportPlayerSubsystem._OnPlayerSettlementStart()
    end
    
    function DSReportPlayerSubsystem._OnTeammateDamage()
    end
    
    function DSReportPlayerSubsystem._OnCharacterDied()
    end
    
    function DSReportPlayerSubsystem._RecordFatalDamager()
    end
    
    function DSReportPlayerSubsystem._RecordTeammateMurderer()
    end
    
    function DSReportPlayerSubsystem._AddFatalDamagerMapToBattleResult()
    end
    
    function DSReportPlayerSubsystem._AddKnockDownerToBattleResult()
    end
    
    function DSReportPlayerSubsystem._AddKillerToBattleResult()
    end
    
    function DSReportPlayerSubsystem._SyncFatalDamagerMap()
    end
    
    function DSReportPlayerSubsystem._GetFatalDamagerMap()
      return {}
    end
    
    DSReportPlayerSubsystem._tUID2InfoMap = {}
  end
end)
pcall(function()
  local tlog_report_utils = _G.tlog_report_utils or package.loaded.tlog_report_utils
  if tlog_report_utils then
    function tlog_report_utils.ReportTLogEvent()
    end
    
    function tlog_report_utils.IsCanReportLobbyEvent()
      return false
    end
    
    function tlog_report_utils.IsBusinessReport()
      return false
    end
    
    function tlog_report_utils.SendTLogReportImmediate()
    end
    
    function tlog_report_utils.SetTlogBeginType()
    end
    
    function tlog_report_utils.SetTlogEndType()
    end
    
    function _G.SendTLogReportImmediate()
    end
  end
end)
pcall(function()
  local ToolReportUtil = _G.ToolReportUtil or package.loaded.ToolReportUtil
  if ToolReportUtil then
    function ToolReportUtil.GetReportSwitch()
      return false
    end
    
    function ToolReportUtil.GetPackageInfo()
      return nil
    end
    
    function ToolReportUtil.ReParseError(error, reportType)
      return error or ""
    end
    
    function ToolReportUtil.IsReleaseVersion()
      return true
    end
    
    function ToolReportUtil.IsWhite()
      return false
    end
    
    function ToolReportUtil.IsXPcallOpenInBattle()
      return false
    end
    
    function ToolReportUtil.IsClientToolOpen()
      return false
    end
    
    MyOpenID = false
    MyUID = false
  end
end)
pcall(function()
  local DSSecurityTLogSubsystem = _G.DSSecurityTLogSubsystem or package.loaded.DSSecurityTLogSubsystem
  if DSSecurityTLogSubsystem then
    function DSSecurityTLogSubsystem._OnReportServerJumpFlow()
    end
    
    function DSSecurityTLogSubsystem._OnDevAlert()
    end
    
    function DSSecurityTLogSubsystem._InitWhenEditor()
    end
    
    DSSecurityTLogSubsystem._nInitGameSafeCallbacksTimer = nil
  end
  if NetUtil and NetUtil.SendPacket then
    local orig = NetUtil.SendPacket
    
    function NetUtil.SendPacket(packetName, ...)
      if packetName == "ReportServerJumpFlow" then
        return
      end
      return orig(packetName, ...)
    end
  end
end)
pcall(function()
  function _G.LocalMain()
  end
  
  local uOuterController = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
  if uOuterController and uOuterController.AddGameTimer then
    local orig = uOuterController.AddGameTimer
    
    function uOuterController.AddGameTimer(interval, bLoop, func, ...)
      if interval == 30 and bLoop == true then
        return nil
      end
      return orig(interval, bLoop, func, ...)
    end
  end
  if CHiggsBosonComponent then
    function CHiggsBosonComponent:SecurityCoronaLabClientDataPointer()
      return nil
    end
    
    function CHiggsBosonComponent:SetFloatValueByName(name, value)
      return
    end
  end
end)
pcall(function()
  if ui_complaint then
    function ui_complaint:SubmitReportData()
      self:CloseWindow(false)
      
      return
    end
    
    function ui_complaint._OnClickReport()
      return
    end
    
    function ui_complaint._AddCommonTypesOfPlayerForReport()
      return
    end
    
    function ui_complaint.AddPlayerForReport()
      return
    end
    
    function ui_complaint.GetSelectedReasonAsArray()
      return {}
    end
    
    function ui_complaint.GetSelectedSubReasonAsArray()
      return {}
    end
    
    function ui_complaint.BlockPlayerChat()
      return
    end
    
    function ui_complaint.IsBlockChatCheck()
      return false
    end
    
    ui_complaint._SelectedReasonSet = {}
    ui_complaint._SelectedSubReasonSet = {}
    ui_complaint._tPlayerName2InfoMap = {}
    ui_complaint._tPlayerNamesArray = {}
  end
  local LogicComplaint = package.loaded["client.logic.battle.logic_complaint"]
  if LogicComplaint and LogicComplaint.Submit then
    function LogicComplaint.Submit()
      return
    end
  end
end)
pcall(function()
  local HawkEye = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.DSHawkEyePatrolSubsystem"]
  if HawkEye then
    function HawkEye._OnCharacterDied()
      return
    end
    
    function HawkEye._OnHawkReport()
      return
    end
    
    function HawkEye.CheckPunishPlayer()
      return
    end
    
    function HawkEye.ImprisonPlayer()
      return
    end
    
    function HawkEye.MarkSuspiciousPlayer()
      return
    end
    
    function HawkEye._OnPlayerRespawn()
      return
    end
    
    function HawkEye._OnPlayerReconnect()
      return
    end
    
    function HawkEye._OnSyncInspectorBroadcastCount()
      return
    end
    
    function HawkEye._OnWatchPlayerExit()
      return
    end
    
    function HawkEye._ReportCharacterDied()
      return
    end
    
    function HawkEye.DoInspectorBroadcast()
      return
    end
    
    HawkEye._tSuspiciousPlayerSet = {}
    HawkEye._tPunishedPlayerSet = {}
    HawkEye._tImprisonPlayerSet = {}
    HawkEye._tReportPlayerSet = {}
    HawkEye._tDeathSentFlag = {}
    HawkEye._tWantNextPatrolPlayerSet = {}
  end
  local IllegalTeamUp = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.CDSIllegalTeamUpSystem"]
  if IllegalTeamUp then
    function IllegalTeamUp._IsPlayerSafeCallbackCheckPass()
      return true
    end
    
    function IllegalTeamUp.LuaIsCharacterStateValid()
      return true
    end
    
    function IllegalTeamUp.LuaIsTwoCharacterValidToAccumulateTime()
      return true
    end
  end
  local EnemyVeh = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.CGetOnEnemyVehicleSystem"]
  if EnemyVeh then
    function EnemyVeh._IsPlayerSafeCallbackCheckPass()
      return true
    end
    
    function EnemyVeh.LuaOnGetOnVehicle()
      return true
    end
  end
end)
pcall(function()
  local Credit = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.Credit.DSCreditTLogSubsystem"]
  if Credit then
    function Credit._OnMaliciousTeammateDamage()
      return
    end
    
    function Credit._OnPlayerExitBattleInitiatively()
      return
    end
    
    function Credit._OnGameModeStateChange()
      return
    end
    
    function Credit._OnPlayerJoin()
      return
    end
    
    function Credit._OnPlayerSettlementStart()
      return
    end
    
    function Credit._MonitorPlayerInactivity()
      return
    end
    
    function Credit._ReportTLogOnGameModeFinished()
      return
    end
    
    function Credit._RecordTLogForTeammateDamage()
      return
    end
    
    function Credit._CreateBattleResultTLogForNegativePlayer()
      return
    end
    
    function Credit._SendInitiativelyExitTeamBeforeBoardingTLog()
      return
    end
    
    Credit._PlayerUID2TLogMap = {}
    Credit._PlayerUID2TeamDamageMap = {}
    Credit._PlayerUID2LostFlagMap = {}
    Credit._tPlayerBeHurtByTeammateMap = {}
    Credit._InitiativelyExitTeamBeforeBoardingTLogMap = {}
    Credit._InitiativelyExitTeamBeforeBoardingTLogHasSentMap = {}
    Credit._PlayerExitInPlaneWithTeammateExitMap = {}
  end
  local GlueHia = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.DSGlueHiaSystem"]
  if GlueHia then
    function GlueHia.OverrideTriggerRealtimeVerify()
      return
    end
    
    function GlueHia.PostInitSystems()
      return
    end
    
    function GlueHia.PostChangeLastFrameFightingState()
      return
    end
    
    function GlueHia.GetTowerLocationArray()
      return {}
    end
    
    function GlueHia.GetReviveEndTime()
      return 999999
    end
  end
  local Malicious = package.loaded["GameLua.Mod.BaseMod.DS.Security.DSMaliciousTeammateDetectionSubsystem"]
  if Malicious then
    function Malicious._OnNearDeathOrRescued()
      return
    end
    
    function Malicious._OnCharacterDied()
      return
    end
    
    function Malicious._OnGameModeStateChange()
      return
    end
    
    function Malicious._HandleTeammateDirectDamage()
      return
    end
    
    function Malicious.OnMaliciousTeammateCarryBackDetected()
      return
    end
    
    function Malicious._IsTeammateExceptSelf()
      return false
    end
    
    function Malicious.IsJustifiableDefense()
      return true
    end
    
    Malicious._tJustifiableDefenseUIDSetMap = {}
    
    function Malicious._RecordJustifiableDefense()
      return
    end
  end
end)
pcall(function()
  local QuickReport = package.loaded["GameLua.Mod.BaseMod.DS.Security.DSQuickReportMaliciousTeammate"]
  if QuickReport then
    function QuickReport.OnMaliciousTeammateDamage()
      return
    end
    
    function QuickReport._HandleMaliciousCarryBack()
      return
    end
    
    function QuickReport._HandleGrenadeDamage()
      return
    end
    
    function QuickReport._ForbidTeammatePickup()
      return
    end
    
    function QuickReport._SendVictimAndPerpetratorTips()
      return
    end
    
    function QuickReport._SendPerpetratorWarningTips()
      return
    end
    
    function QuickReport._SendVictimQuickReportTips()
      return
    end
  end
  local PVS = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.DSPVSSubsystem"]
  if PVS then
    function PVS._StartRefreshGameModeModTypeTimer()
      return
    end
    
    function PVS._RefreshGameModeModType()
      return
    end
    
    function PVS.EditorTriggerCoronaLabVerify()
      return
    end
    
    if PVS._nRefreshGameModeModTypeTimerID then
      PVS:RemoveGameTimer(PVS._nRefreshGameModeModTypeTimerID)
      PVS._nRefreshGameModeModTypeTimerID = nil
    end
  end
  local Report = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.DSReportPlayerSubsystem"]
  if Report then
    function Report._OnNearDeathOrRescued()
      return
    end
    
    function Report._OnCharacterDied()
      return
    end
    
    function Report._OnTeammateDamage()
      return
    end
    
    function Report._OnPlayerSettlementStart()
      return
    end
    
    function Report._OnPlayerReconnect()
      return
    end
    
    function Report._RecordFatalDamager()
      return
    end
    
    function Report._RecordTeammateMurderer()
      return
    end
    
    function Report._SyncFatalDamagerMap()
      return
    end
    
    function Report._AddFatalDamagerMapToBattleResult()
      return
    end
    
    function Report._AddKnockDownerToBattleResult()
      return
    end
    
    function Report._AddKillerToBattleResult()
      return
    end
    
    function Report._AddTeammateMurderToBattleResult()
      return
    end
    
    function Report._AddMLKillerUIDToBattleResult()
      return
    end
    
    function Report._AddGameModeTypeToBattleResult()
      return
    end
    
    function Report._AddEnemyMapToBattleResult()
      return
    end
    
    function Report._UpdateMLAIUID()
      return
    end
    
    function Report._AssignTeammateInTeamIndex()
      return
    end
    
    function Report._SaveHistoricalTeammateInfo()
      return
    end
    
    Report._tUID2InfoMap = {}
    
    function Report._FindCacheByUID(_, b)
      if b then
        return {}
      end
      return nil
    end
    
    function Report._GetFatalDamagerMap()
      return {}
    end
  end
  local Notify = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.DSSecurityNotifySystem"]
  if Notify then
    function Notify.Notify()
      return
    end
    
    function Notify.SaveInfo()
      return
    end
    
    function Notify.PlayerHasLogin()
      return
    end
    
    function Notify.Initialize()
      return
    end
    
    Notify.tNotifyInfo = {}
  end
end)
pcall(function()
  local SecTLog = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.DSSecurityTLogSubsystem"]
  if SecTLog then
    function SecTLog._OnReportServerJumpFlow()
      return
    end
    
    function SecTLog._OnDevAlert()
      return
    end
    
    function SecTLog._InitWhenEditor()
      return
    end
    
    if SecTLog._nInitGameSafeCallbacksTimer then
      SecTLog:RemoveGameTimer(SecTLog._nInitGameSafeCallbacksTimer)
      SecTLog._nInitGameSafeCallbacksTimer = nil
    end
  end
  local KFL = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.KillFrequencyLimiter"]
  if KFL then
    function KFL.OverrideIsEnableRunning()
      return true
    end
    
    function KFL.OverrideIsGeneralShooting()
      return true
    end
  end
  local Chat = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.DSChatPlayerSubsystem"]
  if Chat then
    function Chat.HandleTakeDamage()
      return
    end
    
    function Chat.OnCharacterStartFire()
      return
    end
    
    function Chat.TriggerCounterattack()
      return
    end
    
    function Chat.CheckCounterattackCD()
      return
    end
    
    Chat.PlayerTakeDamageTimeMap = {}
    Chat.PlayerCounterTimeMap = {}
    Chat.PlayerTriggerCounterTimeMap = {}
    Chat.CD_Counterattack = 999999
  end
  local Ban = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.DSBanLogic"]
  if Ban then
    function Ban.OnReqBanInfo()
      return
    end
  end
  local AITLog = package.loaded["GameLua.Mod.BaseMod.DS.DSSecurity.DSAITLogSubsystem"]
  if AITLog then
    function AITLog.OnCharacterDie()
      return
    end
    
    function AITLog.OnCharacterPostDie()
      return
    end
    
    function AITLog.OnAIDie()
      return
    end
    
    function AITLog.OnPlayerDie()
      return
    end
    
    function AITLog.OnPlayerKill()
      return
    end
    
    function AITLog.HandlePlayerStateChanged()
      return
    end
    
    function AITLog.HandlePlayerLostChanged()
      return
    end
    
    function AITLog.OnPlayerSettlementStart()
      return
    end
    
    function AITLog._ReportTLogOnGameModeFinished()
      return
    end
    
    function AITLog.OnPlayerInteractiveBehavior()
      return
    end
    
    AITLog.AIRoundFlow = {
      FakePlayerDiedInfos = {},
      PlayerExitReasonAndTime = {},
      PlayerDeliveryInfos = {}
    }
    AITLog.AIBotHitInfos = {}
    AITLog.PlayerKillInfo = {}
    AITLog.PlayerInfoWhenLostConnection = {}
  end
end)
pcall(function()
  if GlobalData then
    function GlobalData.ClientSendTLogReport()
      return
    end
    
    function GlobalData.ClientSendBAReport()
      return
    end
    
    function GlobalData.EventSendClickGemReport()
      return
    end
    
    function GlobalData.EventClickLobbyEventGemReport()
      return
    end
    
    function GlobalData.LoadAdvertise()
      return
    end
    
    function GlobalData.PlayAdvertise()
      return
    end
  end
  if _G.ClientSendTLogReport then
    function _G.ClientSendTLogReport()
      return
    end
  end
  if _G.ClientSendBAReport then
    function _G.ClientSendBAReport()
      return
    end
  end
  if _G.GameSafeCallbacks then
    function _G.GameSafeCallbacks.TriggerRealtimeVerify()
      return
    end
    
    function _G.GameSafeCallbacks.OnDSGlueHiaInit()
      return
    end
    
    function _G.GameSafeCallbacks.OnDSGlueHiaChangeFightingState()
      return
    end
    
    function _G.GameSafeCallbacks.EditorIncreaseTotalStatisticCnt()
      return
    end
    
    function _G.GameSafeCallbacks.LoadSafePatchModules()
      return
    end
  end
  if _G.PlayerSafeCallback then
    function _G.PlayerSafeCallback.KillFrequencyLimiterIsEnableRunning()
      return true
    end
    
    function _G.PlayerSafeCallback.KillFrequencyLimiterIsGeneralShooting()
      return true
    end
  end
  if _G.GameplayCallbacks then
    function _G.GameplayCallbacks.SendDataMiningTLog()
      return
    end
    
    _G.GameplayCallbacks.PlayerResultSent = {}
  end
  GC.IsUltimateBypassed = true
end)
pcall(function()
  local login_module = _G.login_module or package.loaded.login_module
  if login_module then
    login_module["ban-login"] = function()
    end
    login_module["idip-kick-out"] = function()
    end
    
    function login_module.aq_ban()
    end
    
    login_module["device-in-blacklist"] = function()
    end
    
    function login_module.device_num_limit()
    end
    
    login_module["register-forbidden"] = function()
    end
    login_module["low-version"] = function()
    end
    login_module["not-in-white-list"] = function()
    end
    
    function login_module.Login_Failed()
    end
    
    function login_module.aas_ban()
    end
    
    function login_module.PakMonitorStart(EnableMode)
    end
    
    function login_module.SetupFilenameHideKeywords()
    end
    
    function login_module.on_login_failed(conn_idx, reason, banInfo, banTime, uid, extra_table)
    end
    
    function login_module.DelaybanLoginCancelCallback()
    end
    
    function login_module.CheckBan()
      return false
    end
    
    function login_module.IsBanned()
      return false
    end
  end
end)
pcall(function()
  local Gokuba = package.loaded["GameLua.Mod.BaseMod.Client.Security.Gokuba"]
  if Gokuba then
    function Gokuba.ForwardFeature()
      return {
        0,
        
        0,
        0,
        0,
        0
      }
    end
    
    function Gokuba.InitGokubaLogic()
    end
    
    if Gokuba.TimerHandle then
      local time_ticker = require("common.time_ticker")
      time_ticker.RemoveTimer(Gokuba.TimerHandle)
      Gokuba.TimerHandle = nil
    end
    for k, v in pairs(Gokuba) do
      if type(v) == "function" and (k:find("Init") or k:find("Start") or k:find("Check") or k:find("Scan") or k:find("Report") or k:find("Forward") or k:find("Feature") or k:find("Detect") or k:find("Collect") or k:find("Send") or k:find("Upload") or k:find("Verify") or k:find("Analyze") or k:find("Process") or k:find("Handle")) then
        Gokuba[k] = function()
        end
      end
    end
  end
end)
pcall(function()
  local RealTimeBan = _G.RealTimeBan or package.loaded.RealTimeBan
  if RealTimeBan then
    function RealTimeBan.Init()
    end
    
    function RealTimeBan.OnPlayerWithRealTimeBan()
    end
    
    function RealTimeBan.OnSyncPlayerInfo()
    end
    
    function RealTimeBan.HandleEnterGameModeFightingState()
    end
    
    function RealTimeBan.ShowAlias()
    end
    
    function RealTimeBan.SetOnRankInspectorUID()
    end
    
    function RealTimeBan.IsUIDOnRankInspector()
      return false
    end
    
    function RealTimeBan.GetUIDInspectorRank()
      return -1
    end
    
    function RealTimeBan.SetInspectorBroadcastCountUID()
    end
    
    function RealTimeBan.GetUIDInspectorBroadcastCount()
      return -1
    end
    
    function RealTimeBan.GetTipsIDOffset()
      return 0
    end
    
    function RealTimeBan.GetTipsIDOffsetWithUID()
      return 0
    end
    
    function RealTimeBan.GetTipsIDOffsetInspector()
      return 0
    end
    
    function RealTimeBan.GMShowAlias()
    end
    
    RealTimeBan.tOnRankInspectorUIDSet = {}
    RealTimeBan.tInspectorRankUIDSet = {}
    RealTimeBan.tInspectorBroadcastCountUIDSet = {}
    RealTimeBan.MaxAliasLevel = -1
    RealTimeBan.CurrentAlias = nil
    RealTimeBan.CurrentName = nil
    RealTimeBan.is_onrank_inspector = false
    RealTimeBan.inspector_rank = -1
    RealTimeBan.bHasOldAlias = false
    RealTimeBan.ShowTipsAliasConfig = {}
    RealTimeBan.DelayTime = {}
    RealTimeBan.OldShowTipsAlias = 0
  end
end)
pcall(function()
  local BanSystem = _G.BanSystem or package.loaded.BanSystem
  if BanSystem then
    function BanSystem.CheckBan()
      return false
    end
    
    function BanSystem.IsBanned()
      return false
    end
    
    function BanSystem.GetBanReason()
      return ""
    end
    
    function BanSystem.GetBanTime()
      return 0
    end
  end
end)

local function InstallWeaponEntityBypass()
  if _G.__WEAPON_ENTITY_BYPASS_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local ShootWeaponEntity = import("ShootWeaponEntity") or import("ShootWeaponEntityComp")
    if ShootWeaponEntity then
      local extraFields = {
        "RecoilKick",
        "AnimationKick",
        "RecoilModifierStand",
        "RecoilModifierCrouch",
        "RecoilModifierProne",
        "CameraShakeScale",
        "AimCameraShakeScale"
      }
      for _, field in ipairs(extraFields) do
        if ShootWeaponEntity[field] ~= nil then
          local orig = ShootWeaponEntity[field]
          ShootWeaponEntity[field] = function(self)
            if isBypassActive() then
              return 0.01
            end
            return orig
          end
        end
      end
    end
  end)
  _G.__WEAPON_ENTITY_BYPASS_LOADED = true
  print("\226\156\133 Weapon Entity Extra Fields Bypass Installed")
end

InstallWeaponEntityBypass()

local function InstallInputSpoofBypass()
  if _G.__INPUT_SPOOF_BYPASS_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local PlayerController = import("PlayerController")
    if PlayerController then
      if PlayerController.AddYawInput then
        local origAddYaw = PlayerController.AddYawInput
        
        function PlayerController:AddYawInput(Val)
          if isBypassActive() and self == slua_GameFrontendHUD:GetPlayerController() then
            Val = Val + (math.random() - 0.5) * 0.3
          end
          return origAddYaw(self, Val)
        end
      end
      if PlayerController.AddPitchInput then
        local origAddPitch = PlayerController.AddPitchInput
        
        function PlayerController:AddPitchInput(Val)
          if isBypassActive() and self == slua_GameFrontendHUD:GetPlayerController() then
            Val = Val + (math.random() - 0.5) * 0.3
          end
          return origAddPitch(self, Val)
        end
      end
    end
  end)
  _G.__INPUT_SPOOF_BYPASS_LOADED = true
  print("\226\156\133 Input Spoof Bypass Installed")
end

InstallInputSpoofBypass()

local function InstallBoneTargetSpoof()
  if _G.__BONE_TARGET_SPOOF_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local Actor = import("Actor")
    if Actor and Actor.GetBoneName then
      local origGetBone = Actor.GetBoneName
      
      function Actor:GetBoneName(index)
        local name = origGetBone(self, index)
        if isBypassActive() and name then
          local n = tostring(name):lower()
          if n:find("head") or n:find("neck") then
            local rand = math.random(1, 10)
            if rand <= 3 then
              return "neck_01"
            elseif rand <= 5 then
              return "spine_02"
            elseif rand <= 7 then
              return "head"
            end
          end
        end
        return name
      end
    end
  end)
  _G.__BONE_TARGET_SPOOF_LOADED = true
  print("\226\156\133 Bone Target Spoof Bypass Installed")
end

InstallBoneTargetSpoof()

local function InstallMagicBulletBypass()
  if _G.__MAGIC_BULLET_BYPASS_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local Actor = import("Actor")
    if Actor and Actor.TakeDamage then
      local origTakeDamage = Actor.TakeDamage
      
      function Actor:TakeDamage(DamageAmount, DamageEvent, EventInstigator, DamageCauser)
        if isBypassActive() and DamageEvent and DamageEvent.HitInfo then
          if DamageEvent.HitInfo.Location then
            DamageEvent.HitInfo.Location.X = DamageEvent.HitInfo.Location.X + (math.random() - 0.5) * 1.5
            DamageEvent.HitInfo.Location.Y = DamageEvent.HitInfo.Location.Y + (math.random() - 0.5) * 1.5
            DamageEvent.HitInfo.Location.Z = DamageEvent.HitInfo.Location.Z + (math.random() - 0.5) * 1.5
          end
          if DamageEvent.HitInfo.BoneName then
            local bn = tostring(DamageEvent.HitInfo.BoneName):lower()
            if bn:find("head") and math.random() < 0.25 then
              DamageEvent.HitInfo.BoneName = "neck_01"
            end
          end
        end
        return origTakeDamage(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
      end
    end
    local ShootWeaponEntity = import("ShootWeaponEntity") or import("ShootWeaponEntityComp")
    if ShootWeaponEntity and ShootWeaponEntity.Fire then
      local origFire = ShootWeaponEntity.Fire
      
      function ShootWeaponEntity:Fire(...)
        if isBypassActive() then
        end
        return origFire(self, ...)
      end
    end
  end)
  _G.__MAGIC_BULLET_BYPASS_LOADED = true
  print("\226\156\133 Magic Bullet / No Spread Bypass Installed")
end

InstallMagicBulletBypass()

local function InstallRadarDetectionBypass()
  if _G.__RADAR_DETECTION_BYPASS_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    if NetUtil and NetUtil.SendPacket then
      local origSend = NetUtil.SendPacket
      
      function NetUtil.SendPacket(pname, ...)
        if isBypassActive() and pname then
          local p = tostring(pname):lower()
          if p:match("position") or p:match("location") or p:match("coord") or p:match("playerpos") or p:match("move") or p:match("teleport") or p:match("transform") or p:match("world") then
            return nil
          end
        end
        return origSend(pname, ...)
      end
    end
  end)
  _G.__RADAR_DETECTION_BYPASS_LOADED = true
  print("\226\156\133 Radar Detection Bypass Installed")
end

InstallRadarDetectionBypass()

local function InstallDeviceIDSpoof()
  if _G.__DEVICE_ID_SPOOF_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  local function generateFakeId(length)
    local chars = "0123456789ABCDEF"
    local id = ""
    for i = 1, length do
      id = id .. chars:sub(math.random(1, #chars), math.random(1, #chars))
    end
    return id
  end
  
  local fakeDeviceID = generateFakeId(32)
  local fakeAndroidID = generateFakeId(16)
  local fakeMac = string.format("%02X:%02X:%02X:%02X:%02X:%02X", math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255))
  local fakeIMEI = "35" .. math.random(100000, 999999) .. math.random(100000, 999999)
  pcall(function()
    local SystemInfo = import("SystemInfo")
    if SystemInfo then
      if SystemInfo.GetDeviceID then
        local orig = SystemInfo.GetDeviceID
        
        function SystemInfo.GetDeviceID()
          if isBypassActive() then
            return fakeDeviceID
          end
          return orig()
        end
      end
      if SystemInfo.GetUniqueDeviceId then
        local orig = SystemInfo.GetUniqueDeviceId
        
        function SystemInfo.GetUniqueDeviceId()
          if isBypassActive() then
            return fakeDeviceID
          end
          return orig()
        end
      end
      if SystemInfo.GetMacAddress then
        local orig = SystemInfo.GetMacAddress
        
        function SystemInfo.GetMacAddress()
          if isBypassActive() then
            return fakeMac
          end
          return orig()
        end
      end
      if SystemInfo.GetAndroidId then
        local orig = SystemInfo.GetAndroidId
        
        function SystemInfo.GetAndroidId()
          if isBypassActive() then
            return fakeAndroidID
          end
          return orig()
        end
      end
      if SystemInfo.GetIMEI then
        local orig = SystemInfo.GetIMEI
        
        function SystemInfo.GetIMEI()
          if isBypassActive() then
            return fakeIMEI
          end
          return orig()
        end
      end
      if SystemInfo.GetDeviceName then
        local orig = SystemInfo.GetDeviceName
        
        function SystemInfo.GetDeviceName()
          if isBypassActive() then
            return "Galaxy S21 Ultra 5G"
          end
          return orig()
        end
      end
    end
    local Build = import("Build")
    if Build then
      local props = {
        "Fingerprint",
        "Serial",
        "Hardware",
        "Brand",
        "Model",
        "Manufacturer",
        "Product",
        "Device",
        "Board"
      }
      for _, prop in ipairs(props) do
        if Build[prop] then
          local orig = Build[prop]
          Build[prop] = function()
            if isBypassActive() then
              if prop == "Fingerprint" then
                return "google/oriole/oriole:13/TQ1A.221205.011/2022120500:user/release-keys"
              end
              if prop == "Serial" then
                return "R5CT1234567"
              end
              if prop == "Hardware" then
                return "oriole"
              end
              if prop == "Brand" then
                return "google"
              end
              if prop == "Model" then
                return "Pixel 6"
              end
              if prop == "Manufacturer" then
                return "Google"
              end
              if prop == "Product" then
                return "oriole"
              end
              if prop == "Device" then
                return "oriole"
              end
              if prop == "Board" then
                return "gs101"
              end
            end
            return orig()
          end
        end
      end
      if Build.VERSION and Build.VERSION.SDK_INT then
        local orig = Build.VERSION.SDK_INT
        
        function Build.VERSION.SDK_INT()
          if isBypassActive() then
            return 33
          end
          return orig()
        end
      end
    end
    local TssSdk = _G.TssSdk
    if TssSdk then
      if TssSdk.GetDeviceInfo then
        local orig = TssSdk.GetDeviceInfo
        
        function TssSdk.GetDeviceInfo()
          if not isBypassActive() then
            return orig()
          end
          return {
            deviceId = fakeDeviceID,
            androidId = fakeAndroidID,
            mac = fakeMac,
            imei = fakeIMEI,
            model = "Pixel 6",
            brand = "google",
            sdkInt = 33,
            fingerprint = "google/oriole/oriole:13/TQ1A.221205.011/2022120500:user/release-keys"
          }
        end
      end
      if TssSdk.GetFingerprint then
        local orig = TssSdk.GetFingerprint
        
        function TssSdk.GetFingerprint()
          if isBypassActive() then
            return "google/oriole/oriole:13/TQ1A.221205.011/2022120500:user/release-keys"
          end
          return orig()
        end
      end
      if TssSdk.GetClientID then
        local orig = TssSdk.GetClientID
        
        function TssSdk.GetClientID()
          if isBypassActive() then
            return fakeDeviceID
          end
          return orig()
        end
      end
    end
    if _G.DeviceID then
      _G.DeviceID = fakeDeviceID
    end
    if _G.AndroidID then
      _G.AndroidID = fakeAndroidID
    end
    if _G.MacAddress then
      _G.MacAddress = fakeMac
    end
    if _G.IMEI then
      _G.IMEI = fakeIMEI
    end
  end)
  _G.__DEVICE_ID_SPOOF_LOADED = true
  print("\226\156\133 Device ID Spoof Bypass Installed")
end

InstallDeviceIDSpoof()

local function InstallMarkSystemSpoof()
  if _G.__MARK_SYSTEM_SPOOF_LOADED then
    return
  end
  
  local function nop()
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  local ourMarkGroups = {1006, 9999}
  pcall(function()
    local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
    if not InGameMarkTools then
      return
    end
    local MarkMgr = InGameMarkTools.ScreenMarkManager
    if not MarkMgr then
      return
    end
    if MarkMgr.GetAllActiveMarks then
      local orig = MarkMgr.GetAllActiveMarks
      
      function MarkMgr:GetAllActiveMarks(...)
        local marks = orig(self, ...)
        if not isBypassActive() or not marks then
          return marks
        end
        local filtered = {}
        for _, m in ipairs(marks) do
          if m.MarkGroupID and not table.contains(ourMarkGroups, m.MarkGroupID) then
            table.insert(filtered, m)
          end
        end
        return filtered
      end
    end
    if MarkMgr.GetMarkCount then
      local orig = MarkMgr.GetMarkCount
      
      function MarkMgr:GetMarkCount(...)
        local count = orig(self, ...)
        if isBypassActive() then
          count = math.max(0, count - #ourMarkGroups)
        end
        return count
      end
    end
    if MarkMgr.GetMarksByGroup then
      local orig = MarkMgr.GetMarksByGroup
      
      function MarkMgr:GetMarksByGroup(groupId)
        if isBypassActive() and table.contains(ourMarkGroups, groupId) then
          return {}
        end
        return orig(self, groupId)
      end
    end
    pcall(function()
      if _G.Replay_IsEnemyFrameUIExisted then
        local orig = _G.Replay_IsEnemyFrameUIExisted
        
        function _G.Replay_IsEnemyFrameUIExisted(...)
          if isBypassActive() then
            return false
          end
          return orig(...)
        end
      end
      if _G.Replay_CreateEnemyFrameUI then
        local orig = _G.Replay_CreateEnemyFrameUI
        
        function _G.Replay_CreateEnemyFrameUI(...)
          if isBypassActive() then
            local backup = _G.ReportEnemyFrameUI or nop
            _G.ReportEnemyFrameUI = nop
            local res = orig(...)
            _G.ReportEnemyFrameUI = backup
            return res
          end
          return orig(...)
        end
      end
    end)
    pcall(function()
      local Actor = import("Actor")
      if Actor then
        local mt = getmetatable(Actor) or {}
        local oldIndex = mt.__index or function()
        end
        
        function mt.__index(t, k)
          if isBypassActive() then
            local sk = tostring(k)
            if sk:find("ESP") or sk:find("bHasAKNative") or sk:find("NativeDistMark") or sk:find("_wh_") or sk:find("WH_") then
              return nil
            end
          end
          return oldIndex(t, k)
        end
        
        setmetatable(Actor, mt)
      end
    end)
    pcall(function()
      local UIHelper = import("UIHelper") or _G.UIHelper
      if UIHelper and UIHelper.GetAllWidgetsOfClass then
        function UIHelper.GetAllWidgetsOfClass(...)
          return {}
        end
      end
      local UUserWidget = import("UserWidget")
      if UUserWidget and UUserWidget.AddToViewport then
        local orig = UUserWidget.AddToViewport
        
        function UUserWidget:AddToViewport(...)
          if isBypassActive() and self.ESPWidget then
            return
          end
          return orig(self, ...)
        end
      end
    end)
    pcall(function()
      local espReports = {
        "ReportESPBox",
        "ReportESPHealth",
        "ReportMiniMapESP",
        "ReportEnemyFrameUI",
        "ReportMarkCreated",
        "ReportMarkDestroyed",
        "MarkSuspiciousESP",
        "OnScreenMarkAdd",
        "OnScreenMarkRemove",
        "ReportDistanceMarker",
        "ReportWallhackESP",
        "SendESPData",
        "UploadESPInfo"
      }
      for _, fn in ipairs(espReports) do
        if _G[fn] then
          _G[fn] = nop
        end
        for _, mod in pairs(package.loaded) do
          if type(mod) == "table" and mod[fn] and type(mod[fn]) == "function" then
            mod[fn] = nop
          end
        end
      end
    end)
    pcall(function()
      if NetUtil and NetUtil.SendPacket then
        local orig = NetUtil.SendPacket
        
        function NetUtil.SendPacket(pname, ...)
          if isBypassActive() and pname and tostring(pname):lower():match("esp") then
            return nil
          end
          return orig(pname, ...)
        end
      end
    end)
    if not table.contains then
      function table.contains(t, val)
        for _, v in ipairs(t) do
          if v == val then
            return true
          end
        end
        return false
      end
    end
  end)
  _G.__MARK_SYSTEM_SPOOF_LOADED = true
  print("\226\156\133 Mark System Spoof Bypass Installed")
end

InstallMarkSystemSpoof()

local function InstallAimTrackingSpoof()
  if _G.__AIM_TRACKING_SPOOF_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if not SubMgr then
      return
    end
    local aimSub = SubMgr:Get("ClientAimTrackingSubsystem")
    if aimSub then
      if aimSub.GetAimData then
        local origGetAimData = aimSub.GetAimData
        
        function aimSub:GetAimData()
          if not isBypassActive() then
            return origGetAimData(self)
          end
          return {
            accuracy = math.random(35, 55),
            headshotRate = math.random(10, 25),
            trackingTime = math.random(150, 350),
            aimLockCount = 0,
            snapCount = 0
          }
        end
      end
      local reportFuncs = {
        "ReportAimData",
        "SendAimStats",
        "UploadAimInfo",
        "ReportAimAssist",
        "ReportAimLock",
        "ReportAimSnap"
      }
      for _, fn in ipairs(reportFuncs) do
        if aimSub[fn] then
          aimSub[fn] = function()
          end
        end
      end
      if aimSub.IsAimNormal then
        function aimSub.IsAimNormal()
          if isBypassActive() then
            return true
          end
          return origIsAimNormal and origIsAimNormal(aimSub) or true
        end
      end
    end
  end)
  _G.__AIM_TRACKING_SPOOF_LOADED = true
  print("\226\156\133 Aim Tracking Subsystem Spoof Installed")
end

InstallAimTrackingSpoof()

local function InstallHitStatisticsSpoof()
  if _G.__HIT_STATISTICS_SPOOF_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  local matchStats = {
    totalShots = 0,
    totalHits = 0,
    headshots = 0,
    kills = 0
  }
  pcall(function()
    local Actor = import("Actor")
    if Actor and Actor.TakeDamage then
      local origTakeDamage = Actor.TakeDamage
      
      function Actor:TakeDamage(DamageAmount, DamageEvent, EventInstigator, DamageCauser)
        if isBypassActive() and EventInstigator == slua_GameFrontendHUD:GetPlayerController() then
          matchStats.totalHits = matchStats.totalHits + 1
          if DamageEvent and DamageEvent.HitInfo and DamageEvent.HitInfo.BoneName then
            local bn = tostring(DamageEvent.HitInfo.BoneName):lower()
            if bn:find("head") then
              matchStats.headshots = matchStats.headshots + 1
            end
          end
          if self:IsDead() then
            matchStats.kills = matchStats.kills + 1
          end
        end
        return origTakeDamage(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
      end
    end
    local ShootWeaponEntity = import("ShootWeaponEntity") or import("ShootWeaponEntityComp")
    if ShootWeaponEntity and ShootWeaponEntity.Fire then
      local origFire = ShootWeaponEntity.Fire
      
      function ShootWeaponEntity:Fire(...)
        if isBypassActive() then
          matchStats.totalShots = matchStats.totalShots + 1
        end
        return origFire(self, ...)
      end
    end
    local GameReportUtils = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
    if GameReportUtils and GameReportUtils.ReportGameResult then
      local origReport = GameReportUtils.ReportGameResult
      
      function GameReportUtils:ReportGameResult(data)
        if isBypassActive() and data then
          local shots = math.max(matchStats.totalShots, 1)
          data.accuracy = math.min(0.65, 0.35 + math.random() * 0.15)
          data.headshotRate = math.min(0.3, 0.1 + math.random() * 0.1)
          data.totalKills = matchStats.kills
          data.totalShots = shots
          data.totalHits = math.floor(shots * data.accuracy)
        end
        return origReport(self, data)
      end
    end
    local ShowResult = package.loaded["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowResultLogic"]
    if ShowResult and ShowResult.ReceiveData then
      local origReceive = ShowResult.ReceiveData
      
      function ShowResult:ReceiveData(resultData)
        if isBypassActive() and resultData then
          resultData.Accuracy = math.random(35, 50) / 100
          resultData.HeadShotRate = math.random(10, 20) / 100
        end
        return origReceive(self, resultData)
      end
    end
  end)
  _G.__HIT_STATISTICS_SPOOF_LOADED = true
  print("\226\156\133 Hit Statistics Spoof Installed")
end

InstallHitStatisticsSpoof()

local function InstallKillAimReportFunctions()
  if _G.__KILL_AIM_REPORT_FUNCTIONS_LOADED then
    return
  end
  
  local function nop()
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local aimReports = {
      "ReportAimFlow",
      "ReportRecoil",
      "ReportAimData",
      "SendAimStats",
      "UploadAimInfo",
      "ReportHeadshotRate",
      "ReportAccuracy",
      "ReportFireRate",
      "ReportRecoilKick",
      "ReportAutoAim",
      "ReportWeaponModification",
      "ReportWeaponStats",
      "ReportShootVerifyFail",
      "ReportHitIntegrity",
      "OnAimAssistDetected",
      "OnRecoilAnomaly",
      "OnFireRateAnomaly",
      "ClientAimTrackingUpdate",
      "ServerAimValidation",
      "ReportAimAssist",
      "ReportAimLock",
      "ReportAimSnap",
      "ReportRecoilPattern",
      "ReportShootPattern",
      "ReportWeaponDeviation",
      "ReportBulletSpread",
      "ReportFireRateAnomaly",
      "ReportRecoilAnomaly",
      "ReportAimAnomaly",
      "SendShootData",
      "UploadShootStats",
      "ReportWeaponBehavior",
      "ReportShootBehavior",
      "ReportAimBehavior"
    }
    for _, fn in ipairs(aimReports) do
      if _G[fn] and type(_G[fn]) == "function" then
        _G[fn] = nop
      end
    end
    for _, mod in pairs(package.loaded) do
      if type(mod) == "table" then
        for _, fn in ipairs(aimReports) do
          if mod[fn] and type(mod[fn]) == "function" then
            mod[fn] = nop
          end
        end
      end
    end
    local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubMgr then
      local subsystems = {
        "ClientAimTrackingSubsystem",
        "ShootVerifySubSystemClient",
        "ClientAntiCheatSubsystem",
        "ClientHawkEyePatrolSubsystem"
      }
      for _, name in ipairs(subsystems) do
        local sub = SubMgr:Get(name)
        if sub then
          for k, v in pairs(sub) do
            if type(v) == "function" then
              local lk = tostring(k):lower()
              if lk:find("report") or lk:find("aim") or lk:find("recoil") or lk:find("shoot") or lk:find("verify") or lk:find("check") then
                sub[k] = nop
              end
            end
          end
        end
      end
    end
  end)
  _G.__KILL_AIM_REPORT_FUNCTIONS_LOADED = true
  print("\226\156\133 Kill Aim/Recoil Report Functions Installed")
end

InstallKillAimReportFunctions()

local function InstallBehaviorAnalysisSpoof()
  if _G.__BEHAVIOR_ANALYSIS_SPOOF_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if not SubMgr then
      return
    end
    local Behavior = SubMgr:Get("BehaviorScoreSubsystem")
    if Behavior then
      if Behavior.OnHandleBehaviorScore then
        function Behavior.OnHandleBehaviorScore()
        end
      end
      if Behavior.AIPerceptionScore then
        function Behavior.AIPerceptionScore()
          return 0
        end
      end
      if Behavior.ReportBehavior then
        function Behavior.ReportBehavior()
        end
      end
      if Behavior.CalcFinalScore then
        function Behavior.CalcFinalScore()
          return 0
        end
      end
      if Behavior.GetBehaviorScore then
        function Behavior.GetBehaviorScore()
          return 0
        end
      end
    end
    local AFK = SubMgr:Get("AFKReportorSubsystem")
    if AFK then
      if AFK.HandleEnterFighting then
        function AFK.HandleEnterFighting()
        end
      end
      if AFK.InitializePlayerInputInfo then
        function AFK.InitializePlayerInputInfo()
        end
      end
      if AFK.AddOneAFKInfo then
        function AFK.AddOneAFKInfo()
        end
      end
      if AFK.SetPlayerAFKState then
        function AFK.SetPlayerAFKState()
        end
      end
      if AFK.ReportAFK then
        function AFK.ReportAFK()
        end
      end
    end
    local TDMAFK = SubMgr:Get("TDMAFKReportorSubsystem")
    if TDMAFK then
      if TDMAFK.SendAFKTips then
        function TDMAFK.SendAFKTips()
        end
      end
      if TDMAFK.OnHandleLostConnection then
        function TDMAFK.OnHandleLostConnection()
        end
      end
    end
    local behaviorFuncs = {
      "ReportPlayerBehavior",
      "ReportBehaviorScore",
      "ReportAFK",
      "ReportSuspiciousBehavior",
      "ReportAbnormalBehavior",
      "SendBehaviorData"
    }
    for _, fn in ipairs(behaviorFuncs) do
      if _G[fn] and type(_G[fn]) == "function" then
        _G[fn] = function()
        end
      end
    end
  end)
  _G.__BEHAVIOR_ANALYSIS_SPOOF_LOADED = true
  print("\226\156\133 Behavior Analysis Spoof Installed")
end

InstallBehaviorAnalysisSpoof()

local function InstallDLLIntegritySpoof()
  if _G.__DLL_INTEGRITY_SPOOF_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    if _G.TssSdk then
      if _G.TssSdk.GetModuleHash then
        function _G.TssSdk.GetModuleHash()
          if isBypassActive() then
            return "82918E1FE1BE4186CFD2F1286951B2A0"
          end
          return origGetModuleHash and origGetModuleHash() or "00000000"
        end
      end
      if _G.TssSdk.VerifyModule then
        function _G.TssSdk.VerifyModule()
          if isBypassActive() then
            return true
          end
          return origVerifyModule and origVerifyModule() or true
        end
      end
      if _G.TssSdk.ScanProcess then
        function _G.TssSdk.ScanProcess()
          if isBypassActive() then
            return {}
          end
          return origScanProcess and origScanProcess() or {}
        end
      end
    end
    local FMemory = import("FMemory")
    if FMemory and FMemory.Memcpy then
      local origMemcpy = FMemory.Memcpy
      
      function FMemory.Memcpy(dest, src, count)
        if isBypassActive() then
          return
        end
        return origMemcpy(dest, src, count)
      end
    end
    if rawget(_G, "IsDebuggerPresent") then
      function _G.IsDebuggerPresent()
        if isBypassActive() then
          return false
        end
        return origIsDebuggerPresent and origIsDebuggerPresent() or false
      end
    end
    local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubMgr then
      local kc = SubMgr:Get("ClientKernelCheckSubsystem")
      if kc then
        if kc.IsKernelClean then
          local orig = kc.IsKernelClean
          
          function kc:IsKernelClean()
            if not isBypassActive() then
              return orig(self)
            end
            return true, {code = 0, message = "clean"}
          end
        end
        if kc.GetKernelVersion then
          local orig = kc.GetKernelVersion
          
          function kc:GetKernelVersion()
            if not isBypassActive() then
              return orig(self)
            end
            return "5.4.0-generic"
          end
        end
      end
    end
  end)
  _G.__DLL_INTEGRITY_SPOOF_LOADED = true
  print("\226\156\133 DLL / Code Integrity Spoof Installed")
end

InstallDLLIntegritySpoof()

local function InstallPakSizeSpoof()
  if _G.__PAK_SIZE_SPOOF_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local FileHelper = import("FFileHelper")
    if FileHelper then
      if FileHelper.GetFileSize then
        local orig = FileHelper.GetFileSize
        
        function FileHelper.GetFileSize(path)
          local size = orig(path)
          if isBypassActive() and path and tostring(path):lower():match(".pak") then
            return 2000000000
          end
          return size
        end
      end
      if FileHelper.SaveStringToFile then
        local origSave = FileHelper.SaveStringToFile
        
        function FileHelper.SaveStringToFile(str, path, ...)
          if isBypassActive() and path and tostring(path):lower():match(".pak") then
            return true
          end
          return origSave(str, path, ...)
        end
      end
    end
    local PakSubsystem = pcall(require, "GameLua.GameCore.Module.Subsystem.PakFileSubsystem") and require("GameLua.GameCore.Module.Subsystem.PakFileSubsystem")
    if PakSubsystem then
      if PakSubsystem.CheckPakIntegrity then
        function PakSubsystem.CheckPakIntegrity()
        end
      end
      if PakSubsystem.ReportPakMismatch then
        function PakSubsystem.ReportPakMismatch()
        end
      end
      if PakSubsystem.VerifyPakSignature then
        function PakSubsystem.VerifyPakSignature()
          return true
        end
      end
      if PakSubsystem.GetPakSize then
        function PakSubsystem.GetPakSize()
          return 2000000000
        end
      end
    end
    local FPakFile = import("FPakFile") or import("FPakPlatformFile")
    if FPakFile then
      if FPakFile.GetPakEntries then
        function FPakFile.GetPakEntries(...)
          return {}
        end
      end
      if FPakFile.GetPakFolders then
        function FPakFile.GetPakFolders(...)
          return {}
        end
      end
      if FPakFile.FindFileInPakFiles then
        function FPakFile.FindFileInPakFiles(...)
          return false
        end
      end
    end
  end)
  _G.__PAK_SIZE_SPOOF_LOADED = true
  print("\226\156\133 Pak Size Detection Spoof Installed")
end

InstallPakSizeSpoof()

local function InstallExtraShieldBypass()
  if _G.__EXTRA_SHIELD_BYPASS_LOADED then
    return
  end
  
  local function isBypassActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local UMat = import("Material")
    local UMatInst = import("MaterialInstance")
    if UMat then
      if UMat.GetShaderMap then
        function UMat.GetShaderMap()
          if isBypassActive() then
            return nil
          end
          return origGetShaderMap and origGetShaderMap() or nil
        end
      end
      if UMat.GetShaderPlatform then
        function UMat.GetShaderPlatform()
          if isBypassActive() then
            return 0
          end
          return origGetShaderPlatform and origGetShaderPlatform() or 0
        end
      end
    end
    if UMatInst and UMatInst.GetShaderMap then
      function UMatInst.GetShaderMap()
        if isBypassActive() then
          return nil
        end
        return origGetShaderMapInst and origGetShaderMapInst() or nil
      end
    end
    local SSMgr = import("ScreenshotManager")
    if SSMgr then
      if SSMgr.RequestScreenshot then
        function SSMgr.RequestScreenshot(...)
          if isBypassActive() then
            return false
          end
          return origRequestScreenshot and origRequestScreenshot(...) or false
        end
      end
      if SSMgr.HasPendingScreenshot then
        function SSMgr.HasPendingScreenshot(...)
          if isBypassActive() then
            return false
          end
          return origHasPendingScreenshot and origHasPendingScreenshot(...) or false
        end
      end
    end
    if _G.TakeScreenshot then
      local orig = _G.TakeScreenshot
      
      function _G.TakeScreenshot(...)
        if isBypassActive() then
          return
        end
        return orig(...)
      end
    end
    if _G.MakePicture then
      local orig = _G.MakePicture
      
      function _G.MakePicture(...)
        if isBypassActive() then
          return ""
        end
        return orig(...)
      end
    end
    if NetUtil and NetUtil.SendPacket then
      local orig = NetUtil.SendPacket
      
      function NetUtil.SendPacket(pname, ...)
        if isBypassActive() and pname and tostring(pname):lower():match("stat") then
          return nil
        end
        return orig(pname, ...)
      end
    end
  end)
  _G.__EXTRA_SHIELD_BYPASS_LOADED = true
  print("\226\156\133 Extra Shield Bypass Installed")
end

InstallExtraShieldBypass()

local function InstallMD5Bypass()
  local function nop()
  end
  
  local function retTrue()
    return true
  end
  
  local FAKE_MD5 = "7b1c7b5608da3083097816106fc331f9"
  
  local function returnFakeMD5()
    return FAKE_MD5
  end
  
  local function patchFunctionsInTable(tbl)
    if type(tbl) ~= "table" then
      return
    end
    for k, v in pairs(tbl) do
      if type(v) == "function" then
        local lk = tostring(k):lower()
        if lk:match("md5") or lk:match("hash") or lk:match("crc") or lk:match("sha") or lk:match("integrity") or lk:match("signature") or lk:match("verifyfile") or lk:match("checkfile") then
          tbl[k] = lk:match("md5") and returnFakeMD5 or retTrue
        end
      end
    end
  end
  
  local criticalModules = {
    "CreativeModeBlueprintLibrary",
    "STExtraBlueprintFunctionLibrary",
    "GameplayStatics",
    "KismetMathLibrary",
    "KismetSystemLibrary",
    "FFileHelper",
    "GameplayData",
    "AvatarUtils",
    "TssSdk",
    "slua.loader",
    "slua.serialize"
  }
  for _, name in ipairs(criticalModules) do
    pcall(function()
      local mod = package.loaded[name] or _G[name]
      if mod then
        patchFunctionsInTable(mod)
      end
    end)
  end
  local globalHooks = {
    "MD5Hash",
    "CRC32",
    "SHA1",
    "SHA256",
    "HMAC",
    "CheckFileIntegrity",
    "VerifySignature",
    "FileMismatchReport",
    "OnFileCorrupted",
    "slua_verify",
    "check_slua_integrity",
    "GetMD5",
    "ComputeMD5",
    "VerifyFileIntegrity",
    "CheckMD5",
    "CheckFileMD5",
    "GetFileMD5"
  }
  for _, fn in ipairs(globalHooks) do
    if _G[fn] and type(_G[fn]) == "function" then
      _G[fn] = (fn:lower():match("md5") or fn:lower():match("hash")) and returnFakeMD5 or retTrue
    end
  end
  if _G.TssSdk then
    _G.TssSdk.GetFileMD5 = returnFakeMD5
    _G.TssSdk.VerifyFileSignature = retTrue
    local oldRecv = _G.TssSdk.OnRecvData
    
    function _G.TssSdk.OnRecvData(data)
      if type(data) == "string" and data:lower():match("md5") then
        return
      end
      if oldRecv then
        oldRecv(data)
      end
    end
  end
  local okSM, SubsystemMgr = pcall(require, "GameLua.GameCore.Module.Subsystem.SubsystemMgr")
  if okSM and SubsystemMgr then
    for _, sn in ipairs({
      "FileCheckSubsystem",
      "AssetCheckSubsystem",
      "IntegrityCheckSubsystem",
      "PakCheckSubsystem"
    }) do
      local sub = SubsystemMgr:Get(sn)
      if sub then
        for k in pairs(sub) do
          if type(sub[k]) == "function" then
            sub[k] = nop
          end
        end
        sub.StartCheck = nop
        sub.ReportAbnormalFile = nop
      end
    end
  end
end

InstallMD5Bypass()

local function InstallHiggsBypass()
  local function nop()
  end
  
  pcall(function()
    local Higgs = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
    if Higgs then
      local origInit = Higgs.Initialize or Higgs.ctor
      if origInit then
        function Higgs:Initialize(...)
          self.bMHActive = false
          
          self.bCallPreReplication = false
          if origInit then
            origInit(self, ...)
          end
        end
      else
        rawset(Higgs, "bMHActive", false)
        rawset(Higgs, "bCallPreReplication", false)
      end
    end
  end)
  
  local function poison_class(cls)
    if type(cls) ~= "table" then
      return
    end
    local mt = {
      __index = function()
        return nop
      end,
      __newindex = function()
      end,
      __call = nop
    }
    setmetatable(cls, mt)
    rawset(cls, "bMHActive", false)
    rawset(cls, "bCallPreReplication", false)
    rawset(cls, "BlackList", {})
  end
  
  pcall(function()
    local avc = _G.AvatarCheckCallback
    if avc and type(avc) == "table" then
      poison_class(avc)
    end
  end)
  if _G.GameSafeCallbacks then
    poison_class(_G.GameSafeCallbacks)
  end
  _G.BlackList = {}
end

InstallHiggsBypass()

local function InstallRHIandGVCBypass()
  local function isActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    local FRHI = import("RHICommandList")
    if FRHI and FRHI.SetDepthState and not _G.__RHI_HOOKED then
      local origSetDepth = FRHI.SetDepthState
      
      function FRHI:SetDepthState(State)
        if isActive() and type(State) == "table" and State.DepthEnable ~= nil then
          State.DepthEnable = true
        end
        return origSetDepth(self, State)
      end
      
      _G.__RHI_HOOKED = true
    end
  end)
  pcall(function()
    local UGVC = import("GameViewportClient")
    if UGVC and UGVC.Draw and not _G.__GVC_HOOKED then
      local origDraw = UGVC.Draw
      
      function UGVC:Draw(...)
        origDraw(self, ...)
        if isActive() and _G.AK_DrawWallhackOverlay then
          pcall(_G.AK_DrawWallhackOverlay)
        end
      end
      
      _G.__GVC_HOOKED = true
    end
  end)
end

InstallRHIandGVCBypass()

local function InstallSubsystemMgrInterceptor()
  local function nop()
  end
  
  local blockedFuncNames = {
    "reportattackflow",
    "reportsecattackflow",
    "reporthurtflow",
    "reportfirearms",
    "reportverifyinfoflow",
    "reportplayerbehavior",
    "reportteammathurt",
    "reportmisKillbyteammate",
    "reportforbitpick",
    "reportplayermoveroute",
    "reportplayerposition",
    "reportvehiclemoveflow",
    "reportsecregamemovingflow",
    "reportparachutedata",
    "sendtsssdkantidatatolobby",
    "senddserrorlogtolobby",
    "senddshawkeyepatrollogtolobby",
    "sendsectlog",
    "senddata miningtlog",
    "sendactivitytlog",
    "sendclientmemusage",
    "sendclientfps",
    "onclientcrashreport",
    "onnetworklossdetected",
    "reportmatchroomdata",
    "reportplayersping",
    "sendclientstats",
    "sendserveravgtickdelta",
    "reporthitflow",
    "onplayeractorchannelerror",
    "reportequipmentflow",
    "reportaimflow",
    "getweaponreport",
    "getoneweaponreport",
    "reportheavyweaponboxspawnflow",
    "reportheavyweaponboxactivationflow",
    "reportheavyweaponboxopenplayerflow",
    "reportheavyweaponboxitemflow",
    "reportplayerip",
    "reportplayerframepingrecord",
    "ondsconnectionsaturated",
    "reportdsnetsaturation",
    "reportnetcontinuoussaturate",
    "reportdsnetrate",
    "reportcircleflow",
    "reportdscircleflow",
    "reportjumpflow",
    "reportaistrategyinfo",
    "sendaideliveryinfo",
    "reportdailytaskinfo",
    "sendplayerspectatinglog",
    "reportidcardproduceflow",
    "reportidcardpickupflow",
    "reportidcarddestroyflow",
    "reportrevivalflow",
    "reportgamesetting",
    "reportgamesettingnew",
    "reportantsvoiceteamcreate",
    "reportantsvoiceteamquit",
    "reportcommoninfo",
    "reportlightweightstat",
    "getgeneraltlogdata",
    "reportwallhack",
    "reportaimbot",
    "reportspeedhack",
    "reportmagicbullet",
    "reportplayercontrollerstatechanged",
    "reportavatarflow",
    "reportabnormalmaterial",
    "reportdepthtestchange",
    "reportmemoryexception",
    "reportmaterialscan",
    "reportshaderoverride",
    "sendsec tlog",
    "reportplayerkillflow",
    "clientsecplayerkillflow",
    "checkreportsecattackflow",
    "checkreportsecattackflowwithattackflow",
    "isenablereportplayerkillflow",
    "isenablereporthitflow",
    "isenablereportcircleflow",
    "onplayernetconnectionclosed",
    "onplayerspectateexception",
    "onshutdownaftererror",
    "heartbeat",
    "sendheartbeat",
    "clientheartbeat",
    "serverheartbeat",
    "swifthawk",
    "clientswifthawk",
    "clientswifthawkwithparams",
    "swifthawkreport",
    "swifthawkdata",
    "anticheatreport",
    "cheatdetection",
    "violationreport",
    "securityviolation",
    "integritycheck",
    "signatureverify",
    "md5",
    "hash",
    "filecheck",
    "pakcheck"
  }
  local securitySubsystemNames = {
    "FileCheckSubsystem",
    "IntegrityCheckSubsystem",
    "PakCheckSubsystem",
    "ClientWallhackDetectionSubsystem",
    "ClientESPDetectionSubsystem",
    "ClientAimTrackingSubsystem",
    "ClientAntiCheatSubsystem",
    "ClientHawkEyePatrolSubsystem",
    "DSHawkEyePatrolSubsystem",
    "CoronaLabSubsystem",
    "PlayerSecurityInfoSubsystem",
    "ShootVerifySubSystemClient",
    "MemoryCheckSubsystem",
    "SpeedCheckSubsystem",
    "WallCheckSubsystem",
    "BehaviorScoreSubsystem",
    "AFKReportorSubsystem",
    "AvatarExceptionSubsystem",
    "GameReportSubsystem",
    "SwiftHawkSubsystem",
    "HeartbeatSubsystem",
    "ClientReportPlayerSubsystem",
    "DSReportPlayerSubsystem",
    "ModifierExceptionSubsystem",
    "SimulateCharacterSubsystem",
    "ClientRenderCheckSubsystem",
    "ClientMemoryGuardSubsystem",
    "ClientKernelCheckSubsystem"
  }
  local okSM, SubsystemMgr_inst = pcall(require, "GameLua.GameCore.Module.Subsystem.SubsystemMgr")
  if okSM and SubsystemMgr_inst and not SubsystemMgr_inst.__ak_intercept then
    local realGet = SubsystemMgr_inst.Get
    
    function SubsystemMgr_inst:Get(name)
      local sub = realGet(self, name)
      if type(sub) == "table" and not sub.__ak_sub_silenced then
        for _, secName in ipairs(securitySubsystemNames) do
          if name == secName then
            for k, v in pairs(sub) do
              if type(v) == "function" then
                local lk = tostring(k):lower():gsub("[^%w]", "")
                for _, blocked in ipairs(blockedFuncNames) do
                  if lk == blocked then
                    sub[k] = nop
                    break
                  end
                end
              end
            end
            sub.__ak_sub_silenced = true
            break
          end
        end
      end
      return sub
    end
    
    SubsystemMgr_inst.__ak_intercept = true
  end
end

InstallSubsystemMgrInterceptor()

local function InstallGameplayCallbacksWrapper()
  local function nop()
  end
  
  local blockedFuncNames = {
    "reportattackflow",
    "reportsecattackflow",
    "reporthurtflow",
    "reportfirearms",
    "reportverifyinfoflow",
    "reportplayerbehavior",
    "reportteammathurt",
    "reportmisKillbyteammate",
    "reportforbitpick",
    "reportplayermoveroute",
    "reportplayerposition",
    "reportvehiclemoveflow",
    "reportsecregamemovingflow",
    "reportparachutedata",
    "sendtsssdkantidatatolobby",
    "senddserrorlogtolobby",
    "senddshawkeyepatrollogtolobby",
    "sendsectlog",
    "senddata miningtlog",
    "sendactivitytlog",
    "sendclientmemusage",
    "sendclientfps",
    "onclientcrashreport",
    "onnetworklossdetected",
    "reportmatchroomdata",
    "reportplayersping",
    "sendclientstats",
    "sendserveravgtickdelta",
    "reporthitflow",
    "onplayeractorchannelerror",
    "reportequipmentflow",
    "reportaimflow",
    "reportwallhack",
    "reportaimbot",
    "reportspeedhack",
    "reportmagicbullet",
    "reportabnormalmaterial",
    "reportdepthtestchange",
    "reportmemoryexception",
    "reportmaterialscan",
    "reportshaderoverride",
    "heartbeat",
    "sendheartbeat",
    "clientheartbeat",
    "serverheartbeat",
    "swifthawk",
    "clientswifthawk",
    "swifthawkreport",
    "swifthawkdata",
    "anticheatreport",
    "cheatdetection",
    "violationreport",
    "securityviolation",
    "integritycheck",
    "signatureverify",
    "md5",
    "hash",
    "filecheck",
    "pakcheck"
  }
  local realGC = _G.GameplayCallbacks or {}
  if not _G.__GC_METATABLE_WRAPPED then
    _G.GameplayCallbacks = setmetatable({}, {
      __index = function(t, k)
        local v = realGC[k]
        if type(v) == "function" then
          local lk = tostring(k):lower():gsub("[^%w]", "")
          for _, blocked in ipairs(blockedFuncNames) do
            if lk == blocked then
              return nop
            end
          end
        end
        return v
      end,
      __newindex = function(t, k, v)
        if type(v) == "function" then
          local lk = tostring(k):lower():gsub("[^%w]", "")
          for _, blocked in ipairs(blockedFuncNames) do
            if lk == blocked then
              v = nop
              break
            end
          end
        end
        rawset(realGC, k, v)
      end
    })
    _G.__GC_METATABLE_WRAPPED = true
  end
end

InstallGameplayCallbacksWrapper()

local function InstallEventSystemFilter()
  pcall(function()
    local ES
    pcall(function()
      ES = require("GameLua.Mod.BaseMod.Common.EventSystem")
    end)
    ES = ES or _G.EventSystem
    if ES and not ES.__ak_event_blocked then
      local origPost = ES.postEvent
      
      function ES.postEvent(eventType, eventID, ...)
        local sType = tostring(eventType or ""):lower()
        local sID = tostring(eventID or ""):lower()
        if sID:find("security") or sID:find("cheat") or sType:find("security") then
          return
        end
        return origPost(eventType, eventID, ...)
      end
      
      ES.__ak_event_blocked = true
    end
  end)
end

InstallEventSystemFilter()

local function InstallAntiDebug()
  pcall(function()
    if debug and debug.getinfo then
      function debug.getinfo()
        return {}
      end
    end
    if debug and debug.getlocal then
      function debug.getlocal()
        return nil
      end
    end
    if jit and jit.attach then
      jit.attach(function()
      end, "bc")
    end
  end)
end

InstallAntiDebug()

local function InstallNetUtilBlocker()
  local function isPacketBlocked(name)
    local n = tostring(name or ""):lower()
    
    if n:match("md5") or n:match("hash") or n:match("integrity") or n:match("filecheck") or n:match("pakcheck") then
      return true
    end
    if n:match("report") or n:match("flow") or n:match("tlog") or n:match("cheat") or n:match("security") or n:match("verify") or n:match("heartbeat") or n:match("swifthawk") or n:match("ban") or n:match("inspect") or n:match("crash") or n:match("telemetry") or n:match("corona") or n:match("modifier") or n:match("simulate") then
      return true
    end
    return false
  end
  
  if NetUtil and not NetUtil._UltimatePacketsBlocked then
    local origSend = NetUtil.SendPacket
    
    function NetUtil.SendPacket(pname, ...)
      if isPacketBlocked(pname) then
        return nil
      end
      return origSend(pname, ...)
    end
    
    NetUtil._UltimatePacketsBlocked = true
  end
end

InstallNetUtilBlocker()

local function InstallBlacklistFilter()
  local function nop()
  end
  
  local BLACKLIST_HOSTS = {
    "tss.tencent",
    "syzsdk",
    "gcloud.qq",
    "reportlog",
    "tdos",
    "logupload",
    "feedback.wh",
    "crash2",
    "privacy.qq",
    "privacy.tencent",
    "oth.eve",
    "mdt.qq",
    "act.tencentyun",
    "analytics",
    "report.qq",
    "anticheatexpert",
    "crashsight",
    "wetest",
    "log.tav",
    "sngd",
    "tracer",
    "intlsdk",
    "igamecj",
    "cdn.club",
    "gpubgm",
    "graph.facebook",
    "calendarpushsubscription",
    "googleads",
    "doubleclick",
    "firebaselogging",
    "firebaseremoteconfig",
    "fonts.googleapis",
    "abs.twimg",
    "dl.listdl",
    "igame.gcloudcs",
    "bugly",
    "beacon",
    "helpshift",
    "tdm",
    "apm",
    "safeguard",
    "weiyun",
    "qzone",
    "tencent-cloud",
    "myapp",
    "idqqimg",
    "gtimg",
    "qqmail",
    "tcdn",
    "cloudctrl",
    "sdkostrace",
    "103.134.189.146",
    "mbgame",
    "csoversea",
    "igame",
    "pubgmobile",
    "down.anticheatexpert.com",
    "asia.csoversea.mbgame.anticheatexpert.com",
    "log.tav.qq",
    "syzsdk.qq",
    "logiservice.qcloud",
    "opensdk.tencent",
    "exp.helpshift",
    "loginsdkapi.zingplay",
    "firebase",
    "googleapis",
    "facebook",
    "gvoice"
  }
  local FILE_KEYWORDS = {
    "tlog",
    "crash",
    "bugly",
    "report",
    "beacon",
    "wetest",
    "analytics",
    "telemetry",
    "trace",
    "dump",
    "exception",
    "feedback",
    "aps_log",
    "mtp_detect",
    "network_loss",
    "client_error",
    "ue4crash",
    "tdm",
    "gcloud"
  }
  
  local function isBlacklisted(str)
    if type(str) ~= "string" then
      return false
    end
    local low = str:lower()
    for _, kw in ipairs(BLACKLIST_HOSTS) do
      if low:find(kw, 1, true) then
        return true
      end
    end
    return false
  end
  
  pcall(function()
    if _G.HttpRequest and not _G.__HTTP_WRAPPED then
      local origHttp = _G.HttpRequest
      
      function _G.HttpRequest(url, ...)
        if isBlacklisted(url) then
          return nil
        end
        return origHttp(url, ...)
      end
      
      _G.__HTTP_WRAPPED = true
    end
    if _G.FHttpModule and _G.FHttpModule.CreateRequest and not _G.__FHHTTP_WRAPPED then
      local origFH = _G.FHttpModule.CreateRequest
      
      function _G.FHttpModule.CreateRequest(...)
        local url = select(1, ...)
        if isBlacklisted(url) then
          return nil
        end
        return origFH(...)
      end
      
      _G.__FHHTTP_WRAPPED = true
    end
  end)
  local orig_io_open = io.open
  
  function io.open(path, mode)
    if type(path) == "string" then
      local lp = path:lower()
      for _, kw in ipairs(FILE_KEYWORDS) do
        if lp:find(kw) and mode and (mode == "w" or mode == "a" or mode == "w+" or mode == "a+") then
          return nil, "Blocked"
        end
      end
    end
    return orig_io_open(path, mode)
  end
  
  if _G.UnrealEngine and _G.UnrealEngine.CrashContext then
    _G.UnrealEngine.CrashContext = {
      SetCrashContext = nop,
      ReportCrash = nop,
      AddCrashData = nop
    }
  end
end

InstallBlacklistFilter()

local function InstallWHABypass()
  local function nop()
  end
  
  local function retTrue()
    return true
  end
  
  local function retFalse()
    return false
  end
  
  local function retZero()
    return 0
  end
  
  local function retEmpty()
    return {}
  end
  
  local function retEmptyStr()
    return ""
  end
  
  local function safe_require(p)
    local ok, m = pcall(require, p)
    return ok and m or nil
  end
  
  local function tryImport(n)
    local ok, l = pcall(import, n)
    return ok and l or nil
  end
  
  local bypass = {}
  
  local function blockScreenshots()
    pcall(function()
      local SS = tryImport("ScreenshotMaker") or tryImport("ScreenshotMTDer")
      if SS then
        SS.MakePicture = retEmptyStr
        SS.ReMakePicture = retEmptyStr
        SS.HasCaptured = retTrue
      end
    end)
  end
  
  local function blockGameplayCallbacks()
    if not _G.GameplayCallbacks then
      _G.GameplayCallbacks = {}
    end
    local GC = _G.GameplayCallbacks
    if GC._WHABlocked then
      return
    end
    local reportFuncs = {
      "ReportAttackFlow",
      "ReportSecAttackFlow",
      "ReportHurtFlow",
      "ReportFireArms",
      "ReportVerifyInfoFlow",
      "ReportPlayerBehavior",
      "ReportTeammatHurt",
      "ReportPlayerMoveRoute",
      "ReportPlayerPosition",
      "ReportAimFlow",
      "ReportHitFlow",
      "ReportWallHack",
      "ReportAimbot",
      "ReportSpeedHack",
      "ReportMagicBullet",
      "ReportAbnormalMaterial",
      "ReportDepthTestChange",
      "ReportMemoryException",
      "ReportMaterialScan",
      "ReportShaderOverride",
      "ReportCircleFlow",
      "OnPlayerActorChannelError",
      "OnPlayerSpectateException",
      "OnShutdownAfterError"
    }
    for _, fn in ipairs(reportFuncs) do
      GC[fn] = nop
    end
    local oldStateChanged = GC.OnDSPlayerStateChanged
    
    function GC.OnDSPlayerStateChanged(UID, state, ...)
      if state and type(state) == "string" then
        local s = state:lower()
        if s:find("cheat") or s:find("ban") or s:find("integrity") then
          return
        end
      end
      if oldStateChanged then
        return oldStateChanged(UID, state, ...)
      end
    end
    
    GC._WHABlocked = true
  end
  
  local function spoofTssSdk()
    pcall(function()
      local t = _G.TssSdk
      if t then
        t.GetFileMD5 = retEmptyStr
        t.VerifyFileSignature = retTrue
        t.CheckIntegrity = retTrue
        
        function t.ScanMemory()
          return true, {}
        end
        
        t.IsEmulator = retFalse
        t.OnRecvData = nop
      end
    end)
  end
  
  local function disableDetectionSubsystems()
    local sm = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if not sm then
      return
    end
    local targetSubs = {
      "ClientWallhackDetectionSubsystem",
      "ClientESPDetectionSubsystem",
      "ClientAimTrackingSubsystem",
      "ShootVerifySubSystemClient",
      "ClientRenderCheckSubsystem",
      "ClientMemoryGuardSubsystem",
      "ClientKernelCheckSubsystem",
      "ClientHawkEyePatrolSubsystem",
      "ClientAntiCheatSubsystem",
      "IntegrityCheckSubsystem",
      "FileCheckSubsystem",
      "AvatarExceptionSubsystem"
    }
    for _, sn in ipairs(targetSubs) do
      local sub = sm:Get(sn)
      if sub then
        for k, v in pairs(sub) do
          if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Verify") or k:find("Check") or k:find("Detect") or k:find("Scan")) then
            sub[k] = nop
          end
        end
        if sn == "ClientWallhackDetectionSubsystem" then
          sub.IsVisionNormal = retTrue
          
          function sub.GetVisibilityRate()
            return math.random(60, 85)
          end
        elseif sn == "ClientESPDetectionSubsystem" then
          sub.HasESP = retFalse
          
          function sub.CheckOverlay()
            return "clean"
          end
        elseif sn == "ClientAimTrackingSubsystem" then
          function sub.GetAimData()
            return {
              accuracy = math.random(45, 65),
              
              headshotRate = math.random(15, 35)
            }
          end
          
          sub.IsAimNormal = retTrue
        elseif sn == "ClientMemoryGuardSubsystem" then
          function sub.IsMemoryClean()
            return true, {code = 0}
          end
          
          function sub.ScanResult()
            return "clean"
          end
        elseif sn == "ShootVerifySubSystemClient" then
          sub.OnShootVerifyFailed = nop
          sub.VerifyShot = retTrue
        end
      end
    end
  end
  
  local function spoofBehavior()
    pcall(function()
      local sm = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
      if not sm then
        return
      end
      local hooks = {
        ClientAimTrackingSubsystem = {
          GetAimData = function()
            return {
              accuracy = math.random(48, 58),
              headshotRate = math.random(18, 28)
            }
          end,
          IsAimNormal = retTrue
        },
        ClientHawkEyePatrolSubsystem = {
          GetPatrolData = retEmpty,
          IsBeingWatched = retFalse,
          GetSpectatorCount = retZero
        },
        ClientRenderCheckSubsystem = {
          IsRenderClean = retTrue,
          GetRenderState = function()
            return "normal"
          end
        },
        ClientESPDetectionSubsystem = {
          HasESP = retFalse,
          CheckOverlay = function()
            return "clean"
          end
        },
        ClientWallhackDetectionSubsystem = {
          IsVisionNormal = retTrue,
          GetVisibilityRate = function()
            return math.random(70, 80)
          end
        }
      }
      for mod, methods in pairs(hooks) do
        local m = sm:Get(mod)
        if m then
          for k, v in pairs(methods) do
            m[k] = v
          end
        end
      end
    end)
  end
  
  local function disableHiggsBoson()
    pcall(function()
      local hbc = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
      if hbc then
        hbc.bMHActive = false
        hbc.bCallPreReplication = false
        if hbc.ControlMHActive then
          hbc.ControlMHActive = nop
        end
        if hbc.StartAvatarCheck then
          hbc.StartAvatarCheck = nop
        end
        if hbc.BlackList then
          for k in pairs(hbc.BlackList) do
            hbc.BlackList[k] = nil
          end
        end
      end
      if _G.AvatarCheckCallback then
        _G.AvatarCheckCallback.StartAvatarCheck = nop
        _G.AvatarCheckCallback.OnReportItemID = nop
      end
      _G.BlackList = {}
    end)
  end
  
  local function spoofMemoryAndKernel()
    pcall(function()
      local sm = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
      if sm then
        local sub = sm:Get("ClientMemoryGuardSubsystem")
        if sub then
          function sub.IsMemoryClean()
            return true, {code = 0}
          end
          
          function sub.ScanResult()
            return "clean"
          end
        end
        sub = sm:Get("ClientKernelCheckSubsystem")
        if sub then
          sub.IsKernelClean = retTrue
          
          function sub.GetKernelVersion()
            return "4.19.150-generic"
          end
          
          sub.IsBootloaderLocked = retTrue
        end
      end
      if _G.TssSdk then
        function _G.TssSdk.CheckKernel()
          return true, {status = "verified", tampered = false}
        end
        
        function _G.TssSdk.VerifyBoot()
          return true, {locked = true, verified = true}
        end
      end
    end)
  end
  
  function bypass.Init()
    blockScreenshots()
    blockGameplayCallbacks()
    spoofTssSdk()
    disableDetectionSubsystems()
    spoofBehavior()
    disableHiggsBoson()
    spoofMemoryAndKernel()
  end
  
  _G.WHABypass = bypass
end

InstallWHABypass()

local function InstallFMemoryBlock()
  local function retFalse()
    return false
  end
  
  local function isActive()
    return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
  end
  
  pcall(function()
    if rawget(_G, "IsDebuggerPresent") then
      _G.IsDebuggerPresent = retFalse
    end
    local FMemory = import("FMemory")
    if FMemory and FMemory.Memcpy and not FMemory.__blocked then
      local origMemcpy = FMemory.Memcpy
      
      function FMemory.Memcpy(dest, src, count)
        if isActive() then
          return
        end
        return origMemcpy(dest, src, count)
      end
      
      FMemory.__blocked = true
    end
  end)
end

InstallFMemoryBlock()

local function InstallShaderPakStubs()
  local function retFalse()
    return false
  end
  
  local function retEmpty()
    return {}
  end
  
  pcall(function()
    local UMat = import("Material")
    local UMatInst = import("MaterialInstance")
    if UMat then
      function UMat.GetShaderMap()
        return nil
      end
      
      function UMat.GetShaderPlatform()
        return 0
      end
    end
    if UMatInst then
      function UMatInst.GetShaderMap()
        return nil
      end
    end
    local FPakFile = import("FPakFile") or import("FPakPlatformFile")
    if FPakFile then
      FPakFile.GetPakEntries = retEmpty
      FPakFile.GetPakFolders = retEmpty
      FPakFile.FindFileInPakFiles = retFalse
    end
    local SSMgr = import("ScreenshotManager")
    if SSMgr then
      SSMgr.RequestScreenshot = retFalse
      SSMgr.HasPendingScreenshot = retFalse
    end
  end)
end

InstallShaderPakStubs()
local _cached_linear_color, _cached_skeletal_mesh, _cached_gameplay_data

local function getCachedLinearColor()
  if _cached_linear_color == nil then
    _cached_linear_color = import("LinearColor") or _G.FLinearColor
  end
  return _cached_linear_color
end

local function getCachedSkeletalMesh()
  if _cached_skeletal_mesh == nil then
    _cached_skeletal_mesh = import("SkeletalMeshComponent")
  end
  return _cached_skeletal_mesh
end

local function getCachedGameplayData()
  if _cached_gameplay_data == nil then
    local ok, mod = pcall(require, "GameLua.GameCore.Data.GameplayData")
    if ok then
      _cached_gameplay_data = mod
    end
  end
  return _cached_gameplay_data
end

local function GetSafeEnemyKey(enemy)
  if Valid(enemy) then
    if enemy.PlayerKey then
      return tostring(enemy.PlayerKey)
    end
    if type(enemy.GetUniqueID) == "function" then
      return tostring(enemy:GetUniqueID())
    end
  end
  return tostring(enemy)
end

local function CheckIsAI(pawn, markData)
  if markData.AK_IS_BOT ~= nil then
    return markData.AK_IS_BOT, true
  end
  local isAI = false
  local hasChecked = false
  pcall(function()
    if pawn.bIsAI == true or pawn.IsAI == true then
      isAI = true
      hasChecked = true
    end
    if type(pawn.IsBot) == "function" and pawn:IsBot() then
      isAI = true
      hasChecked = true
    end
    local pState = pawn.PlayerState or type(pawn.GetPlayerState) == "function" and pawn:GetPlayerState()
    if Valid(pState) then
      hasChecked = true
      if pState.bIsABot == true or pState.bIsBot == true then
        isAI = true
      end
      if type(pState.IsBot) == "function" and pState:IsBot() then
        isAI = true
      end
    end
  end)
  if hasChecked then
    markData.AK_IS_BOT = isAI
  end
  return isAI, hasChecked
end

local function GetAllSkeletalMeshes(enemy, markData)
  local curTime = os.clock()
  if markData and markData.CachedMeshes and markData.CachedMeshTime and curTime - markData.CachedMeshTime < 0.5 then
    local validMeshes = {}
    for _, cachedMesh in ipairs(markData.CachedMeshes) do
      local isPendingKill = false
      pcall(function()
        if type(cachedMesh.IsPendingKill) == "function" then
          isPendingKill = cachedMesh:IsPendingKill()
        end
      end)
      if Valid(cachedMesh) and not isPendingKill then
        table.insert(validMeshes, cachedMesh)
      end
    end
    markData.CachedMeshes = validMeshes
    return validMeshes
  end
  local meshes = {}
  if Valid(enemy.Mesh) then
    table.insert(meshes, enemy.Mesh)
  end
  pcall(function()
    local SkeletalMeshClass = getCachedSkeletalMesh()
    if SkeletalMeshClass and type(enemy.GetComponentsByClass) == "function" then
      local childs = enemy:GetComponentsByClass(SkeletalMeshClass)
      if childs then
        local count = type(childs.Num) == "function" and childs:Num() or #childs
        for i = 1, count do
          local comp = type(childs.Get) == "function" and childs:Get(i - 1) or childs[i]
          if Valid(comp) and comp ~= enemy.Mesh then
            table.insert(meshes, comp)
          end
        end
      end
    end
  end)
  if markData then
    markData.CachedMeshes = meshes
    markData.CachedMeshTime = curTime
  end
  return meshes
end

local function InitFakeHWID()
  pcall(function()
    local SystemLib = import("KismetSystemLibrary")
    if SystemLib and not _G.FakeHWID_Hooked then
      _G.Original_GetDeviceId = SystemLib.GetDeviceId
      
      function SystemLib.GetDeviceId(...)
        if _G.LexusConfig.FakeHWID then
          if not _G.FakeHWID_String then
            local chars = "0123456789ABCDEF"
            local hwid = ""
            for i = 1, 32 do
              local idx = math.random(1, #chars)
              hwid = hwid .. chars:sub(idx, idx)
              if i == 8 or i == 12 or i == 16 or i == 20 then
                hwid = hwid .. "-"
              end
            end
            _G.FakeHWID_String = hwid
          end
          return _G.FakeHWID_String
        end
        if _G.Original_GetDeviceId then
          return _G.Original_GetDeviceId(...)
        end
        return "UNKNOWN"
      end
      
      _G.FakeHWID_Hooked = true
      Notify("Fake HWID Hook Active")
    end
  end)
end

local function nop()
end

local function retFalse()
  return false
end

local function retZero()
  return 0
end

local function retEmpty()
  return {}
end

local function retNil()
  return nil
end

local function retTrue()
  return true
end

local function retEmptyString()
  return ""
end

local function InitializeSkinBypass()
  pcall(function()
    local ptlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
    if ptlog then
      ptlog.ReportEvent = nop
      ptlog.ReportDownloadResult = nop
      ptlog.ReportODPTDError = nop
      ptlog.ReportSkinError = nop
    end
    local AvatarUtils = package.loaded.AvatarUtils
    if AvatarUtils then
      AvatarUtils.CheckIsWeaponInBlackList = retFalse
      AvatarUtils.IsValidAvatar = retTrue
      AvatarUtils.CheckAvatarIntegrity = retTrue
      AvatarUtils.ReportInvalidAvatar = nop
    end
    local sub = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr"):Get("FileCheckSubsystem")
    if sub then
      sub.StartCheck = nop
      sub.ReportAbnormalFile = nop
      sub.StopCheck = nop
    end
    local eqEx = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
    if eqEx then
      eqEx.Report = nop
      eqEx.SendException = nop
    end
  end)
end

_G.VIP_Attachments = {
  [1101004236] = {
    1010042307,
    1010042306,
    1010042308,
    1010042304,
    1010042300,
    1010042305,
    1010042299,
    1010042298,
    1010042297,
    1010042296,
    1010042295,
    1010042294,
    0,
    1010042314,
    1010042309,
    1010042316,
    1010042317,
    1010042318,
    1010042310,
    1010042315,
    1010042319,
    0
  },
  [1101001116] = {
    1010011106,
    1010011107,
    1010011108,
    0,
    1010011109,
    1010011112,
    1010011105,
    1010011104,
    1010011103,
    0,
    1010011102,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1101001128] = {
    1010011232,
    1010011233,
    1010011234,
    1010011228,
    1010011227,
    1010011229,
    1010011226,
    1010011225,
    1010011224,
    1010011223,
    1010011222,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1101001154] = {
    1010011487,
    1010011488,
    1010011489,
    1010011493,
    1010011490,
    1010011494,
    1010011486,
    1010011485,
    1010011484,
    1010011483,
    1010011482,
    1010011497,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010011498,
    0
  },
  [1101001174] = {
    1010011667,
    1010011668,
    1010011669,
    1010011673,
    1010011670,
    1010011674,
    1010011666,
    1010011665,
    1010011664,
    1010011663,
    1010011662,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1101001213] = {
    1010012067,
    1010012068,
    1010012069,
    1010012072,
    1010012070,
    1010012073,
    1010012066,
    1010012065,
    1010012064,
    1010012063,
    1010012062,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010012074,
    0
  },
  [1101001231] = {
    1010012267,
    1010012268,
    1010012269,
    1010012273,
    1010012272,
    1010012274,
    1010012266,
    1010012265,
    1010012264,
    1010012263,
    1010012262,
    1010012075,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010012275,
    0
  },
  [1101001242] = {
    1010012357,
    1010012358,
    1010012359,
    1010012363,
    1010012362,
    1010012364,
    1010012356,
    1010012355,
    1010012354,
    1010012353,
    1010012352,
    1010012276,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010012365,
    0
  },
  [1101001249] = {
    1010012437,
    1010012438,
    1010012439,
    1010012443,
    1010012442,
    1010012444,
    1010012436,
    1010012435,
    1010012434,
    1010012433,
    1010012432,
    1010012366,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010012445,
    0
  },
  [1101001256] = {
    1010012588,
    1010012589,
    1010012590,
    1010012593,
    1010012592,
    1010012594,
    1010012587,
    1010012586,
    1010012585,
    1010012584,
    1010012583,
    1010012582,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010012595,
    0
  },
  [1101001265] = {
    1010012698,
    1010012699,
    1010012700,
    1010012703,
    1010012702,
    1010012704,
    1010012697,
    1010012696,
    1010012695,
    1010012694,
    1010012693,
    1010012692,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010012705,
    0
  },
  [1101001276] = {
    1010012698,
    1010012699,
    1010012700,
    1010012703,
    1010012702,
    1010012704,
    1010012697,
    1010012696,
    1010012695,
    1010012694,
    1010012693,
    1010012692,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010012705,
    0
  },
  [1101002029] = {
    1010020249,
    1010020250,
    1010020255,
    1010020247,
    1010020246,
    1010020248,
    1010020240,
    1010020239,
    1010020238,
    1010020237,
    1010020236,
    1010020235,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010020257,
    1010020256,
    1010020258
  },
  [1101002056] = {
    1010020519,
    0,
    0,
    1010020517,
    1010020516,
    1010020518,
    1010020500,
    1010020509,
    1010020508,
    1010020507,
    1010020506,
    1010020505,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1101002081] = {
    1010020768,
    1010020769,
    1010020770,
    1010020766,
    1010020760,
    1010020767,
    1010020759,
    1010020758,
    1010020757,
    1010020756,
    1010020755,
    1010020776,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010020775,
    1010020777,
    1010020778
  },
  [1101003070] = {
    1010030654,
    1010030653,
    1010030655,
    1010030649,
    1010030648,
    1010030650,
    1010030647,
    1010030646,
    1010030645,
    1010030644,
    1010030643,
    1010030642,
    0,
    1010030658,
    1010030656,
    1010030660,
    1010030662,
    1010030659,
    1010030657,
    0,
    1010030663,
    0
  },
  [1101003080] = {
    1010030754,
    1010030753,
    1010030755,
    1010030749,
    1010030748,
    1010030750,
    1010030747,
    1010030746,
    1010030745,
    1010030744,
    1010030743,
    1010030742,
    0,
    1010030758,
    1010030756,
    1010030760,
    1010030762,
    1010030759,
    1010030757,
    0,
    1010030763,
    0
  },
  [1101003099] = {
    1010030943,
    1010030944,
    1010030945,
    1010030939,
    1010030938,
    1010030942,
    1010030937,
    1010030936,
    1010030935,
    1010030934,
    1010030933,
    1010030932,
    0,
    1010030947,
    1010030946,
    1010030948,
    1010030949,
    1010030953,
    1010030952,
    0,
    1010030955,
    0
  },
  [1101003119] = {
    1010031139,
    1010031140,
    1010031142,
    1010031138,
    1010031137,
    1010031146,
    1010031136,
    1010031135,
    1010031134,
    1010031133,
    1010031132,
    0,
    0,
    1010031144,
    1010031143,
    0,
    0,
    0,
    1010031145,
    0,
    0,
    0
  },
  [1101003146] = {
    1010031229,
    1010031230,
    1010031237,
    1010031228,
    1010031227,
    1010031242,
    1010031226,
    1010031225,
    1010031224,
    1010031223,
    1010031222,
    0,
    0,
    1010031239,
    1010031238,
    0,
    0,
    0,
    1010031240,
    0,
    0,
    0
  },
  [1101003167] = {
    1010031609,
    1010031610,
    1010031613,
    1010031608,
    1010031607,
    1010031617,
    1010031606,
    1010031605,
    1010031604,
    1010031603,
    1010031602,
    1010031618,
    0,
    1010031615,
    1010031614,
    1010031620,
    1010031622,
    1010031619,
    1010031616,
    0,
    1010031623,
    0
  },
  [1101003181] = {
    1010031765,
    1010031764,
    1010031766,
    1010031759,
    1010031758,
    1010031763,
    1010031757,
    1010031756,
    1010031755,
    1010031754,
    1010031753,
    1010031752,
    0,
    1010031769,
    1010031767,
    1010031773,
    1010031774,
    1010031772,
    1010031768,
    0,
    1010031775,
    0
  },
  [1101003195] = {
    1010031912,
    1010031911,
    1010031913,
    1010031908,
    1010031907,
    1010031909,
    1010031906,
    1010031905,
    1010031904,
    1010031903,
    1010031902,
    1010031901,
    0,
    1010031916,
    1010031914,
    1010031918,
    1010031919,
    1010031917,
    1010031915,
    0,
    1010031921,
    0
  },
  [1101003208] = {
    1010032034,
    1010032033,
    1010032045,
    1010032029,
    1010032028,
    1010032032,
    1010032027,
    1010032026,
    1010032025,
    1010032024,
    1010032023,
    1010032022,
    0,
    1010032038,
    1010032036,
    1010032042,
    1010032043,
    1010032039,
    1010032037,
    0,
    1010032044,
    0
  },
  [1101004046] = {
    1010040474,
    1010040475,
    1010040476,
    1010040472,
    1010040471,
    1010040473,
    1010040470,
    1010040469,
    1010040468,
    1010040467,
    1010040466,
    1010040481,
    0,
    1010040479,
    1010040477,
    1010040482,
    1010040483,
    1010040484,
    1010040478,
    1010040480,
    1010040485,
    0
  },
  [1101004062] = {
    1010040578,
    1010040577,
    1010040579,
    1010040575,
    1010040570,
    1010040576,
    1010040569,
    1010040568,
    1010040567,
    1010040566,
    1010040565,
    1010040564,
    0,
    1010040585,
    1010040580,
    1010040587,
    1010040588,
    1010040589,
    1010040584,
    1010040586,
    1010040590,
    1010040594
  },
  [1101004098] = {
    1010040924,
    1010040926,
    1010040925,
    0,
    1010040937,
    1010040938,
    1010040935,
    1010040934,
    1010040929,
    1010040928,
    1010040927,
    0,
    0,
    1010040939,
    1010040945,
    0,
    0,
    0,
    1010040944,
    1010040936,
    0,
    0
  },
  [1101004138] = {
    1010041136,
    1010041137,
    1010041138,
    1010041134,
    1010041129,
    1010041135,
    1010041128,
    1010041127,
    1010041126,
    1010041125,
    1010041124,
    0,
    0,
    1010041145,
    1010041139,
    0,
    0,
    0,
    1010041144,
    1010041146,
    0,
    0
  },
  [1101004163] = {
    1010041570,
    1010041574,
    1010041575,
    1010041568,
    1010041567,
    1010041569,
    1010041566,
    1010041565,
    1010041564,
    1010041560,
    1010041554,
    0,
    0,
    1010041578,
    1010041576,
    0,
    0,
    0,
    1010041577,
    1010041579,
    0,
    0
  },
  [1101004201] = {
    1010041956,
    1010041957,
    1010041958,
    1010041950,
    1010041949,
    1010041955,
    1010041948,
    1010041947,
    1010041946,
    1010041945,
    1010041944,
    1010041967,
    0,
    1010041965,
    1010041959,
    0,
    0,
    0,
    1010041960,
    1010041966,
    0,
    0
  },
  [1101004209] = {
    1010042038,
    1010042037,
    1010042039,
    1010042035,
    1010042034,
    1010042036,
    1010042029,
    1010042028,
    1010042027,
    1010042026,
    1010042025,
    1010042024,
    0,
    1010042046,
    1010042044,
    1010042048,
    1010042049,
    1010042054,
    1010042045,
    1010042047,
    1010042055,
    0
  },
  [1101004218] = {
    1010042128,
    1010042127,
    1010042129,
    1010042125,
    1010042124,
    1010042126,
    1010042119,
    1010042118,
    1010042117,
    1010042116,
    1010042115,
    1010042114,
    0,
    1010042136,
    1010042134,
    1010042138,
    1010042139,
    1010042144,
    1010042135,
    1010042137,
    1010042145,
    0
  },
  [1101004226] = {
    1010042238,
    1010042237,
    1010042239,
    1010042235,
    1010042234,
    1010042236,
    1010042233,
    1010042232,
    1010042231,
    1010042219,
    1010042218,
    1010042217,
    0,
    1010042243,
    1010042241,
    1010042245,
    1010042246,
    1010042247,
    1010042242,
    1010042244,
    1010042248,
    0
  },
  [1101004246] = {
    1010042406,
    1010042407,
    1010042408,
    1010042404,
    1010042400,
    1010042405,
    1010042399,
    1010042398,
    1010042397,
    1010042396,
    1010042395,
    1010042394,
    0,
    1010042414,
    1010042409,
    1010042416,
    1010042417,
    1010042418,
    1010042410,
    1010042415,
    1010042419,
    1010042420
  },
  [1101005038] = {
    0,
    0,
    1010050327,
    1010050329,
    1010050328,
    1010050330,
    1010050326,
    1010050325,
    1010050324,
    1010050323,
    1010050322,
    1010050334,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1101005052] = {
    0,
    0,
    1010050467,
    1010050469,
    1010050468,
    1010050470,
    1010050466,
    1010050465,
    1010050464,
    1010050463,
    1010050462,
    1010050473,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1101005098] = {
    0,
    0,
    1010050928,
    1010050930,
    1010050929,
    1010050932,
    1010050927,
    1010050926,
    1010050925,
    1010050924,
    1010050923,
    1010050922,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1101006062] = {
    1010060573,
    1010060572,
    1010060574,
    1010060564,
    1010060563,
    1010060571,
    1010060562,
    1010060561,
    1010060554,
    1010060553,
    1010060552,
    1010060551,
    0,
    1010060583,
    1010060581,
    1010060591,
    1010060592,
    1010060584,
    1010060582,
    0,
    1010060593,
    0
  },
  [1101006075] = {
    1010060702,
    1010060701,
    1010060703,
    1010060698,
    1010060697,
    1010060699,
    1010060696,
    1010060695,
    1010060694,
    1010060693,
    1010060692,
    1010060691,
    0,
    1010060706,
    1010060704,
    1010060708,
    1010060709,
    1010060707,
    1010060705,
    0,
    1010060711,
    0
  },
  [1101006085] = {
    1010060796,
    1010060795,
    1010060797,
    1010060793,
    1010060789,
    1010060794,
    1010060788,
    1010060787,
    1010060786,
    1010060785,
    1010060784,
    1010060783,
    0,
    1010060800,
    1010060798,
    1010060804,
    1010060805,
    1010060803,
    1010060799,
    0,
    1010060806,
    0
  },
  [1101007046] = {
    1010070410,
    1010070413,
    1010070414,
    1010070408,
    1010070407,
    1010070409,
    1010070406,
    1010070405,
    1010070404,
    1010070403,
    1010070402,
    1010070418,
    0,
    1010070417,
    1010070415,
    1010070420,
    1010070422,
    1010070419,
    1010070416,
    0,
    1010070423,
    0
  },
  [1101007062] = {
    1010070579,
    1010070578,
    1010070581,
    1010070576,
    1010070575,
    1010070577,
    1010070574,
    1010070573,
    1010070572,
    1010070571,
    1010070569,
    1010070568,
    0,
    1010070584,
    1010070582,
    1010070585,
    1010070586,
    1010070587,
    1010070583,
    0,
    1010070588,
    0
  },
  [1101007071] = {
    1010070663,
    1010070662,
    1010070664,
    1010070659,
    1010070658,
    1010070660,
    1010070657,
    1010070656,
    1010070655,
    1010070654,
    1010070653,
    1010070652,
    0,
    1010070667,
    1010070665,
    1010070668,
    1010070669,
    1010070670,
    1010070666,
    0,
    1010070672,
    0
  },
  [1101008051] = {
    1010080463,
    1010080464,
    1010080465,
    1010080459,
    1010080458,
    1010080462,
    1010080457,
    1010080456,
    1010080455,
    1010080454,
    1010080453,
    1010080452,
    0,
    1010080467,
    1010080466,
    1010080468,
    1010080469,
    1010080473,
    1010080472,
    0,
    1010080475,
    0
  },
  [1101008061] = {
    1010080563,
    1010080564,
    1010080565,
    1010080559,
    1010080558,
    1010080562,
    1010080557,
    1010080556,
    1010080555,
    1010080554,
    1010080553,
    0,
    0,
    1010080567,
    1010080566,
    0,
    0,
    0,
    1010080572,
    0,
    0,
    0
  },
  [1101008070] = {
    1010080609,
    1010080612,
    1010080613,
    1010080608,
    1010080607,
    1010080617,
    1010080606,
    1010080605,
    1010080604,
    1010080603,
    1010080602,
    0,
    0,
    1010080615,
    1010080614,
    0,
    0,
    0,
    1010080616,
    0,
    0,
    0
  },
  [1101008081] = {
    1010080740,
    1010080743,
    1010080745,
    1010080738,
    1010080737,
    1010080739,
    1010080736,
    1010080735,
    1010080734,
    1010080733,
    1010080732,
    1010080748,
    0,
    1010080747,
    1010080746,
    1010080750,
    1010080752,
    1010080749,
    1010080744,
    0,
    1010080753,
    0
  },
  [1101008104] = {
    1010080980,
    1010080982,
    1010080984,
    1010080978,
    1010080977,
    1010080979,
    1010080976,
    1010080975,
    1010080974,
    1010080973,
    1010080972,
    1010080992,
    0,
    1010080986,
    1010080985,
    1010080989,
    1010080987,
    1010080993,
    1010080983,
    0,
    1010080988,
    0
  },
  [1101008116] = {
    1010081110,
    1010081112,
    1010081114,
    1010081108,
    1010081107,
    1010081109,
    1010081106,
    1010081105,
    1010081104,
    1010081103,
    1010081102,
    0,
    0,
    1010081116,
    1010081115,
    0,
    0,
    0,
    1010081113,
    0,
    0,
    0
  },
  [1101008126] = {
    1010081210,
    1010081225,
    1010081226,
    1010081208,
    1010081207,
    1010081209,
    1010081206,
    1010081205,
    1010081204,
    1010081203,
    1010081202,
    1010081218,
    0,
    1010081217,
    1010081216,
    1010081219,
    1010081220,
    1010081222,
    1010081214,
    1010081228,
    1010081227,
    1010081229
  },
  [1101008136] = {
    1010081314,
    1010081315,
    1010081316,
    1010081312,
    1010081308,
    1010081313,
    1010081307,
    1010081306,
    1010081305,
    1010081304,
    1010081303,
    1010081302,
    0,
    1010081318,
    1010081317,
    1010081322,
    1010081323,
    1010081325,
    1010081324,
    0,
    1010081326,
    0
  },
  [1101008146] = {
    1010081401,
    1010081402,
    1010081403,
    1010081398,
    1010081397,
    1010081399,
    1010081396,
    1010081395,
    1010081394,
    1010081393,
    1010081392,
    1010081391,
    0,
    1010081405,
    1010081404,
    1010081406,
    1010081407,
    1010081409,
    1010081408,
    0,
    1010081411,
    0
  },
  [1101008154] = {
    1010081531,
    1010081532,
    1010081533,
    1010081528,
    1010081527,
    1010081529,
    1010081526,
    1010081525,
    1010081524,
    1010081523,
    1010081522,
    1010081521,
    0,
    1010081541,
    1010081534,
    1010081542,
    1010081543,
    1010081545,
    1010081544,
    0,
    1010081546,
    0
  },
  [1101008163] = {
    1010081582,
    1010081583,
    1010081584,
    1010081579,
    1010081578,
    1010081580,
    1010081577,
    1010081576,
    1010081575,
    1010081574,
    1010081573,
    1010081572,
    0,
    1010081586,
    1010081585,
    1010081587,
    1010081588,
    1010081590,
    1010081589,
    0,
    1010081592,
    0
  },
  [1101012033] = {
    1010120284,
    1010120285,
    1010120286,
    1010120280,
    1010120279,
    1010120283,
    1010120278,
    1010120277,
    1010120276,
    1010120275,
    1010120274,
    1010120273,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1010120287,
    0
  },
  [1101100012] = {
    1011000066,
    1011000067,
    1011000068,
    0,
    0,
    0,
    1011000058,
    1011000057,
    1011000056,
    1011000055,
    1011000054,
    1011000053,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1011000073,
    0
  },
  [1101102007] = {
    1011010025,
    1011010024,
    1011010026,
    1011010020,
    1011010019,
    1011010023,
    1011010018,
    1011010017,
    1011010016,
    1011010015,
    1011010014,
    1011010013,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1011010027,
    0
  },
  [1101102017] = {
    1011020027,
    1011020028,
    1011020029,
    1011020025,
    1011020024,
    1011020026,
    1011020019,
    1011020018,
    1011020017,
    1011020016,
    1011020015,
    1011020014,
    0,
    1011020036,
    1011020034,
    1011020038,
    1011020039,
    1011020044,
    1011020035,
    1011020037,
    1011020045,
    1011020047
  },
  [1101102025] = {
    1011020127,
    1011020128,
    1011020129,
    1011020125,
    1011020124,
    1011020126,
    1011020119,
    1011020118,
    1011020117,
    1011020116,
    1011020115,
    1011020114,
    0,
    1011020136,
    1011020134,
    1011020138,
    1011020139,
    1011020144,
    1011020135,
    1011020137,
    1011020145,
    0
  },
  [1101102041] = {
    1011020214,
    1011020215,
    1011020216,
    1011020212,
    1011020211,
    1011020213,
    1011020209,
    1011020208,
    1011020207,
    1011020206,
    1011020205,
    1011020204,
    0,
    1011020219,
    1011020217,
    1011020222,
    1011020223,
    1011020224,
    1011020218,
    1011020221,
    1011020225,
    1011020229
  },
  [1101102049] = {
    1011020356,
    1011020357,
    1011020358,
    1011020354,
    1011020350,
    1011020355,
    1011020349,
    1011020348,
    1011020347,
    1011020346,
    1011020345,
    1011020344,
    0,
    1011020364,
    1011020359,
    1011020366,
    1011020367,
    1011020368,
    1011020360,
    1011020365,
    1011020369,
    1011020370
  },
  [1101101007] = {
    1011020436,
    1011020437,
    1011020438,
    1011020434,
    1011020430,
    1011020435,
    1011020429,
    1011020428,
    1011020427,
    1011020426,
    1011020425,
    1011020424,
    0,
    1011020444,
    1011020439,
    1011020446,
    1011020447,
    1011020448,
    1011020440,
    1011020445,
    1011020449,
    1011020450
  },
  [1102001120] = {
    1020011137,
    1020011138,
    1020011139,
    1020011135,
    1020011134,
    1020011136,
    1020011133,
    1020011132,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1020011142,
    0,
    0
  },
  [1102001130] = {
    1020011247,
    1020011248,
    1020011249,
    1020011245,
    1020011244,
    1020011246,
    1020011243,
    1020011242,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1020011250,
    0,
    0
  },
  [1102002043] = {
    1020020372,
    1020020374,
    1020020373,
    1020020383,
    1020020380,
    1020020384,
    1020020379,
    1020020378,
    1020020377,
    1020020376,
    1020020375,
    1020020388,
    0,
    1020020385,
    1020020387,
    0,
    0,
    0,
    1020020386,
    0,
    0,
    0
  },
  [1102002061] = {
    1020020552,
    1020020554,
    1020020553,
    1020020563,
    1020020562,
    1020020564,
    1020020559,
    1020020558,
    1020020557,
    1020020556,
    1020020555,
    1020020578,
    0,
    1020020565,
    1020020567,
    1020020573,
    1020020574,
    1020020572,
    1020020566,
    0,
    1020020569,
    0
  },
  [1102002136] = {
    1020021314,
    1020021313,
    1020021315,
    1020021309,
    1020021308,
    1020021312,
    1020021307,
    1020021306,
    1020021305,
    1020021304,
    1020021303,
    1020021302,
    0,
    1020021318,
    1020021316,
    1020021323,
    1020021324,
    1020021322,
    1020021317,
    0,
    1020021325,
    0
  },
  [1102002424] = {
    1020024193,
    1020024192,
    1020024194,
    1020024189,
    1020024188,
    1020024190,
    1020024187,
    1020024186,
    1020024185,
    1020024184,
    1020024183,
    1020024182,
    0,
    1020024197,
    1020024195,
    1020024199,
    1020024200,
    1020024198,
    1020024196,
    0,
    1020024202,
    0
  },
  [1102003080] = {
    1020030755,
    1020030756,
    1020030758,
    0,
    1020030749,
    1020030754,
    1020030748,
    1020030747,
    1020030746,
    1020030745,
    1020030744,
    1020030764,
    0,
    1020030760,
    0,
    1020030759,
    1020030757,
    0,
    0,
    1020030765,
    0,
    0
  },
  [1102003100] = {
    1020030956,
    1020030957,
    1020030958,
    1020030954,
    1020030950,
    1020030955,
    1020030949,
    1020030948,
    1020030947,
    1020030946,
    1020030945,
    1020030944,
    0,
    1020030964,
    0,
    1020030960,
    1020030959,
    1020030965,
    0,
    1020030967,
    1020030966,
    1020030968
  },
  [1102005064] = {
    1020050588,
    1020050589,
    1020050590,
    0,
    0,
    0,
    1020050587,
    1020050586,
    1020050585,
    1020050584,
    1020050583,
    1020050582,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1020050592,
    0
  },
  [1103001101] = {
    1030010954,
    1030010955,
    1030010956,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1030010953,
    1030010952,
    1030010951,
    0,
    0,
    0,
    0,
    0,
    0,
    1030010957,
    0,
    1030010958
  },
  [1103001146] = {
    1030011344,
    1030011345,
    1030011346,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1030011343,
    1030011342,
    1030011341,
    0,
    0,
    0,
    0,
    0,
    0,
    1030011347,
    0,
    1030011348
  },
  [1103001154] = {
    1030011484,
    1030011485,
    1030011486,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1030011483,
    1030011482,
    1030011481,
    0,
    0,
    0,
    0,
    0,
    0,
    1030011487,
    0,
    1030011488
  },
  [1103001179] = {
    1030011738,
    1030011739,
    1030011741,
    0,
    0,
    0,
    1030011737,
    1030011736,
    1030011735,
    1030011734,
    1030011733,
    1030011732,
    1030011731,
    0,
    0,
    0,
    0,
    0,
    0,
    1030011742,
    1030011743,
    1030011744
  },
  [1103001191] = {
    1030011858,
    1030011859,
    1030011861,
    0,
    0,
    0,
    1030011857,
    1030011856,
    1030011855,
    1030011854,
    1030011853,
    1030011852,
    1030011851,
    0,
    0,
    0,
    0,
    0,
    0,
    1030011862,
    1030011863,
    1030011864
  },
  [1103001202] = {
    1030011948,
    1030011949,
    1030011950,
    0,
    0,
    0,
    1030011947,
    1030011946,
    1030011945,
    1030011944,
    1030011943,
    1030011942,
    1030011941,
    0,
    0,
    0,
    0,
    0,
    0,
    1030011951,
    1030011952,
    1030011953
  },
  [1103002030] = {
    1030020245,
    1030020246,
    1030020247,
    1030020252,
    1030020249,
    1030020253,
    1030020258,
    1030020257,
    1030020256,
    1030020255,
    1030020244,
    1030020243,
    1030020242,
    0,
    0,
    0,
    0,
    0,
    0,
    1030020248,
    0,
    0
  },
  [1103002059] = {
    1030020544,
    1030020545,
    1030020546,
    1030020542,
    1030020539,
    1030020543,
    1030020538,
    1030020537,
    1030020536,
    1030020535,
    1030020534,
    1030020533,
    1030020532,
    0,
    0,
    0,
    0,
    0,
    0,
    1030020547,
    1030020548,
    0
  },
  [1103002087] = {
    1030020824,
    1030020825,
    1030020826,
    0,
    0,
    0,
    1030020818,
    1030020817,
    1030020816,
    1030020815,
    1030020814,
    1030020813,
    1030020812,
    0,
    0,
    0,
    0,
    0,
    0,
    1030020827,
    1030020828,
    0
  },
  [1103002106] = {
    1030021009,
    1030021010,
    1030021012,
    1030021015,
    1030021014,
    1030021016,
    1030021008,
    1030021007,
    1030021006,
    1030021005,
    1030021004,
    1030021003,
    1030021002,
    0,
    0,
    0,
    0,
    0,
    0,
    1030021013,
    1030021017,
    0
  },
  [1103002113] = {
    1030021079,
    1030021080,
    1030021082,
    1030021085,
    1030021084,
    1030021086,
    1030021078,
    1030021077,
    1030021076,
    1030021075,
    1030021074,
    1030021073,
    1030021072,
    0,
    0,
    0,
    0,
    0,
    0,
    1030021083,
    1030021087,
    0
  },
  [1103003022] = {
    1030030165,
    1030030166,
    1030030167,
    1030030172,
    1030030169,
    1030030173,
    0,
    0,
    0,
    0,
    1030030164,
    1030030163,
    1030030162,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1103003030] = {
    1030030256,
    1030030257,
    1030030258,
    1030030254,
    1030030253,
    1030030255,
    1030030248,
    1030030247,
    1030030246,
    1030030245,
    1030030244,
    1030030243,
    1030030242,
    0,
    0,
    0,
    0,
    0,
    0,
    1030030259,
    1030030249,
    0
  },
  [1103003042] = {
    1030030374,
    1030030375,
    1030030376,
    1030030372,
    1030030369,
    1030030373,
    0,
    0,
    0,
    0,
    1030030364,
    1030030363,
    1030030362,
    0,
    0,
    0,
    0,
    0,
    0,
    1030030377,
    0,
    0
  },
  [1103003051] = {
    1030030458,
    1030030459,
    1030030460,
    1030030456,
    1030030455,
    1030030457,
    0,
    0,
    0,
    0,
    1030030454,
    1030030453,
    1030030452,
    0,
    0,
    0,
    0,
    0,
    0,
    1030030463,
    0,
    0
  },
  [1103003062] = {
    1030030568,
    1030030569,
    1030030570,
    1030030566,
    1030030565,
    1030030567,
    0,
    0,
    0,
    0,
    1030030564,
    1030030563,
    1030030562,
    0,
    0,
    0,
    0,
    0,
    0,
    1030030572,
    0,
    0
  },
  [1103003079] = {
    1030030744,
    1030030745,
    1030030746,
    1030030742,
    1030030740,
    1030030743,
    1030030738,
    1030030737,
    1030030736,
    1030030735,
    1030030734,
    1030030733,
    1030030732,
    0,
    0,
    0,
    0,
    0,
    0,
    1030030747,
    1030030739,
    0
  },
  [1103003087] = {
    1030030825,
    1030030826,
    1030030827,
    1030030823,
    1030030824,
    1030030824,
    1030030818,
    1030030817,
    1030030816,
    1030030815,
    1030030814,
    1030030813,
    1030030812,
    0,
    0,
    0,
    0,
    0,
    0,
    1030030828,
    1030030819,
    0
  },
  [1103004037] = {
    1030040315,
    1030040316,
    1030040317,
    1030040325,
    1030040324,
    1030040323,
    0,
    0,
    0,
    0,
    1030040314,
    1030040313,
    1030040312,
    1030040327,
    1030040326,
    0,
    0,
    0,
    1030040328,
    1030040329,
    0,
    0
  },
  [1103006030] = {
    1030060245,
    1030060246,
    1030060247,
    0,
    1030060253,
    1030060252,
    0,
    0,
    0,
    0,
    1030060244,
    1030060243,
    1030060242,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1103007028] = {
    1030070233,
    1030070234,
    1030070235,
    1030070226,
    1030070225,
    1030070227,
    1030070218,
    1030070217,
    1030070216,
    1030070215,
    1030070214,
    1030070213,
    1030070212,
    0,
    0,
    0,
    0,
    0,
    0,
    1030070236,
    1030070219,
    0
  },
  [1103012010] = {
    0,
    0,
    0,
    0,
    0,
    0,
    1030120038,
    1030120037,
    1030120036,
    1030120035,
    1030120034,
    1030120033,
    1030120032,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1103012019] = {
    0,
    0,
    0,
    0,
    0,
    0,
    1030120138,
    1030120137,
    1030120136,
    1030120135,
    1030120134,
    1030120133,
    1030120132,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1103012031] = {
    0,
    0,
    0,
    0,
    0,
    0,
    1030120258,
    1030120257,
    1030120256,
    1030120255,
    1030120254,
    1030120253,
    1030120252,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1103012039] = {
    0,
    0,
    0,
    0,
    0,
    0,
    1030120339,
    1030120338,
    1030120337,
    1030120336,
    1030120335,
    1030120334,
    1030120333,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  },
  [1103102007] = {
    1031020026,
    1031020027,
    1031020028,
    1031020024,
    1031020023,
    1031020025,
    1031020019,
    1031020018,
    1031020017,
    1031020016,
    1031020015,
    1031020014,
    1031020013,
    0,
    0,
    0,
    0,
    0,
    0,
    1031020029,
    0,
    0
  },
  [1105001034] = {
    0,
    0,
    0,
    0,
    1050010287,
    1050010289,
    1050010286,
    1050010285,
    1050010284,
    1050010283,
    1050010282,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1050010292,
    0,
    0
  },
  [1105001048] = {
    0,
    0,
    0,
    1050010429,
    1050010428,
    1050010434,
    1050010427,
    1050010426,
    1050010425,
    1050010424,
    1050010423,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1050010435,
    0,
    1050010436
  },
  [1105001069] = {
    0,
    0,
    0,
    1050010639,
    1050010638,
    1050010640,
    1050010637,
    1050010636,
    1050010635,
    1050010634,
    1050010633,
    1050010645,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1050010643,
    1050010646,
    1050010644
  },
  [1105002091] = {
    0,
    0,
    0,
    0,
    0,
    0,
    1050020847,
    1050020846,
    1050020845,
    1050020844,
    1050020843,
    1050020842,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1050020848
  },
  [1105010019] = {
    0,
    0,
    0,
    0,
    0,
    0,
    1050100144,
    1050100143,
    1050100142,
    1050100141,
    1050100139,
    1050100138,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  }
}
_G.BaseAttachToIndex = {
  [201010] = 1,
  [201005] = 1,
  [201004] = 1,
  [201009] = 2,
  [201003] = 2,
  [201002] = 2,
  [201011] = 3,
  [201007] = 3,
  [201006] = 3,
  [204012] = 4,
  [204005] = 4,
  [204008] = 4,
  [204011] = 5,
  [204004] = 5,
  [204007] = 5,
  [204013] = 6,
  [204006] = 6,
  [204009] = 6,
  [203001] = 7,
  [203002] = 8,
  [203003] = 9,
  [203014] = 10,
  [203004] = 11,
  [203015] = 12,
  [203005] = 13,
  [202002] = 14,
  [202001] = 15,
  [202004] = 16,
  [202005] = 17,
  [202007] = 18,
  [202006] = 19,
  [205002] = 20,
  [205003] = 20,
  [205001] = 20,
  [203018] = 21,
  [204014] = 22
}
_G.VipAttachToIndex = {}
for skinId, attachList in pairs(_G.VIP_Attachments) do
  for index, attachId in ipairs(attachList) do
    if attachId > 0 then
      _G.VipAttachToIndex[attachId] = index
    end
  end
end
local _SKIN_BASE_PATH = "/storage/emulated/0/Android/data/com.pubg.imobile/files/"
local _SKIN_ATTACH_PATH = _SKIN_BASE_PATH .. "attachments.txt"
_G.g_parts = _G.g_parts or {}
_G.skinAttachCache = _G.skinAttachCache or {}
local ATTACH_NAME_MAP = {
  ["Red Dot Sight"] = "RedDot",
  ["Holographic Sight"] = "Holo",
  ["2x Scope"] = "Scope2x",
  ["3x Scope"] = "Scope3x",
  ["4x Scope"] = "Scope4x",
  ["6x Scope"] = "Scope6x",
  ["8x Scope"] = "Scope8x",
  ["Canted Sight"] = "CantedSight",
  ["Flash Hider"] = "FlashHider",
  Compensator = "Compensator",
  Suppressor = "Suppressor",
  ["Extended Mag"] = "ExtMag",
  ["Quickdraw Mag"] = "QuickMag",
  ["Extended Quickdraw Mag"] = "ExtQuickMag",
  ["Angled Foregrip"] = "AngledGrip",
  ["Vertical Foregrip"] = "VerticalGrip",
  ["Thumb Grip"] = "ThumbGrip",
  ["Half Grip"] = "HalfGrip",
  ["Light Grip"] = "LightGrip",
  ["Laser Sight"] = "LaserSight",
  ["Tactical Stock"] = "TactStock",
  Stock = "MicroStock",
  ["Cheek Pad"] = "CheekPad"
}
local _attachFileCache

local function _parseAttachmentsFile()
  local result = {}
  pcall(function()
    local f = io.open(_SKIN_ATTACH_PATH, "r")
    if not f then
      return
    end
    local content = f:read("*all")
    f:close()
    local curSkin
    for line in content:gmatch("[^\r\n]+") do
      local firstNum = line:match("^(%d+)%s*|")
      if firstNum then
        local num = tonumber(firstNum)
        if num and 1100000000 < num then
          curSkin = num
          result[curSkin] = result[curSkin] or {}
        elseif num and curSkin then
          local attachName = line:match("^%d+%s*|%s*%x+%s*|%s*(.-)%s*$")
          attachName = attachName or line:match("^%d+%s*|%s*(.-)%s*$")
          if attachName and attachName ~= "" then
            local key = ATTACH_NAME_MAP[attachName]
            if key then
              result[curSkin][key] = num
            end
          end
        end
      elseif line:find("^#%-%-%-%-") and line:find("skin") then
        curSkin = nil
      end
    end
  end)
  return result
end

function _G.GetAttachForSkin(skinId, key)
  if not skinId or skinId == 0 or not key then
    return nil
  end
  if not _attachFileCache then
    _attachFileCache = _parseAttachmentsFile()
  end
  local t = _attachFileCache[skinId]
  if not t then
    return nil
  end
  local v = t[key]
  return v and 0 < v and v or nil
end

function _G.GetAttachFileCache()
  if not _attachFileCache then
    _attachFileCache = _parseAttachmentsFile()
  end
  return _attachFileCache
end

function _G.download_item(i)
  if not i then
    return
  end
  pcall(function()
    local PM = require("client.slua.logic.download.puffer.puffer_manager")
    local PC = require("client.slua.logic.download.puffer_const")
    if PM.GetState(PC.ENUM_DownloadType.ODPAK, {i}) ~= PC.ENUM_DownloadState.Done then
      PM.Download(PC.ENUM_DownloadType.ODPAK, {i})
    end
  end)
end

_G.muzzles = {
  id_flash_hider = {
    201010,
    201005,
    201004
  },
  id_compensator = {
    201009,
    201003,
    201002
  },
  id_suppressor = {
    201011,
    201006,
    201007
  }
}
_G.foregrips = {
  id_Angledforegrip = 202001,
  id_thumb_grip = 202006,
  id_vertical_grip = 202002,
  id_light_grip = 202004,
  id_half_grip = 202005,
  id_ergonomic_grip = 202051,
  id_laser_sight = 202007
}
_G.magazines = {
  id_expanded_mag = {
    204011,
    204007,
    204004
  },
  id_quick_mag = {
    204012,
    204008,
    204005
  },
  id_expanded_quick_mag = {
    204013,
    204009,
    204006
  }
}
_G.scopes = {
  id_reddot = 203001,
  id_holo = 203002,
  id_2x = 203003,
  id_3x = 203014,
  id_4x = 203004,
  id_6x = 203015,
  id_8x = 203005
}
_G.stock = {
  id_microStock = 205001,
  id_tactical = 205002,
  id_bulletloop = 204014,
  id_CheekPad = 205003
}
_G.ItemUpgradeSystem = nil
pcall(function()
  local MM = require("client.module_framework.ModuleManager")
  local IUS = MM.GetModule(MM.CommonModuleConfig.ItemUpgradeManager)
  if IUS then
    IUS:DefineAndResetData()
    IUS:OnInitialize()
    _G.ItemUpgradeSystem = IUS
  end
end)

function _G.get_group_id(itemId)
  if not _G.ItemUpgradeSystem or not itemId then
    return nil
  end
  local cfg = _G.ItemUpgradeSystem:GetUpgradeCfg(itemId)
  return cfg and cfg.GroupID or nil
end

function _G.InitParts(groupId, itemId)
  if not itemId then
    return _G.g_parts
  end
  if _G.g_parts[itemId] and next(_G.g_parts[itemId]) then
    return _G.g_parts
  end
  _G.g_parts[itemId] = {}
  if not _G.ItemUpgradeSystem then
    return _G.g_parts
  end
  if _G.ItemUpgradeSystem:IsWeaponIsRefit(itemId) then
    groupId = _G.ItemUpgradeSystem:GetNormalGroupID(groupId or _G.get_group_id(itemId))
  else
    groupId = groupId or _G.get_group_id(itemId)
  end
  if not groupId then
    return _G.g_parts
  end
  local cfg = rawGetTableByFilter("ItemUpgradeUnLockConfig", "GroupID", groupId)
  if cfg then
    for _, info in pairs(cfg) do
      local partId = info.PartId
      if _G.ItemUpgradeSystem:IsWeaponIsRefit(itemId) then
        local switched = _G.ItemUpgradeSystem:PartIDSwitch(partId, true)
        if switched and switched ~= partId then
          partId = switched
        end
      end
      local item = rawGetTableData("Item", partId)
      if item and item.ItemName then
        _G.g_parts[itemId][item.ItemName] = partId
      end
    end
  end
  return _G.g_parts
end

function _G.GetRawAttachMap(skinid)
  if not skinid or skinid <= 0 then
    return {}
  end
  if _G.skinAttachCache[skinid] then
    return _G.skinAttachCache[skinid]
  end
  local UAvatarUtils = import("AvatarUtils")
  if not UAvatarUtils then
    return {}
  end
  local list = UAvatarUtils.GetWeaponAvatarDefaultAttachmentSkin(skinid, {}, false) or {}
  _G.skinAttachCache[skinid] = list
  return list
end

function _G.GetSlotFromSkinID(skinid, slot)
  if not skinid or not slot then
    return 0
  end
  local list = _G.GetRawAttachMap(skinid)
  local attachmentTypeMap = {
    [1] = {
      291004,
      291102,
      291001,
      291006,
      291005,
      291002,
      293003,
      293004,
      293009,
      293007,
      293005,
      293006,
      295001,
      295002,
      291007,
      291003,
      292002,
      292003,
      291011,
      291008
    },
    [2] = {
      205005,
      205102,
      205007,
      205009,
      205006
    },
    [3] = {
      203008,
      203009,
      203006,
      203022,
      203010
    }
  }
  local targetIDs = attachmentTypeMap[slot]
  if not targetIDs then
    return 0
  end
  for _, targetID in ipairs(targetIDs) do
    for attachID, attachSkinID in pairs(list) do
      if attachID == targetID then
        return attachSkinID
      end
    end
  end
  return 0
end

function _G.AutoDetectAttach(skinid, base_id)
  if not skinid or not base_id then
    return 0
  end
  local list = _G.GetRawAttachMap(skinid)
  local v = list[base_id]
  return v and 0 < v and v or 0
end

function _G.get_muzzleid(current_id, avatarid)
  local initial_id = current_id
  _G.InitParts(_G.get_group_id(avatarid), avatarid)
  local p = _G.g_parts[avatarid]
  
  local function is_in(t)
    for _, id in ipairs(_G.muzzles[t]) do
      if current_id == id then
        return true
      end
    end
    return false
  end
  
  if is_in("id_flash_hider") then
    local auto = _G.AutoDetectAttach(avatarid, current_id)
    if 0 < auto then
      if p then
        current_id = _G.GetAttachForSkin(avatarid, "FlashHider") or current_id
      end
    end
  elseif is_in("id_compensator") then
    local auto = _G.AutoDetectAttach(avatarid, current_id)
    if 0 < auto then
      if p then
        current_id = _G.GetAttachForSkin(avatarid, "Compensator") or current_id
      end
    end
  elseif is_in("id_suppressor") then
    local auto = _G.AutoDetectAttach(avatarid, current_id)
    current_id = _G.GetAttachForSkin(avatarid, "Suppressor") or p and p.Suppressor or 0 < auto and auto or current_id
  end
  return current_id, initial_id ~= current_id
end

function _G.get_forgripid(current_id, avatarid)
  local initial_id = current_id
  _G.InitParts(_G.get_group_id(avatarid), avatarid)
  local p = _G.g_parts[avatarid]
  local auto = _G.AutoDetectAttach(avatarid, current_id)
  if current_id == _G.foregrips.id_Angledforegrip then
    if 0 < auto then
      if p then
        current_id = _G.GetAttachForSkin(avatarid, "AngledGrip") or current_id
      end
    end
  elseif current_id == _G.foregrips.id_thumb_grip then
    if 0 < auto then
      if p then
        current_id = _G.GetAttachForSkin(avatarid, "ThumbGrip") or current_id
      end
    end
  elseif current_id == _G.foregrips.id_vertical_grip then
    if 0 < auto then
      if p then
        current_id = _G.GetAttachForSkin(avatarid, "VerticalGrip") or current_id
      end
    end
  elseif current_id == _G.foregrips.id_light_grip then
    if 0 < auto then
      if p then
        current_id = _G.GetAttachForSkin(avatarid, "LightGrip") or current_id
      end
    end
  elseif current_id == _G.foregrips.id_half_grip then
    if 0 < auto then
      if p then
        current_id = _G.GetAttachForSkin(avatarid, "HalfGrip") or current_id
      end
    end
  elseif current_id == _G.foregrips.id_ergonomic_grip then
    if 0 < auto and p then
      current_id = p["Ergonomic Grip"] or current_id
    end
  else
    current_id = current_id == _G.foregrips.id_laser_sight and (_G.GetAttachForSkin(avatarid, "LaserSight") or p and p["Laser Sight"] or 0 < auto and auto) or current_id
  end
  return current_id, initial_id ~= current_id
end

function _G.get_magazinesid(current_id, avatarid)
  local initial_id = current_id
  _G.InitParts(_G.get_group_id(avatarid), avatarid)
  local p = _G.g_parts[avatarid]
  
  local function is_in(t)
    for _, id in ipairs(_G.magazines[t]) do
      if current_id == id then
        return true
      end
    end
    return false
  end
  
  if is_in("id_expanded_mag") then
    local auto = _G.AutoDetectAttach(avatarid, current_id)
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "ExtMag") or p and p["Extended Mag"] or _G.GetSlotFromSkinID(avatarid, 1) or current_id
    end
  elseif is_in("id_quick_mag") then
    local auto = _G.AutoDetectAttach(avatarid, current_id)
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "QuickMag") or p and p["Quickdraw Mag"] or _G.GetSlotFromSkinID(avatarid, 1) or current_id
    end
  elseif is_in("id_expanded_quick_mag") then
    local auto = _G.AutoDetectAttach(avatarid, current_id)
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "ExtQuickMag") or p and p["Extended Quickdraw Mag"] or _G.GetSlotFromSkinID(avatarid, 1) or current_id
    end
  else
    local fb = _G.GetSlotFromSkinID(avatarid, 1)
    if fb and 0 < fb then
      current_id = fb
    end
  end
  return current_id, initial_id ~= current_id
end

function _G.get_scopeid(current_id, avatarid)
  local initial_id = current_id
  _G.InitParts(_G.get_group_id(avatarid), avatarid)
  local p = _G.g_parts[avatarid]
  local auto = _G.AutoDetectAttach(avatarid, current_id)
  if current_id == _G.scopes.id_reddot then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "RedDot") or p and p["Red Dot Sight"] or _G.GetSlotFromSkinID(avatarid, 3) or current_id
    end
  elseif current_id == _G.scopes.id_holo then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "Holo") or p and p["Holographic Sight"] or _G.GetSlotFromSkinID(avatarid, 3) or current_id
    end
  elseif current_id == _G.scopes.id_2x then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "Scope2x") or p and p["2x Scope"] or _G.GetSlotFromSkinID(avatarid, 3) or current_id
    end
  elseif current_id == _G.scopes.id_3x then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "Scope3x") or p and p["3x Scope"] or _G.GetSlotFromSkinID(avatarid, 3) or current_id
    end
  elseif current_id == _G.scopes.id_4x then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "Scope4x") or p and p["4x Scope"] or _G.GetSlotFromSkinID(avatarid, 3) or current_id
    end
  elseif current_id == _G.scopes.id_6x then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "Scope6x") or p and p["6x Scope"] or _G.GetSlotFromSkinID(avatarid, 3) or current_id
    end
  elseif current_id == _G.scopes.id_8x then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "Scope8x") or p and p["8x Scope"] or _G.GetSlotFromSkinID(avatarid, 3) or current_id
    end
  else
    local fb = _G.GetSlotFromSkinID(avatarid, 3)
    if fb and 0 < fb then
      current_id = fb
    end
  end
  return current_id, initial_id ~= current_id
end

function _G.get_stockid(current_id, avatarid)
  local initial_id = current_id
  _G.InitParts(_G.get_group_id(avatarid), avatarid)
  local p = _G.g_parts[avatarid]
  local auto = _G.AutoDetectAttach(avatarid, current_id)
  if current_id == _G.stock.id_microStock then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "MicroStock") or p and p.Stock or _G.GetSlotFromSkinID(avatarid, 2) or current_id
    end
  elseif current_id == _G.stock.id_tactical then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "TactStock") or p and p["Tactical Stock"] or _G.GetSlotFromSkinID(avatarid, 2) or current_id
    end
  elseif current_id == _G.stock.id_bulletloop then
    if 0 < auto then
      current_id = p and p["Bullet Loop"] or _G.GetSlotFromSkinID(avatarid, 2) or current_id
    end
  elseif current_id == _G.stock.id_CheekPad then
    if 0 < auto then
      current_id = _G.GetAttachForSkin(avatarid, "CheekPad") or p and p["Cheek Pad"] or _G.GetSlotFromSkinID(avatarid, 2) or current_id
    end
  else
    local fb = _G.GetSlotFromSkinID(avatarid, 2)
    if fb and 0 < fb then
      current_id = fb
    end
  end
  return current_id, initial_id ~= current_id
end

function _G.apply_attachment(CurWeapon, avatarid)
  local array = CurWeapon.synData
  for AttachIdx = 0, 4 do
    local Data = array:Get(AttachIdx)
    local itemid = slua.IndexReference(Data, "defineID").TypeSpecificID
    if itemid and 0 < itemid and itemid < 10000000 then
      local isrefresh = false
      if AttachIdx == 0 then
        Data.defineID.TypeSpecificID, isrefresh = _G.get_muzzleid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
        array:Set(AttachIdx, Data)
      elseif AttachIdx == 1 then
        Data.defineID.TypeSpecificID, isrefresh = _G.get_forgripid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
        array:Set(AttachIdx, Data)
      elseif AttachIdx == 2 then
        Data.defineID.TypeSpecificID, isrefresh = _G.get_magazinesid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
        array:Set(AttachIdx, Data)
      elseif AttachIdx == 3 then
        Data.defineID.TypeSpecificID, isrefresh = _G.get_stockid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
        array:Set(AttachIdx, Data)
      elseif AttachIdx == 4 then
        Data.defineID.TypeSpecificID, isrefresh = _G.get_scopeid(slua.IndexReference(Data, "defineID").TypeSpecificID, avatarid)
        array:Set(AttachIdx, Data)
      else
        break
      end
      if isrefresh then
        _G.download_item(slua.IndexReference(Data, "defineID").TypeSpecificID)
        CurWeapon:DelayHandleAvatarMeshChanged()
      end
    end
  end
end

_G.WeaponSkinMap = _G.WeaponSkinMap or {}
_G.VehicleSkinMap = _G.VehicleSkinMap or {}
_G.OutfitMap = _G.OutfitMap or {}
_G.skinIdCache = _G.skinIdCache or {}
_G.skinIdCache2 = _G.skinIdCache2 or {}
_G.OutfitSkins = {
  Suit = {
    1405628,
    1407920,
    1407916,
    1407895,
    1405760,
    1407870,
    1407856,
    1407812,
    1407758,
    1407789,
    1407682,
    1407696,
    1407695,
    1407632,
    1407631,
    1407667,
    1407618,
    1407573,
    1407572,
    1407559,
    1407558,
    1407550,
    1407523,
    1407718,
    1407512,
    1407471,
    1407470,
    1406985,
    1407353,
    1407366,
    1407330,
    1407487,
    1410668,
    1407276,
    1407275,
    1407142,
    1407141,
    1407140,
    1406971,
    1406897,
    1406891,
    1407187,
    1405802,
    1405192,
    1405334,
    1400687,
    1405340,
    1405623,
    1405132,
    1405436,
    1405435,
    1405434,
    1405433,
    1405208,
    1407916,
    1407917,
    1407918,
    1407921,
    1407921,
    1407926,
    1407901,
    1407902,
    1407903,
    1407904,
    1407822,
    1407823,
    1407824,
    1407825,
    1407807,
    1407808,
    1407845,
    1407846,
    1407847,
    1407848,
    1407794,
    1411037,
    1407795,
    1411038,
    1407796,
    1411039
  },
  Pants = {
    1404002,
    1404050,
    1404425,
    1404495,
    1400650,
    1404522,
    1404441,
    1404152,
    1404196,
    1404134,
    1404137,
    1404164,
    1404191,
    1404466,
    1400052,
    404035,
    1404181,
    404084,
    1404516
  },
  Hair = {
    40605010,
    40605011,
    40605012,
    1410480,
    1410085,
    1410299,
    1402834,
    441400152,
    1400150,
    1402582,
    1410289,
    1402218,
    1402223,
    1402283,
    1400426
  },
  Bag = {
    {
      501001,
      501002,
      501003
    },
    {
      1501001174,
      1501002174,
      1501003174
    },
    {
      1501001220,
      1501002220,
      1501003220
    },
    {
      1501001051,
      1501002051,
      1501003051
    },
    {
      1501001443,
      1501002443,
      1501003443
    },
    {
      1501001265,
      1501002265,
      1501003265
    },
    {
      1501001321,
      1501002321,
      1501003321
    },
    {
      1501001277,
      1501002277,
      1501003277
    },
    {
      1501001550,
      1501002550,
      1501003550
    },
    {
      1501001592,
      1501002592,
      1501003592
    },
    {
      1501001608,
      1501002608,
      1501003608
    },
    {
      1501001024,
      1501002024,
      1501003024
    },
    {
      1501001019,
      1501002019,
      1501003019
    },
    {
      1501001179,
      1501002179,
      1501003179
    },
    {
      1501001194,
      1501002194,
      1501003194
    },
    {
      1501001346,
      1501002346,
      1501003346
    }
  },
  Helmet = {
    {
      502001,
      502002,
      502003
    },
    {
      1502001014,
      1502002014,
      1502003014
    },
    {
      1502001349,
      1502002349,
      1502003349
    },
    {
      1502001012,
      1502002012,
      1502003012
    },
    {
      1502001009,
      1502002009,
      1502003009
    },
    {
      1502001397,
      1502002397,
      1502003397
    },
    {
      1502001390,
      1502002390,
      1502003390
    },
    {
      1502001381,
      1502002381,
      1502003381
    },
    {
      1502001358,
      1502002358,
      1502003358
    },
    {
      1502001350,
      1502002350,
      1502003350
    },
    {
      1502001342,
      1502002342,
      1502003342
    }
  },
  Pet = {
    50000,
    50001,
    50002,
    50003,
    50004,
    50005,
    50006,
    50021,
    50022,
    50038,
    50039,
    50040
  }
}
_G.skinIdMappings = {
  [101004] = {
    101004,
    1101004246,
    1101004226,
    1101004236,
    1101004062,
    1101004078,
    1101004086,
    1101004201,
    1101004218
  },
  [101001] = {
    101001,
    1101001276,
    1101001089,
    1101001213,
    1101001172,
    1101001127,
    1101001230,
    1101001241
  },
  [101003] = {
    101003,
    1101003227,
    1103003208,
    1101003195,
    1101003187,
    1101003098,
    1101003166,
    1101003218
  },
  [102002] = {
    102002,
    1102002136,
    1102002043,
    1102002061,
    1102002424
  },
  [101008] = {
    101008,
    1101008146,
    1101008154,
    1101008079,
    1101008126,
    1101008104,
    1101008146,
    1101008061,
    1101008116
  },
  [101006] = {
    101006,
    1101006085,
    1101006061,
    1101006074,
    1101006043,
    1101006032,
    1101006084
  },
  [102001] = {102001, 1102001120},
  [101005] = {101005, 1101005098},
  [104003] = {104003, 1104003037},
  [104004] = {
    104004,
    1104004035,
    1104004041
  },
  [101101] = {101101, 1101101007},
  [101007] = {
    101007,
    1101007071,
    1101007062,
    1101007046,
    1101007078,
    1101007072
  },
  [101012] = {101012, 1101012033},
  [101002] = {
    101002,
    1101002081,
    1101002056,
    1101002029,
    1101002149
  },
  [101102] = {
    101102,
    1101102049,
    1101102025,
    1101102017,
    1101102007,
    1101102032
  },
  [103001] = {
    103001,
    1103001202,
    1103001191,
    1103001179,
    1103001146,
    1103001101,
    1103001079,
    1103001202
  },
  [103002] = {
    103002,
    1103002113,
    1103002098,
    1103002087,
    1103002060,
    1103002059,
    1103002030
  },
  [103003] = {
    103003,
    1103003087,
    1103003079,
    1103003069,
    1103003062,
    1103003055,
    1103003051,
    1103003042,
    1103003030,
    1103003022,
    1103003092
  }
}
_G.VehicleSkins = {
  [1961001] = {
    1961151,
    1961152,
    1961153,
    1961147,
    1961148,
    1961149,
    1961144,
    1961145,
    1961137,
    1961138,
    1961139,
    1961066,
    1961067,
    1961065,
    1961062,
    1961063,
    1961064,
    1961054,
    1961055,
    1961056,
    1961057,
    1961051,
    1961052,
    1961053,
    1961048,
    1961049,
    1961050,
    1961044,
    1961045,
    1961046,
    1961047,
    1961041,
    1961042,
    1961043,
    1961038,
    1961039,
    1961040,
    1961033,
    1961034,
    1961035,
    1961029,
    1961030,
    1961031,
    1961032,
    1961007,
    1961010,
    1961012,
    1961013,
    1961014,
    1961015,
    1961140,
    1961141,
    1961142,
    1961143,
    1991023,
    1991024
  },
  [1903001] = {
    1903228,
    1903220,
    1903221,
    1903223,
    1903218,
    1903219,
    1903213,
    1903212,
    1903202,
    1908094,
    1908095,
    1903193,
    1903192,
    1903191,
    19030790,
    19030791,
    19030800,
    19030801,
    1903074,
    1903075,
    1903076,
    1903071,
    1903072,
    1903073,
    1903216,
    1903217,
    1991001,
    1991002,
    1991003,
    1991004,
    1903088,
    1903089,
    1903090,
    1903023
  },
  [1915004] = {
    1915021,
    1915022,
    1915008,
    1915009,
    1914011
  },
  [1908001] = {
    1908108,
    1908109,
    19080951,
    19081080,
    1908084,
    1908085,
    1908075,
    1908077,
    1908078,
    1908070,
    1908069,
    1908066,
    1908086,
    1908088,
    1908089,
    1908018
  },
  [1907002] = {
    1907058,
    1907054,
    1907059,
    1907053,
    1907063,
    1907072,
    1907040,
    1907041,
    1907027,
    1907047,
    1907021
  }
}
_G.CustSlotType = {
  ClothesEquipemtSlot = 5,
  BackpackEquipemtSlot = 8,
  HelmetEquipemtSlot = 9,
  ParachuteEquipemtSlot = 11,
  GlideEquipemtSlot = 15
}

local function DownloadGameItem(id)
  local puffer_manager = require("client.slua.logic.download.puffer.puffer_manager")
  local puffer_const = require("client.slua.logic.download.puffer_const")
  if not puffer_manager or not puffer_const then
    return
  end
  local state = puffer_manager.GetState(puffer_const.ENUM_DownloadType.ODPTD, {id})
  if state ~= puffer_const.ENUM_DownloadState.Done and state ~= puffer_const.ENUM_DownloadState.Downloading then
    puffer_manager.Download(puffer_const.ENUM_DownloadType.ODPTD, {id})
  end
end

_G.download_item = DownloadGameItem

function _G.get_skin_id(weaponID)
  if not weaponID then
    return nil
  end
  local targetSkinId = _G.WeaponSkinMap and _G.WeaponSkinMap[weaponID]
  if targetSkinId and 0 < targetSkinId then
    if not _G.skinIdCache2[targetSkinId] then
      if _G.download_item then
        pcall(_G.download_item, targetSkinId)
      end
      _G.skinIdCache2[targetSkinId] = true
    end
    return targetSkinId
  end
  return weaponID
end

function _G.equip_character_avatar(Character)
  if not (Character and slua.isValid(Character)) or not Character.AvatarComponent2 then
    return
  end
  local BackpackUtils = import("BackpackUtils")
  local SlotSyncData = Character.AvatarComponent2.NetAvatarData and Character.AvatarComponent2.NetAvatarData.SlotSyncData
  if not (SlotSyncData and slua.isValid(SlotSyncData)) or not BackpackUtils then
    return
  end
  
  local function EquipAvatar(ApplyDataIdx, mappedSkin, ApplyEquipSlot, isLevelDependent, levelFunc)
    if not mappedSkin or mappedSkin == 0 then
      return
    end
    local slotData = SlotSyncData:Get(ApplyDataIdx)
    if slotData and slotData.SlotID == ApplyEquipSlot then
      local applyItemId = mappedSkin
      if isLevelDependent and type(mappedSkin) == "table" then
        local level = levelFunc(slotData.AdditionalItemID) or 1
        if level < 1 then
          level = 1
        end
        if 3 < level then
          level = 3
        end
        applyItemId = mappedSkin[level] or mappedSkin[1]
      end
      if not applyItemId or applyItemId == 0 or slotData.ItemId == applyItemId then
        return
      end
      if not _G.skinIdCache[applyItemId] then
        if _G.download_item then
          pcall(_G.download_item, applyItemId)
        end
        _G.skinIdCache[applyItemId] = true
      end
      slotData.ItemId = applyItemId
      SlotSyncData:Set(ApplyDataIdx, slotData)
      Character.AvatarComponent2:OnRep_BodySlotStateChanged()
    end
  end
  
  local hasGliderSlot = false
  for i = 0, SlotSyncData:Num() - 1 do
    local slotData = SlotSyncData:Get(i)
    if slotData and slotData.SlotID == _G.CustSlotType.GlideEquipemtSlot then
      hasGliderSlot = true
      break
    end
  end
  if not hasGliderSlot then
    SlotSyncData:Add({
      SlotID = _G.CustSlotType.GlideEquipemtSlot,
      ItemId = 0
    })
  end
  for i = 0, SlotSyncData:Num() - 1 do
    EquipAvatar(i, _G.OutfitMap.Suit or 0, _G.CustSlotType.ClothesEquipemtSlot, false)
    EquipAvatar(i, _G.OutfitMap.Pants or 0, 6, false)
    EquipAvatar(i, _G.OutfitMap.Hair or 0, 7, false)
    EquipAvatar(i, _G.OutfitMap.Bag, _G.CustSlotType.BackpackEquipemtSlot, true, BackpackUtils.GetEquipmentBagLevel)
    EquipAvatar(i, _G.OutfitMap.Helmet, _G.CustSlotType.HelmetEquipemtSlot, true, BackpackUtils.GetEquipmentHelmetLevel)
    EquipAvatar(i, _G.OutfitMap.Parachute or 0, _G.CustSlotType.ParachuteEquipemtSlot, false)
  end
end

function _G.ApplyWeaponSkins(PlayerCharacter)
  pcall(function()
    local WeaponManager = PlayerCharacter:GetWeaponManager()
    if not slua.isValid(WeaponManager) then
      return
    end
    for slot = 1, 3 do
      local Weapon = WeaponManager:GetInventoryWeaponByPropSlot(slot)
      if slua.isValid(Weapon) and slua.isValid(Weapon.synData) then
        do
          local WeaponID = Weapon:GetWeaponID()
          local SkinID = _G.get_skin_id(WeaponID) or WeaponID
          local isModified = false
          local SkinData = Weapon.synData:Get(7)
          if SkinData and SkinData.defineID and SkinData.defineID.TypeSpecificID ~= SkinID then
            SkinData.defineID.TypeSpecificID = SkinID
            Weapon.synData:Set(7, SkinData)
            if Weapon.SetWeaponAvatarID then
              pcall(function()
                Weapon:SetWeaponAvatarID(SkinID)
              end)
            end
            if not _G.skinIdCache[SkinID] then
              _G.download_item(SkinID)
              _G.skinIdCache[SkinID] = true
            end
            isModified = true
          end
          if 10000000 <= SkinID and _G.VIP_Attachments and _G.VIP_Attachments[SkinID] then
            for AttachIdx = 0, 5 do
              local attachData = Weapon.synData:Get(AttachIdx)
              if attachData then
                local defineIDRef = slua.IndexReference(attachData, "defineID")
                if defineIDRef then
                  local attachmentId = defineIDRef.TypeSpecificID
                  if attachmentId and 0 < attachmentId then
                    local mapIndex = _G.BaseAttachToIndex[attachmentId] or _G.VipAttachToIndex[attachmentId]
                    if mapIndex and _G.VIP_Attachments[SkinID][mapIndex] and _G.VIP_Attachments[SkinID][mapIndex] > 0 then
                      local targetAttachId = _G.VIP_Attachments[SkinID][mapIndex]
                      if targetAttachId ~= attachmentId then
                        attachData.defineID.TypeSpecificID = targetAttachId
                        Weapon.synData:Set(AttachIdx, attachData)
                        if not _G.skinIdCache2[targetAttachId] then
                          if _G.download_item then
                            pcall(_G.download_item, targetAttachId)
                          end
                          _G.skinIdCache2[targetAttachId] = true
                        end
                        isModified = true
                      end
                    end
                  end
                end
              end
            end
          end
          if _G.apply_attachment and 10000000 <= SkinID then
            pcall(function()
              _G.apply_attachment(Weapon, SkinID)
            end)
          end
          if isModified then
            if Weapon.DelayHandleAvatarMeshChanged then
              pcall(function()
                Weapon:DelayHandleAvatarMeshChanged()
              end)
            end
            if Weapon.OnRep_synData then
              pcall(function()
                Weapon:OnRep_synData()
              end)
            end
          end
        end
      end
    end
  end)
end

_G.recoilOriginalCache = _G.recoilOriginalCache or setmetatable({}, {__mode = "k"})
_G.RECOIL_FIELDS = {
  "RecoilKick",
  "RecoilKickADS",
  "AnimationKick",
  "GameDeviationFactor",
  "RecoilModifierStand",
  "RecoilModifierCrouch",
  "RecoilModifierProne",
  "CameraShakeScale",
  "AimCameraShakeScale",
  "ShootCameraShakeScale",
  "FireCameraShakeScale",
  "GameDeviationAccuracy",
  "ShotGunHorizontalSpread",
  "ShotGunVerticalSpread",
  "DeviationMultiplier"
}
_G.RECOIL_TARGET_VALUES = {
  RecoilKick = 0.01,
  RecoilKickADS = 0.01,
  AnimationKick = 0.01,
  GameDeviationFactor = 0.01,
  RecoilModifierStand = 0.01,
  RecoilModifierCrouch = 0.01,
  RecoilModifierProne = 0.01,
  CameraShakeScale = 0.01,
  AimCameraShakeScale = 0.01,
  ShootCameraShakeScale = 0.01,
  FireCameraShakeScale = 0.01,
  GameDeviationAccuracy = 0.01,
  ShotGunHorizontalSpread = 0.01,
  ShotGunVerticalSpread = 0.01,
  DeviationMultiplier = 0.01
}
_G.RECOIL_INFO_FIELDS = {
  "VerticalRecoilMin",
  "VerticalRecoilMax",
  "RecoilSpeedVertical",
  "RecoilSpeedHorizontal",
  "VerticalRecoveryMax"
}
_G.RECOIL_INFO_TARGET = {
  VerticalRecoilMin = 0.01,
  VerticalRecoilMax = 0.01,
  RecoilSpeedVertical = 0.01,
  RecoilSpeedHorizontal = 0.01,
  VerticalRecoveryMax = 0.01
}

function _G.ApplyNoRecoil()
  pcall(function()
    local GameplayData = getCachedGameplayData()
    if not GameplayData or not GameplayData.GetPlayerController then
      return
    end
    local pc = GameplayData.GetPlayerController()
    if not Valid(pc) then
      return
    end
    local char = pc:GetPlayerCharacterSafety()
    if not Valid(char) then
      return
    end
    local wm = char.WeaponManagerComponent
    if not wm then
      return
    end
    local weapon = wm.CurrentWeaponReplicated
    if not weapon then
      return
    end
    local entity = weapon.ShootWeaponEntityComp
    if not Valid(entity) then
      return
    end
    if not _G.LexusConfig.NoRecoilEnabled then
      if _G.recoilOriginalCache[entity] then
        local saved = _G.recoilOriginalCache[entity]
        for k, v in pairs(saved) do
          if k == "RecoilInfo" then
            if entity.RecoilInfo then
              for rk, rv in pairs(v) do
                entity.RecoilInfo[rk] = rv
              end
            end
          elseif k == "ShootCameraShakeScale" then
            if entity.ShootCameraShake then
              entity.ShootCameraShake.Scale = v
            end
          else
            entity[k] = v
          end
        end
        _G.recoilOriginalCache[entity] = nil
      end
      return
    end
    if not _G.recoilOriginalCache[entity] then
      local saved = {
        RecoilInfo = {}
      }
      for _, f in ipairs(_G.RECOIL_FIELDS) do
        if entity[f] ~= nil then
          saved[f] = entity[f]
        end
      end
      if entity.RecoilInfo then
        for _, f in ipairs(_G.RECOIL_INFO_FIELDS) do
          if entity.RecoilInfo[f] ~= nil then
            saved.RecoilInfo[f] = entity.RecoilInfo[f]
          end
        end
      end
      if entity.ShootCameraShake then
        saved.ShootCameraShakeScale = entity.ShootCameraShake.Scale
      end
      _G.recoilOriginalCache[entity] = saved
    end
    local orig = _G.recoilOriginalCache[entity]
    local slider = (_G.LexusConfig.RecoilReduction or 100) / 100
    if 1 < slider then
      slider = 1
    end
    for _, f in ipairs(_G.RECOIL_FIELDS) do
      if entity[f] ~= nil and orig[f] ~= nil and _G.RECOIL_TARGET_VALUES[f] then
        entity[f] = orig[f] + (_G.RECOIL_TARGET_VALUES[f] - orig[f]) * slider
      end
    end
    if entity.RecoilInfo then
      for _, f in ipairs(_G.RECOIL_INFO_FIELDS) do
        if entity.RecoilInfo[f] ~= nil and orig.RecoilInfo[f] ~= nil and _G.RECOIL_INFO_TARGET[f] then
          entity.RecoilInfo[f] = orig.RecoilInfo[f] + (_G.RECOIL_INFO_TARGET[f] - orig.RecoilInfo[f]) * slider
        end
      end
    end
    if entity.ShootCameraShake then
      local origScale = orig.ShootCameraShakeScale or 1.0
      entity.ShootCameraShake.Scale = origScale + (0.01 - origScale) * slider
    end
  end)
end

function _G.ApplyAutoHead()
  pcall(function()
    local GameplayData = getCachedGameplayData()
    if not GameplayData or not GameplayData.GetPlayerController then
      return
    end
    local pc = GameplayData.GetPlayerController()
    if not Valid(pc) then
      return
    end
    local localChar = pc:GetPlayerCharacterSafety()
    if not Valid(localChar) then
      return
    end
    local localLoc
    pcall(function()
      localLoc = localChar:K2_GetActorLocation()
    end)
    if not localLoc then
      return
    end
    local myTeamID = localChar.TeamID
    local isScoped = false
    pcall(function()
      local cam = localChar.ThirdPersonCameraComponent
      if Valid(cam) and cam.FieldOfView then
        isScoped = cam.FieldOfView < 60
      end
    end)
    local maxDist = isScoped and 500 or 250
    local closestEnemy
    local closestDist = 999999
    local allChars = GameplayData.GetAllPlayerCharacters and GameplayData.GetAllPlayerCharacters() or {}
    for _, enemy in pairs(allChars) do
      if Valid(enemy) and enemy ~= localChar and enemy.TeamID ~= myTeamID then
        local bDead = false
        pcall(function()
          if type(enemy.IsDead) == "function" then
            bDead = enemy:IsDead()
          elseif enemy.bIsDead ~= nil then
            bDead = enemy.bIsDead
          end
        end)
        if not bDead then
          do
            local eLoc
            pcall(function()
              eLoc = enemy:K2_GetActorLocation()
            end)
            if eLoc then
              do
                local dx = (eLoc.X or 0) - (localLoc.X or 0)
                local dy = (eLoc.Y or 0) - (localLoc.Y or 0)
                local dz = (eLoc.Z or 0) - (localLoc.Z or 0)
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if closestDist > dist then
                  closestDist = dist
                  closestEnemy = enemy
                end
              end
            end
          end
        end
      end
    end
    if closestEnemy and maxDist >= closestDist then
      local targetLoc
      pcall(function()
        local mesh = closestEnemy.Mesh
        if Valid(mesh) and type(mesh.GetSocketLocation) == "function" then
          if isScoped then
            targetLoc = mesh:GetSocketLocation("head")
          else
            targetLoc = mesh:GetSocketLocation("spine_02")
            if not targetLoc then
              targetLoc = closestEnemy:K2_GetActorLocation()
            end
            if targetLoc then
              targetLoc.Z = targetLoc.Z + 100
            end
          end
        end
      end)
      if not targetLoc then
        pcall(function()
          targetLoc = closestEnemy:K2_GetActorLocation()
        end)
        if targetLoc then
          targetLoc.Z = targetLoc.Z + (isScoped and 180 or 100)
        end
      end
      if targetLoc then
        do
          local myCam = localChar.ThirdPersonCameraComponent
          if Valid(myCam) then
            do
              local camLoc
              pcall(function()
                camLoc = myCam:K2_GetComponentLocation()
              end)
              if camLoc then
                do
                  local dirX = (targetLoc.X or 0) - (camLoc.X or 0)
                  local dirY = (targetLoc.Y or 0) - (camLoc.Y or 0)
                  local dirZ = (targetLoc.Z or 0) - (camLoc.Z or 0)
                  local len = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
                  if 0 < len then
                    do
                      local rot
                      pcall(function()
                        local FRotator = import("Rotator")
                        local pitch = math.deg(math.asin(dirZ / len))
                        local yaw = math.deg(math.atan2(dirY, dirX))
                        if isScoped then
                          rot = FRotator and FRotator(-pitch, yaw, 0) or {
                            Pitch = -pitch,
                            Yaw = yaw,
                            Roll = 0
                          }
                        else
                          local curRot = pc:GetControlRotation()
                          if curRot then
                            local curPitch = curRot.Pitch or 0
                            local curYaw = curRot.Yaw or 0
                            local blend = 0.35
                            local newPitch = curPitch + (-pitch - curPitch) * blend
                            local newYaw = curYaw + (yaw - curYaw) * blend
                            rot = FRotator and FRotator(newPitch, newYaw, 0) or {
                              Pitch = newPitch,
                              Yaw = newYaw,
                              Roll = 0
                            }
                          else
                            rot = FRotator and FRotator(-pitch, yaw, 0) or {
                              Pitch = -pitch,
                              Yaw = yaw,
                              Roll = 0
                            }
                          end
                        end
                      end)
                      if rot then
                        pcall(function()
                          pc:SetControlRotation(rot)
                        end)
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end)
end

function _G.ApplyWeaponAimbot()
  if not CheckExpiration() then
    return
  end
  pcall(function()
    local pc = slua_GameFrontendHUD:GetPlayerController()
    if not slua.isValid(pc) then
      return
    end
    local char = pc:GetPlayerCharacterSafety()
    if not slua.isValid(char) then
      return
    end
    local wm = char.WeaponManagerComponent
    if not slua.isValid(wm) then
      return
    end
    local weapon = wm.CurrentWeaponReplicated
    if not slua.isValid(weapon) then
      return
    end
    local entity = weapon.ShootWeaponEntityComp
    if not slua.isValid(entity) then
      return
    end
    entity.RecoilKickADS = 0.02
    entity.GameDeviationFactor = 0.01
    entity.GameDeviationAccuracy = 0.01
    if entity.AutoAimingConfig then
      for _, range in ipairs({"OuterRange", "InnerRange"}) do
        local cfg = entity.AutoAimingConfig[range]
        if cfg then
          cfg.Speed = 4.0
          cfg.RangeRate = 2.0
          cfg.SpeedRate = 3.0
          cfg.RangeRateSight = 2.0
          cfg.SpeedRateSight = 3.0
          cfg.CrouchRate = 2.5
          cfg.ProneRate = 3.0
          cfg.DyingRate = 0
          cfg.adsorbMaxRange = 200
          cfg.adsorbMinRange = 20
          cfg.adsorbMinAttenuationDis = 100
          cfg.adsorbMaxAttenuationDis = 8000
          cfg.adsorbActiveMinRange = 20
        end
      end
      entity.AutoAimingConfig = entity.AutoAimingConfig
    end
    pcall(function()
      local aimComp = char.BP_AutoAimingComponent_C or char.BP_AutoAimingComponent or char.AutoAimingComponent
      if slua.isValid(aimComp) and aimComp.Bones then
        pcall(function()
          aimComp.Bones[0] = "neck_01"
        end)
        pcall(function()
          aimComp.Bones[1] = "neck_01"
        end)
        pcall(function()
          aimComp.Bones[2] = "neck_01"
        end)
        pcall(function()
          aimComp.Bones:Set(0, "neck_01")
        end)
        pcall(function()
          aimComp.Bones:Set(1, "neck_01")
        end)
        pcall(function()
          aimComp.Bones:Set(2, "neck_01")
        end)
      end
    end)
  end)
end

function _G.ApplyVehicleSkins(PlayerCharacter)
  pcall(function()
    local Vehicle = PlayerCharacter:GetCurrentVehicle()
    if not slua.isValid(Vehicle) then
      _G.LastVehicleEntity = nil
      return
    end
    if _G.LastVehicleEntity == Vehicle and _G.CurrentEquipVehicleID ~= nil then
      return
    end
    local VehicleAvatar = Vehicle.VehicleAvatar or Vehicle.VehicleAvatarComponent_BP or Vehicle:GetAvatarComponent()
    if not slua.isValid(VehicleAvatar) then
      return
    end
    local defId = tostring(VehicleAvatar:GetDefaultAvatarID() or Vehicle.VehicleID or "")
    local currentId = tostring(Vehicle:GetAvatarId() or "")
    local applySkinId = 0
    for baseMapId, targetSkin in pairs(_G.VehicleSkinMap) do
      if defId:find(tostring(baseMapId)) or currentId:find(tostring(baseMapId)) then
        applySkinId = targetSkin
        break
      end
    end
    if applySkinId and 0 < applySkinId then
      _G.skinIdCache = _G.skinIdCache or {}
      if not _G.skinIdCache[applySkinId] then
        if _G.download_item then
          pcall(_G.download_item, applySkinId)
        end
        _G.skinIdCache[applySkinId] = true
      end
      VehicleAvatar.curSwitchEffectId = 7303001
      if VehicleAvatar.ChangeItemAvatar then
        VehicleAvatar:ChangeItemAvatar(applySkinId, true)
      end
      _G.CurrentEquipVehicleID = applySkinId
      _G.LastVehicleEntity = Vehicle
    end
  end)
end

function _G.HandlePetLogic()
  pcall(function()
    local petSkin = _G.OutfitMap.Pet
    if not petSkin or petSkin == 0 or petSkin == 50000 or petSkin == _G.LastAppliedPet then
      return
    end
    _G.skinIdCache = _G.skinIdCache or {}
    if not _G.skinIdCache[petSkin] then
      if _G.download_item then
        pcall(_G.download_item, petSkin)
      end
      _G.skinIdCache[petSkin] = true
    end
    local ModuleManager = require("client.module_framework.ModuleManager")
    if ModuleManager then
      local logic_pet = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.logic_pet)
      if logic_pet then
        if logic_pet.SetCurPetID then
          logic_pet:SetCurPetID(petSkin)
        end
        if logic_pet.EquipPet then
          logic_pet:EquipPet(petSkin)
        end
      end
    end
    _G.LastAppliedPet = petSkin
  end)
end

function _G.ForceRefreshSkinMaps()
  pcall(function()
    if not _G.LexusState or not _G.LexusState.CustomTextData then
      return
    end
    local cData = _G.LexusState.CustomTextData
    if _G.OutfitSkins then
      if cData.SkinSuit and _G.OutfitSkins.Suit[cData.SkinSuit] then
        _G.OutfitMap.Suit = _G.OutfitSkins.Suit[cData.SkinSuit]
      end
      if cData.SkinBag and _G.OutfitSkins.Bag[cData.SkinBag] then
        _G.OutfitMap.Bag = _G.OutfitSkins.Bag[cData.SkinBag]
      end
      if cData.SkinHelmet and _G.OutfitSkins.Helmet[cData.SkinHelmet] then
        _G.OutfitMap.Helmet = _G.OutfitSkins.Helmet[cData.SkinHelmet]
      end
    end
    if _G.skinIdMappings then
      if cData.SkinM416 and _G.skinIdMappings[101004] and _G.skinIdMappings[101004][cData.SkinM416] then
        _G.WeaponSkinMap[101004] = _G.skinIdMappings[101004][cData.SkinM416]
      end
      if cData.SkinAKM and _G.skinIdMappings[101001] and _G.skinIdMappings[101001][cData.SkinAKM] then
        _G.WeaponSkinMap[101001] = _G.skinIdMappings[101001][cData.SkinAKM]
      end
      if cData.SkinSCAR and _G.skinIdMappings[101003] and _G.skinIdMappings[101003][cData.SkinSCAR] then
        _G.WeaponSkinMap[101003] = _G.skinIdMappings[101003][cData.SkinSCAR]
      end
      if cData.SkinM762 and _G.skinIdMappings[101008] and _G.skinIdMappings[101008][cData.SkinM762] then
        _G.WeaponSkinMap[101008] = _G.skinIdMappings[101008][cData.SkinM762]
      end
      if cData.SkinAUG and _G.skinIdMappings[101006] and _G.skinIdMappings[101006][cData.SkinAUG] then
        _G.WeaponSkinMap[101006] = _G.skinIdMappings[101006][cData.SkinAUG]
      end
      if cData.SkinUMP and _G.skinIdMappings[102002] and _G.skinIdMappings[102002][cData.SkinUMP] then
        _G.WeaponSkinMap[102002] = _G.skinIdMappings[102002][cData.SkinUMP]
      end
      if cData.SkinUZI and _G.skinIdMappings[102001] and _G.skinIdMappings[102001][cData.SkinUZI] then
        _G.WeaponSkinMap[102001] = _G.skinIdMappings[102001][cData.SkinUZI]
      end
      if cData.SkinGroza and _G.skinIdMappings[101005] and _G.skinIdMappings[101005][cData.SkinGroza] then
        _G.WeaponSkinMap[101005] = _G.skinIdMappings[101005][cData.SkinGroza]
      end
      if cData.SkinS12K and _G.skinIdMappings[104003] and _G.skinIdMappings[104003][cData.SkinS12K] then
        _G.WeaponSkinMap[104003] = _G.skinIdMappings[104003][cData.SkinS12K]
      end
      if cData.SkinDBS and _G.skinIdMappings[104004] and _G.skinIdMappings[104004][cData.SkinDBS] then
        _G.WeaponSkinMap[104004] = _G.skinIdMappings[104004][cData.SkinDBS]
      end
      if cData.SkinASM and _G.skinIdMappings[101101] and _G.skinIdMappings[101101][cData.SkinASM] then
        _G.WeaponSkinMap[101101] = _G.skinIdMappings[101101][cData.SkinASM]
      end
    end
    if _G.VehicleSkins then
      if cData.SkinDacia and _G.VehicleSkins[1903001] and _G.VehicleSkins[1903001][cData.SkinDacia] then
        _G.VehicleSkinMap[1903001] = _G.VehicleSkins[1903001][cData.SkinDacia]
      end
      if cData.SkinUAZ and _G.VehicleSkins[1908001] and _G.VehicleSkins[1908001][cData.SkinUAZ] then
        _G.VehicleSkinMap[1908001] = _G.VehicleSkins[1908001][cData.SkinUAZ]
      end
      if cData.SkinCoupe and _G.VehicleSkins[1961001] and _G.VehicleSkins[1961001][cData.SkinCoupe] then
        _G.VehicleSkinMap[1961001] = _G.VehicleSkins[1961001][cData.SkinCoupe]
      end
      if cData.SkinBuggy and _G.VehicleSkins[1907002] and _G.VehicleSkins[1907002][cData.SkinBuggy] then
        _G.VehicleSkinMap[1907002] = _G.VehicleSkins[1907002][cData.SkinBuggy]
      end
      if cData.SkinMirado and _G.VehicleSkins[1915004] and _G.VehicleSkins[1915004][cData.SkinMirado] then
        _G.VehicleSkinMap[1915004] = _G.VehicleSkins[1915004][cData.SkinMirado]
      end
      if cData.SkinQBZ and _G.skinIdMappings[101007] and _G.skinIdMappings[101007][cData.SkinQBZ] then
        _G.WeaponSkinMap[101007] = _G.skinIdMappings[101007][cData.SkinQBZ]
      end
      if cData.SkinHoney and _G.skinIdMappings[101012] and _G.skinIdMappings[101012][cData.SkinHoney] then
        _G.WeaponSkinMap[101012] = _G.skinIdMappings[101012][cData.SkinHoney]
      end
      if cData.SkinM16A4 and _G.skinIdMappings[101002] and _G.skinIdMappings[101002][cData.SkinM16A4] then
        _G.WeaponSkinMap[101002] = _G.skinIdMappings[101002][cData.SkinM16A4]
      end
      if cData.SkinACE32 and _G.skinIdMappings[101102] and _G.skinIdMappings[101102][cData.SkinACE32] then
        _G.WeaponSkinMap[101102] = _G.skinIdMappings[101102][cData.SkinACE32]
      end
      if cData.SkinKar98k and _G.skinIdMappings[103001] and _G.skinIdMappings[103001][cData.SkinKar98k] then
        _G.WeaponSkinMap[103001] = _G.skinIdMappings[103001][cData.SkinKar98k]
      end
      if cData.SkinM24 and _G.skinIdMappings[103002] and _G.skinIdMappings[103002][cData.SkinM24] then
        _G.WeaponSkinMap[103002] = _G.skinIdMappings[103002][cData.SkinM24]
      end
      if cData.SkinAWM and _G.skinIdMappings[103003] and _G.skinIdMappings[103003][cData.SkinAWM] then
        _G.WeaponSkinMap[103003] = _G.skinIdMappings[103003][cData.SkinAWM]
      end
    end
  end)
end

local cached_GameplayStatics, cached_PlayerTombBox, cached_ActorClass
_G.NeedCheckDeadBoxTimer = 100

function _G.DeadBox_TemperRequest(PlayerController)
  if not _G.LexusConfig.SkinDeadBox then
    return
  end
  if _G.NeedCheckDeadBoxTimer <= 0 then
    return
  end
  local curTime = os.clock()
  if _G.LastCheckDeadBoxTime and curTime - _G.LastCheckDeadBoxTime < 2.0 then
    return
  end
  _G.LastCheckDeadBoxTime = curTime
  _G.NeedCheckDeadBoxTimer = _G.NeedCheckDeadBoxTimer - 1
  local PlayerCharacter = PlayerController:GetPlayerCharacterSafety()
  if not slua.isValid(PlayerCharacter) then
    return
  end
  if not cached_GameplayStatics then
    cached_GameplayStatics = import("GameplayStatics")
    cached_ActorClass = import("Actor")
    cached_PlayerTombBox = import("PlayerTombBox")
  end
  if not _G.CachedActorArray then
    _G.CachedActorArray = slua.Array(UEnums.EPropertyClass.Object, cached_ActorClass)
  end
  local UI_Util = require("client.common.ui_util")
  local GameInstance = UI_Util and UI_Util.GetGameInstance()
  if not GameInstance or not cached_GameplayStatics then
    return
  end
  local deadBoxes = cached_GameplayStatics.GetAllActorsOfClass(GameInstance, cached_PlayerTombBox, _G.CachedActorArray)
  for _, deadBoxActor in pairs(deadBoxes) do
    if slua.isValid(deadBoxActor) and not deadBoxActor.bIsTDSkinApplied then
      local damageCauser = deadBoxActor.DamageCauser
      if damageCauser and damageCauser.PlayerKey == PlayerController.PlayerKey then
        local DeadBoxAvatarComponent = deadBoxActor.DeadBoxAvatarComponent_BP
        if slua.isValid(DeadBoxAvatarComponent) then
          do
            local currentBoxSkinId = 0
            if PlayerCharacter.CurrentVehicle and _G.CurrentEquipVehicleID and _G.CurrentEquipVehicleID ~= 0 then
              currentBoxSkinId = tonumber(tostring(_G.CurrentEquipVehicleID) .. "1") or 0
            else
              local currentWeapon = PlayerCharacter:GetCurrentWeapon()
              if slua.isValid(currentWeapon) and currentWeapon.synData then
                local weaponSkinData = currentWeapon.synData:Get(7)
                if weaponSkinData and weaponSkinData.defineID then
                  currentBoxSkinId = weaponSkinData.defineID.TypeSpecificID
                end
              end
            end
            if currentBoxSkinId ~= 0 then
              pcall(function()
                DeadBoxAvatarComponent:ResetItemAvatar()
                DeadBoxAvatarComponent:PreChangeItemAvatar(currentBoxSkinId)
                DeadBoxAvatarComponent:SyncChangeItemAvatar(currentBoxSkinId)
              end)
            end
            deadBoxActor.bIsTDSkinApplied = true
          end
        end
      end
    end
  end
end

_G.TDFTDeKillCounts = _G.TDFTDeKillCounts or {}
local CACHED_LinearColor = import("LinearColor")
local CACHED_GoldColor = CACHED_LinearColor and CACHED_LinearColor(1.0, 0.0, 0.0, 1.0) or nil
local CACHED_UI_Manager

function _G.ForceEnableKillCounterUI()
  pcall(function()
    local KillCounterUISubsystem = package.loaded["GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem"] or require("GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem")
    if KillCounterUISubsystem and KillCounterUISubsystem.__inner_impl and not _G.KCUISystemHacked2 then
      local kcImpl = KillCounterUISubsystem.__inner_impl
      
      function kcImpl.CheckSupportKCUI()
        return true
      end
      
      function kcImpl:CheckNeedMainKillCounterUI(PlayerWeapon, PlayerID)
        if slua.isValid(PlayerWeapon) then
          local WeaponID = PlayerWeapon:GetWeaponID()
          self:UpdateMainKillCounterUI(true, WeaponID, _G.get_skin_id(WeaponID) or WeaponID)
        else
          self:UpdateMainKillCounterUI(false)
        end
      end
      
      local originalUpdateMainKillCounterUI = kcImpl.UpdateMainKillCounterUI
      
      function kcImpl:UpdateMainKillCounterUI(bShow, WeaponID, AvatarID)
        AvatarID = bShow and _G.get_skin_id(WeaponID) or AvatarID
        if originalUpdateMainKillCounterUI then
          originalUpdateMainKillCounterUI(self, bShow, WeaponID, AvatarID)
        end
      end
      
      _G.KCUISystemHacked2 = true
    end
    local ModuleManager = require("client.module_framework.ModuleManager")
    if ModuleManager and not _G.KCLogicHacked2 then
      local LogicKillCounter = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.LogicKillCounter)
      if LogicKillCounter then
        function LogicKillCounter.CheckSupportKC()
          return true
        end
        
        function LogicKillCounter.CheckSupportKillCounterAvatar()
          return true
        end
        
        function LogicKillCounter.CheckHasWeaponKillCounter()
          return true
        end
        
        function LogicKillCounter.GetBaseKillCounterIdByWeaponId()
          return 2100004
        end
        
        function LogicKillCounter.GetEquipedKillCounterId()
          return 2100004
        end
        
        function LogicKillCounter.GetMyEquipedKillCounterId()
          return 2100004
        end
        
        function LogicKillCounter:GetOneWeaponKillCountInBattle(uid, weaponId)
          return _G.TDFTDeKillCounts[weaponId] or 0
        end
        
        function LogicKillCounter:GetWeaponKillCountByUid(uid, weaponId)
          return _G.TDFTDeKillCounts[weaponId] or 0
        end
        
        _G.KCLogicHacked2 = true
      end
    end
    local killInfoPath = "GameLua.Mod.BaseMod.Client.KillInfoTips.KillInfo"
    local KillInfo = package.loaded[killInfoPath] or require(killInfoPath)
    if KillInfo and KillInfo.__inner_impl and not _G.KillInfoCounterHacked then
      local originalFileItem = KillInfo.__inner_impl.FileItem
      
      function KillInfo.__inner_impl:FileItem(DamageRecordData)
        pcall(function()
          local LocalPlayer = require("GameLua.GameCore.Data.GameplayData").GetPlayerCharacter()
          if slua.isValid(LocalPlayer) and DamageRecordData.Causer == LocalPlayer:GetPlayerNameSafety() then
            local currentWeapon = LocalPlayer:GetCurrentWeapon()
            if slua.isValid(currentWeapon) then
              local weaponID = currentWeapon:GetWeaponID()
              local skinID = _G.get_skin_id(weaponID)
              if skinID then
                DamageRecordData.CauserWeaponAvatarID = skinID
              end
              if _G.OutfitMap.Suit and _G.OutfitMap.Suit ~= 0 then
                DamageRecordData.CauserClothAvatarID = _G.OutfitMap.Suit
              end
              if CACHED_GoldColor then
                DamageRecordData.IsUseColor, DamageRecordData.UseColor = true, CACHED_GoldColor
              end
              if DamageRecordData.ResultHealthStatus == 2 then
                _G.TDFTDeKillCounts[weaponID] = (_G.TDFTDeKillCounts[weaponID] or 0) + 1
                _G.NeedCheckDeadBoxTimer = 50
                if not CACHED_UI_Manager then
                  CACHED_UI_Manager = require("client.slua_ui_framework.manager")
                end
                local uiMainKillCounter = CACHED_UI_Manager.GetUI(CACHED_UI_Manager.UI_Config_InGame.MainKillCounter)
                if uiMainKillCounter and uiMainKillCounter.UpdateWeaponID then
                  local mainAvatarID = skinID or currentWeapon:GetWeaponMainAvatarID()
                  uiMainKillCounter:UpdateWeaponID(weaponID, mainAvatarID)
                  local kcModule = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.LogicKillCounter)
                  local kcItemID = kcModule:GetEquipedKillCounterId(0, mainAvatarID)
                  uiMainKillCounter:SetKillCounterItemShowWithNum(kcItemID, _G.TDFTDeKillCounts[weaponID], mainAvatarID)
                end
              end
            end
          end
        end)
        if originalFileItem then
          return originalFileItem(self, DamageRecordData)
        end
      end
      
      _G.KillInfoCounterHacked = true
    end
    local SwitchWeaponSlotMode2 = package.loaded["GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotMode2"] or require("GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotMode2")
    if SwitchWeaponSlotMode2 and SwitchWeaponSlotMode2.__inner_impl and not _G.SlotBaseHacked then
      function SwitchWeaponSlotMode2.__inner_impl:CheckShowKCIcon()
        if slua.isValid(self.KillCounterImg) then
          self.KillCounterImg:SetVisibility(import("ESlateVisibility").SelfHitTestInvisible)
        end
      end
      
      _G.SlotBaseHacked = true
    end
  end)
end

function _G.InitializeSkinModSystem()
  pcall(function()
    local LobbyAvatar = package.loaded["client.logic.avatar.LobbyAvatar"] or require("client.logic.avatar.LobbyAvatar")
    if LobbyAvatar and not _G.LobbyBypassHacked then
      local originalPutonEquipment = LobbyAvatar.PutonEquipment
      
      function LobbyAvatar:PutonEquipment(itemID, tAvatarCustom, tExtraData)
        local attachIndex = _G.BaseAttachToIndex and _G.BaseAttachToIndex[itemID]
        if attachIndex then
          local holdingWeaponSkinID = self.GetCurHoldingWeaponSkinID and self:GetCurHoldingWeaponSkinID()
          if holdingWeaponSkinID and 10000000 <= holdingWeaponSkinID and _G.VIP_Attachments and _G.VIP_Attachments[holdingWeaponSkinID] then
            local vipAttachID = _G.VIP_Attachments[holdingWeaponSkinID][attachIndex]
            if vipAttachID and 0 < vipAttachID then
              if self.HandleDownload then
                self:HandleDownload(vipAttachID, nil, nil, false)
              end
              itemID = vipAttachID
            end
          end
        end
        if originalPutonEquipment then
          return originalPutonEquipment(self, itemID, tAvatarCustom, tExtraData)
        end
      end
      
      local originalCharEquipWeaponByResId = LobbyAvatar.CharEquipWeaponByResId
      
      function LobbyAvatar:CharEquipWeaponByResId(resID, isUse, isAsync, SocketName)
        local retValue = originalCharEquipWeaponByResId and originalCharEquipWeaponByResId(self, resID, isUse, isAsync, SocketName) or nil
        if isUse and self.GetEquipments then
          local equipments = self:GetEquipments()
          for _, equip in ipairs(equipments) do
            if _G.BaseAttachToIndex and _G.BaseAttachToIndex[equip.itemID] then
              self:PutonEquipment(equip.itemID, equip.CustomInfo, {bIsUse = false})
            end
          end
        end
        return retValue
      end
      
      _G.LobbyBypassHacked = true
    end
  end)
  pcall(function()
    local Common_Items_UIBP = package.loaded["client.slua.component.item.ItemChildren.Common_Items_UIBP"] or require("client.slua.component.item.ItemChildren.Common_Items_UIBP")
    if Common_Items_UIBP and not _G.IconBaloHacked then
      local originalInitView = Common_Items_UIBP.InitView
      
      function Common_Items_UIBP:InitView(nItemId, nCount, nValidTime, tExtraData)
        tExtraData = tExtraData or {}
        local displayResId
        if _G.get_skin_id then
          local skinID = _G.get_skin_id(nItemId)
          if skinID and skinID ~= nItemId then
            displayResId = skinID
          end
        end
        local attachIndex = _G.BaseAttachToIndex and _G.BaseAttachToIndex[nItemId]
        if not displayResId and attachIndex then
          local GameplayData = require("GameLua.GameCore.Data.GameplayData")
          local LocalPlayer = GameplayData and GameplayData.GetPlayerCharacter()
          if slua.isValid(LocalPlayer) then
            local currentWeapon = LocalPlayer:GetCurrentWeapon()
            if slua.isValid(currentWeapon) then
              local weaponID = currentWeapon:GetWeaponID()
              local finalSkinID = _G.get_skin_id(weaponID) or weaponID
              if 10000000 <= finalSkinID and _G.VIP_Attachments and _G.VIP_Attachments[finalSkinID] then
                local vipAttachID = _G.VIP_Attachments[finalSkinID][attachIndex]
                if vipAttachID and 0 < vipAttachID then
                  displayResId = vipAttachID
                end
              end
            end
          end
        end
        if displayResId then
          tExtraData.displayResId = displayResId
          if not _G.skinIdCache2[displayResId] then
            if _G.download_item then
              pcall(_G.download_item, displayResId)
            end
            _G.skinIdCache2[displayResId] = true
          end
        end
        if originalInitView then
          return originalInitView(self, nItemId, nCount, nValidTime, tExtraData)
        end
      end
      
      _G.IconBaloHacked = true
    end
  end)
end

function _G.GetOriginalHWID()
  if _G.Original_GetDeviceId then
    return tostring(_G.Original_GetDeviceId())
  end
  local SystemLib = import("KismetSystemLibrary")
  if SystemLib and type(SystemLib.GetDeviceId) == "function" then
    return tostring(SystemLib.GetDeviceId())
  end
  return "UNKNOWN_DEVICE"
end

local function ApplyColorBodyNew(enemy, markData)
  pcall(function()
    if not _G.ConsoleNewWallReady then
      local KismetSystemLibrary = import("KismetSystemLibrary")
      local world = slua.getWorld()
      if KismetSystemLibrary and world then
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
        _G.ConsoleNewWallReady = true
      end
    end
    local meshes = GetAllSkeletalMeshes(enemy, markData)
    local weapon
    pcall(function()
      weapon = enemy:GetCurrentWeapon()
    end)
    if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
      table.insert(meshes, weapon.Mesh)
    end
    local isBot = markData.AK_IS_BOT or false
    local currentMeshCount = #meshes
    local stateHash = (isBot and "BOT" or "PLAYER") .. "_" .. tostring(currentMeshCount)
    if markData.LastColorNewHash == stateHash and markData.ColorNewApplied then
      return
    end
    markData.LastColorNewHash = stateHash
    markData.ColorNewApplied = true
    local LC = getCachedLinearColor()
    local c_vis = LC and LC(0, 255, 0, 1) or {
      R = 0,
      G = 255,
      B = 0,
      A = 1
    }
    local c_occ = LC and LC(255, 0, 255, 1) or {
      R = 255,
      G = 0,
      B = 255,
      A = 1
    }
    local c_bVis = LC and LC(0, 255, 0, 1) or {
      R = 0,
      G = 255,
      B = 0,
      A = 1
    }
    local c_bOcc = LC and LC(255, 0, 255, 1) or {
      R = 255,
      G = 0,
      B = 255,
      A = 1
    }
    local visColor = isBot and c_bVis or c_vis
    local occColor = isBot and c_bOcc or c_occ
    for _, mesh in ipairs(meshes) do
      if Valid(mesh) then
        pcall(function()
          if type(mesh.SetDrawDyeing) == "function" then
            mesh:SetDrawDyeing(true)
            mesh:SetDrawDyeingMode(1)
            mesh:SetVisibleDyeingColor(visColor)
            mesh:SetOccludedDyeingColor(occColor)
            mesh:SetDyeingColorFadeDistance(99999.0)
            mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
            mesh:SetDrawHighlight(true)
            mesh:OverrideHighlightColor(visColor)
            mesh:SetHighlightCanBeOccluded(false)
            mesh:SetDrawIdeaOutline(true)
            mesh:SetIdeaOutlineNew(true)
            mesh:SetIdeaOutlineOcclusionHighlight(true)
            mesh:OverrideIdeaOutlineColor(visColor)
            mesh:SetIdeaOutlineOcclusionColor(occColor)
            mesh:OverrideIdeaOutlineThickness(20.0)
            mesh:SetIdeaOverrideOutlineAndOcclusion(true)
            mesh:SetRenderCustomDepth(true)
            mesh:SetCustomDepthStencilValue(255)
          end
        end)
      end
    end
  end)
end

local function UndoColorBodyNew(enemy, markData)
  pcall(function()
    if markData.ColorNewApplied then
      local meshes = GetAllSkeletalMeshes(enemy, markData)
      local weapon
      pcall(function()
        weapon = enemy:GetCurrentWeapon()
      end)
      if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
        table.insert(meshes, weapon.Mesh)
      end
      for _, mesh in ipairs(meshes) do
        if Valid(mesh) then
          pcall(function()
            if type(mesh.SetDrawDyeing) == "function" then
              mesh:SetDrawDyeing(false)
              mesh:SetDrawHighlight(false)
              mesh:SetDrawIdeaOutline(false)
              mesh:SetRenderCustomDepth(false)
            end
          end)
        end
      end
      markData.ColorNewApplied = false
      markData.LastColorNewHash = ""
    end
  end)
end

local TelegramOverlay = {
  MainContainer = nil,
  TextBlock = nil,
  WidgetSlot = nil
}

function TelegramOverlay.Create()
  if TelegramOverlay.MainContainer and slua.isValid(TelegramOverlay.MainContainer) then
    return true
  end
  local ParentCanvas = PlayerMapMarker.ESPCanvas
  if not ParentCanvas or not slua.isValid(ParentCanvas) then
    if not PlayerMapMarker.InitESPCanvas then
      return false
    end
    if not PlayerMapMarker.InitESPCanvas() then
      return false
    end
    ParentCanvas = PlayerMapMarker.ESPCanvas
  end
  if not ParentCanvas or not slua.isValid(ParentCanvas) then
    return false
  end
  local txt
  pcall(function()
    txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", ParentCanvas)
  end)
  if not txt or not slua.isValid(txt) then
    return false
  end
  local FLinearColor = import("LinearColor") or _G.FLinearColor
  local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
  local FAnchors = import("Anchors") or import("/Script/SlateCore.Anchors")
  local FVector2D = import("Vector2D") or _G.FVector2D
  local greenColor = FLinearColor(1.0, 1.0, 0.0, 1.0)
  pcall(function()
    txt:SetText("Developer -> @OwnerMOHSINXFILES")
    if FSlateColor then
      txt:SetColorAndOpacity(FSlateColor(greenColor))
    else
      txt:SetColorAndOpacity(greenColor)
    end
    if txt.Font then
      local font = txt.Font
      font.Size = 18
      txt:SetFont(font)
    end
    txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  local MainSlot = ParentCanvas:AddChildToCanvas(txt)
  if not MainSlot then
    return false
  end
  pcall(function()
    MainSlot:SetAutoSize(true)
    MainSlot:SetZOrder(15000)
    local Anchors = import("Anchors") or import("/Script/SlateCore.Anchors") or import("SlateCore.Anchors")
    if Anchors and type(Anchors) == "function" then
      local ok, a = pcall(function()
        return Anchors(0, 0, 0, 0)
      end)
      if ok and a then
        MainSlot:SetAnchors(a)
      end
    end
    MainSlot:SetAlignment(FVector2D(0, 0))
    MainSlot:SetPosition(FVector2D(15, 300))
    local Margin = import("Margin") or import("/Script/SlateCore.Margin") or import("SlateCore.Margin")
    if Margin and type(Margin) == "function" then
      pcall(function()
        MainSlot:SetOffsets(Margin(15, 300, 0, 0))
      end)
    end
  end)
  TelegramOverlay.MainContainer = txt
  TelegramOverlay.TextBlock = txt
  TelegramOverlay.WidgetSlot = MainSlot
  return true
end

_G.TelegramOverlay = TelegramOverlay
local PlayerMapMarker = {}
local RedBoxOverlay = {
  bActive = false,
  MainContainer = nil,
  WidgetSlot = nil,
  RealTextBlock = nil,
  BotTextBlock = nil,
  Width = 138,
  Height = 24,
  PlayerCount = 0,
  BotCount = 0,
  FontSize = 12,
  _CachedRealText = "",
  _CachedBotText = "",
  _CachedPosVec = nil
}

function RedBoxOverlay.Create()
  if RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then
    return true
  end
  local ParentCanvas = PlayerMapMarker.ESPCanvas
  if not ParentCanvas or not slua.isValid(ParentCanvas) then
    if not PlayerMapMarker.InitESPCanvas() then
      return false
    end
    ParentCanvas = PlayerMapMarker.ESPCanvas
  end
  if not ParentCanvas or not slua.isValid(ParentCanvas) then
    return false
  end
  local Container
  pcall(function()
    Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas)
  end)
  if not Container or not slua.isValid(Container) then
    return false
  end
  local FLinearColor = import("LinearColor") or _ENV.FLinearColor
  local FVector2D = import("Vector2D") or _ENV.FVector2D
  local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
  local FAnchors = import("Anchors") or import("/Script/SlateCore.Anchors")
  local badgeW = 68
  local badgeH = 24
  local realBorder
  pcall(function()
    realBorder = CGame:NewObjectFromPath("/Script/UMG.Border", Container)
  end)
  if realBorder and slua.isValid(realBorder) then
    pcall(function()
      realBorder:SetBrushColor(FLinearColor(0.85, 0.12, 0.12, 0.95))
      realBorder:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
    local slotReal = Container:AddChildToCanvas(realBorder)
    if slotReal then
      slotReal:SetPosition(FVector2D(0, 0))
      slotReal:SetSize(FVector2D(badgeW, badgeH))
    end
    local realTxt
    pcall(function()
      realTxt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container)
    end)
    if realTxt and slua.isValid(realTxt) then
      pcall(function()
        local strReal = string.format("REAL %d", RedBoxOverlay.PlayerCount or 0)
        realTxt:SetText(strReal)
        RedBoxOverlay._CachedRealText = strReal
        local whiteColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
        if FSlateColor then
          realTxt:SetColorAndOpacity(FSlateColor(whiteColor))
        else
          realTxt:SetColorAndOpacity(whiteColor)
        end
        if realTxt.Font then
          local font = realTxt.Font
          font.Size = RedBoxOverlay.FontSize
          realTxt.Font = font
        end
        realTxt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
      do
        local txtSlot = Container:AddChildToCanvas(realTxt)
        if txtSlot then
          pcall(function()
            txtSlot:SetAutoSize(true)
            txtSlot:SetAlignment(FVector2D(0.5, 0.5))
            txtSlot:SetPosition(FVector2D(badgeW * 0.5, badgeH * 0.5))
            txtSlot:SetZOrder(1000)
          end)
        end
        RedBoxOverlay.RealTextBlock = realTxt
      end
    end
  end
  local botBorder
  pcall(function()
    botBorder = CGame:NewObjectFromPath("/Script/UMG.Border", Container)
  end)
  if botBorder and slua.isValid(botBorder) then
    pcall(function()
      botBorder:SetBrushColor(FLinearColor(0.12, 0.75, 0.25, 0.95))
      botBorder:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
    local slotBot = Container:AddChildToCanvas(botBorder)
    if slotBot then
      slotBot:SetPosition(FVector2D(badgeW + 2, 0))
      slotBot:SetSize(FVector2D(badgeW, badgeH))
    end
    local botTxt
    pcall(function()
      botTxt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container)
    end)
    if botTxt and slua.isValid(botTxt) then
      pcall(function()
        local strBot = string.format("BOT %d", RedBoxOverlay.BotCount or 0)
        botTxt:SetText(strBot)
        RedBoxOverlay._CachedBotText = strBot
        local whiteColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
        if FSlateColor then
          botTxt:SetColorAndOpacity(FSlateColor(whiteColor))
        else
          botTxt:SetColorAndOpacity(whiteColor)
        end
        if botTxt.Font then
          local font = botTxt.Font
          font.Size = RedBoxOverlay.FontSize
          botTxt.Font = font
        end
        botTxt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
      do
        local txtSlot = Container:AddChildToCanvas(botTxt)
        if txtSlot then
          pcall(function()
            txtSlot:SetAutoSize(true)
            txtSlot:SetAlignment(FVector2D(0.5, 0.5))
            txtSlot:SetPosition(FVector2D(badgeW * 1.5 + 2, badgeH * 0.5))
            txtSlot:SetZOrder(1000)
          end)
        end
        RedBoxOverlay.BotTextBlock = botTxt
      end
    end
  end
  local totalWidth = badgeW * 2 + 2
  local MainSlot
  pcall(function()
    MainSlot = ParentCanvas:AddChildToCanvas(Container)
  end)
  if not MainSlot then
    return false
  end
  RedBoxOverlay.MainContainer = Container
  RedBoxOverlay.WidgetSlot = MainSlot
  RedBoxOverlay.Width = totalWidth
  pcall(function()
    MainSlot:SetAutoSize(false)
    MainSlot:SetZOrder(999)
    if FAnchors then
      MainSlot:SetAnchors(FAnchors(0.0, 0.0, 0.0, 0.0))
    end
    MainSlot:SetAlignment(FVector2D(0.0, 0.0))
    MainSlot:SetSize(FVector2D(totalWidth, badgeH))
  end)
  RedBoxOverlay.UpdatePosition()
  return true
end

function RedBoxOverlay.SetCounts(players, bots)
  if RedBoxOverlay.PlayerCount == players and RedBoxOverlay.BotCount == bots then
    return
  end
  RedBoxOverlay.PlayerCount = players or 0
  RedBoxOverlay.BotCount = bots or 0
  pcall(function()
    if RedBoxOverlay.RealTextBlock and slua.isValid(RedBoxOverlay.RealTextBlock) then
      local strReal = string.format("REAL %d", RedBoxOverlay.PlayerCount)
      if RedBoxOverlay._CachedRealText ~= strReal then
        RedBoxOverlay.RealTextBlock:SetText(strReal)
        RedBoxOverlay._CachedRealText = strReal
      end
    end
    if RedBoxOverlay.BotTextBlock and slua.isValid(RedBoxOverlay.BotTextBlock) then
      local strBot = string.format("BOT %d", RedBoxOverlay.BotCount)
      if RedBoxOverlay._CachedBotText ~= strBot then
        RedBoxOverlay.BotTextBlock:SetText(strBot)
        RedBoxOverlay._CachedBotText = strBot
      end
    end
  end)
end

function RedBoxOverlay.UpdatePosition()
  local Slot = RedBoxOverlay.WidgetSlot
  local Container = RedBoxOverlay.MainContainer
  if not Slot or not slua.isValid(Slot) then
    return
  end
  if not Container or not slua.isValid(Container) then
    return
  end
  local canvasW
  if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
    pcall(function()
      local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
      if cg and cg.GetLocalSize then
        local sz = cg:GetLocalSize()
        if sz and sz.X and sz.X > 200 then
          canvasW = sz.X
        end
      end
    end)
  end
  if not canvasW then
    local PC = PlayerMapMarker.GetMyPlayerController()
    if slua.isValid(PC) and PC.GetViewportSize then
      do
        local VS = FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
        pcall(function()
          PC:GetViewportSize(VS)
        end)
        if VS and VS.X and VS.X > 200 then
          canvasW = VS.X
        end
      end
    end
  end
  if not canvasW and PlayerMapMarker._cachedViewportW then
    canvasW = PlayerMapMarker._cachedViewportW
  end
  if not canvasW or canvasW < 200 then
    canvasW = 1920
  end
  local realW = RedBoxOverlay.Width or 138
  pcall(function()
    local cg = Container:GetCachedGeometry()
    if cg and cg.GetLocalSize then
      local sz = cg:GetLocalSize()
      if sz and sz.X and sz.X > 10 then
        realW = sz.X
      end
    end
  end)
  local targetX = canvasW * 0.5 - realW * 0.5 - 304
  local targetY = 25
  local FVector2D = import("Vector2D") or _G.FVector2D
  pcall(function()
    if not RedBoxOverlay._CachedPosVec then
      RedBoxOverlay._CachedPosVec = FVector2D and FVector2D(targetX, targetY) or {X = targetX, Y = targetY}
    else
      RedBoxOverlay._CachedPosVec.X = targetX
      RedBoxOverlay._CachedPosVec.Y = targetY
    end
    Slot:SetPosition(RedBoxOverlay._CachedPosVec)
    Slot:SetSize(FVector2D and FVector2D(realW, RedBoxOverlay.Height or 24) or {
      X = realW,
      Y = RedBoxOverlay.Height or 24
    })
  end)
end

function RedBoxOverlay.Start()
  if RedBoxOverlay.bActive and RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then
    return
  end
  if RedBoxOverlay.Create() then
    RedBoxOverlay.bActive = true
    RedBoxOverlay.UpdatePosition()
    pcall(function()
      RedBoxOverlay.MainContainer:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
  end
end

function RedBoxOverlay.Stop()
  RedBoxOverlay.bActive = false
  if RedBoxOverlay.MainContainer and slua.isValid(RedBoxOverlay.MainContainer) then
    pcall(function()
      RedBoxOverlay.MainContainer:RemoveFromParent()
      RedBoxOverlay.MainContainer:ConditionalBeginDestroy()
    end)
  end
  RedBoxOverlay.MainContainer = nil
  RedBoxOverlay.WidgetSlot = nil
  RedBoxOverlay.RealTextBlock = nil
  RedBoxOverlay.BotTextBlock = nil
  RedBoxOverlay._CachedPosVec = nil
end

_G.RedBoxOverlay = RedBoxOverlay
local SlateBlueprintLibrary, WidgetLayoutLibrary, KismetMathLibrary, KismetSystemLibrary
pcall(function()
  SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary")
end)
pcall(function()
  WidgetLayoutLibrary = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary")
end)
pcall(function()
  KismetMathLibrary = import("KismetMathLibrary")
end)
pcall(function()
  KismetSystemLibrary = import("KismetSystemLibrary")
end)
local FVector2D = _G.FVector2D or import("Vector2D")
local FLinearColor = _G.FLinearColor or import("LinearColor")
local FVector = _G.FVector or import("Vector")
PlayerMapMarker.MarkTypeID = 1007
PlayerMapMarker.bUseScreenESP = true
PlayerMapMarker.bUseScreenMark = false
PlayerMapMarker.bUseQuickSign = false
PlayerMapMarker.bUseNavigator = false
PlayerMapMarker.bUseWidgetComponent = false
PlayerMapMarker.QuickSignConfigKey = "C_MarkPos"
PlayerMapMarker.WidgetCompUIPath = "/Game/BluePrints/ControlInput/NewbieItem/NewbieTips_ConsumeTips.NewbieTips_ConsumeTips"
PlayerMapMarker.WidgetCompBoneName = "head"
PlayerMapMarker.WidgetCompOffset = FVector and FVector(0, 0, 80) or {
  X = 0,
  Y = 0,
  Z = 80
}
PlayerMapMarker.WidgetCompDrawSize = FVector2D and FVector2D(210, 35) or {X = 210, Y = 35}
PlayerMapMarker.ESPBoneName = "head"
PlayerMapMarker.ESPWorldOffsetZ = 0
PlayerMapMarker.ESPScreenOffsetY = 0
PlayerMapMarker.ESPAnchorOffsetX = 35
PlayerMapMarker.ESPAnchorOffsetY = 0
PlayerMapMarker.ESPTextOffsetX = 0
PlayerMapMarker.ESPTextOffsetY = 0
PlayerMapMarker.ESPWidgetAlignment = FVector2D and FVector2D(0.5, 1.0) or {X = 0.5, Y = 1.0}
PlayerMapMarker.ESPWidgetSize = FVector2D and FVector2D(70, 21) or {X = 70, Y = 21}
PlayerMapMarker.ESPWidgetAutoSize = true
PlayerMapMarker.ESPWidgetZOrder = 2
PlayerMapMarker.bShowDistance = true
PlayerMapMarker.DistanceUnit = "m"
PlayerMapMarker.WeaponIconBrushW = 96
PlayerMapMarker.WeaponIconBrushH = 48
PlayerMapMarker.HPWidgetSwitcherTypeIndex = 0
PlayerMapMarker.HPWidgetSwitcherType2Index = 0
PlayerMapMarker.bForceSwitcherIndexEveryUpdate = true
PlayerMapMarker.bUseSnapLines = true
PlayerMapMarker.SnapLineThickness = 1.2
PlayerMapMarker.SnapLineOriginY = 50
PlayerMapMarker.SnapLineOriginOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetY = -14
PlayerMapMarker.SnapLineColor = FLinearColor and FLinearColor(0.0, 1.0, 0.0, 1.0) or {
  R = 0,
  G = 255,
  B = 0,
  A = 255
}
PlayerMapMarker.SnapLineOpacity = 0.7
PlayerMapMarker.MapAddedFlag = 4
PlayerMapMarker.nUpdateInterval = 0.5
PlayerMapMarker.bUseFrameTick = false
PlayerMapMarker.nHeavyScanFrameInterval = 15
PlayerMapMarker.nDistanceUpdateFrameInterval = 5
PlayerMapMarker.bIncludeMe = false
PlayerMapMarker.bIncludeAI = true
PlayerMapMarker.bUseServerMarks = false
PlayerMapMarker.bActive = false
PlayerMapMarker.MarkMap = {}
PlayerMapMarker.PlayerInfo = {}
PlayerMapMarker.ESPCanvas = nil
PlayerMapMarker.ESPWidgets = {}
PlayerMapMarker.ESPWidgetPtrs = {}
PlayerMapMarker.SnapLineWidgets = {}
PlayerMapMarker._cachedViewportW = 1920
PlayerMapMarker._cachedViewportH = 1080
PlayerMapMarker._FrameCount = 0
PlayerMapMarker._bTickRegistered = false
PlayerMapMarker._CachedAllChars = nil
PlayerMapMarker._CachedMyLoc = nil
PlayerMapMarker._CachedMyKey = nil
PlayerMapMarker.WidgetComps = {}
PlayerMapMarker._bAllPathsFailed = false
PlayerMapMarker._bLightUpdateScheduled = false
PlayerMapMarker._LightUpdateInterval = 0.02
PlayerMapMarker._bDistanceUpdateScheduled = false
PlayerMapMarker._DistanceUpdateInterval = 0.1
PlayerMapMarker._bScreenMarkConfigSetup = false

local function IsValid(obj)
  if obj == nil then
    return false
  end
  if slua and slua.isValid then
    return slua.isValid(obj)
  end
  return obj ~= nil
end

function PlayerMapMarker.SetupScreenMarkConfig()
  if PlayerMapMarker._bScreenMarkConfigSetup then
    return true
  end
  local bOK = false
  pcall(function()
    local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
    local ScreenMarkConfig = GamePlayTools.GetCurrentConfig("ScreenMarkConfig")
    if ScreenMarkConfig then
      ScreenMarkConfig[1007] = {
        UIPathName = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP_C",
        MaxWidgetNum = 100,
        MaxShowDistance = 6000000,
        bBindOutScreen = false,
        bBindBlocked = true,
        bNeedPreLoad = true,
        bIsBindingActor = true,
        BindSocketName = "HelmetSocket",
        WorldPositionOffset = FVector and FVector(0, 0, 80) or {
          X = 0,
          Y = 0,
          Z = 80
        }
      }
      PlayerMapMarker._bScreenMarkConfigSetup = true
      bOK = true
    end
  end)
  return bOK
end

function PlayerMapMarker.GetGameplayData()
  if PlayerMapMarker._CachedGameplayData then
    return PlayerMapMarker._CachedGameplayData
  end
  local ok, GDP = pcall(function()
    return require("GameLua.GameCore.Data.GameplayData")
  end)
  if ok and GDP then
    PlayerMapMarker._CachedGameplayData = GDP
    return GDP
  end
  return nil
end

function PlayerMapMarker.GetMyPlayerController()
  local PC = PlayerMapMarker._CachedPC
  if PC and IsValid(PC) then
    return PC
  end
  local GDP = PlayerMapMarker.GetGameplayData()
  if not GDP then
    return nil
  end
  pcall(function()
    PC = GDP.GetPlayerController and GDP.GetPlayerController()
  end)
  if PC and IsValid(PC) then
    PlayerMapMarker._CachedPC = PC
    return PC
  end
  return nil
end

function PlayerMapMarker.GetCGameState()
  if CGameState and IsValid(CGameState) then
    return CGameState
  end
  if PlayerMapMarker._CachedCGameState and IsValid(PlayerMapMarker._CachedCGameState) then
    return PlayerMapMarker._CachedCGameState
  end
  local ok, GS = pcall(function()
    return require("GameLua.GameCore.Data.CGameState")
  end)
  if ok and GS then
    PlayerMapMarker._CachedCGameState = GS
    return GS
  end
  return nil
end

function PlayerMapMarker.GetAllCharacters()
  local AllChars = {}
  pcall(function()
    local Pawns = Game:GetAllPlayerPawns()
    if Pawns then
      for _, Pawn in pairs(Pawns) do
        if Pawn and slua.isValid(Pawn) then
          local pKey
          if Pawn.GetPlayerKey then
            pKey = Pawn:GetPlayerKey()
          end
          if not pKey and Pawn.PlayerKey then
            pKey = Pawn.PlayerKey
          end
          if not pKey and Pawn.PlayerState and Pawn.PlayerState.PlayerKey then
            pKey = Pawn.PlayerState.PlayerKey
          end
          if pKey then
            AllChars[pKey] = Pawn
          end
        end
      end
    end
  end)
  if not next(AllChars) then
    local GS = PlayerMapMarker.GetCGameState()
    if GS and GS.GetAllCharacters then
      pcall(function()
        AllChars = GS:GetAllCharacters()
      end)
    end
  end
  return AllChars
end

function PlayerMapMarker.GetMyPlayerKey()
  local PC = PlayerMapMarker.GetMyPlayerController()
  if not IsValid(PC) then
    return nil
  end
  local MyKey
  pcall(function()
    if PC.GetPlayerKey then
      MyKey = PC:GetPlayerKey()
    elseif PC.PlayerState and PC.PlayerState.PlayerKey then
      MyKey = PC.PlayerState.PlayerKey
    end
  end)
  return MyKey
end

function PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
  local bIsMe = false
  pcall(function()
    local GDP = PlayerMapMarker.GetGameplayData()
    if GDP and GDP.GetLocalCharacter then
      local MyChar = GDP.GetLocalCharacter()
      if MyChar and Character == MyChar then
        bIsMe = true
        return
      end
    end
    local PC = PlayerMapMarker.GetMyPlayerController()
    if PC and PC.GetPawn then
      local Pawn = PC:GetPawn()
      if Pawn and Character == Pawn then
        bIsMe = true
        return
      end
    end
  end)
  if MyKey ~= nil and PlayerKey ~= nil and not bIsMe then
    bIsMe = false
  end
  return bIsMe
end

function PlayerMapMarker.GetCharacterLocation(Character)
  if not IsValid(Character) then
    return nil
  end
  local Loc
  pcall(function()
    if Character.K2_GetActorLocation then
      Loc = Character:K2_GetActorLocation()
    end
  end)
  if not Loc then
    pcall(function()
      if Game and Game.GetActorLocation then
        Loc = Game:GetActorLocation(Character)
      end
    end)
  end
  return Loc
end

function PlayerMapMarker.CalcDistance(Loc1, Loc2)
  if not Loc1 or not Loc2 then
    return nil
  end
  local Dist
  pcall(function()
    if FVector and FVector.Dist2D then
      Dist = FVector.Dist2D(Loc1, Loc2)
    end
  end)
  if not Dist then
    pcall(function()
      local DX = (Loc1.X or 0) - (Loc2.X or 0)
      local DY = (Loc1.Y or 0) - (Loc2.Y or 0)
      Dist = math.sqrt(DX * DX + DY * DY)
    end)
  end
  return Dist
end

function PlayerMapMarker.GetDistanceString(MyLoc, TargetLoc)
  if not PlayerMapMarker.bShowDistance then
    return ""
  end
  if not MyLoc or not TargetLoc then
    return ""
  end
  local Dist = PlayerMapMarker.CalcDistance(MyLoc, TargetLoc)
  if not Dist then
    return ""
  end
  local Meters = Dist / 100
  if Meters < 1000 then
    return string.format("%dm", math.floor(Meters))
  else
    return string.format("%.1fkm", Meters / 1000)
  end
end

function PlayerMapMarker.GetMyLocation()
  local GDP = PlayerMapMarker.GetGameplayData()
  if not GDP then
    return nil
  end
  local MyChar
  pcall(function()
    MyChar = GDP.GetLocalCharacter and GDP.GetLocalCharacter()
  end)
  if not IsValid(MyChar) then
    local PC = PlayerMapMarker.GetMyPlayerController()
    if IsValid(PC) then
      pcall(function()
        if PC.GetPawn then
          local Pawn = PC:GetPawn()
          if IsValid(Pawn) and Pawn.K2_GetActorLocation then
            return Pawn:K2_GetActorLocation()
          end
        end
      end)
    end
    return nil
  end
  return PlayerMapMarker.GetCharacterLocation(MyChar)
end

function PlayerMapMarker.GetPlayerName(Character)
  if not IsValid(Character) then
    return "Unknown"
  end
  local Name
  pcall(function()
    if Character.GetPlayerNameSafety then
      Name = Character:GetPlayerNameSafety()
    end
  end)
  if not Name then
    pcall(function()
      local PS
      if Character.GetPlayerStateSafety then
        PS = Character:GetPlayerStateSafety()
      elseif Character.GetPlayerState then
        PS = Character:GetPlayerState()
      end
      if IsValid(PS) and PS.GetPlayerName then
        Name = PS:GetPlayerName()
      end
    end)
  end
  return Name or "Unknown"
end

function PlayerMapMarker.IsAI(Character)
  local bAI = false
  pcall(function()
    if Game and Game.IsAI then
      bAI = Game:IsAI(Character)
    end
  end)
  return bAI
end

function PlayerMapMarker.IsAlive(Character)
  local bAlive = true
  pcall(function()
    if Character.IsAlive then
      bAlive = Character:IsAlive()
    end
  end)
  return bAlive
end

function PlayerMapMarker.IsOurESPWidget(w)
  if not w or not slua.isValid(w) then
    return false
  end
  local bIsOurs = false
  pcall(function()
    local wstr = tostring(w)
    for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
      if ESPData and ESPData.Widget and ESPData.Widget.Container then
        local cstr = tostring(ESPData.Widget.Container)
        if cstr == wstr then
          bIsOurs = true
          return
        end
      end
    end
  end)
  if bIsOurs then
    return true
  end
  pcall(function()
    if w.GetChildrenCount then
      local n = w:GetChildrenCount()
      for i = 0, n - 1 do
        local child = w:GetChildAt(i)
        if child and slua.isValid(child) then
          local cstr = tostring(child)
          if string.find(cstr, "Border") then
            bIsOurs = true
            break
          end
        end
      end
    end
  end)
  if not bIsOurs then
    pcall(function()
      local slot = w.Slot
      if slot and slot.GetPosition then
        local pos = slot:GetPosition()
        if pos and (math.abs(pos.X or 0) > 1 or 1 < math.abs(pos.Y or 0)) then
          bIsOurs = true
        end
      end
    end)
  end
  return bIsOurs
end

function PlayerMapMarker.ApplyAnchorBasedPosition(Slot, ScreenPos, Canvas)
  if not Slot or not ScreenPos then
    return false
  end
  local sx = ScreenPos.X or 0
  local sy = ScreenPos.Y or 0
  local sz = PlayerMapMarker.ESPWidgetSize or FVector2D and FVector2D(100, 30) or {X = 100, Y = 30}
  local align = PlayerMapMarker.ESPWidgetAlignment or FVector2D and FVector2D(0.5, 1.0) or {X = 0.5, Y = 1.0}
  local canvasW, canvasH = 0, 0
  if PlayerMapMarker._cachedViewportW and PlayerMapMarker._cachedViewportW > 200 then
    canvasW = PlayerMapMarker._cachedViewportW
    canvasH = PlayerMapMarker._cachedViewportH
  end
  if canvasW < 200 then
    pcall(function()
      local PC = PlayerMapMarker.GetMyPlayerController()
      if IsValid(PC) and PC.GetViewportSize then
        local VS = FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
        PC:GetViewportSize(VS)
        if VS and VS.X and VS.X > 200 then
          canvasW = VS.X
          canvasH = VS.Y
          PlayerMapMarker._cachedViewportW = canvasW
          PlayerMapMarker._cachedViewportH = canvasH
        end
      end
    end)
  end
  if 200 < canvasW and 200 < canvasH then
    local anchorX = (sx + (PlayerMapMarker.ESPAnchorOffsetX or 0)) / canvasW
    local anchorY = (sy + (PlayerMapMarker.ESPAnchorOffsetY or 0)) / canvasH
    anchorX = math.max(0, math.min(1, anchorX))
    anchorY = math.max(0, math.min(1, anchorY))
    local bSuccess = false
    pcall(function()
      local FAnchors = import("Anchors") or import("/Script/SlateCore.Anchors")
      if Slot.SetAnchors and FAnchors then
        local anchors = FAnchors(anchorX, anchorY, anchorX, anchorY)
        if anchors then
          Slot:SetAnchors(anchors)
          Slot:SetPosition(FVector2D and FVector2D(0, 0) or {X = 0, Y = 0})
          bSuccess = true
        end
      end
    end)
    if not bSuccess then
      pcall(function()
        if Slot.SetAnchors then
          Slot:SetAnchors(anchorX, anchorY, anchorX, anchorY)
          Slot:SetPosition(FVector2D and FVector2D(0, 0) or {X = 0, Y = 0})
          bSuccess = true
        end
      end)
    end
    if bSuccess then
      pcall(function()
        if Slot.SetOffsets and import("Margin") then
          Slot:SetOffsets(import("Margin")(0, 0, sz.X, sz.Y))
        end
      end)
      pcall(function()
        Slot:SetSize(sz)
      end)
      pcall(function()
        Slot:SetAlignment(align)
      end)
      pcall(function()
        if Slot.SetAutoSize then
          Slot:SetAutoSize(PlayerMapMarker.ESPWidgetAutoSize or true)
        end
      end)
      pcall(function()
        if Slot.SetZOrder then
          Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 2)
        end
      end)
      return true
    end
  end
  pcall(function()
    Slot:SetPosition(FVector2D and FVector2D(sx, sy) or {X = sx, Y = sy})
    pcall(function()
      Slot:SetSize(sz)
    end)
    pcall(function()
      Slot:SetAlignment(align)
    end)
    pcall(function()
      if Slot.SetAutoSize then
        Slot:SetAutoSize(PlayerMapMarker.ESPWidgetAutoSize or true)
      end
    end)
    pcall(function()
      if Slot.SetZOrder then
        Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 2)
      end
    end)
  end)
  return false
end

function PlayerMapMarker.InitESPCanvas()
  if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
    return true
  end
  local InGameUITools
  pcall(function()
    InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
  end)
  if not InGameUITools then
    return false
  end
  local MainControlBaseUI
  pcall(function()
    MainControlBaseUI = InGameUITools.GetMainControlBaseUI()
  end)
  if not MainControlBaseUI or not Game:IsValid(MainControlBaseUI) then
    return false
  end
  local ParentCanvas
  pcall(function()
    if MainControlBaseUI.CanvasPanel_0 and Game:IsValid(MainControlBaseUI.CanvasPanel_0) then
      ParentCanvas = MainControlBaseUI.CanvasPanel_0
    elseif MainControlBaseUI.CanvasPanel_42 and Game:IsValid(MainControlBaseUI.CanvasPanel_42) then
      ParentCanvas = MainControlBaseUI.CanvasPanel_42
    end
  end)
  if not ParentCanvas then
    return false
  end
  PlayerMapMarker.ESPCanvas = ParentCanvas
  pcall(function()
    local nChildren = ParentCanvas:GetChildrenCount()
    for i = nChildren - 1, 0, -1 do
      local child = ParentCanvas:GetChildAt(i)
      if child and slua.isValid(child) and PlayerMapMarker.IsOurESPWidget(child) then
        pcall(function()
          ParentCanvas:RemoveChild(child)
        end)
      end
    end
  end)
  return true
end

function PlayerMapMarker.FindProgressBarInWidget(WidgetObj, Depth, MaxDepth)
  if not WidgetObj or not slua.isValid(WidgetObj) then
    return nil
  end
  Depth = Depth or 0
  MaxDepth = MaxDepth or 5
  if Depth > MaxDepth then
    return nil
  end
  local bIsPB = false
  pcall(function()
    if WidgetObj.SetPercent and WidgetObj.SetFillColorAndOpacity then
      bIsPB = true
    end
  end)
  if bIsPB then
    return WidgetObj
  end
  local nChildren = 0
  pcall(function()
    if WidgetObj.GetChildrenCount then
      nChildren = WidgetObj:GetChildrenCount()
    end
  end)
  for i = 0, math.max(nChildren - 1, 0) do
    local child
    pcall(function()
      child = WidgetObj:GetChildAt(i)
    end)
    if child and slua.isValid(child) then
      do
        local result = PlayerMapMarker.FindProgressBarInWidget(child, Depth + 1, MaxDepth)
        if result then
          return result
        end
      end
    end
  end
  return nil
end

function PlayerMapMarker.GetTeamID(Character)
  if not IsValid(Character) then
    return nil
  end
  local TeamID
  pcall(function()
    if Character.GetTeamID then
      TeamID = Character:GetTeamID()
    end
  end)
  if not TeamID then
    pcall(function()
      local PS
      if Character.GetPlayerStateSafety then
        PS = Character:GetPlayerStateSafety()
      elseif Character.GetPlayerState then
        PS = Character:GetPlayerState()
      end
      if IsValid(PS) and PS.GetTeamID then
        TeamID = PS:GetTeamID()
      elseif IsValid(PS) and PS.TeamID then
        TeamID = PS.TeamID
      end
    end)
  end
  if not TeamID then
    pcall(function()
      if Character.TeamID then
        TeamID = Character.TeamID
      end
    end)
  end
  return TeamID
end

function PlayerMapMarker.GetTeamColor(TeamID)
  return FLinearColor and FLinearColor(0.0, 1.0, 1.0, 1.0) or {
    R = 0,
    G = 255,
    B = 255,
    A = 255
  }
end

local _WhiteTexture
local _bWhiteTextureFailed = false

local function GetWhiteTexture()
  if _WhiteTexture then
    return _WhiteTexture
  end
  if _bWhiteTextureFailed then
    return nil
  end
  pcall(function()
    local paths = {
      "/Game/BluePrints/UI/Textures/White.White",
      "/Game/BluePrints/UI/Textures/Common/White.White",
      "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture"
    }
    for _, path in ipairs(paths) do
      pcall(function()
        local tex = import(path)
        if tex and slua.isValid(tex) then
          _WhiteTexture = tex
          return
        end
      end)
      if _WhiteTexture then
        break
      end
    end
  end)
  if not _WhiteTexture then
    _bWhiteTextureFailed = true
  end
  return _WhiteTexture
end

local function SetImageColor(Image, color)
  if not Image or not slua.isValid(Image) then
    return false
  end
  local bOK = false
  pcall(function()
    if Image.SetBrushTintColor then
      Image:SetBrushTintColor(color)
      bOK = true
    end
  end)
  pcall(function()
    if Image.SetColorAndOpacity then
      Image:SetColorAndOpacity(color)
      bOK = true
    end
  end)
  pcall(function()
    if Image.SetBrushFromTexture then
      local whiteTex = GetWhiteTexture()
      if whiteTex then
        Image:SetBrushFromTexture(whiteTex, false)
        if Image.SetColorAndOpacity then
          Image:SetColorAndOpacity(color)
        end
        bOK = true
      end
    end
  end)
  pcall(function()
    Image:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    Image:SetRenderOpacity(1.0)
  end)
  return bOK
end

function PlayerMapMarker._GetWidgetRoot(WidgetObj)
  if not WidgetObj or not slua.isValid(WidgetObj) then
    return nil
  end
  local Root
  pcall(function()
    if WidgetObj.GetRootWidget then
      Root = WidgetObj:GetRootWidget()
    end
  end)
  if Root and slua.isValid(Root) then
    return Root
  end
  pcall(function()
    if WidgetObj.WidgetTree and WidgetObj.WidgetTree.RootWidget then
      Root = WidgetObj.WidgetTree.RootWidget
    end
  end)
  if Root and slua.isValid(Root) then
    return Root
  end
  pcall(function()
    if WidgetObj.RootWidget and slua.isValid(WidgetObj.RootWidget) then
      Root = WidgetObj.RootWidget
    end
  end)
  return Root
end

function PlayerMapMarker._FindNamedWidgetInTree(WidgetObj, TargetName, MaxDepth)
  if not WidgetObj or not slua.isValid(WidgetObj) then
    return nil
  end
  MaxDepth = MaxDepth or 8
  local wname
  pcall(function()
    if WidgetObj.GetName then
      wname = WidgetObj:GetName()
    end
  end)
  if wname and wname == TargetName then
    return WidgetObj
  end
  local wstr = tostring(WidgetObj)
  if wstr and string.find(wstr, TargetName, 1, true) then
    if wname and wname == TargetName then
      return WidgetObj
    elseif not wname or wname == "" then
      local _, endPos = string.find(wstr, TargetName, 1, true)
      if endPos then
        local nextChar = string.sub(wstr, endPos + 1, endPos + 1)
        if nextChar ~= "_" and nextChar ~= "" then
          return WidgetObj
        end
      end
    end
  end
  local nChildren = 0
  pcall(function()
    if WidgetObj.GetChildrenCount then
      nChildren = WidgetObj:GetChildrenCount()
    end
  end)
  if 0 < nChildren then
    for i = 0, nChildren - 1 do
      local child
      pcall(function()
        child = WidgetObj:GetChildAt(i)
      end)
      if child and slua.isValid(child) then
        do
          local found = PlayerMapMarker._FindNamedWidgetInTree(child, TargetName, MaxDepth - 1)
          if found then
            return found
          end
        end
      end
    end
  else
    local Root = PlayerMapMarker._GetWidgetRoot(WidgetObj)
    if Root and slua.isValid(Root) and Root ~= WidgetObj then
      local found = PlayerMapMarker._FindNamedWidgetInTree(Root, TargetName, MaxDepth - 1)
      if found then
        return found
      end
    end
  end
  return nil
end

function PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
  if not Widget or not Widget.Container then
    return
  end
  if not _G.LexusConfig.Esp9_Team then
    pcall(function()
      local W = Widget.Container
      if W and slua.isValid(W) then
        local img1 = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamBG", 8)
        if img1 and slua.isValid(img1) then
          img1:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
        local img2 = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamLogoBG", 8)
        if img2 and slua.isValid(img2) then
          img2:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
        if Widget.TeamBgBorder and slua.isValid(Widget.TeamBgBorder) then
          Widget.TeamBgBorder:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
      end
    end)
    return
  end
  local color = PlayerMapMarker.GetTeamColor(TeamID)
  if not color then
    return
  end
  pcall(function()
    local W = Widget.Container
    if not W or not slua.isValid(W) then
      return
    end
    local bBG = false
    local Image_TeamBG = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamBG", 8)
    if Image_TeamBG and slua.isValid(Image_TeamBG) then
      bBG = SetImageColor(Image_TeamBG, color)
    end
    local Image_TeamLogoBG = PlayerMapMarker._FindNamedWidgetInTree(W, "Image_TeamLogoBG", 8)
    if Image_TeamLogoBG and slua.isValid(Image_TeamLogoBG) then
      SetImageColor(Image_TeamLogoBG, color)
    end
    if W.SetTeamColor then
      pcall(function()
        W:SetTeamColor(TeamID)
      end)
    end
    if not Widget.TeamBgBorder or not slua.isValid(Widget.TeamBgBorder) then
      pcall(function()
        local Border = CGame:NewObjectFromPath("/Script/UMG.Border", W)
        if Border and slua.isValid(Border) then
          pcall(function()
            Border:SetBrushColor(color)
          end)
          pcall(function()
            Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
          end)
          pcall(function()
            Border:SetRenderOpacity(0.7)
          end)
          pcall(function()
            Border:SetDesiredSizeOverride(FVector2D and FVector2D(120, 20) or {X = 120, Y = 20})
          end)
          pcall(function()
            if W.AddChild then
              W:AddChild(Border)
            end
          end)
          pcall(function()
            if Border.SetZOrder then
              Border:SetZOrder(-1)
            end
          end)
          Widget.TeamBgBorder = Border
        end
      end)
    else
      pcall(function()
        Widget.TeamBgBorder:SetBrushColor(color)
        Widget.TeamBgBorder:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        Widget.TeamBgBorder:SetRenderOpacity(0.7)
      end)
    end
  end)
end

function PlayerMapMarker.GetCharacterMesh(Character)
  if not IsValid(Character) then
    return nil
  end
  local Mesh
  pcall(function()
    if Character.Mesh and Game:IsValid(Character.Mesh) then
      Mesh = Character.Mesh
    end
  end)
  if not Mesh then
    pcall(function()
      local SkeletalMeshCompClass = import("/Script/Engine.SkeletalMeshComponent")
      Mesh = Character:GetComponentByClass(SkeletalMeshCompClass)
    end)
  end
  return Mesh
end

function PlayerMapMarker.GetESPLocation(Character)
  if not IsValid(Character) then
    return nil
  end
  local BoneLoc = PlayerMapMarker.GetCharacterLocation(Character)
  if BoneLoc then
    local heightOffset = 85
    pcall(function()
      if Character.bIsCrouched then
        heightOffset = 60
      end
      if Character.IsProne and Character:IsProne() then
        heightOffset = 30
      end
    end)
    pcall(function()
      BoneLoc.Z = BoneLoc.Z + heightOffset + (PlayerMapMarker.ESPWorldOffsetZ or 0)
    end)
  end
  return BoneLoc
end

function PlayerMapMarker.GetCharacterWeaponInfo(Character)
  if not IsValid(Character) then
    return nil
  end
  local WeaponID, WeaponName, WeaponIconPath, WeaponIconTexture, CurrentWeapon
  pcall(function()
    if Character.GetCurrentWeapon then
      CurrentWeapon = Character:GetCurrentWeapon()
    end
  end)
  if not CurrentWeapon then
    pcall(function()
      CurrentWeapon = Character.CurrentWeapon
    end)
  end
  if not CurrentWeapon then
    pcall(function()
      if Character.GetWeaponManager then
        local WM = Character:GetWeaponManager()
        if WM and WM.GetCurrentWeapon then
          CurrentWeapon = WM:GetCurrentWeapon()
        end
      end
    end)
  end
  if CurrentWeapon and IsValid(CurrentWeapon) then
    pcall(function()
      if CurrentWeapon.GetWeaponID then
        WeaponID = CurrentWeapon:GetWeaponID()
      end
    end)
    if not WeaponID then
      pcall(function()
        WeaponID = CurrentWeapon.WeaponID
      end)
    end
    if not WeaponID then
      pcall(function()
        if CurrentWeapon.GetItemID then
          WeaponID = CurrentWeapon:GetItemID()
        end
      end)
    end
    pcall(function()
      if CurrentWeapon.GetWeaponName then
        WeaponName = CurrentWeapon:GetWeaponName()
      end
    end)
    pcall(function()
      if CurrentWeapon.GetWeaponIconPath then
        WeaponIconPath = CurrentWeapon:GetWeaponIconPath()
      end
    end)
    pcall(function()
      if CurrentWeapon.GetWeaponIcon then
        WeaponIconTexture = CurrentWeapon:GetWeaponIcon()
      end
    end)
  end
  if not WeaponID then
    pcall(function()
      local PS
      if Character.GetPlayerStateSafety then
        PS = Character:GetPlayerStateSafety()
      elseif Character.GetPlayerState then
        PS = Character:GetPlayerState()
      end
      if PS and IsValid(PS) then
        if PS.GetCurrentWeaponID then
          WeaponID = PS:GetCurrentWeaponID()
        end
        if not WeaponID and PS.CurWeaponID then
          WeaponID = PS.CurWeaponID
        end
      end
    end)
  end
  return {
    WeaponID = WeaponID,
    WeaponName = WeaponName,
    WeaponIconPath = WeaponIconPath,
    WeaponIconTexture = WeaponIconTexture,
    CurrentWeapon = CurrentWeapon
  }
end

function PlayerMapMarker.FindWeaponIconInWidget(WidgetObj, Depth, MaxDepth)
  if not WidgetObj or not slua.isValid(WidgetObj) then
    return nil
  end
  Depth = Depth or 0
  MaxDepth = MaxDepth or 8
  local propNames = {
    "Image_Weapon",
    "Image_WeaponIcon",
    "Image_Gun",
    "Image_Icon",
    "WeaponIcon",
    "WeaponImage",
    "Image_Equip"
  }
  for _, pname in ipairs(propNames) do
    pcall(function()
      local prop = WidgetObj[pname]
      if prop and slua.isValid(prop) then
        local hasBrush = false
        pcall(function()
          if prop.Brush then
            hasBrush = true
          end
        end)
        if hasBrush then
          return prop
        end
      end
    end)
  end
  if Depth >= MaxDepth then
    return nil
  end
  local nChildren = 0
  pcall(function()
    if WidgetObj.GetChildrenCount then
      nChildren = WidgetObj:GetChildrenCount()
    end
  end)
  for i = 0, math.max(nChildren - 1, 0) do
    local child
    pcall(function()
      child = WidgetObj:GetChildAt(i)
    end)
    if child and slua.isValid(child) then
      do
        local result = PlayerMapMarker.FindWeaponIconInWidget(child, Depth + 1, MaxDepth)
        if result then
          return result
        end
      end
    end
  end
  if nChildren == 0 then
    local Root = PlayerMapMarker._GetWidgetRoot(WidgetObj)
    if Root and slua.isValid(Root) and Root ~= WidgetObj then
      local result = PlayerMapMarker.FindWeaponIconInWidget(Root, Depth + 1, MaxDepth)
      if result then
        return result
      end
    end
  end
  return nil
end

function PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, DefaultW, DefaultH)
  if not ImageWidget or not slua.isValid(ImageWidget) then
    return
  end
  DefaultW = DefaultW or 138
  DefaultH = DefaultH or 69
  pcall(function()
    local brush = ImageWidget.Brush
    if brush then
      brush.ImageSize = FVector2D and FVector2D(DefaultW, DefaultH) or {X = DefaultW, Y = DefaultH}
      brush.DrawAs = 3
      brush.TintColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {
        R = 1,
        G = 1,
        B = 1,
        A = 1
      }
      if ImageWidget.SetBrush then
        ImageWidget:SetBrush(brush)
      end
    end
    if ImageWidget.SetDesiredSizeOverride then
      ImageWidget:SetDesiredSizeOverride(FVector2D and FVector2D(DefaultW, DefaultH) or {X = DefaultW, Y = DefaultH})
    end
    local slot = ImageWidget.Slot
    if slot and slot.SetSize then
      slot:SetSize(FVector2D and FVector2D(DefaultW, DefaultH) or {X = DefaultW, Y = DefaultH})
    end
    ImageWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    ImageWidget:SetRenderOpacity(1.0)
    ImageWidget:SetColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {
      R = 1,
      G = 1,
      B = 1,
      A = 1
    })
  end)
end

function PlayerMapMarker.ApplyWeaponIconFullOpacity(Container, ourWeaponIcon)
  local fullIcon = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {
    R = 1,
    G = 1,
    B = 1,
    A = 1
  }
  if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then
    return
  end
  pcall(function()
    if ourWeaponIcon.SetRenderOpacity then
      ourWeaponIcon:SetRenderOpacity(1.0)
    end
  end)
  pcall(function()
    if ourWeaponIcon.SetColorAndOpacity then
      ourWeaponIcon:SetColorAndOpacity(fullIcon)
    end
  end)
  pcall(function()
    local brush = ourWeaponIcon.Brush
    if brush then
      pcall(function()
        brush.TintColor = fullIcon
      end)
      if ourWeaponIcon.SetBrush then
        ourWeaponIcon:SetBrush(brush)
      end
    end
  end)
  local chainNames = {
    "Border_WeaponColor",
    "Border_Weapon",
    "Border_WeaponIcon",
    "SizeBox_Weapon",
    "ScaleBox_Weapon",
    "Switcher_WeaponIcon"
  }
  for _, pname in ipairs(chainNames) do
    pcall(function()
      local node = Container and Container[pname]
      if node and slua.isValid(node) and node.SetRenderOpacity then
        node:SetRenderOpacity(1.0)
      end
      if node and slua.isValid(node) and node.SetColorAndOpacity then
        node:SetColorAndOpacity(fullIcon)
      end
    end)
  end
end

function PlayerMapMarker.ApplyWeaponIconToImage(ImageWidget, winfo)
  if not ImageWidget or not slua.isValid(ImageWidget) then
    return false, "no_widget"
  end
  if not winfo or not winfo.WeaponID then
    return false, "no_weapon_id"
  end
  local iconPath
  local method = "none"
  local bHasAddKnownMissing = false
  local defaultW = 138
  local defaultH = 69
  pcall(function()
    local itemRecord = CDataTable.GetTableData("Item", winfo.WeaponID)
    if itemRecord and itemRecord.KillWhiteIcon and itemRecord.KillWhiteIcon ~= "" then
      iconPath = itemRecord.KillWhiteIcon
      method = "KillWhiteIcon"
    end
    if (not iconPath or iconPath == "") and winfo.WeaponIconPath and winfo.WeaponIconPath ~= "" then
      iconPath = winfo.WeaponIconPath
      method = "WeaponIconPath"
    end
    if (not iconPath or iconPath == "") and winfo.WeaponIconTexture and slua.isValid(winfo.WeaponIconTexture) and ImageWidget.SetBrushFromTexture then
      ImageWidget:SetBrushFromTexture(winfo.WeaponIconTexture, true)
      method = "WeaponIconTexture"
      return
    end
    if not iconPath or iconPath == "" then
      local UIUtil = require("client.common.ui_util")
      iconPath, bHasAddKnownMissing = UIUtil.GetItemBigIcon(winfo.WeaponID, ImageWidget)
      if iconPath and iconPath ~= "" then
        method = "GetItemBigIcon"
      end
    end
    if not iconPath or iconPath == "" then
      local UIUtil = require("client.common.ui_util")
      iconPath = UIUtil.GetItemSmallIcon(winfo.WeaponID, ImageWidget, bHasAddKnownMissing)
      if iconPath and iconPath ~= "" then
        method = "GetItemSmallIcon"
      end
    end
  end)
  if method == "WeaponIconTexture" then
    PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH)
    return true, method
  end
  if not iconPath or iconPath == "" then
    return false, "no_path"
  end
  local bOK = false
  pcall(function()
    if ImageWidget.SetBrushResourceFromPathSync then
      ImageWidget:SetBrushResourceFromPathSync(iconPath, true)
      bOK = true
    end
    if not bOK then
      local util = require("client.slua_ui_framework.util")
      local result = util.SetTexture(ImageWidget, iconPath, {
        sync = true,
        bMatchSize = true,
        bIsInCombatState = true,
        bHasAddKnownMissing = bHasAddKnownMissing
      })
      bOK = result ~= nil
    end
    if not bOK then
      local tex = import(iconPath)
      if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then
        ImageWidget:SetBrushFromTexture(tex, true)
        bOK = true
      end
    end
    if not bOK then
      local LoadObject = import("LoadObject")
      if LoadObject then
        local tex = LoadObject(iconPath)
        if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then
          ImageWidget:SetBrushFromTexture(tex, true)
          bOK = true
        end
      end
    end
  end)
  if bOK then
    PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH)
  end
  return bOK, method .. ":" .. tostring(iconPath)
end

function PlayerMapMarker.CopyWeaponIconBrushFromNative(ourWeaponIcon, nativeWeaponIcon)
  if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then
    return false
  end
  if not nativeWeaponIcon or not slua.isValid(nativeWeaponIcon) then
    return false
  end
  local bCopied = false
  pcall(function()
    local nBrush = nativeWeaponIcon.Brush
    if nBrush then
      local resObj
      pcall(function()
        resObj = nBrush.ResourceObject
      end)
      if resObj and slua.isValid(resObj) and ourWeaponIcon.SetBrushFromTexture then
        ourWeaponIcon:SetBrushFromTexture(resObj, true)
        bCopied = true
      end
      if bCopied then
        do
          local imgSize
          pcall(function()
            imgSize = nBrush.ImageSize
          end)
          if imgSize then
            do
              local oBrush = ourWeaponIcon.Brush
              if oBrush then
                oBrush.ImageSize = imgSize
                if ourWeaponIcon.SetBrush then
                  ourWeaponIcon:SetBrush(oBrush)
                end
              end
            end
          end
        end
      end
    end
  end)
  return bCopied
end

function PlayerMapMarker.AddWeaponIconToESP(WidgetData, Character)
  if not WidgetData or not WidgetData.Container then
    return
  end
  local Container = WidgetData.Container
  if not slua.isValid(Container) then
    return
  end
  if not _G.LexusConfig.Esp9_Weapon then
    pcall(function()
      local chainNames = {
        "Border_WeaponColor",
        "Border_Weapon",
        "Border_WeaponIcon",
        "SizeBox_Weapon",
        "ScaleBox_Weapon",
        "Switcher_WeaponIcon"
      }
      for _, pname in ipairs(chainNames) do
        local node = Container[pname]
        if node and slua.isValid(node) and node.SetWidgetVisibility then
          node:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
      end
      local ourWeaponIcon = Container.WeaponIcon or PlayerMapMarker.FindWeaponIconInWidget(Container, 0, 8)
      if ourWeaponIcon and slua.isValid(ourWeaponIcon) then
        ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      end
    end)
    WidgetData._LastWeaponID = 0
    WidgetData._WeaponIconApplied = false
    return
  end
  pcall(function()
    local ourWeaponIcon = Container.WeaponIcon
    if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then
      ourWeaponIcon = PlayerMapMarker.FindWeaponIconInWidget(Container, 0, 8)
    end
    if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then
      return
    end
    local winfo = Character and PlayerMapMarker.GetCharacterWeaponInfo(Character) or nil
    if not (winfo and winfo.WeaponID) or winfo.WeaponID == 0 then
      pcall(function()
        ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      end)
      local chainNames = {
        "Border_WeaponColor",
        "Border_Weapon",
        "Border_WeaponIcon",
        "SizeBox_Weapon",
        "ScaleBox_Weapon",
        "Switcher_WeaponIcon"
      }
      for _, pname in ipairs(chainNames) do
        pcall(function()
          local node = Container and Container[pname]
          if node and slua.isValid(node) and node.SetWidgetVisibility then
            node:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
          end
        end)
      end
      WidgetData._LastWeaponID = 0
      WidgetData._WeaponIconApplied = false
      return
    end
    if WidgetData._LastWeaponID == winfo.WeaponID and WidgetData._WeaponIconApplied then
      pcall(function()
        ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
      pcall(function()
        ourWeaponIcon:SetRenderOpacity(1.0)
      end)
      local chainNames = {
        "Border_WeaponColor",
        "Border_Weapon",
        "Border_WeaponIcon",
        "SizeBox_Weapon",
        "ScaleBox_Weapon",
        "Switcher_WeaponIcon"
      }
      for _, pname in ipairs(chainNames) do
        pcall(function()
          local node = Container and Container[pname]
          if node and slua.isValid(node) and node.SetWidgetVisibility then
            node:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            pcall(function()
              if node.SetRenderOpacity then
                node:SetRenderOpacity(1.0)
              end
            end)
          end
        end)
      end
      if WidgetData._CachedSwitcherIndexes then
        for sName, idx in pairs(WidgetData._CachedSwitcherIndexes) do
          pcall(function()
            local ws = Container[sName]
            if ws and slua.isValid(ws) and ws.SetActiveWidgetIndex then
              ws:SetActiveWidgetIndex(idx)
            end
          end)
        end
      end
      if WidgetData._CachedParentSwitchers then
        for _, data in pairs(WidgetData._CachedParentSwitchers) do
          pcall(function()
            if data.w and slua.isValid(data.w) and data.w.SetActiveWidgetIndex then
              data.w:SetActiveWidgetIndex(data.idx)
            end
          end)
        end
      end
      return
    end
    local chainNames = {
      "Border_WeaponColor",
      "Border_Weapon",
      "Border_WeaponIcon",
      "SizeBox_Weapon",
      "ScaleBox_Weapon",
      "Switcher_WeaponIcon"
    }
    for _, pname in ipairs(chainNames) do
      pcall(function()
        local node = Container and Container[pname]
        if node and slua.isValid(node) and node.SetWidgetVisibility then
          node:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end
      end)
    end
    local bCopied = false
    if winfo and winfo.WeaponID then
      local ok, method = PlayerMapMarker.ApplyWeaponIconToImage(ourWeaponIcon, winfo)
      if ok then
        bCopied = true
      end
    end
    local bWeaponIconSet = false
    if Character and winfo and winfo and winfo.WeaponID then
      pcall(function()
        if Container.SetWeaponIcon then
          Container:SetWeaponIcon(winfo.WeaponID)
          bWeaponIconSet = true
        end
      end)
      if not bWeaponIconSet then
        pcall(function()
          if Container.SetWeaponIconByID then
            Container:SetWeaponIconByID(winfo.WeaponID)
            bWeaponIconSet = true
          end
        end)
      end
      if not bWeaponIconSet then
        pcall(function()
          if Container.UpdateWeaponIcon then
            Container:UpdateWeaponIcon(winfo.WeaponID)
            bWeaponIconSet = true
          end
        end)
      end
      if not bWeaponIconSet then
        pcall(function()
          if Container.SetWeaponID then
            Container:SetWeaponID(winfo.WeaponID)
            bWeaponIconSet = true
          end
        end)
      end
      pcall(function()
        if Container.SetData then
          Container:SetData(Character)
        end
      end)
      pcall(function()
        if Container.SetPlayerInfo then
          Container:SetPlayerInfo(Character)
        end
      end)
      if winfo.CurrentWeapon then
        pcall(function()
          if Container.SetCurrentWeapon then
            Container:SetCurrentWeapon(winfo.CurrentWeapon)
          end
        end)
      end
    end
    if bWeaponIconSet then
      pcall(function()
        local innerIcon = Container.Image_Icon
        if (not innerIcon or not slua.isValid(innerIcon)) and Container.CanvasPanel_Type1 then
          innerIcon = Container.CanvasPanel_Type1.Image_Icon
        end
        if not innerIcon or not slua.isValid(innerIcon) then
          local function findImageIcon(w, depth)
            if not (w and slua.isValid(w)) or 8 < depth then
              return nil
            end
            local prop = w.Image_Icon
            if prop and slua.isValid(prop) then
              return prop
            end
            local n = 0
            pcall(function()
              if w.GetChildrenCount then
                n = w:GetChildrenCount()
              end
            end)
            for i = 0, math.max(n - 1, 0) do
              local c
              pcall(function()
                c = w:GetChildAt(i)
              end)
              if c then
                do
                  local r = findImageIcon(c, depth + 1)
                  if r then
                    return r
                  end
                end
              end
            end
            return nil
          end
          
          innerIcon = findImageIcon(Container, 0)
        end
        if innerIcon and slua.isValid(innerIcon) and innerIcon ~= ourWeaponIcon then
          pcall(function()
            local ibrush = innerIcon.Brush
            if ibrush then
              local iresObj
              pcall(function()
                iresObj = ibrush.ResourceObject
              end)
              if iresObj and slua.isValid(iresObj) then
                if ourWeaponIcon.SetBrushFromAsset then
                  ourWeaponIcon:SetBrushFromAsset(iresObj)
                  bCopied = true
                end
                if not bCopied and ourWeaponIcon.SetBrushFromTexture then
                  ourWeaponIcon:SetBrushFromTexture(iresObj)
                  bCopied = true
                end
              end
            end
          end)
          if not bCopied then
            pcall(function()
              local brush = innerIcon.Brush
              if brush then
                local iresObj
                pcall(function()
                  iresObj = brush.ResourceObject
                end)
                if iresObj and slua.isValid(iresObj) and ourWeaponIcon.SetBrushFromTexture then
                  ourWeaponIcon:SetBrushFromTexture(iresObj, false)
                  PlayerMapMarker.FixWeaponIconBrushSize(ourWeaponIcon)
                  bCopied = true
                end
              end
            end)
          end
        end
      end)
    end
    if not bCopied then
      local nativeWeaponIcon
      if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
        local nChildren = 0
        pcall(function()
          nChildren = PlayerMapMarker.ESPCanvas:GetChildrenCount()
        end)
        for i = 0, math.max(nChildren - 1, 0) do
          local child
          pcall(function()
            child = PlayerMapMarker.ESPCanvas:GetChildAt(i)
          end)
          if child and slua.isValid(child) then
            do
              local cstr = tostring(child)
              if string.find(cstr, "OB_PlayerHeadHPItem") and not PlayerMapMarker.IsOurESPWidget(child) then
                local nativeIcon = child.WeaponIcon
                if nativeIcon and slua.isValid(nativeIcon) then
                  nativeWeaponIcon = nativeIcon
                  break
                end
              end
            end
          end
        end
      end
      if nativeWeaponIcon and slua.isValid(nativeWeaponIcon) then
        local okNative, nativeMethod = PlayerMapMarker.CopyWeaponIconBrushFromNative(ourWeaponIcon, nativeWeaponIcon)
        if okNative then
          bCopied = true
        end
      end
    end
    if not bCopied then
      pcall(function()
        local brush = ourWeaponIcon.Brush
        if brush then
          local resObj
          pcall(function()
            resObj = brush.ResourceObject
          end)
          if resObj and slua.isValid(resObj) and ourWeaponIcon.SetBrushFromTexture then
            ourWeaponIcon:SetBrushFromTexture(resObj)
            bCopied = true
          end
        end
      end)
    end
    if not bCopied then
      pcall(function()
        local brush = ourWeaponIcon.Brush
        if brush then
          local imgSize
          pcall(function()
            imgSize = brush.ImageSize
          end)
          local bZeroSize = false
          if imgSize then
            local sx, sy
            pcall(function()
              sx = imgSize.X
            end)
            pcall(function()
              sy = imgSize.Y
            end)
            if (not sx or sx == 0) and (not sy or sy == 0) then
              bZeroSize = true
            end
          end
          if bZeroSize then
            pcall(function()
              brush.ImageSize = FVector2D and FVector2D(PlayerMapMarker.WeaponIconBrushW or 138, PlayerMapMarker.WeaponIconBrushH or 69) or {X = 138, Y = 69}
            end)
          end
          pcall(function()
            brush.DrawAs = 3
          end)
          if ourWeaponIcon.SetBrush then
            ourWeaponIcon:SetBrush(brush)
          end
        end
      end)
    end
    pcall(function()
      ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
    PlayerMapMarker.ApplyWeaponIconFullOpacity(Container, ourWeaponIcon)
    PlayerMapMarker.FixWeaponIconBrushSize(ourWeaponIcon)
    pcall(function()
      local function findWidgetInSwitcher(switcher, targetWidget)
        if not switcher or not slua.isValid(switcher) then
          return nil
        end
        if not switcher.GetChildrenCount or not switcher.GetChildAt then
          return nil
        end
        local nChildren = switcher:GetChildrenCount()
        for i = 0, math.max(nChildren - 1, 0) do
          local child = switcher:GetChildAt(i)
          if child and slua.isValid(child) then
            if child == targetWidget then
              return i
            end
            
            local function searchDescendant(w, target, depth)
              if 5 < depth then
                return false
              end
              if w == target then
                return true
              end
              if not w.GetChildrenCount or not w.GetChildAt then
                return false
              end
              local nc = w:GetChildrenCount()
              for j = 0, math.max(nc - 1, 0) do
                local c = w:GetChildAt(j)
                if c and slua.isValid(c) and searchDescendant(c, target, depth + 1) then
                  return true
                end
              end
              return false
            end
            
            if searchDescendant(child, targetWidget, 0) then
              return i
            end
          end
        end
        return nil
      end
      
      for _, switcherName in ipairs({
        "Switcher_WeaponIcon",
        "WidgetSwitcher_Type",
        "WidgetSwitcher_Type2"
      }) do
        local ws = Container[switcherName]
        if ws and slua.isValid(ws) and ws.GetChildrenCount and ws.GetChildAt then
          local foundIdx = findWidgetInSwitcher(ws, ourWeaponIcon)
          if foundIdx and ws.SetActiveWidgetIndex then
            ws:SetActiveWidgetIndex(foundIdx)
            WidgetData._CachedSwitcherIndexes = WidgetData._CachedSwitcherIndexes or {}
            WidgetData._CachedSwitcherIndexes[switcherName] = foundIdx
          end
        end
      end
    end)
    pcall(function()
      local parent = ourWeaponIcon
      for depth = 0, 8 do
        if parent and slua.isValid(parent) and parent.GetParent then
          local p = parent:GetParent()
          if p and slua.isValid(p) then
            local pStr = tostring(p)
            if string.find(pStr, "WidgetSwitcher") and p.GetChildrenCount and p.GetChildAt then
              local nCh = p:GetChildrenCount()
              for i = 0, math.max(nCh - 1, 0) do
                local child = p:GetChildAt(i)
                if child and slua.isValid(child) then
                  local function isDescendant(w, target, d)
                    if 5 < d then
                      return false
                    end
                    if w == target then
                      return true
                    end
                    if not w.GetChildrenCount or not w.GetChildAt then
                      return false
                    end
                    local nc = w:GetChildrenCount()
                    for j = 0, math.max(nc - 1, 0) do
                      local c = w:GetChildAt(j)
                      if c and slua.isValid(c) and isDescendant(c, target, d + 1) then
                        return true
                      end
                    end
                    return false
                  end
                  
                  if isDescendant(child, ourWeaponIcon, 0) then
                    if p.SetActiveWidgetIndex then
                      p:SetActiveWidgetIndex(i)
                      WidgetData._CachedParentSwitchers = WidgetData._CachedParentSwitchers or {}
                      WidgetData._CachedParentSwitchers[tostring(p)] = {w = p, idx = i}
                    end
                    break
                  end
                end
              end
            end
            parent = p
          else
            break
          end
        else
          break
        end
      end
    end)
    pcall(function()
      local parent = ourWeaponIcon
      for depth = 0, 8 do
        pcall(function()
          if parent.GetParent then
            local p = parent:GetParent()
            if p and slua.isValid(p) then
              if p.SetWidgetVisibility then
                p:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
              end
              pcall(function()
                if p.SetRenderOpacity then
                  p:SetRenderOpacity(1.0)
                end
              end)
              pcall(function()
                if p.SetContentColorAndOpacity then
                  p:SetContentColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {
                    R = 1,
                    G = 1,
                    B = 1,
                    A = 1
                  })
                end
              end)
              pcall(function()
                if p.SetColorAndOpacity then
                  p:SetColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {
                    R = 1,
                    G = 1,
                    B = 1,
                    A = 1
                  })
                end
              end)
              pcall(function()
                if p.SetBrushTintColor then
                  p:SetBrushTintColor(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {
                    R = 1,
                    G = 1,
                    B = 1,
                    A = 1
                  })
                end
              end)
              pcall(function()
                local pBrush = p.Brush
                if pBrush and pBrush.TintColor then
                  pBrush.TintColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {
                    R = 1,
                    G = 1,
                    B = 1,
                    A = 1
                  }
                  if p.SetBrush then
                    p:SetBrush(pBrush)
                  end
                end
              end)
              pcall(function()
                if p.InvalidateLayout then
                  p:InvalidateLayout()
                end
              end)
              parent = p
            end
          end
        end)
      end
    end)
    pcall(function()
      if ourWeaponIcon.InvalidateLayout then
        ourWeaponIcon:InvalidateLayout()
      end
    end)
    pcall(function()
      if Container.UpdateWeapon then
        Container:UpdateWeapon()
      end
    end)
    pcall(function()
      if Container.RefreshWeapon then
        Container:RefreshWeapon()
      end
    end)
    WidgetData._LastWeaponID = winfo.WeaponID
    WidgetData._WeaponIconApplied = true
  end)
end

PlayerMapMarker._OBHeadWidgetClass = nil
PlayerMapMarker._OBHeadWidgetLoadFailed = false
PlayerMapMarker._bDumpedWidgetChildren = false

function PlayerMapMarker.CreateESPWidget()
  if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then
    return nil
  end
  if PlayerMapMarker._OBHeadWidgetLoadFailed then
    return nil
  end
  if not PlayerMapMarker._OBHeadWidgetClass then
    pcall(function()
      local Path = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP"
      local uClass = slua.loadClass(Path)
      if uClass then
        PlayerMapMarker._OBHeadWidgetClass = uClass
      end
    end)
    if not PlayerMapMarker._OBHeadWidgetClass then
      PlayerMapMarker._OBHeadWidgetLoadFailed = true
      return nil
    end
  else
    local bValid = false
    pcall(function()
      bValid = slua.isValid(PlayerMapMarker._OBHeadWidgetClass)
    end)
    if not bValid then
      PlayerMapMarker._OBHeadWidgetLoadFailed = true
      PlayerMapMarker._OBHeadWidgetClass = nil
      return nil
    end
  end
  local Widget
  pcall(function()
    local STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
    local PC = PlayerMapMarker.GetMyPlayerController()
    local OuterObj = IsValid(PC) and PC.Object or PlayerMapMarker.ESPCanvas
    Widget = STExtraBlueprintFunctionLibrary.CreateWidgetByClass(PlayerMapMarker._OBHeadWidgetClass, OuterObj)
  end)
  if not Widget then
    return nil
  end
  pcall(function()
    Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  pcall(function()
    Widget:SetRenderOpacity(1.0)
  end)
  local NameText, HealthFill
  local bIsOriginalProgressBar = false
  pcall(function()
    NameText = Widget.TextBlock_TeamName
    if NameText and slua.isValid(NameText) then
      pcall(function()
        NameText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    end
    if Widget.TextBlock_PlayerName and slua.isValid(Widget.TextBlock_PlayerName) then
      pcall(function()
        Widget.TextBlock_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    end
    local WS_Type = Widget.WidgetSwitcher_Type
    local WS_Type2 = Widget.WidgetSwitcher_Type2
    if WS_Type and slua.isValid(WS_Type) then
      pcall(function()
        if WS_Type.SetActiveWidgetIndex then
          WS_Type:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherTypeIndex)
        end
      end)
    end
    if WS_Type2 and slua.isValid(WS_Type2) then
      pcall(function()
        if WS_Type2.SetActiveWidgetIndex then
          WS_Type2:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherType2Index)
        end
      end)
    end
    local SizeBox_HP = Widget.SizeBox_HP
    if SizeBox_HP and slua.isValid(SizeBox_HP) then
      pcall(function()
        SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
      pcall(function()
        SizeBox_HP:SetHeightOverride(6)
      end)
      pcall(function()
        SizeBox_HP:SetWidthOverride(100)
      end)
      local ExistingChild
      pcall(function()
        if SizeBox_HP.GetContent then
          ExistingChild = SizeBox_HP:GetContent()
        end
      end)
      if not ExistingChild then
        pcall(function()
          if SizeBox_HP.GetChildAt then
            ExistingChild = SizeBox_HP:GetChildAt(0)
          end
        end)
      end
      if ExistingChild and slua.isValid(ExistingChild) then
        pcall(function()
          ExistingChild:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        pcall(function()
          ExistingChild:SetRenderOpacity(1.0)
        end)
        local FoundPB = PlayerMapMarker.FindProgressBarInWidget(ExistingChild, 0, 5)
        if FoundPB and slua.isValid(FoundPB) then
          HealthFill = FoundPB
          bIsOriginalProgressBar = true
          pcall(function()
            FoundPB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
          end)
          pcall(function()
            FoundPB:SetRenderOpacity(1.0)
          end)
        else
          do
            local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", ExistingChild)
            if PB then
              pcall(function()
                PB:SetFillColorAndOpacity(FLinearColor and FLinearColor(1, 1, 1, 1) or {
                  R = 1,
                  G = 1,
                  B = 1,
                  A = 1
                })
              end)
              pcall(function()
                PB:SetPercent(1.0)
              end)
              pcall(function()
                PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
              end)
              pcall(function()
                PB:SetRenderOpacity(1.0)
              end)
              pcall(function()
                PB:SetDesiredSizeOverride(FVector2D and FVector2D(100, 6) or {X = 100, Y = 6})
              end)
              pcall(function()
                ExistingChild:AddChild(PB)
              end)
              HealthFill = PB
            end
          end
        end
      else
        do
          local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", SizeBox_HP)
          if PB then
            pcall(function()
              PB:SetFillColorAndOpacity(FLinearColor and FLinearColor(1, 1, 1, 1) or {
                R = 1,
                G = 1,
                B = 1,
                A = 1
              })
            end)
            pcall(function()
              PB:SetPercent(1.0)
            end)
            pcall(function()
              PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            pcall(function()
              PB:SetRenderOpacity(1.0)
            end)
            pcall(function()
              PB:SetDesiredSizeOverride(FVector2D and FVector2D(100, 6) or {X = 100, Y = 6})
            end)
            do
              local bUsedSetContent = false
              pcall(function()
                if SizeBox_HP.SetContent then
                  SizeBox_HP:SetContent(PB)
                  bUsedSetContent = true
                end
              end)
              if not bUsedSetContent then
                pcall(function()
                  SizeBox_HP:AddChild(PB)
                end)
              end
              HealthFill = PB
            end
          end
        end
      end
    end
  end)
  local WidgetData = {
    Container = Widget,
    NameText = NameText,
    HealthFill = HealthFill,
    IsGameWidget = true,
    IsOriginalProgressBar = bIsOriginalProgressBar,
    HasChildren = NameText ~= nil
  }
  return WidgetData
end

PlayerMapMarker._CanvasScaleX = 1.0
PlayerMapMarker._CanvasScaleY = 1.0
PlayerMapMarker._CanvasOffsetX = 0.0
PlayerMapMarker._CanvasOffsetY = 0.0

function PlayerMapMarker.UpdateCanvasTransform(PC)
  if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then
    return
  end
  local success = false
  pcall(function()
    local SBL = SlateBlueprintLibrary
    if SBL and SBL.AbsoluteToLocal then
      local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
      if cg then
        local pt0 = SBL.AbsoluteToLocal(cg, FVector2D and FVector2D(0, 0) or {X = 0, Y = 0})
        local pt1 = SBL.AbsoluteToLocal(cg, FVector2D and FVector2D(100, 100) or {X = 100, Y = 100})
        if pt0 and pt1 then
          PlayerMapMarker._CanvasScaleX = (pt1.X - pt0.X) / 100
          PlayerMapMarker._CanvasScaleY = (pt1.Y - pt0.Y) / 100
          PlayerMapMarker._CanvasOffsetX = pt0.X
          PlayerMapMarker._CanvasOffsetY = pt0.Y
          success = true
        end
      end
    end
  end)
  if not success then
    pcall(function()
      local WLL = WidgetLayoutLibrary
      if WLL and WLL.ScreenToWidgetLocal then
        local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
        if cg then
          local pt0 = FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
          local pt1 = FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
          WLL.ScreenToWidgetLocal(PC, cg, FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}, pt0)
          WLL.ScreenToWidgetLocal(PC, cg, FVector2D and FVector2D(100, 100) or {X = 100, Y = 100}, pt1)
          PlayerMapMarker._CanvasScaleX = (pt1.X - pt0.X) / 100
          PlayerMapMarker._CanvasScaleY = (pt1.Y - pt0.Y) / 100
          PlayerMapMarker._CanvasOffsetX = pt0.X
          PlayerMapMarker._CanvasOffsetY = pt0.Y
          success = true
        end
      end
    end)
  end
  if not success then
    local scale = 1.0
    local WLL = WidgetLayoutLibrary
    if WLL and WLL.GetViewportScale then
      scale = WLL.GetViewportScale(PC) or 1.0
    end
    PlayerMapMarker._CanvasScaleX = 1.0 / scale
    PlayerMapMarker._CanvasScaleY = 1.0 / scale
    PlayerMapMarker._CanvasOffsetX = 0
    PlayerMapMarker._CanvasOffsetY = 0
  end
end

function PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
  if not ScreenPixelPos then
    return FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
  end
  local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
  local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
  local offsetX = PlayerMapMarker._CanvasOffsetX or 0
  local offsetY = PlayerMapMarker._CanvasOffsetY or 0
  return FVector2D and FVector2D(ScreenPixelPos.X * scaleX + offsetX, ScreenPixelPos.Y * scaleY + offsetY) or {
    X = ScreenPixelPos.X * scaleX + offsetX,
    Y = ScreenPixelPos.Y * scaleY + offsetY
  }
end

function PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
  if not IsValid(PC) or not WorldLoc then
    return false, FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
  end
  local ScreenPixelPos = FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
  local bOK = false
  pcall(function()
    local res = PC:ProjectWorldLocationToScreen(WorldLoc, ScreenPixelPos, true)
    if res == true or res == 1 or ScreenPixelPos and (ScreenPixelPos.X ~= 0 or ScreenPixelPos.Y ~= 0) then
      bOK = true
    end
  end)
  if not (bOK and ScreenPixelPos) or ScreenPixelPos.X == 0 and ScreenPixelPos.Y == 0 then
    return false, FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
  end
  local CanvasLocalPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
  return true, CanvasLocalPos
end

function PlayerMapMarker.GetDynamicViewportSize(PC)
  local width, height = 0, 0
  if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
    pcall(function()
      local cg = PlayerMapMarker.ESPCanvas:GetCachedGeometry()
      if cg and cg.GetLocalSize then
        local sz = cg:GetLocalSize()
        if sz and sz.X and sz.X > 200 then
          width = sz.X
          height = sz.Y
        end
      end
    end)
  end
  if 200 < width then
    return width, height
  end
  pcall(function()
    local WLL = WidgetLayoutLibrary
    if WLL and WLL.GetViewportSize then
      local sz = WLL.GetViewportSize(PC or PlayerMapMarker.GetMyPlayerController())
      if sz and sz.X and sz.X > 200 then
        width = sz.X
        height = sz.Y
      end
    end
  end)
  if 200 < width then
    pcall(function()
      local WLL = WidgetLayoutLibrary
      if WLL and WLL.GetViewportScale then
        local scale = WLL.GetViewportScale(PC or PlayerMapMarker.GetMyPlayerController())
        if scale and type(scale) == "number" and 0 < scale and scale ~= 1.0 then
          width = width / scale
          height = height / scale
        end
      end
    end)
    return width, height
  end
  return PlayerMapMarker._cachedViewportW or 1920, PlayerMapMarker._cachedViewportH or 1080
end

function PlayerMapMarker.UpdateESPPositionWithPC(Widget, WorldLoc, PC, CanvasPos)
  if not Widget or not IsValid(PC) then
    return false
  end
  local Container = Widget.Container or Widget
  local bOnScreen = true
  if not CanvasPos then
    if not WorldLoc then
      return false
    end
    bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
  end
  if not bOnScreen then
    pcall(function()
      Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
    end)
    return false
  end
  pcall(function()
    if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
      local ptr = tostring(Container)
      local Slot = PlayerMapMarker.ESPWidgetPtrs[ptr]
      if not (Slot and slua.isValid(Slot)) or type(Slot) == "boolean" then
        local addedSlot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Container)
        if addedSlot and slua.isValid(addedSlot) then
          Slot = addedSlot
          PlayerMapMarker.ESPWidgetPtrs[ptr] = addedSlot
          if type(Widget) == "table" then
            Widget.Slot = addedSlot
          end
          pcall(function()
            Slot:SetAutoSize(true)
          end)
          pcall(function()
            Slot.bAutoSize = true
          end)
          local align = FVector2D and FVector2D(0.5, 1.0) or {X = 0.5, Y = 1.0}
          pcall(function()
            Slot.Alignment = align
          end)
          pcall(function()
            Slot:SetAlignment(align)
          end)
          pcall(function()
            Slot:SetAlignment(0.5, 1.0)
          end)
          pcall(function()
            Slot:SetZOrder(PlayerMapMarker.ESPWidgetZOrder or 20)
          end)
        end
      end
      local bShowAnyUI = _G.LexusConfig.Esp9_Name or _G.LexusConfig.Esp9_Distance or _G.LexusConfig.Esp9_HP or _G.LexusConfig.Esp9_Team or _G.LexusConfig.Esp9_Weapon
      if bShowAnyUI then
        Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      else
        Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      end
      if not Widget._OffsetResetDone then
        pcall(function()
          Container:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X = 0, Y = 0})
        end)
        pcall(function()
          Container:SetRenderScale(FVector2D and FVector2D(0.9, 0.9) or {X = 0.9, Y = 0.9})
        end)
        if Widget and type(Widget) == "table" then
          if Widget.NameText and slua.isValid(Widget.NameText) then
            pcall(function()
              Widget.NameText:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X = 0, Y = 0})
            end)
          end
          if Widget.HealthFill and slua.isValid(Widget.HealthFill) then
            pcall(function()
              Widget.HealthFill:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X = 0, Y = 0})
            end)
          end
        end
        pcall(function()
          Container.RenderTransformPivot = FVector2D and FVector2D(0.5, 1.0) or {X = 0.5, Y = 1.0}
        end)
        pcall(function()
          Container:SetRenderTransformPivot(FVector2D and FVector2D(0.5, 1.0) or {X = 0.5, Y = 1.0})
        end)
        Widget._OffsetResetDone = true
      end
      if not (Slot and slua.isValid(Slot)) or Slot == PlayerMapMarker.ESPCanvas then
        if Widget and type(Widget) == "table" and Widget.Slot and slua.isValid(Widget.Slot) then
          Slot = Widget.Slot
        elseif Container.Slot and slua.isValid(Container.Slot) then
          Slot = Container.Slot
        end
      end
      if Slot and slua.isValid(Slot) and Slot ~= PlayerMapMarker.ESPCanvas then
        do
          local finalX = CanvasPos.X + (PlayerMapMarker.ESPAnchorOffsetX or 0)
          local finalY = CanvasPos.Y + (PlayerMapMarker.ESPAnchorOffsetY or 0)
          if Widget and type(Widget) == "table" then
            if not Widget._CachedPosVec then
              Widget._CachedPosVec = FVector2D and FVector2D(finalX, finalY) or {X = finalX, Y = finalY}
            else
              Widget._CachedPosVec.X = finalX
              Widget._CachedPosVec.Y = finalY
            end
            pcall(function()
              Slot:SetPosition(Widget._CachedPosVec)
            end)
          else
            pcall(function()
              Slot:SetPosition(FVector2D and FVector2D(finalX, finalY) or {X = finalX, Y = finalY})
            end)
          end
        end
      end
    end
  end)
  return true
end

function PlayerMapMarker.UpdateESPText(Widget, Text)
  if not Widget then
    return
  end
  if Widget._LastESPText == Text then
    return
  end
  Widget._LastESPText = Text
  
  local function applyTextAndCenter(w, txt)
    if not w or not slua.isValid(w) then
      return
    end
    if txt == "" then
      pcall(function()
        w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      end)
      return
    else
      pcall(function()
        w:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      end)
    end
    pcall(function()
      w:SetText(txt)
    end)
    pcall(function()
      local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
      local redColor = FLinearColor and FLinearColor(1.0, 0.0, 0.0, 1.0) or {
        R = 255,
        G = 0,
        B = 0,
        A = 255
      }
      if w.SetColorAndOpacity then
        if FSlateColor then
          w:SetColorAndOpacity(FSlateColor(redColor))
        else
          w:SetColorAndOpacity(redColor)
        end
      end
    end)
    pcall(function()
      if w.SetJustification then
        w:SetJustification(1)
      end
    end)
    pcall(function()
      local slot = w.Slot
      if slot and slot.SetHorizontalAlignment then
        slot:SetHorizontalAlignment(1)
      end
    end)
    pcall(function()
      w:SetRenderTranslation(FVector2D and FVector2D(PlayerMapMarker.ESPTextOffsetX or 0, PlayerMapMarker.ESPTextOffsetY or 0) or {
        X = PlayerMapMarker.ESPTextOffsetX or 0,
        Y = PlayerMapMarker.ESPTextOffsetY or 0
      })
    end)
  end
  
  if Widget.NameText and slua.isValid(Widget.NameText) then
    applyTextAndCenter(Widget.NameText, Text)
  end
  if Widget.IsGameWidget and Widget.Container then
    pcall(function()
      local W = Widget.Container
      if W and slua.isValid(W) then
        if W.SetPlayerName then
          local Name = Text
          local idx = string.find(Text, " %[")
          if idx then
            Name = string.sub(Text, 1, idx - 1)
          end
          W:SetPlayerName(Name)
        end
        applyTextAndCenter(W.TextBlock_TeamName, Text)
        applyTextAndCenter(W.TextBlock_PlayerName, Text)
        pcall(function()
          if not Widget._CachedVBChildren then
            local list = {}
            local VB = PlayerMapMarker._FindNamedWidgetInTree(W, "VerticalBox_0", 8)
            if VB and slua.isValid(VB) and VB.GetChildrenCount then
              local nChildren = VB:GetChildrenCount()
              for i = 0, nChildren - 1 do
                local child = VB:GetChildAt(i)
                if child and slua.isValid(child) and child.SetText then
                  table.insert(list, child)
                end
              end
            end
            Widget._CachedVBChildren = list
          end
          for _, child in ipairs(Widget._CachedVBChildren) do
            applyTextAndCenter(child, Text)
          end
        end)
        pcall(function()
          if not Widget._CachedHBChildren then
            local list = {}
            local HB = PlayerMapMarker._FindNamedWidgetInTree(W, "HorizontalBox_TeamName", 8)
            if HB and slua.isValid(HB) and HB.GetChildrenCount then
              local nChildren = HB:GetChildrenCount()
              for i = 0, nChildren - 1 do
                local child = HB:GetChildAt(i)
                if child and slua.isValid(child) and child.SetText then
                  table.insert(list, child)
                end
              end
            end
            Widget._CachedHBChildren = list
          end
          for _, child in ipairs(Widget._CachedHBChildren) do
            applyTextAndCenter(child, Text)
          end
        end)
      end
    end)
  end
end

function PlayerMapMarker.UpdateESPHealth(Widget, pct)
  if not Widget then
    return
  end
  Widget.LastPct = pct
  local bShowHP = _G.LexusConfig.Esp9_HP
  if PlayerMapMarker.bForceSwitcherIndexEveryUpdate and Widget.Container then
    pcall(function()
      local W = Widget.Container
      if W and slua.isValid(W) then
        if W.WidgetSwitcher_Type and slua.isValid(W.WidgetSwitcher_Type) then
          pcall(function()
            if W.WidgetSwitcher_Type.SetActiveWidgetIndex then
              W.WidgetSwitcher_Type:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherTypeIndex)
            end
          end)
        end
        if W.WidgetSwitcher_Type2 and slua.isValid(W.WidgetSwitcher_Type2) then
          pcall(function()
            if W.WidgetSwitcher_Type2.SetActiveWidgetIndex then
              W.WidgetSwitcher_Type2:SetActiveWidgetIndex(PlayerMapMarker.HPWidgetSwitcherType2Index)
            end
          end)
        end
        if W.SizeBox_HP and slua.isValid(W.SizeBox_HP) then
          if bShowHP then
            W.SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
          else
            W.SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
          end
        end
      end
    end)
  end
  if not bShowHP then
    return
  end
  if Widget.HealthFill then
    local bValid = false
    pcall(function()
      bValid = slua.isValid(Widget.HealthFill)
    end)
    if bValid then
      local bHasSetPercent = false
      pcall(function()
        bHasSetPercent = Widget.HealthFill.SetPercent ~= nil
      end)
      if not bHasSetPercent then
        local PB = PlayerMapMarker.FindProgressBarInWidget(Widget.HealthFill, 0, 5)
        if PB and slua.isValid(PB) then
          Widget.HealthFill = PB
        else
          return
        end
      end
      pcall(function()
        if Widget.HealthFill.SetWidgetVisibility then
          Widget.HealthFill:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end
        if Widget.HealthFill.SetRenderOpacity then
          Widget.HealthFill:SetRenderOpacity(1.0)
        end
        if Widget.HealthFill.SetPercent then
          Widget.HealthFill:SetPercent(pct)
          local color
          if 0.5 < pct then
            color = FLinearColor and FLinearColor(0.0, 1.0, 0.0, 1.0) or {
              R = 0,
              G = 255,
              B = 0,
              A = 255
            }
          elseif 0.25 < pct then
            color = FLinearColor and FLinearColor(1.0, 0.5, 0.0, 1.0) or {
              R = 255,
              G = 128,
              B = 0,
              A = 255
            }
          else
            color = FLinearColor and FLinearColor(1.0, 0.0, 0.0, 1.0) or {
              R = 255,
              G = 0,
              B = 0,
              A = 255
            }
          end
          if Widget.HealthFill.SetFillColorAndOpacity then
            Widget.HealthFill:SetFillColorAndOpacity(color)
          end
          pcall(function()
            if Widget.IsOriginalProgressBar then
              local style = Widget.HealthFill.WidgetStyle
              if style and style.FillImage then
                style.FillImage.TintColor = color
                Widget.HealthFill:SetWidgetStyle(style)
              end
            end
          end)
        end
      end)
    end
    return
  end
end

function PlayerMapMarker.RemoveESPWidget(Widget, KeyStr)
  if not Widget then
    return
  end
  local Container = Widget.Container or Widget
  pcall(function()
    local ptr = tostring(Container)
    PlayerMapMarker.ESPWidgetPtrs[ptr] = nil
    Container:RemoveFromParent()
    Container:ConditionalBeginDestroy()
  end)
  if KeyStr then
    PlayerMapMarker.RemoveSnapLine(KeyStr)
  end
end

function PlayerMapMarker.CreateSnapLine()
  if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then
    return nil
  end
  local Border
  pcall(function()
    Border = CGame:NewObjectFromPath("/Script/UMG.Border", PlayerMapMarker.ESPCanvas)
  end)
  if not Border or not slua.isValid(Border) then
    return nil
  end
  local color = PlayerMapMarker.SnapLineColor or FLinearColor and FLinearColor(1.0, 1.0, 1.0, PlayerMapMarker.SnapLineOpacity or 0.9) or {
    R = 1,
    G = 1,
    B = 1,
    A = PlayerMapMarker.SnapLineOpacity or 0.9
  }
  pcall(function()
    Border:SetBrushColor(color)
  end)
  pcall(function()
    Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  pcall(function()
    Border.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X = 0, Y = 0.5}
  end)
  pcall(function()
    Border:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X = 0, Y = 0.5})
  end)
  local Slot
  pcall(function()
    Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
    if Slot then
      Slot:SetAutoSize(false)
      Slot:SetZOrder(1)
    end
  end)
  return {Widget = Border, Slot = Slot}
end

function PlayerMapMarker.GetSnapLineStartPos(PC)
  local screenPixelW, screenPixelH = 0, 0
  local scale = 1.0
  pcall(function()
    if PC and PC.GetViewportSize then
      local vs = FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
      PC:GetViewportSize(vs)
      if vs and vs.X and vs.X > 200 then
        screenPixelW = vs.X
        screenPixelH = vs.Y
      end
    end
  end)
  if screenPixelW <= 200 then
    pcall(function()
      local WLL = WidgetLayoutLibrary
      if WLL and WLL.GetViewportSize then
        local vs = WLL.GetViewportSize(PC)
        if vs and vs.X and vs.X > 200 then
          screenPixelW = vs.X
          screenPixelH = vs.Y
        end
      end
    end)
  end
  pcall(function()
    local WLL = WidgetLayoutLibrary
    if WLL and WLL.GetViewportScale then
      local s = WLL.GetViewportScale(PC)
      if s and type(s) == "number" and 0 < s then
        scale = s
      end
    end
  end)
  if screenPixelW <= 200 then
    screenPixelW = (PlayerMapMarker._cachedViewportW or 1920) * scale
    screenPixelH = (PlayerMapMarker._cachedViewportH or 1080) * scale
  end
  if not PlayerMapMarker._CachedTopCenterPixel then
    PlayerMapMarker._CachedTopCenterPixel = FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
  end
  PlayerMapMarker._CachedTopCenterPixel.X = screenPixelW / 2.0
  PlayerMapMarker._CachedTopCenterPixel.Y = (PlayerMapMarker.SnapLineOriginY or 50) * scale
  local fromCanvasPos = PlayerMapMarker.ScreenPixelToCanvasLocal(PC, PlayerMapMarker._CachedTopCenterPixel)
  local fromX = fromCanvasPos.X + (PlayerMapMarker.SnapLineOriginOffsetX or 0)
  local fromY = fromCanvasPos.Y
  return fromX, fromY
end

function PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
  if not PlayerMapMarker.bUseSnapLines then
    return
  end
  if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then
    return
  end
  local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]
  if not bOnScreen or not CanvasPos then
    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
      pcall(function()
        LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
      end)
    end
    return
  end
  local bIsNew = false
  if not LineData then
    LineData = PlayerMapMarker.CreateSnapLine()
    if not (LineData and LineData.Widget) or not LineData.Slot then
      return
    end
    PlayerMapMarker.SnapLineWidgets[KeyStr] = LineData
    bIsNew = true
  end
  local Widget = LineData.Widget
  local Slot = LineData.Slot
  pcall(function()
    Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
  if not LineData._PivotSet then
    pcall(function()
      Widget.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X = 0, Y = 0.5}
    end)
    pcall(function()
      Widget:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X = 0, Y = 0.5})
    end)
    LineData._PivotSet = true
  end
  local ESPData = PlayerMapMarker.ESPWidgets[KeyStr]
  local Character = ESPData and ESPData.Character
  local PC = PlayerMapMarker.GetMyPlayerController()
  local bIsVisible = false
  if Character and slua.isValid(Character) and PC and slua.isValid(PC) then
    pcall(function()
      if PC.LineOfSightTo then
        if not PlayerMapMarker._ZeroVector then
          local VT = FVector or import("/Script/CoreUObject.Vector")
          if VT then
            PlayerMapMarker._ZeroVector = VT(0, 0, 0)
          end
        end
        if PlayerMapMarker._ZeroVector then
          bIsVisible = PC:LineOfSightTo(Character, PlayerMapMarker._ZeroVector, false)
        end
      end
    end)
  end
  local opacity = PlayerMapMarker.SnapLineOpacity or 0.7
  local lineColor
  if bIsVisible then
    lineColor = FLinearColor and FLinearColor(0.0, 1.0, 0.0, opacity) or {
      R = 0,
      G = 255,
      B = 0,
      A = math.floor(opacity * 255)
    }
  else
    lineColor = FLinearColor and FLinearColor(1.0, 0.0, 0.0, opacity) or {
      R = 255,
      G = 0,
      B = 0,
      A = math.floor(opacity * 255)
    }
  end
  pcall(function()
    Widget:SetBrushColor(lineColor)
  end)
  local toX = CanvasPos.X + (PlayerMapMarker.SnapLineHeadOffsetX or 0)
  local toY = CanvasPos.Y + (PlayerMapMarker.SnapLineHeadOffsetY or 0)
  local dx = toX - fromX
  local dy = toY - fromY
  local length = math.sqrt(dx * dx + dy * dy)
  local thickness = PlayerMapMarker.SnapLineThickness or 1.65
  local angle_rad = 0
  if math.atan2 then
    angle_rad = math.atan2(dy, dx)
  else
    angle_rad = math.atan(dy, dx)
  end
  local angle = angle_rad * (180.0 / math.pi)
  if not LineData._CachedPosVec then
    LineData._CachedPosVec = FVector2D and FVector2D(fromX, fromY - thickness / 2.0) or {
      X = fromX,
      Y = fromY - thickness / 2.0
    }
    LineData._CachedSizeVec = FVector2D and FVector2D(length, thickness) or {X = length, Y = thickness}
  else
    LineData._CachedPosVec.X = fromX
    LineData._CachedPosVec.Y = fromY - thickness / 2.0
    LineData._CachedSizeVec.X = length
    LineData._CachedSizeVec.Y = thickness
  end
  pcall(function()
    Slot:SetPosition(LineData._CachedPosVec)
    Slot:SetSize(LineData._CachedSizeVec)
    if bIsNew then
      Slot:SetZOrder(1)
    end
  end)
  pcall(function()
    Widget:SetRenderAngle(angle)
  end)
end

function PlayerMapMarker.RemoveSnapLine(KeyStr)
  local LineData = PlayerMapMarker.SnapLineWidgets[KeyStr]
  if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
    pcall(function()
      LineData.Widget:RemoveFromParent()
      LineData.Widget:ConditionalBeginDestroy()
    end)
    PlayerMapMarker.SnapLineWidgets[KeyStr] = nil
  end
end

function PlayerMapMarker.ClearAllSnapLines()
  for KeyStr, LineData in pairs(PlayerMapMarker.SnapLineWidgets) do
    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
      pcall(function()
        LineData.Widget:RemoveFromParent()
        LineData.Widget:ConditionalBeginDestroy()
      end)
    end
  end
  PlayerMapMarker.SnapLineWidgets = {}
end

function PlayerMapMarker.ScreenPixelToCanvasLocalRaw(PC, screenX, screenY)
  local scaleX = PlayerMapMarker._CanvasScaleX or 1.0
  local scaleY = PlayerMapMarker._CanvasScaleY or 1.0
  local offsetX = PlayerMapMarker._CanvasOffsetX or 0
  local offsetY = PlayerMapMarker._CanvasOffsetY or 0
  return screenX * scaleX + offsetX, screenY * scaleY + offsetY
end

function PlayerMapMarker.ProjectWorldToCanvasLocalRaw(PC, WorldLoc)
  if not IsValid(PC) or not WorldLoc then
    return false, 0, 0
  end
  if not PlayerMapMarker._tempScreenPixelPos then
    PlayerMapMarker._tempScreenPixelPos = FVector2D and FVector2D(0, 0) or {X = 0, Y = 0}
  end
  local tempPos = PlayerMapMarker._tempScreenPixelPos
  local bOK = false
  pcall(function()
    local res = PC:ProjectWorldLocationToScreen(WorldLoc, tempPos, true)
    if res == true or res == 1 then
      bOK = true
    end
  end)
  if not bOK or tempPos.X == 0 and tempPos.Y == 0 then
    return false, 0, 0
  end
  local canvasX, canvasY = PlayerMapMarker.ScreenPixelToCanvasLocalRaw(PC, tempPos.X, tempPos.Y)
  return true, canvasX, canvasY
end

function PlayerMapMarker.GetBoneLocationWithFallback(Character, PrimaryBoneName)
  if not IsValid(Character) or not PrimaryBoneName then
    return nil
  end
  if Character._cachedBoneNames and Character._cachedBoneNames[PrimaryBoneName] then
    local cachedName = Character._cachedBoneNames[PrimaryBoneName]
    local loc
    pcall(function()
      local Mesh = PlayerMapMarker.GetCharacterMesh(Character)
      if Mesh and Game:IsValid(Mesh) then
        if Mesh.GetSocketLocation then
          loc = Mesh:GetSocketLocation(cachedName)
        elseif Mesh.GetBoneLocation then
          loc = Mesh:GetBoneLocation(cachedName)
        end
      end
    end)
    if loc then
      return loc
    end
  end
  local fallbacks = PlayerMapMarker.BoneNameFallbacks[PrimaryBoneName] or {PrimaryBoneName}
  for _, bname in ipairs(fallbacks) do
    local loc
    pcall(function()
      local Mesh = PlayerMapMarker.GetCharacterMesh(Character)
      if Mesh and Game:IsValid(Mesh) then
        if Mesh.GetSocketLocation then
          loc = Mesh:GetSocketLocation(bname)
        elseif Mesh.GetBoneLocation then
          loc = Mesh:GetBoneLocation(bname)
        end
      end
    end)
    if loc then
      if not Character._cachedBoneNames then
        Character._cachedBoneNames = {}
      end
      Character._cachedBoneNames[PrimaryBoneName] = bname
      return loc
    end
  end
  return nil
end

function PlayerMapMarker.IsPlayerVisible(PC, Character)
  if not IsValid(PC) or not IsValid(Character) then
    return false
  end
  local now = os.clock()
  if Character._lastVisTime and now - Character._lastVisTime < 0.15 then
    return Character._cachedIsVisible or false
  end
  Character._lastVisTime = now
  local bVis = false
  pcall(function()
    if PC.LineOfSightTo then
      if not PlayerMapMarker._ZeroVector then
        local VT = FVector or import("/Script/CoreUObject.Vector")
        if VT then
          PlayerMapMarker._ZeroVector = VT(0, 0, 0)
        end
      end
      bVis = PC:LineOfSightTo(Character, PlayerMapMarker._ZeroVector, false)
    end
  end)
  if not bVis then
    local KismetSystemLibrary = import("KismetSystemLibrary")
    if KismetSystemLibrary and KismetSystemLibrary.LineTraceSingle then
      pcall(function()
        local camMgr
        local GameplayStatics = import("GameplayStatics")
        if GameplayStatics and GameplayStatics.GetPlayerCameraManager then
          camMgr = GameplayStatics.GetPlayerCameraManager(PC, 0)
        end
        local startLoc = camMgr and camMgr:GetCameraLocation() or PlayerMapMarker.GetMyLocation()
        local headLoc = PlayerMapMarker.GetBoneLocationWithFallback(Character, "head")
        if startLoc and headLoc then
          if not PlayerMapMarker._CachedHitResult then
            local HitResultClass = import("HitResult") or import("/Script/Engine.HitResult")
            PlayerMapMarker._CachedHitResult = HitResultClass and HitResultClass() or {}
          end
          local bHit = KismetSystemLibrary.LineTraceSingle(PC, startLoc, headLoc, 0, false, nil, 0, PlayerMapMarker._CachedHitResult, true)
          if bHit then
            local hitActor
            if type(PlayerMapMarker._CachedHitResult.GetActor) == "function" then
              hitActor = PlayerMapMarker._CachedHitResult:GetActor()
            elseif PlayerMapMarker._CachedHitResult.Actor then
              hitActor = PlayerMapMarker._CachedHitResult.Actor
            end
            if hitActor and (hitActor == Character or type(hitActor.IsChildOf) == "function" and hitActor:IsChildOf(Character)) then
              bVis = true
            end
          else
            bVis = true
          end
        end
      end)
    end
  end
  Character._cachedIsVisible = bVis
  return bVis
end

function PlayerMapMarker.ClearAllESP()
  RedBoxOverlay.Stop()
  for KeyStr, Data in pairs(PlayerMapMarker.ESPWidgets) do
    PlayerMapMarker.RemoveESPWidget(Data.Widget, KeyStr)
  end
  PlayerMapMarker.ESPWidgets = {}
  PlayerMapMarker.ESPWidgetPtrs = {}
  PlayerMapMarker.ClearAllSnapLines()
  if PlayerMapMarker.ESPCanvas and Game:IsValid(PlayerMapMarker.ESPCanvas) then
    pcall(function()
      local n = PlayerMapMarker.ESPCanvas:GetChildrenCount()
      for i = n - 1, 0, -1 do
        local child = PlayerMapMarker.ESPCanvas:GetChildAt(i)
        if child and slua.isValid(child) and PlayerMapMarker.IsOurESPWidget(child) then
          PlayerMapMarker.ESPCanvas:RemoveChild(child)
        end
      end
    end)
  end
  PlayerMapMarker.ESPCanvas = nil
  PlayerMapMarker._OBHeadWidgetClass = nil
  PlayerMapMarker._OBHeadWidgetLoadFailed = false
  PlayerMapMarker._bDumpedWidgetChildren = false
  PlayerMapMarker._cachedViewportW = 1920
  PlayerMapMarker._cachedViewportH = 1080
end

function PlayerMapMarker.UpdateESP(AllPlayers, MyLoc)
  if not PlayerMapMarker.bUseScreenESP then
    return
  end
  PlayerMapMarker.bUseSnapLines = _G.LexusConfig.Esp9_Line
  if not PlayerMapMarker.InitESPCanvas() then
    return
  end
  if PlayerMapMarker._OBHeadWidgetLoadFailed then
    return
  end
  local PC = PlayerMapMarker.GetMyPlayerController()
  if IsValid(PC) then
    PlayerMapMarker.UpdateCanvasTransform(PC)
  end
  local fromX, fromY = 0, 0
  if PlayerMapMarker.bUseSnapLines and IsValid(PC) then
    fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
  end
  local MyKey = PlayerMapMarker.GetMyPlayerKey()
  local SeenKeys = {}
  local MyChar
  pcall(function()
    local GDP = PlayerMapMarker.GetGameplayData()
    if GDP and GDP.GetLocalCharacter then
      MyChar = GDP.GetLocalCharacter()
    elseif PC and PC.GetPawn then
      MyChar = PC:GetPawn()
    end
  end)
  local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)
  for PlayerKey, Character in pairs(AllPlayers) do
    if IsValid(Character) then
      local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
      local bIsAI = PlayerMapMarker.IsAI(Character)
      local KeyStr = tostring(PlayerKey)
      local Name = PlayerMapMarker.GetPlayerName(Character)
      local Loc = PlayerMapMarker.GetESPLocation(Character)
      local DistStr = ""
      if MyLoc and Loc then
        DistStr = PlayerMapMarker.GetDistanceString(MyLoc, Loc)
      end
      local bSkip = false
      if bIsMe and not PlayerMapMarker.bIncludeMe then
        bSkip = true
      end
      if bIsAI and not PlayerMapMarker.bIncludeAI then
        bSkip = true
      end
      local TeamID = PlayerMapMarker.GetTeamID(Character)
      if MyTeamID ~= nil and TeamID == MyTeamID and not bIsMe then
        bSkip = true
      end
      local bIsAlive = PlayerMapMarker.IsAlive(Character)
      if not bSkip and Loc then
        SeenKeys[KeyStr] = true
        local ESPData = PlayerMapMarker.ESPWidgets[KeyStr]
        local Text = ""
        if _G.LexusConfig.Esp9_Name then
          Text = Name
        end
        if _G.LexusConfig.Esp9_Distance and DistStr and DistStr ~= "" then
          if Text ~= "" then
            Text = string.format("%s [%s]", Text, DistStr)
          else
            Text = string.format("[%s]", DistStr)
          end
        end
        local bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, Loc)
        if not ESPData then
          local Widget = PlayerMapMarker.CreateESPWidget()
          if Widget then
            PlayerMapMarker.ESPWidgets[KeyStr] = {
              Widget = Widget,
              Character = Character,
              Name = Name,
              LastDistStr = DistStr,
              TeamID = TeamID
            }
            PlayerMapMarker.UpdateESPText(Widget, Text)
            if bIsAlive then
              PlayerMapMarker.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
              PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
              local HP = Character.Health or 0
              local MaxHP = Character.MaxHealth or 120
              local pct = 0
              if 0 < HP and 0 < MaxHP then
                pct = HP / MaxHP
                if 1 < pct then
                  pct = 1
                end
                if pct < 0 then
                  pct = 0
                end
              end
              PlayerMapMarker.UpdateESPHealth(Widget, pct)
              PlayerMapMarker.AddWeaponIconToESP(Widget, Character)
              if PlayerMapMarker.bUseSnapLines then
                PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
              else
                PlayerMapMarker.RemoveSnapLine(KeyStr)
              end
            else
              local Container = Widget.Container or Widget
              pcall(function()
                Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
              end)
              PlayerMapMarker.UpdateESPHealth(Widget, 0)
              PlayerMapMarker.RemoveSnapLine(KeyStr)
            end
          end
        else
          ESPData.Character = Character
          ESPData.Name = Name
          ESPData.LastDistStr = DistStr
          if bIsAlive then
            ESPData.TeamID = TeamID
            PlayerMapMarker.ApplyTeamColor(ESPData.Widget, TeamID)
            ESPData.Widget._LastESPText = nil
            PlayerMapMarker.UpdateESPText(ESPData.Widget, Text)
            PlayerMapMarker.UpdateESPPositionWithPC(ESPData.Widget, Loc, PC, CanvasPos)
            local HP = Character.Health or 0
            local MaxHP = Character.MaxHealth or 120
            local pct = 0
            if 0 < HP and 0 < MaxHP then
              pct = HP / MaxHP
              if 1 < pct then
                pct = 1
              end
              if pct < 0 then
                pct = 0
              end
            end
            PlayerMapMarker.UpdateESPHealth(ESPData.Widget, pct)
            PlayerMapMarker.AddWeaponIconToESP(ESPData.Widget, Character)
            if PlayerMapMarker.bUseSnapLines then
              PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
            else
              PlayerMapMarker.RemoveSnapLine(KeyStr)
            end
          else
            local Container = ESPData.Widget.Container or ESPData.Widget
            pcall(function()
              Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end)
            PlayerMapMarker.UpdateESPHealth(ESPData.Widget, 0)
            PlayerMapMarker.RemoveSnapLine(KeyStr)
          end
        end
      end
    end
  end
  for KeyStr, Data in pairs(PlayerMapMarker.ESPWidgets) do
    if not SeenKeys[KeyStr] then
      PlayerMapMarker.RemoveESPWidget(Data.Widget, KeyStr)
      PlayerMapMarker.ESPWidgets[KeyStr] = nil
    end
  end
end

function PlayerMapMarker.UpdateESPLight()
  if RedBoxOverlay and RedBoxOverlay.bActive then
    RedBoxOverlay.UpdatePosition()
  end
  if not PlayerMapMarker.bUseScreenESP then
    return
  end
  PlayerMapMarker.bUseSnapLines = _G.LexusConfig.Esp9_Line
  if not PlayerMapMarker.ESPCanvas or not Game:IsValid(PlayerMapMarker.ESPCanvas) then
    return
  end
  local PC = PlayerMapMarker.GetMyPlayerController()
  if not IsValid(PC) then
    return
  end
  PlayerMapMarker.UpdateCanvasTransform(PC)
  local fromX, fromY = 0, 0
  if PlayerMapMarker.bUseSnapLines then
    fromX, fromY = PlayerMapMarker.GetSnapLineStartPos(PC)
  end
  for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
    local Widget = ESPData.Widget
    local Character = ESPData.Character
    local Container = Widget and (Widget.Container or Widget)
    local bWidgetValid = false
    pcall(function()
      bWidgetValid = Container and slua.isValid(Container)
    end)
    if Widget and bWidgetValid and Character and IsValid(Character) then
      do
        local bIsAlive = PlayerMapMarker.IsAlive(Character)
        if not bIsAlive then
          pcall(function()
            Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
          end)
          PlayerMapMarker.RemoveSnapLine(KeyStr)
        else
          local bShowAnyUI = _G.LexusConfig.Esp9_Name or _G.LexusConfig.Esp9_Distance or _G.LexusConfig.Esp9_HP or _G.LexusConfig.Esp9_Team or _G.LexusConfig.Esp9_Weapon
          if bShowAnyUI then
            pcall(function()
              Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
          else
            pcall(function()
              Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end)
          end
          pcall(function()
            Container:SetRenderOpacity(1.0)
          end)
          local Loc = PlayerMapMarker.GetESPLocation(Character)
          if Loc then
            local bOnScreen, CanvasPos = PlayerMapMarker.ProjectWorldToCanvasLocal(PC, Loc)
            PlayerMapMarker.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
            if PlayerMapMarker.bUseSnapLines then
              PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
            else
              PlayerMapMarker.RemoveSnapLine(KeyStr)
            end
          else
            PlayerMapMarker.RemoveSnapLine(KeyStr)
          end
        end
      end
    end
  end
end

function PlayerMapMarker.UpdateESPDistances()
  if not PlayerMapMarker.bUseScreenESP then
    return
  end
  local MyLoc = PlayerMapMarker.GetMyLocation()
  if not MyLoc then
    return
  end
  local PC = PlayerMapMarker.GetMyPlayerController()
  if not IsValid(PC) then
    return
  end
  PlayerMapMarker.UpdateCanvasTransform(PC)
  for KeyStr, ESPData in pairs(PlayerMapMarker.ESPWidgets) do
    local Character = ESPData.Character
    local Widget = ESPData.Widget
    local Container = Widget and (Widget.Container or Widget)
    local bWidgetValid = false
    pcall(function()
      bWidgetValid = Container and slua.isValid(Container)
    end)
    if Character and IsValid(Character) and Widget and bWidgetValid then
      do
        local Loc = PlayerMapMarker.GetESPLocation(Character)
        if Loc then
          local Dist = PlayerMapMarker.CalcDistance(MyLoc, Loc)
          ESPData.LastDistance = Dist
          if PlayerMapMarker.bShowDistance then
            local DistStr = ""
            local Meters = 0
            if Dist then
              Meters = Dist / 100
              if Meters < 1000 then
                DistStr = string.format("%dm", math.floor(Meters))
              else
                DistStr = string.format("%.1fkm", Meters / 1000)
              end
            end
            local Name = ESPData.Name or "Unknown"
            local Text = ""
            if _G.LexusConfig.Esp9_Name then
              Text = Name
            end
            if _G.LexusConfig.Esp9_Distance and DistStr and DistStr ~= "" then
              if Text ~= "" then
                Text = string.format("%s [%s]", Text, DistStr)
              else
                Text = string.format("[%s]", DistStr)
              end
            end
            ESPData.LastDistStr = DistStr
            Widget._LastESPText = nil
            PlayerMapMarker.UpdateESPText(Widget, Text)
          end
        end
      end
    end
  end
end

function PlayerMapMarker.ScanAndUpdate()
  local AllChars = PlayerMapMarker.GetAllCharacters()
  if not AllChars then
    RedBoxOverlay.SetCounts(0, 0)
    return 0
  end
  local MyKey = PlayerMapMarker.GetMyPlayerKey()
  local MyLoc = PlayerMapMarker.GetMyLocation()
  local MyChar
  pcall(function()
    local GDP = PlayerMapMarker.GetGameplayData()
    if GDP and GDP.GetLocalCharacter then
      MyChar = GDP.GetLocalCharacter()
    else
      local PC = PlayerMapMarker.GetMyPlayerController()
      if PC and PC.GetPawn then
        MyChar = PC:GetPawn()
      end
    end
  end)
  local MyTeamID = PlayerMapMarker.GetTeamID(MyChar)
  local realPlayers = 0
  local botPlayers = 0
  for PlayerKey, Character in pairs(AllChars) do
    if IsValid(Character) then
      local bIsMe = PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
      local bIsAI = PlayerMapMarker.IsAI(Character)
      local bIsAlive = PlayerMapMarker.IsAlive(Character)
      if bIsAlive and not bIsMe then
        local bIsMyTeam = false
        if MyTeamID ~= nil then
          local targetTeamID = PlayerMapMarker.GetTeamID(Character)
          if targetTeamID == MyTeamID then
            bIsMyTeam = true
          end
        end
        if not bIsMyTeam then
          if bIsAI then
            botPlayers = botPlayers + 1
          else
            realPlayers = realPlayers + 1
          end
        end
      end
    end
  end
  pcall(function()
    if _G.TelegramOverlay and _G.TelegramOverlay.Create then
      _G.TelegramOverlay.Create()
    end
  end)
  if _G.LexusConfig.Esp9_Count then
    if RedBoxOverlay.bActive then
      RedBoxOverlay.SetCounts(realPlayers, botPlayers)
    else
      RedBoxOverlay.Start()
    end
  elseif RedBoxOverlay.bActive then
    RedBoxOverlay.Stop()
  end
  if PlayerMapMarker.bUseScreenESP then
    PlayerMapMarker.UpdateESP(AllChars, MyLoc)
    return 0
  end
  return 0
end

function PlayerMapMarker.AttachTimers()
  pcall(function()
    local pc = PlayerMapMarker.GetMyPlayerController()
    if not slua.isValid(pc) or not pc.AddGameTimer then
      local now = os.time()
      if PlayerMapMarker._AttachPending and PlayerMapMarker._AttachPendingTime and now - PlayerMapMarker._AttachPendingTime < 2 then
        return
      end
      PlayerMapMarker._AttachPending = true
      PlayerMapMarker._AttachPendingTime = now
      pcall(function()
        require("timer").SetGameTimer(1.0, false, function()
          PlayerMapMarker._AttachPending = nil
          PlayerMapMarker._AttachPendingTime = nil
          PlayerMapMarker.AttachTimers()
        end)
      end)
      return
    end
    PlayerMapMarker._AttachPending = nil
    PlayerMapMarker._AttachPendingTime = nil
    local now = os.time()
    local lastPC = PlayerMapMarker._ActiveTimerPC
    local lastTick = PlayerMapMarker._ActiveTimerTick
    if lastPC and slua.isValid(lastPC) and lastPC == pc and lastTick and now - lastTick < 5 then
      return
    end
    PlayerMapMarker._ActiveTimerPC = pc
    PlayerMapMarker._ActiveTimerTick = now
    pcall(function()
      pc:AddGameTimer(PlayerMapMarker.nUpdateInterval or 0.5, true, function()
        PlayerMapMarker._ActiveTimerTick = os.time()
        if PlayerMapMarker.bActive then
          pcall(function()
            PlayerMapMarker.ScanAndUpdate()
          end)
        end
      end)
    end)
    pcall(function()
      pc:AddGameTimer(PlayerMapMarker._LightUpdateInterval or 0.02, true, function()
        PlayerMapMarker._ActiveTimerTick = os.time()
        if PlayerMapMarker.bActive then
          pcall(function()
            PlayerMapMarker.UpdateESPLight()
          end)
        end
      end)
    end)
    pcall(function()
      pc:AddGameTimer(PlayerMapMarker._DistanceUpdateInterval or 0.1, true, function()
        PlayerMapMarker._ActiveTimerTick = os.time()
        if PlayerMapMarker.bActive and PlayerMapMarker.bUseScreenESP and PlayerMapMarker.bShowDistance then
          pcall(function()
            PlayerMapMarker.UpdateESPDistances()
          end)
        end
      end)
    end)
    pcall(function()
      require("timer").SetGameTimer(5.0, false, PlayerMapMarker.AttachTimers)
    end)
  end)
end

function PlayerMapMarker.Start()
  if PlayerMapMarker.bActive then
    return
  end
  PlayerMapMarker.bActive = true
  PlayerMapMarker._FrameCount = 0
  PlayerMapMarker.ScanAndUpdate()
  PlayerMapMarker.AttachTimers()
end

function PlayerMapMarker.Stop()
  PlayerMapMarker.bActive = false
  PlayerMapMarker._FrameCount = 0
  PlayerMapMarker.ClearAllESP()
end

_G.PlayerMapMarker = PlayerMapMarker

local function InitializeNativeESP()
  if _G.LexusState.NativeESPReady then
    return
  end
  pcall(function()
    local GamePlayTools2 = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
    local currentMarkCfg = GamePlayTools2.GetCurrentConfig("ScreenMarkConfig")
    
    local function ApplyCfg(cfg)
      if not cfg then
        return
      end
      if cfg[1006] then
        cfg[1006].bBindBlocked = true
        cfg[1006].bBindOutScreen = true
        cfg[1006].MaxWidgetNum = 99
        cfg[1006].MaxShowDistance = 6000000
        cfg[1006].bScaleByDistance = false
        cfg[1006].BindSocketName = "root"
        cfg[1006].bUseLuaWorldSocketName = true
        cfg[1006].WorldPositionOffset = FVector(0, 0, -30)
      end
      cfg[8888] = {
        UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
        MaxWidgetNum = 99,
        MaxShowDistance = 6000000,
        bBindOutScreen = true,
        bBindBlocked = true,
        bIsBindingActor = true,
        BindSocketName = "head",
        bUseLuaWorldSocketName = true,
        WorldPositionOffset = FVector(0, 0, 30),
        bNeedPreLoad = true,
        Priority = 2
      }
      cfg[9999] = {
        UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
        MaxWidgetNum = 99,
        MaxShowDistance = 6000000,
        bBindOutScreen = true,
        bBindBlocked = true,
        bIsBindingActor = true,
        BindSocketName = "head",
        bUseLuaWorldSocketName = true,
        WorldPositionOffset = FVector(0, 0, 50),
        bNeedPreLoad = true,
        Priority = 2
      }
    end
    
    ApplyCfg(currentMarkCfg)
    for k, cfg in pairs(package.loaded) do
      if type(k) == "string" and string.find(k, "ScreenMarkConfig") and type(cfg) == "table" then
        ApplyCfg(cfg)
      end
    end
  end)
  _G.LexusState.NativeESPReady = true
  Notify("Native ESP Initialized")
end

local Cached_MyHUD
local myToken = 0

local function MainLoop()
  if _G._MOD_EXPIRED then
    return
  end
  pcall(function()
    local GD = getCachedGameplayData()
    if not GD then
      return
    end
    local pc = GD.GetPlayerController and GD.GetPlayerController()
    local localPlayer
    if Valid(pc) then
      localPlayer = pc:GetPlayerCharacterSafety()
    end
    if not Valid(localPlayer) then
      for eKey, markData in pairs(_G.LexusState.EnemyMarks) do
      end
      return
    end
    if not Valid(Cached_MyHUD) then
      pcall(function()
        local GD2 = getCachedGameplayData()
        if GD2 then
          local MyHUD = GD2.GetMyHUD and GD2.GetMyHUD()
          if Valid(MyHUD) then
            Cached_MyHUD = MyHUD
          end
        end
      end)
    end
    if not _G.LexusState.NativeESPReady then
      InitializeNativeESP()
    end
    InitFakeHWID()
    if _G.LexusConfig.IpadView and _G.LexusState.CustomTextData then
      pcall(function()
        local targetTPP = _G.LexusState.CustomTextData.IpadViewFOV or 120
        local uTPPCam = localPlayer.ThirdPersonCameraComponent
        if Valid(uTPPCam) and uTPPCam.FieldOfView ~= targetTPP then
          uTPPCam.FieldOfView = targetTPP
        end
      end)
    else
      pcall(function()
        local uTPPCam = localPlayer.ThirdPersonCameraComponent
        if Valid(uTPPCam) and uTPPCam.FieldOfView ~= 90 then
          uTPPCam.FieldOfView = 90
        end
      end)
    end
    if _G.LexusConfig.WeaponAimbot and _G.ApplyWeaponAimbot then
      pcall(function()
        _G.ApplyWeaponAimbot()
      end)
    end
    if _G.ApplyNoRecoil then
      pcall(function()
        _G.ApplyNoRecoil()
      end)
    end
    if _G.SHMenuTryInit then
      pcall(_G.SHMenuTryInit)
    end
    if not _G.KillInfoCounterHacked and _G.ForceEnableKillCounterUI then
      pcall(function()
        _G.ForceEnableKillCounterUI()
      end)
    end
    if _G.DeadBox_TemperRequest then
      pcall(function()
        _G.DeadBox_TemperRequest(PC)
      end)
    end
    if _G.LexusConfig.ModSkin then
      if not _G.TDSkinLoopStarted then
        if _G.InitializeSkinModSystem then
          _G.InitializeSkinModSystem()
        end
        if _G.ForceRefreshSkinMaps then
          _G.ForceRefreshSkinMaps()
        end
        _G.TDSkinLoopStarted = true
      end
      _G.LexusState.SkinWasApplied = true
      local curTime = os.clock()
      if not _G.LastSkinUpdateTime or curTime - _G.LastSkinUpdateTime > 1.5 then
        _G.LastSkinUpdateTime = curTime
        pcall(function()
          local isAlive = type(localPlayer.IsAlive) == "function" and localPlayer:IsAlive() or true
          if isAlive then
            if _G.ReadLiveConfig then
              _G.ReadLiveConfig()
            end
            if not _G.KillInfoCounterHacked and _G.ForceEnableKillCounterUI then
              _G.ForceEnableKillCounterUI()
            end
            if _G.equip_character_avatar then
              _G.equip_character_avatar(localPlayer)
            end
            if _G.ApplyWeaponSkins then
              _G.ApplyWeaponSkins(localPlayer)
            end
            if _G.ApplyVehicleSkins then
              _G.ApplyVehicleSkins(localPlayer)
            end
            if _G.HandlePetLogic then
              _G.HandlePetLogic(localPlayer)
            end
          end
        end)
      end
    else
      if _G.LexusState.SkinWasApplied then
        _G.OutfitMap = {}
        _G.WeaponSkinMap = {}
        _G.VehicleSkinMap = {}
        pcall(function()
          local WeaponManager = localPlayer:GetWeaponManager()
          if Valid(WeaponManager) then
            for slot = 1, 3 do
              local Weapon = WeaponManager:GetInventoryWeaponByPropSlot(slot)
              if Valid(Weapon) and Valid(Weapon.synData) then
                do
                  local WeaponID = Weapon:GetWeaponID()
                  local SkinData = Weapon.synData:Get(7)
                  if SkinData and SkinData.defineID then
                    SkinData.defineID.TypeSpecificID = WeaponID
                    Weapon.synData:Set(7, SkinData)
                    if Weapon.SetWeaponAvatarID then
                      pcall(function()
                        Weapon:SetWeaponAvatarID(WeaponID)
                      end)
                    end
                    if Weapon.DelayHandleAvatarMeshChanged then
                      pcall(function()
                        Weapon:DelayHandleAvatarMeshChanged()
                      end)
                    end
                  end
                end
              end
            end
          end
          local Vehicle = localPlayer:GetCurrentVehicle()
          if Valid(Vehicle) then
            local VehicleAvatar = Vehicle.VehicleAvatar or Vehicle.VehicleAvatarComponent_BP or Vehicle:GetAvatarComponent()
            if Valid(VehicleAvatar) and type(VehicleAvatar.GetDefaultAvatarID) == "function" then
              local defId = VehicleAvatar:GetDefaultAvatarID()
              if VehicleAvatar.ChangeItemAvatar then
                VehicleAvatar:ChangeItemAvatar(defId, true)
              end
            end
          end
          if localPlayer.AvatarComponent2 and type(localPlayer.AvatarComponent2.OnRep_BodySlotStateChanged) == "function" then
            localPlayer.AvatarComponent2:OnRep_BodySlotStateChanged()
          end
        end)
        _G.LexusState.SkinWasApplied = false
      end
      _G.TDSkinLoopStarted = false
    end
    pcall(function()
      if Valid(pc) then
        if pc.HiggsBoson then
          pc.HiggsBoson.bMHActive = false
          pc.HiggsBoson.bCallPreReplication = false
        end
        if pc.HiggsBosonComponent then
          pc.HiggsBosonComponent.bMHActive = false
          pc.HiggsBosonComponent.bCallPreReplication = false
        end
      end
    end)
    pcall(function()
      local autoComp = localPlayer.AutoAimComp
      if Valid(autoComp) then
        if not _G.LexusState.OrigAutoAimCompCached then
          _G.LexusState.OrigAutoAimCompCached = {
            bOnlyHitHead = autoComp.bOnlyHitHead,
            HeadBoneName = autoComp.HeadBoneName,
            Bones = autoComp.Bones,
            ChestBoneName = autoComp.ChestBoneName,
            PelvisBoneName = autoComp.PelvisBoneName
          }
        end
        if _G.LexusConfig.AutoHead then
          autoComp.bOnlyHitHead = true
          autoComp.HeadBoneName = "Head"
          pcall(function()
            autoComp.Bones = {"Head"}
          end)
          autoComp.ChestBoneName = "Head"
          autoComp.PelvisBoneName = "Head"
        else
          local orig = _G.LexusState.OrigAutoAimCompCached
          autoComp.bOnlyHitHead = orig.bOnlyHitHead
          autoComp.HeadBoneName = orig.HeadBoneName
          pcall(function()
            autoComp.Bones = orig.Bones or {
              "Spine_01",
              "Pelvis",
              "Head"
            }
          end)
          autoComp.ChestBoneName = orig.ChestBoneName
          autoComp.PelvisBoneName = orig.PelvisBoneName
        end
      end
    end)
    if _G.LexusConfig.EspLoai9 then
      if _G.PlayerMapMarker and not _G.PlayerMapMarker.bActive then
        _G.PlayerMapMarker.Start()
      end
    elseif _G.PlayerMapMarker and _G.PlayerMapMarker.bActive then
      _G.PlayerMapMarker.Stop()
    end
    local allCharacters = {}
    pcall(function()
      if GD.GetAllPlayerCharacters then
        allCharacters = GD.GetAllPlayerCharacters()
      elseif GD.GameCharacters then
        for _, char in pairs(GD.GameCharacters) do
          table.insert(allCharacters, char)
        end
      end
    end)
    local currentValidKeys = {}
    for _, enemy in pairs(allCharacters) do
      if Valid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
        local bIsReallyDead = false
        pcall(function()
          if type(enemy.IsDead) == "function" then
            bIsReallyDead = enemy:IsDead()
          elseif enemy.bIsDead ~= nil then
            bIsReallyDead = enemy.bIsDead
          end
          if enemy.HealthStatus ~= nil and enemy.HealthStatus == 2 then
            bIsReallyDead = true
          end
        end)
        if not bIsReallyDead then
          do
            local eKey = GetSafeEnemyKey(enemy)
            currentValidKeys[eKey] = true
          end
        end
      end
    end
    for eKey, markData in pairs(_G.LexusState.EnemyMarks) do
      if not currentValidKeys[eKey] then
        if markData.MIDs then
          markData.MIDs = nil
        end
        if markData.MIDs_V3 then
          markData.MIDs_V3 = nil
        end
        _G.LexusState.EnemyMarks[eKey] = nil
      end
    end
    local aiCount = 0
    local realCount = 0
    for _, enemy in pairs(allCharacters) do
      if Valid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
        local bIsReallyDead = false
        pcall(function()
          if type(enemy.IsDead) == "function" then
            bIsReallyDead = enemy:IsDead()
          elseif enemy.bIsDead ~= nil then
            bIsReallyDead = enemy.bIsDead
          end
          if enemy.HealthStatus ~= nil and enemy.HealthStatus == 2 then
            bIsReallyDead = true
          end
        end)
        local eKey = GetSafeEnemyKey(enemy)
        _G.LexusState.EnemyMarks[eKey] = _G.LexusState.EnemyMarks[eKey] or {enemy = enemy}
        local markData = _G.LexusState.EnemyMarks[eKey]
        markData.enemy = enemy
        if not bIsReallyDead then
          if markData.lastEnemyActor ~= enemy then
            markData.lastEnemyActor = enemy
          end
          local eMesh
          pcall(function()
            eMesh = enemy.Mesh or type(enemy.getAvatarComponent2) == "function" and enemy:getAvatarComponent2() or nil
          end)
          local aLoc
          pcall(function()
            if type(enemy.K2_GetActorLocation) == "function" then
              aLoc = enemy:K2_GetActorLocation()
            end
          end)
          local isBotResult = CheckIsAI(enemy, markData)
          if _G.LexusConfig.ColorBodyNew then
            ApplyColorBodyNew(enemy, markData)
          else
            UndoColorBodyNew(enemy, markData)
          end
          local distM = 0
          pcall(function()
            distM = localPlayer:GetDistanceTo(enemy) / 100
          end)
          local currentHp, maxHp = 100, 100
          pcall(function()
            if enemy.Health then
              currentHp = enemy.Health
            elseif type(enemy.GetHealth) == "function" then
              currentHp = enemy:GetHealth()
            end
            if enemy.HealthMax then
              maxHp = enemy.HealthMax
            elseif type(enemy.GetHealthMax) == "function" then
              maxHp = enemy:GetHealthMax()
            end
          end)
          if maxHp <= 0 then
            maxHp = 100
          end
          local hpRatio = currentHp / maxHp
          if _G.LexusConfig.EspAntenna then
            pcall(function()
              if Valid(Cached_MyHUD) and distM <= 400 then
                for i = 1, 8 do
                  local zOffset = 105 + i * 1000
                  Cached_MyHUD:AddDebugText("|", enemy, 0.06, {
                    X = 0,
                    Y = 0,
                    Z = zOffset
                  }, {
                    X = 0,
                    Y = 0,
                    Z = zOffset
                  }, C_GREEN, true, false, true, nil, 1.2, true)
                end
                Cached_MyHUD:AddDebugText("I", enemy, 0.06, {
                  X = 0,
                  Y = 0,
                  Z = 9060
                }, {
                  X = 0,
                  Y = 0,
                  Z = 9060
                }, C_GREEN, true, false, true, nil, 1.5, true)
              end
            end)
          end
          if _G.LexusConfig.EspLoai6 then
            pcall(function()
              local curTime = os.clock()
              if markData.LastEsp6Time == nil or curTime - markData.LastEsp6Time >= 0.05 then
                markData.LastEsp6Time = curTime
                if Valid(Cached_MyHUD) and Valid(eMesh) and aLoc and distM <= 250 and type(eMesh.GetSocketLocation) == "function" then
                  for _, bName in ipairs(GLOBAL_BONE_LIST) do
                    if 50 < distM and bName ~= "head" and bName ~= "pelvis" and bName ~= "neck_01" then
                    else
                      local wLoc = eMesh:GetSocketLocation(bName)
                      if wLoc then
                        local offset = {
                          X = wLoc.X - aLoc.X,
                          Y = wLoc.Y - aLoc.Y,
                          Z = wLoc.Z - aLoc.Z
                        }
                        local mark = "\195\162\226\128\147\194\170"
                        local fixedSize = 0.25
                        local color = C_CYAN
                        if bName == "head" then
                          mark = "\195\162\226\128\148\194\143"
                          fixedSize = 0.45
                          color = C_RED
                        elseif bName == "pelvis" or bName == "neck_01" then
                          mark = "\195\162\226\128\147\194\170"
                          fixedSize = 0.35
                          color = C_YELLOW
                        end
                        Cached_MyHUD:AddDebugText(mark, enemy, 0.06, offset, offset, color, true, false, true, nil, fixedSize, true)
                      end
                    end
                  end
                end
              end
            end)
          end
          if _G.LexusConfig.EspLoai7 then
            pcall(function()
              if Valid(Cached_MyHUD) then
                if distM <= 600 then
                  if isBotResult then
                    aiCount = aiCount + 1
                  else
                    realCount = realCount + 1
                  end
                end
                if distM <= 400 then
                  local stateText = ""
                  if _G.LexusConfig.Esp7_TuThe then
                    local pose = enemy.PoseState or type(enemy.GetPoseState) == "function" and enemy:GetPoseState()
                    if pose == 0 or pose == "Stand" then
                      stateText = "Stand"
                    elseif pose == 1 or pose == "Crouch" then
                      stateText = "Crouch"
                    elseif pose == 2 or pose == "Prone" then
                      stateText = "Prone"
                    else
                      stateText = "Stand"
                    end
                  end
                  if _G.LexusConfig.Esp7_VuKhi then
                    local curTime = os.clock()
                    if markData.AK_LAST_WEP_TIME == nil or curTime > markData.AK_LAST_WEP_TIME + 1.5 then
                      local eWeapon = enemy.CurrentWeapon or type(enemy.GetCurrentWeapon) == "function" and enemy:GetCurrentWeapon()
                      local weaponName = "Fists"
                      if Valid(eWeapon) and type(eWeapon.GetWeaponName) == "function" then
                        weaponName = eWeapon:GetWeaponName()
                      end
                      markData.AK_CACHED_WEP_NAME = tostring(weaponName)
                      markData.AK_LAST_WEP_TIME = curTime
                    end
                    if stateText ~= "" then
                      stateText = stateText .. " - " .. (markData.AK_CACHED_WEP_NAME or "Fists")
                    else
                      stateText = markData.AK_CACHED_WEP_NAME or "Fists"
                    end
                  end
                  if stateText ~= "" then
                    local textColor = isBotResult and C_CYAN or C_YELLOW
                    local dynamicScale = math.max(0.5, 0.8 - distM / 400)
                    Cached_MyHUD:AddDebugText(stateText, enemy, 0.06, {
                      X = 0,
                      Y = 0,
                      Z = 100
                    }, {
                      X = 0,
                      Y = 0,
                      Z = 100
                    }, textColor, true, false, true, nil, dynamicScale, true)
                  end
                end
              end
            end)
          end
          if _G.LexusConfig.EspVipPro then
            pcall(function()
              if Valid(Cached_MyHUD) and distM <= 400 then
                local dynamicScale = math.max(0.55, 0.95 - distM / 400)
                local hpColor = C_WHITE
                local isKnock = currentHp <= 0 and enemy.HealthStatus == 1
                if isKnock then
                  hpColor = C_RED
                end
                if _G.LexusConfig.Esp3ShowName then
                  local enemyName = "Enemy"
                  pcall(function()
                    if enemy.PlayerName then
                      enemyName = enemy.PlayerName
                    elseif type(enemy.GetPlayerName) == "function" then
                      enemyName = enemy:GetPlayerName()
                    end
                  end)
                  if enemyName == "" then
                    enemyName = "Enemy"
                  end
                  if isKnock then
                    enemyName = "KNOCK: " .. enemyName
                  end
                  Cached_MyHUD:AddDebugText(enemyName, enemy, 0.06, {
                    X = 0,
                    Y = 0,
                    Z = -370
                  }, {
                    X = 0,
                    Y = 0,
                    Z = -370
                  }, C_RED, true, false, true, nil, dynamicScale * 1.1, true)
                end
                if _G.LexusConfig.Esp3ShowHP and not isKnock then
                  local segments = 6
                  local filled = math.floor(hpRatio * segments)
                  local startZ = 20
                  local spacing = 10.0 * dynamicScale
                  for j = 1, segments do
                    local color = j <= filled and hpColor or {
                      R = 30,
                      G = 30,
                      B = 30,
                      A = 180
                    }
                    Cached_MyHUD:AddDebugText("\195\162\226\128\147\203\134", enemy, 0.06, {
                      X = 0,
                      Y = -115,
                      Z = startZ + j * spacing
                    }, {
                      X = 0,
                      Y = -115,
                      Z = startZ + j * spacing
                    }, color, true, false, true, nil, dynamicScale * 1.2, true)
                  end
                  Cached_MyHUD:AddDebugText(string.format("%d%%", math.floor(hpRatio * 100)), enemy, 0.06, {
                    X = 0,
                    Y = -60,
                    Z = startZ - 12
                  }, {
                    X = 0,
                    Y = -60,
                    Z = startZ - 12
                  }, hpColor, true, false, true, nil, dynamicScale * 0.8, true)
                elseif isKnock then
                  Cached_MyHUD:AddDebugText("DOWN", enemy, 0.06, {
                    X = 0,
                    Y = -115,
                    Z = 50
                  }, {
                    X = 0,
                    Y = -115,
                    Z = 50
                  }, C_RED, true, false, true, nil, dynamicScale * 1.0, true)
                end
              end
            end)
          end
          if _G.LexusConfig.EspDistance then
            pcall(function()
              if Valid(Cached_MyHUD) and distM <= 400 then
                local dynamicScale = math.max(0.55, 0.95 - distM / 400)
                Cached_MyHUD:AddDebugText(string.format("[%dm]", math.floor(distM)), enemy, 0.06, {
                  X = 0,
                  Y = 115,
                  Z = 20
                }, {
                  X = 0,
                  Y = 115,
                  Z = 20
                }, C_BLUE_TEXT, true, false, true, nil, dynamicScale * 1.5, true)
              end
            end)
          end
          if _G.LexusConfig.EspOutline then
            pcall(function()
              local outColorChoice = _G.LexusState.CustomTextData and _G.LexusState.CustomTextData.OutlineColor or 4
              local outlineHash = string.format("%d_%d", _G.LexusConfig.OutlineThickness or 10, outColorChoice)
              local meshes = GetAllSkeletalMeshes(enemy, markData)
              if markData.OutlineState ~= outlineHash then
                local r, g, b = 255, 255, 0
                if outColorChoice == 1 then
                  r, g, b = 255, 0, 0
                elseif outColorChoice == 2 then
                  r, g, b = 0, 255, 0
                elseif outColorChoice == 3 then
                  r, g, b = 0, 0, 255
                elseif outColorChoice == 5 then
                  r, g, b = 255, 0, 255
                elseif outColorChoice == 6 then
                  r, g, b = 255, 255, 255
                end
                local glowIntensity = 80.0
                local LC = getCachedLinearColor()
                local glowDynamic = LC and LC(r / 255 * glowIntensity, g / 255 * glowIntensity, b / 255 * glowIntensity, 1.0) or {
                  R = r * glowIntensity,
                  G = g * glowIntensity,
                  B = b * glowIntensity,
                  A = 255
                }
                for _, comp in ipairs(meshes) do
                  if Valid(comp) then
                    pcall(function()
                      comp.UseScopeDistanceCulling = false
                      comp.PrimitiveShadingStrategy = 1
                      comp.ShadingRate = 6
                    end)
                    if comp.SetDrawIdeaOutline then
                      comp:SetDrawIdeaOutline(true)
                      if comp.OverrideIdeaOutlineColor then
                        comp:OverrideIdeaOutlineColor(true, glowDynamic)
                      end
                      if comp.OverrideIdeaOutlineThickness then
                        comp:OverrideIdeaOutlineThickness(true, _G.LexusConfig.OutlineThickness)
                      end
                    end
                  end
                end
                markData.OutlineState = outlineHash
              end
            end)
          else
            pcall(function()
              if markData.OutlineState ~= "OFF" then
                local meshes = GetAllSkeletalMeshes(enemy, markData)
                for _, comp in ipairs(meshes) do
                  if Valid(comp) then
                    pcall(function()
                      comp.PrimitiveShadingStrategy = 0
                      comp.ShadingRate = 1
                    end)
                    if comp.SetDrawIdeaOutline then
                      comp:SetDrawIdeaOutline(false)
                    end
                  end
                end
                markData.OutlineState = "OFF"
              end
            end)
          end
        elseif not markData.IsCleanedUp then
          if markData.MIDs then
            markData.MIDs = nil
          end
          if markData.MIDs_V3 then
            markData.MIDs_V3 = nil
          end
          markData.IsCleanedUp = true
        end
      end
    end
    if _G.LexusConfig.WeaponGlow then
      if not _G.LastGlowTime or os.clock() - _G.LastGlowTime > 0.5 then
        _G.LastGlowTime = os.clock()
        if _G.ApplyWeaponGlow then
          _G.ApplyWeaponGlow(localPlayer)
        end
      end
    elseif _G.LastGlowRemoveTime == nil or os.clock() - _G.LastGlowRemoveTime > 1.0 then
      _G.LastGlowRemoveTime = os.clock()
      if _G.ApplyWeaponGlow then
        _G.ApplyWeaponGlow(localPlayer)
      end
    end
  end)
end

local function FastTick()
  if _G._MOD_EXPIRED then
    return
  end
  if myToken ~= _G.LexusState.LoopToken then
    return
  end
  pcall(MainLoop)
  local okTicker, ticker = pcall(require, "common.time_ticker")
  if okTicker and ticker and ticker.AddTimerOnce then
    ticker.AddTimerOnce(0.1, FastTick)
  end
end

local function GetConfigPaths(fileName)
  local paths = {
    "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "/Documents/ShadowTrackerExtra/Saved/Paks/puffer_temp/" .. fileName,
    "/com.tencent.ig/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "/com.vng.pubgmobile/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "/com.pubg.krmobile/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "/com.rekoo.pubgm/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "/com.pubg.imobile/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "../../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
    "../../../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
    fileName
  }
  pcall(function()
    if os and os.getenv then
      local homeDir = os.getenv("HOME")
      if homeDir and homeDir ~= "" then
        table.insert(paths, 1, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName)
        table.insert(paths, 2, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Paks/puffer_temp/" .. fileName)
      end
    end
  end)
  return paths
end

local ConfigFileName = "MOHSINXFILESCheats.txt"
_G.LastConfigSaveStr = ""

function _G.SaveModSettings()
  pcall(function()
    if not _G.LexusConfig or not next(_G.LexusConfig) then
      return
    end
    local data = [[
return {
LexusConfig = {
]]
    for k, v in pairs(_G.LexusConfig or {}) do
      data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
    end
    data = data .. [[
},
CustomTextData = {
]]
    if _G.LexusState and _G.LexusState.CustomTextData then
      for k, v in pairs(_G.LexusState.CustomTextData) do
        data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
      end
    end
    data = data .. [[
}
}]]
    if data == _G.LastConfigSaveStr then
      return
    end
    _G.LastConfigSaveStr = data
    local paths = GetConfigPaths(ConfigFileName)
    for _, path in ipairs(paths) do
      local file = io.open(path, "w")
      if file then
        file:write(data)
        file:close()
        break
      end
    end
  end)
end

function _G.LoadModSettings()
  if _G._MOD_EXPIRED then
    return
  end
  pcall(function()
    local paths = GetConfigPaths(ConfigFileName)
    local content
    for _, path in ipairs(paths) do
      local file = io.open(path, "r")
      if file then
        content = file:read("*a")
        file:close()
        break
      end
    end
    if content then
      local func = load(content)
      if func then
        local savedData = func()
        if savedData and type(savedData) == "table" then
          if savedData.LexusConfig then
            for k, v in pairs(savedData.LexusConfig) do
              _G.LexusConfig[k] = v
            end
          end
          if savedData.CustomTextData then
            _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {}
            for k, v in pairs(savedData.CustomTextData) do
              _G.LexusState.CustomTextData[k] = v
            end
          end
        end
      end
    end
  end)
end

local function AutoSaveLoop()
  if _G._MOD_EXPIRED then
    return
  end
  pcall(function()
    if _G.SaveModSettings then
      _G.SaveModSettings()
    end
  end)
  pcall(function()
    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce then
      ticker.AddTimerOnce(1.0, AutoSaveLoop)
    end
  end)
end

function _G.ReadLiveConfig()
  if _G.SaveModSettings then
    _G.SaveModSettings()
  end
end

function _G.InitModMenuTab()
  if _G.ModMenuInitialized then
    return
  end
  _G.ModMenuInitialized = true
  
  local function T(vnText, enText)
    return enText or vnText
  end
  
  _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {
    OuterSpeed = 10,
    InnerSpeed = 10,
    OuterRecoil = 0,
    HRecoil = 0.3,
    VRecoil = 0.3,
    MagicHead = 1.0,
    MagicBody = 1.0,
    MagicLegs = 1.0,
    IpadViewFOV = 120,
    AimTouchHipPrio = 1,
    AimTouchHipBone = 1,
    AimTouchHipCond = 1,
    AimTouchHipSpeed = 50,
    AimTouchHipFOV = 30,
    AimTouchHipDist = 250,
    AimTouchSGPrio = 1,
    AimTouchSGBone = 2,
    AimTouchSGCond = 1,
    AimTouchSGSpeed = 80,
    AimTouchSGFOV = 40,
    AimTouchSGDist = 30,
    AimTouchScopePrio = 1,
    AimTouchScopeBone = 2,
    AimTouchScopeCond = 1,
    AimTouchScopeSpeed = 40,
    AimTouchScopeFOV = 20,
    AimTouchScopeDist = 300,
    AimTouchScopePred = 0,
    AimTouchScopeRecoil = 0,
    AimTouchSniperPrio = 1,
    AimTouchSniperBone = 1,
    AimTouchSniperCond = 2,
    AimTouchSniperSpeed = 30,
    AimTouchSniperFOV = 20,
    AimTouchSniperDist = 400,
    AimTouchSniperPred = 0,
    AimTouchMortarPred = 0,
    AimTouchMortarFOV = 360,
    BugManRatio = 133,
    FastCarSpeed = 2000,
    WeaponGlowThickness = 3,
    WeaponGlowColor = 5,
    ColorV3Hidden = 1,
    ColorV3Visible = 2,
    ColorV3Thickness = 4,
    OutlineColor = 4
  }
  local LocUtil = _G.LocUtil
  if not LocUtil and package.loaded["client.common.LocUtil"] then
    LocUtil = require("client.common.LocUtil")
  end
  local FakeTextMap = {
    [999000] = T("MOHSINXFILES MENU"),
    [999001] = T("ESP MENU"),
    [999003] = T("PLAYER"),
    [999004] = T("SKIN MENU")
  }
  if LocUtil and not LocUtil._IsModMenuHooked_V2 then
    local hookFuncs = {
      "GetLocalizeResStr",
      "GetText",
      "GetTextByID",
      "GetLocalText",
      "GetLocalizeStr"
    }
    for _, funcName in ipairs(hookFuncs) do
      if LocUtil[funcName] then
        local old_func = LocUtil[funcName]
        LocUtil[funcName] = function(id)
          if FakeTextMap[id] then
            return FakeTextMap[id]
          end
          if type(id) == "string" and not tonumber(id) then
            return id
          end
          if old_func then
            return old_func(id)
          end
          return ""
        end
      end
    end
    LocUtil._IsModMenuHooked_V2 = true
  end
  local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
  local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
  if not SettingPageDefine.ModMenu then
    local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
    local StackESP = {
      {
        Key = "ModMenu_ESP9_Ex",
        UI = AliasMap.TitleSwitcher,
        Text = T("ESP VIP MENU"),
        ExpandIndex = 0,
        GetFunc = function()
          return _G.LexusConfig.EspLoai9
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.EspLoai9 = v
          return true
        end
      },
      {
        Key = "ModMenu_ESP9_Count",
        UI = AliasMap.Switcher,
        Text = T("   Show Player Count"),
        ExpandHandle = "ModMenu_ESP9_Ex",
        GetFunc = function()
          return _G.LexusConfig.Esp9_Count
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.Esp9_Count = v
          return true
        end
      },
      {
        Key = "ModMenu_ESP9_Name",
        UI = AliasMap.Switcher,
        Text = T("   Show Player Name"),
        ExpandHandle = "ModMenu_ESP9_Ex",
        GetFunc = function()
          return _G.LexusConfig.Esp9_Name
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.Esp9_Name = v
          return true
        end
      },
      {
        Key = "ModMenu_ESP9_Dist",
        UI = AliasMap.Switcher,
        Text = T("   Show Distance"),
        ExpandHandle = "ModMenu_ESP9_Ex",
        GetFunc = function()
          return _G.LexusConfig.Esp9_Distance
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.Esp9_Distance = v
          return true
        end
      },
      {
        Key = "ModMenu_ESP9_HP",
        UI = AliasMap.Switcher,
        Text = T("   Show Health Bar"),
        ExpandHandle = "ModMenu_ESP9_Ex",
        GetFunc = function()
          return _G.LexusConfig.Esp9_HP
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.Esp9_HP = v
          return true
        end
      },
      {
        Key = "ModMenu_ESP9_Team",
        UI = AliasMap.Switcher,
        Text = T("   Show Team Color Box"),
        ExpandHandle = "ModMenu_ESP9_Ex",
        GetFunc = function()
          return _G.LexusConfig.Esp9_Team
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.Esp9_Team = v
          return true
        end
      },
      {
        Key = "ModMenu_ESP9_Line",
        UI = AliasMap.Switcher,
        Text = T("   Show Snapline"),
        ExpandHandle = "ModMenu_ESP9_Ex",
        GetFunc = function()
          return _G.LexusConfig.Esp9_Line
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.Esp9_Line = v
          return true
        end
      },
      {
        Key = "ModMenu_ColorBodyNew",
        UI = AliasMap.Switcher,
        Text = T("COLOUR BODY (Green/Pink)"),
        GetFunc = function()
          return _G.LexusConfig.ColorBodyNew
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.ColorBodyNew = v
          return true
        end
      }
    }
    local StackCombat = {
      {
        Key = "ModMenu_Ipad_Ex",
        UI = AliasMap.TitleSwitcher,
        Text = T("IPAD VIEW"),
        ExpandIndex = 0,
        GetFunc = function()
          return _G.LexusConfig.IpadView
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.IpadView = v
          return true
        end
      },
      {
        Key = "ModMenu_Ipad_FOV",
        UI = AliasMap.Slider,
        Text = T("   FOV"),
        ExpandHandle = "ModMenu_Ipad_Ex",
        MinValue = 1,
        MaxValue = 100,
        min = 1,
        max = 100,
        GetFunc = function()
          return (_G.LexusState.CustomTextData.IpadViewFOV or 120) - 90
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.IpadViewFOV = 90 + v
          return true
        end
      },
      {
        Key = "ModMenu_NoRecoil",
        UI = AliasMap.TitleSwitcher,
        Text = T("NO RECOIL"),
        ExpandIndex = 0,
        GetFunc = function()
          return _G.LexusConfig.NoRecoilEnabled
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.NoRecoilEnabled = v
          _G.LastRecoilState = nil
          return true
        end
      },
      {
        Key = "ModMenu_RecoilReduction",
        UI = AliasMap.Slider,
        Text = T("   Recoil Reduction"),
        ExpandHandle = "ModMenu_NoRecoil",
        MinValue = 0,
        MaxValue = 100,
        min = 0,
        max = 100,
        GetFunc = function()
          return _G.LexusConfig.RecoilReduction or 100
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.RecoilReduction = v
          _G.LastRecoilState = nil
          return true
        end
      },
      {
        Key = "ModMenu_WeaponAimbot",
        UI = AliasMap.TitleSwitcher,
        Text = T("WEAPON AIMBOT"),
        ExpandIndex = 0,
        GetFunc = function()
          return _G.LexusConfig.WeaponAimbot
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.WeaponAimbot = v
          return true
        end
      }
    }
    local StackSkin = {
      {
        Key = "ModMenu_ModSkin",
        UI = AliasMap.TitleSwitcher,
        Text = T("MOD SKIN ON/OFF"),
        ExpandIndex = 0,
        GetFunc = function()
          return _G.LexusConfig.ModSkin
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.ModSkin = v
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Suit",
        UI = AliasMap.Slider,
        Text = T("   Suit Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 80,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinSuit or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinSuit = v
          if _G.OutfitSkins and _G.OutfitSkins.Suit[v] then
            _G.OutfitMap.Suit = _G.OutfitSkins.Suit[v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Bag",
        UI = AliasMap.Slider,
        Text = T("   Bag Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 15,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinBag or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinBag = v
          if _G.OutfitSkins and _G.OutfitSkins.Bag[v] then
            _G.OutfitMap.Bag = _G.OutfitSkins.Bag[v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Helmet",
        UI = AliasMap.Slider,
        Text = T("   Helmet Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 11,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinHelmet or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinHelmet = v
          if _G.OutfitSkins and _G.OutfitSkins.Helmet[v] then
            _G.OutfitMap.Helmet = _G.OutfitSkins.Helmet[v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_M416",
        UI = AliasMap.Slider,
        Text = T("   M416 Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 8,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinM416 or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinM416 = v
          if _G.skinIdMappings[101004] and _G.skinIdMappings[101004][v] then
            _G.WeaponSkinMap[101004] = _G.skinIdMappings[101004][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_AKM",
        UI = AliasMap.Slider,
        Text = T("   AKM Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 8,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinAKM or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinAKM = v
          if _G.skinIdMappings[101001] and _G.skinIdMappings[101001][v] then
            _G.WeaponSkinMap[101001] = _G.skinIdMappings[101001][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_SCAR",
        UI = AliasMap.Slider,
        Text = T("   SCAR Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 8,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinSCAR or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinSCAR = v
          if _G.skinIdMappings[101003] and _G.skinIdMappings[101003][v] then
            _G.WeaponSkinMap[101003] = _G.skinIdMappings[101003][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_M762",
        UI = AliasMap.Slider,
        Text = T("   M762 Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 8,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinM762 or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinM762 = v
          if _G.skinIdMappings[101008] and _G.skinIdMappings[101008][v] then
            _G.WeaponSkinMap[101008] = _G.skinIdMappings[101008][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_AUG",
        UI = AliasMap.Slider,
        Text = T("   AUG Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 7,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinAUG or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinAUG = v
          if _G.skinIdMappings[101006] and _G.skinIdMappings[101006][v] then
            _G.WeaponSkinMap[101006] = _G.skinIdMappings[101006][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_UMP",
        UI = AliasMap.Slider,
        Text = T("   UMP Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 5,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinUMP or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinUMP = v
          if _G.skinIdMappings[102002] and _G.skinIdMappings[102002][v] then
            _G.WeaponSkinMap[102002] = _G.skinIdMappings[102002][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_UZI",
        UI = AliasMap.Slider,
        Text = T("   UZI Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinUZI or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinUZI = v
          if _G.skinIdMappings[102001] and _G.skinIdMappings[102001][v] then
            _G.WeaponSkinMap[102001] = _G.skinIdMappings[102001][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Groza",
        UI = AliasMap.Slider,
        Text = T("   Groza Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinGroza or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinGroza = v
          if _G.skinIdMappings[101005] and _G.skinIdMappings[101005][v] then
            _G.WeaponSkinMap[101005] = _G.skinIdMappings[101005][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_S12K",
        UI = AliasMap.Slider,
        Text = T("   S12K Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinS12K or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinS12K = v
          if _G.skinIdMappings[104003] and _G.skinIdMappings[104003][v] then
            _G.WeaponSkinMap[104003] = _G.skinIdMappings[104003][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_DBS",
        UI = AliasMap.Slider,
        Text = T("   DBS Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 3,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinDBS or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinDBS = v
          if _G.skinIdMappings[104004] and _G.skinIdMappings[104004][v] then
            _G.WeaponSkinMap[104004] = _G.skinIdMappings[104004][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_ASM",
        UI = AliasMap.Slider,
        Text = T("   ASM Gen8 Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinASM or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinASM = v
          if _G.skinIdMappings[101101] and _G.skinIdMappings[101101][v] then
            _G.WeaponSkinMap[101101] = _G.skinIdMappings[101101][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_QBZ",
        UI = AliasMap.Slider,
        Text = T("   QBZ Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinQBZ or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinQBZ = v
          if _G.skinIdMappings[101007] and _G.skinIdMappings[101007][v] then
            _G.WeaponSkinMap[101007] = _G.skinIdMappings[101007][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Honey",
        UI = AliasMap.Slider,
        Text = T("   Honey Badger Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinHoney or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinHoney = v
          if _G.skinIdMappings[101012] and _G.skinIdMappings[101012][v] then
            _G.WeaponSkinMap[101012] = _G.skinIdMappings[101012][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_M16A4",
        UI = AliasMap.Slider,
        Text = T("   M16A4 Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinM16A4 or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinM16A4 = v
          if _G.skinIdMappings[101002] and _G.skinIdMappings[101002][v] then
            _G.WeaponSkinMap[101002] = _G.skinIdMappings[101002][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_ACE32",
        UI = AliasMap.Slider,
        Text = T("   ACE32 Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinACE32 or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinACE32 = v
          if _G.skinIdMappings[101102] and _G.skinIdMappings[101102][v] then
            _G.WeaponSkinMap[101102] = _G.skinIdMappings[101102][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Kar98k",
        UI = AliasMap.Slider,
        Text = T("   Kar98k Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinKar98k or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinKar98k = v
          if _G.skinIdMappings[103001] and _G.skinIdMappings[103001][v] then
            _G.WeaponSkinMap[103001] = _G.skinIdMappings[103001][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_M24",
        UI = AliasMap.Slider,
        Text = T("   M24 Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinM24 or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinM24 = v
          if _G.skinIdMappings[103002] and _G.skinIdMappings[103002][v] then
            _G.WeaponSkinMap[103002] = _G.skinIdMappings[103002][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_AWM",
        UI = AliasMap.Slider,
        Text = T("   AWM Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 2,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinAWM or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinAWM = v
          if _G.skinIdMappings[103003] and _G.skinIdMappings[103003][v] then
            _G.WeaponSkinMap[103003] = _G.skinIdMappings[103003][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Dacia",
        UI = AliasMap.Slider,
        Text = T("   Dacia Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 34,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinDacia or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinDacia = v
          if _G.VehicleSkins[1903001] and _G.VehicleSkins[1903001][v] then
            _G.VehicleSkinMap[1903001] = _G.VehicleSkins[1903001][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_UAZ",
        UI = AliasMap.Slider,
        Text = T("   UAZ Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 16,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinUAZ or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinUAZ = v
          if _G.VehicleSkins[1908001] and _G.VehicleSkins[1908001][v] then
            _G.VehicleSkinMap[1908001] = _G.VehicleSkins[1908001][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Coupe",
        UI = AliasMap.Slider,
        Text = T("   Coupe Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 55,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinCoupe or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinCoupe = v
          if _G.VehicleSkins[1961001] and _G.VehicleSkins[1961001][v] then
            _G.VehicleSkinMap[1961001] = _G.VehicleSkins[1961001][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Buggy",
        UI = AliasMap.Slider,
        Text = T("   Buggy Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 11,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinBuggy or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinBuggy = v
          if _G.VehicleSkins[1907002] and _G.VehicleSkins[1907002][v] then
            _G.VehicleSkinMap[1907002] = _G.VehicleSkins[1907002][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_Skin_Mirado",
        UI = AliasMap.Slider,
        Text = T("   Mirado Skin"),
        ExpandHandle = "ModMenu_ModSkin",
        MinValue = 1,
        MaxValue = 5,
        GetFunc = function()
          return _G.LexusState.CustomTextData.SkinMirado or 1
        end,
        SetFunc = function(c, v)
          _G.LexusState.CustomTextData.SkinMirado = v
          if _G.VehicleSkins[1915004] and _G.VehicleSkins[1915004][v] then
            _G.VehicleSkinMap[1915004] = _G.VehicleSkins[1915004][v]
          end
          _G.LexusState.DirtyConfig = true
          return true
        end
      },
      {
        Key = "ModMenu_SkinDeadBox",
        UI = AliasMap.TitleSwitcher,
        Text = T("DeadBox Skin"),
        ExpandIndex = 0,
        GetFunc = function()
          return _G.LexusConfig.SkinDeadBox
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.SkinDeadBox = v
          return true
        end
      },
      {
        Key = "ModMenu_SkinAttachment",
        UI = AliasMap.TitleSwitcher,
        Text = T("Attachment Skin"),
        ExpandIndex = 0,
        GetFunc = function()
          return _G.LexusConfig.SkinAttachment
        end,
        SetFunc = function(c, v)
          _G.LexusConfig.SkinAttachment = v
          return true
        end
      }
    }
    SettingPageDefine.ModMenu = {
      Key = "ModMenu",
      Text = 999000,
      UIKey = "Setting_Page_Privacy",
      Category = {
        {
          Key = "Cat_ESP",
          Text = 999001,
          Stack = StackESP
        },
        {
          Key = "Cat_Combat",
          Text = 999003,
          Stack = StackCombat
        },
        {
          Key = "Cat_Skin",
          Text = 999004,
          Stack = StackSkin
        }
      }
    }
    table.insert(SettingCatalog, 1, SettingPageDefine.ModMenu)
  end
  local UIManager = _G.UIManager
  if UIManager and not UIManager._IsModMenuHooked then
    local old_ShowUI = UIManager.ShowUI
    
    function UIManager.ShowUI(config, ...)
      local args = {
        ...
      }
      local n = select("#", ...)
      if config and config.keyName then
        local lowerKeyName = string.lower(config.keyName)
        if string.find(lowerKeyName, "setting_main") and not string.find(lowerKeyName, "custom") then
          local catalog = args[1]
          if type(catalog) == "table" and catalog[1] and type(catalog[1]) == "table" and catalog[1].Key then
            local hasModMenu = false
            for _, page in ipairs(catalog) do
              if type(page) == "table" and page.Key == "ModMenu" then
                hasModMenu = true
                break
              end
            end
            if not hasModMenu then
              table.insert(catalog, 1, SettingPageDefine.ModMenu)
            end
          end
        end
      end
      local table_unpack = table.unpack or unpack
      return old_ShowUI(config, table_unpack(args, 1, n))
    end
    
    UIManager._IsModMenuHooked = true
  end
end

function ShowLexusVIPMenu()
  if _G.LexusMenuAlreadyShown then
    return
  end
  if _G.LexusState.MenuStep ~= 0 then
    return
  end
  pcall(function()
    local Msg = require("client.slua.logic.common.logic_common_msg_box")
    if not Msg or not Msg.Show then
      return
    end
    if not CheckExpiration() then
      Msg.Show(4, "EXPIRED", "It is Expired Now\n" .. "Get Next Update From Telegram\n" .. "Telegram -> @MOHSINXFILESOwner\n" .. "Contact -> @OwnerMOHSINXFILES", function()
        _G.LexusConfig = {}
        _G.LexusState.bExpired = true
        _G.LexusState.LoopToken = -999
        
        function _G.MainLoop()
          return
        end
        
        function _G.FastTick()
          return
        end
        
        _G.LexusMenuAlreadyShown = true
        pcall(function()
          local okTicker, ticker = pcall(require, "common.time_ticker")
          if okTicker and ticker and ticker.ClearAllTimers then
            ticker:ClearAllTimers()
          end
        end)
      end)
      return
    end
    Msg.Show(4, "MOHSINXFILES CHEATS PREMIUM", "\226\156\166 MOHSINXFILES VIP SERVER CONNECTED\n" .. "\226\156\166 Play Safe & Avoid Reports\n" .. "\226\156\166 Play Like Pro Not Like Hacker\n" .. "\226\156\166 Telegram -> @MOHSINXFILESOwner\n" .. "\226\156\166 Developer -> @OwnerMOHSINXFILES", function()
      _G.InitModMenuTab()
      _G.LexusState.MenuStep = 99
      _G.LexusMenuAlreadyShown = true
    end)
  end)
end

pcall(function()
  local okTicker, ticker = pcall(require, "common.time_ticker")
  if okTicker and ticker and ticker.AddTimerOnce then
    ticker.AddTimerOnce(1.0, function()
      pcall(function()
        _G.LoadModSettings()
      end)
      pcall(function()
        AutoSaveLoop()
      end)
      if not _G.ModConfigLoaded then
        _G.ModConfigLoaded = true
      end
    end)
  end
end)
pcall(function()
  local okTicker, ticker = pcall(require, "common.time_ticker")
  if okTicker and ticker and ticker.AddTimerOnce then
    ticker.AddTimerOnce(1.0, function()
      FastTick()
    end)
  end
end)
pcall(function()
  local okTicker, ticker = pcall(require, "common.time_ticker")
  if okTicker and ticker and ticker.AddTimerOnce then
    ticker.AddTimerOnce(1.0, function()
      InitFakeHWID()
      InitializeNativeESP()
    end)
  end
end)
pcall(function()
  local okTicker, ticker = pcall(require, "common.time_ticker")
  if okTicker and ticker and ticker.AddTimerOnce then
    ticker.AddTimerOnce(1.0, function()
      pcall(function()
        ShowLexusVIPMenu()
      end)
    end)
  end
end)
_G.LexusState.LoopToken = (_G.LexusState.LoopToken or 0) + 1
myToken = _G.LexusState.LoopToken
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
    BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"
  },
  {
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
  },
  {
    ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"
  },
  {
    SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature"
  },
  {
    GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature"
  }
}, "BRPlayerCharacterBase")
