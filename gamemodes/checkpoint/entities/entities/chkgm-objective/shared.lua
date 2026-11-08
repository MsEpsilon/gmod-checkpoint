ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Objective"
ENT.Author = "MsEpsilon"
ENT.Category = "Checkpoint gamemode"
ENT.Contact = "STEAM_0:1:12345678"
ENT.Purpose = "Objective that can be captured by players."
ENT.Spawnable = true
ENT.Editable = true
ENT.Icon = "vgui/entities/chkgm-objective"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "ObjectiveID")
    self:NetworkVar("Float", 2, "Score")
    self:NetworkVar("Float", 0, "Radius", {
        KeyName = "radius",
        Edit = {
            type = "Float",
            order = 1,
            min = 0,
            max = 2048
        }
    })
    self:NetworkVar("Float", 1, "PatrolRadius", {
        KeyName = "patrolradius",
        Edit = {
            type = "Float",
            order = 2,
            min = 0,
            max = 4096
        }
    })

    self:SetupKeyValue("objectivename", "string", function() end, function(ent)
        return ObjectiveName(ent:GetObjectiveID())
    end)
    self:SetupEditing("Objective Name", "objectivename", {
        type = "String",
        title = "Objective Name",
        readonly = true,
        order = 3
    })
end