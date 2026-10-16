-- Test-only timing and inventory overrides. Never mapped into the shipped place.
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS.PartyShared.Config)
Config.Board.BotRollDelay={0.1,0.2};Config.Board.BotChoiceDelay={0.1,0.2}
Config.Board.HopTime=0.12;Config.Board.LandPause=0.2
Config.Match.OrderRollTimeout=2;Config.Board.ChoiceTimeout=2
Config.Items.StartingItems={"MoonDial","LuckyDie"}
Config.Match.WaitingRoomDuration=60
Config.VoteDuration=2;Config.InstructionsDuration=2;Config.ResultsDuration=2
-- Deliberately begin on the moving deck to exercise a real player riding Moon Dial.
require(game.ServerScriptService.PartyServer.Board.Boards.MagicalFestival).Start=34
local remote=Instance.new("RemoteEvent");remote.Name="FestivalTestReport";remote.Parent=RS
local reports={}
remote.OnServerEvent:Connect(function(p,data)
 if type(data)~="table" then return end
 data.Passed=data.Finished==true and data.Turns>=3 and data.Players==4 and data.Automatic>=3 and data.Rotations>=4 and data.SawRider==true
 reports[p.Name]=data
 print("[FestivalSmoke] "..p.Name.." "..game:GetService("HttpService"):JSONEncode(data))
 workspace:SetAttribute("FestivalReports",game:GetService("HttpService"):JSONEncode(reports))
 if #game:GetService("Players"):GetPlayers()>=2 then
  local n=0;for _ in reports do n+=1 end
  if n>=2 then pcall(function() game:GetService("StudioTestService"):EndTest(game:GetService("HttpService"):JSONEncode(reports)) end) end
 end
end)

-- A failed client launch must not leave a local multi-client test running indefinitely.
task.delay(600,function()
 local count=0;for _ in reports do count+=1 end
 if count<2 then
  pcall(function() game:GetService("StudioTestService"):EndTest("INCOMPLETE: fewer than two reports after 600 seconds") end)
 end
end)
