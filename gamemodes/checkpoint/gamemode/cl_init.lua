include( "shared.lua" )

local scenarioResult
local scenarioResultText
local scenarioResultEndTime = 0
local scenarioVoteFrame
local scenarioVoteStatus
local scenarioVoteTimer
local scenarioVoteEndTime = 0
local scenarioVoteCandidates = {}
local scenarioVoteCounts = {}
local scenarioVoteChoice
local loadoutFrame
local loadoutSets = {}
local loadoutSelections = {}

local counterattackTracks = {
    ["counterattack1.wav"] = true,
    ["counterattack2.wav"] = true,
    ["counterattack3.wav"] = true,
    ["counterattack4.wav"] = true,
    ["finalcounterattack.wav"] = true
}

net.Receive("ChkPlayCounterattackMusic", function()
    local track = net.ReadString()
    if not counterattackTracks[track] then
        print("[Chk] Received unknown counterattack music track: " .. track)
        return
    end

    surface.PlaySound(track)
end)

local function OpenLoadoutMenu()
    if IsValid(loadoutFrame) then
        loadoutFrame:Remove()
    end

    local width = math.min(900, ScrW() - 40)
    local height = math.min(650, ScrH() - 40)
    loadoutFrame = vgui.Create("DFrame")
    loadoutFrame:SetSize(width, height)
    loadoutFrame:Center()
    loadoutFrame:SetTitle("Choose your loadout")
    loadoutFrame:SetDraggable(false)
    loadoutFrame:ShowCloseButton(false)
    loadoutFrame:MakePopup()

    local help = vgui.Create("DLabel", loadoutFrame)
    help:SetPos(16, 34)
    help:SetSize(width - 32, 24)
    help:SetText("Choose one item for each available slot.")

    local content = vgui.Create("DScrollPanel", loadoutFrame)
    content:SetPos(12, 62)
    content:SetSize(width - 24, height - 122)

    local columns = math.max(1, math.floor((width - 44) / 138))
    for id = 1, 8 do
        local classes = loadoutSets[id] or {}
        if #classes > 0 then
            local row = vgui.Create("DPanel")
            row:Dock(TOP)
            row:DockMargin(0, 0, 0, 8)
            row:SetTall(32 + math.ceil(#classes / columns) * 112)
            content:AddItem(row)
            row.Paint = function(_, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(35, 38, 43, 245))
            end

            local title = vgui.Create("DLabel", row)
            title:Dock(TOP)
            title:DockMargin(10, 4, 0, 2)
            title:SetTall(24)
            title:SetText(id <= 5 and "Weapon set " .. id or "Loadout entity set " .. (id - 5))

            local layout = vgui.Create("DIconLayout", row)
            layout:Dock(FILL)
            layout:DockMargin(8, 0, 8, 6)
            layout:SetSpaceX(6)
            layout:SetSpaceY(4)

            for _, class in ipairs(classes) do
                local button = layout:Add("DButton")
                button:SetSize(128, 104)
                button:SetText("")
                button.DoClick = function()
                    loadoutSelections[id] = class
                    if IsValid(loadoutFrame) then
                        loadoutFrame:InvalidateLayout(true)
                    end
                end
                button.Paint = function(self, w, h)
                    local selected = loadoutSelections[id] == class
                    draw.RoundedBox(4, 0, 0, w, h, selected and Color(65, 110, 75) or Color(55, 59, 66))
                    surface.SetDrawColor(selected and Color(130, 220, 145) or Color(90, 94, 102))
                    surface.DrawOutlinedRect(0, 0, w, h, selected and 2 or 1)
                end

                local iconPath = "entities/" .. class .. ".png"
                local iconMaterial = Material(iconPath, "smooth")
                if not iconMaterial:IsError() then
                    local icon = vgui.Create("DImage", button)
                    icon:SetPos(28, 4)
                    icon:SetSize(72, 64)
                    icon:SetMaterial(iconMaterial)
                    icon:SetMouseInputEnabled(false)
                else
                    local definition = weapons.Get(class)
                    local storedEntity = scripted_ents.GetStored(class)
                    local entityDefinition = storedEntity and storedEntity.t
                    local model = definition and (definition.WorldModel or definition.ViewModel)
                        or entityDefinition and entityDefinition.Model
                    if isstring(model) and model ~= "" then
                        local icon = vgui.Create("SpawnIcon", button)
                        icon:SetPos(36, 2)
                        icon:SetSize(56, 64)
                        icon:SetModel(model)
                        icon:SetMouseInputEnabled(false)
                    end
                end

                local definition = weapons.Get(class)
                local storedEntity = scripted_ents.GetStored(class)
                local entityDefinition = storedEntity and storedEntity.t
                local label = vgui.Create("DLabel", button)
                label:SetPos(4, 70)
                label:SetSize(120, 30)
                label:SetText(
                    (definition and definition.PrintName)
                    or (entityDefinition and entityDefinition.PrintName)
                    or string.Trim(string.gsub(class, "^weapon_", ""))
                )
                label:SetContentAlignment(5)
                label:SetWrap(true)
                label:SetMouseInputEnabled(false)
            end
        end
    end

    local confirm = vgui.Create("DButton", loadoutFrame)
    confirm:SetPos(12, height - 48)
    confirm:SetSize(width - 132, 36)
    confirm:SetText("Confirm loadout")
    confirm.DoClick = function()
        net.Start("ChkLoadoutSelect")
        for id = 1, 8 do
            net.WriteString(loadoutSelections[id] or "")
        end
        net.SendToServer()
        loadoutFrame:Close()
    end

    local exit = vgui.Create("DButton", loadoutFrame)
    exit:SetPos(width - 112, height - 48)
    exit:SetSize(100, 36)
    exit:SetText("Exit")
    exit.DoClick = function()
        loadoutFrame:Close()
    end
end

net.Receive("ChkLoadoutMenu", function()
    loadoutSets = {}
    loadoutSelections = {}
    for id = 1, 8 do
        local count = net.ReadUInt(8)
        loadoutSets[id] = {}
        for index = 1, count do
            loadoutSets[id][index] = net.ReadString()
        end
        loadoutSelections[id] = net.ReadString()
    end
    OpenLoadoutMenu()
end)

local function OpenScenarioVote(candidates, endTime)
    if IsValid(scenarioVoteFrame) then
        scenarioVoteFrame:Remove()
    end

    scenarioVoteCandidates = candidates
    scenarioVoteCounts = {}
    scenarioVoteEndTime = endTime
    scenarioVoteChoice = nil

    scenarioVoteFrame = vgui.Create("DFrame")
    scenarioVoteFrame:SetSize(460, 250)
    scenarioVoteFrame:Center()
    scenarioVoteFrame:SetTitle("Vote for the next scenario")
    scenarioVoteFrame:SetDraggable(false)
    scenarioVoteFrame:ShowCloseButton(false)
    scenarioVoteFrame:MakePopup()

    local scenarioBox = vgui.Create("DComboBox", scenarioVoteFrame)
    scenarioBox:SetPos(20, 45)
    scenarioBox:SetSize(420, 30)
    scenarioBox:SetValue("Choose a scenario")
    for index, candidate in ipairs(candidates) do
        scenarioBox:AddChoice(candidate.name .. " [" .. candidate.map .. "]", index)
    end
    scenarioBox.OnSelect = function(_, _, _, data)
        scenarioVoteChoice = candidates[data]
    end

    scenarioVoteTimer = vgui.Create("DLabel", scenarioVoteFrame)
    scenarioVoteTimer:SetPos(20, 85)
    scenarioVoteTimer:SetSize(420, 24)
    scenarioVoteTimer:SetText("")

    scenarioVoteStatus = vgui.Create("DLabel", scenarioVoteFrame)
    scenarioVoteStatus:SetPos(20, 110)
    scenarioVoteStatus:SetSize(420, 76)
    scenarioVoteStatus:SetWrap(true)
    scenarioVoteStatus:SetText("")

    local voteButton = vgui.Create("DButton", scenarioVoteFrame)
    voteButton:SetPos(20, 195)
    voteButton:SetSize(420, 35)
    voteButton:SetText("Cast vote")
    voteButton.DoClick = function()
        if not scenarioVoteChoice then return end

        net.Start("ChkScenarioVote")
        net.WriteString(scenarioVoteChoice.name)
        net.SendToServer()
        voteButton:SetText("Change vote")
    end
end

net.Receive("ChkScenarioResult", function()
    local result = net.ReadString()
    local message = net.ReadString()
    if result ~= "failed" and result ~= "complete" then return end

    scenarioResult = result
    scenarioResultText = message ~= "" and message or nil
    scenarioResultEndTime = CurTime() + 5
end)

net.Receive("ChkScenarioVoteStart", function()
    local endTime = net.ReadFloat()
    local candidates = {}
    for index = 1, net.ReadUInt(8) do
        candidates[index] = {
            name = net.ReadString(),
            map = net.ReadString()
        }
    end
    scenarioResult = nil
    scenarioResultText = nil
    OpenScenarioVote(candidates, endTime)
end)

net.Receive("ChkScenarioVoteUpdate", function()
    scenarioVoteCounts = {}
    for _ = 1, net.ReadUInt(8) do
        local scenarioName = net.ReadString()
        scenarioVoteCounts[scenarioName] = net.ReadUInt(8)
    end
end)

function GM:SpawnMenuOpen()
    return GetConVar( "chk_editmode" ):GetInt() > 0
end

function GM:ContextMenuOpen()
    return GetConVar( "chk_editmode" ):GetInt() > 0
end

function GM:HUDPaint()
    if scenarioResult and CurTime() < scenarioResultEndTime then
        local text = scenarioResultText
            or (scenarioResult == "failed" and "MISSION FAILED" or "MISSION COMPLETE")
        draw.SimpleTextOutlined(
            text,
            "Trebuchet24",
            ScrW() / 2,
            ScrH() / 2,
            Color(255, 255, 255),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            2,
            Color(0, 0, 0)
        )
    end

    if GetConVar( "chk_editmode" ):GetInt() > 0 then
        draw.SimpleText( "Checkpoint - Edit Mode Enabled", "Trebuchet24", ScrW() / 2, 10, Color( 255, 0, 0 ), TEXT_ALIGN_CENTER )
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local objective = ply:GetNW2Entity("chk_inside_objective")
    if IsValid(objective) then
        local objectiveName = ObjectiveName(objective:GetObjectiveID())
        local score = objective:GetScore()
        if GetGlobalBool("chk_counterattack_active", false)
            and objective:GetClass() == "chkgm-objective"
            and objective:GetObjectiveID() == GetGlobalInt("chk_current_objective_id", 0) then
            score = 100 - objective:GetNW2Float("chk_counterattack_capture_progress", 0)
        end
        draw.SimpleTextOutlined(
            "Inside objective " .. objectiveName .. " - " .. math.floor(score) .. "%",
            "Trebuchet24",
            ScrW() / 2,
            40,
            Color(255, 255, 255),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            2,
            Color(0, 0, 0)
        )
    end

    if GetGlobalBool("chk_counterattack_active", false) then
        local remaining = math.max(math.ceil(GetGlobalFloat("chk_counterattack_end", CurTime()) - CurTime()), 0)
        local minutes = math.floor(remaining / 60)
        local seconds = remaining % 60
        local timeText = string.format("%02d:%02d", minutes, seconds)
        draw.SimpleTextOutlined(
            "COUNTERATTACK - " .. timeText,
            "Trebuchet24",
            ScrW() / 2,
            ScrH() - 48,
            Color(255, 80, 80),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            2,
            Color(0, 0, 0)
        )
    elseif GetGlobalBool("chk_objective_timer_active", false) then
        local remaining = math.max(math.ceil(GetGlobalFloat("chk_objective_time_end", CurTime()) - CurTime()), 0)
        local minutes = math.floor(remaining / 60)
        local seconds = remaining % 60
        local timeText = string.format("%02d:%02d", minutes, seconds)
        draw.SimpleTextOutlined(
            "OBJECTIVE TIME - " .. timeText,
            "Trebuchet24",
            ScrW() / 2,
            ScrH() - 48,
            Color(255, 220, 100),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            2,
            Color(0, 0, 0)
        )
    end
end

hook.Add("Think", "ChkScenarioVoteTimer", function()
    if not IsValid(scenarioVoteFrame) then return end

    local remaining = math.max(math.ceil(scenarioVoteEndTime - CurTime()), 0)
    scenarioVoteTimer:SetText("Voting ends in " .. remaining .. " seconds.")

    local tally = {}
    for _, candidate in ipairs(scenarioVoteCandidates) do
        tally[#tally + 1] = candidate.name .. " (" .. candidate.map .. "): "
            .. (scenarioVoteCounts[candidate.name] or 0)
    end
    scenarioVoteStatus:SetText(table.concat(tally, "    "))
end)

objectiveSprites = {
	Material( "sprites/objicon_alpha.png" ),
	Material( "sprites/objicon_bravo.png" ),
	Material( "sprites/objicon_charlie.png" ),
	Material( "sprites/objicon_delta.png" ),
	Material( "sprites/objicon_echo.png" ),
	Material( "sprites/objicon_foxtrot.png" ),
	Material( "sprites/objicon_golf.png" ),
	Material( "sprites/objicon_hotel.png" ),
	Material( "sprites/objicon_india.png" ),
	Material( "sprites/objicon_juliet.png" )
}

local objectiveIconColor = Color( 255, 255, 255, 178 )

hook.Add("PreDrawViewModel", "ObjectiveIconDraw", function(vm, ply, weapon, flags )
    if GetConVar( "chk_editmode" ):GetInt() > 0 then return end
    if input.IsMouseDown( MOUSE_RIGHT ) then return end

    local currentObjectiveID = GetGlobalInt("chk_current_objective_id", 0)
    local currentObjectivePos = GetGlobalVector("chk_current_objective_pos", Vector(0, 0, 0))
    local sprite = objectiveSprites[currentObjectiveID]
    if not sprite then return end

    render.SetMaterial(sprite)
    render.DrawSprite(currentObjectivePos, 50, 50, objectiveIconColor)
end)

print( "[Chk] Loaded checkpoint gamemode!" )