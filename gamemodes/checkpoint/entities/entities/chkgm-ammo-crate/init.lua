AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local model = "models/items/ammocrate_smg1.mdl"

local function PlaySequence(ent, name)
	local sequence = ent:LookupSequence(name)
	if sequence < 0 then
		if not ent.MissingSequences then
			ent.MissingSequences = {}
		end
		if not ent.MissingSequences[name] then
			ent.MissingSequences[name] = true
			print(string.format("[Chk] Ammo crate model is missing the %q animation sequence.", name))
		end
		return 0.1
	end

	ent:ResetSequence(sequence)
	ent:SetCycle(0)
	ent:SetPlaybackRate(1)
	return math.max(ent:SequenceDuration(sequence), 0.1)
end

function ENT:Initialize()
	self:SetModel(model)
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)
	self:SetAnimating(false)

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:Wake()
	end
end

function ENT:StartAnimationCycle(closeAfterOpening)
	if self:GetAnimating() then return end

	self:SetAnimating(true)
	self.CloseRequested = false
	self.Closing = false
	local openDuration = PlaySequence(self, "open")
	self.OpenAnimationEnd = CurTime() + openDuration
	timer.Simple(openDuration, function()
		if not IsValid(self) then return end

		self:SetCycle(1)
		self:SetPlaybackRate(0)
		if closeAfterOpening or self.CloseRequested then
			self:PlayCloseAnimation()
		end
	end)
end

function ENT:PlayCloseAnimation()
	if not self:GetAnimating() or self.Closing then return end

	self.Closing = true
	local closeDuration = PlaySequence(self, "close")
	timer.Simple(closeDuration, function()
		if not IsValid(self) then return end

		self:SetCycle(1)
		self:SetPlaybackRate(0)
		self:SetAnimating(false)
		self.CloseRequested = false
		self.Closing = false
	end)
end

function ENT:CloseAfterUse()
	if not self:GetAnimating() or self.Closing then return end

	self.CloseRequested = true
	if CurTime() >= (self.OpenAnimationEnd or CurTime()) then
		self:PlayCloseAnimation()
	end
end

function ENT:Use(activator)
	if self:GetAnimating() then return end
	if not IsValid(activator) or not activator:IsPlayer() then return end

	local cooldownRemaining = GAMEMODE:GetAmmoCrateCooldownRemaining(activator)
	if cooldownRemaining > 0 then
		activator:PrintMessage(HUD_PRINTTALK, string.format(
			"You must wait %d seconds before resupplying again.",
			math.ceil(cooldownRemaining)
		))
		return
	end

	activator.chkAmmoCrate = self
	self:StartAnimationCycle()
	SendWeaponSelection(activator)
end

function ENT:PreEntityCopy()
	duplicator.StoreEntityModifier(self, "CheckpointAmmoCrate", {
		version = 1,
		animating = self:GetAnimating()
	})
end

function ENT:PostEntityPaste(_, pastedEntity)
	local modifiers = IsValid(pastedEntity) and pastedEntity.EntityMods or self.EntityMods
	local data = modifiers and modifiers.CheckpointAmmoCrate
	if not istable(data) or data.version ~= 1 or not data.animating then return end

	self:StartAnimationCycle(true)
end
