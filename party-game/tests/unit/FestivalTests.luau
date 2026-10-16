local Server=game:GetService("ServerScriptService").PartyServer
local BoardLayout=require(Server.Board.BoardLayout)
local Match=require(Server.Board.Match)
local Types=require(Server.Board.SpaceTypes)
local Data=require(Server.Board.Boards.MagicalFestival)
local Bridge=require(Server.Board.RotatingBridge)
local World=require(Server.Board.BoardWorld)
local Bot=require(Server.Board.BotBrain)
local Wallet=require(Server.CoinService)
local Inventory=require(Server.Inventory)
local tests={}
local function test(name,fn) table.insert(tests,{name,fn}) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function new()
 Wallet.resetAll()
 local seats={}
 for i=1,4 do seats[i]={Id="festival"..i,Name="F"..i,IsBot=true} end
 return Match.new(BoardLayout.load(Data,Types),seats,{Rounds=8,Difficulty="Hard"},{Wallet=Wallet,Inventory=Inventory,Rng=Random.new(9),Ask=function(_,q) return q.Default end})
end
test("definition: 36 spaces, four eight-space loops, every space type",function()
 eq(BoardLayout.validate(Data,Types),nil)
 local m=new();eq(#m.Board.Order,36)
 local count,kinds={},{}
 for _,s in m.Board.Spaces do count[s.Zone]=(count[s.Zone] or 0)+1;kinds[s.Type]=true end
 for zone=1,4 do eq(count[zone],8) end
 eq(count[0],4)
 for _,kind in {"Gain","Lose","Neutral","Item","Reward","Event","Chaos","Duel","Switch","Shop"} do assert(kinds[kind],kind) end
end)
for orientation=0,1 do
 test("alignment "..orientation..": exact connected docks, no bypass",function()
  local m=new();m.Orientation=orientation
  for zone,dock in Bridge.Docks do
   local open=Bridge.connected(zone,orientation)
   eq(#m:nextOptions(dock),if open then 2 else 1)
   eq(m:distance(dock,34)<math.huge,open)
   for other,target in Bridge.Docks do
    if other~=zone then eq(m:distance(dock,target)<math.huge,open and Bridge.connected(other,orientation)) end
   end
  end
 end)
 test("alignment "..orientation..": every local zone plays 48 uninterrupted moves",function()
  local m=new();m.Orientation=orientation
  for zone,dock in Bridge.Docks do
   local seat=m.Seats[1];seat.SpaceId=dock
   for step=1,48 do
    m:step(seat)
    eq(m.Board:get(seat.SpaceId).Zone,zone)
   end
   eq(seat.SpaceId,dock)
  end
 end)
 test("alignment "..orientation..": bridge always has legal escape",function()
  local m=new();m.Orientation=orientation
  for id=33,36 do
   assert(#m:nextOptions(id)>0)
   local reaches=false
   for zone,dock in Bridge.Docks do reaches=reaches or m:distance(id,dock)<math.huge end
   assert(reaches)
  end
 end)
 test("alignment "..orientation..": closed route preview and reachable rewards",function()
  local m=new();m.Orientation=orientation
  local zone=if orientation==0 then 2 else 1
  local dock=Bridge.Docks[zone]
  assert(m:routeInfo(m.Seats[1],dock,0).Preview:find("CLOSED"))
  m.Seats[1].SpaceId=dock+1
  m:land(m.Seats[1]);assert(m:coinsOf(m.Seats[1])>0)
  m.Seats[1].SpaceId=dock+6
  local before=#m.Seats[1].Items;m:itemSpace(m.Seats[1]);eq(#m.Seats[1].Items,before+1)
 end)
end
test("rotation invalidates warmed distances atomically",function()
 local m=new();eq(m:distance(9,34),math.huge)
 assert(m:rotateBridge());eq(m.Orientation,1);eq(m.BridgeRevision,1)
 assert(m:distance(9,34)<math.huge);eq(m:distance(1,34),math.huge)
end)
test("rotation waits for turn boundary and is idempotent per round",function()
 local m=new();m:startRound(1);m:beginTurn(m.Seats[1]);m:rollTurn(m.Seats[1])
 eq(m:rotateBridge(),false);eq(m:finishBoardRound(),false)
 m:endTurn();assert(m:finishBoardRound());eq(m:finishBoardRound(),false)
 m:startRound(2);assert(m:finishBoardRound());eq(m.Orientation,0)
end)
test("state snapshot includes current next alignment and every closed dock",function()
 local m=new();local old=m:bridgeState();m:rotateBridge();local fresh=m:bridgeState()
 eq(old.Alignment,"N–S");eq(fresh.Alignment,"E–W");eq(fresh.NextAlignment,"N–S")
 eq(fresh.Docks[1].Open,false);eq(fresh.Docks[2].Open,true);eq(fresh.Revision,1)
end)
test("Crown relocates off closing zone and preserves an accessible Crown",function()
 local m=new();m.CollectibleSpace=4;m:rotateBridge();eq(m.CollectibleSpace,34)
 m.CollectibleSpace=20;m:rotateBridge();eq(m.CollectibleSpace,20)
 for _=1,20 do m:relocateCollectible();assert(Bridge.connected(m.Board:get(m.CollectibleSpace).Zone,m.Orientation)) end
end)
test("Moon Dial rejects wrong owner, slot, stage, repeat, board",function()
 local m=new();m:startRound(1);local s=m.Seats[1];m:giveItem(s,"MoonDial");m:beginTurn(s)
 eq(m:useItem(m.Seats[2],1),false);eq(m:useItem(s,0/0),false);eq(m:useItem(s,1.5),false)
 m:rollTurn(s);eq(m:useItem(s,1),false);eq(#s.Items,1)
 m:beginTurn(s);assert(m:useItem(s,1));eq(#s.Items,0);eq(m.Orientation,1)
 m:giveItem(s,"MoonDial");eq(m:useItem(s,1),false)
 m:endTurn();m:startRound(2);m:beginTurn(s);eq(m:useItem(s,1),false)
 m.Board.Bridge=nil;eq(m:useItem(s,1),false)
end)
test("Moon Dial cannot cancel automatic rotation or starve zones",function()
 local m=new()
 for round=1,8 do
  m:startRound(round)
  if m:canUseMoonDial() then
   m:beginTurn(m.Seats[1]);m:giveItem(m.Seats[1],"MoonDial");assert(m:useItem(m.Seats[1],1));m:endTurn()
   eq(m.DialReadyRound,round+2)
  else
   -- At least every other round nobody can interfere with scheduled alignment.
   eq(round%2,0)
  end
  local before=m.Orientation;assert(m:finishBoardRound());eq(m.Orientation,1-before)
 end
end)
test("bots prefer Moon Dial for affordable newly reachable Crown and wait when far from dock",function()
 local m=new();m:startRound(1);local s=m.Seats[1];Wallet.add(s.Participant,30)
 s.SpaceId=9;m.CollectibleSpace=34;assert(Bot.itemScore(m,s,"MoonDial")>0)
 s.SpaceId=10;eq(Bot.itemScore(m,s,"MoonDial"),0)
 eq(m.Orientation,0);eq(m.BridgeRevision,0)
end)
test("bot lookahead never follows a disconnected exit",function()
 local m=new();local s=m.Seats[1]
 for orientation=0,1 do
  m.Orientation=orientation;m.DistanceCache=nil
  for _,dock in Bridge.Docks do
   local opts=m:nextOptions(dock)
   local chosen=Bot.choosePath(m,s,opts,Bot.profile("Hard"))
   assert(table.find(opts,opts[chosen]))
   if #opts==1 then eq(chosen,1) end
  end
 end
end)
test("world: only one deck, bridge tile transforms and recovery",function()
 local m=new();local w=World.build(m.Board,Types,Vector3.new(0,200,0))
 local success,problem=pcall(function()
  assert(w.Moving:FindFirstChild("SingleStraightDeck"));eq(w.Folder:FindFirstChild("Base"),nil)
  eq(w.Folder.MoonMechanism.CanCollide,false)
  local old=w.Tops[33];w:setBridgeAngle(-math.pi/2)
  assert(math.abs(w.Tops[33].X-27)<0.01);assert((old-w.Tops[33]).Magnitude>30)
  assert((w.Tiles[33].Position+Vector3.new(0,0.5,0)-w.Tops[33]).Magnitude<0.01)
  assert(w:isMisplaced(Vector3.new(500,0,0),33))
  eq(w:isMisplaced(w:spaceCFrame(33,1).Position,33),false)
  w:setBridgeState(m:bridgeState());eq(w.DockLabels[2].Text,"CLOSED · LOOP")
 end)
 w:destroy();assert(success,problem)
end)
test("validation rejects bypasses, broken local loops and invalid timing",function()
 local copy=table.clone(Data);copy.Spaces={}
 for _,space in Data.Spaces do local row=table.clone(space);row.Next=table.clone(space.Next);table.insert(copy.Spaces,row) end
 table.insert(copy.Spaces[3].Next,11);assert(BoardLayout.validate(copy,Types))
 table.remove(copy.Spaces[3].Next);copy.Spaces[3].Next={5};assert(BoardLayout.validate(copy,Types))
 copy.Spaces[3].Next={4};copy.Bridge=table.clone(Data.Bridge);copy.Bridge.EveryRounds=0;assert(BoardLayout.validate(copy,Types))
end)
test("Crown and trap markers travel with bridge tiles",function()
 local m=new();local w=World.build(m.Board,Types,Vector3.new(0,200,0))
 w:setCollectible(34,"Crown");w:setTraps({[35]={}});w:setBridgeAngle(-math.pi/2)
 local ok1=(w.Marker.Position-w.Tops[34]-Vector3.new(0,7,0)).Magnitude<0.01
 local ok2=(w.TrapMarkers[35].Position-w.Tops[35]-Vector3.new(0,0.2,0)).Magnitude<0.01
 w:destroy();assert(ok1 and ok2)
end)
return function()
 local passed,failed=0,0
 for _,t in tests do
  local success,problem=pcall(t[2])
  if success then passed+=1 else failed+=1;warn("[FestivalTests] "..t[1]..": "..tostring(problem)) end
 end
 print(("[FestivalTests] %d passed, %d failed"):format(passed,failed));return passed,failed
end
