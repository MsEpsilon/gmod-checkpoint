ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Ammo Crate"
ENT.Author = "MsEpsilon"
ENT.Category = "Checkpoint gamemode"
ENT.Purpose = "Resupply and choose a loadout."
ENT.Spawnable = true
ENT.Editable = false

function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "Animating")
end
