--[[
	Multi-client board test (server half). Only part of the place built from
	tests/multi/multi.project.json. Two real clients (MultiTestClient) play a board match on
	autopilot with two bots; each reports what it saw. This collects the reports plus any
	server errors/warnings, prints "[MultiTest] ..." and ends the multiplayer test.

	Run: build the place, open it, then in the command bar
	  task.spawn(function() print(game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2, {})) end)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")

local report = Instance.new("RemoteEvent")
report.Name = "MultiTestReport"
report.Parent = ReplicatedStorage

local reports, problems = {}, {}
game:GetService("LogService").MessageOut:Connect(function(text, kind)
	if (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning)
		and not text:find("UIBlox") and not text:find("CorePackages") and not text:find("[Profiles]", 1, true) then
		table.insert(problems, text:sub(1, 200))
	end
end)

local done = false
local function finish(why: string)
	if done then
		return
	end
	done = true
	local lines = { "why=" .. why }
	for name, text in reports do
		table.insert(lines, name .. " => " .. text)
	end
	table.insert(lines, "serverProblems=" .. (if #problems > 0 then table.concat(problems, " | ") else "none"))
	local result = table.concat(lines, "\n")
	print("[MultiTest] " .. result)
	pcall(function()
		StudioTestService:EndTest(result)
	end)
end

local count = 0
report.OnServerEvent:Connect(function(player, text)
	if type(text) ~= "string" or reports[player.Name] then
		return
	end
	reports[player.Name] = text
	count += 1
	if count >= 2 then
		finish("both reported")
	end
end)
task.delay(600, function()
	finish("timeout with " .. count .. " report(s)")
end)
