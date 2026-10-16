-- Pure topology; no yields, rendering, randomness or mutation during queries.
local Bridge = {}
Bridge.Docks = {1,9,17,25}
function Bridge.isMoving(id) return id >= 33 and id <= 36 end
function Bridge.connected(zone, orientation)
 return zone == 0 or (if orientation == 0 then zone == 1 or zone == 3 else zone == 2 or zone == 4)
end
function Bridge.options(board, id, orientation)
 local options = {}
 for _, target in board:nextOptions(id) do
  local fromZone,toZone = board:get(id).Zone,board:get(target).Zone
  if fromZone == toZone or (Bridge.connected(fromZone,orientation) and Bridge.connected(toZone,orientation)) then
   table.insert(options,target)
  end
 end
 return options
end
function Bridge.distance(board, from, target, orientation)
 local queue,seen,head = {from},{[from]=0},1
 while queue[head] do
  local id=queue[head]; head+=1
  if id==target then return seen[id] end
  for _,nextId in Bridge.options(board,id,orientation) do
   if seen[nextId]==nil then seen[nextId]=seen[id]+1;table.insert(queue,nextId) end
  end
 end
 return math.huge
end
function Bridge.snapshot(match)
 if not match.Board.Bridge then return nil end
 local docks={}
 for zone,id in Bridge.Docks do
  table.insert(docks,{SpaceId=id,Name=match.Board.Zones[zone],Open=Bridge.connected(zone,match.Orientation)})
 end
 return { Orientation=match.Orientation, Alignment=if match.Orientation==0 then "N–S" else "E–W",
  NextAlignment=if match.Orientation==0 then "E–W" else "N–S", Revision=match.BridgeRevision,
  DialReadyRound=match.DialReadyRound, NextRound=match.LastRotationRound+match.Board.Bridge.EveryRounds,
  Docks=docks }
end
-- Validate this mechanism's contract as well as the union graph checked by BoardLayout.
function Bridge.validate(data)
 if not data.Bridge then return nil end
 local rule=data.Bridge
 if type(rule.EveryRounds)~="number" or rule.EveryRounds<1 or rule.EveryRounds%1~=0 then return "bridge needs a positive round interval" end
 if type(rule.WarningSeconds)~="number" or rule.WarningSeconds<0 or type(rule.RotationSeconds)~="number" or rule.RotationSeconds<=0 then return "bridge needs valid warning and rotation durations" end
 if type(rule.DialCooldownRounds)~="number" or rule.DialCooldownRounds<2 then return "Moon Dial cooldown must preserve a full automatic interval" end
 if not data.Zones or #data.Zones~=4 or #data.Spaces~=36 then return "moon bridge needs four eight-space zones and four moving spaces" end
 local byId={}
 for _,space in data.Spaces do byId[space.Id]=space end
 for zone=1,4 do
  for n=1,8 do
   local id=(zone-1)*8+n
   local space=byId[id]
   if not space or space.Zone~=zone or space.Next[1]~=(zone-1)*8+n%8+1 then return "each zone needs an uninterrupted local loop" end
   for _,target in space.Next do
    local allowed=target==(zone-1)*8+n%8+1 or (n==1 and target==(if zone<=2 then 33 else 36))
    if not allowed then return "zone edge bypasses the rotating bridge" end
   end
  end
 end
 local expected={ [33]={34,1,9}, [34]={33,35}, [35]={34,36}, [36]={35,17,25} }
 for id,edges in expected do
  local space=byId[id]
  if not space or space.Zone~=0 or #space.Next~=#edges then return "invalid straight bridge" end
  for _,target in edges do if not table.find(space.Next,target) then return "invalid bridge connection" end end
 end
 if not table.find(data.CrownSpaces,34) or not table.find(data.CrownSpaces,35) then return "bridge needs configured Crown fallback spaces" end
 return nil
end
return Bridge
