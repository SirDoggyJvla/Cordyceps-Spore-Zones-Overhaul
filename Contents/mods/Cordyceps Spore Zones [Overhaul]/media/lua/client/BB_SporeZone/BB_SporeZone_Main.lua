-- **************************************************
-- ██████  ██████   █████  ██    ██ ███████ ███    ██ 
-- ██   ██ ██   ██ ██   ██ ██    ██ ██      ████   ██ 
-- ██████  ███████ ██   ██ ██    ██ █████   ██ 
-- ██   ██ ██   ██ ██   ██  ██  ██  ██      ██  ██ ██ 
-- ██████  ██   ██ ██   ██   ████   ███████ ██   ████
-- **************************************************
require "Susceptible/SusceptibleTrait"
local SusUtil = require "Susceptible/SusceptibleUtil"

local climateManager = nil
local currZoneChance = 0
local INFECTION_ROLLS_PER_SECOND = 10 -- This number should evenly divide 60. Not a hard requirement, but nicer.

local function isWearingGasMask()
	-- from SirDoggyJvla: almost everything here was modified to adapt to Susceptible mask check
	local item, mask = SusceptibleMod.getEquippedMaskItemAndData(getPlayer());
    if not mask or SusUtil.isBroken(item) then
        return false
    end
	
	-- checks if mask with filter/oxygen is on, else return false for no mask
	if mask.repairType == SusceptibleRepairTypes.OXYGEN or mask.repairType == SusceptibleRepairTypes.FILTER then
		return true
	end
	
	return false
end

-- from SirDoggyJvla: creates the mask UI and updates the durability
local function maskUI(player,threatLevel,gasMask)
    if player:isDead() then
        return;
    end

	-- retrieve mask item type and info
    local item, mask = SusceptibleMod.getEquippedMaskItemAndData(player)
	
    if not SusceptibleMod.uiByPlayer[player] then
        SusceptibleMod.createMaskUi(player);
    end
	
	-- makes sure mask item is not broken
    local isBroken = not item or SusUtil.isBroken(item);

	
	
    
	if gasMask and not isBroken then
        -- set mask image
        SusceptibleMod.uiByPlayer[player]:updateMaskImage(item, mask, threatLevel, isBroken)

		-- get item data, notably durabilityMax
		local data = SusUtil.getItemModData(item);
				
		--local durability = SusUtil.getNormalizedDurability(item)
		local durability = data.durability / data.durabilityMax
		
		SusceptibleMod.uiByPlayer[player]:updateMaskInfo(true, durability, 0)
	else
        item = nil
        -- set mask image
        SusceptibleMod.uiByPlayer[player]:updateMaskImage(item, mask, threatLevel, isBroken)

		SusceptibleMod.uiByPlayer[player]:updateMaskInfo(false, 0, 0)
	end

end

local function everyMinute()
    if not SandboxVars.SporeZones then return end
    local playerObj = getPlayer(); if not playerObj then return end
    local building = playerObj:getBuilding()

	-- from SirDoggyJvla: check mask from Susceptible list
	local gasMask = isWearingGasMask()

	-- from SirDoggyJvla: UI of mask even without Susceptible Trait
	if not SusceptibleMod.isPlayerSusceptible(playerObj) then
		maskUI(playerObj,0,gasMask)
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
			-- if no mask, then get sick
            if gasMask == false then
				-- from SirDoggyJvla: set mask UI to danger
				if not SusceptibleMod.isPlayerSusceptible(playerObj) then
					maskUI(playerObj,2,gasMask)
				end
				
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
				-- from SirDoggyJvla: set mask UI to no danger
				if not SusceptibleMod.isPlayerSusceptible(playerObj) then
					maskUI(playerObj,0,gasMask)
				end
				
				-- retrieve mask item type and info
				local item, mask = SusceptibleMod.getEquippedMaskItemAndData(getPlayer());
				
				-- get item data, notably durabilityMax
				local data = SusUtil.getItemModData(item);
				
				-- maskDamageRate / time to drain = durability loss per minute (bcs function everyMinute)
				local maskDamageRate = data.durabilityMax / 60;

				-- calculate durability loss depending on mask type, priotizing oxygen tanks
				if mask.repairType == SusceptibleRepairTypes.OXYGEN and SandboxVars.SporeZones.DrainageOxyTank then
					local condition = item:getCondition() / item:getConditionMax() + 0.1;
					condition = condition * condition;
					if condition > 1 then
						condition = 1;
					end
	
					local conditionMult = 1.0 / condition; -- You're leaking :)
					SusceptibleMod.damageMask(item, mask, conditionMult * maskDamageRate / SandboxVars.SporeZones.TimetoDrainOxyTank ); -- Constant drain rate for oxygen based protection
				elseif mask.repairType == SusceptibleRepairTypes.FILTER and SandboxVars.SporeZones.DrainageFilter then
					local damage = maskDamageRate / SandboxVars.SporeZones.TimetoDrainFilter;
					SusceptibleMod.damageMask(item, mask, damage);
				end
			end
			
			-- draw spore zone UI
            BB_Spore_UI.drawSporeCanvas = true
        end

    elseif BB_Spore_UI.drawSporeCanvas == true then

        BB_Spore_UI.drawSporeCanvas = false
        local bodyDamage = playerObj:getBodyDamage(); if not bodyDamage then return end
        if not playerObj:getModData().existingSickness then return end

        bodyDamage:setFoodSicknessLevel(playerObj:getModData().existingSickness)
        if bodyDamage:isHasACold() then
            bodyDamage:setHasACold(false)
        end

        playerObj:getModData().cordycepsInfectionTimer = nil
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