ENT.Type = "anim" 
ENT.Base = "base_gmodentity"
ENT.PrintName = "Weapon Cache"
ENT.Author = "MsEpsilon"
ENT.Category = "Checkpoint gamemode" 
ENT.Contact = "STEAM_0:1:12345678" 
ENT.Purpose = "Checkpoint weapons cache objective" 
ENT.Spawnable = true 
ENT.Editable = true
ENT.Icon = "vgui/entities/chkgm-weapons-cache"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "ObjectiveID")
    self:NetworkVar("Float", 0, "PatrolRadius", {
        KeyName = "patrolradius",
        Edit = {
            type = "Float",
            order = 1,
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
        order = 2
    })
end