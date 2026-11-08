function GM:ShouldCollide(ent1, ent2)
	local firstClass = ent1:GetClass()
	local secondClass = ent2:GetClass()
	local isCheckpointEntity = firstClass == "chkgm-objective"
		or firstClass == "chkgm-spawnpoint"
		or secondClass == "chkgm-objective"
		or secondClass == "chkgm-spawnpoint"

	if isCheckpointEntity then
		if ent1:IsPlayer() or ent2:IsPlayer() then
			return GetConVar("chk_editmode"):GetInt() > 0
		end
		return true
	end
end