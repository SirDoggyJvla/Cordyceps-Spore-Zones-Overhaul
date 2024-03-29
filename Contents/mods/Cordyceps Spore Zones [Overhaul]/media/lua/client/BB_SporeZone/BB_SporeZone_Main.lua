-- **************************************************
-- ██████  ██████   █████  ██    ██ ███████ ███    ██ 
-- ██   ██ ██   ██ ██   ██ ██    ██ ██      ████   ██ 
-- ██████  ███████ ██   ██ ██    ██ █████   ██ 
-- ██   ██ ██   ██ ██   ██  ██  ██  ██      ██  ██ ██ 
-- ██████  ██   ██ ██   ██   ████   ███████ ██   ████
-- **************************************************
-- from SirDoggyJvla: import module
local Susceptible_Overhaul = require "Susceptible_Overhaul_module"

local climateManager = nil
local currZoneChance = 0
local INFECTION_ROLLS_PER_SECOND = 10 -- This number should evenly divide 60. Not a hard requirement, but nicer.

local function everyMinute()
    if not SandboxVars.SporeZones then return end
    local playerObj = getPlayer(); if not playerObj then return end
    local building = playerObj:getBuilding()

    local player = getPlayer()
    local playerModData = player:getModData()
    if not playerModData["Susceptible_Overhaul"] then
        playerModData["Susceptible_Overhaul"] = {}
    end
    if not playerModData["Susceptible_Overhaul"].InDanger then
        playerModData["Susceptible_Overhaul"].InDanger = {}
    end

    if building then
        local buildingDef = building:getDef()
        local zCoord = (buildingDef:getFirstRoom() and buildingDef:getFirstRoom():getZ()) or 0
        local buildingSq = playerObj:getCell():getGridSquare(buildingDef:getX(), buildingDef:getY(), zCoord)
        local zoneSq = buildingDef:getFreeSquareInRoom(); if not zoneSq then return end
        local modData = nil
        if buildingSq then
            modData = buildingSq:getModData()
        end

        if not modData or modData and not (modData.isSporeZone or modData.visitedBefore) then
            if buildingSq then
                if ZombRand(0,100) < currZoneChance then
                    Utils_SporeZones.CreateSporeZone(building, buildingDef, playerObj, buildingSq, zoneSq)
                else
                    local args = { origin = { x = buildingSq:getX(), y = buildingSq:getY(), z = buildingSq:getZ() } }
                    sendClientCommand(playerObj, 'SporeZone', 'TransmitVisited', args)
                end
            end
        elseif modData and modData.isSporeZone then
            -- from SirDoggyJvla: check mask from Susceptible list
	        local gasMask = Susceptible_Overhaul.isWearingGasMask() or Susceptible_Overhaul.isWearingHazmat()

            -- if no mask, then get sick
            if gasMask == false then
				-- from SirDoggyJvla: set mask UI to danger
				playerModData["Susceptible_Overhaul"].InDanger.CSZ = true

                local bodyDamage = playerObj:getBodyDamage()

                local currSickness = bodyDamage:getFoodSicknessLevel()
                local existingSickness = playerObj:getModData().existingSickness
                if not existingSickness or existingSickness ~= currSickness then
                    playerObj:getModData().existingSickness = currSickness
                end

                if not bodyDamage:isHasACold() then
                    bodyDamage:setHasACold(true)
                    bodyDamage:setColdStrength(80.0)
                    bodyDamage:setTimeToSneezeOrCough(0)
                end

                if not bodyDamage:isInfected() then

                    local sicknessIncreasePerMinute = 100 / SandboxVars.SporeZones.InfectionTime
                    bodyDamage:setFoodSicknessLevel(currSickness + sicknessIncreasePerMinute)

                    local newSicknessLevel = bodyDamage:getFoodSicknessLevel()
                    playerObj:getModData().cordycepsInfectionTimer = newSicknessLevel

                    if newSicknessLevel >= 100 then
                        bodyDamage:setInfected(true)
                    end
                end

			-- from SirDoggyJvla: if gasMask is on and in sporeZone then damage mask
			elseif gasMask == true then
                playerModData["Susceptible_Overhaul"].InDanger.CSZ = nil

				Susceptible_Overhaul.damageMask(
                    SandboxVars.SporeZones.DrainageOxyTank,
                    SandboxVars.SporeZones.DrainageFilter,
                    SandboxVars.SporeZones.TimetoDrainOxyTank,
                    SandboxVars.SporeZones.TimetoDrainFilter
                )
			end

			-- draw spore zone UI
            BB_Spore_UI.drawSporeCanvas = true
        else
            playerModData["Susceptible_Overhaul"].InDanger.CSZ = nil
        end

    elseif BB_Spore_UI.drawSporeCanvas == true then
        playerModData["Susceptible_Overhaul"].InDanger.CSZ = nil

        BB_Spore_UI.drawSporeCanvas = false
        local bodyDamage = playerObj:getBodyDamage(); if not bodyDamage then return end
        if not playerObj:getModData().existingSickness then return end

        bodyDamage:setFoodSicknessLevel(playerObj:getModData().existingSickness)
        if bodyDamage:isHasACold() then
            bodyDamage:setHasACold(false)
        end

        playerObj:getModData().cordycepsInfectionTimer = nil
    else
        playerModData["Susceptible_Overhaul"].InDanger.CSZ = nil
    end
end

local updateZoneChance = function()

    if not SandboxVars.SporeZones.StartDay then

        if SandboxVars.SporeZones.ZoneChance then
            currZoneChance = SandboxVars.SporeZones.ZoneChance
        else
            currZoneChance = 5
        end

        return
    end

    local dayInfo = climateManager:getCurrentDay()
    local startDate = os.time{day = SandboxVars.StartDay, year = 1992 + SandboxVars.StartYear, month = SandboxVars.StartMonth}
    local currDate = os.time{day = dayInfo:getDay(), year = dayInfo:getYear(), month = dayInfo:getMonth() + 1}

    local daysfrom = os.difftime(startDate, currDate) / (24 * 60 * 60)
    local currDay = math.floor(daysfrom)
    if currDay < 0 then currDay = -currDay end

    if currDay >= SandboxVars.SporeZones.StartDay then
        if SandboxVars.SporeZones.DailyIncrement == 0 then
            currZoneChance = SandboxVars.SporeZones.ZoneChance
        elseif currZoneChance < SandboxVars.SporeZones.ZoneChance then
            currZoneChance = (currDay - (SandboxVars.SporeZones.StartDay - 1)) * SandboxVars.SporeZones.DailyIncrement
            if currZoneChance > SandboxVars.SporeZones.ZoneChance then currZoneChance = SandboxVars.SporeZones.ZoneChance end
        end
    end
end

local onGameStart = function()
	local playerObj = getPlayer(); if not playerObj then return end
    local hoursSurvived = playerObj:getHoursSurvived()
	local hoursSlept = playerObj:getLastHourSleeped()
    local playerNum = playerObj:getPlayerNum()

    climateManager = getClimateManager()

    BB_Spore_UI.screenWidth = getPlayerScreenWidth(playerNum)
    BB_Spore_UI.screenHeight = getPlayerScreenHeight(playerNum)
    updateZoneChance()

	if hoursSurvived == 0 and hoursSlept == 0 then
        local building = playerObj:getBuilding()
        if building then
            local buildingDef = building:getDef()
            local buildingSq = playerObj:getCell():getGridSquare(buildingDef:getX(), buildingDef:getY(), buildingDef:getFirstRoom():getZ())
            local modData = nil
            if buildingSq then
                modData = buildingSq:getModData()
            end

            if not modData or not (modData.isSporeZone or modData.visitedBefore) then
                local args = { origin = { x = buildingSq:getX(), y = buildingSq:getY(), z = buildingSq:getZ() } }
                sendClientCommand(playerObj, 'SporeZone', 'TransmitVisited', args)
            end
        end
    end

    Events.EveryOneMinute.Add(everyMinute)
end

local everyHour = function()
    if climateManager:getCurrentDay():getHour() + 1 == getGameTime():getStartTimeOfDay() then
        updateZoneChance()
    end
end

Events.OnGameStart.Add(onGameStart)

Events.EveryHours.Add(everyHour)