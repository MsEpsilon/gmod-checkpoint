hook.Add("PlayerCanPickupWeapon", "DisableSandboxToolsPickup", function(ply, weapon)
	local class = weapon:GetClass()
	if class == "weapon_physgun" or class == "gmod_tool" then
		return GetConVar("chk_editmode"):GetInt() > 0
	end
end)

function GM:PhysgunPickup(ply, ent)
	return GetConVar("chk_editmode"):GetInt() > 0
end

function GM:CanTool(ply, tr, toolname)
	return GetConVar("chk_editmode"):GetInt() > 0
end

function GM:PlayerNoClip(ply, desiredState)
	if desiredState then
		return GetConVar("chk_editmode"):GetInt() > 0
	end
	return true
end

local sandboxHints = {
	"Annoy1",
	"Annoy2",
	"OpeningMenu",
	"OpeningContext",
	"ContextClick",
	"PhysgunFreeze",
	"PhysgunUnfreeze",
	"PhysgunUse",
	"VehicleView",
	"ColorRoom",
	"EditingSpawnlists",
	"EditingSpawnlistsSave"
}

hook.Add("PlayerInitialSpawn", "DisableSandboxHints", function(ply)
	for _, hint in ipairs(sandboxHints) do
		ply:SuppressHint(hint)
	end
end)