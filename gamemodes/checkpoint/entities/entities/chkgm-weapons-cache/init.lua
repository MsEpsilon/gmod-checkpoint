AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

game.AddParticles("particles/fire_01.pcf")
game.AddParticles( "particles/explosion.pcf" )
PrecacheParticleSystem("explosion_huge")
PrecacheParticleSystem("smoke_large_01")
PrecacheParticleSystem( "ExplosionCore_wall" )

local nextAmmoUse = setmetatable({}, { __mode = "k" })

function ENT:Initialize()
    RegisterObjectiveEntity(self)
    self:SetPatrolRadius(512)
    self:SetModel( "models/static_props/weapon_cache_01.mdl" ) -- Sets the model for the Entity.
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS ) 
    self:SetSolid( SOLID_VPHYSICS )
    self:SetHealth( GetConVar("chk_objective_health"):GetInt() )
    self.Destroyed = false
    self.Attackers = {}
    local phys = self:GetPhysicsObject()
    if phys:IsValid() then
        phys:SetMass(10000)
        phys:Wake() 
    end
end

function ENT:OnRemove()
    UnregisterObjectiveEntity(self)
end

function ENT:OnTakeDamage(dmginfo)
    if self.Destroyed then return end

    if self:GetObjectiveID() ~= GetGlobalInt("chk_current_objective_id", 0) then
        return
    end

    local attacker = dmginfo:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() then
        self.Attackers[attacker] = attacker:Nick()
    end

    self:SetHealth(self:Health() - dmginfo:GetDamage())

    if(self:Health() <= 0) then
        self.Destroyed = true

        local attackerNames = {}
        for _, attackerName in pairs(self.Attackers) do
            attackerNames[#attackerNames + 1] = attackerName
        end
        table.sort(attackerNames)
        local attackerList = #attackerNames > 0 and table.concat(attackerNames, " + ") or "Unknown"
        PrintMessage(HUD_PRINTTALK, attackerList .. " destroyed weapons cache " .. ObjectiveName(self:GetObjectiveID()) .. ".")

        self:SetModel("models/static_props/wcache_ins_01_destr.mdl")
        self:Ignite(10, 100)

        local pos = self:WorldSpaceCenter()
        if not IsValid(attacker) then
            attacker = self
        end

        local effect = EffectData()
        effect:SetOrigin(pos)

        util.Effect("Explosion", effect, true, true)

        local angle = Angle(0, 0, 0)
        ParticleEffect("ExplosionCore_wall", pos, angle)

        timer.Simple(0.15, function()
            ParticleEffect("smoke_large_01", pos, angle)
        end)

        hook.Run("CheckpointObjectiveCompleted", self)
        util.BlastDamage(self, attacker, pos, 500, 550) -- Radius and damage
    end
end

function ENT:Use(activator, caller)
    if self.Destroyed then return end
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if (nextAmmoUse[activator] or 0) > CurTime() then 
        local secondsRemaining = math.ceil(nextAmmoUse[activator] - CurTime())
        activator:PrintMessage(HUD_PRINTTALK, "You must wait " .. secondsRemaining .. " seconds before using the weapon cache again.")
        return
    end

    local weapon = activator:GetActiveWeapon()
    if not IsValid(weapon) then return end

    local ammoType = weapon:GetPrimaryAmmoType()
    local clipSize = weapon:GetMaxClip1()
    if ammoType < 0 or clipSize <= 0 then
        activator:PrintMessage(HUD_PRINTTALK, "Your current weapon does not use ammo or has no clip size.")
        return
    end

    local ammoName = game.GetAmmoName(ammoType)
    if not ammoName or ammoName == "" then return end

    activator:GiveAmmo(clipSize * 3, ammoName, true)
    nextAmmoUse[activator] = CurTime() + 60

    activator:PrintMessage(HUD_PRINTTALK, "You have received ammo from the weapon cache!")
end