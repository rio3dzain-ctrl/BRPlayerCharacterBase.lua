-- BRPlayerCharacterBase_ESP.lua
-- Drop into: GameLua.Mod.BaseMod.GamePlay.Character.BRPlayerCharacterBase
-- Compact enemy ESP (marker + distance) for BRPlayerCharacterBase

local BRPlayerCharacterBase = {}

local import = import
local slua = slua
local Game = Game
local UIManager = UIManager

local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local EGameModeType = import("EGameModeType")
local STExtraGameStateBase = import("STExtraGameStateBase")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")

-- ─── ESP CONFIG ───────────────────────────────────────────────
local ESP = {
  Enabled       = true,
  MaxDistance   = 40000,     -- cm (400m)
  BoxColor      = { 255, 40, 40, 255 },
  TextColor     = { 255, 255, 255, 255 },
  BoxThickness  = 1.5,
  FontSize      = 14,
  UpdateRate    = 0.05,      -- 20 Hz
  HeadOffset    = 90,        -- cm above actor origin for head pos
  Tracked       = {},        -- [pawn] = { pawn, cached_name }
  LocalPawn     = nil,
  Acc           = 0,
  Inited        = false,
}

-- ─── HELPERS ──────────────────────────────────────────────────
local function is_alive(pawn)
  if not slua.isValid(pawn) then return false end
  if pawn:HasState(EPawnState.Dead) or pawn:HasState(EPawnState.NearDeath) then return false end
  return true
end

local function get_team(pawn)
  local ps = pawn:GetPlayerStateSafety()
  if not slua.isValid(ps) then return -1 end
  return ps.TeamID or ps:GetTeamID() or -1
end

local function get_local_team()
  local pc = GameplayData:GetLocalPlayerController()
  if not slua.isValid(pc) then return -1 end
  local ps = pc.PlayerState
  if not slua.isValid(ps) then return -1 end
  return ps.TeamID or ps:GetTeamID() or -1
end

local function is_enemy(pawn, local_team)
  local t = get_team(pawn)
  if t < 0 or local_team < 0 then return true end -- FFA / no team
  return t ~= local_team
end

local function get_name(pawn)
  if pawn.__esp_name then return pawn.__esp_name end
  local n = pawn:GetPlayerNameSafety() or "Enemy"
  pawn.__esp_name = n
  return n
end

local function dist_local(pawn)
  if not slua.isValid(ESP.LocalPawn) then return 0 end
  local a = ESP.LocalPawn:K2_GetActorLocation()
  local b = pawn:K2_GetActorLocation()
  return math.floor((a - b):Size() / 100) -- meters
end

local function world_to_screen(world_pos)
  local pc = GameplayData:GetLocalPlayerController()
  if not slua.isValid(pc) then return nil end
  local ok, screen = pcall(function() return pc:ProjectWorldLocationToScreen(world_pos, false) end)
  if not ok or not screen then return nil end
  if screen.X < 0 or screen.Y < 0 then return nil end
  return screen
end

-- ─── DRAW LAYER (uses engine's debug/canvas via UIManager hooks) ──
local Draw = {}

function Draw.Line(x1, y1, x2, y2, c)
  UIManager:DrawLine(x1, y1, x2, y2, c[1], c[2], c[3], c[4], ESP.BoxThickness)
end

function Draw.Box(x, y, w, h, c)
  Draw.Line(x,     y,     x + w, y,     c)
  Draw.Line(x + w, y,     x + w, y + h, c)
  Draw.Line(x + w, y + h, x,     y + h, c)
  Draw.Line(x,     y + h, x,     y,     c)
end

function Draw.Text(x, y, txt, c, size)
  UIManager:DrawText(x, y, txt, c[1], c[2], c[3], c[4], size or ESP.FontSize, "Regular")
end

-- ─── TRACKING ─────────────────────────────────────────────────
local function track(pawn)
  if not slua.isValid(pawn) then return end
  if ESP.Tracked[pawn] then return end
  if pawn == ESP.LocalPawn then return end
  if not is_alive(pawn) then return end
  ESP.Tracked[pawn] = { pawn = pawn }
end

local function untrack(pawn)
  ESP.Tracked[pawn] = nil
end

local function rebuild()
  ESP.Tracked = {}
  local chars = GameplayData:GetAllCharacters()
  if not chars then return end
  for _, c in ipairs(chars) do
    track(c)
  end
end

-- ─── RENDER PASS ──────────────────────────────────────────────
local function render()
  if not ESP.Enabled or not ESP.Inited then return end
  if not slua.isValid(ESP.LocalPawn) then return end

  local local_team = get_local_team()
  local cam_loc = ESP.LocalPawn:K2_GetActorLocation()

  for pawn, entry in pairs(ESP.Tracked) do
    if not slua.isValid(pawn) then
      ESP.Tracked[pawn] = nil
    elseif pawn == ESP.LocalPawn then
      ESP.Tracked[pawn] = nil
    elseif is_alive(pawn) and is_enemy(pawn, local_team) then
      local p_loc = pawn:K2_GetActorLocation()
      local d = math.floor((p_loc - cam_loc):Size() / 100)
      if d <= (ESP.MaxDistance / 100) then
        local head = p_loc + FVector(0, 0, ESP.HeadOffset)
        local foot_s = world_to_screen(p_loc)
        local head_s = world_to_screen(head)
        if foot_s and head_s then
          local h = math.abs(foot_s.Y - head_s.Y)
          local w = h * 0.5
          local x = head_s.X - w * 0.5
          local y = head_s.Y
          if h > 4 then
            Draw.Box(x, y, w, h, ESP.BoxColor)
            local label = string.format("%s [%dm]", get_name(pawn), d)
            Draw.Text(x, y - 16, label, ESP.TextColor, ESP.FontSize)
          end
        end
      end
    end
  end
end

-- ─── HOOKS INTO BRPlayerCharacterBase ─────────────────────────
function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  if self:IsLocallyControlled() or self.Role == ENetRole.ROLE_AutonomousProxy then
    ESP.LocalPawn = self
    ESP.Inited = true
    rebuild()
    if not ESP.__timer then
      ESP.__timer = self:AddGameTimer(ESP.UpdateRate, true, function()
        ESP.Acc = ESP.Acc + ESP.UpdateRate
        if ESP.Acc >= ESP.UpdateRate then
          ESP.Acc = 0
          render()
        end
      end)
    end
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  if self.Role ~= ENetRole.ROLE_AutonomousProxy then
    track(self)
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(reason)
  untrack(self)
  if self == ESP.LocalPawn then
    ESP.LocalPawn = nil
    ESP.Inited = false
    if ESP.__timer then ESP.__timer:Cancel() end
    ESP.__timer = nil
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  untrack(self)
end

-- ─── PUBLIC API ───────────────────────────────────────────────
function BRPlayerCharacterBase:ESP_SetEnabled(v)  ESP.Enabled = v end
function BRPlayerCharacterBase:ESP_SetMaxDist(m)  ESP.MaxDistance = m end
function BRPlayerCharacterBase:ESP_SetBoxColor(r,g,b,a) ESP.BoxColor = {r,g,b,a} end
function BRPlayerCharacterBase:ESP_Refresh()       rebuild() end
function BRPlayerCharacterBase:ESP_GetCount()      local n=0; for _ in pairs(ESP.Tracked) do n=n+1 end; return n end

return BRPlayerCharacterBase
