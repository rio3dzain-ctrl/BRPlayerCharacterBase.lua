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
  
  -- ESP KO SIRF CLIENT PE CHALAYENGE
  if Client then
    self:StartESP()
  end
end

-- ==========================================
-- 120 FPS BOX ESP (INTEGRATED)
-- ==========================================
function BRPlayerCharacterBase:StartESP()
  local _ESPLocal = {}
  local FVector2D = import("Vector2D")
  local FLinearColor = import("LinearColor")
  local GameplayStaticsESP = nil
  pcall(function() GameplayStaticsESP = import("GameplayStatics") end)

  local function V(o) if o == nil then return false end local ok, v = pcall(function() return slua.isValid(o) end) return ok and v == true end
  local function V2(x, y) return FVector2D(x, y) end
  local function MKC(r, g, b, a) return FLinearColor(r, g, b, a) end

  local CFG = {
    MaxDistance = 30000, 
    MaxTracked = 15,     
    BoxWidthFactor = 0.62,
    BoxMinWidth = 22,
    BoxMaxWidth = 320,
    HeadExtra = 0.06,
    FootExtra = 0.02,
    ScanInterval = 0.2,  
    DrawInterval = 0.008 
  }

  local C_GREEN = MKC(0.12, 1.0, 0.25, 1.0)

  _ESPLocal.Canvas = nil
  _ESPLocal.Boxes = {}
  _ESPLocal.Cache = {}
  _ESPLocal.Active = false

  function _ESPLocal.GDP() if _ESPLocal._g then return _ESPLocal._g end local ok,g = pcall(require, "GameLua.GameCore.Data.GameplayData") if ok and g then _ESPLocal._g = g return g end end
  function _ESPLocal.PC() local pc pcall(function() local g=_ESPLocal.GDP() if g and g.GetPlayerController then pc=g.GetPlayerController() end end) if not V(pc) then pcall(function() if slua_GameFrontendHUD then pc=slua_GameFrontendHUD:GetPlayerController() end end) end return V(pc) and pc or nil end
  function _ESPLocal.LC() local c pcall(function() local g=_ESPLocal.GDP() if g then if g.GetPlayerCharacter then c=g.GetPlayerCharacter() end if not V(c) and g.GetLocalCharacter then c=g.GetLocalCharacter() end end end) if not V(c) then local pc=_ESPLocal.PC() pcall(function() if pc and pc.GetPawn then c=pc:GetPawn() end end) end return V(c) and c or nil end

  function _ESPLocal.GetAll()
    local all = {}
    local function m(chars) if not chars then return end for k,ch in pairs(chars) do if ch and slua.isValid(ch) then local pk=k pcall(function() if not pk and ch.GetPlayerKey then pk=ch:GetPlayerKey() end if not pk and ch.PlayerKey then pk=ch.PlayerKey end end) if pk then all[pk]=ch end end end end
    pcall(function() if Game and Game.GetAllPlayerPawns then m(Game:GetAllPlayerPawns()) end end)
    pcall(function() local g=_ESPLocal.GDP() if g and g.GetAllCharacters then m(g:GetAllCharacters()) end end)
    return all
  end

  function _ESPLocal.Alive(c)
    if not V(c) then return false end
    local a pcall(function() if c.IsAlive then a=c:IsAlive() end end)
    if type(a)=="boolean" then return a end
    local hp pcall(function() hp=c.Health end) if type(hp)~="number" then pcall(function() hp=c.HP end) end
    return type(hp)=="number" and hp>0 or true
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
    if id==nil then local ps pcall(function() if c.GetPlayerStateSafety then ps=c:GetPlayerStateSafety() end end) if V(ps) then pcall(function() if ps.GetTeamID then id=ps:GetTeamID() end end) end end
    return id
  end

  function _ESPLocal.Loc(c)
    local l pcall(function() if c.K2_GetActorLocation then l=c:K2_GetActorLocation() end end)
    return l
  end

  function _ESPLocal.Dist(a,b) if not a or not b then return 99999 end local dx,dy,dz=a.X-b.X,a.Y-b.Y,a.Z-b.Z return math.sqrt(dx*dx+dy*dy+dz*dz)/100.0 end

  function _ESPLocal.HeadFeet(c)
    local ct,hh pcall(function()
      local cap if c.GetCapsuleComponent then cap=c:GetCapsuleComponent() end
      if cap and V(cap) then if cap.K2_GetComponentLocation then ct=cap:K2_GetComponentLocation() end if cap.GetScaledCapsuleHalfHeight then hh=cap:GetScaledCapsuleHalfHeight() end end
    end)
    if not ct then pcall(function() if c.K2_GetActorLocation then ct=c:K2_GetActorLocation() end end) end
    if not ct then return nil,nil end
    if not hh or hh<10 or hh>200 then hh=85 pcall(function() if c.bIsCrouched then hh=60 end if c.IsProne and c:IsProne() then hh=25 end end) end
    return {X=ct.X,Y=ct.Y,Z=ct.Z+hh}, {X=ct.X,Y=ct.Y,Z=ct.Z-hh}
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
    return V2(pix.X, pix.Y), pix
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
    x1,y1,x2,y2=math.floor(x1+0.5),math.floor(y1+0.5),math.floor(x2+0.5),math.floor(y2+0.5)
    if d.x1==x1 and d.y1==y1 and d.x2==x2 and d.y2==y2 and d.th==th and d.h~=true then return true end
    local dx,dy=x2-x1,y2-y1 local l=math.sqrt(dx*dx+dy*dy)
    if l<1 then _ESPLocal.Hide(d) return false end
    local a=((math.atan2 and math.atan2(dy,dx)) or math.atan(dy,dx))*180/math.pi
    local ok pcall(function() d.S:SetPosition(V2(x1,y1-th*0.5)) d.S:SetSize(V2(l,th)) d.W:SetRenderAngle(a) d.W:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    if ok then d.x1,d.y1,d.x2,d.y2,d.th,d.h=x1,y1,x2,y2,th,false end
    return true
  end

  function _ESPLocal.Hide(d) if d and V(d.W) and d.h~=true then pcall(function() d.W:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) d.h=true end end

  function _ESPLocal.Scan()
    local pc=_ESPLocal.PC() local me=_ESPLocal.LC() if not pc or not me then _ESPLocal.Cache={} return end
    local ml=_ESPLocal.Loc(me) if not ml then _ESPLocal.Cache={} return end
    local mt=_ESPLocal.Team(me) local list={} local all=_ESPLocal.GetAll() local seen={}
    local function add(c)
      if not V(c) or c==me or not _ESPLocal.Alive(c) then return end
      local k=_ESPLocal.Key(c) if seen[k] then return end
      local t=_ESPLocal.Team(c) if mt~=nil and t~=nil and tostring(t)==tostring(mt) then return end
      local l=_ESPLocal.Loc(c) local dm=_ESPLocal.Dist(ml,l) 
      if dm <= CFG.MaxDistance then
        seen[k]=true
        list[#list+1]={C=c, K=k, D=dm}
      end
    end
    if all then for _,c in pairs(all) do add(c) end end
    table.sort(list, function(a,b) return (a.D or 99999)<(b.D or 99999) end)
    local tr={} for i,it in ipairs(list) do if i>CFG.MaxTracked then break end tr[#tr+1]=it end
    _ESPLocal.Cache=tr
  end

  function _ESPLocal.UpdateDraw()
    local cv=_ESPLocal.CanvasGet() if not cv then return end
    local pc=_ESPLocal.PC() if not pc then return end
    
    local vw,vh=1920,1080 pcall(function() local v=V2(0,0) pc:GetViewportSize(v) if v.X>200 then vw,vh=v.X,v.Y end end)
    
    local active = {}
    for _,it in ipairs(_ESPLocal.Cache) do
      local c=it.C if V(c) and _ESPLocal.Alive(c) then
        local hd,ft=_ESPLocal.HeadFeet(c) if hd and ft then
          local hs,hp=_ESPLocal.Proj(pc,hd) local fs,fp=_ESPLocal.Proj(pc,ft)
          if hs and fs and hp and fp then
            local on=hp.X>-500 and hp.X<vw+500 and hp.Y>-500 and hp.Y<vh+500 and fp.X>-500 and fp.X<vw+500 and fp.Y>-500 and fp.Y<vh+500
            if on then
              local H=fs.Y-hs.Y if H>=1 and H<=vh*1.5 then
                active[it.K]=true
                local W=H*CFG.BoxWidthFactor W=math.max(CFG.BoxMinWidth,math.min(CFG.BoxMaxWidth,W))
                local cx=(hs.X+fs.X)*0.5 local L=cx-W*0.5 local R=cx+W*0.5
                local T=hs.Y-(H*CFG.HeadExtra) local B=fs.Y+(H*CFG.FootExtra)
                
                local bx = _ESPLocal.Boxes[it.K]
                if not bx then
                  bx = { 
                    Top = _ESPLocal.Line(C_GREEN, 30), 
                    Bot = _ESPLocal.Line(C_GREEN, 30), 
                    Lft = _ESPLocal.Line(C_GREEN, 30), 
                    Rgt = _ESPLocal.Line(C_GREEN, 30) 
                  }
                  _ESPLocal.Boxes[it.K] = bx
                end
                
                _ESPLocal.Draw(bx.Top, L, T, R, T, 1.5)
                _ESPLocal.Draw(bx.Bot, L, B, R, B, 1.5)
                _ESPLocal.Draw(bx.Lft, L, T, L, B, 1.5)
                _ESPLocal.Draw(bx.Rgt, R, T, R, B, 1.5)
              end
            end
          end
        end
      end
    end
    
    for k, bx in pairs(_ESPLocal.Boxes) do
      if not active[k] then
        _ESPLocal.Hide(bx.Top) _ESPLocal.Hide(bx.Bot) _ESPLocal.Hide(bx.Lft) _ESPLocal.Hide(bx.Rgt)
      end
    end
  end

  _ESPLocal.Active = true
  local tk = require("timer")

  -- SMART WAIT LOOP (Har 1 second baad check karega ki Canvas aaya ya nahi)
  local function SafeStart()
    local pc = _ESPLocal.PC()
    local cv = _ESPLocal.CanvasGet()
    if V(pc) and V(cv) then
      -- Jab UI ready ho jaye, tab timers shuru karo
      tk.SetGameTimer(CFG.ScanInterval, true, function() if _ESPLocal.Active then pcall(_ESPLocal.Scan) end end)
      tk.SetGameTimer(CFG.DrawInterval, true, function() if _ESPLocal.Active then pcall(_ESPLocal.UpdateDraw) end end)
      print("[ESP] 120 FPS Box ESP Loaded Successfully!")
    else
      -- Agar UI nahi aayi, toh 1 sec baad wapas try karo
      tk.SetGameTimer(1.0, false, SafeStart)
    end
  end

  SafeStart()
end

-- ==========================================
-- BAQI GAME FUNCTIONS (Same as original)
-- ==========================================
function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then self.STCharacterMovement.bPositiveBlowUp = true end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", { AttrName = { "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1] = "FinishedState" }, self.HandleFinishedState, self)
  end
end

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
    local GT, GID = CGameMode.GameModeType, tonumber(CGameState.GameModeID)
    local a = GT == EGameModeType.ETypicalGameMode or GT == EGameModeType.EFourInOneGameMode or GT == EGameModeType.EHeavyWeaponGameMode
    local b = not MatchModeIds[GID]
    return a and b
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
  end
  return false
end

function BRPlayerCharacterBase:BPOnRecycled() if Client then self:ResetMeshRelativeLocationAndRotation() end end
function BRPlayerCharacterBase:BPOnRespawned() if Client then self:ResetMeshRelativeLocationAndRotation() end end
function BRPlayerCharacterBase:ReceiveOnRecycle() if Client then self:ResetMeshRelativeLocationAndRotation() GameplayData.RemoveCharacter(self.Object) end end
function BRPlayerCharacterBase:ReceiveOnSpawn() if Client then self:ResetMeshRelativeLocationAndRotation() GameplayData.AddCharacter(self.Object) end end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local rot, loc = FRotator(0, -90, 0), FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then self.Mesh:K2_SetRelativeRotation(rot, false, nil, false) end
    self:CacheInitialMeshOffset(loc, rot)
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
  local pc = self:GetPlayerControllerSafety()
  if not slua.isValid(pc) then return end
  local av = self.CharacterAvatarComp2_BP
  if not slua.isValid(av) then return end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local vid = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(pc, av)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if vid then
    local AU = import("AvatarUtils")
    if AU.GetVehicleShapeBySkinID(vid) == ESTExtraVehicleShapeType.VST_Horse then
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
        pc:ReInitParachuteItem() pc:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then return end
  local mc = self:GetMedievalCraneFromBase(uNewMovementBase)
  if mc and mc.AddCharacter then mc:AddCharacter(self.Object)
  else
    mc = self:GetMedievalCraneFromBase(uOldMovementBase)
    if mc and mc.RemoveCharacter then mc:RemoveCharacter(self.Object) end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then return end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) or not Lifter.AddCharacter then return end
  return Lifter
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

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then self:MulticastRPC_GmPlayAction(actionId) end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then return end
  local em = self:GetPlayEmoteComponent()
  if not slua.isValid(em) then return end
  local cfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not cfg then return end
  local handle = slua.loadObject(cfg.Path)()
  local arr = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  em:OnLoadEmoteAssetBegin(handle, actionId, arr, "")
  local tb = FuncUtil.LuaArrayToTable(arr)
  require("common.asset_util").GetAssetsArrayAsyncParallel(tb, function()
    em:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(flag)
  if slua.isValid(self.ParachuteComponent) then self.ParachuteComponent.bServerSyncShouldCheckPassWall = flag end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState() end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(interrupt)
  self.Super:OnPlayerLeaveCarryBoxState(interrupt)
  if self.CarryDeadBoxFeature then self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(interrupt) end
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
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then self.ParachuteFormation:OnLandingClearFormationCamera() end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local w = self:GetWeaponBySlot(Slot)
    if slua.isValid(w) then
      local wid = w:GetWeaponID()
      local cfg = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if cfg and cfg.CheckIsWeaponInBlackList and cfg.CheckIsWeaponInBlackList(wid) then
        local pc = self:GetPlayerControllerSafety()
        if Client and slua.isValid(pc) and pc.Role == ENetRole.ROLE_AutonomousProxy then pc:DisplayGameTipWithMsgID(47306) end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local sw = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(sw) then
      local st = sw:GetCurMoveState()
      if st == ESpiderSwingMoveState.Launching or st == ESpiderSwingMoveState.Swinging then return false end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
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
