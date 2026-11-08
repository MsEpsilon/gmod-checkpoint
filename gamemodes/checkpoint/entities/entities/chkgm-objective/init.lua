AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    RegisterObjectiveEntity(self)
    self:SetScore(0)
    self:SetRadius(256)
    self:SetPatrolRadius(512)
    self:SetModel( "models/hunter/blocks/cube025x025x025.mdl" )
    self:PhysicsInit( SOLID_VPHYSICS ) 
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetCustomCollisionCheck( true )
    self:DrawShadow( false )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:Wake()
    end
end

function ENT:OnRemove()
    UnregisterObjectiveEntity(self)
end