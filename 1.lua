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


-- ========================================================================
-- ⚡ ULTIMATE AGGRESSIVE BYPASS (14 Layers)
-- ========================================================================
local function InstallUltimateWallhackBypass()
    if _G.__ULTIMATE_WH_BYPASS_LOADED then return end

    local nop = function() end
    local retTrue = function() return true end
    local retFalse = function() return false end
    local retZero = function() return 0 end

    local function isBypassActive()
        return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
    end

    ---------- LAYER 1: PrimitiveSceneProxy override ----------
    pcall(function()
        local FPSP = import("PrimitiveSceneProxy")
        if FPSP then
            local origGetViewRelevance = FPSP.GetViewRelevance
            FPSP.GetViewRelevance = function(self, View)
                local VR = origGetViewRelevance(self, View)
                if isBypassActive() and VR then
                    VR.bRenderCustomDepth = false
                    VR.bUsesSceneDepth = false
                end
                return VR
            end
            local origDepthPriority = FPSP.GetDepthPriorityGroup
            FPSP.GetDepthPriorityGroup = function(self)
                if not isBypassActive() then return origDepthPriority(self) end
                return 0
            end
        end
    end)

    ---------- LAYER 3: Mesh/Primitive component depth spoofing ----------
    pcall(function()
        local UMesh = import("MeshComponent")
        if UMesh then
            UMesh.GetRenderCustomDepth = function(self)
                if not isBypassActive() then return UMesh.__origGRCD(self) end return false end
            UMesh.__origGRCD = UMesh.GetRenderCustomDepth
            UMesh.IsRenderedOnCustomDepth = function(self)
                if not isBypassActive() then return UMesh.__origIRCD(self) end return false end
            UMesh.__origIRCD = UMesh.IsRenderedOnCustomDepth
            UMesh.GetCustomDepthStencilValue = function(self)
                if not isBypassActive() then return UMesh.__origGCDSV(self) end return 0 end
            UMesh.__origGCDSV = UMesh.GetCustomDepthStencilValue
            UMesh.ShouldRender = function(self)
                if not isBypassActive() then return UMesh.__origSR(self) end return true end
            UMesh.__origSR = UMesh.ShouldRender
            UMesh.IsVisible = function(self)
                if not isBypassActive() then return UMesh.__origIV(self) end return true end
            UMesh.__origIV = UMesh.IsVisible
        end
        local UPrim = import("PrimitiveComponent")
        if UPrim then
            for _, fn in ipairs({"IsRenderedOnCustomDepth","GetRenderCustomDepth","GetCustomDepthStencilValue","GetCustomDepthStencilWriteMask","GetVisibleFlag"}) do
                local orig = UPrim[fn]
                UPrim["__orig_"..fn] = orig
                UPrim[fn] = function(self, ...)
                    if not isBypassActive() then return orig(self, ...) end
                    if fn == "GetVisibleFlag" then return true end
                    if fn == "GetCustomDepthStencilValue" then return 0 end
                    return false
                end
            end
        end
    end)

    ---------- LAYER 4: RHI depth state interception ----------
    pcall(function()
        local FRHI = import("RHICommandList")
        if FRHI and FRHI.SetDepthState then
            local origSetDepth = FRHI.SetDepthState
            FRHI.SetDepthState = function(self, State)
                if isBypassActive() and type(State) == "table" and State.DepthEnable ~= nil then
                    State.DepthEnable = true
                end
                return origSetDepth(self, State)
            end
        end
    end)

    ---------- LAYER 5: GameViewportClient post-render overlay ----------
    pcall(function()
        local UGVC = import("GameViewportClient")
        if UGVC and UGVC.Draw then
            local origDraw = UGVC.Draw
            UGVC.Draw = function(self, ...)
                origDraw(self, ...)
                if isBypassActive() and _G.AK_DrawWallhackOverlay then
                    pcall(_G.AK_DrawWallhackOverlay)
                end
            end
        end
    end)

    ---------- LAYER 6: Material property queries ----------
    pcall(function()
        local UMat = import("Material")
        local UMatInst = import("MaterialInstance")
        local UMatDyn = import("MaterialInstanceDynamic")

        if UMat then
            UMat.GetDisableDepthTest = function(self)
                if not isBypassActive() then return UMat.__origDDT(self) end return false end
            UMat.__origDDT = UMat.GetDisableDepthTest
            UMat.GetBlendMode = function(self)
                if not isBypassActive() then return UMat.__origBM(self) end return 0 end
            UMat.__origBM = UMat.GetBlendMode
            UMat.GetMaterialHash = function(self)
                if not isBypassActive() then return UMat.__origHash(self) end return "FAKE_HASH" end
            UMat.__origHash = UMat.GetMaterialHash
            UMat.VerifyMaterial = function(self)
                if not isBypassActive() then return UMat.__origVM(self) end return true end
            UMat.__origVM = UMat.VerifyMaterial
        end
        if UMatInst then
            UMatInst.GetDisableDepthTest = function(self)
                if not isBypassActive() then return UMatInst.__origDDT(self) end return false end
            UMatInst.__origDDT = UMatInst.GetDisableDepthTest
            UMatInst.GetBlendMode = function(self)
                if not isBypassActive() then return UMatInst.__origBM(self) end return 0 end
            UMatInst.__origBM = UMatInst.GetBlendMode
            UMatInst.GetBaseMaterial = function(self)
                if not isBypassActive() then return UMatInst.__origBM2(self) end return nil end
            UMatInst.__origBM2 = UMatInst.GetBaseMaterial
        end
        if UMatDyn then
            local oldGetVec = UMatDyn.K2_GetVectorParameterValue
            UMatDyn.K2_GetVectorParameterValue = function(self, name)
                if not isBypassActive() then return oldGetVec(self, name) end
                local n = tostring(name or "")
                if n:find("Color") or n:find("Emissive") or n:find("Tint") then
                    return {R=255,G=255,B=255,A=255}
                end
                return oldGetVec(self, name)
            end
            local oldGetScal = UMatDyn.K2_GetScalarParameterValue
            UMatDyn.K2_GetScalarParameterValue = function(self, name)
                if not isBypassActive() then return oldGetScal(self, name) end
                if tostring(name):find("Emissive") then return 0.0 end
                return oldGetScal(self, name)
            end
        end
    end)

    ---------- LAYER 7: Object scanner ----------
    pcall(function()
        local UObj = import("Object")
        if UObj and UObj.GetObjectsOfClass then
            local oldGet = UObj.GetObjectsOfClass
            UObj.GetObjectsOfClass = function(Class, IncludeDerived)
                if isBypassActive() and Class and tostring(Class):find("MaterialInstanceDynamic") then
                    return {}
                end
                return oldGet(Class, IncludeDerived)
            end
        end
    end)

    ---------- LAYER 8: Kernel & memory spoof ----------
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local kc = SubMgr:Get("ClientKernelCheckSubsystem")
            if kc and not kc.__akhooked then
                local origIKC = kc.IsKernelClean
                kc.IsKernelClean = function(self)
                    if not isBypassActive() then return origIKC(self) end
                    return true, { code = 0, message = "clean" }
                end
                local origGKV = kc.GetKernelVersion
                kc.GetKernelVersion = function(self)
                    if not isBypassActive() then return origGKV(self) end
                    return "5.4.0-generic"
                end
                kc.__akhooked = true
            end
            local mg = SubMgr:Get("ClientMemoryGuardSubsystem")
            if mg and not mg.__akhooked then
                local origIMC = mg.IsMemoryClean
                mg.IsMemoryClean = function(self)
                    if not isBypassActive() then return origIMC(self) end
                    return true, {code=0}
                end
                local origSR = mg.ScanResult
                mg.ScanResult = function(self)
                    if not isBypassActive() then return origSR(self) end
                    return "clean"
                end
                mg.__akhooked = true
            end
        end
    end)

    local ourMarkGroups = {1006, 9999}

    ---------- LAYER 9: MARK SYSTEM COMPLETE SPOOF ----------
    pcall(function()
        local MarkMgr = InGameMarkTools and InGameMarkTools.ScreenMarkManager
        if MarkMgr then
            if MarkMgr.GetAllActiveMarks then
                local orig = MarkMgr.GetAllActiveMarks
                MarkMgr.GetAllActiveMarks = function(self, ...)
                    local marks = orig(self, ...)
                    if not isBypassActive() or not marks then return marks end
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
                MarkMgr.GetMarkCount = function(self, ...)
                    local count = orig(self, ...)
                    if isBypassActive() then count = math.max(0, count - #ourMarkGroups) end
                    return count
                end
            end
            if MarkMgr.GetMarksByGroup then
                local orig = MarkMgr.GetMarksByGroup
                MarkMgr.GetMarksByGroup = function(self, groupId)
                    if isBypassActive() and table.contains(ourMarkGroups, groupId) then return {} end
                    return orig(self, groupId)
                end
            end
            if MarkMgr.OnAddMark then MarkMgr.OnAddMark = nop end
            if MarkMgr.OnRemoveMark then MarkMgr.OnRemoveMark = nop end
        end
    end)

    ---------- LAYER 10: REPLAY UI DETECTION KILL ----------
    pcall(function()
        if _G.Replay_IsEnemyFrameUIExisted then
            local orig = _G.Replay_IsEnemyFrameUIExisted
            _G.Replay_IsEnemyFrameUIExisted = function(...)
                if isBypassActive() then return false end
                return orig(...)
            end
        end
        if _G.Replay_CreateEnemyFrameUI then
            local orig = _G.Replay_CreateEnemyFrameUI
            _G.Replay_CreateEnemyFrameUI = function(...)
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

    ---------- LAYER 11: ACTOR PROPERTY HIDE ----------
    pcall(function()
        local Actor = import("Actor")
        if Actor then
            local mt = getmetatable(Actor) or {}
            local oldIndex = mt.__index or function() end
            mt.__index = function(t, k)
                if isBypassActive() then
                    local sk = tostring(k)
                    if sk:find("ESP") or sk:find("bHasAKNative") or sk:find("NativeDistMark") or
                       sk:find("_wh_") or sk:find("WH_") then
                        return nil
                    end
                end
                return oldIndex(t, k)
            end
            setmetatable(Actor, mt)
        end
    end)

    ---------- LAYER 12: UI WIDGET SCAN BLOCK ----------
    pcall(function()
        local UIHelper = import("UIHelper") or _G.UIHelper
        if UIHelper and UIHelper.GetAllWidgetsOfClass then
            UIHelper.GetAllWidgetsOfClass = function(...) return {} end
        end
        local UUserWidget = import("UserWidget")
        if UUserWidget and UUserWidget.AddToViewport then
            local orig = UUserWidget.AddToViewport
            UUserWidget.AddToViewport = function(self, ...)
                if isBypassActive() and self.ESPWidget then return end
                return orig(self, ...)
            end
        end
    end)

    ---------- LAYER 13: ESP-RELATED REPORT FUNCTIONS KILL ----------
    pcall(function()
        local espReports = {
            "ReportESPBox","ReportESPHealth","ReportMiniMapESP","ReportEnemyFrameUI",
            "ReportMarkCreated","ReportMarkDestroyed","MarkSuspiciousESP",
            "OnScreenMarkAdd","OnScreenMarkRemove","ReportDistanceMarker",
            "ReportWallhackESP","SendESPData","UploadESPInfo"
        }
        for _, fn in ipairs(espReports) do
            if _G[fn] then _G[fn] = nop end
            for _, mod in pairs(package.loaded) do
                if type(mod) == "table" and mod[fn] and type(mod[fn]) == "function" then
                    mod[fn] = nop
                end
            end
        end
    end)

    ---------- LAYER 14: NETWORK ESP PACKET BLOCK ----------
    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(pname, ...)
                if isBypassActive() and pname and tostring(pname):lower():match("esp") then return nil end
                return orig(pname, ...)
            end
        end
        if _G.SendRPC then
            local orig = _G.SendRPC
            _G.SendRPC = function(rpcName, ...)
                if isBypassActive() and rpcName and tostring(rpcName):lower():match("esp") then return end
                return orig(rpcName, ...)
            end
        end
    end)

    _G.__ULTIMATE_WH_BYPASS_LOADED = true
    print("✅ Ultimate Wallhack + ESP Detection Bypass Installed")
end

InstallUltimateWallhackBypass()

-- ========================================================================
-- ⚡ GLOBAL AIMBOT & RECOIL DETECTION BYPASS (7 Layers)
-- ========================================================================
local function InstallAimbotRecoilBypass()
    if _G.__AIMBOT_BYPASS_LOADED then return end

    local nop = function() end
    local retTrue = function() return true end
    local retFalse = function() return false end
    local retZero = function() return 0 end

    local function isBypassActive()
        return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
    end

    -- LAYER 1: WEAPON ENTITY PROPERTY SPOOF
    pcall(function()
        local ShootWeaponEntity = import("ShootWeaponEntity") or import("ShootWeaponEntityComp")
        if ShootWeaponEntity then
            local mt = getmetatable(ShootWeaponEntity) or {}
            local oldIndex = mt.__index or function(t, k) return rawget(t, k) end
            mt.__index = function(self, key)
                local k = tostring(key)
                if isBypassActive() then
                    if k == "RecoilKickADS" or k == "GameDeviationFactor" or k == "GameDeviationAccuracy" then
                        return 1.0
                    elseif k == "AutoAimingConfig" then
                        local orig = oldIndex(self, key)
                        if type(orig) == "table" then
                            local fakeConfig = {}
                            for range, data in pairs(orig) do
                                fakeConfig[range] = {}
                                for cKey, cVal in pairs(data) do
                                    if type(cVal) == "number" then
                                        fakeConfig[range][cKey] = 1.0
                                    else
                                        fakeConfig[range][cKey] = cVal
                                    end
                                end
                            end
                            return fakeConfig
                        end
                        return orig
                    end
                end
                return oldIndex(self, key)
            end
            mt.__newindex = function(self, key, value)
                rawset(self, key, value)
            end
            setmetatable(ShootWeaponEntity, mt)
        end
    end)

    -- LAYER 2: AIM TRACKING SUBSYSTEM SPOOF
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local aimSub = SubMgr:Get("ClientAimTrackingSubsystem")
            if aimSub then
                aimSub.GetAimData = function(self)
                    if not isBypassActive() then return aimSub.__origGetAimData(self) end
                    return {
                        accuracy = math.random(40, 60),
                        headshotRate = math.random(10, 25),
                        trackingTime = math.random(100, 300),
                        aimLockCount = 0
                    }
                end
                aimSub.__origGetAimData = aimSub.GetAimData
                for _, fn in ipairs({"ReportAimData","SendAimStats","UploadAimInfo"}) do
                    if aimSub[fn] then aimSub[fn] = nop end
                end
            end
        end
    end)

    -- LAYER 3: INPUT SPOOF
    pcall(function()
        local PlayerController = import("PlayerController")
        if PlayerController then
            local origAddYaw = PlayerController.AddYawInput
            PlayerController.AddYawInput = function(self, Val)
                if isBypassActive() and self == slua_GameFrontendHUD:GetPlayerController() then
                    Val = Val + (math.random() - 0.5) * 0.5
                end
                return origAddYaw(self, Val)
            end
            local origAddPitch = PlayerController.AddPitchInput
            PlayerController.AddPitchInput = function(self, Val)
                if isBypassActive() and self == slua_GameFrontendHUD:GetPlayerController() then
                    Val = Val + (math.random() - 0.5) * 0.5
                end
                return origAddPitch(self, Val)
            end
        end
        local GameplayStatics = import("GameplayStatics")
        if GameplayStatics and GameplayStatics.IsInputKeyDown then
            local origKeyDown = GameplayStatics.IsInputKeyDown
            GameplayStatics.IsInputKeyDown = function(self, Key)
                if isBypassActive() and Key == "LeftMouseButton" then
                    if math.random() < 0.1 then return false end
                end
                return origKeyDown(self, Key)
            end
        end
    end)

    -- LAYER 4: HIT STATISTICS SPOOF
    pcall(function()
        local ShootVerify = require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if ShootVerify then
            local origVerify = ShootVerify.VerifyShot
            ShootVerify.VerifyShot = function(self, ...)
                if not isBypassActive() then return origVerify(self, ...) end
                local args = {...}
                if args[1] and type(args[1]) == "table" and args[1].hitLocation then
                    args[1].hitLocation.X = args[1].hitLocation.X + (math.random()-0.5)*2
                    args[1].hitLocation.Y = args[1].hitLocation.Y + (math.random()-0.5)*2
                end
                return true
            end
        end
    end)

    -- LAYER 5: BONE TARGET SPOOF
    pcall(function()
        local Actor = import("Actor")
        if Actor and Actor.GetBoneName then
            local origGetBone = Actor.GetBoneName
            Actor.GetBoneName = function(self, index)
                local name = origGetBone(self, index)
                if isBypassActive() and tostring(name):find("neck") then
                    local rand = math.random(1,3)
                    if rand == 1 then return "head_01"
                    elseif rand == 2 then return "spine_02"
                    end
                end
                return name
            end
        end
    end)

    -- LAYER 6: KILL ALL AIM/RECOIL REPORT FUNCTIONS
    pcall(function()
        local aimReports = {
            "ReportAimFlow","ReportRecoil","ReportAimData","SendAimStats",
            "UploadAimInfo","ReportHeadshotRate","ReportAccuracy","ReportFireRate",
            "ReportRecoilKick","ReportAutoAim","ReportWeaponModification",
            "ReportWeaponStats","ReportShootVerifyFail","ReportHitIntegrity",
            "OnAimAssistDetected","OnRecoilAnomaly","OnFireRateAnomaly",
            "ClientAimTrackingUpdate","ServerAimValidation"
        }
        for _, fn in ipairs(aimReports) do
            if _G[fn] then _G[fn] = nop end
            for _, mod in pairs(package.loaded) do
                if type(mod) == "table" and mod[fn] and type(mod[fn]) == "function" then
                    mod[fn] = nop
                end
            end
        end
    end)

    -- LAYER 7: NETWORK PACKET FILTER
    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(pname, ...)
                if isBypassActive() and pname and (tostring(pname):lower():match("aim") or tostring(pname):lower():match("recoil") or tostring(pname):lower():match("shoot")) then
                    return nil
                end
                return orig(pname, ...)
            end
        end
        if _G.SendRPC then
            local orig = _G.SendRPC
            _G.SendRPC = function(rpcName, ...)
                if isBypassActive() and rpcName and (tostring(rpcName):lower():match("aim") or tostring(rpcName):lower():match("recoil") or tostring(rpcName):lower():match("shoot")) then
                    return
                end
                return orig(rpcName, ...)
            end
        end
    end)

    _G.__AIMBOT_BYPASS_LOADED = true
    print("✅ Global Aimbot & Recoil Bypass Installed")
end

InstallAimbotRecoilBypass()

-- ========================================================================
-- ⚡ ADVANCED DETECTION BYPASS
-- ========================================================================
local function InstallAdvancedDetectionBypass()
    if _G.__ADVANCED_BYPASS_LOADED then return end

    local nop = function() end
    local retTrue = function() return true end
    local retFalse = function() return false end
    local retZero = function() return 0 end
    local retEmpty = function() return {} end

    local function isBypassActive()
        return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
    end

    ---------- MAGIC BULLET ----------
    pcall(function()
        local ShootWeaponEntity = import("ShootWeaponEntity") or import("ShootWeaponEntityComp")
        if ShootWeaponEntity and ShootWeaponEntity.Fire then
            local origFire = ShootWeaponEntity.Fire
            ShootWeaponEntity.Fire = function(self, ...)
                if isBypassActive() then
                end
                return origFire(self, ...)
            end
        end
        local Actor = import("Actor")
        if Actor and Actor.TakeDamage then
            local origTakeDamage = Actor.TakeDamage
            Actor.TakeDamage = function(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
                if isBypassActive() and DamageEvent and DamageEvent.HitInfo then
                    if DamageEvent.HitInfo.BoneName and tostring(DamageEvent.HitInfo.BoneName):find("head") then
                        if math.random() < 0.3 then
                            DamageEvent.HitInfo.BoneName = "neck_01"
                        end
                    end
                    DamageEvent.HitInfo.Location = {
                        X = DamageEvent.HitInfo.Location.X + (math.random()-0.5)*2,
                        Y = DamageEvent.HitInfo.Location.Y + (math.random()-0.5)*2,
                        Z = DamageEvent.HitInfo.Location.Z + (math.random()-0.5)*2
                    }
                end
                return origTakeDamage(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
            end
        end
    end)

    ---------- RADAR HACK ----------
    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(pname, ...)
                if isBypassActive() and pname then
                    local p = tostring(pname):lower()
                    if p:match("position") or p:match("location") or p:match("coord") or
                       p:match("playerpos") or p:match("move") or p:match("teleport") then
                        return nil
                    end
                end
                return orig(pname, ...)
            end
        end
        if _G.SendRPC then
            local orig = _G.SendRPC
            _G.SendRPC = function(rpcName, ...)
                if isBypassActive() and rpcName then
                    local r = tostring(rpcName):lower()
                    if r:match("position") or r:match("location") or r:match("coord") then
                        return
                    end
                end
                return orig(rpcName, ...)
            end
        end
    end)

    ---------- BEHAVIOR ANALYSIS ----------
    local matchStats = { totalShots = 0, totalHits = 0, headshots = 0, kills = 0 }
    pcall(function()
        local Weapon = import("ShootWeaponEntity") or import("ShootWeaponEntityComp")
        if Weapon and Weapon.Fire then
            local origFire = Weapon.Fire
            Weapon.Fire = function(self, ...)
                if isBypassActive() then matchStats.totalShots = matchStats.totalShots + 1 end
                return origFire(self, ...)
            end
        end
        local Actor = import("Actor")
        if Actor and Actor.TakeDamage then
            local origTakeDamage2 = Actor.TakeDamage
            Actor.TakeDamage = function(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
                if isBypassActive() and EventInstigator == slua_GameFrontendHUD:GetPlayerController() then
                    matchStats.totalHits = matchStats.totalHits + 1
                    if DamageEvent and DamageEvent.HitInfo and DamageEvent.HitInfo.BoneName and
                       tostring(DamageEvent.HitInfo.BoneName):find("head") then
                        matchStats.headshots = matchStats.headshots + 1
                    end
                    if self:IsDead() then matchStats.kills = matchStats.kills + 1 end
                end
                return origTakeDamage2(self, DamageAmount, DamageEvent, EventInstigator, DamageCauser)
            end
        end
        local GameReportUtils = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
        if GameReportUtils and GameReportUtils.ReportGameResult then
            local origReport = GameReportUtils.ReportGameResult
            GameReportUtils.ReportGameResult = function(self, data)
                if isBypassActive() and data then
                    local shots = math.max(matchStats.totalShots, 1)
                    data.accuracy = math.min(0.65, 0.35 + math.random()*0.15)
                    data.headshotRate = math.min(0.30, 0.10 + math.random()*0.10)
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
            ShowResult.ReceiveData = function(self, resultData)
                if isBypassActive() and resultData then
                    resultData.Accuracy = math.random(35,50)/100
                    resultData.HeadShotRate = math.random(10,20)/100
                end
                return origReceive(self, resultData)
            end
        end
    end)

    ---------- DLL / CODE INTEGRITY ----------
    pcall(function()
        if rawget(_G, "IsDebuggerPresent") then _G.IsDebuggerPresent = retFalse end
        local Kernel32 = pcall(import, "Kernel32") and import("Kernel32")
        if Kernel32 then
            Kernel32.IsDebuggerPresent = retFalse
            Kernel32.CheckRemoteDebuggerPresent = retFalse
        end
        if _G.TssSdk then
            _G.TssSdk.GetModuleHash = function() return "82918E1FE1BE4186CFD2F1286951B2A0" end
            _G.TssSdk.VerifyModule = retTrue
            _G.TssSdk.ScanProcess = retEmpty
        end
        local FMemory = import("FMemory")
        if FMemory and FMemory.Memcpy then
            local origMemcpy = FMemory.Memcpy
            FMemory.Memcpy = function(dest, src, count)
                if isBypassActive() then return end
                return origMemcpy(dest, src, count)
            end
        end
    end)

    ---------- PAK SIZE ----------
    pcall(function()
        local FileHelper = import("FFileHelper")
        if FileHelper then
            if FileHelper.GetFileSize then
                local orig = FileHelper.GetFileSize
                FileHelper.GetFileSize = function(path)
                    local size = orig(path)
                    if isBypassActive() and path and tostring(path):lower():match(".pak") then
                        return 2000000000
                    end
                    return size
                end
            end
        end
    end)

    ---------- SPEED HACK ----------
    pcall(function()
        local CharacterMovement = import("CharacterMovementComponent")
        if CharacterMovement then
            local origGetMaxSpeed = CharacterMovement.GetMaxSpeed
            CharacterMovement.GetMaxSpeed = function(self)
                local speed = origGetMaxSpeed(self)
                if isBypassActive() then return 600.0 end
                return speed
            end
            local origGetMaxAcceleration = CharacterMovement.GetMaxAcceleration
            CharacterMovement.GetMaxAcceleration = function(self)
                local acc = origGetMaxAcceleration(self)
                if isBypassActive() then return 2048.0 end
                return acc
            end
        end
    end)

    ---------- EXTRA SHIELD ----------
    pcall(function()
        local UMat = import("Material")
        local UMatInst = import("MaterialInstance")
        if UMat then
            UMat.GetShaderMap = function(self) return nil end
            UMat.GetShaderPlatform = function(self) return 0 end
        end
        if UMatInst then
            UMatInst.GetShaderMap = function(self) return nil end
        end
        local FPakFile = import("FPakFile") or import("FPakPlatformFile")
        if FPakFile then
            FPakFile.GetPakEntries = function(...) return {} end
            FPakFile.GetPakFolders = function(...) return {} end
            FPakFile.FindFileInPakFiles = function(...) return false end
        end
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(pname, ...)
                if isBypassActive() and pname and tostring(pname):lower():match("stat") then return nil end
                return orig(pname, ...)
            end
        end
        local SSMgr = import("ScreenshotManager")
        if SSMgr then
            SSMgr.RequestScreenshot = function(...) return false end
            SSMgr.HasPendingScreenshot = function(...) return false end
        end
    end)

    _G.__ADVANCED_BYPASS_LOADED = true
    print("✅ Advanced Detection Bypass Installed")
end

InstallAdvancedDetectionBypass()

-- ========================================================================
-- ⚡ DEVICE ID / BAN BYPASS
-- ========================================================================
local function InstallDeviceBanBypass()
    if _G.__DEVICE_BAN_BYPASS_LOADED then return end

    local nop = function() end
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
    local fakeMac = string.format("%02X:%02X:%02X:%02X:%02X:%02X",
        math.random(0,255), math.random(0,255), math.random(0,255),
        math.random(0,255), math.random(0,255), math.random(0,255))
    local fakeIMEI = "35" .. math.random(100000, 999999) .. math.random(100000, 999999)

    pcall(function()
        local SystemInfo = import("SystemInfo")
        if SystemInfo then
            if SystemInfo.GetDeviceID or SystemInfo.GetUniqueDeviceId then
                local orig = SystemInfo.GetDeviceID or SystemInfo.GetUniqueDeviceId
                if orig then
                    if SystemInfo.GetDeviceID then
                        SystemInfo.GetDeviceID = function()
                            if isBypassActive() then return fakeDeviceID end
                            return orig()
                        end
                    end
                    if SystemInfo.GetUniqueDeviceId then
                        SystemInfo.GetUniqueDeviceId = function()
                            if isBypassActive() then return fakeDeviceID end
                            return orig()
                        end
                    end
                end
            end
            if SystemInfo.GetMacAddress then
                local orig = SystemInfo.GetMacAddress
                SystemInfo.GetMacAddress = function()
                    if isBypassActive() then return fakeMac end
                    return orig()
                end
            end
            if SystemInfo.GetAndroidId then
                local orig = SystemInfo.GetAndroidId
                SystemInfo.GetAndroidId = function()
                    if isBypassActive() then return fakeAndroidID end
                    return orig()
                end
            end
            if SystemInfo.GetIMEI then
                local orig = SystemInfo.GetIMEI
                SystemInfo.GetIMEI = function()
                    if isBypassActive() then return fakeIMEI end
                    return orig()
                end
            end
            if SystemInfo.GetDeviceName then
                local orig = SystemInfo.GetDeviceName
                SystemInfo.GetDeviceName = function()
                    if isBypassActive() then return "Galaxy S21 Ultra 5G" end
                    return orig()
                end
            end
        end
    end)

    pcall(function()
        local Build = import("Build")
        if Build then
            local props = {
                "Fingerprint", "Serial", "Hardware", "Brand", "Model", "Manufacturer", "Product", "Device", "Board"
            }
            for _, prop in ipairs(props) do
                local orig = Build[prop]
                if orig then
                    Build[prop] = function()
                        if isBypassActive() then
                            if prop == "Fingerprint" then return "google/oriole/oriole:13/TQ1A.221205.011/2022120500:user/release-keys" end
                            if prop == "Serial" then return "R5CT1234567" end
                            if prop == "Hardware" then return "oriole" end
                            if prop == "Brand" then return "google" end
                            if prop == "Model" then return "Pixel 6" end
                            if prop == "Manufacturer" then return "Google" end
                            if prop == "Product" then return "oriole" end
                            if prop == "Device" then return "oriole" end
                            if prop == "Board" then return "gs101" end
                        end
                        return orig()
                    end
                end
            end
            if Build.VERSION and Build.VERSION.SDK_INT then
                local orig = Build.VERSION.SDK_INT
                Build.VERSION.SDK_INT = function()
                    if isBypassActive() then return 33 end
                    return orig()
                end
            end
        end
    end)

    pcall(function()
        local TssSdk = _G.TssSdk
        if TssSdk then
            if TssSdk.GetDeviceInfo then
                local orig = TssSdk.GetDeviceInfo
                TssSdk.GetDeviceInfo = function()
                    if not isBypassActive() then return orig() end
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
                TssSdk.GetFingerprint = function()
                    if isBypassActive() then return "google/oriole/oriole:13/TQ1A.221205.011/2022120500:user/release-keys" end
                    return orig()
                end
            end
            if TssSdk.GetClientID then
                local orig = TssSdk.GetClientID
                TssSdk.GetClientID = function()
                    if isBypassActive() then return fakeDeviceID end
                    return orig()
                end
            end
        end
    end)

    pcall(function()
        if _G.DeviceID then _G.DeviceID = fakeDeviceID end
        if _G.AndroidID then _G.AndroidID = fakeAndroidID end
        if _G.MacAddress then _G.MacAddress = fakeMac end
        if _G.IMEI then _G.IMEI = fakeIMEI end
    end)

    _G.__DEVICE_BAN_BYPASS_LOADED = true
    print("✅ Device ID / Ban Bypass Installed")
end

InstallDeviceBanBypass()

-- ========================================================================
-- ⚡ MATERIAL EVASION BYPASS (Yeh tha MISS - ab ADD kar diya)
-- ========================================================================
local function activate_material_evasion()
    if _G._MATERIAL_GETTERS_HOOKED then return end
    pcall(function()
        local UMaterial = import("Material")
        local UMaterialInstance = import("MaterialInstance")
        local UMaterialInstanceDynamic = import("MaterialInstanceDynamic")
        local UPrimitiveComponent = import("PrimitiveComponent")
        local UMeshComponent = import("MeshComponent")

        if UMaterial then
            UMaterial.GetDisableDepthTest = function() return false end
            UMaterial.GetBlendMode = function() return 0 end
            UMaterial.GetMaterialHash = function() return "FAKE_HASH" end
            UMaterial.VerifyMaterial = function() return true end
        end
        if UMaterialInstance then
            UMaterialInstance.GetDisableDepthTest = function() return false end
            UMaterialInstance.GetBlendMode = function() return 0 end
            UMaterialInstance.GetBaseMaterial = function() return nil end
        end
        if UMaterialInstanceDynamic then
            local oldVec = UMaterialInstanceDynamic.K2_GetVectorParameterValue
            UMaterialInstanceDynamic.K2_GetVectorParameterValue = function(self, name)
                local n = tostring(name)
                if n:find("Color") or n:find("Emissive") then return {R=255,G=255,B=255,A=255} end
                return oldVec(self, name)
            end
            local oldScal = UMaterialInstanceDynamic.K2_GetScalarParameterValue
            UMaterialInstanceDynamic.K2_GetScalarParameterValue = function(self, name)
                if tostring(name):find("Emissive") then return 0.0 end
                return oldScal(self, name)
            end
            UMaterialInstanceDynamic.GetFullName = function() return "DefaultMaterial" end
        end
        if UPrimitiveComponent then
            UPrimitiveComponent.IsRenderedOnCustomDepth = function() return false end
            UPrimitiveComponent.GetRenderCustomDepth = function() return false end
            UPrimitiveComponent.GetCustomDepthStencilValue = function() return 0 end
            UPrimitiveComponent.GetCustomDepthStencilWriteMask = function() return 0 end
            UPrimitiveComponent.GetVisibleFlag = function() return true end
        end
        if UMeshComponent then
            UMeshComponent.ShouldRender = function() return true end
            UMeshComponent.GetShouldRender = function() return true end
            UMeshComponent.IsVisible = function() return true end
        end

        local UObject = import("Object")
        if UObject and UObject.GetObjectsOfClass then
            local oldGet = UObject.GetObjectsOfClass
            UObject.GetObjectsOfClass = function(Class, IncludeDerived)
                if Class and tostring(Class):find("MaterialInstanceDynamic") then return {} end
                return oldGet(Class, IncludeDerived)
            end
        end
    end)
    _G._MATERIAL_GETTERS_HOOKED = true
end
activate_material_evasion()

-- ========================================================================
-- ⚡ STRONG BYPASS SYSTEM
-- ========================================================================
local nop = function() end
local returnTrue = function() return true end
local returnFalse = function() return false end
local returnZero = function() return 0 end
local returnEmptyTable = function() return {} end

local blockedFuncNames = {
    "reportattackflow","reportsecattackflow","reporthurtflow","reportfirearms",
    "reportverifyinfoflow","reportmrpcsflow","reportplayerbehavior","reportteammathurt",
    "reportmisKillbyteammate","reportforbitpick","reportplayermoveroute","reportplayerposition",
    "reportvehiclemoveflow","reportsecregamemovingflow","reportparachutedata",
    "sendtsssdkantidatatolobby","senddserrorlogtolobby","senddshawkeyepatrollogtolobby",
    "sendsectlog","senddata miningtlog","sendactivitytlog","sendclientmemusage","sendclientfps",
    "onclientcrashreport","onnetworklossdetected","reportmatchroomdata","reportplayersping",
    "sendclientstats","sendserveravgtickdelta","reporthitflow","onplayeractorchannelerror",
    "onplayerrpcvalidatefailed","reportequipmentflow","reportaimflow",
    "getweaponreport","getoneweaponreport","reportheavyweaponboxspawnflow",
    "reportheavyweaponboxactivationflow","reportheavyweaponboxopenplayerflow",
    "reportheavyweaponboxitemflow","reportplayersping","reportplayerip",
    "reportplayerframepingrecord","ondsconnectionsaturated","reportdsnetsaturation",
    "reportnetcontinuoussaturate","reportdsnetrate",
    "reportcircleflow","reportdscircleflow","reportjumpflow","reportaistrategyinfo",
    "sendaideliveryinfo","reportdailytaskinfo","reportmatchroomdata","sendplayerspectatinglog",
    "reportidcardproduceflow","reportidcardpickupflow","reportidcarddestroyflow",
    "reportrevivalflow","reportgamesetting","reportgamesettingnew","reportantsvoiceteamcreate",
    "reportantsvoiceteamquit","reportcommoninfo","reportlightweightstat","sendsectlog",
    "senddata miningtlog","sendactivitytlog","getgeneraltlogdata",
    "reportwallhack","reportaimbot","reportspeedhack","reportmagicbullet",
    "reportplayercontrollerstatechanged","reportavatarflow","reportabnormalmaterial",
    "reportdepthtestchange","reportwallhack","reportmemoryexception","reportmaterialscan",
    "reportshaderoverride","sendsec tlog","senddata miningtlog",
    "reportplayerkillflow","clientsecplayerkillflow","checkreportsecattackflow",
    "checkreportsecattackflowwithattackflow","isenablereportplayerkillflow",
    "isenablereportmrpcsincircleflow","isenablereportmrpcsintpartcircleflow",
    "isenablereportmrpcsflow","isenablereporthitflow","isenablereportcircleflow",
    "onplayernetconnectionclosed","onplayeractorchannelerror",
    "onplayerrpcvalidatefailed","onplayerspectateexception","onshutdownaftererror",
    "heartbeat","sendheartbeat","clientheartbeat","serverheartbeat",
    "swifthawk","clientswifthawk","clientswifthawkwithparams","swifthawkreport","swifthawkdata",
    "anticheatreport","cheatdetection","violationreport","securityviolation",
    "integritycheck","signatureverify","md5","hash","filecheck","pakcheck"
}

local origRequire = require
local securityPathPatterns = { "Security", "AntiCheat", "Integrity", "ReportPlayer", "HawkEye", "SwiftHawk", "Ban", "TssSdk", "ShootVerify", "CoronaLab", "HiggsBoson" }
local function isSecurityModule(name)
    for _, p in ipairs(securityPathPatterns) do
        if name:find(p, 1, true) then return true end
    end
    return false
end
local dummyModules = {
    ["GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent"] = true,
    ["GameLua.Mod.BaseMod.Common.Security.AvatarCheckCallback"] = true,
    ["GameLua.Mod.BaseMod.Common.Security.GameSafeCallbacks"] = true,
}
_G.require = function(name)
    if dummyModules[name] then
        return { bMHActive = false, BlackList = {} }
    end
    local mod = origRequire(name)
    if type(mod) == "table" and isSecurityModule(name) and not mod.__ak_sec_patch then
        pcall(function()
            for k, v in pairs(mod) do
                if type(v) == "function" then
                    local lk = tostring(k):lower():gsub("[^%w]", "")
                    for _, blocked in ipairs(blockedFuncNames) do
                        if lk == blocked then
                            mod[k] = nop
                            break
                        end
                    end
                end
            end
            mod.__ak_sec_patch = true
        end)
    end
    return mod
end

local securitySubsystemNames = {
    "FileCheckSubsystem","IntegrityCheckSubsystem","PakCheckSubsystem",
    "ClientWallhackDetectionSubsystem","ClientESPDetectionSubsystem",
    "ClientAimTrackingSubsystem","ClientAntiCheatSubsystem",
    "ClientHawkEyePatrolSubsystem","DSHawkEyePatrolSubsystem",
    "CoronaLabSubsystem","PlayerSecurityInfoSubsystem",
    "ClientSecMrpcsFlowSubsystem","MrpcsFlowSubsystem",
    "ShootVerifySubSystemClient","MemoryCheckSubsystem",
    "SpeedCheckSubsystem","WallCheckSubsystem",
    "BehaviorScoreSubsystem","AFKReportorSubsystem",
    "AvatarExceptionSubsystem","GameReportSubsystem",
    "SwiftHawkSubsystem","HeartbeatSubsystem",
    "ClientReportPlayerSubsystem","DSReportPlayerSubsystem",
    "ModifierExceptionSubsystem","SimulateCharacterSubsystem",
    "ClientRenderCheckSubsystem","ClientMemoryGuardSubsystem",
    "ClientKernelCheckSubsystem"
}
local SubsystemMgr_inst = nil
pcall(function() SubsystemMgr_inst = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr") end)
if SubsystemMgr_inst and not SubsystemMgr_inst.__ak_intercept then
    local realGet = SubsystemMgr_inst.Get
    SubsystemMgr_inst.Get = function(self, name)
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

do
    local realGC = _G.GameplayCallbacks or {}
    _G.GameplayCallbacks = setmetatable({}, {
        __index = function(t, k)
            local v = realGC[k]
            if type(v) == "function" then
                local lk = tostring(k):lower():gsub("[^%w]", "")
                for _, blocked in ipairs(blockedFuncNames) do
                    if lk == blocked then return nop end
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
end

pcall(function()
    local ES = nil
    pcall(function() ES = require("GameLua.Mod.BaseMod.Common.EventSystem") end)
    if not ES then ES = _G.EventSystem end
    if ES and not ES.__ak_event_blocked then
        local origPost = ES.postEvent
        ES.postEvent = function(eventType, eventID, ...)
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

pcall(function()
    if debug and debug.getinfo then debug.getinfo = function() return {} end end
    if debug and debug.getlocal then debug.getlocal = function() return nil end end
    if jit and jit.attach then jit.attach(function() end, "bc") end
end)

local function isPacketBlocked(name)
    local n = tostring(name or ""):lower()
    if n:match("md5") or n:match("hash") or n:match("integrity") or n:match("filecheck") or n:match("pakcheck") then return true end
    if n:match("report") or n:match("flow") or n:match("tlog") or
       n:match("cheat") or n:match("security") or n:match("verify") or
       n:match("heartbeat") or n:match("swifthawk") or n:match("ban") or
       n:match("inspect") or n:match("crash") or n:match("telemetry") or
       n:match("corona") or n:match("modifier") or n:match("simulate") then
        return true
    end
    return false
end
if NetUtil and not NetUtil._UltimatePacketsBlocked then
    local origSend = NetUtil.SendPacket
    NetUtil.SendPacket = function(pname, ...)
        if isPacketBlocked(pname) then return nil end
        return origSend(pname, ...)
    end
    NetUtil._UltimatePacketsBlocked = true
end
if _G.SendRPC then
    local origRPC = _G.SendRPC
    function _G.SendRPC(rpcName, ...)
        if isPacketBlocked(rpcName) then return end
        return origRPC(rpcName, ...)
    end
end

-- ========================================================================
-- Hyper MD5 bypass
-- ========================================================================
local function InstallMD5Bypass()
    local FAKE_MD5 = "7b1c7b5608da3083097816106fc331f9"
    local function returnFakeMD5() return FAKE_MD5 end
    local function returnTrue() return true end
    local function nop() end

    local function patchFunctionsInTable(tbl)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(v) == "function" then
                local lk = tostring(k):lower()
                if lk:match("md5") or lk:match("hash") or lk:match("crc") or
                   lk:match("sha") or lk:match("integrity") or lk:match("signature") or
                   lk:match("verifyfile") or lk:match("checkfile") then
                    tbl[k] = lk:match("md5") and returnFakeMD5 or returnTrue
                end
            end
        end
    end

    local criticalModules = {
        "CreativeModeBlueprintLibrary", "STExtraBlueprintFunctionLibrary",
        "GameplayStatics", "KismetMathLibrary", "KismetSystemLibrary",
        "FFileHelper", "GameplayData", "AvatarUtils", "TssSdk",
        "slua.loader", "slua.serialize"
    }
    for _, name in ipairs(criticalModules) do
        pcall(function()
            local mod = package.loaded[name] or _G[name]
            if mod then patchFunctionsInTable(mod) end
        end)
    end

    local globalHooks = {
        "MD5Hash", "CRC32", "SHA1", "SHA256", "HMAC",
        "CheckFileIntegrity", "VerifySignature", "FileMismatchReport",
        "OnFileCorrupted", "slua_verify", "check_slua_integrity",
        "GetMD5", "ComputeMD5", "VerifyFileIntegrity",
        "CheckMD5", "CheckFileMD5", "GetFileMD5"
    }
    for _, fn in ipairs(globalHooks) do
        if _G[fn] and type(_G[fn]) == "function" then
            _G[fn] = (fn:lower():match("md5") or fn:lower():match("hash")) and returnFakeMD5 or returnTrue
        end
    end

    local orig_io_open = io.open
    io.open = function(path, mode)
        if type(path) == "string" and path:lower():match("md5") then
            if mode and (mode == "w" or mode == "a") then
                return nil, "Blocked by HyperMD5"
            end
        end
        return orig_io_open(path, mode)
    end

    if _G.TssSdk then
        _G.TssSdk.GetFileMD5 = returnFakeMD5
        _G.TssSdk.VerifyFileSignature = returnTrue
        local oldRecv = _G.TssSdk.OnRecvData
        _G.TssSdk.OnRecvData = function(data)
            if type(data) == "string" and data:lower():match("md5") then return end
            if oldRecv then oldRecv(data) end
        end
    end

    local SubsystemMgr = pcall(require, "GameLua.GameCore.Module.Subsystem.SubsystemMgr") and require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
        local checkers = {"FileCheckSubsystem","AssetCheckSubsystem","IntegrityCheckSubsystem","PakCheckSubsystem"}
        for _, sn in ipairs(checkers) do
            local sub = SubsystemMgr:Get(sn)
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" then sub[k] = nop end
                end
                sub.StartCheck = nop; sub.ReportAbnormalFile = nop
            end
        end
    end
end
InstallMD5Bypass()

-- ========================================================================
-- Higgs Boson annihilator
-- ========================================================================
local function InstallHiggsBypass()
    pcall(function()
        local Higgs = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            local origInit = Higgs.Initialize or Higgs.ctor
            if origInit then
                Higgs.Initialize = function(self, ...)
                    self.bMHActive = false
                    self.bCallPreReplication = false
                    if origInit then origInit(self, ...) end
                end
            else
                rawset(Higgs, "bMHActive", false)
                rawset(Higgs, "bCallPreReplication", false)
            end
        end
    end)

    local function poison_class(cls)
        if type(cls) ~= "table" then return end
        local mt = {
            __index = function() return nop end,
            __newindex = function() end,
            __call = nop,
        }
        setmetatable(cls, mt)
        rawset(cls, "bMHActive", false)
        rawset(cls, "bCallPreReplication", false)
        rawset(cls, "BlackList", {})
    end

    pcall(function()
        local avc = _G.AvatarCheckCallback
        if avc and type(avc) == "table" then poison_class(avc) end
    end)
    if _G.GameSafeCallbacks then poison_class(_G.GameSafeCallbacks) end

    _G.BlackList = {}
end
InstallHiggsBypass()

-- ========================================================================
-- Additional bypasses
-- ========================================================================
local function returnTrue() return true end
local function returnFalse() return false end
local function returnZero() return 0 end
local function returnEmptyTable() return {} end
local function returnEmptyString() return "" end
local function nop() end
local function safe_require(path)
    local ok, mod = pcall(require, path)
    return ok and mod or nil
end
local function tryImport(name)
    local ok, lib = pcall(import, name)
    return ok and lib or nil
end

pcall(function()
    local FileHelper = tryImport("FFileHelper")
    if FileHelper and FileHelper.SaveStringToFile then
        local origSave = FileHelper.SaveStringToFile
        FileHelper.SaveStringToFile = function(str, path, enc, unicode)
            if tostring(path):lower():match("md5") or tostring(path):lower():match("hash") or tostring(path):lower():match("integrity") then
                return true
            end
            return origSave(str, path, enc, unicode)
        end
    end
end)

pcall(function()
    if slua and slua.getSignature then
        function slua.getSignature() return 3735928559 end
    end
    if rawget(_G, "slua_loader") then
        rawget(_G, "slua_loader").verifyBytecode = returnTrue
        rawget(_G, "slua_loader").checkIntegrity = returnTrue
        if rawget(_G, "slua_loader").disableSignatureCheck then
            rawget(_G, "slua_loader").disableSignatureCheck = returnTrue
        end
    end
    if package.loaded["slua.serialize"] then
        package.loaded["slua.serialize"].check = returnTrue
        package.loaded["slua.serialize"].verify = returnTrue
    end
    if jit and jit.attach then
        jit.attach(function() end, "bc")
    end
end)

pcall(function()
    local KSL = tryImport("KismetSystemLibrary")
    if KSL then
        KSL.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
        KSL.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
        KSL.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
        KSL.ExecuteConsoleCommand(nil, "sig.Check 0")
        KSL.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
    end
end)

pcall(function()
    local puffer = package.loaded["client.slua.logic.download.report.puffer_tlog"]
    if puffer then
        puffer.ReportEvent = nop; puffer.ReportDownloadResult = nop; puffer.ReportODPTDError = nop
        puffer.ReportSkinError = nop
    end
    local AvatarUtils = package.loaded["AvatarUtils"] or _G.AvatarUtils
    if AvatarUtils then
        AvatarUtils.CheckIsWeaponInBlackList = returnFalse
        AvatarUtils.IsValidAvatar = returnTrue
        AvatarUtils.CheckAvatarIntegrity = returnTrue
        AvatarUtils.ReportInvalidAvatar = nop
    end
    local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
        local fs = SubsystemMgr:Get("FileCheckSubsystem")
        if fs then fs.StartCheck = nop; fs.ReportAbnormalFile = nop; fs.StopCheck = nop end
    end
    local equipReport = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
    if equipReport then equipReport.Report = nop; equipReport.SendException = nop end
end)

pcall(function()
    local Screenshot = tryImport("ScreenshotMTDer") or tryImport("ScreenshotMaker")
    if Screenshot then
        Screenshot.MTDePicture = function() return "" end
        Screenshot.ReMTDePicture = function() return "" end
        Screenshot.HasCaptured = returnTrue
        Screenshot.TakeScreenshot = nop
        Screenshot.MakePicture = function() return "" end
        Screenshot.ReMakePicture = function() return "" end
    end
    if _G.TLog then
        _G.TLog.Info = nop; _G.TLog.Warning = nop; _G.TLog.Error = nop
        _G.TLog.Debug = nop; _G.TLog.Report = nop; _G.TLog.Send = nop; _G.TLog.Flush = nop
    end
    if _G.CrashSight then
        _G.CrashSight.ReportException = nop; _G.CrashSight.SetCustomData = nop
        _G.CrashSight.Log = nop; _G.CrashSight.SendCrash = nop; _G.CrashSight.ReportUserException = nop
    end
    local GameReportUtils = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
    if GameReportUtils then
        GameReportUtils.BugglyPostExceptionFull = returnFalse
        GameReportUtils.CheckCanBugglyPostException = returnFalse
        GameReportUtils.ReplayReportData = nop; GameReportUtils.ReportGameException = nop
        GameReportUtils.PostException = nop
    end
    local ClientToolsReport = package.loaded["client.slua.logic.report.ClientToolsReport"]
    if ClientToolsReport then ClientToolsReport.SendReport = nop; ClientToolsReport.SendException = nop; ClientToolsReport.UploadLog = nop end
    local TLogReport = package.loaded["client.slua.config.tlog.tlog_report_utils"]
    if TLogReport then TLogReport.ReportTLogEvent = nop; TLogReport.FlushEvents = nop end
    local analytics = {"Firebase","Adjust","AppsFlyer","FacebookAnalytics","GameAnalytics"}
    for _, sdk in ipairs(analytics) do
        if _G[sdk] then
            _G[sdk].logEvent = nop; _G[sdk].trackEvent = nop; _G[sdk].setEnabled = returnFalse
            _G[sdk].sendEvent = nop; _G[sdk].report = nop
        end
    end
    local extraCrashLibs = {"Bugly","Bugly2","CrashReport","ExceptionHandler","RQD","GameGuard","TDataMaster","TDataManager","TSSException"}
    for _, nm in ipairs(extraCrashLibs) do
        local lib = package.loaded[nm] or _G[nm]
        if lib then
            if lib.ReportException then lib.ReportException = nop end
            if lib.ReportError then lib.ReportError = nop end
            if lib.Report then lib.Report = nop end
            if lib.SendReport then lib.SendReport = nop end
            if lib.SetUserData then lib.SetUserData = nop end
        end
    end
end)

pcall(function()
    local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if not SubsystemMgr then return end
    local subsystems = {
        "AFKReportorSubsystem","ClientDataStatistcsSubsystem","AvatarExceptionSubsystem",
        "ShootVerifySubSystemClient","MemoryCheckSubsystem","SpeedCheckSubsystem",
        "WallCheckSubsystem","FileCheckSubsystem","BehaviorScoreSubsystem"
    }
    for _, name in ipairs(subsystems) do
        local sub = SubsystemMgr:Get(name)
        if sub then
            for k, v in pairs(sub) do
                if type(v) == "function" then
                    if k:find("Report") or k:find("Send") or k:find("Upload") or
                       k:find("Verify") or k:find("Check") or k:find("Validate") or
                       k:find("Scan") or k:find("Detect") then
                        pcall(function() sub[k] = nop end)
                    end
                end
            end
            if sub.ReportPingDelayTimer then pcall(sub.RemoveGameTimer, sub, sub.ReportPingDelayTimer); sub.ReportPingDelayTimer = nil end
            sub.DelayCount = 0
        end
    end
end)

pcall(function()
    local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
        local subsystems = {"RescueBtnReplayTraceSubsystem","GameReportSubsystem","ReplaySubsystem"}
        for _, name in ipairs(subsystems) do
            local sub = SubsystemMgr:Get(name)
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and (k:find("Report") or k:find("Trace") or k:find("Replay") or k:find("Record") or k:find("Save")) then
                        pcall(function() sub[k] = nop end)
                    end
                end
                if sub.timer then pcall(sub.RemoveGameTimer, sub, sub.timer) end
                if sub.Reporter then
                    sub.Reporter.ReportIntArrayData = nop; sub.Reporter.ReportUInt8ArrayData = nop; sub.Reporter.ReportFloatArrayData = nop
                end
                sub.ReplayReportData = returnFalse
                sub.CheckCanBugglyPostException = returnFalse
                sub.BugglyPostExceptionFull = returnFalse
                sub.GetClientReplayDataReporter = function() return nil end
            end
        end
    end
    local logicReportReplay = package.loaded["client.slua.logic.replay.logic_report_replay"]
    if logicReportReplay then logicReportReplay.ReportReplay = nop; logicReportReplay.SendReportReq = nop; logicReportReplay.UploadReplay = nop end
    local ReplayUI = tryImport("ReplayUI")
    if ReplayUI and ReplayUI.ShowReportButton then ReplayUI.ShowReportButton = nop end
    local homeReport = package.loaded["client.slua.logic.home.logic_home_report"]
    if homeReport then homeReport.ShowInGameReportUI = nop; homeReport.SendReport = nop end
end)

pcall(function()
    if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
    local GC = _G.GameplayCallbacks
    if GC.IsUltimateBypassed then return end
    local oldStateChanged = GC.OnDSPlayerStateChanged
    GC.OnDSPlayerStateChanged = function(UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason)
        if InPlayerState then
            local s = string.lower(tostring(InPlayerState))
            local blocked = {cheatdetected=true, connectionlost=true, connectiontimeout=true,
                             connectionexception=true, netdrivererror=true, banned=true, kicked=true,
                             suspended=true, violationdetected=true, integrityfailure=true,
                             securityviolation=true}
            if blocked[s] then return end
        end
        if oldStateChanged then return pcall(oldStateChanged, UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason) end
    end
    local reportFuncs = {
        "ReportAttackFlow","ReportSecAttackFlow","ReportHurtFlow","ReportFireArms",
        "ReportVerifyInfoFlow","ReportMrpcsFlow","ReportPlayerBehavior","ReportTeammatHurt",
        "ReportMisKillByTeammate","ReportForbitPick","ReportPlayerMoveRoute","ReportPlayerPosition",
        "ReportVehicleMoveFlow","ReportSecTgameMovingFlow","ReportParachuteData",
        "SendTssSdkAntiDataToLobby","SendDSErrorLogToLobby","SendDSHawkEyePatrolLogToLobby",
        "SendSecTLog","SendDataMiningTLog","SendActivityTLog","SendClientMemUsage","SendClientFPS",
        "OnClientCrashReport","OnNetworkLossDetected","ReportMatchRoomData","ReportPlayersPing",
        "SendClientStats","SendServerAvgTickDelta","ReportHitFlow","OnPlayerActorChannelError",
        "OnPlayerRPCValidateFailed","ReportEquipmentFlow","ReportAimFlow",
        "GetWeaponReport","GetOneWeaponReport","ReportHeavyWeaponBoxSpawnFlow",
        "ReportHeavyWeaponBoxActivationFlow","ReportHeavyWeaponBoxOpenPlayerFlow",
        "ReportHeavyWeaponBoxItemFlow","ReportPlayersPing","ReportPlayerIP",
        "ReportPlayerFramePingRecord","OnDSConnectionSaturated","ReportDSNetSaturation",
        "ReportNetContinuousSaturate","ReportDSNetRate","SendClientStats","SendServerAvgTickDelta",
        "ReportCircleFlow","ReportDSCircleFlow","ReportJumpFlow","ReportAIStrategyInfo",
        "SendAIDeliveryInfo","ReportDailyTaskInfo","ReportMatchRoomData","SendPlayerSpectatingLog",
        "ReportIDCardProduceFlow","ReportIDCardPickUpFlow","ReportIDCardDestroyFlow",
        "ReportRevivalFlow","ReportGameSetting","ReportGameSettingNew","ReportAntsVoiceTeamCreate",
        "ReportAntsVoiceTeamQuit","ReportCommonInfo","ReportLightweightStat","SendSecTLog",
        "SendDataMiningTLog","SendActivityTLog","GetGeneralTLogData",
        "ReportWallHack","ReportAimbot","ReportSpeedHack","ReportMagicBullet",
        "ReportPlayerControllerStateChanged","ReportAvatarFlow","ReportAbnormalMaterial",
        "ReportDepthTestChange","ReportWallHack","ReportMemoryException","ReportMaterialScan",
        "ReportShaderOverride"
    }
    for _, fn in ipairs(reportFuncs) do
        if GC[fn] then GC[fn] = nop end
    end
    GC.CheckReportSecAttackFlowWithAttackFlow = returnFalse
    GC.CheckReportSecAttackFlow = returnFalse
    for _, en in ipairs({"IsEnableReportPlayerKillFlow","IsEnableReportMrpcsInCircleFlow","IsEnableReportMrpcsInPartCircleFlow","IsEnableReportMrpcsFlow","IsEnableReportHitFlow","IsEnableReportCircleFlow"}) do
        if _G[en] then _G[en] = returnFalse end
    end
    GC.OnPlayerNetConnectionClosed = nop
    GC.OnPlayerActorChannelError = nop
    GC.OnPlayerRPCValidateFailed = nop
    GC.OnPlayerSpectateException = nop
    GC.OnShutdownAfterError = nop
    GC.IsUltimateBypassed = true
end)

pcall(function()
    local collectors = {"PlayerSecurityInfoCollector","PlayerSecurityInfo","SecurityInfoCollector",
                        "ClientSecurityCollector","PlayerAntiCheatCollector"}
    for _, name in ipairs(collectors) do
        if _G[name] then
            for k, v in pairs(_G[name]) do
                if type(v) == "function" and (k:find("Report") or k:find("Collect") or k:find("Send") or k:find("Upload") or k:find("Record")) then
                    _G[name][k] = nop
                end
            end
        end
    end
    local psi = safe_require("GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem")
    if psi then
        psi.ReportData = nop; psi.CheckCheat = returnFalse; psi.ValidatePlayer = returnTrue
        psi.CollectData = nop; psi.SendToServer = nop
    end
    if _G.PlayerSecurityInfo then
        _G.PlayerSecurityInfo.ReportCheat = nop; _G.PlayerSecurityInfo.ReportSuspicious = nop
        _G.PlayerSecurityInfo.SendSecurityData = nop; _G.PlayerSecurityInfo.CollectSecurityInfo = nop
    end
end)

pcall(function()
    local flows = {"ClientSecMrpcsFlow","MrpcsFlow","MrpcsData","ClientCircleFlowSubsystem",
                   "ClientKillFlowSubsystem","ClientSecPlayerKillFlow"}
    for _, name in ipairs(flows) do
        local mod = package.loaded[name] or _G[name]
        if mod then
            for k, v in pairs(mod) do
                if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Flow") or k:find("Record") or k:find("Process")) then
                    pcall(function() mod[k] = nop end)
                end
            end
        end
    end
    local cc = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientCircleFlowSubsystem")
    if cc then
        cc.ReportCircleFlow = nop; cc.SendCircleData = nop; cc.ReportPlayerPosition = nop; cc.ReportCircleData = nop
    end
    if _G.ReportPlayerKillFlow then _G.ReportPlayerKillFlow = nop end
    if _G.ClientSecPlayerKillFlow then _G.ClientSecPlayerKillFlow = nop end
end)

pcall(function()
    local heartbeats = {"Heartbeat","SendHeartbeat","ClientHeartbeat","ServerHeartbeat"}
    for _, name in ipairs(heartbeats) do
        if _G[name] then _G[name] = nop end
        if _G.GameplayCallbacks and _G.GameplayCallbacks[name] then _G.GameplayCallbacks[name] = nop end
    end
    local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
        local hb = SubsystemMgr:Get("HeartbeatSubsystem")
        if hb then
            if hb.timer then hb:RemoveGameTimer(hb.timer) end
            hb.SendHeartbeat = nop; hb.StartHeartbeat = nop
        end
    end
end)

pcall(function()
    if _G.CoronaLab then
        _G.CoronaLab.ReportData = nop; _G.CoronaLab.SendData = nop; _G.CoronaLab.CollectData = nop; _G.CoronaLab.Telemetry = nop
    end
    local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
        local cl = SubsystemMgr:Get("CoronaLabSubsystem")
        if cl then cl.ReportData = nop; cl.SendToServer = nop; cl.CollectTelemetry = nop; cl.StopCollection = nop end
    end
    _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
    for k in pairs(_G.GlobalPlayerCoronaData) do _G.GlobalPlayerCoronaData[k] = nil end
    local mt = getmetatable(_G.GlobalPlayerCoronaData) or {}
    mt.__newindex = function() end
    setmetatable(_G.GlobalPlayerCoronaData, mt)
end)

pcall(function()
    if _G.bReportedModifierException then _G.bReportedModifierException = false end
    local mod = safe_require("GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem")
    if mod then
        mod.ReportException = nop; mod.CheckModifier = returnTrue; mod.ValidateModifier = returnTrue; mod.ReportModifierError = nop
    end
end)

pcall(function()
    local mod = safe_require("GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem")
    if mod then mod.ReportLocation = nop; mod.SendLocationData = nop; mod.VerifyLocation = returnTrue end
end)

pcall(function()
    local mod = safe_require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
    if mod then
        mod.OnShootVerifyFailed = nop; mod.SendVerifyData = nop; mod.ReportBulletHit = nop
        mod.UploadHitInfo = nop; mod.VerifyShot = returnTrue
    end
    if _G.BulletHitInfoUploadData then
        _G.BulletHitInfoUploadData.Report = nop; _G.BulletHitInfoUploadData.Send = nop; _G.BulletHitInfoUploadData.Upload = nop
    end
end)

pcall(function()
    local ClientSub = nil
    for _, p in ipairs({"GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem", "Client.Security.ClientReportPlayerSubsystem"}) do
        if package.loaded[p] then ClientSub = package.loaded[p]; break end
        local ok, mod = pcall(require, p)
        if ok and mod then ClientSub = mod; break end
    end
    if ClientSub then
        ClientSub.OnInit = nop; ClientSub._OnPlayerKilledOtherPlayer = nop
        ClientSub._RecordFatalDamager = nop; ClientSub._OnDeathReplayDataWhenFatalDamaged = nop
        ClientSub._RecordMurdererFromDeathReplayData = nop; ClientSub._RecordTeammatePlayerInfo = nop
        ClientSub._OnBattleResult = nop; ClientSub._OnShowQuickReportMutualExclusiveUI = nop
        ClientSub.GetFatalDamagerMap = returnEmptyTable
        ClientSub.GetCachedTeammateName2InfoMap = returnEmptyTable
        ClientSub.GetTeammateName2InfoMapDuringBattle = returnEmptyTable
        ClientSub.GetCurrentNotInTeamHistoricalTeammateMap = returnEmptyTable
        ClientSub.GetInTeamIndexFromHistoricalTeammateInfo = function() return -1 end
    end
    local DSSub = nil
    for _, p in ipairs({"GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem", "GameLua.Mod.BaseMod.Client.Security.DSReportPlayerSubsystem"}) do
        if package.loaded[p] then DSSub = package.loaded[p]; break end
        local ok, mod = pcall(require, p)
        if ok and mod then DSSub = mod; break end
    end
    if DSSub then
        DSSub.OnInit = nop; DSSub._OnNearDeathOrRescued = nop; DSSub._OnCharacterDied = nop
        DSSub._OnTeammateDamage = nop; DSSub._OnPlayerSettlementStart = nop
        DSSub._AddKnockDownerToBattleResult = nop; DSSub._AddKillerToBattleResult = nop
        DSSub._AddTeammateMurderToBattleResult = nop; DSSub._AddFatalDamagerMapToBattleResult = nop
        DSSub._AddMLKillerUIDToBattleResult = nop; DSSub._SaveHistoricalTeammateInfo = nop
        DSSub._RecordFatalDamager = nop; DSSub._RecordTeammateMurderer = nop
    end
    local RPUtils = safe_require("GameLua.Mod.BaseMod.Common.Security.ReportPlayerUtils")
    if RPUtils then
        RPUtils.RecordFatalDamager = nop; RPUtils.IsUsingHistoricalTeammateInfo = returnFalse; RPUtils.IsCharacterDeliverAI = returnFalse
    end
    local SecUtils = safe_require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
    if SecUtils then SecUtils.ExtractPlayerBasicInfo = returnEmptyTable; SecUtils.LogIf = returnFalse end
    local QuickReport = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientQuickReportMaliciousTeammate")
    if QuickReport then QuickReport.OnShowMutualExclusiveUI = nop; QuickReport.OnHideMutualExclusiveUI = nop end
end)

pcall(function()
    local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if not SubsystemMgr then return end
    local allSubs = {
        "CoronaLabSubsystem","PlayerSecurityInfoSubsystem","ClientCircleFlowSubsystem",
        "ModifierExceptionSubsystem","SimulateCharacterSubsystem","ShootVerifySubSystemClient",
        "HiggsBosonComponent","ClientReportPlayerSubsystem","DSReportPlayerSubsystem",
        "ClientHawkEyePatrolSubsystem","DSHawkEyePatrolSubsystem","ClientDataStatistcsSubsystem",
        "AFKReportorSubsystem","BehaviorScoreSubsystem","FileCheckSubsystem","MemoryCheckSubsystem",
        "SpeedCheckSubsystem","WallCheckSubsystem","AvatarExceptionSubsystem","GameReportSubsystem",
        "RescueBtnReplayTraceSubsystem","ClientSecMrpcsFlowSubsystem","MrpcsFlowSubsystem",
        "PlayerKillFlowSubsystem","CircleFlowSubsystem","SwiftHawkSubsystem","HeartbeatSubsystem",
        "AntiCheatSubsystem","IntegrityCheckSubsystem","SignatureVerifySubsystem","MD5CheckSubsystem",
        "PakVerifySubsystem"
    }
    for _, sn in ipairs(allSubs) do
        local sub = SubsystemMgr:Get(sn)
        if sub then
            for k, v in pairs(sub) do
                if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Upload") or
                    k:find("Verify") or k:find("Check") or k:find("Validate") or k:find("Scan") or
                    k:find("Detect") or k:find("Collect") or k:find("Flow") or k:find("Heartbeat")) then
                    pcall(function() sub[k] = nop end)
                end
            end
            if sub.timer then pcall(function() sub:RemoveGameTimer(sub.timer) end) end
            if sub.heartbeatTimer then pcall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
            if sub.reportTimer then pcall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
        end
    end
end)

pcall(function()
    local flags = {"ENABLE_REPORT","ENABLE_ANTI_CHEAT","ENABLE_SECURITY","ENABLE_TELEMETRY",
                   "ENABLE_ANALYTICS","ENABLE_CRASH_REPORT","ENABLE_PERFORMANCE_REPORT"}
    for _, f in ipairs(flags) do
        if _G[f] then _G[f] = false end
    end
end)

pcall(function()
    local stExtra = tryImport("STExtraBlueprintFunctionLibrary")
    if stExtra and stExtra.IsDevelopment then stExtra.IsDevelopment = returnFalse end
    if Client then Client.IsDevelopment = returnFalse; Client.IsShipping = returnFalse end
    if Server then Server.IsShipping = returnFalse end

    local ToolReport = package.loaded["client.slua.logic.report.ToolReportUtil"]
    if ToolReport then
        ToolReport.IsReleaseVersion = returnFalse; ToolReport.IsWhite = returnFalse; ToolReport.GetReportSwitch = returnFalse
    end

    if _G.TApmHelper then _G.TApmHelper.postEvent = nop end

    local PC = _G.PacketCallbacks
    if PC then
        PC.player_report_cheat = nop; PC.upload_loots_rsp = nop; PC.watch_player_exit = nop
        PC.player_login_report = nop; PC.player_logout_report = nop; PC.server_time_report = nop
    end

    local sdm = _G.ServerDataMgr
    if sdm and sdm.DeletablePlayerResultKey then
        sdm.DeletablePlayerResultKey.SuspiciousHitCount = true
        sdm.DeletablePlayerResultKey.EspTotalSimTraceCnt = true
        sdm.DeletablePlayerResultKey.EspTotalImeFocusCnt = true
        sdm.DeletablePlayerResultKey.ClientGravityAnomalyCount = true
    end

    local pcNotify = package.loaded["GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature"]
    if pcNotify then
        pcNotify.ClientRPC_SyncBanID = nop; pcNotify.ClientRPC_StrongTips = nop
        pcNotify.ClientRPC_NormalTips = nop; pcNotify.Notify = nop
        pcNotify.ClientRPC_NotifyBan = nop; pcNotify.ClientRPC_NotifyPunish = nop
        pcNotify.ClientRPC_NotifyIllegalProgram = nop
    end

    local secUtils = package.loaded["GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils"]
    if secUtils and secUtils.EStrategyTypeInReplay then
        secUtils.EStrategyTypeInReplay.EspTotalSimTraceCnt = 0
        secUtils.EStrategyTypeInReplay.EspTotalImeFocusCnt = 0
        secUtils.EStrategyTypeInReplay.ClientGravityAnomalyCount = 0
        secUtils.EStrategyTypeInReplay.FlyingErrorCnt = 0
    end

    local hia = safe_require("GameLua.Mod.BaseMod.Client.Security.ClientGlueHiaSystem")
    if hia then hia.CheckHitIntegrity = nop; hia.InitSession = nop; hia.OnBattleEnd = nop end

    local Behavior = safe_require("GameLua.Mod.Escape.Gameplay.Subsystem.BehaviorScoreSubsystem")
    if Behavior then
        Behavior.OnHandleBehaviorScore = nop; Behavior.AIPerceptionScore = nop; Behavior.ReportBehavior = nop; Behavior.CalcFinalScore = returnZero
    end

    local BanLogic = package.loaded["client.slua.logic.ban.ClientBanLogic"]
    if BanLogic then
        BanLogic.OnSyncBanInfo = nop; BanLogic.OnVoiceBanNotify = nop; BanLogic.OnRealTimeVoiceBanNotify = nop
        BanLogic.OnVoiceBanSuccess = nop; BanLogic.OnSyncMicSuspicious = nop; BanLogic.OnSyncMicPreFilter = nop
        BanLogic.OnNotifyWarningTips = nop; BanLogic.ReqBanInfo = nop
    end
    local BanUtil = package.loaded["client.common.ban_util"] or _G.ban_util
    if BanUtil then BanUtil.CheckBanStatus = returnFalse; BanUtil.GetBanTime = returnZero; BanUtil.IsBanForever = returnFalse end
    local TTBan = package.loaded["client.logic.login.logic_tt_ban"] or _G.logic_tt_ban
    if TTBan then TTBan.CheckIfCanCreateRole = nop; TTBan.GetCarrierInfo = function() return "[{\"mcc\":\"000\"}]" end end
    local GodzillaBan = package.loaded["client.network.Protocol.GodzillaBanHandler"]
    if GodzillaBan then GodzillaBan.send_godzilla_ban_req = nop; GodzillaBan.send_godzilla_unban_req = nop end
    local AntiAddiction = package.loaded["client.network.Protocol.AntiaddctionHandler"]
    if AntiAddiction then AntiAddiction.send_anti_addiction_req = nop; AntiAddiction.send_anti_addiction_notify = nop end
    local AccessRestrict = package.loaded["client.network.Protocol.AccessRestrictionHandler"]
    if AccessRestrict then
        AccessRestrict.send_access_restriction_req = nop; AccessRestrict.send_access_restriction_notify = nop
        AccessRestrict.on_player_cheat_state_notify = nop
    end
    local DeleteAccount = package.loaded["client.slua.logic.gdpr.logic_deleteaccount"]
    if DeleteAccount then DeleteAccount.ForceDeleteAccount = returnFalse; DeleteAccount.OnReceiveDeleteNotify = nop end
    local ComplianceUtil = package.loaded["client.slua.logic.gdpr.compliance_util"]
    if ComplianceUtil then ComplianceUtil.CheckCompliance = nop end

    local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
        local hawk = SubsystemMgr:Get("DSHawkEyePatrolSubsystem")
        if hawk then hawk.MarkSuspiciousPlayer = nop end
    end
    if _G.DSHawkEyePatrolSubsystem then
        _G.DSHawkEyePatrolSubsystem._OnHawkReport = nop; _G.DSHawkEyePatrolSubsystem._OnHawkImprison = nop
        _G.DSHawkEyePatrolSubsystem.CheckPunishPlayer = nop
    end
    local ClientHawk = package.loaded["GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem"]
    if ClientHawk then
        for _, fn in ipairs({"_OnHawkSync","_OnHawkReportSuccess","_StartExitGameTimer","_OnRecvInspectorBroadcastCount","SendReportTLog","ReportCheat"}) do
            if ClientHawk[fn] then ClientHawk[fn] = nop end
        end
        ClientHawk.CanInspectorBroadcast = returnFalse
    end
    local InspectClient = package.loaded["GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem"]
    if InspectClient then
        for _, fn in ipairs({"AskForInspector","ReportEnemy","KickOutOneTeam","OnReceiveInspectCmd","ClientReportData","SendReportToInspector","SendKickOutOneTeam","ClientNotifyInspectorImplementation","RecvNotifyInspector"}) do
            if InspectClient[fn] then InspectClient[fn] = nop end
        end
    end
    local InspectDS = package.loaded["GameLua.Mod.BaseMod.DS.Security.InspectionSystemReportDSLogicSubsystem"]
    if InspectDS then
        for _, fn in ipairs({"ServerKickOutOneTeamByPlayerImplementation","AddReportedCount","AddInspectionRecord","BanPlayerByInspection","BroadCastToAllInspector","ServerReportToInspectorImplementation","InitPlayerInspectionInfo"}) do
            if InspectDS[fn] then InspectDS[fn] = nop end
        end
    end

    local tlogModules = {
        "client.network.Protocol.ClientTlogHandler","client.network.Protocol.BattleReportHandler",
        "client.network.Protocol.ClientErrorReportHandler","client.network.Protocol.LobbyPingReportHandler",
        "client.slua.config.tlog.tlog_report_utils","client.slua.data.BasicData.BasicDataTLogReport",
        "client.slua.data.BasicData.BasicDataClientReport","client.slua.data.BasicData.BasicDataReport",
        "GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem","GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem",
        "GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem","GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem"
    }
    for _, path in ipairs(tlogModules) do
        local mod = package.loaded[path]
        if mod then
            for k, v in pairs(mod) do
                if type(v) == "function" and (k:find("Log") or k:find("Report") or k:find("Send") or k:find("Tlog")) then
                    pcall(function() mod[k] = nop end)
                end
            end
        end
    end

    local ClientError = package.loaded["client.network.Protocol.ClientErrorReportHandler"]
    if ClientError then ClientError.send_client_error_report = nop; ClientError.send_client_crash_report = nop; ClientError.send_client_tools_batch_report_req = nop end
    local BattleReport = package.loaded["client.network.Protocol.BattleReportHandler"]
    if BattleReport then BattleReport.send_battle_report = nop; BattleReport.send_battle_result = nop; BattleReport.send_vod_game_report_req = nop; BattleReport.send_batch_get_vod_info_req = nop; BattleReport.send_get_game_report_req = nop; BattleReport.send_batch_get_game_report_req = nop; BattleReport.send_get_game_report_by_uid_req = nop end
    local BugHandler = package.loaded["client.network.Protocol.BugHandler"]
    if BugHandler then BugHandler.send_report_bug_info = nop; BugHandler.send_report_bug_feedback = nop end
    local PingReport = package.loaded["client.network.Protocol.LobbyPingReportHandler"]
    if PingReport then PingReport.send_lobby_ping_report = nop; PingReport.send_ingame_ping_report = nop end
    local WeekReport = package.loaded["client.network.Protocol.WeekRportHandler"]
    if WeekReport then WeekReport.send_week_report = nop; WeekReport.send_week_detail = nop end
    local LogicComplaint = package.loaded["client.logic.battle.logic_complaint"]
    if LogicComplaint then LogicComplaint.SendComplaintReq = nop; LogicComplaint.Submit = nop; LogicComplaint.ReportPlayer = nop; LogicComplaint.ShowComplaint = nop; LogicComplaint.ShowHandle = nop end
    local OBResult = package.loaded["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.EscapeBattleResultShowOBResultLogic"]
    if OBResult then OBResult.OnBattleResult = nop; OBResult.OnResultProcessStart = nop end
    local NormalOBResult = package.loaded["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowOBResultLogic"]
    if NormalOBResult then NormalOBResult.OnBattleResult = nop; NormalOBResult.OnResultProcessStart = nop end
    local ShowResult = package.loaded["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowResultLogic"]
    if ShowResult then
        ShowResult.OnBattleResult = nop; ShowResult.OnResultProcessStart = nop; ShowResult.OnResultProcessContinue = nop
        ShowResult.ReceiveData = nop; ShowResult.SendEndFlow = nop; ShowResult.OnReport = nop; ShowResult.ShowResult = nop
        ShowResult.ShowResultInternal = nop; ShowResult.StopResultProcess = nop
    end

    local EmuHandler = package.loaded["client.network.Protocol.EmulatorHandler"]
    if EmuHandler then EmuHandler.send_emulator_info = nop end
    local EmuScanner = package.loaded["client.logic.login.emulator_scanner"]
    if EmuScanner then EmuScanner.StartScan = nop; EmuScanner.GetScanResult = returnFalse; EmuScanner.ReportScanResult = nop end
    local LoginVerify = package.loaded["client.network.Protocol.LoginVerifyHandler"]
    if LoginVerify then LoginVerify.send_login_verify_req = nop; LoginVerify.send_device_verify_req = nop end
    local DSMonitor = package.loaded["client.logic.data.logic_ds_monitor"]
    if DSMonitor then DSMonitor.OnRecordMsg = nop; DSMonitor.OnReportMsg = nop end
    local ClientDataStat = package.loaded["GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem"]
    if ClientDataStat then ClientDataStat.StartToCheck = nop; ClientDataStat.OnReceiveRTT = nop; ClientDataStat.OnReceiveJitter = nop; ClientDataStat.ReportAbnormal = nop; ClientDataStat.ResetData = nop end
    local VoiceReport = package.loaded["client.slua.logic.chat_voice.logic_chat_voice_report"]
    if VoiceReport then VoiceReport.ReportVoiceData = nop; VoiceReport.ReportVoiceText = nop end
    local VoiceDoctor = package.loaded["client.slua.logic.chat_voice.logic_chat_voice_doctor"]
    if VoiceDoctor then VoiceDoctor.UploadVoiceLog = nop; VoiceDoctor.UploadVoiceException = nop end
    local HomeAudit = package.loaded["client.slua.logic.home.Audit.logic_home_audit_state"]
    if HomeAudit then HomeAudit.SendAuditState = nop; HomeAudit.ReportAuditResult = nop end
    local HomeReport2 = package.loaded["client.slua.logic.home.logic_home_report"]
    if HomeReport2 then HomeReport2.ReportHomeData = nop; HomeReport2.ReportHomeVisitor = nop end
    local GemReport = package.loaded["client.logic.store.gem_report_utils"]
    if GemReport then GemReport.ReportGemData = nop; GemReport.ReportGemPurchase = nop end
    local SafeStation = package.loaded["client.slua.logic.CustomerService.LogicSafeStation"]
    if SafeStation then SafeStation.UploadVideoEvidence = nop; SafeStation.ReportPlayerBehavior = nop end
    local CustomerService = package.loaded["client.slua.logic.CustomerService.LogicCustomerService"]
    if CustomerService then CustomerService.SendComplaint = nop; CustomerService.SendFeedback = nop end
    local znq6Revive = safe_require("GameLua.Mod.TDEvent.ZNQ6th.DS.ZNQ6thDSReviveSubsystem")
    if znq6Revive then znq6Revive.HaveNewItemForRevive = nop end
    local znq7Revive = safe_require("GameLua.Mod.TDEvent.ZNQ7th.DS.ZNQ7DSReviveSubsystem")
    if znq7Revive then znq7Revive.HaveChanceRevival = nop end
    local DataLayer = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.DataLayerSubsystem")
    if DataLayer and DataLayer.OnSpectatorReplayChanged then
        local origDL = DataLayer.OnSpectatorReplayChanged
        DataLayer.OnSpectatorReplayChanged = function(dlSelf) _G.IsBeingWatched = true; origDL(dlSelf) end
    end
    local DSActive = safe_require("GameLua.Mod.PlanBT.Gameplay.Subsystem.DSActiveSubsystem")
    if DSActive then DSActive.DelayKickOutPlayer = nop; DSActive.ActiveKickNotify = nop end
    local CreativeDev = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeDevDebugSubsystem")
    if CreativeDev then CreativeDev.IsDebugPanelEnalbedCli = nop end
    local CreativeDeath = safe_require("GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeModeDeathRecordSubsystem")
    if CreativeDeath then CreativeDeath.OnPlayerKilled = nop end
    if _G.ClientReplayDataReporter then
        _G.ClientReplayDataReporter.ReportIntArrayData = nop; _G.ClientReplayDataReporter.ReportFloatArrayData = nop
    end
    local SpectateReplay = safe_require("GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem")
    if SpectateReplay then SpectateReplay.RequestGotoSpectatingImp = nop; SpectateReplay.RequestGotoSpectating = nop end
    local AIReplay = safe_require("GameLua.ExtraModule.MLAI.Client.AIReplaySubsystem")
    if AIReplay then
        AIReplay.ReportAllPlayerInfo = nop; AIReplay.ReportFrameData = nop; AIReplay.ReportPlayerInput = nop
        if AIReplay.uCompletePlayBack then AIReplay.uCompletePlayBack.AddRecordMLAIInfo = nop; AIReplay.uCompletePlayBack.StopRecording = nop end
    end
    local AITracking = safe_require("GameLua.Mod.BaseMod.GamePlay.AI.AITrackingLogSubsystem")
    if AITracking then
        AITracking.RealLogoutTimer = nop; AITracking.LogQueue = {}; AITracking.AddToLogQue = nop; AITracking.DoPrint = nop
        AITracking.OnAIPawnDied = nop; AITracking.OnAIPawnReceiveDamage = nop; AITracking.OnAIPawnEnemyChange = nop
    end
    local AFKReport = safe_require("GameLua.Mod.BaseMod.DS.Security.AFKReportorSubsystem")
    if AFKReport then
        AFKReport.HandleEnterFighting = nop; AFKReport.InitializePlayerInputInfo = nop; AFKReport.AddOneAFKInfo = nop
        AFKReport.SetPlayerAFKState = nop; AFKReport.ResetPlayerInputInfo = nop; AFKReport.PlayerHaveAction = nop
    end
    local TDMAFK = safe_require("GameLua.Mod.TDM.Gameplay.Subsystem.TDMAFKReportorSubsystem")
    if TDMAFK then TDMAFK.SendAFKTips = nop; TDMAFK.OnHandleLostConnection = nop end
    local DataMgr = package.loaded["client.slua.logic.data.data_mgr"]
    if DataMgr then DataMgr.GetWeaponSkinSoundVolumeInfoByGroup = returnZero end
    local CreditLogic = safe_require("GameLua.Mod.BaseMod.Client.ClientInGameCreditLogic")
    if CreditLogic then
        CreditLogic._SendUserReaction2ExitTeamBeforeBoardingReturnLobbyNotice = nop
        CreditLogic.ShowReturnLobbyIfFirstExitTeamBeforeBoarding = returnFalse
        CreditLogic.OnReceiveCreditScoreChange = nop
        CreditLogic._IsFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = returnFalse
        CreditLogic.SetFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = nop
    end

    local globalFuncs = {
        "ReportTLogEvent","SendTlog","SendClientStats","ReportHitFlow","ReportAvatarException",
        "SendComplaintReq","SubmitReport","ReportSuspiciousPlayer","SendPacket","OnSyncBanInfo",
        "OnVoiceBanNotify","SendSecTLog","MarkSuspiciousPlayer","ReportPlayerBehaviorData",
        "CheckCompliance","ReportIllegalProgram","UploadVoiceLog"
    }
    for _, fn in ipairs(globalFuncs) do
        if type(_G[fn]) == "function" then _G[fn] = nop end
    end
end)

-- Network blacklist hosts and file keywords
local BLACKLIST_HOSTS = {
    "tss.tencent","syzsdk","gcloud.qq","reportlog","tdos","logupload","feedback.wh","crash2",
    "privacy.qq","privacy.tencent","oth.eve","mdt.qq","act.tencentyun","analytics","report.qq",
    "anticheatexpert","crashsight","wetest","log.tav","sngd","tracer","intlsdk","igamecj",
    "cdn.club","gpubgm","graph.facebook","calendarpushsubscription","googleads","doubleclick",
    "firebaselogging","firebaseremoteconfig","fonts.googleapis","abs.twimg","dl.listdl",
    "igame.gcloudcs","bugly","beacon","helpshift","tdm","apm","safeguard","weiyun","qzone",
    "tencent-cloud","myapp","idqqimg","gtimg","qqmail","tcdn","cloudctrl","sdkostrace",
    "103.134.189.146","mbgame","csoversea","igame","pubgmobile","down.anticheatexpert.com",
    "asia.csoversea.mbgame.anticheatexpert.com","log.tav.qq","syzsdk.qq","logiservice.qcloud",
    "opensdk.tencent","exp.helpshift","loginsdkapi.zingplay","firebase","googleapis","facebook","gvoice"
}
local FILE_KEYWORDS = {
    "tlog","crash","bugly","report","beacon","wetest","analytics","telemetry","trace","dump",
    "exception","feedback","aps_log","mtp_detect","network_loss","client_error","ue4crash","tdm","gcloud"
}

local function isBlacklisted(str)
    if type(str) ~= "string" then return false end
    local low = str:lower()
    for _, kw in ipairs(BLACKLIST_HOSTS) do
        if low:find(kw, 1, true) then return true end
    end
    return false
end

pcall(function()
    if _G.HttpRequest then
        local origHttp = _G.HttpRequest
        _G.HttpRequest = function(url, ...) if isBlacklisted(url) then return nil end return origHttp(url, ...) end
    end
    if _G.FHttpModule and _G.FHttpModule.CreateRequest then
        local origFH = _G.FHttpModule.CreateRequest
        _G.FHttpModule.CreateRequest = function(...)
            local url = select(1, ...)
            if isBlacklisted(url) then return nil end
            return origFH(...)
        end
    end
    local netMods = {
        "client.slua.logic.network.logic_network","client.slua.logic.download.report.puffer_tlog",
        "client.slua.data.BasicData.BasicDataClientReport","GameLua.GameCore.Module.Network.NetworkManager",
        "client.network.Protocol.ClientTlogHandler","client.network.Protocol.BattleReportHandler",
        "client.network.Protocol.ClientErrorReportHandler"
    }
    for _, mp in ipairs(netMods) do
        local mod = package.loaded[mp]
        if mod then
            for k, v in pairs(mod) do
                if type(v) == "function" and (k:find("Http") or k:find("Request") or k:find("Send") or k:find("Upload") or k:find("Post") or k:find("Get") or k:find("Report")) then
                    local origf = v
                    mod[k] = function(...)
                        local args = {...}
                        for _, arg in ipairs(args) do if type(arg)=="string" and isBlacklisted(arg) then return nil end end
                        return pcall(origf, ...)
                    end
                end
            end
        end
    end
end)

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
    end
    return orig_io_open(path, mode)
end

if _G.UnrealEngine and _G.UnrealEngine.CrashContext then
    _G.UnrealEngine.CrashContext = nil
    _G.UnrealEngine.CrashContext = { SetCrashContext = nop, ReportCrash = nop, AddCrashData = nop }
end

-- ✅ Device info spoofing (FakeData table - ye bhi MISS tha)
local FakeData = {
    deviceID = function()
        local chars = "0123456789ABCDEF"
        local id = ""
        for i = 1, 32 do id = id .. chars:sub(math.random(1, #chars), math.random(1, #chars)) end
        return id
    end,
    ipAddress = function() return "192.168." .. math.random(1, 255) .. "." .. math.random(1, 255) end,
    macAddress = function()
        return string.format("%02X:%02X:%02X:%02X:%02X:%02X",
            math.random(0,255), math.random(0,255), math.random(0,255),
            math.random(0,255), math.random(0,255), math.random(0,255))
    end,
    kernelVersion = function() return "4.19." .. math.random(100, 200) .. "-generic" end,
}

-- ========================================================================
-- Comprehensive bypass module
-- ========================================================================
do
    local bypass = {}
    local function nop() end
    local function returnTrue() return true end
    local function returnFalse() return false end
    local function returnZero() return 0 end
    local function returnEmptyTable() return {} end
    local function returnEmptyString() return "" end
    local function safe_require(mod)
        local ok, res = pcall(require, mod)
        return ok and res or nil
    end
    local function tryImport(name)
        local ok, lib = pcall(import, name)
        return ok and lib or nil
    end

    local function blockScreenshots()
        pcall(function()
            local SS = tryImport("ScreenshotMaker") or tryImport("ScreenshotMTDer")
            if SS then
                SS.MakePicture = function() return "" end
                SS.ReMakePicture = function() return "" end
                SS.HasCaptured = returnTrue
            end
        end)
    end

    local function blockGameplayCallbacks()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        local GC = _G.GameplayCallbacks
        if GC._WHABlocked then return end

        local reportFuncs = {
            "ReportAttackFlow","ReportSecAttackFlow","ReportHurtFlow","ReportFireArms",
            "ReportVerifyInfoFlow","ReportMrpcsFlow","ReportPlayerBehavior","ReportTeammatHurt",
            "ReportPlayerMoveRoute","ReportPlayerPosition","ReportAimFlow","ReportHitFlow",
            "ReportWallHack","ReportAimbot","ReportSpeedHack","ReportMagicBullet",
            "ReportAbnormalMaterial","ReportDepthTestChange","ReportMemoryException",
            "ReportMaterialScan","ReportShaderOverride","ReportCircleFlow",
            "OnPlayerRPCValidateFailed","OnPlayerActorChannelError",
            "OnPlayerSpectateException","OnShutdownAfterError"
        }
        for _, fn in ipairs(reportFuncs) do GC[fn] = nop end

        local oldStateChanged = GC.OnDSPlayerStateChanged
        GC.OnDSPlayerStateChanged = function(UID, state, ...)
            if state and type(state) == "string" then
                local s = state:lower()
                if s:find("cheat") or s:find("ban") or s:find("integrity") then return end
            end
            if oldStateChanged then return oldStateChanged(UID, state, ...) end
        end

        GC._WHABlocked = true
    end

    local function spoofTssSdk()
        pcall(function() local t = _G.TssSdk if t then t.GetFileMD5, t.VerifyFileSignature, t.CheckIntegrity, t.ScanMemory, t.IsEmulator, t.OnRecvData = function() return "" end, returnTrue, returnTrue, function() return true, {} end, returnFalse, nop end end)
    end

    local function disableDetectionSubsystems()
        local sm = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not sm then return end

        local targetSubs = {
            "ClientWallhackDetectionSubsystem", "ClientESPDetectionSubsystem",
            "ClientAimTrackingSubsystem", "ShootVerifySubSystemClient",
            "ClientRenderCheckSubsystem", "ClientMemoryGuardSubsystem",
            "ClientKernelCheckSubsystem", "ClientHawkEyePatrolSubsystem",
            "ClientAntiCheatSubsystem", "IntegrityCheckSubsystem",
            "FileCheckSubsystem", "AvatarExceptionSubsystem"
        }
        for _, sn in ipairs(targetSubs) do
            local sub = sm:Get(sn)
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" then
                        if k:find("Report") or k:find("Send") or k:find("Verify") or
                           k:find("Check") or k:find("Detect") or k:find("Scan") then
                            sub[k] = nop
                        end
                    end
                end
                if sn == "ClientWallhackDetectionSubsystem" then
                    sub.IsVisionNormal = returnTrue
                    sub.GetVisibilityRate = function() return math.random(60, 85) end
                elseif sn == "ClientESPDetectionSubsystem" then
                    sub.HasESP = returnFalse
                    sub.CheckOverlay = function() return "clean" end
                elseif sn == "ClientAimTrackingSubsystem" then
                    sub.GetAimData = function()
                        return { accuracy = math.random(45,65), headshotRate = math.random(15,35) }
                    end
                    sub.IsAimNormal = returnTrue
                elseif sn == "ClientMemoryGuardSubsystem" then
                    sub.IsMemoryClean = function() return true, {code=0} end
                    sub.ScanResult = function() return "clean" end
                elseif sn == "ShootVerifySubSystemClient" then
                    sub.OnShootVerifyFailed = nop; sub.VerifyShot = returnTrue
                end
            end
        end
    end

    local function spoofBehavior()
        pcall(function()
            local sm = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
            if not sm then return end
            
            local hooks = {
                ClientAimTrackingSubsystem = {
                    GetAimData = function() return { accuracy = math.random(48,58), headshotRate = math.random(18,28) } end,
                    IsAimNormal = returnTrue
                },
                ClientHawkEyePatrolSubsystem = {
                    GetPatrolData = returnEmptyTable, IsBeingWatched = returnFalse, GetSpectatorCount = returnZero
                },
                ClientRenderCheckSubsystem = {
                    IsRenderClean = returnTrue, GetRenderState = function() return "normal" end
                },
                ClientESPDetectionSubsystem = {
                    HasESP = returnFalse, CheckOverlay = function() return "clean" end
                },
                ClientWallhackDetectionSubsystem = {
                    IsVisionNormal = returnTrue, GetVisibilityRate = function() return math.random(70,80) end
                }
            }
            
            for mod, methods in pairs(hooks) do
                local m = sm:Get(mod)
                if m then for k, v in pairs(methods) do m[k] = v end end
            end
        end)
    end

    local function disableHiggsBoson()
        pcall(function()
            local hbc = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
            if hbc then
                hbc.bMHActive = false
                hbc.bCallPreReplication = false
                if hbc.ControlMHActive then hbc.ControlMHActive = nop end
                if hbc.StartAvatarCheck then hbc.StartAvatarCheck = nop end
                if hbc.BlackList then for k in pairs(hbc.BlackList) do hbc.BlackList[k] = nil end end
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
                if sub then sub.IsMemoryClean, sub.ScanResult = function() return true, {code=0} end, function() return "clean" end end
                sub = sm:Get("ClientKernelCheckSubsystem")
                if sub then sub.IsKernelClean, sub.GetKernelVersion, sub.IsBootloaderLocked = returnTrue, function() return "4.19.150-generic" end, returnTrue end
            end
            if _G.TssSdk then _G.TssSdk.CheckKernel, _G.TssSdk.VerifyBoot = function() return true, {status="verified", tampered=false} end, function() return true, {locked=true, verified=true} end end
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

-- ================================================================
-- BRPlayerCharacterBase class
-- ================================================================
local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {}
}

BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }
BRPlayerCharacterBase.ClientRPC.ClientRPC_TriggerHighlightMoment = { Reliable = true, Params = { UEnums.EPropertyClass.UInt32, UEnums.EPropertyClass.UInt32 } }

function BRPlayerCharacterBase:ctor()
    self.bHasShownDevNotice = false
end

function BRPlayerCharacterBase:_PostConstruct()
    BRPlayerCharacterBase.__super._PostConstruct(self)
    self:InitAddSpecialMoveInfo()
    self.bCanNearDeathGiveup = true
    self:StartAdvancedSystems()
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
        self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", { AttrName = { "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
    end
    if Client then
        GameplayData.AddCharacter(self.Object)
    else
        self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1] = "FinishedState" }, self.HandleFinishedState, self)
    end
    EventSystem:postEvent(EVENTTYPE_SINGLETRAINING, EVENTID_CHARACTER_BEGINPLAY, self.Object)
end

function BRPlayerCharacterBase:ReceiveEndPlay(endPlayReason)
    BRPlayerCharacterBase.__super.ReceiveEndPlay(self, endPlayReason)
    if Client and GameplayData.RemoveCharacter then GameplayData.RemoveCharacter(self.Object) end
end

-- ✅ StartAdvancedSystems - Only bypass activation
function BRPlayerCharacterBase:StartAdvancedSystems()
    if not Client then return end
    
    local localPlayer = GameplayData.GetPlayerCharacter()
    if slua.isValid(localPlayer) and self.Object == localPlayer then
        if not self._bypassActive then
            self._bypassActive = true
            pcall(function()
                if _G.WHABypass and _G.WHABypass.Init then
                    _G.WHABypass.Init()
                    _G._WHA_BYPASS_ACTIVE = true
                end
            end)
        end

        if not self._bypassTimerSet then
            self._bypassTimerSet = true
            self:AddGameTimer(10.0, true, function()
                pcall(function()
                    if _G.WHABypass and _G.WHABypass.Init then
                        _G.WHABypass.Init()
                        _G._WHA_BYPASS_ACTIVE = true
                    end
                end)
            end)
        end
    end
end

_G.WHABypass = _G.WHABypass or {}
if not _G.WHABypass.Init then
    _G.WHABypass.Init = function()
        _G._WHA_BYPASS_ACTIVE = true
    end
end

function _G.InitializeAllSystems()
    _G._WHA_BYPASS_ACTIVE = true
    local gameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"] or require("GameLua.GameCore.Data.GameplayData")
    if gameplayData then
        pcall(function()
            local pc = gameplayData.GetPlayerCharacter and gameplayData.GetPlayerCharacter()
            if slua.isValid(pc) then pc.StartAdvancedSystems = BRPlayerCharacterBase.StartAdvancedSystems end
        end)
    end
end
_G.InitializeAllSystems()
local function SafeAddMark(id, pos, z, str, size, actor)
    local mark = nil
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.ClientAddMapMark then
            mark = InGameMarkTools.ClientAddMapMark(id, pos, z, str, size, actor)
            if mark then _G.LexusState.TrackedMarks[mark] = true end
        end
    end)
    return mark
end

local function SafeRemoveMark(mark)
    if not mark then return end
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.HideMapMark then
            InGameMarkTools.HideMapMark(mark)
        end
        if InGameMarkTools and InGameMarkTools.RemoveMapMark then
            InGameMarkTools.RemoveMapMark(mark)
        end
    end)
    _G.LexusState.TrackedMarks[mark] = nil
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
      if _G.__AegisStartScheduled == true then return end
      _G.__AegisStartScheduled = true
      self:AddGameTimer(1.0, false, function()
        pcall(function()
          if _G.__AegisStartAfterLicense then
            _G.__AegisStartAfterLicense()
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
  Weapons = false,
  SpeedHack = false,
  SpeedPercent = 150,
  SpeedRandomize = true,
  SpeedRandomRange = 0.15,
  SpeedServerSync = true,
  SpeedSyncInterval = 0.25,
  SpeedSyncMethod = "Attribute"
}

-- ============================================================================
-- EXPIRY SYSTEM (ported from Skins.lua)
-- ============================================================================
local limitTime = os.time({ year = 2026, month = 11, day = 25, hour = 23, min = 59, sec = 0 })
local currentTime = os.time(os.date("!*t"))
local isExpired = false

pcall(function()
    local fileName = ".sys_time_cache"
    local paths = {
        -- [ANDROID] SaveGames
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        -- [ANDROID] Gamelet/logs (hidden deep)
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        -- [IOS / FALLBACK]
        "Documents/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "../../ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "../../ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName
    }

    if os and os.getenv then
        local homeDir = os.getenv("HOME")
        if homeDir and homeDir ~= "" then
            table.insert(paths, 1, homeDir .. "/Documents/ShadowTrackerExtra/Saved/SaveGames/" .. fileName)
            table.insert(paths, 2, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName)
        end
    end

    -- LAYER 1: real server time (anti device-clock rollback)
    local tm = package.loaded["client.logic.common.TimeManager"]
    if not tm then
        local s, r = pcall(require, "client.logic.common.TimeManager")
        if s and r then tm = r end
    end
    if tm and type(tm.GetServerTime) == "function" then
        local serverTime = tm.GetServerTime()
        if serverTime and serverTime > 1700000000 then
            currentTime = serverTime
        end
    end

    -- LAYER 2: read every hidden cache file, keep the highest timestamp
    local lastSeenTime = 0
    for _, path in ipairs(paths) do
        local file = io.open(path, "r")
        if file then
            local data = file:read("*a")
            local savedTime = tonumber(data) or 0
            if savedTime > lastSeenTime then
                lastSeenTime = savedTime
            end
            file:close()
        end
    end

    if currentTime < lastSeenTime then
        currentTime = lastSeenTime
    else
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(tostring(currentTime))
                file:close()
            end
        end
    end
end)

isExpired = (currentTime > limitTime)
A.isExpired = isExpired
A.limitTime = limitTime

local function ExpiredTick()
    if not _G.LexusNotifiedPopup then
        pcall(function()
            local Msg = require("client.slua.logic.common.logic_common_msg_box")
            if Msg and Msg.Show then
                Msg.Show(1,
                    "المود انتهت مدته",
                    "نسخة المود بتاعتك خلصت!\nمن فضلك راسل الأدمن عشان التجديد.\nراسل تيليجرام @SOKU القناة @SOKU عشان تشتري. لو أي حد باعك ده غيري، أهنئك إنت اتخدعت",
                    function()
                        local Web = require("client.slua.logic.url.logic_webview_sdk")
                        if Web and Web.OpenURL then Web:OpenURL("https://t.me/MOHSINXFILES") end
                    end,
                    function() end,
                    "راسل صاحب المود", "إغلاق")
                _G.LexusNotifiedPopup = true
            end
        end)

        if not _G.LexusNotifiedPopup then
            local okTicker, ticker = pcall(require, "common.time_ticker")
            if okTicker and ticker and ticker.AddTimerOnce then
                ticker.AddTimerOnce(2.0, ExpiredTick)
            end
        end
    end
end
-- ============================================================================
-- END EXPIRY SYSTEM
-- ============================================================================

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
      "ModifierExceptionSubsystem", "MemoryCheckSubsystem",
      "SpeedCheckSubsystem"
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
        ["report_net_saturate"]=1, ["report_unrealnet_exception"]=1,
        ["report_player_position"]=1, ["ReportPlayerPosition"]=1,
        ["ReportPlayerMoveRoute"]=1, ["report_player_move_route"]=1
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
  print("[MOHSIN] ALL PROTECTION + BAN BYPASS 4.6 ACTIVE")
end

-- ============================================================================
-- SPEED HACK SYSTEM — ROBUST v2 (beat-driven, multi-fallback, bypass safe)
-- ============================================================================
_G.SpeedHackState = _G.SpeedHackState or {
    active = false,
    timer = nil,
    modifyId = nil,
    currentChar = nil,
    syncTimer = 0,
    currentSpeed = 150,
    lastBeatTick = 0,
    applyMethod = nil,
    diagMsg = "",
}
local SH = _G.SpeedHackState

local function SH_GetChar()
    local char = nil
    pcall(function()
        local GD = require("GameLua.GameCore.Data.GameplayData")
        if GD and GD.GetPlayerCharacter then char = GD.GetPlayerCharacter() end
    end)
    if not Around(char) then
        pcall(function()
            local hud = slua_GameFrontendHUD
            if hud then
                local pc = hud:GetPlayerController()
                if Around(pc) then char = pc:GetPlayerCharacterSafety() end
            end
        end)
    end
    return Around(char) and char or nil
end

local function SH_Remove(char)
    if not char or not Around(char) then return end
    if SH.modifyId then
        pcall(function()
            if char.AttrModifyComp then
                if char.AttrModifyComp.RemoveModifyItemFromCache then
                    char.AttrModifyComp:RemoveModifyItemFromCache(SH.modifyId)
                elseif char.AttrModifyComp.RemoveModifyItem then
                    char.AttrModifyComp:RemoveModifyItem(SH.modifyId)
                elseif char.AttrModifyComp.RemoveModify then
                    char.AttrModifyComp:RemoveModify(SH.modifyId)
                end
            end
        end)
        SH.modifyId = nil
    end
    pcall(function()
        local cm = char.STCharacterMovement or char.CharacterMovement
        if Around(cm) then
            if SH.savedWalkSpeed and cm.MaxWalkSpeed then cm.MaxWalkSpeed = SH.savedWalkSpeed end
            if SH.savedAccel and cm.MaxAcceleration then cm.MaxAcceleration = SH.savedAccel end
            if SH.savedCustSpeed and cm.MaxCustomMovementSpeed then cm.MaxCustomMovementSpeed = SH.savedCustSpeed end
        end
    end)
    SH.savedWalkSpeed = nil
    SH.savedAccel = nil
    SH.savedCustSpeed = nil
    SH.applyMethod = nil
end

local function SH_TryAttrModify(char, rate)
    local ok = false
    pcall(function()
        if not char.AttrModifyComp then return end
        local comp = char.AttrModifyComp
        if comp.AddModifyItemAndCache then
            SH.modifyId = comp:AddModifyItemAndCache("SpeedRate", 0, rate, true, char, false)
            ok = SH.modifyId ~= nil
        elseif comp.AddModifyItem then
            SH.modifyId = comp:AddModifyItem("SpeedRate", 0, rate, true, char, false)
            ok = SH.modifyId ~= nil
        elseif comp.AddModify then
            SH.modifyId = comp:AddModify("SpeedRate", rate, true, char)
            ok = SH.modifyId ~= nil
        end
    end)
    if ok then SH.applyMethod = "AttrModify" end
    return ok
end

local function SH_TryDirectMove(char, pct)
    local ok = false
    pcall(function()
        local cm = char.STCharacterMovement or char.CharacterMovement
        if not Around(cm) then return end
        if SH.savedWalkSpeed == nil and cm.MaxWalkSpeed then
            SH.savedWalkSpeed = cm.MaxWalkSpeed
        end
        if SH.savedAccel == nil and cm.MaxAcceleration then
            SH.savedAccel = cm.MaxAcceleration
        end
        if SH.savedCustSpeed == nil and cm.MaxCustomMovementSpeed then
            SH.savedCustSpeed = cm.MaxCustomMovementSpeed
        end
        local base = SH.savedWalkSpeed or 480
        local target = base * (pct / 100.0)
        if target < 500 then target = 500 end
        if target > 3500 then target = 3500 end
        if cm.MaxWalkSpeed then cm.MaxWalkSpeed = target end
        if cm.MaxCustomMovementSpeed then cm.MaxCustomMovementSpeed = target end
        if cm.MaxAcceleration and SH.savedAccel then
            cm.MaxAcceleration = math.max(SH.savedAccel, target * 4)
        end
        ok = true
    end)
    if ok then SH.applyMethod = "DirectMove" end
    return ok
end

local function SH_DoServerSync(char)
    if not A.Config.SpeedServerSync then return end
    if not Around(char) then return end
    pcall(function()
        local cm = char.STCharacterMovement or char.CharacterMovement
        if not Around(cm) then return end
        local pos = char:K2_GetActorLocation()
        if not pos then return end
        local pc = char:GetPlayerControllerSafety()
        if not Around(pc) then return end
        if A.Config.SpeedSyncMethod == "ServerMove" and cm.ServerMove then
            local vel = cm.Velocity or char:GetVelocity()
            if vel then
                local spoofPos = FVector(
                    pos.X + math.random(-3, 3),
                    pos.Y + math.random(-3, 3),
                    pos.Z - 20 + math.random(-5, 5))
                pcall(function() cm:ServerMove(os.clock(), FVector(0,0,0), spoofPos, vel) end)
            end
        else
            if char.ForceNetUpdate then char:ForceNetUpdate() end
        end
    end)
end

function _SH_RobustUpdate()
    if not A.Config.SpeedHack then
        if SH.applyMethod and SH.currentChar then
            SH_Remove(SH.currentChar)
            SH.currentChar = nil
        end
        return
    end
    local now = os.clock()
    if now - SH.lastBeatTick < 0.2 then return end
    SH.lastBeatTick = now
    local char = SH_GetChar()
    if not char then
        SH.diagMsg = "no char"
        return
    end
    if SH.currentChar ~= char then
        if SH.currentChar then SH_Remove(SH.currentChar) end
        SH.currentChar = char
    end
    local base = A.Config.SpeedPercent or 150
    local finalPct = base
    if A.Config.SpeedRandomize then
        local rng = A.Config.SpeedRandomRange or 0.15
        local variation = 1.0 + (math.random() * 2 * rng) - rng
        finalPct = base * variation
        if finalPct < 100 then finalPct = 100 end
        if finalPct > 500 then finalPct = 500 end
    end
    SH.currentSpeed = finalPct
    local rate = (finalPct / 100.0) - 1.0
    local attrOK = SH_TryAttrModify(char, rate)
    if not attrOK then
        SH_TryDirectMove(char, finalPct)
    end
    if SH.applyMethod == "AttrModify" then
        SH_TryDirectMove(char, finalPct)
        SH.applyMethod = "AttrModify+DirectMove"
    end
    if A.Config.SpeedServerSync then
        SH.syncTimer = (SH.syncTimer or 0) + 0.2
        if SH.syncTimer >= (A.Config.SpeedSyncInterval or 0.25) then
            SH.syncTimer = 0
            SH_DoServerSync(char)
        end
    end
    SH.diagMsg = string.format("%.0f%% via %s", finalPct, SH.applyMethod or "?")
end

function SetMemorySpeedHack(enabled)
    A.Config.SpeedHack = enabled == true
    if not enabled then
        if SH.currentChar then SH_Remove(SH.currentChar) end
        SH.currentChar = nil
        SH.applyMethod = nil
        OnScreen("[SpeedHack] OFF")
    else
        SH.lastBeatTick = 0
        SH.syncTimer = 0
        OnScreen("[SpeedHack] ON - will apply on next beat (2s)")
    end
end

function SetMemorySpeedPercent(val)
    val = tonumber(val) or 150
    if val < 100 then val = 100 end
    if val > 500 then val = 500 end
    A.Config.SpeedPercent = val
    if A.Config.SpeedHack then
        SH.lastBeatTick = 0
        OnScreen("[SpeedHack] " .. val .. "%")
    end
end

function SpeedHackBeatTick()
    pcall(_SH_RobustUpdate)
end
-- ============================================================================

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
      [999000] = "MOHSIN MENU",
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
        SetFunc = function(c, v) A.Config.Weapons = v return true end },
      { Key = "ModMenu_SpeedHack_Ex", UI = alias.TitleSwitcher, Text = "🚀 Speed Boost",
        ExpandIndex = 0,
        GetFunc = function() return A.Config.SpeedHack end,
        SetFunc = function(c, v) SetMemorySpeedHack(v) return true end },
      { Key = "ModMenu_SpeedPercent", UI = alias.Slider, Text = "   Speed % (100-500)",
        ExpandHandle = "ModMenu_SpeedHack_Ex",
        MinValue = 0, MaxValue = 100, min = 0, max = 100,
        GetFunc = function() return ((A.Config.SpeedPercent or 150) - 100) / 4 end,
        SetFunc = function(c, v) SetMemorySpeedPercent(100 + (v * 4)) return true end },
      { Key = "ModMenu_SpeedRandomize", UI = alias.Switcher, Text = "   Randomize Speed (Anti-Ban)",
        ExpandHandle = "ModMenu_SpeedHack_Ex",
        GetFunc = function() return A.Config.SpeedRandomize end,
        SetFunc = function(c, v) A.Config.SpeedRandomize = v return true end },
      { Key = "ModMenu_SpeedSync", UI = alias.Switcher, Text = "   Server Sync (Anti-Detect)",
        ExpandHandle = "ModMenu_SpeedHack_Ex",
        GetFunc = function() return A.Config.SpeedServerSync end,
        SetFunc = function(c, v) A.Config.SpeedServerSync = v return true end }
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
    OnScreen("Mod Menu Added!\nOpen Settings (Gear icon) -> SOKU  MENU.")
    A.Up.Announced = true
  end)
end

local MOKING = {}

function MOKING.ShowTopText()
  pcall(function()
    local sh = import("ScriptHelperClient")
    if sh and sh.AddOnScreenDebugMessage then
      sh.AddOnScreenDebugMessage("OWNER +92 [ 03121808681 ]", -1, 1.0, {R = 0, G = 1, B = 1, A = 1}, {X = 0.85, Y = 0.85})
    end
  end)
end

function MOKING.OnMatchEnter()
  if MOKING._matchEntered then return end
  MOKING._matchEntered = true
  MOKING.ShowTopText()
end

A.Up.Pulse = (A.Up.Pulse or 0) + 1
local myPulse = A.Up.Pulse
A.Up.TrackedMarks = A.Up.TrackedMarks or {}
A.Up.Targets = A.Up.Targets or {}

local function Beat()
  if myPulse ~= A.Up.Pulse then return end

  -- === EXPIRY GUARD ===
  if isExpired then
    if not _G.LexusNotifiedExpire then
      _G.LexusNotifiedExpire = true
      pcall(function()
        local sh = import("ScriptHelperClient")
        if sh and sh.AddOnScreenDebugMessage then
          sh.AddOnScreenDebugMessage(
            "SOKU TELEGRAM @SOKU عشان التجديد",
            -1, 5.0, {R=1, G=0, B=0, A=1}, {X=1.2, Y=1.2})
        end
      end)
      ExpiredTick()
    end
    -- Cleanup active SpeedHack effect since mod is dead
    pcall(function()
      if _G.SpeedHackState and _G.SpeedHackState.currentChar then
        local cm = _G.SpeedHackState.currentChar.STCharacterMovement
                  or _G.SpeedHackState.currentChar.CharacterMovement
        if cm then
          if _G.SpeedHackState.savedWalkSpeed and cm.MaxWalkSpeed then
            cm.MaxWalkSpeed = _G.SpeedHackState.savedWalkSpeed
          end
          if _G.SpeedHackState.savedAccel and cm.MaxAcceleration then
            cm.MaxAcceleration = _G.SpeedHackState.savedAccel
          end
        end
        _G.SpeedHackState.currentChar = nil
      end
    end)
    return
  end
  -- === END EXPIRY GUARD ===

  pcall(function()
    if not A.Up.NativeReady and not A.Up.NativePriming then
      A.Up.NativePriming = true
      Esp.PrimeNativeMarks()
    end
    if A.Config.HighFps and not A.Up.GfxReady then Gfx.Unlock() end
  end)

  -- SpeedHack — beat-driven robust apply
  pcall(SpeedHackBeatTick)

  -- SpeedHack live diagnostic on screen (once per second, only when ON)
  if A.Config.SpeedHack and SH.diagMsg ~= "" and SH.lastBeatTick > 0 then
    local now = os.clock()
    if not SH.lastDiagShow or now - SH.lastDiagShow > 1.0 then
      SH.lastDiagShow = now
      pcall(function()
        local sh = import("ScriptHelperClient")
        if sh and sh.AddOnScreenDebugMessage then
          sh.AddOnScreenDebugMessage("[SpeedHack] " .. SH.diagMsg, 1, 1.0,
            {R=0, G=1, B=1, A=1}, {X=1.1, Y=1.4})
        end
      end)
    end
  end

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
  pcall(function()
    local delay = math.random(150, 450) / 1000
    Later(delay, function()
      pcall(Shield.InstallAll)
    end, true)
  end)
end

pcall(function()
  Later(2.0, function()
    if isExpired then
      ExpiredTick()
      return
    end
    Pulse()
  end, true)
end)

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
