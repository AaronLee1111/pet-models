-- Four eight-space loops and four spaces on ONE straight rotating bridge.
local spaces = {}
local zones = { "Moonflower Plaza", "Crystal-Flower Garden", "Moon-Tree Grove", "Lantern Fair" }
local points = { {0,2.8}, {1.25,3.25}, {1.7,4.5}, {1.25,5.75}, {0,6.2}, {-1.25,5.75}, {-1.7,4.5}, {-1.25,3.25} }
local kinds = {
 {"Neutral","Gain","Item","Gain","Switch","Reward","Lose","Shop"},
 {"Neutral","Gain","Reward","Gain","Event","Item","Lose","Shop"},
 {"Neutral","Gain","Chaos","Gain","Event","Reward","Item","Shop"},
 {"Neutral","Gain","Duel","Gain","Lose","Reward","Item","Shop"},
}
for zone = 1, 4 do
 for i, at in points do
  local x,z = at[1],at[2]
  for _ = 2, zone do x,z = z,-x end
  local id = (zone-1)*8+i
  local nextIds = { (zone-1)*8+i%8+1 }
  local paths = nil
  if i == 1 then
   table.insert(nextIds, if zone <= 2 then 33 else 36)
   paths = { "Local loop", "Moon bridge" }
  end
  table.insert(spaces, { Id=id, Type=kinds[zone][i], At={x,z}, Next=nextIds, Paths=paths, Zone=zone })
 end
end
for i = 1,4 do
 local nextIds = {}
 if i > 1 then table.insert(nextIds,32+i-1) end
 if i < 4 then table.insert(nextIds,32+i+1) end
 if i == 1 then table.insert(nextIds,1); table.insert(nextIds,9) end
 if i == 4 then table.insert(nextIds,17); table.insert(nextIds,25) end
 table.insert(spaces,{Id=32+i,Type=if i==2 then "Reward" elseif i==3 then "Gain" else "Neutral",At={0,2.25-(i-1)*1.5},Next=nextIds,Zone=0})
end
return {
 Name="MagicalFestival", DisplayName="Magical Festival Island", Start=17,
 CrownSpaces={4,12,20,28,34,35}, Spaces=spaces, Zones=zones,
 -- Board-opening intro (BoardWorld:introSpec): a sky dive-in to the whole map, then each participant floats down
 -- a moonbeam on the open lawn east of Start (17) and walks onto it. Cameras checked clear of props.
 Intro={
  Arrival={ Camera={0.2,-4.0,14}, Look={0.6,-2.8,2} },
  Entry={ {1.17,-2.8,16}, {1.17,-2.8,0} },
  Group={ Camera={-0.08,-3.95,13}, Look={0.1,-2.8,2} },
  Effect="Moonbeam",
 },
 Bridge={ EveryRounds=1, WarningSeconds=2, RotationSeconds=1.5, DialCooldownRounds=2,
  -- Crown relocation when a rotation strands it (Match:chooseCrownSpace).
  CrownMemory=2, CrownLeaderBuffer=4 },
}
