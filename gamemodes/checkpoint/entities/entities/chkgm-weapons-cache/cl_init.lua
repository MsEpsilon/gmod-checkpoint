include("shared.lua")

game.AddParticles("particles/fire_01.pcf")
game.AddParticles("particles/explosion.pcf")
PrecacheParticleSystem("explosion")
PrecacheParticleSystem("smoke_large_01")

-- Client-side draw function for the Entity
function ENT:Draw()
    self:DrawModel()

    if GetConVar("chk_editmode"):GetInt() == 0 then return end
    if not GetConVar("chk_obj_viewpatrol"):GetBool() then return end
    if not self.GetPatrolRadius then return end

    render.SetColorMaterial()
    render.DrawSphere(
        self:GetPos(),
        self:GetPatrolRadius(),
        24,
        16,
        Color(255, 128, 0, 32)
    )
end