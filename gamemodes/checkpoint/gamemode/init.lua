AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )

CreateConVar("chk_obj_viewcapture", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED)
CreateConVar("chk_obj_viewpatrol", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED)
CreateConVar("chk_scenario", "", FCVAR_ARCHIVE)

include( "shared.lua" )
include( "cmds.lua" )
include( "loadout.lua" )
include( "sandbox_hooks.lua" )
include( "entities.lua" )

util.AddNetworkString("ChkPlayCounterattackMusic")
util.AddNetworkString("ChkScenarioResult")
util.AddNetworkString("ChkScenarioVoteStart")
util.AddNetworkString("ChkScenarioVote")
util.AddNetworkString("ChkScenarioVoteUpdate")
util.AddNetworkString("ChkLoadoutMenu")
util.AddNetworkString("ChkLoadoutSelect")

local currentObjectiveID = 0
local currentObjectivePos = Vector(0, 0, 0)
local objectiveEntities = {}
local remainingWaves = 0;
local initialWaveSpawned = false
local scenarioStartupReady = false
local objectiveTransitionPending = false
local gameFinished = false
local scenarioSelectionPending = false
local scenarioLoading = false
local scenarioDeinitializing = false
local activeScenarioVote
local currentScenarioName
local loadoutPhaseActive = false
local pendingLoadoutPlayers = {}
local loadoutConfirmedThisPhase = false
local lastCapturedObjective
local activeCounterattack
local captureSampleTime = CurTime()
local captureSampleObjective
local missingObjectiveTimeConvarLogged = false
local missingObjectiveTimeLimitConvarLogged = false
local missingObjectiveWaveLimitConvarLogged = false

SetGlobalBool("chk_objective_timer_active", false)
SetGlobalFloat("chk_objective_time_end", 0)
SetGlobalBool("chk_gamemode_failed", false)

local function PlayCounterattackMusic(track)
	net.Start("ChkPlayCounterattackMusic")
	net.WriteString(track)
	net.Broadcast()
end

local function ShowScenarioResult(result, message)
	scenarioSelectionPending = true
	net.Start("ChkScenarioResult")
	net.WriteString(result)
	net.WriteString(message or "")
	net.Broadcast()
	timer.Simple(5, function()
		if gameFinished and scenarioSelectionPending then
			GAMEMODE:StartScenarioVote()
		end
	end)
end

local function GetObjectiveCaptureDuration()
	local convar = GetConVar("chk_objective_time")
	if not convar then
		if not missingObjectiveTimeConvarLogged then
			print("[Chk] Missing convar: chk_objective_time; using 20 seconds")
			missingObjectiveTimeConvarLogged = true
		end
		return 20
	end

	return math.max(convar:GetFloat(), 20)
end

local function GetObjectiveTimeLimit()
	local convar = GetConVar("chk_objective_time_limit")
	if not convar then
		if not missingObjectiveTimeLimitConvarLogged then
			print("[Chk] Missing convar: chk_objective_time_limit; using 15 minutes")
			missingObjectiveTimeLimitConvarLogged = true
		end
		return 15 * 60
	end

	return math.max(convar:GetFloat(), 0) * 60
end

local function IsEditModeEnabled()
	local convar = GetConVar("chk_editmode")
	return convar and convar:GetBool() or false
end

local function IsProgressionObjective(ent)
	if not IsValid(ent) then return false end

	local class = ent:GetClass()
	return class == "chkgm-objective" or class == "chkgm-weapons-cache"
end

local function UpdateCurrentObjective()
	local objective = objectiveEntities[currentObjectiveID]
	if IsProgressionObjective(objective) then
		currentObjectivePos = objective:GetPos()
	else
		currentObjectivePos = Vector(0, 0, 0)
	end

	SetGlobalInt("chk_current_objective_id", currentObjectiveID)
	SetGlobalVector("chk_current_objective_pos", currentObjectivePos)
end

local function GetObjectiveListIndex(startIndex)
	for index = startIndex, #objectiveEntities do
		local objective = objectiveEntities[index]
		if IsProgressionObjective(objective) then
			return index
		end
	end
end

local function StopObjectiveTimeLimit()
	timer.Remove("ChkObjectiveTimeLimit")
	SetGlobalBool("chk_objective_timer_active", false)
	SetGlobalFloat("chk_objective_time_end", 0)
end

local function StartObjectiveTimeLimit()
	StopObjectiveTimeLimit()

	local objective = objectiveEntities[currentObjectiveID]
	if IsEditModeEnabled()
		or gameFinished
		or scenarioLoading
		or scenarioDeinitializing
		or loadoutPhaseActive
		or objectiveTransitionPending
		or activeCounterattack
		or not IsProgressionObjective(objective) then
		return
	end

	local duration = GetObjectiveTimeLimit()
	SetGlobalFloat("chk_objective_time_end", CurTime() + duration)
	SetGlobalBool("chk_objective_timer_active", true)
	timer.Create("ChkObjectiveTimeLimit", duration, 1, function()
		if gameFinished
			or activeCounterattack
			or objectiveTransitionPending
			or objectiveEntities[currentObjectiveID] ~= objective then
			return
		end

		GAMEMODE:GamemodeFailed()
	end)
end

local function GetConfiguredClasses(convarName)
	local convar = GetConVar(convarName)
	if not convar then
		print("[Chk] Missing convar: " .. convarName)
		return {}
	end

	local classes = {}
	for class in string.gmatch(convar:GetString(), "%S+") do
		classes[#classes + 1] = class
	end
	return classes
end

local function GetSpawnPosition(objective)
	local radius = math.max(objective:GetPatrolRadius(), 0)
	local origin = objective:GetPos()
	local radiusSqr = radius * radius
	local nearbyAreas = navmesh.Find(origin, radius, 64, 64)
	local spawnPoints = {}

	for _, area in ipairs(nearbyAreas or {}) do
		for _ = 1, 8 do
			local point = area:GetRandomPoint()
			if point:DistToSqr(origin) <= radiusSqr then
				spawnPoints[#spawnPoints + 1] = point
			end
		end
	end

	if #spawnPoints > 0 then
		return table.Random(spawnPoints)
	end

	local nearestArea = navmesh.GetNearestNavArea(origin, 100000, 100000, false, false)
	if nearestArea then
		return nearestArea:GetClosestPointOnArea(origin)
	end

	print("[Chk] Cannot spawn enemy: no navigation mesh area is available")
	return nil
end

local function GiveConfiguredWeapon(npc, convarName)
	local weaponClasses = GetConfiguredClasses(convarName)
	if #weaponClasses == 0 then return end

	local weaponClass = table.Random(weaponClasses)
	npc:Give(weaponClass)
end

local function MoveNPCToObjective(npc, objective)
	if not IsValid(npc) or not npc:IsNPC() or not IsValid(objective) then return end

	npc:SetLastPosition(objective:GetPos())
	npc:SetSchedule(SCHED_FORCED_GO_RUN)
end

local function IsNPCAtCounterattackObjective(npc, objective)
	if not IsValid(npc) or not IsValid(objective) then return false end

	local radius = objective:GetClass() == "chkgm-objective"
		and math.max(objective:GetRadius(), 0)
		or 128
	return npc:GetPos():DistToSqr(objective:GetPos()) <= radius * radius
end

local function SetCounterattackPlayerRelationships(npc)
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:Alive() then
			npc:AddEntityRelationship(ply, D_HT, 99)
		end
	end
end

local function RestoreCounterattackPlayerRelationships()
	for _, npc in ipairs(ents.GetAll()) do
		if IsValid(npc) and npc:IsNPC() then
			npc.ChkCounterattackEngaged = nil
			for _, ply in ipairs(player.GetAll()) do
				if IsValid(ply) and ply:Alive() then
					npc:AddEntityRelationship(ply, D_HT, 99)
				end
			end
		end
	end
end

local function PrepareNPCForCounterattack(npc, objective)
	if not IsValid(npc) or not npc:IsNPC() or not IsValid(objective) then return end

	SetCounterattackPlayerRelationships(npc)
	npc.ChkCounterattackEngaged = false

	if npc.SetEnemy then
		npc:SetEnemy(NULL)
	end
	if npc.ClearEnemyMemory then
		npc:ClearEnemyMemory()
	end
	if npc.SetNPCState then
		npc:SetNPCState(NPC_STATE_ALERT)
	end
	npc:ClearSchedule()
	if not IsNPCAtCounterattackObjective(npc, objective) then
		MoveNPCToObjective(npc, objective)
	end
end

local function GetCurrentNPCCount()
	local count = 0
	for _, ent in ipairs(ents.GetAll()) do
		if ent:IsNPC() and ent:Health() > 0 then
			count = count + 1
		end
	end
	return count
end

local function GetMaximumNPCCount()
	local convar = GetConVar("chk_bots_max")
	if not convar then
		print("[Chk] Missing convar: chk_bots_max")
		return nil
	end

	return math.max(convar:GetInt(), 0)
end

local function SpawnNPC(class, objective, weaponConvar)
	if IsEditModeEnabled() or not IsValid(objective) then return end

	local maximumNPCs = GetMaximumNPCCount()
	if maximumNPCs == nil or GetCurrentNPCCount() >= maximumNPCs then return end

	local spawnPosition = GetSpawnPosition(objective)
	if not spawnPosition then return end

	local npc = ents.Create(class)
	if not IsValid(npc) then
		print("[Chk] Failed to create NPC class: " .. class)
		return
	end

	npc:SetPos(spawnPosition + Vector(0, 0, 64))
	local target = player.GetAll()[1]
	if IsValid(target) then
		local yaw = (target:GetPos() - npc:GetPos()):Angle().y
		npc:SetAngles(Angle(0, yaw, 0))
	end
	npc:Spawn()

	if not IsValid(npc) or not npc:IsNPC() then
		print("[Chk] Entity is not a valid NPC class: " .. class)
		if IsValid(npc) then npc:Remove() end
		return
	end

	npc:Activate()
	npc:DropToFloor()
	npc.ChkScenarioNPC = true

	GiveConfiguredWeapon(npc, weaponConvar)
	if activeCounterattack then
		PrepareNPCForCounterattack(npc, activeCounterattack.defendedObjective)
	end

	return npc
end

local function SpawnObjectiveWave(objective, count)
	if IsEditModeEnabled() or not IsValid(objective) then return end

	if remainingWaves <= 0 then
		print("[Chk] Objective wave limit reached; objective wave was not spawned")
		return
	end

	local maximumNPCs = GetMaximumNPCCount()
	if maximumNPCs == nil then return end

	local availableSlots = math.max(maximumNPCs - GetCurrentNPCCount(), 0)
	count = math.min(math.max(math.floor(count), 0), availableSlots)
	if count == 0 then return end

	local classes = GetConfiguredClasses("chk_enemy_classes")
	if #classes == 0 then
		print("[Chk] No enemy classes configured; objective wave was not spawned")
		return
	end

	local spawnedCount = 0
	for _ = 1, math.max(math.floor(count), 0) do
		if SpawnNPC(table.Random(classes), objective, "chk_enemy_weapons") then
			spawnedCount = spawnedCount + 1
		end
	end

	if spawnedCount > 0 then
		remainingWaves = remainingWaves - 1
	end
end

local function StopRespawnTimer()
	timer.Remove("ChkObjectiveRespawn")
end

function GM:GamemodeStop()
	for _, ent in ipairs(ents.GetAll()) do
		if ent:IsPlayer() then
			ent:Freeze(true)
		elseif ent:IsNPC() then
			ent:SetSchedule(SCHED_NPC_FREEZE)
		end
	end
end

function GM:RegisterLoadoutSelection(ply)
	if loadoutPhaseActive and IsValid(ply) then
		ply.chkLoadoutConfirmed = false
		pendingLoadoutPlayers[ply] = true
		ply:Freeze(true)
	end
end

local function CompleteLoadoutPhaseIfReady()
	if not loadoutPhaseActive or not loadoutConfirmedThisPhase or next(pendingLoadoutPlayers) then return end

	loadoutPhaseActive = false
	if initialWaveSpawned then
		StartObjectiveTimeLimit()
	end
end

function GM:ConfirmLoadoutSelection(ply)
	pendingLoadoutPlayers[ply] = nil
	loadoutConfirmedThisPhase = true
	if IsValid(ply) then
		ply:Freeze(false)
	end
	CompleteLoadoutPhaseIfReady()
end

hook.Add("PlayerDisconnected", "ChkLoadoutSelectionDisconnected", function(ply)
	pendingLoadoutPlayers[ply] = nil
	CompleteLoadoutPhaseIfReady()
end)

function GM:GamemodeFailed(message)
	if gameFinished then return end

	gameFinished = true
	objectiveTransitionPending = false
	remainingWaves = 0
	if activeCounterattack then
		RestoreCounterattackPlayerRelationships()
	end
	activeCounterattack = nil
	StopObjectiveTimeLimit()
	StopRespawnTimer()
	timer.Remove("ChkCounterattackDuration")
	timer.Remove("ChkCounterattackSpawn")
	timer.Remove("ChkCounterattackRespawn")
	timer.Remove("ChkCounterattackAlert")
	SetGlobalBool("chk_counterattack_active", false)
	SetGlobalFloat("chk_counterattack_end", 0)
	SetGlobalBool("chk_gamemode_failed", true)
	self:GamemodeStop()
	ShowScenarioResult("failed", message)
end

function GM:PlayerDeathThink() end

hook.Add("PlayerDeath", "ChkSpectateAlivePlayers", function(ply)
	local target
	for _, other in ipairs(player.GetAll()) do
		if other ~= ply and IsValid(other) and other:Alive() then
			target = other
			break
		end
	end

	if not IsValid(target) then
		GAMEMODE:GamemodeFailed()
		return
	end

	ply:Spectate(OBS_MODE_CHASE)
	ply:SpectateEntity(target)
end)

local function GetRespawnSpawnObjective()
	if not IsProgressionObjective(objectiveEntities[currentObjectiveID]) then return end

	local nextIndex = GetObjectiveListIndex(currentObjectiveID + 1)
	if nextIndex then
		return objectiveEntities[nextIndex]
	end

	for index = currentObjectiveID - 1, 1, -1 do
		local objective = objectiveEntities[index]
		if IsProgressionObjective(objective) then
			return objective
		end
	end
end

local function StartRespawnTimer()
	StopRespawnTimer()
	local enabled = GetConVar("chk_bots_respawn_enable")
	local interval = GetConVar("chk_bots_respawn_time")
	local count = GetConVar("chk_bots_objective")
	if IsEditModeEnabled()
		or gameFinished
		or remainingWaves <= 0
		or not IsProgressionObjective(objectiveEntities[currentObjectiveID])
		or not enabled
		or not enabled:GetBool()
		or not interval
		or not count then
		return
	end

	local delay = math.max(interval:GetFloat(), 1)
	timer.Create("ChkObjectiveRespawn", delay, 0, function()
		if IsEditModeEnabled()
			or gameFinished
			or remainingWaves <= 0
			or not IsProgressionObjective(objectiveEntities[currentObjectiveID]) then
			if remainingWaves <= 0 then
				StopRespawnTimer()
			end
			return
		end

		local spawnObjective = GetRespawnSpawnObjective()
		if IsProgressionObjective(spawnObjective) then
			SpawnObjectiveWave(spawnObjective, count:GetInt())
		end
	end)
end

local function FinishScenario()
	if gameFinished then return end

	gameFinished = true
	objectiveTransitionPending = false
	currentObjectiveID = 0
	remainingWaves = 0
	StopObjectiveTimeLimit()
	UpdateCurrentObjective()
	StopRespawnTimer()
	SetGlobalBool("chk_counterattack_active", false)
	SetGlobalFloat("chk_counterattack_end", 0)
	GAMEMODE:GamemodeStop()
	ShowScenarioResult("complete")
end

local function SetRemainingWavesForObjective()
	remainingWaves = 0
	local waveLimit = GetConVar("chk_bots_objective_waves")
	if not waveLimit then
		if not missingObjectiveWaveLimitConvarLogged then
			print("[Chk] Missing convar: chk_bots_objective_waves")
			missingObjectiveWaveLimitConvarLogged = true
		end
		return
	end

	remainingWaves = math.max(waveLimit:GetInt(), 1)
end

local function AdvanceToObjective(index)
	objectiveTransitionPending = false
	currentObjectiveID = index
	SetRemainingWavesForObjective()
	UpdateCurrentObjective()

	local objective = objectiveEntities[currentObjectiveID]
	if IsProgressionObjective(objective) then
		local count = GetConVar("chk_bots_objective")
		SpawnObjectiveWave(objective, count and count:GetInt() or 20)
		StartRespawnTimer()
		StartObjectiveTimeLimit()
	end
end

local function CompleteCounterattack(counterattack)
	if activeCounterattack ~= counterattack then return end
	if IsEditModeEnabled() then
		timer.Simple(1, function()
			CompleteCounterattack(counterattack)
		end)
		return
	end

	RestoreCounterattackPlayerRelationships()
	activeCounterattack = nil
	timer.Remove("ChkCounterattackDuration")
	timer.Remove("ChkCounterattackSpawn")
	timer.Remove("ChkCounterattackRespawn")
	timer.Remove("ChkCounterattackAlert")
	SetGlobalBool("chk_counterattack_active", false)
	SetGlobalFloat("chk_counterattack_end", 0)

	if counterattack.isFinal then
		FinishScenario()
	else
		AdvanceToObjective(counterattack.nextObjectiveIndex)
	end
end

local function StartCounterattack(objective, duration, isFinal, nextObjectiveIndex, spawnOrigin)
	if IsEditModeEnabled() or not IsValid(objective) then return false end

	local bossClasses = GetConfiguredClasses("chk_enemy_boss")
	if #bossClasses == 0 then
		print("[Chk] No boss classes configured; counterattack was skipped")
		return false
	end

	StopObjectiveTimeLimit()

	local counterattack = {
		defendedObjective = objectiveEntities[currentObjectiveID],
		captureProgress = 0,
		captureSampleTime = CurTime(),
		bosses = {},
		bossClasses = bossClasses,
		nextBossIndex = 1,
		defeatedBosses = 0,
		bossKillTarget = math.max(math.floor(math.max(duration, 0) / 30), 1),
		isFinal = isFinal,
		nextObjectiveIndex = nextObjectiveIndex,
		spawnOrigin = spawnOrigin or objective
	}
	activeCounterattack = counterattack
	if IsValid(counterattack.defendedObjective) then
		counterattack.defendedObjective:SetNW2Float("chk_counterattack_capture_progress", 0)
	end
	objectiveTransitionPending = true

	local endTime = CurTime() + duration
	SetGlobalBool("chk_counterattack_active", true)
	SetGlobalFloat("chk_counterattack_end", endTime)

	local function SpawnNextBoss()
		if IsEditModeEnabled() or activeCounterattack ~= counterattack then return end

		local class = counterattack.bossClasses[counterattack.nextBossIndex]
		counterattack.nextBossIndex = counterattack.nextBossIndex % #counterattack.bossClasses + 1
		local boss = SpawnNPC(class, counterattack.spawnOrigin, "chk_enemy_boss_weapon")
		if IsValid(boss) then
			counterattack.bosses[boss] = true
		end
	end
	counterattack.spawnNextBoss = SpawnNextBoss

	SpawnNextBoss()
	if activeCounterattack ~= counterattack then return true end

	timer.Create("ChkCounterattackDuration", math.max(duration, 0), 1, function()
		CompleteCounterattack(counterattack)
	end)
	timer.Create("ChkCounterattackAlert", 1, 0, function()
		if IsEditModeEnabled() or activeCounterattack ~= counterattack then return end
		for _, npc in ipairs(ents.GetAll()) do
			if IsValid(npc) and npc:IsNPC() then
				local enemy = npc:GetEnemy()
				if IsValid(enemy) and enemy:IsPlayer() then
					npc.ChkCounterattackEngaged = true
				end

				if not npc.ChkCounterattackEngaged
					and not IsNPCAtCounterattackObjective(npc, counterattack.defendedObjective)
					and npc:GetCurrentSchedule() ~= SCHED_FORCED_GO_RUN then
					MoveNPCToObjective(npc, counterattack.defendedObjective)
				end
			end
		end
	end)

	for _, npc in ipairs(ents.GetAll()) do
		if npc:IsNPC() then
			PrepareNPCForCounterattack(npc, counterattack.defendedObjective)
		end
	end
	return true
end

hook.Add("OnNPCKilled", "ChkCounterattackBossKilled", function(npc)
	local counterattack = activeCounterattack
	if not counterattack or not counterattack.bosses[npc] then return end

	counterattack.bosses[npc] = nil
	counterattack.defeatedBosses = counterattack.defeatedBosses + 1
	if counterattack.defeatedBosses >= counterattack.bossKillTarget then
		CompleteCounterattack(counterattack)
		return
	end

	timer.Create("ChkCounterattackRespawn", 0, 1, counterattack.spawnNextBoss)
end)

local function BeginObjectiveCounterattack(capturedObjective)
	local nextIndex = GetObjectiveListIndex(currentObjectiveID + 1)
	if not nextIndex then
		local allowFinal = GetConVar("chk_counterattack_final_allow")
		if allowFinal and allowFinal:GetBool() then
			local duration = GetConVar("chk_counterattack_final_time")
			local spawnOrigin = lastCapturedObjective or capturedObjective
			if StartCounterattack(capturedObjective, duration and duration:GetFloat() or 180, true, nil, spawnOrigin) then
				PrintMessage(HUD_PRINTTALK, "Final counterattack!")
				PlayCounterattackMusic("finalcounterattack.wav")
				return
			end
		end
		FinishScenario()
		return
	end

	lastCapturedObjective = capturedObjective
	local chanceConVar = GetConVar("chk_counterattack_chance")
	local chance = chanceConVar and math.Clamp(chanceConVar:GetFloat(), 0, 100) or 0
	if chance > 0 and math.Rand(0, 100) <= chance then
		local duration = GetConVar("chk_counterattack_time")
		if StartCounterattack(objectiveEntities[nextIndex], duration and duration:GetFloat() or 60, false, nextIndex) then
			PrintMessage(HUD_PRINTTALK, "Counterattack!")
			PlayCounterattackMusic("counterattack" .. math.random(1, 4) .. ".wav")
			return
		end
	end

	AdvanceToObjective(nextIndex)
end

local function StartInitialWave()
	if not scenarioStartupReady or IsEditModeEnabled() or initialWaveSpawned or gameFinished then return end

	local firstIndex = GetObjectiveListIndex(1)
	if not firstIndex then return end
	initialWaveSpawned = true
	currentObjectiveID = firstIndex
	SetRemainingWavesForObjective()
	UpdateCurrentObjective()

	local count = GetConVar("chk_bots_objective")
	SpawnObjectiveWave(objectiveEntities[firstIndex], count and count:GetInt() or 20)
	StartRespawnTimer()
	StartObjectiveTimeLimit()
end

function GM:DeinitializeScenario()
	local wasLoading = scenarioLoading
	scenarioLoading = true
	scenarioDeinitializing = true

	timer.Remove("ChkScenarioVoteEnd")
	activeScenarioVote = nil
	StopObjectiveTimeLimit()
	StopRespawnTimer()
	timer.Remove("ChkCounterattackDuration")
	timer.Remove("ChkCounterattackSpawn")
	timer.Remove("ChkCounterattackRespawn")
	timer.Remove("ChkCounterattackAlert")
	if activeCounterattack then
		RestoreCounterattackPlayerRelationships()
	end
	activeCounterattack = nil

	for _, ent in ipairs(ents.GetAll()) do
		if ent:IsPlayer() then
			ent:Freeze(false)
			ent:SetNW2Entity("chk_inside_objective", NULL)
		elseif ent:IsNPC() and ent.ChkScenarioNPC then
			ent:Remove()
		elseif ent:IsNPC() then
			ent:ClearSchedule()
		elseif ent.ChkScenarioNPC
			or ent.ChkScenarioEntity
			or ent:GetClass() == "chkgm-objective"
			or ent:GetClass() == "chkgm-weapons-cache"
			or ent:GetClass() == "chkgm-spawnpoint"
			or ent:GetClass() == "chkgm-ammo-crate" then
			ent:Remove()
		end
	end

	objectiveEntities = {}
	currentObjectiveID = 0
	currentObjectivePos = Vector(0, 0, 0)
	remainingWaves = 0
	initialWaveSpawned = false
	objectiveTransitionPending = false
	lastCapturedObjective = nil
	captureSampleObjective = nil
	currentScenarioName = nil
	gameFinished = false
	scenarioSelectionPending = false
	loadoutPhaseActive = false
	pendingLoadoutPlayers = {}
	loadoutConfirmedThisPhase = false
	SetGlobalBool("chk_gamemode_failed", false)
	SetGlobalBool("chk_counterattack_active", false)
	SetGlobalFloat("chk_counterattack_end", 0)
	UpdateCurrentObjective()

	scenarioDeinitializing = false
	scenarioLoading = wasLoading
end

function GM:InitializeScenario(scenarioName, preparedScenario)
	if scenarioLoading then return false end

	local scenarioEntities = preparedScenario or PrepareScenario(scenarioName)
	if not scenarioEntities then return false end

	local wasSelectionPending = scenarioSelectionPending
	scenarioLoading = true
	self:DeinitializeScenario()
	scenarioLoading = true

	if not LoadScenario(scenarioName, scenarioEntities) then
		gameFinished = true
		scenarioSelectionPending = wasSelectionPending
		scenarioLoading = false
		self:GamemodeStop()
		return false
	end

	gameFinished = false
	scenarioSelectionPending = false
	initialWaveSpawned = false
	scenarioStartupReady = true
	currentScenarioName = scenarioName
	loadoutPhaseActive = true
	pendingLoadoutPlayers = {}
	loadoutConfirmedThisPhase = false
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) then
			ply.chkLoadoutConfirmed = false
			if not ply:Alive() then
				ply:Spawn()
			else
				self:PlacePlayerAtSpawnPoint(ply)
			end
		end
	end
	SendWeaponSelection()
	SetGlobalBool("chk_gamemode_failed", false)
	scenarioLoading = false
	timer.Simple(0, StartInitialWave)
	return true
end

local function GetScenariosForMap(mapName)
	local scenarios = {}
	for _, scenarioName in ipairs(GetScenarioNames()) do
		if GetScenarioMap(scenarioName) == mapName and PrepareScenario(scenarioName) then
			scenarios[#scenarios + 1] = scenarioName
		end
	end
	table.sort(scenarios)
	return scenarios
end

local function GetAvailableScenarios()
	local scenarios = {}
	for _, scenarioName in ipairs(GetScenarioNames()) do
		local mapName = GetScenarioMap(scenarioName)
		if mapName and PrepareScenario(scenarioName, true) then
			scenarios[#scenarios + 1] = { name = scenarioName, map = mapName }
		end
	end
	table.sort(scenarios, function(first, second)
		if first.map == second.map then
			return first.name < second.name
		end
		return first.map < second.map
	end)
	return scenarios
end

local function BroadcastScenarioVoteUpdate()
	if not activeScenarioVote then return end

	local counts = {}
	for _, candidate in ipairs(activeScenarioVote.scenarios) do
		counts[candidate.name] = 0
	end
	for _, scenarioName in pairs(activeScenarioVote.votes) do
		counts[scenarioName] = (counts[scenarioName] or 0) + 1
	end

	net.Start("ChkScenarioVoteUpdate")
	net.WriteUInt(#activeScenarioVote.scenarios, 8)
	for _, candidate in ipairs(activeScenarioVote.scenarios) do
		net.WriteString(candidate.name)
		net.WriteUInt(counts[candidate.name] or 0, 8)
	end
	net.Broadcast()
end

local function FinishScenarioVote()
	if not activeScenarioVote then return end

	local voteCounts = {}
	local highestVoteCount = 0
	for _, candidate in ipairs(activeScenarioVote.scenarios) do
		voteCounts[candidate.name] = 0
	end
	for _, scenarioName in pairs(activeScenarioVote.votes) do
		voteCounts[scenarioName] = (voteCounts[scenarioName] or 0) + 1
	end
	for _, count in pairs(voteCounts) do
		highestVoteCount = math.max(highestVoteCount, count)
	end

	local winners = {}
	for _, candidate in ipairs(activeScenarioVote.scenarios) do
		if voteCounts[candidate.name] == highestVoteCount then
			winners[#winners + 1] = candidate
		end
	end

	local winner = table.Random(winners)
	activeScenarioVote = nil
	timer.Remove("ChkScenarioVoteEnd")
	GAMEMODE:DeinitializeScenario()
	RunConsoleCommand("chk_scenario", winner.name)
	GAMEMODE:GamemodeStop()
	timer.Simple(1, function()
		RunConsoleCommand("changelevel", winner.map)
	end)
end

function GM:StartScenarioVote()
	if not gameFinished or not scenarioSelectionPending or activeScenarioVote then return end

	local scenarios = GetAvailableScenarios()
	if #scenarios == 0 then
		scenarioSelectionPending = false
		GAMEMODE:DeinitializeScenario()
		RunConsoleCommand("chk_editmode", "1")
		print("[Chk] No valid scenarios are available to vote for. Edit mode enabled.")
		PrintMessage(HUD_PRINTTALK, "[Checkpoint] No valid scenarios are available to vote for. Edit mode enabled.")
		return
	end

	while #scenarios > 255 do
		table.remove(scenarios)
	end

	activeScenarioVote = {
		scenarios = scenarios,
		votes = {},
		endTime = CurTime() + 60
	}
	scenarioSelectionPending = false

	net.Start("ChkScenarioVoteStart")
	net.WriteFloat(activeScenarioVote.endTime)
	net.WriteUInt(#scenarios, 8)
	for _, candidate in ipairs(scenarios) do
		net.WriteString(candidate.name)
		net.WriteString(candidate.map)
	end
	net.Broadcast()
	BroadcastScenarioVoteUpdate()

	timer.Create("ChkScenarioVoteEnd", 60, 1, function()
		FinishScenarioVote()
	end)
end

net.Receive("ChkScenarioVote", function(_, ply)
	if not activeScenarioVote or CurTime() >= activeScenarioVote.endTime or not IsValid(ply) then return end

	local scenarioName = net.ReadString()
	for _, candidate in ipairs(activeScenarioVote.scenarios) do
		if candidate.name == scenarioName then
			local voterID = ply:UserID()
			local hadAlreadyVoted = activeScenarioVote.votes[voterID] ~= nil
			activeScenarioVote.votes[voterID] = scenarioName
			BroadcastScenarioVoteUpdate()
			if not hadAlreadyVoted and table.Count(activeScenarioVote.votes) >= #player.GetAll() then
				FinishScenarioVote()
			end
			return
		end
	end
end)

hook.Add("PlayerDisconnected", "ChkRemoveScenarioVote", function(ply)
	if not activeScenarioVote then return end
	if activeScenarioVote.votes[ply:UserID()] then
		activeScenarioVote.votes[ply:UserID()] = nil
		BroadcastScenarioVoteUpdate()
	end
end)

cvars.AddChangeCallback("chk_editmode", function(_, _, newValue)
	if tonumber(newValue) ~= 0 then
		StopObjectiveTimeLimit()
		StopRespawnTimer()
		return
	end

	timer.Simple(0, function()
		StartInitialWave()
		if initialWaveSpawned then
			StartRespawnTimer()
			StartObjectiveTimeLimit()
		end
	end)
end, "ChkEditModeSpawning")

function RegisterObjectiveEntity(ent)
	objectiveEntities[#objectiveEntities + 1] = ent
	ent:SetObjectiveID(#objectiveEntities)

	if currentObjectiveID == 0 and IsProgressionObjective(ent) then
		currentObjectiveID = ent:GetObjectiveID()
	end

	UpdateCurrentObjective()
	timer.Simple(0, StartInitialWave)
end

function UnregisterObjectiveEntity(ent)
	local removedID = ent:GetObjectiveID()
	local wasCurrentObjective = removedID == currentObjectiveID
	for index, objective in ipairs(objectiveEntities) do
		if objective == ent then
			table.remove(objectiveEntities, index)
			break
		end
	end

	for index, objective in ipairs(objectiveEntities) do
		if IsValid(objective) then
			objective:SetObjectiveID(index)
		end
	end

	if removedID < currentObjectiveID then
		currentObjectiveID = currentObjectiveID - 1
	elseif removedID == currentObjectiveID then
		currentObjectiveID = math.min(removedID, #objectiveEntities + 1)
		while currentObjectiveID <= #objectiveEntities do
			local objective = objectiveEntities[currentObjectiveID]
			if IsProgressionObjective(objective) then
				break
			end
			currentObjectiveID = currentObjectiveID + 1
		end
	end

	UpdateCurrentObjective()
	if wasCurrentObjective then
		StartObjectiveTimeLimit()
	end
end

function GM:Tick()
	local now = CurTime()
	if gameFinished then return end

	local entities = ents.GetAll()
	local players = {}
	local livingNPCs = {}
	for _, ent in ipairs(entities) do
		if ent:IsPlayer() then
			players[#players + 1] = ent
		elseif ent:IsNPC() and ent:Health() > 0 then
			livingNPCs[#livingNPCs + 1] = ent
		end
	end

	local counterattack = activeCounterattack
	if counterattack then
		local target = counterattack.defendedObjective
		local npcInsideObjective = false
		if not IsEditModeEnabled()
			and IsValid(target)
			and target:GetClass() == "chkgm-objective" then
			local radius = math.max(target:GetRadius(), 0)
			local radiusSqr = radius * radius
			for _, npc in ipairs(livingNPCs) do
				if npc:GetPos():DistToSqr(target:GetPos()) <= radiusSqr then
					npcInsideObjective = true
					break
				end
			end
		end

		local elapsed = math.max(now - counterattack.captureSampleTime, 0)
		counterattack.captureSampleTime = now
		if npcInsideObjective then
			counterattack.captureProgress = math.min(
				counterattack.captureProgress + elapsed * 100 / GetObjectiveCaptureDuration(),
				100
			)
			if IsValid(target) then
				target:SetNW2Float("chk_counterattack_capture_progress", counterattack.captureProgress)
			end
			if counterattack.captureProgress >= 100 then
				GAMEMODE:GamemodeFailed(ObjectiveName(target:GetObjectiveID()) .. " was lost")
				return
			end
		end
	end

	local objective = objectiveEntities[currentObjectiveID]
	local insidePlayers = {}
	local playersInsideObjective = {}
	if IsValid(objective) and objective:GetClass() == "chkgm-objective" then
		local radius = math.max(objective:GetRadius(), 0)
		local radiusSqr = radius * radius

		for _, ply in ipairs(players) do
			if ply:GetPos():DistToSqr(objective:GetPos()) <= radiusSqr then
				insidePlayers[#insidePlayers + 1] = ply
				playersInsideObjective[ply] = true
			end
		end
	end

	local canCapture = not IsEditModeEnabled()
		and not objectiveTransitionPending
		and IsValid(objective)
		and objective:GetClass() == "chkgm-objective"
		and #insidePlayers > 0
	local elapsed = 0
	if canCapture then
		if captureSampleObjective == objective then
			elapsed = math.max(now - captureSampleTime, 0)
		end
		captureSampleObjective = objective
	else
		captureSampleObjective = nil
	end
	captureSampleTime = now

	for _, ply in ipairs(players) do
		local insideObjective = playersInsideObjective[ply] and objective or NULL
		if ply:GetNW2Entity("chk_inside_objective") ~= insideObjective then
			ply:SetNW2Entity("chk_inside_objective", insideObjective)
			if IsValid(insideObjective) then
				ply:ChatPrint("You are inside objective " .. ObjectiveName(insideObjective:GetObjectiveID()) .. ".")
			end
		end
	end

	if canCapture then
		objective.Capturers = objective.Capturers or {}
		for _, ply in ipairs(insidePlayers) do
			objective.Capturers[ply:UserID()] = ply:Nick()
		end

		local progress = math.min(objective:GetScore() + elapsed * 100 / GetObjectiveCaptureDuration(), 100)
		objective:SetScore(progress)
		if progress >= 100 then
			hook.Run("CheckpointObjectiveCompleted", objective)
		end
	end
end

hook.Add("CheckpointObjectiveCompleted", "ChkAdvanceCompletedObjective", function(objective)
	if IsEditModeEnabled()
		or gameFinished
		or objectiveTransitionPending
		or objective ~= objectiveEntities[currentObjectiveID] then
		return
	end

	if objective:GetClass() == "chkgm-objective" then
		local capturerNames = {}
		for _, name in pairs(objective.Capturers or {}) do
			capturerNames[#capturerNames + 1] = name
		end
		table.sort(capturerNames)
		local capturerList = #capturerNames > 0 and table.concat(capturerNames, " + ") or "Unknown"
		PrintMessage(HUD_PRINTTALK, capturerList .. " captured objective " .. ObjectiveName(objective:GetObjectiveID()) .. ".")
	end

	StopObjectiveTimeLimit()
	objectiveTransitionPending = true
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and not ply:Alive() then
			ply:Spawn()
		end
	end
	BeginObjectiveCounterattack(objective)
end)

hook.Add("InitPostEntity", "ChkLoadStartupScenario", function()
	timer.Simple(0, function()
		local scenarioConVar = GetConVar("chk_scenario")
		local scenario = scenarioConVar and scenarioConVar:GetString() or ""
		if scenario ~= "" then
			if not GAMEMODE:InitializeScenario(scenario) then
				print("[Chk] Configured scenario is invalid for this map; trying a compatible scenario")
			end
		end

		if not currentScenarioName then
			local compatibleScenarios = GetScenariosForMap(game.GetMap())
			local loadedScenario = false
			for _, compatibleScenario in ipairs(compatibleScenarios) do
				if GAMEMODE:InitializeScenario(compatibleScenario) then
					loadedScenario = true
					break
				end
			end
			if not loadedScenario then
				RunConsoleCommand("chk_editmode", "1")
				print("[Chk] No valid scenario was found for map " .. game.GetMap() .. "; edit mode enabled")
				PrintMessage(HUD_PRINTTALK, "[Checkpoint] No valid scenario was found for this map. Edit mode enabled.")
			end
		end

		scenarioStartupReady = true
		StartInitialWave()
	end)
end)

hook.Add("PlayerInitialSpawn", "ChkSendLoadoutMenu", function(ply)
	timer.Simple(1, function()
		if IsValid(ply) and currentScenarioName then
			SendWeaponSelection(ply)
		end
	end)
end)
