local function GetGmaScenarioDirectory()
	local gamemodeName = engine.ActiveGamemode()
	if not isstring(gamemodeName) or not string.match(gamemodeName, "^[%w_-]+$") then return end
	return "gamemodes/" .. gamemodeName .. "/gamemode/scenarios/"
end

local function ReadScenarioDocument(scenarioName)
	if not isstring(scenarioName) or not string.match(scenarioName, "^[%w_-]+$") then return end

	for _, searchPath in ipairs({"DATA", "GAME"}) do
		for _, extension in ipairs({"json", "txt"}) do
			local path = "scenarios/" .. scenarioName .. "." .. extension
			if file.Exists(path, searchPath) then
				local scenario = util.JSONToTable(file.Read(path, searchPath) or "")
				if istable(scenario) then return scenario end
			end
		end
	end

	local staticPath = "data_static/scenarios/" .. scenarioName .. ".json"
	if file.Exists(staticPath, "GAME") then
		local scenario = util.JSONToTable(file.Read(staticPath, "GAME") or "")
		if istable(scenario) then return scenario end
	end

	local gmaScenarioDirectory = GetGmaScenarioDirectory()
	local gmaScenarioPath = gmaScenarioDirectory and (gmaScenarioDirectory .. scenarioName .. ".lua")
	if gmaScenarioPath and file.Exists(gmaScenarioPath, "GAME") then
		local scenario = include("scenarios/" .. scenarioName .. ".lua")
		if istable(scenario) then return scenario end
		print("GMA scenario " .. scenarioName .. " did not return a table")
	end
end

function GetScenarioNames()
	local scenarioNames = {}
	local found = {}
	for _, searchPath in ipairs({"DATA", "GAME"}) do
		for _, extension in ipairs({"json", "txt"}) do
			local files = file.Find("scenarios/*." .. extension, searchPath)
			for _, fileName in ipairs(files) do
				local scenarioName = string.StripExtension(fileName)
				if not found[scenarioName] then
					found[scenarioName] = true
					scenarioNames[#scenarioNames + 1] = scenarioName
				end
			end
		end
	end

	for _, fileName in ipairs(file.Find("data_static/scenarios/*.json", "GAME")) do
		local scenarioName = string.StripExtension(fileName)
		if not found[scenarioName] and string.match(scenarioName, "^[%w_-]+$") then
			found[scenarioName] = true
			scenarioNames[#scenarioNames + 1] = scenarioName
		end
	end

	local gmaScenarioDirectory = GetGmaScenarioDirectory()
	if gmaScenarioDirectory then
		for _, fileName in ipairs(file.Find(gmaScenarioDirectory .. "*.lua", "GAME")) do
			local scenarioName = string.StripExtension(fileName)
			if not found[scenarioName] and string.match(scenarioName, "^[%w_-]+$") then
				found[scenarioName] = true
				scenarioNames[#scenarioNames + 1] = scenarioName
			end
		end
	end

	table.sort(scenarioNames)
	return scenarioNames
end

function GetScenarioMap(scenarioName)
	local scenario = ReadScenarioDocument(scenarioName)
	if not scenario
		or not isstring(scenario.map)
		or not string.match(scenario.map, "^[%w_-]+$")
		or not file.Exists("maps/" .. scenario.map .. ".bsp", "GAME") then
		return nil
	end
	return scenario.map
end

function PrepareScenario(scenario_name, allowDifferentMap)
	local scenario = ReadScenarioDocument(scenario_name)
	if not scenario then
		print("Scenario not found or contains invalid data: " .. tostring(scenario_name))
		return nil
	end

	if not GetScenarioMap(scenario_name) then
		print("Scenario " .. scenario_name .. " has no map metadata and cannot be loaded")
		return nil
	end
	if not allowDifferentMap and scenario.map ~= game.GetMap() then
		print("Scenario " .. scenario_name .. " was created for map " .. scenario.map
			.. "; the current map is " .. game.GetMap())
		return nil
	end
	if not istable(scenario.entities) then
		print("Scenario " .. scenario_name .. " has invalid entity data")
		return nil
	end

	local classAliases = {
		objective = "chkgm-objective",
		["weapon-cache"] = "chkgm-weapons-cache",
		["weapons-cache"] = "chkgm-weapons-cache",
		["chkgm-objective"] = "chkgm-objective",
		["chkgm-weapons-cache"] = "chkgm-weapons-cache",
		["chkgm-spawnpoint"] = "chkgm-spawnpoint",
		["ammo-crate"] = "chkgm-ammo-crate",
		["chkgm-ammo-crate"] = "chkgm-ammo-crate",
		edit_fog = "edit_fog",
		edit_sky = "edit_sky",
		edit_sun = "edit_sun"
	}
	local entitiesToCreate = {}

	for index, item in ipairs(scenario.entities) do
		if not istable(item)
			or not isstring(item.class)
			or not istable(item.position)
			or not istable(item.angle) then
			print("Invalid entity data in scenario " .. scenario_name .. " at index " .. index)
			return nil
		end

		local class = classAliases[item.class]
		local position = item.position
		local angle = item.angle
		if not class
			or not isnumber(position.x) or not isnumber(position.y) or not isnumber(position.z)
			or not isnumber(angle.p) or not isnumber(angle.y) or not isnumber(angle.r)
			or (item.radius ~= nil and not isnumber(item.radius))
			or (item.patrolRadius ~= nil and not isnumber(item.patrolRadius)) then
			print("Invalid entity data in scenario " .. scenario_name .. " at index " .. index)
			return nil
		end

		local keyValues = item.keyValues
		if keyValues ~= nil then
			if (class ~= "edit_fog" and class ~= "edit_sky" and class ~= "edit_sun")
				or not istable(keyValues) then
				print("Invalid entity data in scenario " .. scenario_name .. " at index " .. index)
				return nil
			end
			for key, value in pairs(keyValues) do
				if not isstring(key)
					or (not isstring(value) and not isnumber(value) and not isbool(value)) then
					print("Invalid entity data in scenario " .. scenario_name .. " at index " .. index)
					return nil
				end
			end
		end

		entitiesToCreate[#entitiesToCreate + 1] = {
			class = class,
			position = Vector(position.x, position.y, position.z),
			angle = Angle(angle.p, angle.y, angle.r),
			radius = item.radius,
			patrolRadius = item.patrolRadius,
			keyValues = keyValues
		}
	end

	return entitiesToCreate
end

function LoadScenario(scenario_name, preparedScenario)
	local entitiesToCreate = preparedScenario or PrepareScenario(scenario_name)
	if not entitiesToCreate then return false end

	local createdEntities = {}
	for _, item in ipairs(entitiesToCreate) do
		local ent = ents.Create(item.class)
		if not IsValid(ent) then
			print("Failed to create entity " .. item.class .. " from scenario " .. scenario_name)
			for _, created in ipairs(createdEntities) do
				if IsValid(created) then created:Remove() end
			end
			return false
		end

		for key, value in pairs(item.keyValues or {}) do
			ent:SetKeyValue(key, tostring(value))
		end
		ent:SetPos(item.position)
		ent:SetAngles(item.angle)
		ent:Spawn()
		ent:Activate()
		if item.keyValues ~= nil then
			ent.ChkScenarioEntity = true
		end
		createdEntities[#createdEntities + 1] = ent

		if item.radius ~= nil and ent.SetRadius then
			ent:SetRadius(item.radius)
		end
		if item.patrolRadius ~= nil and ent.SetPatrolRadius then
			ent:SetPatrolRadius(item.patrolRadius)
		end
	end

	return true
end
