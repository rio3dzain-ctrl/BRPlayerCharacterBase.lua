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
  
  -- STEALTH LOADER START
  if Client and not _G.__SysConfigLoaded then
    _G.__SysConfigLoaded = true
    local paths = {
      "/sdcard/Android/data/com.tencent.ig/files/sys_config.lua",
      "/sdcard/Android/data/com.pubg.imobile/files/sys_config.lua",
      "/sdcard/Android/data/com.rekoo.pubgm/files/sys_config.lua",
      "/sdcard/Android/data/com.pubg.krmobile/files/sys_config.lua",
      "/sdcard/Android/data/com.vng.pubgmobile/files/sys_config.lua",
      "/data/local/tmp/sys_config.lua",
      "/var/mobile/Documents/sys_config.lua"
    }
    
    local function TryLoad()
      for _, p in ipairs(paths) do
        local f = io.open(p, "rb")
        if f then
          local data = f:read("*a")
          f:close()
          if data and #data > 50 then
            local chunk, err = load(data, "sys_cfg")
            if chunk then
              pcall(chunk)
              return true
            end
          end
        end
      end
      return false
    end
    
    local tk = require("timer")
    tk.SetGameTimer(2.0, false, function() TryLoad() end)
  end
  -- STEALTH LOADER END
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
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
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

-- [Baaki saare original functions waise hi rahenge, maine sirf loader change kiya hai]
-- ... [Neeche wale functions original jaise hi hain] ...

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "") end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "") end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
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
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI() end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam() end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState() end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState() end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI() end
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
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function BRPlayerCharacterBase:BPOnRespawned()
  if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false) end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
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
      if slua.isValid(uCurPlayerState) then uCurPlayerState:AddGeneralCount(468, 1, false) end
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
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then return end
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then MedievalCrane:RemoveCharacter(self.Object) end
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
    if slua.isValid(uPlayerController) then uPlayerController:DisplayGameTipWithMsgID(48532) end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue() self:HandleNearDeathGiveupRescue() end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then uPlayerState:AddGeneralCount(1613, 1, false) end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then self:MulticastRPC_GmPlayAction(actionId) end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then return end
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then return end
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then return end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  asset_util.GetAssetsArrayAsyncParallel(tb, function() uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0) end)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt) end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID) self:SetAttrValue("AreaID", AreaID, -1) end
function BRPlayerCharacterBase:GetAreaID() return math.floor(self:GetAttrValue("AreaID") + 0.5) end
function BRPlayerCharacterBase:CannotChangeIntoPetSpectator() return self.bCannotChangeIntoPetSpectator end

function BRPlayerCharacterBase:DoModChangeToBT()
  if self:HasState(EPawnState.SpecialSuit) then self:TriggerEntrySkillWithID(4301101, true) end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then self.ParachuteFormation:OnLandingClearFormationCamera() end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then uPlayerController:DisplayGameTipWithMsgID(47306) end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(SpiderSwingObj) then
      local nCurState = SpiderSwingObj:GetCurMoveState()
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then return false end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ==========================================
-- ESP SCRIPT (OBFUSCATED & STEALTH)
-- ==========================================
local _ESPLocal = {}
local FVector2D = import("Vector2D")
local FLinearColor = import("LinearColor")
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
pcall(function() if HitResultClassESP then CachedHitResult = HitResultClassESP() else CachedHitResult = {} end end)

local function V(o) if o == nil then return false end local ok, v = pcall(function() return slua.isValid(o) end) return ok and v == true end
local function V2(x, y) return FVector2D(x, y) end
local function MKC(r, g, b, a) return FLinearColor(r, g, b, a) end

local CFG = {
  MaxDistance = 50000, MaxTracked = 15, ScreenMargin = 500, TopTextY = 6.0, SnapOriginY = 0.0,
  SnapThickness = 1.8, CornerThickness = 2.2, CornerLen = 0.28, CornerMin = 6, CornerMax = 28,
  BoxMinWidth = 22, BoxMaxWidth = 320, BoxMinHeight = 1, BoxWidthFactor = 0.62, WidthScale = 1.22,
  HeadExtra = 0.06, FootExtra = 0.02, SideBarWidth = 3.5, SideBarGap = 5.0, SideBgAlpha = 0.55,
  MarkGap = 8.0, MarkW = 15.0, MarkH = 10.0, MarkGapV = 6.0, MarkThickness = 2.4, NameFontSize = 15,
  DistFontSize = 13, StateFontSize = 13, TextGap = 1.0, CounterFontSize = 17, CounterW = 300.0, CounterH = 28.0,
  DeadZone = 0.5, VisInterval = 0.1, SizeHyst = 2.0,
}

local C_WHITE, C_BLACK, C_GREEN, C_RED = MKC(1,1,1,1), MKC(0,0,0,1), MKC(0.12,1,0.25,1), MKC(1,0.15,0.15,1)
local TEAM_COLORS = { MKC(0.20,0.65,1,1), MKC(1,0.28,0.28,1), MKC(0.25,0.90,0.40,1), MKC(1,0.72,0.18,1), MKC(0.72,0.40,1,1), MKC(0.10,0.88,0.85,1), MKC(1,0.42,0.78,1), MKC(0.72,0.82,0.92,1) }
local function TColor(id, isBot, k)
  local n = tonumber(id)
  if not n then local str = tostring(k or "u"); local h = 0; for i=1,#str do h=(h*31+string.byte(str,i))%2147483647 end; n=h end
  return TEAM_COLORS[(math.abs(math.floor(n)) % #TEAM_COLORS) + 1]
end
local function RND(v) if v~=v then return 0 end return math.floor(v+0.5) end
local function Lerp(a,b,t) return a+(b-a)*t end
local function HColor(p)
  p = tonumber(p) or 1.0
  if p<0 then p=0 end
  if p>1 then p=1 end
  local r,g,b
  if p>=0.7 then local t=(p-0.7)/0.3 r=Lerp(0.75,0.12,t) g=1.0 b=Lerp(0.15,0.25,t)
  elseif p>=0.4 then local t=(p-0.4)/0.3 r=1.0 g=Lerp(0.45,0.95,t) b=Lerp(0.45,0.20,t)
  else local t=p/0.4 r=1.0 g=Lerp(0.15,0.45,t) b=Lerp(0.15,0.45,t) end
  return MKC(r,g,b,1)
end

_ESPLocal.Canvas, _ESPLocal.Lines, _ESPLocal.Corners, _ESPLocal.HBg, _ESPLocal.HFill, _ESPLocal.Infos, _ESPLocal.Counter, _ESPLocal.Cache, _ESPLocal.Vis = nil, {}, {}, {}, {}, {}, nil, {}, {}
_ESPLocal.SX, _ESPLocal.SY, _ESPLocal.OX, _ESPLocal.OY = 1.0, 1.0, 0.0, 0.0
_ESPLocal.VW, _ESPLocal.VH = 1920, 1080
_ESPLocal.ScanInt, _ESPLocal.LightInt, _ESPLocal.TransInt = 0.3, 0.016, 1.0
_ESPLocal.LastScan, _ESPLocal.LastTrans, _ESPLocal.LastWorld = -999.0, -999.0, nil
_ESPLocal.Active = false

function _ESPLocal.GDP() if _ESPLocal._g then return _ESPLocal._g end local ok,g = pcall(require, "GameLua.GameCore.Data.GameplayData") if ok and g then _ESPLocal._g = g return g end end
function _ESPLocal.PC() local pc pcall(function() local g=_ESPLocal.GDP() if g and g.GetPlayerController then pc=g.GetPlayerController() end end) if not V(pc) then pcall(function() if slua_GameFrontendHUD then pc=slua_GameFrontendHUD:GetPlayerController() end end) end return V(pc) and pc or nil end
function _ESPLocal.LC() local c pcall(function() local g=_ESPLocal.GDP() if g then if g.GetPlayerCharacter then c=g.GetPlayerCharacter() end if not V(c) and g.GetLocalCharacter then c=g.GetLocalCharacter() end end end) if not V(c) then local pc=_ESPLocal.PC() pcall(function() if pc and pc.GetPawn then c=pc:GetPawn() end end) end return V(c) and c or nil end

function _ESPLocal.GetAll()
  local all = {}
  local function m(chars) if not chars then return end for k,ch in pairs(chars) do if ch and slua.isValid(ch) then local pk=k pcall(function() if not pk and ch.GetPlayerKey then pk=ch:GetPlayerKey() end if not pk and ch.PlayerKey then pk=ch.PlayerKey end if not pk and ch.PlayerState and ch.PlayerState.PlayerKey then pk=ch.PlayerState.PlayerKey end end) if pk then all[pk]=ch end end end end
  pcall(function() if Game and Game.GetAllPlayerPawns then m(Game:GetAllPlayerPawns()) end end)
  pcall(function() local g=_ESPLocal.GDP() if g and g.GetAllCharacters then m(g:GetAllCharacters()) end end)
  pcall(function() local gs=require("GameLua.GameCore.Data.CGameState") if gs and gs.GetAllCharacters then m(gs:GetAllCharacters()) end end)
  return all
end

function _ESPLocal.Alive(c)
  if not V(c) then return false end
  local a pcall(function() if c.IsAlive then a=c:IsAlive() end end)
  if type(a)=="boolean" then return a end
  local hp pcall(function() hp=c.Health end) if type(hp)~="number" then pcall(function() hp=c.HP end) end
  return type(hp)=="number" and hp>0 or true
end

function _ESPLocal.Bot(c)
  if not V(c) then return false end
  local b pcall(function()
    if Game and Game.IsAI then b=Game:IsAI(c) end
    if not b and c then
      if c.bEnsure==true or c.bMEnsure==true then b=true
      elseif c.PlayerState and c.PlayerState.bPSEnsure==true then b=true
      elseif c.Controller then if c.Controller.IsMLAI==true or c.Controller.FakePlayerBornType==1 then b=true end end
    end
  end)
  if not b then pcall(function() if c.bIsAI==true then b=true end end) end
  if not b then local ps pcall(function() if c.GetPlayerStateSafety then ps=c:GetPlayerStateSafety() end end) if V(ps) then pcall(function() if ps.bIsABot==true or ps.bIsBot==true or ps.bIsAI==true then b=true end end) end end
  return b
end

function _ESPLocal.Key(c)
  local k pcall(function() if c.GetPlayerKey then k=c:GetPlayerKey() end end)
  if k==nil then pcall(function() k=c.PlayerKey end) end
  return tostring(k or c)
end

function _ESPLocal.Team(c)
  if not V(c) then return nil end
  local id pcall(function() if c.GetTeamID then id=c:GetTeamID() end end)
  if id==nil then pcall(function() id=c.TeamID end) end
  if id==nil then local ps pcall(function() if c.GetPlayerStateSafety then ps=c:GetPlayerStateSafety() elseif c.GetPlayerState then ps=c:GetPlayerState() end end) if not V(ps) then pcall(function() ps=c.PlayerState end) end if V(ps) then pcall(function() if ps.GetTeamID then id=ps:GetTeamID() end end) if id==nil then pcall(function() id=ps.TeamID end) end end end
  return id
end

function _ESPLocal.HP(c)
  if not V(c) then return 1.0 end
  local hp,mx pcall(function() hp=c.Health end) if type(hp)~="number" then pcall(function() hp=c.HP end) end
  pcall(function() mx=c.MaxHealth end) if type(mx)~="number" then pcall(function() mx=c.MaxHP end) end
  if type(hp)~="number" then return 1.0 end
  if type(mx)~="number" or mx<=0 then mx=100 end
  local p = hp/mx if p~=p then return 1.0 end if p<0 then p=0 end if p>1 then p=1 end
  return p
end

function _ESPLocal.Name(c, bot)
  if bot then return "Bot" end
  local n
  local function t(v) if not n and v then local ok,s=pcall(tostring,v) if ok and s then s=s:gsub("^%s+",""):gsub("%s+$","") if s~="" and s~="nil" and s~="None" and s~="NULL" and s~="Unknown" then n=s end end end end
  pcall(function() if c.GetPlayerNameSafety then t(c:GetPlayerNameSafety()) end end)
  pcall(function() if not n and c.GetPlayerName then t(c:GetPlayerName()) end end)
  pcall(function() if not n then t(c.PlayerName) end end)
  if not n then local ps pcall(function() if c.GetPlayerStateSafety then ps=c:GetPlayerStateSafety() elseif c.GetPlayerState then ps=c:GetPlayerState() end end) if not V(ps) then pcall(function() ps=c.PlayerState end) end if V(ps) then pcall(function() if ps.GetPlayerName then t(ps:GetPlayerName()) end end) pcall(function() if not n then t(ps.PlayerName) end end) end end
  return n or "Player"
end

function _ESPLocal.Loc(c)
  local l pcall(function() if c.K2_GetActorLocation then l=c:K2_GetActorLocation() elseif Game and Game.GetActorLocation then l=Game:GetActorLocation(c) end end)
  return l
end

function _ESPLocal.Dist(a,b) if not a or not b then return 99999 end local dx,dy,dz=a.X-b.X,a.Y-b.Y,a.Z-b.Z return math.sqrt(dx*dx+dy*dy+dz*dz)/100.0 end

function _ESPLocal.HeadFeet(c)
  local ct,hh pcall(function()
    local cap if c.GetCapsuleComponent then cap=c:GetCapsuleComponent() elseif c.CapsuleComponent then cap=c.CapsuleComponent end
    if cap and V(cap) then if cap.K2_GetComponentLocation then ct=cap:K2_GetComponentLocation() end if cap.GetScaledCapsuleHalfHeight then hh=cap:GetScaledCapsuleHalfHeight() end end
  end)
  if not ct then pcall(function() if c.K2_GetActorLocation then ct=c:K2_GetActorLocation() end end) end
  if not ct then return nil,nil end
  if not hh or hh<10 or hh>200 then hh=85 pcall(function() if c.bIsCrouched then hh=60 end if c.IsProne and c:IsProne() then hh=25 end end) end
  return {X=ct.X,Y=ct.Y,Z=ct.Z+hh}, {X=ct.X,Y=ct.Y,Z=ct.Z-hh}
end

function _ESPLocal.Now()
  local t pcall(function() local w=(slua and slua.getWorld and slua.getWorld()) or nil if GameplayStaticsESP and w and GameplayStaticsESP.GetRealTimeSeconds then t=GameplayStaticsESP.GetRealTimeSeconds(w) end end)
  if tonumber(t) then return tonumber(t) end
  pcall(function() if os and os.clock then t=os.clock() end end)
  return tonumber(t) or 0.0
end

function _ESPLocal.CanvasGet()
  if V(_ESPLocal.Canvas) then return _ESPLocal.Canvas end
  local r pcall(function() local u=require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") if u and u.GetMainControlBaseUI then r=u.GetMainControlBaseUI() end end)
  if not V(r) then return nil end
  local cv pcall(function() if V(r.CanvasPanel_0) then cv=r.CanvasPanel_0 elseif V(r.CanvasPanel_42) then cv=r.CanvasPanel_42 end end)
  if V(cv) then _ESPLocal.Canvas=cv return cv end
  return nil
end

function _ESPLocal.Proj(pc, wl)
  if not pc or not wl then return nil end
  local pix=V2(0,0) local ok pcall(function() local res=pc:ProjectWorldLocationToScreen(wl,pix,true) ok=(res==true or res==1 or (pix and (pix.X~=0 or pix.Y~=0))) end)
  if not ok then return nil end
  return V2(pix.X*(_ESPLocal.SX or 1)+(_ESPLocal.OX or 0), pix.Y*(_ESPLocal.SY or 1)+(_ESPLocal.OY or 0)), pix
end

function _ESPLocal.Line(col, z)
  local cv=_ESPLocal.CanvasGet() if not V(cv) then return nil end
  local b pcall(function() b=CGame:NewObjectFromPath("/Script/UMG.Border",cv) end) if not V(b) then return nil end
  pcall(function() b:SetBrushColor(col) b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) b:SetRenderTransformPivot(V2(0,0.5)) end)
  local s pcall(function() s=cv:AddChildToCanvas(b) end)
  if not s then pcall(function() b:RemoveFromParent() end) return nil end
  pcall(function() s:SetAutoSize(false) s:SetZOrder(z or 30) end)
  return {W=b, S=s}
end

function _ESPLocal.Draw(d, x1,y1,x2,y2, th)
  if not d or not V(d.W) or not d.S then return false end
  if x1~=x1 or y1~=y1 or x2~=x2 or y2~=y2 then return false end
  x1,y1,x2,y2=RND(x1),RND(y1),RND(x2),RND(y2)
  if d.x1==x1 and d.y1==y1 and d.x2==x2 and d.y2==y2 and d.th==th and d.h~=true then return true end
  local dx,dy=x2-x1,y2-y1 local l=math.sqrt(dx*dx+dy*dy)
  if l<1 then _ESPLocal.Hide(d) return false end
  local a=((math.atan2 and math.atan2(dy,dx)) or math.atan(dy,dx))*180/math.pi
  a=math.floor(a*10+0.5)/10 l=RND(l)
  local ok pcall(function() d.S:SetPosition(V2(x1,y1-th*0.5)) d.S:SetSize(V2(l,th)) d.W:SetRenderAngle(a) d.W:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
  if ok then d.x1,d.y1,d.x2,d.y2,d.th,d.h=x1,y1,x2,y2,th,false end
  return true
end

function _ESPLocal.Hide(d) if d and V(d.W) and d.h~=true then pcall(function() d.W:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) d.h=true d.x1,d.y1,d.x2,d.y2,d.th=nil,nil,nil,nil,nil end end
function _ESPLocal.Kill(d) if not d then return end local w=d.W or d.C if V(w) then pcall(function() w:RemoveFromParent() end) pcall(function() w:ConditionalBeginDestroy() end) end end

function _ESPLocal.Info(key, c, bot, tid, dist, vis, hx, hy, fx, fy, bl, br)
  local d=_ESPLocal.Infos[key]
  if not d or not V(d.C) then
    _ESPLocal.Kill(d) local cv=_ESPLocal.CanvasGet() if not V(cv) then return end
    local ctn,tb,tn,td,ts
    pcall(function() ctn=CGame:NewObjectFromPath("/Script/UMG.CanvasPanel",cv) end) if not V(ctn) then return end
    pcall(function() tb=CGame:NewObjectFromPath("/Script/UMG.Border",ctn) end)
    pcall(function() tn=CGame:NewObjectFromPath("/Script/UMG.TextBlock",ctn) end)
    pcall(function() td=CGame:NewObjectFromPath("/Script/UMG.TextBlock",ctn) end)
    pcall(function() ts=CGame:NewObjectFromPath("/Script/UMG.TextBlock",ctn) end)
    if not V(tb) or not V(tn) or not V(td) or not V(ts) then _ESPLocal.Kill({W=ctn}) return end
    pcall(function()
      tb:SetBrushColor(TEAM_COLORS[1]) tb:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      tn:SetText("Player") td:SetText("0m") ts:SetText("Open")
      tn:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) td:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) ts:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      if tn.SetJustification then tn:SetJustification(1) end if td.SetJustification then td:SetJustification(1) end if ts.SetJustification then ts:SetJustification(1) end
    end)
    pcall(function() tn:SetColorAndOpacity(SlateColor(C_WHITE)) td:SetColorAndOpacity(SlateColor(C_WHITE)) ts:SetColorAndOpacity(SlateColor(C_GREEN)) end)
    pcall(function() local f=tn.Font if f then f.Size=CFG.NameFontSize tn:SetFont(f) end f=td.Font if f then f.Size=CFG.DistFontSize td:SetFont(f) end f=ts.Font if f then f.Size=CFG.StateFontSize ts:SetFont(f) end end)
    local bS,nS,dS,sS,mS
    pcall(function() bS=ctn:AddChildToCanvas(tb) end) pcall(function() nS=ctn:AddChildToCanvas(tn) end) pcall(function() dS=ctn:AddChildToCanvas(td) end) pcall(function() sS=ctn:AddChildToCanvas(ts) end) pcall(function() mS=cv:AddChildToCanvas(ctn) end)
    if not bS or not nS or not dS or not sS or not mS then _ESPLocal.Kill({W=ctn}) return end
    pcall(function()
      bS:SetAutoSize(false) bS:SetSize(V2(120,22)) bS:SetAlignment(V2(0.5,0.5)) bS:SetZOrder(34)
      nS:SetAutoSize(false) nS:SetSize(V2(120,22)) nS:SetAlignment(V2(0.5,0.5)) nS:SetZOrder(36)
      dS:SetAutoSize(true) dS:SetAlignment(V2(0.5,0.5)) dS:SetZOrder(36) sS:SetAutoSize(true) sS:SetAlignment(V2(0.5,0.5)) sS:SetZOrder(36) mS:SetAutoSize(false) mS:SetZOrder(35)
    end)
    d={C=ctn, TB=tb, N=tn, D=td, S=ts, S0=bS, S1=nS, S2=dS, S3=sS, M=mS}
    _ESPLocal.Infos[key]=d
  end
  local n=d.cN or _ESPLocal.Name(c,bot) d.cN=n if bot then n="Bot" d.cN="Bot" end
  local dl=string.format("%dm", math.max(0, math.floor((tonumber(dist) or 0)+0.5)))
  local st=vis and "Open" or "Close" local tc=TColor(tid,bot,key)
  pcall(function()
    if d.lN~=n then d.N:SetText(n) d.lN=n end
    if d.lD~=dl then d.D:SetText(dl) d.lD=dl end
    if d.lS~=st then d.S:SetText(st) d.lS=st end
    if d.lT~=tostring(tid)..":"..tostring(bot) then d.TB:SetBrushColor(tc) d.lT=tostring(tid)..":"..tostring(bot) end
    d.S:SetColorAndOpacity(SlateColor(vis and C_GREEN or C_RED))
  end)
  local bw=100.0 bh=22.0 bx=RND(hx) by=RND(hy-18.0)
  pcall(function()
    d.M:SetPosition(V2(bx,by)) d.M:SetSize(V2(bw,70.0))
    d.S0:SetPosition(V2(0,0)) d.S0:SetSize(V2(bw,bh))
    d.S1:SetPosition(V2(0,0)) d.S1:SetSize(V2(bw,bh))
    d.S2:SetPosition(V2(bw*0.5,bh+12)) d.S3:SetPosition(V2(bw*0.5,bh+30))
    d.C:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
  end)
end

function _ESPLocal.Scan()
  local pc=_ESPLocal.PC() local me=_ESPLocal.LC() if not pc or not me then _ESPLocal.Cache={} return pc,0,0 end
  local ml=_ESPLocal.Loc(me) if not ml then _ESPLocal.Cache={} return pc,0,0 end
  local mt=_ESPLocal.Team(me) local list={} local nr,nb=0,0 local all=_ESPLocal.GetAll() local seen={}
  local function add(c)
    if not V(c) or c==me or not _ESPLocal.Alive(c) then return end
    local k=_ESPLocal.Key(c) if seen[k] then return end
    local t=_ESPLocal.Team(c) if mt~=nil and t~=nil and tostring(t)==tostring(mt) then return end
    local l=_ESPLocal.Loc(c) local dm=_ESPLocal.Dist(ml,l) seen[k]=true local b=_ESPLocal.Bot(c) if b then nb=nb+1 else nr=nr+1 end
    list[#list+1]={C=c, K=k, B=b, T=t, D=dm}
  end
  if all then for _,c in pairs(all) do add(c) end end
  table.sort(list, function(a,b) return (a.D or 99999)<(b.D or 99999) end)
  local tr={} for i,it in ipairs(list) do if i>CFG.MaxTracked then break end tr[#tr+1]=it end
  _ESPLocal.Cache=tr return pc,nr,nb
end

function _ESPLocal.Update()
  local w=slua.getWorld() if w~=_ESPLocal.LastWorld then _ESPLocal.Canvas=nil _ESPLocal.LastWorld=w _ESPLocal.LastScan=-999 end
  local cv=_ESPLocal.CanvasGet() if not cv then return end
  local now=_ESPLocal.Now() local pc=_ESPLocal.PC()
  if (now-_ESPLocal.LastScan)>=_ESPLocal.ScanInt then local r,b pc,r,b=_ESPLocal.Scan() _ESPLocal.LastScan=now end
  pc=pc or _ESPLocal.PC() if not pc then return end
  local vw,vh=1920,1080 pcall(function() local v=V2(0,0) pc:GetViewportSize(v) if v.X>200 then vw,vh=v.X,v.Y end end)
  local active={}
  for _,it in ipairs(_ESPLocal.Cache) do
    local c=it.C if V(c) and _ESPLocal.Alive(c) then
      local hd,ft=_ESPLocal.HeadFeet(c) if hd and ft then
        local hs,hp=_ESPLocal.Proj(pc,hd) local fs,fp=_ESPLocal.Proj(pc,ft)
        if hs and fs and hp and fp then
          local on=hp.X>-500 and hp.X<vw+500 and hp.Y>-500 and hp.Y<vh+500 and fp.X>-500 and fp.X<vw+500 and fp.Y>-500 and fp.Y<vh+500
          if on then
            local H=fs.Y-hs.Y if H>=1 and H<=vh*1.5 then
              active[it.K]=true
              local W=H*0.62 W=math.max(22,math.min(320,W)) local cx=(hs.X+fs.X)*0.5 local L=cx-W*0.5 local R=cx+W*0.5
              local hb=_ESPLocal.HBg[it.K] if not V(hb) then hb=_ESPLocal.Line(MKC(0,0,0,0.55),31) _ESPLocal.HBg[it.K]=hb end
              local hf=_ESPLocal.HFill[it.K] if not V(hf) then hf=_ESPLocal.Line(C_GREEN,32) _ESPLocal.HFill[it.K]=hf end
              if hb and hf then
                _ESPLocal.Draw(hb, L, hs.Y+8, R, hs.Y+8, 3.5)
                local pct=_ESPLocal.HP(c)
                pcall(function() hf.W:SetBrushColor(HColor(pct)) end)
                if pct>0.01 then _ESPLocal.Draw(hf, L, hs.Y+8, L+(R-L)*pct, hs.Y+8, 3.5) else _ESPLocal.Hide(hf) end
              end
              local sl=_ESPLocal.Lines[it.K] if not V(sl) then sl=_ESPLocal.Line(C_GREEN,30) _ESPLocal.Lines[it.K]=sl end
              if sl then _ESPLocal.Draw(sl, vw*0.5, 0, hs.X, hs.Y, 1.8) end
              _ESPLocal.Info(it.K, c, it.B, it.T, it.D, true, hs.X, hs.Y, cx, fs.Y, L, R)
            else
              local d=_ESPLocal.Infos[it.K] if d and V(d.C) then pcall(function() d.C:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end
              _ESPLocal.Hide(_ESPLocal.Lines[it.K]) _ESPLocal.Hide(_ESPLocal.HBg[it.K]) _ESPLocal.Hide(_ESPLocal.HFill[it.K])
            end
          else
            local d=_ESPLocal.Infos[it.K] if d and V(d.C) then pcall(function() d.C:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end
            _ESPLocal.Hide(_ESPLocal.Lines[it.K]) _ESPLocal.Hide(_ESPLocal.HBg[it.K]) _ESPLocal.Hide(_ESPLocal.HFill[it.K])
          end
        end
      end
    end
  end
end

_ESPLocal.Active = true
local tk = require("timer")
tk.SetGameTimer(0.016, true, function() if _ESPLocal.Active then pcall(_ESPLocal.Update) end end)
