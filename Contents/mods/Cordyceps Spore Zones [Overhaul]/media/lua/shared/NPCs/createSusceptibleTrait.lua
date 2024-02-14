local function initSusceptibleTrait()
	if getActivatedMods():contains("CordycepsSporeZoneSusceptiblePatchNoTrait") == false then
		TraitFactory.addTrait("Susceptible", getText("UI_trait_Susceptible"), -11, getText("UI_trait_SusceptibleDesc"), false, false);
	end
end

Events.OnGameBoot.Add(initSusceptibleTrait);