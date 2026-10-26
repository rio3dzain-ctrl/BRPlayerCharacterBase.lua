local BRPlayerCharacterBase = { ServerRPC={}, ClientRPC={}, MulticastRPC={}, LuaEventContainer={} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable=true, Params={} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable=true, Params={ UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable=true, Params={ UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable=true, Params={ UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable=true, Params={ UEnums.EPropertyClass.Bool } }

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

local _EM = { start = function() end }

function BRPlayerCharacterBase:ctor() end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local C = import("CheckFallingDistanceComponent")
    if slua.isValid(C) and not slua.isValid(self:GetComponentByClass(C)) then
      Game:AddComponent(C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then self.STCharacterMovement.bPositiveBlowUp = true end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", { AttrName={ "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
    if Client then pcall(function() _EM.start(self) end) end
  end
  if Client then
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1]="FinishedState" }, self.HandleFinishedState, self)
    self:AddControlEvent(self, "OnPawnRespawnDelegate", self.OnRespawnRehideCheck, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) then pc:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "") end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(s)
  if s == EPawnState.SwitchPP then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) then pc:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "") end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local M = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(M.Bit0, true)
  end
end

function BRPlayerCharacterBase:OnRespawnRehideCheck()
  if not self:GetEnsure() then return end
  self:AddGameTimer(0.5, false, function()
    if not slua.isValid(self.Object) then return end
    if self:HasState(EPawnState.InPlane) then
      self:SetCharacterHideInGame(true, true, true, 1, ECharacterHideMovementAcive.Normal)
    end
  end)
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local t = CGameMode.GameModeType
    local id = tonumber(CGameState.GameModeID)
    local ok = t == EGameModeType.ETypicalGameMode or t == EGameModeType.EFourInOneGameMode or t == EGameModeType.EHeavyWeaponGameMode
    return ok and not MatchModeIds[id]
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(L, N)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, L, N)
  if not Client then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) and pc.CheckParachuteOpenFeature then
      if N == EParachuteState.PS_Opening and pc.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
        pc.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
      elseif N == EParachuteState.PS_None then
        if pc.CheckParachuteOpenFeature.RecoverParachuteOpenParam then pc.CheckParachuteOpenFeature:RecoverParachuteOpenParam() end
        if pc.CheckParachuteOpenFeature.ClearTimerAndState then pc.CheckParachuteOpenFeature:ClearTimerAndState() end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
  if not Client then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) and pc.CheckParachuteOpenFeature then
      if pc.CheckParachuteOpenFeature.ClearTimerAndState then pc.CheckParachuteOpenFeature:ClearTimerAndState() end
      if pc.CheckParachuteOpenFeature.ResetCheckShowUI then pc.CheckParachuteOpenFeature:ResetCheckShowUI() end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(R)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, R)
  if Client then GameplayData.RemoveCharacter(self.Object) end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local gs = GameplayData:GetGameState()
  if slua.isValid(gs) and Game:IsClassOf(gs, STExtraGameStateBase) then
    return gs.GameModeType == EGameModeType.EWarGameMode
  end
  return false
end

function BRPlayerCharacterBase:BPOnRecycled() if Client then self:ResetMeshRelativeLocationAndRotation() end end
function BRPlayerCharacterBase:BPOnRespawned() if Client then self:ResetMeshRelativeLocationAndRotation() end end
function BRPlayerCharacterBase:ReceiveOnRecycle()
  if Client then self:ResetMeshRelativeLocationAndRotation() GameplayData.RemoveCharacter(self.Object) end
end
function BRPlayerCharacterBase:ReceiveOnSpawn()
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
    if self.Role == ENetRole.ROLE_AutonomousProxy then pcall(function() _EM.start(self) end) end
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local r = FRotator(0, -90, 0)
    local l = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then self.Mesh:K2_SetRelativeRotation(r, false, nil, false) end
    self:CacheInitialMeshOffset(l, r)
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement)
     and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking
     and UIManager.UI_Config_InGame.ParachuteOpenUI then
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord() end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  if not UKismetSystemLibrary.IsDedicatedServer(self) then return end
  local pc = self:GetPlayerControllerSafety()
  if not slua.isValid(pc) then return end
  local av = self.CharacterAvatarComp2_BP
  if not slua.isValid(av) then return end
  local U = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local vID = U:ChangeVehicleSkinByClothes(pc, av)
  local S = import("ESTExtraVehicleShapeType")
  if vID then
    local AU = import("AvatarUtils")
    if AU.GetVehicleShapeBySkinID(vID) == S.VST_Horse then
      local ps = self:GetPlayerStateSafety()
      if slua.isValid(ps) then ps:AddGeneralCount(468, 1, false) end
    end
  end
end

function BRPlayerCharacterBase:ParachuteJump()
  local pc = self:GetControllerSafety()
  if slua.isValid(pc) then
    if not self:GetEnsure() then
      if pc:GetCurrentStateType() ~= EStateType.State_ParachuteJump and pc:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        pc:ReInitParachuteItem()
        pc:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uC, uN, uO)
  if uC ~= self.Object then return end
  local M = self:GetMedievalCraneFromBase(uN)
  if M and M.AddCharacter then M:AddCharacter(self.Object)
  else
    M = self:GetMedievalCraneFromBase(uO)
    if M and M.RemoveCharacter then M:RemoveCharacter(self.Object) end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(B)
  if not slua.isValid(B) or not B.GetOwner then return end
  local L = B:GetOwner()
  if not slua.isValid(L) or not L.AddCharacter then return end
  return L
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local ps = self:GetPlayerStateSafety()
  if not slua.isValid(ps) then return false end
  if ps.CanUseFlaregun == false and self:IsLocallyControlled() then
    local pc = self:GetPlayerControllerSafety()
    if slua.isValid(pc) then pc:DisplayGameTipWithMsgID(48532) end
  end
  return not ps.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue() self:HandleNearDeathGiveupRescue() end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local c = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(c) and self.bCanNearDeathGiveup == true then
    local ps = self:GetPlayerStateSafety()
    if slua.isValid(ps) then ps:AddGeneralCount(1613, 1, false) end
    c:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(id)
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then self:MulticastRPC_GmPlayAction(id) end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(id)
  if not Client then return end
  local c = self:GetPlayEmoteComponent()
  if not slua.isValid(c) then return end
  local LF = require("common.log_filter")
  LF.SetLogTreeEnable(true)
  local cfg = CDataTable.GetTableData("EmoteBPTable", id)
  if not cfg then return end
  local H = slua.loadObject(cfg.Path)
  local A = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local h = H()
  c:OnLoadEmoteAssetBegin(h, id, A, "")
  local tb = FuncUtil.LuaArrayToTable(A)
  local AU = require("common.asset_util")
  local function done() c:OnLoadEmoteAssetEnd(h, id, 0) end
  AU.GetAssetsArrayAsyncParallel(tb, done)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(v)
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = v
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(b)
  self.Super:OnPlayerLeaveCarryBoxState(b)
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(b) end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(box)
  if slua.isValid(box) and Game:IsClassOf(box, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(box)
  end
end

function BRPlayerCharacterBase:SetAreaID(id) self:SetAttrValue("AreaID", id, -1) end
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
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local W = self:GetWeaponBySlot(Slot)
    if slua.isValid(W) then
      local id = W:GetWeaponID()
      local cfg = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if cfg and cfg.CheckIsWeaponInBlackList and cfg.CheckIsWeaponInBlackList(id) then
        local pc = self:GetPlayerControllerSafety()
        if Client and slua.isValid(pc) and pc.Role == ENetRole.ROLE_AutonomousProxy then pc:DisplayGameTipWithMsgID(47306) end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local S = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(S) then
      local st = S:GetCurMoveState()
      if st == ESpiderSwingMoveState.Launching or st == ESpiderSwingMoveState.Swinging then return false end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- Emote resolve
local VICTORY_DANCE_FX_MAP = { [12219601] = 22010089 }
local isFitVersion = false
pcall(function()
  local P = require("client.slua.config.ClientMacros.PublishRegionMacros")
  if P and type(P.IsFITVersion) == "function" then isFitVersion = P.IsFITVersion() end
end)

local function RER(id)
  local fx = VICTORY_DANCE_FX_MAP[id]
  if not fx or fx == id then return id end
  local mu = nil
  pcall(function() mu = require("client.common.model_util") end)
  if not mu then return id end
  local bp = nil
  pcall(function() bp = mu.GetBPID(fx) end)
  local r = id
  if bp and bp > 0 and mu.IsBattleItemHandleExist and mu.IsBattleItemHandleExist("Emote", bp, false, false) then r = fx end
  if isFitVersion and r == 12219601 then return 12222069 end
  return r
end

function BRPlayerCharacterBase:GetEmoteHandlePath(id)
  local r = RER(id)
  if self.Super then return self.Super:GetEmoteHandlePath(r) end
  local mu = nil
  pcall(function() mu = require("client.common.model_util") end)
  if not mu then return "" end
  local bp = nil
  pcall(function() bp = mu.GetBPID(r) end)
  if not bp or bp <= 0 then return "" end
  local p = nil
  pcall(function() p = mu.GetPath("Emote", bp, false, false) end)
  return p or ""
end

function BRPlayerCharacterBase:GetEmoteHandle(id)
  local r = RER(id)
  if self.Super then return self.Super:GetEmoteHandle(r) end
  local mu = nil
  pcall(function() mu = require("client.common.model_util") end)
  if not mu then return nil end
  local bp = nil
  pcall(function() bp = mu.GetBPID(r) end)
  if not bp or bp <= 0 then return nil end
  local C = nil
  pcall(function() C = mu.GetClass("Emote", bp, false, false) end)
  if not C then return nil end
  local h = nil
  pcall(function() h = C() end)
  if not h or not slua.isValid(h) then return nil end
  return h
end

-- ========== BYPASS (targeted, no mod path block) ==========
local function _bp()
  if io and io.open then
    local _o = io.open
    io.open = function(p, m)
      if type(p) == "string" then
        local s = p:lower()
        if s:find("magisk") or s:find("supersu") or s:find("busybox")
           or s:find("/system/bin/su") or s:find("/system/xbin/su")
           or s:find("/proc/version") or s:find("/proc/self/maps")
           or s:find("/proc/self/status") or s:find("/proc/mounts") then
          return nil
        end
      end
      return _o(p, m)
    end
  end
  if os and os.getenv then
    local _e = os.getenv
    os.getenv = function(k)
      if type(k) == "string" then
        local s = k:lower()
        if s == "magisk" or s == "supersu" or s == "busybox"
           or s:find("root", 1, true) or s:find("superuser", 1, true) then return nil end
      end
      return _e(k)
    end
  end
  if string and string.dump then string.dump = function() return "" end end
end
pcall(_bp)

-- ========== ESP ==========
do
  local FV2 = _G.FVector2D or import("Vector2D")
  local FLC = _G.FLinearColor or import("LinearColor")
  local SBL, WLL, SLC, GSE, KSE, HRE = nil, nil, nil, nil, nil, nil
  pcall(function() SBL = import("SlateBlueprintLibrary") end)
  pcall(function() WLL = import("WidgetLayoutLibrary") end)
  pcall(function() SLC = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
  pcall(function() GSE = import("GameplayStatics") end)
  pcall(function() KSE = import("KismetSystemLibrary") end)
  pcall(function() HRE = import("HitResult") end)

  local TS = { X=0, Y=0, Z=0 }
  local HR = {}
  pcall(function() if HRE then HR = HRE() end end)

  local function V(o)
    if o == nil then return false end
    local ok, r = pcall(function() return slua.isValid(o) end)
    return ok and r == true
  end

  local function V2(x, y)
    if FV2 then return FV2(x, y) end
    return { X=x, Y=y }
  end

  local function MK(r, g, b, a)
    if FLC then return FLC(r, g, b, a) end
    return { R=r, G=g, B=b, A=a }
  end

  local CFG = {
    MaxTracked=15, ScreenMargin=500, SnapOriginY=0.0, SnapThickness=1.8,
    BoxMinWidth=22, BoxMaxWidth=320, BoxWidthFactor=0.62,
    BarWidth=3.5, BarBgAlpha=0.55,
    NameSize=15, DistSize=13, StateSize=13,
    DeadZone=0.5, VisInterval=0.1, SizeHyst=2.0, ScanInterval=0.3,
  }

  local CB = MK(0,0,0,1)
  local CG = MK(0.12,1.0,0.25,1.0)
  local CR = MK(1.0,0.15,0.15,1.0)
  local CW = MK(1,1,1,1)
  local TCLR = {
    MK(0.20,0.65,1.00,1.00), MK(1.00,0.28,0.28,1.00),
    MK(0.25,0.90,0.40,1.00), MK(1.00,0.72,0.18,1.00),
    MK(0.72,0.40,1.00,1.00), MK(0.10,0.88,0.85,1.00),
    MK(1.00,0.42,0.78,1.00), MK(0.72,0.82,0.92,1.00),
  }

  local function TC(tid, bot, fb)
    local n = tonumber(tid)
    if n then n = math.abs(math.floor(n))
    else
      local s = tostring(fb or "x") local h = 0
      for i = 1, #s do h = (h*31 + string.byte(s, i)) % 2147483647 end
      n = h
    end
    return TCLR[(n % #TCLR) + 1]
  end

  local function RND(v) if v ~= v then return 0 end return math.floor(v + 0.5) end
  local function LP(a, b, t) return a + (b - a) * t end

  local function HC(p)
    p = tonumber(p) or 1.0
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end
    local r, g, b
    if p >= 0.7 then local t=(p-0.7)/0.3 r=LP(0.75,0.12,t) g=1.0 b=LP(0.15,0.25,t)
    elseif p >= 0.4 then local t=(p-0.4)/0.3 r=1.0 g=LP(0.45,0.95,t) b=LP(0.45,0.20,t)
    else local t=p/0.4 r=1.0 g=LP(0.15,0.45,t) b=LP(0.15,0.45,t) end
    return MK(r, g, b, 1.0)
  end

  local E = {
    Canvas=nil, Lines={}, HBg={}, HFill={}, Infos={},
    Cache={}, Vis={}, SX=1.0, SY=1.0, OX=0.0, OY=0.0,
    VW=1920, VH=1080, LS=-999.0, LT=-999.0, LW=nil,
    PC=nil, On=false, _own_canvas=nil, _GDP=nil,
  }

  local function GDP()
    if E._GDP then return E._GDP end
    local ok, G = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
    if ok and G then E._GDP = G return G end
    return nil
  end

  local function World()
    local w = nil
    pcall(function() if slua and slua.getWorld then w = slua.getWorld() end end)
    return w
  end

  local function Now()
    local t = nil
    pcall(function()
      local w = World()
      if GSE and w and GSE.GetRealTimeSeconds then t = GSE.GetRealTimeSeconds(w) end
    end)
    if tonumber(t) then return tonumber(t) end
    pcall(function() if os and os.clock then t = os.clock() end end)
    return tonumber(t) or 0.0
  end

  local function PC()
    if V(E.PC) then return E.PC end
    local pc = nil
    pcall(function()
      local G = GDP()
      if G and type(G.GetPlayerController) == "function" then pc = G.GetPlayerController() end
    end)
    if not V(pc) then
      pcall(function()
        if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then
          pc = slua_GameFrontendHUD:GetPlayerController()
        end
      end)
    end
    if V(pc) then E.PC = pc return pc end
    return nil
  end

  local function Local()
    local c = nil
    pcall(function()
      local G = GDP()
      if G then
        if G.GetPlayerCharacter then c = G.GetPlayerCharacter() end
        if not V(c) and G.GetLocalCharacter then c = G.GetLocalCharacter() end
      end
    end)
    if not V(c) then
      local pc = PC()
      pcall(function() if pc and pc.GetPawn then c = pc:GetPawn() end end)
    end
    return V(c) and c or nil
  end

  local function All()
    local out = {}
    local function mg(cs)
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
    pcall(function() if Game and Game.GetAllPlayerPawns then mg(Game:GetAllPlayerPawns()) end end)
    pcall(function() local G = GDP() if G and G.GetAllCharacters then mg(G:GetAllCharacters()) end end)
    pcall(function()
      local GS = require("GameLua.GameCore.Data.CGameState")
      if GS and GS.GetAllCharacters then mg(GS:GetAllCharacters()) end
    end)
    return out
  end

  local function TID(c)
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

  local function Alive(c)
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

  local function Bot(c)
    if not V(c) then return false end
    local b = false
    pcall(function()
      if Game and Game.IsAI then b = Game:IsAI(c) end
      if not b then
        if c.bEnsure == true or c.bMEnsure == true then b = true
        elseif c.PlayerState and c.PlayerState.bPSEnsure == true then b = true
        elseif c.Controller then
          if c.Controller.IsMLAI == true or c.Controller.FakePlayerBornType == 1 then b = true end
        end
      end
    end)
    if not b then pcall(function() if c.bIsAI == true then b = true end end) end
    return b
  end

  local function Key(c)
    local k = nil
    pcall(function() if c.GetPlayerKey then k = c:GetPlayerKey() end end)
    if k == nil then pcall(function() k = c.PlayerKey end) end
    return tostring(k or c)
  end

  local function HP(c)
    if not V(c) then return 1.0 end
    local hp, mx = nil, nil
    pcall(function() hp = c.Health end)
    if type(hp) ~= "number" then pcall(function() hp = c.HP end) end
    pcall(function() mx = c.MaxHealth end)
    if type(mx) ~= "number" then pcall(function() mx = c.MaxHP end) end
    if type(hp) ~= "number" then return 1.0 end
    if type(mx) ~= "number" or mx <= 0 then mx = 100 end
    local p = hp / mx
    if p ~= p then return 1.0 end
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end
    return p
  end

  local function NM(v)
    if v == nil or v == false then return nil end
    local ok, t = pcall(tostring, v)
    if not ok or not t then return nil end
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" or t == "nil" or t == "None" or t == "NULL" then return nil end
    return t
  end

  local function Name(c, bot)
    if bot then return "Bot" end
    local n = nil
    local function tk(v) if not n then n = NM(v) end end
    pcall(function() if c.GetPlayerNameSafety then tk(c:GetPlayerNameSafety()) end end)
    pcall(function() if not n and c.GetPlayerName then tk(c:GetPlayerName()) end end)
    pcall(function() if not n then tk(c.PlayerName) end end)
    return n or "Player"
  end

  local function BPos(c, bn)
    if not V(c) or not bn then return nil end
    local p = nil
    pcall(function()
      if type(c.GetBonePos) == "function" then p = c:GetBonePos(bn, {X=0,Y=0,Z=0}) end
      if not p or (p.X==0 and p.Y==0 and p.Z==0) then
        if type(c.GetSocketLocation) == "function" then p = c:GetSocketLocation(bn) end
      end
      if (not p or (p.X==0 and p.Y==0 and p.Z==0)) and V(c.Mesh) and c.Mesh.GetSocketLocation then
        local m = c.Mesh:GetSocketLocation(bn)
        if m and not (m.X==0 and m.Y==0 and m.Z==0) then p = m end
      end
    end)
    return p
  end

  local function Cam(pc)
    local l = nil
    pcall(function()
      if GSE and GSE.GetPlayerCameraManager then
        local m = GSE.GetPlayerCameraManager(pc, 0)
        if V(m) and m.GetCameraLocation then l = m:GetCameraLocation() end
      end
    end)
    return l
  end

  local function BVis(pc, cam, tgt, bp)
    if not V(pc) or not V(tgt) or not bp or not cam then return false end
    if not KSE or not KSE.LineTraceSingle then return true end
    local dx, dy, dz = bp.X-cam.X, bp.Y-cam.Y, bp.Z-cam.Z
    local d = math.sqrt(dx*dx + dy*dy + dz*dz)
    if d < 300 then return true end
    TS.X = cam.X + (dx/d)*60
    TS.Y = cam.Y + (dy/d)*60
    TS.Z = cam.Z + (dz/d)*60
    local v = false
    pcall(function()
      local hit = KSE.LineTraceSingle(pc, TS, bp, 0, false, nil, 0, HR, true)
      if hit then
        local ha = nil
        if HR then
          if type(HR.GetActor) == "function" then ha = HR:GetActor()
          elseif HR.Actor then ha = HR.Actor end
        end
        if V(ha) and ha == tgt then v = true end
      else v = true end
    end)
    return v
  end

  local function Vis(k, pc, cam, c)
    local n = Now()
    local ch = E.Vis[k]
    if ch and (n - (ch.t or 0)) < CFG.VisInterval then return ch.b end
    local v = false
    if V(c) and V(pc) and cam then
      for _, bn in ipairs({"head","spine_03","pelvis"}) do
        local bp = BPos(c, bn)
        if bp and (bp.X~=0 or bp.Y~=0 or bp.Z~=0) then
          if BVis(pc, cam, c, bp) then v = true break end
        end
      end
    else v = true end
    E.Vis[k] = { b=v, t=n }
    return v
  end

  local function Pos(c)
    local l = nil
    if not V(c) then return nil end
    pcall(function()
      if c.K2_GetActorLocation then l = c:K2_GetActorLocation()
      elseif Game and Game.GetActorLocation then l = Game:GetActorLocation(c) end
    end)
    return l
  end

  local function DM(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.X-b.X, a.Y-b.Y, a.Z-b.Z
    return math.sqrt(dx*dx+dy*dy+dz*dz)/100.0
  end

  local function HF(c)
    if not V(c) then return nil, nil end
    local ct, hh = nil, nil
    local cp = nil
    pcall(function()
      if c.GetCapsuleComponent then cp = c:GetCapsuleComponent()
      elseif c.CapsuleComponent then cp = c.CapsuleComponent end
    end)
    if cp and V(cp) then
      pcall(function()
        if cp.K2_GetComponentLocation then ct = cp:K2_GetComponentLocation()
        elseif cp.GetComponentLocation then ct = cp:GetComponentLocation() end
        if cp.GetScaledCapsuleHalfHeight then hh = cp:GetScaledCapsuleHalfHeight()
        elseif cp.GetUnscaledCapsuleHalfHeight then hh = cp:GetUnscaledCapsuleHalfHeight()
        elseif cp.CapsuleHalfHeight then hh = cp.CapsuleHalfHeight end
      end)
    end
    if not ct then pcall(function() if c.K2_GetActorLocation then ct = c:K2_GetActorLocation() end end) end
    if not ct then return nil, nil end
    if not hh or hh < 10 or hh > 200 then hh = 85 end
    return {X=ct.X,Y=ct.Y,Z=ct.Z+hh}, {X=ct.X,Y=ct.Y,Z=ct.Z-hh}
  end

  local function Canvas()
    if V(E.Canvas) then return E.Canvas end
    if V(E._own_canvas) then return E._own_canvas end

    -- Method 1: InGameUITools root
    local root = nil
    pcall(function()
      local T = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
      if T and T.GetMainControlBaseUI then root = T.GetMainControlBaseUI() end
    end)
    if V(root) then
      local c = nil
      for _, nm in ipairs({"CanvasPanel_0","CanvasPanel_42","CanvasPanel","MainCanvas","CanvasPanel_1","RootCanvas","Canvas"}) do
        if not c then pcall(function() if V(root[nm]) then c = root[nm] end end) end
      end
      if V(c) then E.Canvas = c return c end
    end

    -- Method 2: create our own and add to viewport
    local pc = PC()
    local w = World()
    local owner = pc or w
    if owner then
      local cnv = nil
      pcall(function() cnv = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", owner) end)
      if V(cnv) then
        local added = false
        pcall(function()
          if slua_GameViewportClient and slua_GameViewportClient.AddViewportWidgetContent then
            slua_GameViewportClient:AddViewportWidgetContent(cnv, 100)
            added = true
          end
        end)
        if not added then
          pcall(function()
            if GSE and w and GSE.GetGameViewportClient then
              local vp = GSE.GetGameViewportClient(w)
              if V(vp) and vp.AddViewportWidgetContent then
                vp:AddViewportWidgetContent(cnv, 100)
                added = true
              end
            end
          end)
        end
        if added then E._own_canvas = cnv return cnv end
      end
    end
    return nil
  end

  local function UT(pc)
    local cv = Canvas()
    if not V(cv) then return false end
    local ok = false
    pcall(function()
      if SBL and SBL.AbsoluteToLocal then
        local geo = cv:GetCachedGeometry()
        if geo then
          local p0 = SBL.AbsoluteToLocal(geo, V2(0,0))
          local p1 = SBL.AbsoluteToLocal(geo, V2(100,100))
          if p0 and p1 and tonumber(p0.X) and tonumber(p1.X) and p1.X ~= p0.X and p1.Y ~= p0.Y then
            E.SX = (p1.X-p0.X)/100.0
            E.SY = (p1.Y-p0.Y)/100.0
            E.OX = p0.X
            E.OY = p0.Y
            ok = true
          end
        end
      end
    end)
    if not ok then
      local s = 1.0
      pcall(function()
        if WLL and WLL.GetViewportScale then
          local v = WLL.GetViewportScale(pc)
          if tonumber(v) and v > 0 then s = v end
        end
      end)
      E.SX = 1.0/s E.SY = 1.0/s E.OX = 0 E.OY = 0
    end
    return true
  end

  local function VP(pc)
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

  local function Prj(pc, wl)
    if not pc or not wl then return nil end
    local p = V2(0,0)
    local ok = false
    pcall(function()
      local r = pc:ProjectWorldLocationToScreen(wl, p, true)
      ok = (r == true or r == 1 or (p and (p.X ~= 0 or p.Y ~= 0)))
    end)
    if not ok then return nil end
    return V2(p.X*(E.SX or 1)+(E.OX or 0), p.Y*(E.SY or 1)+(E.OY or 0)), p
  end

  local function SFont(w, sz)
    if not V(w) then return end
    pcall(function()
      local f = w.Font
      if f then
        f.Size = sz
        if f.OutlineSettings then
          pcall(function() f.OutlineSettings.OutlineSize = 1 end)
          pcall(function() f.OutlineSettings.OutlineColor = CB end)
        end
        w:SetFont(f)
      end
      if w.SetShadowOffset then w:SetShadowOffset(V2(1,1)) end
      if w.SetShadowColorAndOpacity then w:SetShadowColorAndOpacity(CB) end
    end)
  end

  local function SColor(w, c)
    if not V(w) then return end
    pcall(function()
      if SLC then w:SetColorAndOpacity(SLC(c))
      else w:SetColorAndOpacity(c) end
    end)
  end

  local function NL(c, z)
    local cv = Canvas()
    if not V(cv) then return nil end
    local b = nil
    pcall(function() b = CGame:NewObjectFromPath("/Script/UMG.Border", cv) end)
    if not V(b) then return nil end
    pcall(function()
      b:SetBrushColor(c)
      b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      b:SetRenderTransformPivot(V2(0,0.5))
    end)
    local s = nil
    pcall(function() s = cv:AddChildToCanvas(b) end)
    if not s then pcall(function() b:RemoveFromParent() end) return nil end
    pcall(function() s:SetAutoSize(false) s:SetZOrder(z or 30) end)
    return { W=b, S=s }
  end

  local function LN(d, x1, y1, x2, y2, th)
    if not d or not V(d.W) or not d.S then return false end
    if x1~=x1 or y1~=y1 or x2~=x2 or y2~=y2 then return false end
    x1, y1, x2, y2 = RND(x1), RND(y1), RND(x2), RND(y2)
    local dz = CFG.DeadZone
    if d.x1 and d.th == th then
      if math.abs((d.x1 or 0)-x1)<dz and math.abs((d.y1 or 0)-y1)<dz
      and math.abs((d.x2 or 0)-x2)<dz and math.abs((d.y2 or 0)-y2)<dz then
        if d.hid ~= true then return true end
      end
    end
    local dx, dy = x2-x1, y2-y1
    local ln = math.sqrt(dx*dx+dy*dy)
    if ln < 1 then if V(d.W) then pcall(function() d.W:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end d.hid=true return false end
    local ang = ((math.atan2 and math.atan2(dy,dx)) or math.atan(dy,dx))*180.0/math.pi
    ang = math.floor(ang*10+0.5)/10
    ln = RND(ln)
    if d.x1==x1 and d.y1==y1 and d.x2==x2 and d.y2==y2 and d.th==th then
      if d.hid == true then
        pcall(function() d.W:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        d.hid = false
      end
      return true
    end
    local ok = pcall(function()
      d.S:SetPosition(V2(x1, y1-th*0.5))
      d.S:SetSize(V2(ln, th))
      d.W:SetRenderAngle(ang)
      d.W:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
    if ok then d.x1,d.y1,d.x2,d.y2,d.th = x1,y1,x2,y2,th d.hid = false end
    return true
  end

  local function HideD(d)
    if d and V(d.W) and d.hid ~= true then
      pcall(function() d.W:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
      d.hid = true
      d.x1,d.y1,d.x2,d.y2,d.th = nil,nil,nil,nil,nil
    end
  end

  local function SB(d, c, ck)
    if not d or not V(d.W) then return end
    if ck and d.ck == ck then return end
    pcall(function() d.W:SetBrushColor(c) end)
    if ck then d.ck = ck end
  end

  local function DS(d)
    if not d then return end
    local w = d.W or d.C
    if V(w) then
      pcall(function() w:RemoveFromParent() end)
      pcall(function() w:ConditionalBeginDestroy() end)
    end
  end

  local function CInf()
    local cv = Canvas()
    if not V(cv) then return nil end
    local c, tb, tn, td, ts = nil, nil, nil, nil, nil
    pcall(function() c = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", cv) end)
    if not V(c) then return nil end
    pcall(function() tb = CGame:NewObjectFromPath("/Script/UMG.Border", c) end)
    pcall(function() tn = CGame:NewObjectFromPath("/Script/UMG.TextBlock", c) end)
    pcall(function() td = CGame:NewObjectFromPath("/Script/UMG.TextBlock", c) end)
    pcall(function() ts = CGame:NewObjectFromPath("/Script/UMG.TextBlock", c) end)
    if not V(tb) or not V(tn) or not V(td) or not V(ts) then DS({W=c}) return nil end
    pcall(function()
      tb:SetBrushColor(TCLR[1]) tb:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      tn:SetText("") td:SetText("0m") ts:SetText("Open")
      tn:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      td:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      ts:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
      if tn.SetJustification then tn:SetJustification(1) end
      if td.SetJustification then td:SetJustification(1) end
      if ts.SetJustification then ts:SetJustification(1) end
    end)
    SColor(tn, CW) SColor(td, CW) SColor(ts, CG)
    SFont(tn, CFG.NameSize) SFont(td, CFG.DistSize) SFont(ts, CFG.StateSize)
    local bs, ns, s2, s3, ms = nil, nil, nil, nil, nil
    pcall(function() bs = c:AddChildToCanvas(tb) end)
    pcall(function() ns = c:AddChildToCanvas(tn) end)
    pcall(function() s2 = c:AddChildToCanvas(td) end)
    pcall(function() s3 = c:AddChildToCanvas(ts) end)
    pcall(function() ms = cv:AddChildToCanvas(c) end)
    if not bs or not ns or not s2 or not s3 or not ms then DS({W=c}) return nil end
    pcall(function()
      bs:SetAutoSize(false) bs:SetSize(V2(120,22)) bs:SetAlignment(V2(0.5,0.5)) bs:SetZOrder(34)
      ns:SetAutoSize(false) ns:SetSize(V2(120,22)) ns:SetAlignment(V2(0.5,0.5)) ns:SetZOrder(36)
      s2:SetAutoSize(true) s2:SetAlignment(V2(0.5,0.5)) s2:SetZOrder(36)
      s3:SetAutoSize(true) s3:SetAlignment(V2(0.5,0.5)) s3:SetZOrder(36)
      ms:SetAutoSize(false) ms:SetZOrder(35)
    end)
    return { C=c, TB=tb, N=tn, D=td, S=ts, S0=bs, S1=ns, S2=s2, S3=s3, Slot=ms }
  end

  local function UI(k, c, bot, tid, dm, vis, hx, hy)
    local d = E.Infos[k]
    if not d or not V(d.C) then DS(d) d = CInf() E.Infos[k] = d end
    if not d then return end
    local n = d.CN
    if not n then n = Name(c, bot) d.CN = n end
    if bot then n = "Bot" d.CN = "Bot" end
    local dl = string.format("%dm", math.max(0, math.floor((tonumber(dm) or 0)+0.5)))
    local st = vis and "Open" or "Close"
    local tc = TC(tid, bot, k)
    pcall(function()
      if d.LN ~= n then d.N:SetText(n) d.LN = n end
      if d.LD ~= dl then d.D:SetText(dl) d.LD = dl end
      if d.LS ~= st then d.S:SetText(st) d.LS = st end
      if d.LT ~= tostring(tid)..":"..tostring(bot) then d.TB:SetBrushColor(tc) d.LT = tostring(tid)..":"..tostring(bot) end
      if vis then SColor(d.S, CG) else SColor(d.S, CR) end
    end)
    local bw, bh = 100.0, 22.0
    local bx, by = RND(hx), RND(hy - 18.0)
    pcall(function()
      d.Slot:SetPosition(V2(bx, by))
      d.Slot:SetSize(V2(bw, 70.0))
      d.S0:SetPosition(V2(0,0)) d.S0:SetSize(V2(bw,bh))
      d.S1:SetPosition(V2(0,0)) d.S1:SetSize(V2(bw,bh))
      d.S2:SetPosition(V2(bw*0.5, bh+12)) d.S3:SetPosition(V2(bw*0.5, bh+30))
      d.C:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
  end

  local function HBg(k)
    local d = E.HBg[k]
    if d and V(d.W) then return d end
    d = NL(MK(0,0,0,CFG.BarBgAlpha), 31) E.HBg[k] = d return d
  end
  local function HFl(k)
    local d = E.HFill[k]
    if d and V(d.W) then return d end
    d = NL(CG, 32) E.HFill[k] = d return d
  end
  local function HBar(k, p, x, y, w)
    local bg = HBg(k) local fl = HFl(k)
    if not bg or not fl then return end
    w = math.max(1, tonumber(w) or 1)
    LN(bg, x, y, x+w, y, CFG.BarWidth)
    p = tonumber(p) or 1.0
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end
    local bk
    if p >= 0.7 then bk = "g"..math.floor(p*20+0.5)
    elseif p >= 0.4 then bk = "y"..math.floor(p*20+0.5)
    else bk = "r"..math.floor(p*20+0.5) end
    SB(fl, HC(p), bk)
    local fw = w * p
    if fw < 1 then HideD(fl) return end
    LN(fl, x, y, x+fw, y, CFG.BarWidth)
  end

  local function Snap(k)
    local d = E.Lines[k]
    if d and V(d.W) then return d end
    d = NL(CG, 30) E.Lines[k] = d return d
  end

  local function HT(k)
    HideD(E.HBg[k]) HideD(E.HFill[k]) HideD(E.Lines[k])
    local inf = E.Infos[k]
    if inf and V(inf.C) then pcall(function() inf.C:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end
  end

  local function RT(k)
    DS(E.HBg[k]) E.HBg[k] = nil
    DS(E.HFill[k]) E.HFill[k] = nil
    DS(E.Lines[k]) E.Lines[k] = nil
    DS(E.Infos[k]) E.Infos[k] = nil
    E.Vis[k] = nil
  end

  local function Reset()
    for _, d in pairs(E.Lines) do DS(d) end
    for _, d in pairs(E.HBg) do DS(d) end
    for _, d in pairs(E.HFill) do DS(d) end
    for _, d in pairs(E.Infos) do DS(d) end
    E.Lines={} E.HBg={} E.HFill={} E.Infos={} E.Vis={}
    E.Canvas=nil E.Cache={}
  end

  local function Scan(pc, me)
    if not pc or not me then E.Cache = {} return 0, 0 end
    local ml = Pos(me)
    if not ml then E.Cache = {} return 0, 0 end
    local mt = TID(me)
    local list = {}
    local nR, nB = 0, 0
    local all = All()
    local seen = {}
    for _, ch in pairs(all) do
      if V(ch) and ch ~= me and Alive(ch) then
        local k = Key(ch)
        if not seen[k] then
          local t = TID(ch)
          if not (mt ~= nil and t ~= nil and tostring(t) == tostring(mt)) then
            local l = Pos(ch)
            local dm = DM(ml, l)
            seen[k] = true
            local b = Bot(ch)
            if b then nB = nB+1 else nR = nR+1 end
            list[#list+1] = { C=ch, K=k, B=b, T=t, D=dm }
          end
        end
      end
    end
    table.sort(list, function(a,b) return (a.D or 99999) < (b.D or 99999) end)
    local tr = {}
    for i, it in ipairs(list) do if i > CFG.MaxTracked then break end tr[#tr+1] = it end
    E.Cache = tr
    return nR, nB
  end

  local function Update()
    local w = World()
    if w ~= E.LW then Reset() E.LW = w E.LS = -999.0 E.LT = -999.0 end
    local cv = Canvas()
    if not V(cv) then return end
    local n = Now()
    local pc = PC()
    if not pc then return end
    if (n - E.LS) >= CFG.ScanInterval then
      local me = Local()
      Scan(pc, me)
      E.LS = n
    end
    if (n - (E.LT or -999.0)) >= 1.0 then UT(pc) E.LT = n end
    local vw, vh = VP(pc)
    local h = CFG.SizeHyst
    if math.abs(vw - (E.VW or 0)) > h or math.abs(vh - (E.VH or 0)) > h then E.VW, E.VH = vw, vh
    else vw, vh = E.VW, E.VH end

    local ox = vw * 0.5 * (E.SX or 1) + (E.OX or 0)
    local oy = CFG.SnapOriginY
    local cam = Cam(pc)
    local act = {}
    for _, it in ipairs(E.Cache) do
      local c = it.C local k = it.K
      if V(c) and Alive(c) then
        local hd, ft = HF(c)
        if hd and ft then
          local hs, hp = Prj(pc, hd)
          local fs, fp = Prj(pc, ft)
          if hs and fs and hp and fp then
            local m = CFG.ScreenMargin
            local on = hp.X>-m and hp.X<vw+m and hp.Y>-m and hp.Y<vh+m
                       and fp.X>-m and fp.X<vw+m and fp.Y>-m and fp.Y<vh+m
            if on then
              local H = fs.Y - hs.Y
              if H >= 1 and H <= vh*1.5 then
                act[k] = true
                local W = H * CFG.BoxWidthFactor
                W = math.max(CFG.BoxMinWidth, math.min(CFG.BoxMaxWidth, W))
                local cx = (hs.X+fs.X)*0.5
                local L = cx - W*0.5
                local R = cx + W*0.5
                HBar(k, HP(c), L, hs.Y+8, R-L)
                LN(Snap(k), ox, oy, hs.X, hs.Y, CFG.SnapThickness)
                local vis = Vis(k, pc, cam, c)
                UI(k, c, it.B, it.T, it.D, vis, hs.X, hs.Y)
              else HT(k) end
            else HT(k) end
          else HT(k) end
        else HT(k) end
      end
    end
    local sk = {}
    for _, it in ipairs(E.Cache) do sk[it.K] = true end
    for k in pairs(E.Lines) do if not act[k] then HT(k) end end
    for k in pairs(E.HBg) do if not act[k] and not sk[k] then RT(k) end end
  end

  local function Tick() pcall(Update) end

  _EM.start = function(char)
    if not char or not slua.isValid(char) then return end
    if char._esp_on then return end

    local pc = nil
    pcall(function() if char.GetPlayerControllerSafety then pc = char:GetPlayerControllerSafety() end end)
    if not V(pc) then
      pcall(function() if slua_GameFrontendHUD and slua_GameFrontendHUD.GetPlayerController then pc = slua_GameFrontendHUD:GetPlayerController() end end)
    end

    if not V(pc) then
      -- retry in 0.5s
      pcall(function()
        if char and char.AddGameTimer then
          char:AddGameTimer(0.5, false, function() pcall(function() _EM.start(char) end) end)
        end
      end)
      return
    end

    char._esp_on = true
    E.PC = pc
    E.On = true

    local tick = function() if E.On then pcall(Tick) end end

    local hooked = false
    if type(pc.AddGameTimer) == "function" then
      hooked = pcall(function() pc:AddGameTimer(0.016, true, tick) end)
    end
    if not hooked and type(char.AddGameTimer) == "function" then
      hooked = pcall(function() char:AddGameTimer(0.016, true, tick) end)
    end

    if not hooked then
      char._esp_on = false
      pcall(function()
        if char and char.AddGameTimer then
          char:AddGameTimer(1.0, false, function() pcall(function() _EM.start(char) end) end)
        end
      end)
    end
  end
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
