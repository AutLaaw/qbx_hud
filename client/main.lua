local config = require 'config'
local hud = config.HUD
local speedMultiplier = hud.useMPH and 2.23694 or 3.6
local display = false
local vehicleHUDActive = false
local playerHUDActive = false
local showSeatbelt = false
local hunger = LocalPlayer.state.hunger or 100
local thirst = LocalPlayer.state.thirst or 100
local stress = LocalPlayer.state.stress or 0
local nitroLevel = 0

--[[
local function loadSettings(settings)
    for k, v in pairs(settings) do
        if k == 'isToggleMapShapeChecked' then
            sharedConfig.menu.isToggleMapShapeChecked = v
            SendNUIMessage({test = true, event = k, toggle = v})
        elseif k == 'isCineamticModeChecked' then
            sharedConfig.menu.isCineamticModeChecked = v
            cinematicShow(v)
            SendNUIMessage({test = true, event = k, toggle = v})
        elseif k == 'isChangeFPSChecked' then
            sharedConfig.menu[k] = v
            local val = v and 'Optimized' or 'Synced'
            SendNUIMessage({test = true, event = k, toggle = val})
        else
            sharedConfig.menu[k] = v
            SendNUIMessage({test = true, event = k, toggle = v})
        end
    end
    exports.qbx_core:Notify('Hud Settings Loaded', 'success')
    Wait(1000)
    TriggerEvent('hud:client:LoadMap')
end

local function saveSettings()
    SetResourceKvp('hudSettings', json.encode(sharedConfig.menu))
end
]]

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(500)
    --local hudSettings = GetResourceKvpString('hudSettings')
    --if hudSettings then loadSettings(json.decode(hudSettings)) end
    startHUD()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Wait(2000)
    --local hudSettings = GetResourceKvpString('hudSettings')
    --if hudSettings then loadSettings(json.decode(hudSettings)) end
    startHUD()
end)

function startHUD()
    local ped = cache.ped
    if not IsPedInAnyVehicle(ped, false) then
        DisplayRadar(false)
    else
        DisplayRadar(true)
        SendNUIMessage({ action = 'showVehicleHUD' })
    end
    TriggerEvent('hud:client:LoadMap')
    SendNUIMessage({ action = 'showPlayerHUD' })
    playerHUDActive = true
end

local lastCrossroadUpdate = 0
local lastCrossroadCheck = {}

function GetCrossroads(vehicle)
    local updateTick = GetGameTimer()
    if updateTick - lastCrossroadUpdate > 1500 then
        local pos = GetEntityCoords(vehicle)
        local street1, street2 = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
        lastCrossroadUpdate = updateTick
        lastCrossroadCheck = { GetStreetNameFromHashKey(street1), GetStreetNameFromHashKey(street2) }
    end
    return lastCrossroadCheck
end

CreateThread(function()
    local function updatePlayerHUD()
        if IsPauseMenuActive() then
            SendNUIMessage({ action = 'hidePlayerHUD' })
            playerHUDActive = false
            return
        end

        if not playerHUDActive then
            SendNUIMessage({ action = 'showPlayerHUD' })
            playerHUDActive = true
        end

        local stamina = 0
        if not IsEntityInWater(cache.ped) then
            stamina = 100 - GetPlayerSprintStaminaRemaining(cache.playerId)
        else
            stamina = GetPlayerUnderwaterTimeRemaining(cache.playerId) * 10
        end

        SendNUIMessage({
            action = 'updatePlayerHUD',
            health = GetEntityHealth(cache.ped) - 100,
            armor = GetPedArmour(cache.ped),
            thirst = thirst,
            hunger = hunger,
            stamina = stamina,
            dynamicStress = stress,
            stress = stress,
            voice = LocalPlayer.state.proximity.distance,
            talking = NetworkIsPlayerTalking(cache.playerId),
        })
    end

    local function updateVehicleHUD()
        local vehicle = cache.vehicle
        local engineOn = GetIsVehicleEngineRunning(vehicle)
        local vehicleTypeIsAir = IsPedInAnyHeli(cache.ped) or IsPedInAnyPlane(cache.ped)
        local invOpen = LocalPlayer.state.invOpen

        if engineOn and not invOpen then
            if not vehicleHUDActive then
                vehicleHUDActive = true
                DisplayRadar(true)
                SendNUIMessage({ action = 'showVehicleHUD' })
            end

            local crossroads = GetCrossroads(vehicle)
            local gear = exports[hud.gearExport]:getCurrentGear()
            local rpm = GetVehicleCurrentRpm(vehicle)
            local altitudeInfo = vehicleTypeIsAir and {
                altitude = math.ceil(GetEntityCoords(cache.ped, true).z * 100),
                altitudetexto = 'ALT'
            } or {
                altitude = '',
                altitudetexto = ''
            }

            SendNUIMessage({
                action = 'updateVehicleHUD',
                speed = math.ceil(GetEntitySpeed(vehicle) * speedMultiplier),
                fuel = math.ceil(GetVehicleFuelLevel(vehicle)),
                gear = gear,
                rpm = rpm,
                street1 = crossroads[1],
                street2 = crossroads[2],
                direction = GetDirectionText(GetEntityHeading(vehicle)),
                seatbeltOn = LocalPlayer.state.seatbelt,
                showSeatbelt = showSeatbelt,
                nos = nitroLevel,
                altitude = altitudeInfo.altitude,
                altitudetexto = altitudeInfo.altitudetexto
            })
        else
            if vehicleHUDActive then
                vehicleHUDActive = false
                DisplayRadar(false)
                SendNUIMessage({ action = 'hideVehicleHUD' })
            end
        end
    end

    while true do
        updatePlayerHUD()
        if IsPedInAnyVehicle(cache.ped, false) then
            updateVehicleHUD()
        elseif vehicleHUDActive then
            vehicleHUDActive = false
            DisplayRadar(false)
            SendNUIMessage({ action = 'hideVehicleHUD' })
        end

        SetBigmapActive(false, false)
        SetRadarZoom(1000)
        Wait(hud.updateDelay)
    end
end)

function GetDirectionText(heading)
    return ({
        'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'
    })[math.floor(((heading + 22.5) % 360) / 45) + 1]
end

RegisterNetEvent('hud:client:UpdateNeeds', function(newHunger, newThirst) -- Triggered in some scripts
    thirst = newThirst
    hunger = newHunger
end)

RegisterNetEvent('hud:client:LoadMap')
AddEventHandler('hud:client:LoadMap', function(width, height)
    Wait(100)
    TriggerEvent('updateMinimapPosition', width, height)

    local DEFAULT_ASPECT_RATIO = 1920 / 1080
    local TEXTURE_DICT = 'squaremap'
    local MINIMAP_OFFSET_ADJUSTMENT_FACTOR = 3.6
    local MINIMAP_OFFSET_BASE = 0.019

    RequestStreamedTextureDict(TEXTURE_DICT, false)
    while not HasStreamedTextureDictLoaded(TEXTURE_DICT) do
        Wait(0)
    end

    local resolutionX, resolutionY = GetActiveScreenResolution()
    local safezone = GetSafeZoneSize()
    local safezoneX = safezone * 0.5
    local safezoneY = safezone * 0.5
    local aspectRatio = (resolutionX - safezoneX) / (resolutionY - safezoneY)

    local minimapOffsetX = tonumber(width) or 0
    if aspectRatio > DEFAULT_ASPECT_RATIO then
        minimapOffsetX = ((DEFAULT_ASPECT_RATIO - aspectRatio) / MINIMAP_OFFSET_ADJUSTMENT_FACTOR) - MINIMAP_OFFSET_BASE
    end

    local minimapOffsetY = tonumber(height) or -0.047

    AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', TEXTURE_DICT, 'radarmasksm')
    AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', TEXTURE_DICT, 'radarmasksm')
    SetMinimapComponentPosition('minimap', 'L', 'B', 0.0 + minimapOffsetX, minimapOffsetY, 0.163, 0.183)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B', 0.0 + minimapOffsetX, minimapOffsetY + 0.047, 0.128, 0.20)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', 0.00 + minimapOffsetX, minimapOffsetY + 0.112, 0.252, 0.338)

    SetBlipAlpha(GetNorthRadarBlip(), 0)
    SetMinimapClipType(0)
    SetRadarBigmapEnabled(true, false)
    Wait(50)
    SetRadarBigmapEnabled(false, false)
end)

--@Deprecated
RegisterNetEvent('hud:client:UpdateStress', function(newStress)
    stress = newStress
end)

AddStateBagChangeHandler('stress', ('player:%s'):format(cache.serverId), function(_, _, value)
    stress = value
end)

CreateThread(function() -- Speeding
    while true do
        if LocalPlayer.state.isLoggedIn then
            local ped = cache.ped
            if IsPedInAnyVehicle(ped, false) then
                local veh = cache.vehicle
                local vehClass = GetVehicleClass(veh)
                local speed = GetEntitySpeed(veh) * speedMultiplier
                local vehHash = GetEntityModel(veh)
                if hud.vehClassStress[tostring(vehClass)] and not hud.whitelistedVehicles[vehHash] then
                    local stressSpeed
                    if vehClass == 8 then -- Motorcycle exception for seatbelt
                        stressSpeed = hud.minimumSpeed
                    else
                        stressSpeed = LocalPlayer.state.seatbelt and hud.minimumSpeed or hud.minimumSpeedUnbuckled
                    end
                    if speed >= stressSpeed then
                        TriggerServerEvent('hud:server:GainStress', math.random(1, 3))
                    end
                end
            end
        end
        Wait(10000)
    end
end)

-- Stress Screen Effects
local function GetBlurIntensity(stresslevel)
    for _, v in pairs(hud.intensity['blur']) do
        if stresslevel >= v.min and stresslevel <= v.max then
            return v.intensity
        end
    end
    return 1500
end

local function GetEffectInterval(stresslevel)
    for _, v in pairs(hud.effectInterval) do
        if stresslevel >= v.min and stresslevel <= v.max then
            return v.timeout
        end
    end
    return 60000
end

CreateThread(function()
    while true do
        local ped = cache.ped
        local effectInterval = GetEffectInterval(stress)
        if stress >= 100 then
            local BlurIntensity = GetBlurIntensity(stress)
            local FallRepeat = math.random(2, 4)
            local RagdollTimeout = FallRepeat * 1750
            TriggerScreenblurFadeIn(1000.0)
            Wait(BlurIntensity)
            TriggerScreenblurFadeOut(1000.0)

            if not IsPedRagdoll(ped) and IsPedOnFoot(ped) and not IsPedSwimming(ped) then
                SetPedToRagdollWithFall(ped, RagdollTimeout, RagdollTimeout, 1, GetEntityForwardVector(ped), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
            end

            Wait(1000)
            for _ = 1, FallRepeat, 1 do
                Wait(750)
                DoScreenFadeOut(200)
                Wait(1000)
                DoScreenFadeIn(200)
                TriggerScreenblurFadeIn(1000.0)
                Wait(BlurIntensity)
                TriggerScreenblurFadeOut(1000.0)
            end
        elseif stress >= hud.minimumStress then
            local BlurIntensity = GetBlurIntensity(stress)
            TriggerScreenblurFadeIn(1000.0)
            Wait(BlurIntensity)
            TriggerScreenblurFadeOut(1000.0)
        end
        Wait(effectInterval)
    end
end)

-- Seatbelt
RegisterNetEvent('hud:client:ToggleShowSeatbelt', function()
    showSeatbelt = not showSeatbelt
end)

local function restartHud()
    exports.qbx_core:Notify('Hud Is Restarting', 'error')
    Wait(1000)
    SendNUIMessage({ action = 'hideVehicleHUD'})
    SendNUIMessage({ action = 'hidePlayerHUD'})
    DisplayRadar(false)
    Wait(2500)
    SendNUIMessage({ action = 'showVehicleHUD'})
    SendNUIMessage({ action = 'showPlayerHUD'})
    DisplayRadar(true)
    Wait(1000)
    exports.qbx_core:Notify('Hud Has Started!', 'success')
end

RegisterCommand('restarthud', function()
    Wait(50)
    restartHud()
end, false)

RegisterCommand('hud', function()
    SetDisplay(not display)
end, false)

RegisterNUICallback('exit', function()
    SetDisplay(false)
end)

RegisterNUICallback('main', function(data)
    print(data.text)
    SetDisplay(false)
end)

RegisterNUICallback('error', function(data)
    print(data.error)
    SetDisplay(false)
end)

function SetDisplay(bool)
    display = bool
    SetNuiFocus(bool, bool)
    SendNUIMessage({
        type = 'ui',
        status = bool,
    })
end

CreateThread(function()
    while display do
        Wait(0)
        DisableControlAction(0, 1, display)
        DisableControlAction(0, 2, display)
        DisableControlAction(0, 142, display)
        DisableControlAction(0, 18, display)
        DisableControlAction(0, 322, display)
        DisableControlAction(0, 106, display)
    end
end)

CreateThread(function()
    SetMapZoomDataLevel(0, 2.75, 0.9, 0.08, 0.0, 0.0) -- Level 0
    SetMapZoomDataLevel(1, 2.8, 0.9, 0.08, 0.0, 0.0) -- Level 1
    SetMapZoomDataLevel(2, 8.0, 0.9, 0.08, 0.0, 0.0) -- Level 2
    SetMapZoomDataLevel(3, 20.0, 0.9, 0.08, 0.0, 0.0) -- Level 3
    SetMapZoomDataLevel(4, 35.0, 0.9, 0.08, 0.0, 0.0) -- Level 4
    SetMapZoomDataLevel(5, 55.0, 0.0, 0.1, 2.0, 1.0) -- ZOOM_LEVEL_GOLF_COURSE
    SetMapZoomDataLevel(6, 450.0, 0.0, 0.1, 1.0, 1.0) -- ZOOM_LEVEL_INTERIOR
    SetMapZoomDataLevel(7, 4.5, 0.0, 0.0, 0.0, 0.0) -- ZOOM_LEVEL_GALLERY
    SetMapZoomDataLevel(8, 11.0, 0.0, 0.0, 2.0, 3.0) -- ZOOM_LEVEL_GALLERY_MAXIMIZE
end)

if hud.enableCayoMiniMap then
    CreateThread(function()
        while true do
            SetRadarAsExteriorThisFrame()
            local coords = vec(4700.0, -5145.0)
            SetRadarAsInteriorThisFrame(`h4_fake_islandx`, coords.x, coords.y, 0, 0)
            Wait(0)
        end
    end)
end