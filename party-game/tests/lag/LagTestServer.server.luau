--[[
	Lag test (server half). Only part of the place built from tests/lag/lag.project.json.
	Collects one smoothness report per client (see LagTestClient), adds any "[IceDash]"
	rejected-report lines from the output, prints the lot and ends the multiplayer test.
	How to run it is in the party-game README ("Testing under lag").
]]
local RS = game:GetService("ReplicatedStorage")
local STS = game:GetService("StudioTestService")
local ev = Instance.new("RemoteEvent")
ev.Name = "LagReport"
ev.Parent = RS
local reports = {}
local rejects = {}
game:GetService("LogService").MessageOut:Connect(function(text)
	if text:find("[IceDash]", 1, true) then table.insert(rejects, text) end
end)
local count = 0
local function finish()
	local parts = {}
	for name, text in reports do table.insert(parts, name .. " => " .. text) end
	table.insert(parts, "serverRejects: " .. (if #rejects > 0 then table.concat(rejects, " | ") else "none"))
	local result = table.concat(parts, "\n")
	print("[LagTest] " .. result)
	pcall(function() STS:EndTest(result) end)
end
ev.OnServerEvent:Connect(function(player, text)
	if type(text) ~= "string" or reports[player.Name] then return end
	reports[player.Name] = text
	count += 1
	if count >= 2 then task.wait(22) finish() end
end)
task.delay(150, function() if count < 2 then reports.timeout = "timed out with " .. count .. " report(s)" finish() end end)
