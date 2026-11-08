include("shared.lua")

local viewCaptureColor = Color(0, 128, 255, 32)
local viewPatrolColor = Color(255, 128, 0, 32)

function ENT:Draw()
    if GetConVar("chk_editmode"):GetInt() == 0 then return end

    self:DrawModel()

    local pos = self:GetPos()
    render.SetColorMaterial()

    if GetConVar("chk_obj_viewcapture"):GetBool() then
        render.DrawSphere(
            pos,
            self:GetRadius(),
            24,
            16,
            viewCaptureColor
        )
    end

    if GetConVar("chk_obj_viewpatrol"):GetBool() and self.GetPatrolRadius then
        render.DrawSphere(
            pos,
            self:GetPatrolRadius(),
            24,
            16,
            viewPatrolColor
        )
    end
end