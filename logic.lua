-- =====================================================================
-- KYÔKA HUB • LINK 3 — LOGIC (3a/3c)
-- Farm + Combat
-- =====================================================================

local ok, err = pcall(function()

local Core = _G.__KyokaHub
if not Core or not Core.ready then
    warn("[Kyôka] logic.lua: core.lua nao carregou.")
    return
end

local Services = Core.Services
local Game = Core.Game
local H = Core.H
local Logger = Core.Logger
local Notify = Core.Notify
local Panels = Core.Panels
local Tabs = Core.Tabs
local Options = Core.Options
local Sound = Core.Sound
local AntiCheat = Core.AntiCheat
local addToggle = Core.addToggle

if not Tabs or not Notify or not Panels then
    warn("[Kyôka] logic.lua: ui.lua nao carregou.")
    return
end

Logger.log("Carregando logic.lua (3a) — Farm + Combat")

-- =====================================================================
-- STATE FARM
-- =====================================================================
local S = {
    antiSun = false,
    antiDrown = false,
    autoHeal = false,
    healPct = 45,
    healPotion = "Health Potion",
    autoFarm = false,
    farmMode = "MoveTo",
    farmRange = 50,
    farmPriority = "Closest",
    farmDelay = 0.3,
    killAura = false,
    killAuraRange = 15,
    autoBoss = false,
    bossRange = 100,
    attackCount = 0,
    kills = 0,
    healCount = 0,
    lastTarget = "-",
}
Core.Farm = S

-- =====================================================================
-- PATCH ANTI SUN
-- =====================================================================
pcall(function()
    if Game.MinigameSettings and Game.MinigameSettings.Get then
        local orig = Game.MinigameSettings.Get
        Game.MinigameSettings.Get = function(k, ...)
            if k == "NoSunDamage" and S.antiSun then return true end
            return orig(k, ...)
        end
    end
    if Game.SignalFunction and Game.SignalFunction.ToServer then
        local orig = Game.SignalFunction.ToServer
        Game.SignalFunction.ToServer = function(n, v, ...)
            if n == "SunDamage" and v == true and S.antiSun then
                return orig(n, false, ...)
            end
            return orig(n, v, ...)
        end
    end
end)

-- =====================================================================
-- PATCH ANTI DROWN
-- =====================================================================
pcall(function()
    if Game.MinigameSettings and Game.MinigameSettings.Get then
        local orig = Game.MinigameSettings.Get
        Game.MinigameSettings.Get = function(k, ...)
            if k == "NoDrowning" and S.antiDrown then return true end
            return orig(k, ...)
        end
    end
    if Game.SignalEvent and Game.SignalEvent.ToServer then
        local orig = Game.SignalEvent.ToServer
        Game.SignalEvent.ToServer = function(n, a, ...)
            if n == "Swim" and a == "DrownDamage" and S.antiDrown then
                return nil
            end
            return orig(n, a, ...)
        end
    end
end)

-- =====================================================================
-- AUTO HEAL LOOP
-- =====================================================================
task.spawn(function()
    local failUntil = 0
    while true do
        task.wait(0.5)
        if S.autoHeal and os.clock() > failUntil and H.alive() then
            if H.healthPct() <= S.healPct then
                if H.count(S.healPotion) > 0 then
                    local idx = H.hotbarIdx(S.healPotion)
                    if idx then
                        local before = H.count(S.healPotion)
                        H.equip(idx)
                        local _, hrp = H.char()
                        if hrp and Game.SignalEvent then
                            pcall(function()
                                Game.SignalEvent.ToServer("Tool_Mouse", "Down", hrp.Position)
                            end)
                            task.wait(2.1)
                            pcall(function()
                                Game.SignalEvent.ToServer("Tool_Mouse", "Up", hrp.Position)
                            end)
                            task.wait(0.5)
                        end
                        H.equip(0)
                        if H.count(S.healPotion) >= before then
                            failUntil = os.clock() + 5
                        else
                            S.healCount = S.healCount + 1
                        end
                    end
                end
            end
        end
    end
end)

-- =====================================================================
-- PICK TARGET
-- =====================================================================
local function pickTarget(mobs)
    if not mobs or #mobs == 0 then return nil end
    if S.farmPriority == "Lowest HP" then
        table.sort(mobs, function(a, b) return a.health < b.health end)
    elseif S.farmPriority == "Highest HP" then
        table.sort(mobs, function(a, b) return a.health > b.health end)
    else
        table.sort(mobs, function(a, b) return a.dist < b.dist end)
    end
    return mobs[1]
end

-- =====================================================================
-- AUTO FARM LOOP
-- =====================================================================
task.spawn(function()
    while true do
        task.wait(S.farmDelay)
        if S.autoFarm and H.alive() then
            local mobs = H.mobs(S.farmRange)
            local t = pickTarget(mobs)
            if t and t.rig and t.rig.Parent and t.root then
                S.lastTarget = t.rig.Name or "?"
                if t.dist > 8 then
                    if S.farmMode == "Teleport" then
                        H.safeTP(t.root.Position)
                    else
                        H.moveTo(t.root.Position)
                    end
                else
                    H.faceTarget(t.root.Position)
                    H.attack(t.root.Position)
                    S.attackCount = S.attackCount + 1
                    if t.health <= 0 then
                        S.kills = S.kills + 1
                    end
                end
            end
        end
    end
end)

-- =====================================================================
-- KILL AURA LOOP
-- =====================================================================
task.spawn(function()
    while true do
        task.wait(0.15)
        if S.killAura and H.alive() then
            local mobs = H.mobs(S.killAuraRange)
            for _, m in ipairs(mobs) do
                if m.hum and m.hum.Health > 0 and m.root then
                    H.attack(m.root.Position)
                    S.attackCount = S.attackCount + 1
                end
            end
        end
    end
end)

-- =====================================================================
-- AUTO BOSS LOOP
-- =====================================================================
task.spawn(function()
    while true do
        task.wait(0.4)
        if S.autoBoss and H.alive() then
            local bosses = H.bosses(S.bossRange)
            local t = bosses[1]
            if t and t.rig and t.root then
                S.lastTarget = "[BOSS] " .. (t.rig.Name or "?")
                if t.dist > 10 then
                    if S.farmMode == "Teleport" then
                        H.safeTP(t.root.Position)
                    else
                        H.moveTo(t.root.Position)
                    end
                else
                    H.faceTarget(t.root.Position)
                    H.attack(t.root.Position)
                    S.attackCount = S.attackCount + 1
                end
            end
        end
    end
end)

-- =====================================================================
-- ANTI-CHEAT HOOK
-- =====================================================================
AntiCheat.onFail = function()
    Notify.warn("Anti-Cheat", "Teleporte detectado! Pausando 8s", 5)
    S.autoFarm = false
    S.autoBoss = false
    task.spawn(function()
        task.wait(8)
        AntiCheat.reset()
    end)
end

task.spawn(function()
    while true do
        task.wait(0.5)
        if S.autoFarm or S.killAura or S.autoBoss then
            AntiCheat.check()
        end
    end
end)

-- =====================================================================
-- UI: FARM
-- =====================================================================
if Tabs.Farm then
    pcall(function() Tabs.Farm:AddSection("Anti Dano (Patch)") end)

    addToggle(Tabs.Farm, "AntiSun", {
        Title = "Anti Sun Damage",
        Description = "Demonio nao toma dano de sol",
        Default = false,
        Callback = function(v) S.antiSun = v end,
    })

    addToggle(Tabs.Farm, "AntiDrown", {
        Title = "Anti Drown",
        Description = "Nao afoga na agua",
        Default = false,
        Callback = function(v) S.antiDrown = v end,
    })

    pcall(function() Tabs.Farm:AddSection("Auto Heal") end)

    addToggle(Tabs.Farm, "AutoHeal", {
        Title = "Auto Heal",
        Description = "Bebe pocao quando vida baixa",
        Default = false,
        Callback = function(v) S.autoHeal = v end,
    })

    pcall(function()
        Tabs.Farm:AddSlider("HealPct", {
            Title = "Curar abaixo de",
            Default = 45, Min = 10, Max = 95, Rounding = 0, Suffix = "%",
            Callback = function(v) S.healPct = v end,
        })
    end)

    pcall(function()
        Tabs.Farm:AddInput("HealPotion", {
            Title = "Pocao",
            Default = "Health Potion",
            Placeholder = "Health Potion",
            Callback = function(v) S.healPotion = v end,
        })
    end)

    pcall(function() Tabs.Farm:AddSection("Auto Farm") end)

    addToggle(Tabs.Farm, "AutoFarm", {
        Title = "Auto Farm (Kill Mobs)",
        Description = "Ataca o mob mais proximo",
        Default = false,
        Callback = function(v) S.autoFarm = v end,
    })

    pcall(function()
        Tabs.Farm:AddDropdown("FarmMode", {
            Title = "Modo de Movimento",
            Values = { "MoveTo", "Teleport" },
            Default = "MoveTo", Multi = false,
            Callback = function(v) S.farmMode = v end,
        })
    end)

    pcall(function()
        Tabs.Farm:AddDropdown("FarmPriority", {
            Title = "Prioridade",
            Values = { "Closest", "Lowest HP", "Highest HP" },
            Default = "Closest", Multi = false,
            Callback = function(v) S.farmPriority = v end,
        })
    end)

    pcall(function()
        Tabs.Farm:AddSlider("FarmRange", {
            Title = "Alcance",
            Default = 50, Min = 10, Max = 200, Rounding = 0, Suffix = " studs",
            Callback = function(v) S.farmRange = v end,
        })
    end)

    pcall(function()
        Tabs.Farm:AddSlider("FarmDelay", {
            Title = "Delay entre ataques",
            Default = 0.3, Min = 0.1, Max = 2, Rounding = 2, Suffix = "s",
            Callback = function(v) S.farmDelay = v end,
        })
    end)
end

local farmStatus = Panels.create(Tabs.Farm, "Auto Farm: Off", "Attacks: 0 | Kills: 0")

-- =====================================================================
-- UI: COMBAT
-- =====================================================================
if Tabs.Combat then
    pcall(function() Tabs.Combat:AddSection("Kill Aura") end)

    addToggle(Tabs.Combat, "KillAura", {
        Title = "Kill Aura",
        Description = "Ataca TODOS os mobs no alcance",
        Default = false,
        Callback = function(v) S.killAura = v end,
    })

    pcall(function()
        Tabs.Combat:AddSlider("KillAuraRange", {
            Title = "Alcance",
            Default = 15, Min = 5, Max = 50, Rounding = 0, Suffix = " studs",
            Callback = function(v) S.killAuraRange = v end,
        })
    end)

    pcall(function() Tabs.Combat:AddSection("Auto Boss") end)

    addToggle(Tabs.Combat, "AutoBoss", {
        Title = "Auto Boss",
        Description = "Ataca bosses automaticamente",
        Default = false,
        Callback = function(v) S.autoBoss = v end,
    })

    pcall(function()
        Tabs.Combat:AddSlider("BossRange", {
            Title = "Alcance de Boss",
            Default = 100, Min = 30, Max = 500, Rounding = 0, Suffix = " studs",
            Callback = function(v) S.bossRange = v end,
        })
    end)
end

local combatStatus = Panels.create(Tabs.Combat, "Combat: Off", "Attacks: 0")

-- =====================================================================
-- STATUS LOOP
-- =====================================================================
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            if farmStatus then
                farmStatus:update(
                    "Auto Farm: " .. (S.autoFarm and "ON" or "Off"),
                    string.format("Attacks: %d | Kills: %d | Target: %s",
                        S.attackCount, S.kills, S.lastTarget)
                )
            end
            if combatStatus then
                combatStatus:update(
                    "Combat: " .. ((S.killAura or S.autoBoss) and "ON" or "Off"),
                    string.format("KillAura: %s | Boss: %s | Attacks: %d",
                        S.killAura and "OK" or "X",
                        S.autoBoss and "OK" or "X",
                        S.attackCount)
                )
            end
        end)
    end
end)

Logger.log("logic.lua (3a) carregado")

end)

if not ok then
    warn("[Kyôka] ERRO em logic.lua (3a): " .. tostring(err))
else
    print("[Kyôka] ✅ logic.lua (3a) pronto")
end-- =====================================================================
-- KYÔKA HUB • LINK 3 — LOGIC (3b/3c)
-- Skills + Fishing
-- =====================================================================

local ok_b, err_b = pcall(function()

local Core = _G.__KyokaHub
if not Core or not Core.ready then
    warn("[Kyôka] logic.lua (3b): core nao carregou.")
    return
end

local Services = Core.Services
local Game = Core.Game
local H = Core.H
local Logger = Core.Logger
local Notify = Core.Notify
local Panels = Core.Panels
local Tabs = Core.Tabs
local Options = Core.Options
local Sound = Core.Sound
local addToggle = Core.addToggle

if not Tabs or not Notify or not Panels then
    warn("[Kyôka] logic.lua (3b): ui nao carregou.")
    return
end

local LP = Services.LocalPlayer
local CS = Services.CollectionService

Logger.log("Carregando logic.lua (3b) — Skills + Fishing")

-- =====================================================================
-- STATE SKILLS
-- =====================================================================
local SK = {
    autoSkill = false,
    skillHold = 0.4,
    skillMode = "While fighting",
    autoSkillTree = false,
    casts = 0,
    lastSkill = "-",
}
Core.Skills = SK

-- =====================================================================
-- AIM HOOK
-- =====================================================================
local aimAt = nil

pcall(function()
    local PH = Game.Platform_Handler
    if PH and PH.mousepos then
        local orig = PH.mousepos
        PH.mousepos = function(...)
            if aimAt then
                local ok_a, pos = pcall(aimAt)
                if ok_a and typeof(pos) == "Vector3" then return pos end
            end
            return orig(...)
        end
        Logger.log("Aim hook instalado")
    end
end)

-- =====================================================================
-- CAST SKILL
-- =====================================================================
local function castSkill(skill, rig)
    local C = Game.Skill_Controller
    if not C or not C.Attempt_Hold then return false end

    aimAt = function()
        if rig and rig.Parent then
            local r = rig:FindFirstChild("HumanoidRootPart")
            if r then return r.Position end
        end
        local _, hrp = H.char()
        return hrp and (hrp.Position + hrp.CFrame.LookVector * 20) or nil
    end

    local ok_c, pressed = pcall(C.Attempt_Hold, skill.name, nil)
    if not ok_c or pressed ~= true then
        aimAt = nil
        return false
    end

    C.CurrentMax = skill.maxHold
    C.HeldSkill = skill.name

    local char = LP.Character
    local shc = char and (char:FindFirstChild("SHC") or char:FindFirstChild("SHCS"))
    local hold = math.min(SK.skillHold, skill.maxHold or 0)
    local dl = os.clock() + hold

    while shc and shc.Value == skill.name and os.clock() < dl do
        task.wait(0.05)
    end

    if shc and shc.Value == skill.name then
        C.UnHoldBoolean = true
        local rel = os.clock() + 1
        while shc.Value == skill.name and os.clock() < rel do
            task.wait(0.05)
        end
    end

    aimAt = nil
    SK.casts = SK.casts + 1
    SK.lastSkill = skill.name
    return true
end

-- =====================================================================
-- AUTO SKILL LOOP
-- =====================================================================
task.spawn(function()
    while true do
        task.wait(0.25)
        if SK.autoSkill and H.alive() and not H.isCasting() then
            local mobs = H.mobs(40)
            local rig = mobs[1] and mobs[1].rig

            if not (SK.skillMode == "While fighting" and not rig) then
                for _, s in ipairs(H.skillBar()) do
                    if s.name ~= "Blocking" then
                        if castSkill(s, rig) then break end
                    end
                end
            end
        end
    end
end)

-- =====================================================================
-- AUTO SKILL TREE LOOP
-- =====================================================================
task.spawn(function()
    while true do
        task.wait(2)
        if SK.autoSkillTree and H.alive() then
            local points = H.skillPoints()
            if points > 0 and Game.SignalFunction then
                local SS = Game.SkillStats
                if SS and SS.IsSkillUnlocked then
                    local ok_u, unlocked = pcall(SS.IsSkillUnlocked, LP, "Double Jump")
                    if ok_u and not unlocked then
                        pcall(function()
                            Game.SignalFunction.ToServer("UnlockSkillTreeNode", "Double Jump")
                        end)
                    end
                end
            end
        end
    end
end)

-- =====================================================================
-- STATE FISHING
-- =====================================================================
local FI = {
    autoFish = false,
    fishCaught = 0,
    fishStatus = "Off",
    autoLoot = false,
    lootRange = 100,
    lootCollected = 0,
}
Core.Fishing = FI

-- =====================================================================
-- PORTAL EVENT (fishing bite)
-- =====================================================================
local biteToken = nil
local PortalEvent = Game.PortalEvent

if PortalEvent then
    pcall(function()
        PortalEvent.OnClientEvent:Connect(function(ch, kind, token)
            if ch == "FishingRod" and kind == "Bite" then
                biteToken = token
            end
        end)
    end)
end

-- =====================================================================
-- AUTO FISH LOOP
-- =====================================================================
task.spawn(function()
    while true do
        task.wait(0.5)
        if FI.autoFish and PortalEvent and Game.SignalEvent and H.alive() then
            local water = H.findWater(32)
            if not water then
                FI.fishStatus = "Sem agua perto"
            else
                FI.fishStatus = "Pescando..."
                biteToken = nil
                pcall(function()
                    Game.SignalEvent.ToServer("Tool_Mouse", "Up", water)
                end)

                local dl = os.clock() + 30
                while FI.autoFish and not biteToken and os.clock() < dl do
                    task.wait(0.1)
                end

                if biteToken then
                    FI.fishStatus = "Reeling..."
                    task.wait(4.7)
                    if FI.autoFish then
                        pcall(function()
                            PortalEvent:FireServer("FishingRod", biteToken, true)
                        end)
                        FI.fishCaught = FI.fishCaught + 1
                        FI.fishStatus = "Pescou! Total: " .. FI.fishCaught
                        task.wait(2)
                    end
                else
                    FI.fishStatus = "Sem bite"
                end
            end
        else
            FI.fishStatus = "Off"
        end
    end
end)

-- =====================================================================
-- AUTO LOOT
-- =====================================================================
local function isMine(drop)
    local owner = drop:GetAttribute("DropOwnerUserId")
    if typeof(owner) == "number" and owner ~= LP.UserId then
        return false
    end
    local reserved = drop:GetAttribute("DropReservedFor")
    if typeof(reserved) == "string" then
        if not string.find(reserved, "," .. LP.UserId .. ",", 1, true) then
            return false
        end
    end
    return drop:GetAttribute("DropClaimedBy") == nil
end

task.spawn(function()
    while true do
        task.wait(0.5)
        if FI.autoLoot and H.alive() then
            local _, hrp = H.char()
            if hrp then
                local drops = CS:GetTagged("LootDrop")
                for _, drop in ipairs(drops) do
                    if drop:IsA("BasePart") and drop.Parent and isMine(drop) then
                        local d = (drop.Position - hrp.Position).Magnitude
                        if d <= FI.lootRange then
                            pcall(function()
                                hrp.CFrame = CFrame.new(drop.Position + Vector3.new(0, 3, 0))
                            end)
                            FI.lootCollected = FI.lootCollected + 1
                            break
                        end
                    end
                end
            end
        end
    end
end)

-- =====================================================================
-- UI: SKILLS
-- =====================================================================
if Tabs.Skills then
    pcall(function() Tabs.Skills:AddSection("Auto Skill") end)

    addToggle(Tabs.Skills, "AutoSkill", {
        Title = "Auto Skill",
        Description = "Usa skills automaticamente no mob mais proximo",
        Default = false,
        Callback = function(v) SK.autoSkill = v end,
    })

    pcall(function()
        Tabs.Skills:AddDropdown("SkillMode", {
            Title = "Modo de Uso",
            Values = { "While fighting", "Always" },
            Default = "While fighting", Multi = false,
            Callback = function(v) SK.skillMode = v end,
        })
    end)

    pcall(function()
        Tabs.Skills:AddSlider("SkillHold", {
            Title = "Hold time (skills que carregam)",
            Default = 0.4, Min = 0, Max = 3, Rounding = 1, Suffix = "s",
            Callback = function(v) SK.skillHold = v end,
        })
    end)

    pcall(function() Tabs.Skills:AddSection("Auto Skill Tree") end)

    addToggle(Tabs.Skills, "AutoSkillTree", {
        Title = "Auto Skill Tree",
        Description = "Gasta skill points automaticamente",
        Default = false,
        Callback = function(v) SK.autoSkillTree = v end,
    })
end

local skillStatus = Panels.create(Tabs.Skills, "Auto Skill: Off", "Casts: 0")

-- =====================================================================
-- UI: FISHING
-- =====================================================================
if Tabs.Fishing then
    pcall(function() Tabs.Fishing:AddSection("Auto Fish") end)

    addToggle(Tabs.Fishing, "AutoFish", {
        Title = "Auto Fishing",
        Description = "Acha agua, casta e recolhe automaticamente",
        Default = false,
        Callback = function(v) FI.autoFish = v end,
    })

    pcall(function() Tabs.Fishing:AddSection("Auto Loot") end)

    addToggle(Tabs.Fishing, "AutoLoot", {
        Title = "Auto Loot",
        Description = "Coleta drops no chao automaticamente",
        Default = false,
        Callback = function(v) FI.autoLoot = v end,
    })

    pcall(function()
        Tabs.Fishing:AddSlider("LootRange", {
            Title = "Alcance de coleta",
            Default = 100, Min = 20, Max = 500, Rounding = 0, Suffix = " studs",
            Callback = function(v) FI.lootRange = v end,
        })
    end)
end

local fishStatus = Panels.create(Tabs.Fishing, "Auto Fish: Off", "Caught: 0")
local lootStatus = Panels.create(Tabs.Fishing, "Auto Loot: Off", "Collected: 0")

-- =====================================================================
-- STATUS LOOP
-- =====================================================================
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            if skillStatus then
                skillStatus:update(
                    "Auto Skill: " .. (SK.autoSkill and "ON" or "Off"),
                    string.format("Casts: %d | Last: %s", SK.casts, SK.lastSkill)
                )
            end
            if fishStatus then
                fishStatus:update(
                    "Auto Fish: " .. (FI.autoFish and "ON" or "Off"),
                    "Caught: " .. FI.fishCaught .. " | " .. FI.fishStatus
                )
            end
            if lootStatus then
                lootStatus:update(
                    "Auto Loot: " .. (FI.autoLoot and "ON" or "Off"),
                    "Collected: " .. FI.lootCollected
                )
            end
        end)
    end
end)

Logger.log("logic.lua (3b) carregado")

end)

if not ok_b then
    warn("[Kyôka] ERRO em logic.lua (3b): " .. tostring(err_b))
else
    print("[Kyôka] ✅ logic.lua (3b) pronto")
  end-- =====================================================================
-- KYÔKA HUB • LINK 3 — LOGIC (3c/3c)
-- Player + Progress + Teleport + Settings
-- =====================================================================

local ok_c, err_c = pcall(function()

local Core = _G.__KyokaHub
if not Core or not Core.ready then
    warn("[Kyôka] logic.lua (3c): core nao carregou.")
    return
end

local Services = Core.Services
local Game = Core.Game
local H = Core.H
local Logger = Core.Logger
local Notify = Core.Notify
local Panels = Core.Panels
local Tabs = Core.Tabs
local Options = Core.Options
local Sound = Core.Sound
local CatButton = Core.CatButton
local HubStatus = Core.HubStatus
local addToggle = Core.addToggle
local Config = Core.Config

local LP = Services.LocalPlayer
local UIS = Services.UserInputService

if not Tabs or not Notify or not Panels then
    warn("[Kyôka] logic.lua (3c): ui nao carregou.")
    return
end

Logger.log("Carregando logic.lua (3c) — Player + Progress + Teleport + Settings")

-- =====================================================================
-- STATE PROGRESS
-- =====================================================================
local PR = {
    showHUD = true,
    autoQuest = false,
    questTP = false,
    questMsg = "Idle",
    questsDone = 0,
    questFails = 0,
    autoSpin = false,
    spinDelay = 0.4,
    spinsDone = 0,
    autoCodes = false,
    codesRedeemed = 0,
}
Core.Progress = PR

-- =====================================================================
-- STATE TELEPORT / SETTINGS
-- =====================================================================
local ST = {
    teleportMethod = "Instant",
    soundEnabled = true,
    soundVolume = 0.35,
    version = "4.0",
    startTime = os.clock(),
    loadTime = 0,
}
Core.Settings = ST

-- =====================================================================
-- AUTO QUEST LOOP
-- =====================================================================
local questState = {
    step = "idle",
    quest = nil,
    npc = nil,
    npcPos = nil,
    lastPos = nil,
}

task.spawn(function()
    while true do
        task.wait(0.4)
        if PR.autoQuest and H.alive() then
            local _, hrp, hum = H.char()
            if hrp and hum then
                -- Anti-cheat detect
                if questState.lastPos and (hrp.Position - questState.lastPos).Magnitude > 100 then
                    PR.questMsg = "AC detectado, pausando"
                    PR.questFails = PR.questFails + 1
                    if PR.questFails >= 3 then
                        PR.autoQuest = false
                        Notify.error("Auto Quest", "Parado apos 3 falhas de AC", 6)
                    end
                    task.wait(8)
                end
                questState.lastPos = hrp.Position

                if questState.step == "idle" then
                    local pick = H.chooseQuest()
                    if not pick then
                        PR.questMsg = "Sem quest lvl " .. H.level()
                        task.wait(3)
                    else
                        questState.quest = pick
                        questState.npc = pick.npc
                        questState.npcPos = H.npcSpawn(pick.npc)
                        if not questState.npcPos then
                            PR.questMsg = "NPC sem spawn"
                            task.wait(3)
                        else
                            questState.step = "goNPC"
                            PR.questMsg = "-> " .. tostring(pick.npc)
                        end
                    end

                elseif questState.step == "goNPC" then
                    local pos = H.npcSpawn(questState.npc) or questState.npcPos
                    if pos then
                        local d = (hrp.Position - pos).Magnitude
                        if d > 8 then
                            if PR.questTP then H.safeTP(pos) else H.moveTo(pos) end
                            PR.questMsg = string.format("-> %s (%d)", tostring(questState.npc), math.floor(d))
                        else
                            questState.step = "accept"
                        end
                    else
                        questState.step = "idle"
                    end

                elseif questState.step == "accept" then
                    H.moveTo(questState.npcPos)
                    task.wait(0.4)
                    local model = H.npcModel(questState.npc)
                    if model then H.interactNPC(model) end
                    PR.questMsg = "Aceitando quest..."
                    task.wait(2)
                    questState.step = "farm"

                elseif questState.step == "farm" then
                    local task = H.currentTask(questState.quest)
                    if not task then
                        PR.questMsg = "Completo -> voltando"
                        questState.step = "return"
                    else
                        local mobs = H.mobs(150)
                        if #mobs > 0 then
                            local t = mobs[1]
                            if t.dist > 8 then
                                if PR.questTP then H.safeTP(t.root.Position) else H.moveTo(t.root.Position) end
                                PR.questMsg = string.format("X %s (%d)", tostring(t.rig.Name), math.floor(t.dist))
                            else
                                H.faceTarget(t.root.Position)
                                H.attack(t.root.Position)
                                PR.questMsg = "X Atacando " .. tostring(t.rig.Name)
                            end
                        else
                            PR.questMsg = "Sem mobs perto"
                            task.wait(1)
                        end
                    end

                elseif questState.step == "return" then
                    local pos = H.npcSpawn(questState.npc) or questState.npcPos
                    if pos then
                        local d = (hrp.Position - pos).Magnitude
                        if d > 8 then
                            if PR.questTP then H.safeTP(pos) else H.moveTo(pos) end
                            PR.questMsg = string.format("<- %s (%d)", tostring(questState.npc), math.floor(d))
                        else
                            questState.step = "complete"
                        end
                    else
                        questState.step = "idle"
                    end

                elseif questState.step == "complete" then
                    H.moveTo(questState.npcPos)
                    task.wait(0.4)
                    local model = H.npcModel(questState.npc)
                    if model then H.interactNPC(model) end
                    PR.questMsg = "Entregando..."
                    task.wait(2)
                    PR.questsDone = PR.questsDone + 1
                    PR.questFails = 0
                    questState.step = "idle"
                end
            else
                PR.questMsg = "Aguardando respawn"
            end
        else
            if not PR.autoQuest then
                questState.step = "idle"
                PR.questMsg = "Off"
            end
        end
    end
end)

-- =====================================================================
-- CLAN AUTO SPIN LOOP
-- =====================================================================
task.spawn(function()
    while true do
        task.wait(PR.spinDelay)
        if PR.autoSpin and Game.SignalFunction and H.alive() then
            local ok_s, rolled = pcall(function()
                return Game.SignalFunction.ToServer("ClanSpin")
            end)
            if ok_s and rolled then
                PR.spinsDone = PR.spinsDone + 1
                pcall(function()
                    Game.SignalEvent.ToServer("ClanSpinComplete")
                end)
            end
        end
    end
end)

-- =====================================================================
-- AUTO CODES
-- =====================================================================
task.spawn(function()
    task.wait(5)
    if not PR.autoCodes then return end
    if not Game.SignalFunction then return end

    local ok_st, status = pcall(function()
        return Game.SignalFunction.ToServer("CodeStatus")
    end)
    if not ok_st or type(status) ~= "table" or type(status.codes) ~= "table" then
        Notify.warn("Codes", "Nao conseguiu carregar lista", 5)
        return
    end

    for code, info in pairs(status.codes) do
        if not info.redeemed then
            local upper = string.upper(code)
            if not string.find(upper, "RESET", 1, true)
                and not string.find(upper, "WIPE", 1, true)
                and (string.find(upper, "SPIN", 1, true) or string.find(upper, "ROLL", 1, true)) then
                pcall(function()
                    Game.SignalFunction.ToServer("RedeemCode", code)
                end)
                PR.codesRedeemed = PR.codesRedeemed + 1
                task.wait(0.75)
            end
        end
    end
    if PR.codesRedeemed > 0 then
        Notify.success("Codes", PR.codesRedeemed .. " resgatados", 5)
    end
end)

-- =====================================================================
-- PLAYER HUD
-- =====================================================================
local PlayerHUD = { gui = nil, labels = {} }

local function criarPlayerHUD()
    if Services.CoreGui:FindFirstChild("KyokaHub_PlayerHUD") then
        Services.CoreGui.KyokaHub_PlayerHUD:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "KyokaHub_PlayerHUD"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 4
    gui.Parent = Services.CoreGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(220, 140)
    frame.Position = UDim2.new(0, 15, 0, 15)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 10)
    c.Parent = frame

    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(220, 40, 60)
    s.Thickness = 1
    s.Transparency = 0.4
    s.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -16, 0, 22)
    title.Position = UDim2.fromOffset(8, 6)
    title.BackgroundTransparency = 1
    title.Text = "Kyoka Hub • Player"
    title.TextColor3 = Color3.fromRGB(240, 240, 245)
    title.TextSize = 14
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local function line(y)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -16, 0, 18)
        l.Position = UDim2.fromOffset(8, y)
        l.BackgroundTransparency = 1
        l.Text = "-"
        l.TextColor3 = Color3.fromRGB(200, 200, 210)
        l.TextSize = 12
        l.Font = Enum.Font.Gotham
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = frame
        return l
    end

    PlayerHUD.gui = gui
    PlayerHUD.labels.level = line(30)
    PlayerHUD.labels.race = line(50)
    PlayerHUD.labels.clan = line(70)
    PlayerHUD.labels.wen = line(90)
    PlayerHUD.labels.quest = line(110)
end

criarPlayerHUD()

task.spawn(function()
    while true do
        task.wait(1)
        if PR.showHUD and PlayerHUD.gui then
            pcall(function()
                local lvl = H.level()
                local race = tostring(H.race())
                local clan = tostring(H.clan())
                local wen = H.wen()
                local cur, goal = H.exp()
                local pct = goal > 0 and math.floor(cur / goal * 100) or 0
                PlayerHUD.labels.level.Text = string.format("Level: %d (%d%%)", lvl, pct)
                PlayerHUD.labels.race.Text = "Raca: " .. race
                PlayerHUD.labels.clan.Text = "Cla: " .. clan
                PlayerHUD.labels.wen.Text = "Wen: " .. tostring(wen)
                PlayerHUD.labels.quest.Text = "Quest: " .. PR.questMsg
            end)
        end
    end
end)

-- =====================================================================
-- TELEPORT
-- =====================================================================
local Teleport = {}

function Teleport.toNPC(name)
    local pos = H.npcSpawn(name)
    if not pos then return false, "NPC nao encontrado" end
    local _, hrp = H.char()
    if not hrp then return false, "Sem personagem" end
    if ST.teleportMethod == "Instant" then
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
    else
        task.spawn(function()
            local start = hrp.CFrame
            local endCF = CFrame.new(pos + Vector3.new(0, 5, 0))
            for i = 0, 1, 0.05 do
                hrp.CFrame = start:Lerp(endCF, i)
                task.wait(0.02)
            end
        end)
    end
    return true
end

function Teleport.toCoords(x, y, z)
    local _, hrp = H.char()
    if not hrp then return false, "Sem personagem" end
    hrp.CFrame = CFrame.new(Vector3.new(x, y, z))
    return true
end

Core.Teleport = Teleport

-- =====================================================================
-- UI: PLAYER
-- =====================================================================
if Tabs.Player then
    pcall(function() Tabs.Player:AddSection("Info do Personagem") end)

    pcall(function()
        Tabs.Player:AddToggle("ShowHUD", {
            Title = "Mostrar HUD na tela",
            Description = "Painel com stats no canto",
            Default = true,
            Callback = function(v)
                PR.showHUD = v
                if PlayerHUD.gui then PlayerHUD.gui.Enabled = v end
            end,
        })
    end)

    pcall(function() Tabs.Player:AddSection("Clan Auto Spin") end)

    addToggle(Tabs.Player, "AutoSpin", {
        Title = "Auto Clan Spin",
        Description = "Gira o cla automaticamente",
        Default = false,
        Callback = function(v) PR.autoSpin = v end,
    })

    pcall(function()
        Tabs.Player:AddSlider("SpinDelay", {
            Title = "Delay de Spin",
            Default = 0.4, Min = 0.1, Max = 3, Rounding = 1, Suffix = "s",
            Callback = function(v) PR.spinDelay = v end,
        })
    end)
end

local playerPanel = Panels.create(Tabs.Player, "Level: ...", "Carregando...")

-- =====================================================================
-- UI: PROGRESS
-- =====================================================================
if Tabs.Progress then
    pcall(function() Tabs.Progress:AddSection("Auto Quest (Loop Completo)") end)

    addToggle(Tabs.Progress, "AutoQuest", {
        Title = "Auto Quest",
        Description = "Le level -> aceita -> farma -> entrega -> repete",
        Default = false,
        Callback = function(v) PR.autoQuest = v end,
    })

    addToggle(Tabs.Progress, "QuestTP", {
        Title = "Usar Teleporte",
        Description = "OFF = anda | ON = teleporta 30 studs (risco)",
        Default = false,
        Callback = function(v) PR.questTP = v end,
    })

    pcall(function() Tabs.Progress:AddSection("Auto Codes") end)

    addToggle(Tabs.Progress, "AutoCodes", {
        Title = "Auto Codes",
        Description = "Resgata codes de spin/reroll",
        Default = false,
        Callback = function(v) PR.autoCodes = v end,
    })
end

local questPanel = Panels.create(Tabs.Progress, "Auto Quest: Off", "Quests: 0")
local codesPanel = Panels.create(Tabs.Progress, "Codes: 0", "Off")

-- =====================================================================
-- UI: TELEPORT
-- =====================================================================
if Tabs.Teleport then
    pcall(function() Tabs.Teleport:AddSection("NPCs de Quest") end)

    pcall(function()
        Tabs.Teleport:AddDropdown("TpNPC", {
            Title = "Escolher NPC",
            Values = { "Krue","Tom","Chaka","Wagwan","Jugg","Goro","Tomoi","Mitsu","KasugaiCrow" },
            Default = "Krue", Multi = false,
        })
    end)

    pcall(function()
        Tabs.Teleport:AddButton({
            Title = "Teleportar para NPC",
            Callback = function()
                local n = Options.TpNPC and Options.TpNPC.Value or "Krue"
                local ok_t, err_t = Teleport.toNPC(n)
                if ok_t then
                    Notify.success("Teleport", "Foi pra " .. n, 3)
                else
                    Notify.error("Teleport", tostring(err_t), 4)
                end
            end,
        })
    end)

    pcall(function() Tabs.Teleport:AddSection("Coordenadas Customizadas") end)

    pcall(function() Tabs.Teleport:AddInput("TpX", { Title = "X", Default = "0" }) end)
    pcall(function() Tabs.Teleport:AddInput("TpY", { Title = "Y", Default = "0" }) end)
    pcall(function() Tabs.Teleport:AddInput("TpZ", { Title = "Z", Default = "0" }) end)

    pcall(function()
        Tabs.Teleport:AddButton({
            Title = "Ir para Coordenadas",
            Callback = function()
                local x = tonumber(Options.TpX and Options.TpX.Value) or 0
                local y = tonumber(Options.TpY and Options.TpY.Value) or 0
                local z = tonumber(Options.TpZ and Options.TpZ.Value) or 0
                local ok_t = Teleport.toCoords(x, y, z)
                if ok_t then
                    Notify.success("Teleport", string.format("%.0f, %.0f, %.0f", x, y, z), 3)
                else
                    Notify.error("Teleport", "Sem personagem", 3)
                end
            end,
        })
    end)

    pcall(function()
        Tabs.Teleport:AddDropdown("TpMethod", {
            Title = "Metodo",
            Values = { "Instant", "Tween" },
            Default = "Instant", Multi = false,
            Callback = function(v) ST.teleportMethod = v end,
        })
    end)
end

-- =====================================================================
-- UI: SETTINGS
-- =====================================================================
if Tabs.Settings then
    pcall(function() Tabs.Settings:AddSection("Interface") end)

    pcall(function()
        Tabs.Settings:AddToggle("HideCat", {
            Title = "Esconder Botao do Gato",
            Default = false,
            Callback = function(v)
                if CatButton and CatButton.setVisible then
                    CatButton.setVisible(not v)
                end
            end,
        })
    end)

    pcall(function()
        Tabs.Settings:AddKeybind("ToggleKey", {
            Title = "Abrir/Fechar Hub",
            Mode = "Toggle",
            Default = "RightShift",
        })
    end)

    pcall(function() Tabs.Settings:AddSection("Som") end)

    pcall(function()
        Tabs.Settings:AddToggle("SoundEnabled", {
            Title = "Sons da Interface",
            Default = true,
            Callback = function(v)
                ST.soundEnabled = v
                if Sound then Sound.enabled = v end
            end,
        })
    end)

    pcall(function()
        Tabs.Settings:AddSlider("SoundVolume", {
            Title = "Volume",
            Default = 0.35, Min = 0, Max = 1, Rounding = 2,
            Callback = function(v)
                ST.soundVolume = v
                if Sound then Sound.volume = v end
            end,
        })
    end)

    pcall(function() Tabs.Settings:AddSection("Info") end)
end

local infoPanel = Panels.create(Tabs.Settings, "Kyoka Hub v4.0", "Iniciando...")

-- =====================================================================
-- HOTKEYS GLOBAIS
-- =====================================================================
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        local farm = Core.Farm
        if farm then
            farm.autoFarm = false
            farm.killAura = false
            farm.autoBoss = false
        end
        local skills = Core.Ski
