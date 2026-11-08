GM.Name = "Checkpoint"
GM.Author = "MsEpsilon"
GM.Email = "ms_epsilon@proton.me"
GM.Website = "N/A"

DeriveGamemode("sandbox")

function ObjectiveName(id)
	if not isnumber(id) or id > 26 or id < 1 then
		return "Unknown"
	end

	local names = {
		"Alpha",
		"Bravo",
		"Charlie",
		"Delta",
		"Echo",
		"Foxtrot",
		"Golf",
		"Hotel",
		"India",
		"Juliet",
		"Kilo",
		"Lima",
		"Mike",
		"November",
		"Oscar",
		"Papa",
		"Quebec",
		"Romeo",
		"Sierra",
		"Tango",
		"Uniform",
		"Victor",
		"Whiskey",
		"X-ray",
		"Yankee",
		"Zulu"
	}

	return names[id]
end