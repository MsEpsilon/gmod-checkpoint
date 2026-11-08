include("shared.lua")

function ENT:Draw()
    if GetConVar("chk_editmode"):GetInt() == 0 then return end
    self:DrawModel()
end