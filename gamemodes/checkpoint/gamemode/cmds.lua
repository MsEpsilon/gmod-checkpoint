include("scenarios.lua")

local serializableMapEntityClasses = {
	"edit_fog",
	"edit_sky",
	"edit_sun"
}

local function IsSerializableMapEntityClass(class)
	return class == "edit_fog" or class == "edit_sky" or class == "edit_sun"
end

function SaveScenario(scenario_name)
	if not isstring(scenario_name) or not string.match(scenario_name, "^[%w_-]+$") then
		print("Invalid scenario name")
		return
	end

	local entities = {}
	local savedEntityCount = 0
	local function SaveEntity(ent)
		if IsValid(ent) then
			local pos = ent:GetPos()
			local ang = ent:GetAngles()
			local item = {
				class = ent:GetClass(),
				position = { x = pos.x, y = pos.y, z = pos.z },
				angle = { p = ang.p, y = ang.y, r = ang.r },
				radius = ent.GetRadius and ent:GetRadius() or nil,
				patrolRadius = ent.GetPatrolRadius and ent:GetPatrolRadius() or nil
			}
			if IsSerializableMapEntityClass(item.class) then
				item.keyValues = {}
				for key, value in pairs(ent:GetKeyValues() or {}) do
					item.keyValues[key] = tostring(value)
				end
			end
			entities[#entities + 1] = item
			savedEntityCount = savedEntityCount + 1
		end
	end

	local orderedObjectives = ents.FindByClass("chkgm-objective")
	for _, ent in ipairs(ents.FindByClass("chkgm-weapons-cache")) do
		orderedObjectives[#orderedObjectives + 1] = ent
	end
	table.sort(orderedObjectives, function(first, second)
		local firstID = first:GetObjectiveID()
		local secondID = second:GetObjectiveID()
		if firstID == secondID then
			return first:EntIndex() < second:EntIndex()
		end
		return firstID < secondID
	end)

	for _, ent in ipairs(orderedObjectives) do
		SaveEntity(ent)
	end
	for _, ent in ipairs(ents.FindByClass("chkgm-spawnpoint")) do
		SaveEntity(ent)
	end
	for _, ent in ipairs(ents.FindByClass("chkgm-ammo-crate")) do
		SaveEntity(ent)
	end
	for _, class in ipairs(serializableMapEntityClasses) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			SaveEntity(ent)
		end
	end

	local json = util.TableToJSON({
		map = game.GetMap(),
		entities = entities
	}, true)
	if not isstring(json) or json == "" then
		print("Failed to encode scenario: " .. scenario_name)
		return
	end

	file.CreateDir("scenarios")
	local path = "scenarios/" .. scenario_name .. ".json"
	file.Write(path, json)

	if file.Read(path, "DATA") ~= json then
		print("Failed to write scenario: " .. scenario_name)
		return
	end

	print("Saved scenario " .. scenario_name .. " with " .. savedEntityCount .. " entities")
	return true
end

function DeleteScenario(scenario_name)
	if not isstring(scenario_name) or not string.match(scenario_name, "^[%w_-]+$") then
		print("Invalid scenario name")
		return
	end

	local path = "scenarios/" .. scenario_name .. ".json"
	if not file.Exists(path, "DATA") then
		print("Scenario file not found: " .. scenario_name)
		return
	end

	file.Delete(path)
	print("Deleted scenario " .. scenario_name)
end

function ListScenarios()
	local scenarios = GetScenarioNames()
	if #scenarios == 0 then
		print("No scenarios found.")
		return
	end

	print("Available scenarios:")
	for _, scenarioName in ipairs(scenarios) do
		print("- " .. scenarioName)
	end
end

function GM:Initialize()
	concommand.Add( "chk_scenario_load", function( ply, cmd, args, str )
		if GAMEMODE:InitializeScenario(args[1]) then
			RunConsoleCommand("chk_scenario", args[1])
		else
			if IsValid(ply) then
				ply:ChatPrint("Unable to load scenario. Check the server console for details.")
			end
		end
	end)

	concommand.Add( "chk_scenario_save", function( ply, cmd, args, str )
		SaveScenario(args[1])
	end)

	concommand.Add("chk_scenario_delete", function( ply, cmd, args, str )
		DeleteScenario(args[1])
	end)

	concommand.Add("chk_scenario_list", function( ply, cmd, args, str )
		ListScenarios()
	end)
end