-- ═══════════════════════════════════════════════════════════════════════════
-- BRPlayerCharacterBase.lua — SINGLE FILE (hardened + inline ESP)
-- ═══════════════════════════════════════════════════════════════════════════

local BRPlayerCharacterBase = {
  ServerRPC = {}, ClientRPC = {}, MulticastRPC = {}, LuaEventContainer = {}
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

-- ─── Global character registry (populated on client, read by ESP) ──────────
_G.BR_CHARACTER_REGISTRY = _G.BR_CHARACTER_REGISTRY or {}

-- ─── ESP config (tweak here) ────────────────────────────────────────────────
local ESP_CFG = {
  MaxDistance    = 100000,     -- 1000 m (UE units)
  MinDistance    = 100,        -- 1 m
  UpdateInterval = 0.10,       -- 10 Hz
  DrawName       = true,
  DrawDistance   = true,
  DrawHealth     = true,
  DrawLine       = false,
  LineDuration   = 0.12,
  TextDuration   = 0.12,
  HeadOffsetZ    = 100,
}

-- Build FLinearColor once (crash-safe: ESP simply disabled if UE rejects it)
local ESP_TextColor = nil
pcall(function() ESP_TextColor = FLinearColor(1.0, 0.3, 0.3, 1.0) end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Lifecycle
-- ═══════════════════════════════════════════════════════════════════════════
function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  if self.__super and self.__super._PostConstruct then
    self.__super._PostConstruct(self)
  end
  pcall(function() self:InitAddSpecialMoveInfo() end)
  self.bCanNearDeathGiveup = true
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  if self.__super and self.__super.ReceiveBeginPlay then
    self.__super.ReceiveBeginPlay(self)
  end

  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)

  pcall(function()
    if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
      local C = import("CheckFallingDistanceComponent")
      if slua.isValid(C) and not slua.isValid(self:GetComponentByClass(C)) then
        Game:AddComponent(C, self, "CheckFallingDistanceComponent")
      end
    end
  end)

  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end

  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled",  self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate",
      { AttrName = { "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
  end

  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay PlayerKey:%u", self.PlayerKey)
    pcall(function() GameplayData.AddCharacter(self.Object) end)

    -- Register in global table for ESP lookup
    _G.BR_CHARACTER_REGISTRY[self.Object] = self
    print(bWriteLog and string.format("[ESP] registered Object=%s registrySize=%d",
      tostring(self.Object), self:_ESPRegistrySize()))

    -- Start ESP only for the local player
    if self:IsLocallyControlled() then
      pcall(function() self:StartEnemyESP() end)
    end
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE,
      { [1] = "FinishedState" }, self.HandleFinishedState, self)
    self:AddControlEvent(self, "OnPawnRespawnDelegate", self.OnRespawnRehideCheck, self)
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  if self.__super and self.__super.ReceiveEndPlay then
    self.__super.ReceiveEndPlay(self, EndPlayReason)
  end
  if Client then
    _G.BR_CHARACTER_REGISTRY[self.Object] = nil
    pcall(function() self:StopEnemyESP() end)
    pcall(function() GameplayData.RemoveCharacter(self.Object) end)
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  if Client then
    _G.BR_CHARACTER_REGISTRY[self.Object] = nil
    pcall(function()
      self:ResetMeshRelativeLocationAndRotation()
      GameplayData.RemoveCharacter(self.Object)
    end)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  if Client then
    _G.BR_CHARACTER_REGISTRY[self.Object] = self
    pcall(function()
      self:ResetMeshRelativeLocationAndRotation()
      GameplayData.AddCharacter(self.Object)
    end)
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ESP — inline methods on the character class (no feature, no extra file)
-- ═══════════════════════════════════════════════════════════════════════════
function BRPlayerCharacterBase:_ESPRegistrySize()
  local n = 0
  for _ in pairs(_G.BR_CHARACTER_REGISTRY) do n = n + 1 end
  return n
end

function BRPlayerCharacterBase:StartEnemyESP()
  if self._espEnabled then return end
  if not Client then return end
  if not slua.isValid(self.Object) then return end
  if not ESP_TextColor then
    print(bWriteLog and "[ESP] FLinearColor unavailable — ESP disabled")
    return
  end

  self._espEnabled = true
  self._espEnemies = {}
  self._espPrintAccum = 0
  print(bWriteLog and "[ESP] StartEnemyESP")
  self:_ESPScheduleTick()
end

function BRPlayerCharacterBase:StopEnemyESP()
  if not self._espEnabled then return end
  self._espEnabled = false
  self._espEnemies = {}
  print(bWriteLog and "[ESP] StopEnemyESP")
end

function BRPlayerCharacterBase:_ESPScheduleTick()
  if not self._espEnabled then return end
  self:AddGameTimer(ESP_CFG.UpdateInterval, false, function()
    if not self._espEnabled then return end
    if not slua.isValid(self.Object) then
      self._espEnabled = false
      return
    end

    local ok, err = pcall(function() self:_ESPTick() end)
    if not ok then
      print(bWriteLog and "[ESP] tick error: " .. tostring(err))
    end

    if self._espEnabled then
      self:_ESPScheduleTick()
    end
  end)
end

function BRPlayerCharacterBase:_ESPTick()
  local myLoc = self:K2_GetActorLocation()
  if not myLoc then return end

  local reg = _G.BR_CHARACTER_REGISTRY
  if not reg then return end

  local myTeamID = self:_ESPGetMyTeamID()
  local enemies  = {}

  for obj, char in pairs(reg) do
    if char == self then
      -- skip self
    elseif not slua.isValid(char) then
      reg[obj] = nil
    else
      local ok, isEnemy = pcall(function()
        return self:_ESPIsEnemy(char, myTeamID)
      end)
      if ok and isEnemy then
        local loc = char:K2_GetActorLocation()
        if loc then
          local d = (loc - myLoc):Size()
          if d >= ESP_CFG.MinDistance and d <= ESP_CFG.MaxDistance then
            enemies[#enemies + 1] = { char = char, loc = loc, dist = d }
          end
        end
      end
    end
  end

  self._espEnemies = enemies

  -- periodic debug print (~every 2 s)
  self._espPrintAccum = (self._espPrintAccum or 0) + ESP_CFG.UpdateInterval
  if self._espPrintAccum >= 2.0 then
    self._espPrintAccum = 0
    print(bWriteLog and string.format("[ESP] enemies=%d registry=%d",
      #enemies, self:_ESPRegistrySize()))
  end

  for i = 1, #enemies do
    pcall(function() self:_ESPRenderOne(enemies[i]) end)
  end
end

function BRPlayerCharacterBase:_ESPGetMyTeamID()
  local ok, t = pcall(function()
    local ps = self:GetPlayerStateSafety()
    if slua.isValid(ps) then return ps:GetTeamID() end
  end)
  return ok and t or nil
end

function BRPlayerCharacterBase:_ESPIsEnemy(other, myTeamID)
  if not slua.isValid(other) then return false end
  if other == self then return false end

  local hp = other:GetAttrValue("Health")
  if hp and hp <= 0 then return false end

  local ok, pc = pcall(function() return other:IsPlayerControlled() end)
  if not ok or not pc then return false end

  if myTeamID then
    local psOk, ps = pcall(function() return other:GetPlayerStateSafety() end)
    if psOk and slua.isValid(ps) then
      local tOk, team = pcall(function() return ps:GetTeamID() end)
      if tOk and team == myTeamID then return false end
    end
  end
  return true
end

function BRPlayerCharacterBase:_ESPRenderOne(enemy)
  local head  = enemy.loc + FVector(0, 0, ESP_CFG.HeadOffsetZ)
  local label = self:_ESPBuildLabel(enemy)
  if label == "" then return end

  -- KismetSystemLibrary.DrawDebugString signature:
  --   (worldCtx, location, text, testActor, FLinearColor, duration)
  local ok, err = pcall(function()
    UKismetSystemLibrary.DrawDebugString(
      self, head, label, nil, ESP_TextColor, ESP_CFG.TextDuration)
  end)
  if not ok and not self._espDrawWarned then
    self._espDrawWarned = true
    print(bWriteLog and "[ESP] DrawDebugString failed: " .. tostring(err))
  end

  if ESP_CFG.DrawLine then
    pcall(function()
      UKismetSystemLibrary.DrawDebugLine(
        self, enemy.loc, head, 255, 40, 40, ESP_CFG.LineDuration)
    end)
  end
end

function BRPlayerCharacterBase:_ESPBuildLabel(enemy)
  local parts = {}

  if ESP_CFG.DrawName then
    local name = "Enemy"
    local psOk, ps = pcall(function() return enemy.char:GetPlayerStateSafety() end)
    if psOk and slua.isValid(ps) then
      local nOk, n = pcall(function() return ps:GetPlayerNameSafety() end)
      if nOk and type(n) == "string" and n ~= "" then name = n end
    end
    parts[#parts + 1] = name
  end

  if ESP_CFG.DrawDistance then
    parts[#parts + 1] = string.format("[%dm]", math.floor(enemy.dist / 100))
  end

  if ESP_CFG.DrawHealth then
    local hp    = enemy.char:GetAttrValue("Health") or 0
    local maxHp = enemy.char:GetAttrValue("MaxHealth") or 100
    if maxHp and maxHp > 0 then
      local pct = math.floor(math.max(0, math.min(100, hp / maxHp * 100)))
      parts[#parts + 1] = string.format("HP:%d%%", pct)
    end
  end

  return table.concat(parts, " ")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Rest of the character class (unchanged behavior, crash-safe)
-- ═══════════════════════════════════════════════════════════════════════════
function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  if self.__super and self.__super.CharacterAttrChangeEvent then
    self.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  end
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    pcall(function()
      local pc = self:GetPlayerControllerSafety()
      if slua.isValid(pc) then pc:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "") end
    end)
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  if PawnState == EPawnState.SwitchPP then
    pcall(function()
      local pc = self:GetPlayerControllerSafety()
      if slua.isValid(pc) then pc:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "") end
    end)
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    pcall(function()
      local M = import("EDynamicSimpleQueryConfigDisableMask")
      if M then self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(M.Bit0, true) end
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
    end
  end)
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local t  = CGameMode.GameModeType
    local id = tonumber(CGameState.GameModeID)
    local ok1 = t == EGameModeType.ETypicalGameMode
             or t == EGameModeType.EFourInOneGameMode
             or t == EGameModeType.EHeavyWeaponGameMode
    return ok1 and (not MatchModeIds[id])
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(a, b)
  if self.__super and self.__super.LuaHandleParachuteStateChanged then
    self.__super.LuaHandleParachuteStateChanged(self, a, b)
  end
  if Client then return end
  pcall(function()
    local pc = self:GetPlayerControllerSafety()
    if not (slua.isValid(pc) and pc.CheckParachuteOpenFeature) then return end
    local f = pc.CheckParachuteOpenFeature
    if b == EParachuteState.PS_Opening then
      if f.SatrtCheckShowParachuteCloseUI then f:SatrtCheckShowParachuteCloseUI() end
    elseif b == EParachuteState.PS_None then
      if f.RecoverParachuteOpenParam then f:RecoverParachuteOpenParam() end
      if f.ClearTimerAndState then f:ClearTimerAndState() end
    end
  end)
end

function BRPlayerCharacterBase:OnLanded()
  if self.HandleOnLanded then pcall(function() self:HandleOnLanded(-1) end) end
  if Client then return end
  pcall(function()
    local pc = self:GetPlayerControllerSafety()
    if not (slua.isValid(pc) and pc.CheckParachuteOpenFeature) then return end
    local f = pc.CheckParachuteOpenFeature
    if f.ClearTimerAndState then f:ClearTimerAndState() end
    if f.ResetCheckShowUI then f:ResetCheckShowUI() end
  end)
end

function BRPlayerCharacterBase:IsWarGameMode()
  local ok, r = pcall(function()
    local gs = GameplayData:GetGameState()
    if slua.isValid(gs) and Game:IsClassOf(gs, STExtraGameStateBase) then
      return gs.GameModeType == EGameModeType.EWarGameMode
    end
    return false
  end)
  return ok and r or false
end

function BRPlayerCharacterBase:BPOnRecycled()
  if Client then pcall(function() self:ResetMeshRelativeLocationAndRotation() end) end
end
function BRPlayerCharacterBase:BPOnRespawned()
  if Client then pcall(function() self:ResetMeshRelativeLocationAndRotation() end) end
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
  end)
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  pcall(function()
    if Game:IsValid(self.STCharacterMovement)
       and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming
       and self:CheckBaseIsMoveable() then
      self.CharacterMovement:SetBase(nil, "", true)
    end
    if self.Role == ENetRole.ROLE_AutonomousProxy
       and Game:IsValid(self.STCharacterMovement)
       and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking
       and UIManager.UI_Config_InGame.ParachuteOpenUI then
      UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
    end
  end)
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord() end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  pcall(function()
    if not UKismetSystemLibrary.IsDedicatedServer(self) then return end
    local pc = self:GetPlayerControllerSafety()
    if not slua.isValid(pc) then return end
    local av = self.CharacterAvatarComp2_BP
    if not slua.isValid(av) then return end
    local Util = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
    local id = Util:ChangeVehicleSkinByClothes(pc, av)
    if not id then return end
    local ShapeType = import("ESTExtraVehicleShapeType")
    local AvatarUtils = import("AvatarUtils")
    if not (ShapeType and AvatarUtils) then return end
    if AvatarUtils.GetVehicleShapeBySkinID(id) == ShapeType.VST_Horse then
      local ps = self:GetPlayerStateSafety()
      if slua.isValid(ps) then ps:AddGeneralCount(468, 1, false) end
    end
  end)
end

function BRPlayerCharacterBase:ParachuteJump()
  pcall(function()
    local pc = self:GetControllerSafety()
    if not slua.isValid(pc) then return end
    if not self:GetEnsure() then
      if pc:GetCurrentStateType() ~= EStateType.State_ParachuteJump
         and pc:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        pc:ReInitParachuteItem()
        pc:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
    end
  end)
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uChar, uNew, uOld)
  if uChar ~= self.Object then return end
  pcall(function()
    local c = self:GetMedievalCraneFromBase(uNew)
    if c and c.AddCharacter then
      c:AddCharacter(self.Object)
    else
      c = self:GetMedievalCraneFromBase(uOld)
      if c and c.RemoveCharacter then c:RemoveCharacter(self.Object) end
    end
  end)
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then return end
  local o = Base:GetOwner()
  if not slua.isValid(o) or not o.AddCharacter then return end
  return o
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local ok, r = pcall(function()
    local ps = self:GetPlayerStateSafety()
    if not slua.isValid(ps) then return false end
    if ps.CanUseFlaregun == false and self:IsLocallyControlled() then
      local pc = self:GetPlayerControllerSafety()
      if slua.isValid(pc) then pc:DisplayGameTipWithMsgID(48532) end
    end
    return not ps.CanUseFlaregun
  end)
  return ok and r or false
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  pcall(function() self:HandleNearDeathGiveupRescue() end)
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  pcall(function()
    local c = self.NearDeatchComponent
    if self:IsNearDeath() and slua.isValid(c) and self.bCanNearDeathGiveup == true then
      local ps = self:GetPlayerStateSafety()
      if slua.isValid(ps) then ps:AddGeneralCount(1613, 1, false) end
      c:TriggerGotoDieExplictly(self.Object)
    end
  end)
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  if type(actionId) ~= "number" then return end
  pcall(function()
    if USTExtraBlueprintFunctionLibrary
       and USTExtraBlueprintFunctionLibrary.IsDevelopment
       and USTExtraBlueprintFunctionLibrary.IsDevelopment() then
      self:MulticastRPC_GmPlayAction(actionId)
    end
  end)
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client or type(actionId) ~= "number" then return end
  pcall(function()
    local emoteComp = self:GetPlayEmoteComponent()
    if not slua.isValid(emoteComp) then return end
    local LF = require("common.log_filter"); LF.SetLogTreeEnable(true)
    local cfg = CDataTable.GetTableData("EmoteBPTable", actionId)
    if not cfg or not cfg.Path then return end
    local Asset = slua.loadObject(cfg.Path); if not Asset then return end
    local arr = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
    local h = Asset(); if not h then return end
    emoteComp:OnLoadEmoteAssetBegin(h, actionId, arr, "")
    local tb = FuncUtil.LuaArrayToTable(arr)
    require("common.asset_util").GetAssetsArrayAsyncParallel(tb, function()
      pcall(function() emoteComp:OnLoadEmoteAssetEnd(h, actionId, 0) end)
    end)
  end)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(b)
  pcall(function()
    if slua.isValid(self.ParachuteComponent) then
      self.ParachuteComponent.bServerSyncShouldCheckPassWall = b and true or false
    end
  end)
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  if self.Super and self.Super.OnPlayerEnterCarryBoxState then self.Super:OnPlayerEnterCarryBoxState() end
  pcall(function()
    if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
  end)
end
function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(b)
  if self.Super and self.Super.OnPlayerLeaveCarryBoxState then self.Super:OnPlayerLeaveCarryBoxState(b) end
  pcall(function()
    if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(b) end
  end)
end
function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(u)
  if not slua.isValid(u) then return end
  local T = import("/Script/ShadowTrackerExtra.PlayerTombBox")
  if not T or not Game:IsClassOf(u, T) then return end
  if not self.CarryDeadBoxFeature then return end
  pcall(function() self.CarryDeadBoxFeature:CarryDeadBox(u) end)
end

function BRPlayerCharacterBase:SetAreaID(id)
  if type(id) ~= "number" then return end
  self:SetAttrValue("AreaID", id, -1)
end
function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end
function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  return self.bCannotChangeIntoPetSpectator
end
function BRPlayerCharacterBase:DoModChangeToBT()
  pcall(function()
    if self:HasState(EPawnState.SpecialSuit) then
      self:TriggerEntrySkillWithID(4301101, true)
    end
  end)
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  if self.Super and self.Super.SwitchCameraToParachuteOpening then self.Super:SwitchCameraToParachuteOpening() end
  pcall(function()
    if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera
       and self.ParachuteFormation:ShouldApplyFormationCamera() then
      self.ParachuteFormation:OverlayFormationCameraParams()
    end
  end)
end
function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  if self.Super and self.Super.SwitchCameraToParachuteFalling then self.Super:SwitchCameraToParachuteFalling() end
  pcall(function()
    if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera
       and self.ParachuteFormation:ShouldApplyFormationCamera() then
      self.ParachuteFormation:OverlayFormationCameraParams()
    end
  end)
end
function BRPlayerCharacterBase:SwitchCameraToNormal()
  if self.Super and self.Super.SwitchCameraToNormal then self.Super:SwitchCameraToNormal() end
  pcall(function()
    if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
      self.ParachuteFormation:OnLandingClearFormationCamera()
    end
  end)
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local blocked = pcall(function()
      local W = self:GetWeaponBySlot(Slot)
      if not slua.isValid(W) then return false end
      local cfg = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if cfg and cfg.CheckIsWeaponInBlackList and cfg.CheckIsWeaponInBlackList(W:GetWeaponID()) then
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
  if self:HasState(EPawnState.WebSwing)
     and Slot ~= ESurviveWeaponPropSlot.SWPS_None
     and slua.isValid(self.STCharacterMovement) then
    local blocked = pcall(function()
      local o = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(
        ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
      if not slua.isValid(o) then return false end
      local s = o:GetCurMoveState()
      return s == ESpiderSwingMoveState.Launching or s == ESpiderSwingMoveState.Swinging
    end)
    if blocked == true then return false end
  end
  if self.Super and self.Super.SwitchWeaponCheck then
    return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
  end
  return false
end

-- ─── Emote resolve ──────────────────────────────────────────────────────────
local VICTORY_DANCE_FX_MAP = { [12219601] = 22010089 }
local PublishRegionMacros  = require("client.slua.config.ClientMacros.PublishRegionMacros")
local isFitVersion         = PublishRegionMacros.IsFITVersion()

local function ResolveEmoteResID(ItemID)
  if type(ItemID) ~= "number" then return ItemID end
  local FxID = VICTORY_DANCE_FX_MAP[ItemID]
  if not FxID or FxID == ItemID then return ItemID end
  local ok, r = pcall(function()
    local mu = require("client.common.model_util")
    local FxBPID = mu.GetBPID(FxID)
    local ResID  = ItemID
    if FxBPID and 0 < FxBPID and mu.IsBattleItemHandleExist("Emote", FxBPID, false, false) then
      ResID = FxID
    end
    if isFitVersion and ResID == 12219601 then return 12222069 end
    return ResID
  end)
  return ok and r or ItemID
end

function BRPlayerCharacterBase:GetEmoteHandlePath(ItemID)
  local R = ResolveEmoteResID(ItemID)
  if self.Super and self.Super.GetEmoteHandlePath then return self.Super:GetEmoteHandlePath(R) end
  local ok, p = pcall(function()
    local mu = require("client.common.model_util")
    local BPID = mu.GetBPID(R)
    if not BPID or BPID <= 0 then return "" end
    return mu.GetPath("Emote", BPID, false, false) or ""
  end)
  return ok and p or ""
end

function BRPlayerCharacterBase:GetEmoteHandle(ItemID)
  local R = ResolveEmoteResID(ItemID)
  if self.Super and self.Super.GetEmoteHandle then return self.Super:GetEmoteHandle(R) end
  local ok, h = pcall(function()
    local mu = require("client.common.model_util")
    local BPID = mu.GetBPID(R)
    if not BPID or BPID <= 0 then return nil end
    local H = mu.GetClass("Emote", BPID, false, false)
    if not H then return nil end
    local hh = H()
    return slua.isValid(hh) and hh or nil
  end)
  return ok and h or nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Registration — no ESP feature entry (ESP lives as methods on this class)
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
}, "BRPlayerCharacterBase")
