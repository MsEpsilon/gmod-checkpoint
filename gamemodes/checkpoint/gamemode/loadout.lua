function GM:PlacePlayerAtSpawnPoint(ply)
	if not IsValid(ply) then return false end
	local spawnpoints = ents.FindByClass("chkgm-spawnpoint")
	local spawnpoint = table.Random(spawnpoints)
	if not IsValid(spawnpoint) then return false end

	ply:SetPos(spawnpoint:GetPos())
	ply:SetEyeAngles(spawnpoint:GetAngles())
	return true
end

function GM:PlayerSpawn(ply, transition)
	self.BaseClass.PlayerSpawn(self, ply, transition)

	ply:SetupHands()
	ply:SetArmor(100)
	self:PlacePlayerAtSpawnPoint(ply)
end

local ammoCrateCooldown = 60

function GM:GetAmmoCrateCooldownRemaining(ply)
	return math.max((ply.chkNextAmmoCrateUse or 0) - CurTime(), 0)
end

function GM:StartAmmoCrateCooldown(ply)
	ply.chkNextAmmoCrateUse = CurTime() + ammoCrateCooldown
end

local function GetLoadoutSet(id)
	local conVarName = id <= 5
		and string.format("chk_weapon_set%d", id)
		or string.format("chk_weapon_ent%d", id - 5)
	local loadoutConVar = GetConVar(conVarName)
    if not loadoutConVar then return {} end

    local classes = {}
    for class in string.gmatch(loadoutConVar:GetString(), "%S+") do
    	classes[#classes + 1] = class
    end
    return classes
end

local function GetSelectedLoadoutClass(ply, id, classes)
    local selected = ply.chkLoadoutSelection and ply.chkLoadoutSelection[id]
    if selected then
    	for _, class in ipairs(classes) do
    		if class == selected then return selected end
    	end
    end
    return classes[1]
end

function SendWeaponSelection(ply)
    local recipients = IsValid(ply) and {ply} or player.GetAll()
    for _, recipient in ipairs(recipients) do
    	GAMEMODE:RegisterLoadoutSelection(recipient)
    	net.Start("ChkLoadoutMenu")
    	for id = 1, 8 do
    		local classes = GetLoadoutSet(id)
    		net.WriteUInt(math.min(#classes, 255), 8)
    		for index = 1, math.min(#classes, 255) do
    			net.WriteString(classes[index])
    		end
    		net.WriteString(GetSelectedLoadoutClass(recipient, id, classes) or "")
    	end
    	net.Send(recipient)
    end
end

local function GiveConvarWeapon(ply, id)
	if id > 5 then return end
    local classes = GetLoadoutSet(id)
    local class = GetSelectedLoadoutClass(ply, id, classes)
    if not class then return end

    local weapon = ply:Give(class)
    if not IsValid(weapon) then return end

	local ammoConVar = GetConVar(string.format("chk_weapon_set%d_ammo", id))
	if not ammoConVar then return end

	local magazines = math.max(ammoConVar:GetInt(), 0)
	local primaryAmmoType = weapon:GetPrimaryAmmoType()
	local primaryClipSize = weapon:GetMaxClip1()
	if primaryAmmoType >= 0 and primaryClipSize > 0 then
		ply:GiveAmmo(primaryClipSize * magazines, primaryAmmoType, true)
	end

	local secondaryAmmoType = weapon:GetSecondaryAmmoType()
	local secondaryClipSize = weapon:GetMaxClip2()
	if secondaryAmmoType >= 0 and secondaryClipSize > 0 then
		ply:GiveAmmo(secondaryClipSize * magazines, secondaryAmmoType, true)
	end
end

local function SpawnSelectedLoadoutEntities(ply)
	if not IsValid(ply) then return end

	for id = 6, 8 do
		local classes = GetLoadoutSet(id)
		local class = GetSelectedLoadoutClass(ply, id, classes)
		if class then
			local ent = ents.Create(class)
			if not IsValid(ent) then
				print(string.format("[Chk] Failed to create loadout entity %q for player %s", class, ply:Nick()))
			else
				local sideOffset = (id - 7) * 32
				ent:SetPos(ply:GetPos() + ply:GetForward() * 64 + ply:GetRight() * sideOffset + Vector(0, 0, 16))
				ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
				ent:Spawn()
				ent:Activate()
				ent:DropToFloor()
			end
		end
	end
end

local function ApplySelectedLoadout(ply)
	local configuredClasses = {}
	for id = 1, 5 do
		for _, class in ipairs(GetLoadoutSet(id)) do
			configuredClasses[class] = true
		end
	end

	for class in pairs(configuredClasses) do
		if ply:HasWeapon(class) then
			ply:StripWeapon(class)
		end
	end
	ply:RemoveAllAmmo()
	for id = 1, 5 do
		GiveConvarWeapon(ply, id)
	end
	SpawnSelectedLoadoutEntities(ply)
end

net.Receive("ChkLoadoutSelect", function(_, ply)
	local selections = {}
	for id = 1, 8 do
		selections[id] = net.ReadString()
	end

	local ammoCrate = ply.chkAmmoCrate
	if IsValid(ammoCrate) then
		local cooldownRemaining = GAMEMODE:GetAmmoCrateCooldownRemaining(ply)
		if cooldownRemaining > 0 then
			ply:PrintMessage(HUD_PRINTTALK, string.format(
				"You must wait %d seconds before resupplying again.",
				math.ceil(cooldownRemaining)
			))
			return
		end
	end

	local valid = true
	for id = 1, 8 do
		local selected = selections[id]
		local classes = GetLoadoutSet(id)
		if selected == "" and #classes == 0 then
			selections[id] = nil
		else
			local found = false
			for _, class in ipairs(classes) do
				if class == selected then
					found = true
					break
				end
			end
			if not found then
				valid = false
			end
		end
	end

	if not valid then
		SendWeaponSelection(ply)
		return
	end

	ply.chkLoadoutSelection = selections
	ply.chkLoadoutConfirmed = true
	ApplySelectedLoadout(ply)
	ply.chkAmmoCrate = nil
	if IsValid(ammoCrate) then
		ply:SetHealth(ply:GetMaxHealth())
		ply:SetArmor(100)
		GAMEMODE:StartAmmoCrateCooldown(ply)
		if ammoCrate.CloseAfterUse then
			ammoCrate:CloseAfterUse()
		end
	end
	GAMEMODE:ConfirmLoadoutSelection(ply)
end)

function GM:PlayerLoadout(ply)
	ply:RemoveAllAmmo()
	for i = 1, 5 do GiveConvarWeapon(ply, i) end
	if ply.chkLoadoutConfirmed then
		SpawnSelectedLoadoutEntities(ply)
	end
end