local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local remotes=RS:WaitForChild("PartyRemotes")
local input=remotes:WaitForChild("PartyInput")
local report=RS:WaitForChild("FestivalTestReport")
local me="player_"..Players.LocalPlayer.UserId
local seen={Turns=0,Rotations=0,Automatic=0,MoonDial=false,Prompts=0,Errors={},Finished=false,Layouts=0}
local configured=false
local lastRevision=0
local turnKey=nil
local sent=false
local function sendLater(payload) task.delay(0.2,function() input:FireServer(payload) end) end
remotes.PartyState.OnClientEvent:Connect(function(m)
 if m.Type=="BoardLayout" then
  seen.Layouts+=1;seen.Board=m.Name
 elseif m.Type=="Phase" then
  if m.Phase=="Lobby" and m.WaitingRoom and m.HostId==Players.LocalPlayer.UserId and not configured then
   configured=true
   task.spawn(function()
    input:FireServer({Kind="Setting",Key="Board",Value="MagicalFestival"});task.wait(0.3)
    input:FireServer({Kind="Setting",Key="Rounds",Value=3});task.wait(0.3)
    input:FireServer({Kind="StartMatch"})
   end)
  elseif m.Phase=="Vote" then
   local best=1
   for i,choice in m.Choices do if (choice.Duration or 999)<(m.Choices[best].Duration or 999) then best=i end end
   sendLater({Kind="Vote",Choice=best})
  elseif m.Phase=="Standings" and m.Stage=="Final" and not sent then
   sent=true;seen.Finished=true;seen.Players=#m.Rows;report:FireServer(seen)
  end
 elseif m.Type=="BoardState" then
  seen.Round=m.Round;seen.Stage=m.Stage
  if m.Bridge and m.Bridge.Revision>lastRevision then
   seen.Rotations+=m.Bridge.Revision-lastRevision
   if m.TurnId==nil then seen.Automatic+=1 else seen.MoonDial=true end
   lastRevision=m.Bridge.Revision
  end
  if m.Stage=="OrderRoll" and m.OrderPending and m.OrderPending[me] then sendLater({Kind="Roll"}) end
  if m.Stage=="Roll" and m.TurnId==me then
   local key=tostring(m.Round)..":"..me
   if turnKey~=key then
    turnKey=key;seen.Turns+=1
    task.spawn(function()
     if m.Round==1 then input:FireServer({Kind="UseItem",Slot=1});task.wait(5) end
     input:FireServer({Kind="Roll"})
    end)
   end
  end
  if m.Stage=="Rotating" then
   for _,seat in m.Seats do if seat.SpaceId>=33 then seen.SawRider=true end end
  end
 elseif m.Type=="Prompt" and m.PromptId then
  seen.Prompts+=1;input:FireServer({Kind="Choice",PromptId=m.PromptId,Index=99});sendLater({Kind="Choice",PromptId=m.PromptId,Index=1})
 end
 Players.LocalPlayer:SetAttribute("FestivalTestStatus",game:GetService("HttpService"):JSONEncode(seen))
end)
input:FireServer({Kind="Ready"})
