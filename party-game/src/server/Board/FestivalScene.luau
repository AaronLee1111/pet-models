-- Editable procedural blockout: shared lamps, rocks, crystals and seven landmark groups.
-- No external assets, unions, textures, or per-frame effects. All decoration is noncolliding.
local Scene={}
local gold=Color3.fromRGB(241,180,67)
local stone=Color3.fromRGB(156,133,185)
local cyan=Color3.fromRGB(95,221,255)
local pink=Color3.fromRGB(220,120,255)
local function part(parent,name,size,cf,color,material,collide,shape)
 local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color
 p.Material=material or Enum.Material.SmoothPlastic;p.Anchored=true;p.CanCollide=collide==true
 p.CanTouch=false;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 if shape then p.Shape=shape end
 p.Parent=parent;return p
end
local function cylinder(parent,name,radius,height,cf,color,collide)
 return part(parent,name,Vector3.new(height,radius*2,radius*2),cf*CFrame.Angles(0,0,math.pi/2),color,nil,collide,Enum.PartType.Cylinder)
end
local function group(parent,name) local m=Instance.new("Model");m.Name=name;m.Parent=parent;return m end
local function lamp(parent,at)
 part(parent,"LanternPost",Vector3.new(0.7,6,0.7),CFrame.new(at+Vector3.new(0,3,0)),gold)
 part(parent,"Lantern",Vector3.new(2,2.8,2),CFrame.new(at+Vector3.new(0,6.5,0)),Color3.fromRGB(255,204,85),Enum.Material.Neon)
end
local function crystal(parent,at,color,scale)
 local p=part(parent,"Crystal",Vector3.new(2,6,2)*scale,CFrame.new(at+Vector3.new(0,3*scale,0))*CFrame.Angles(0,0,0.2),color,Enum.Material.Neon)
 return p
end
function Scene.build(world)
 local origin=world.Origin
 local folder=world.Folder
 local centers={Vector3.new(0,0,-54),Vector3.new(54,0,0),Vector3.new(0,0,54),Vector3.new(-54,0,0)}
 for zone,offset in centers do
  local island=group(folder,world.Board.Zones[zone])
  local c=origin+offset
  cylinder(island,"Island",25,4,CFrame.new(c-Vector3.new(0,2,0)),stone,true)
  cylinder(island,"Garden",23,0.5,CFrame.new(c+Vector3.new(0,0.1,0)),Color3.fromRGB(97,151,147),false)
  for i=1,8 do
   local a=i*math.pi/4
   local rim=c+Vector3.new(math.cos(a)*22,-5,math.sin(a)*22)
   part(island,"FloatingRock",Vector3.new(9,12+(i%3)*3,9),CFrame.new(rim)*CFrame.Angles(0,a,0.15),stone)
   if i%2==0 then lamp(island,rim+Vector3.new(0,6,0)) end
   crystal(island,rim+Vector3.new(0,7,0),if i%2==0 then cyan else pink,0.4)
  end
 end
 local plaza=group(folder,"MoonflowerFountain")
 local c=origin+centers[1]
 cylinder(plaza,"Basin",8,2,CFrame.new(c+Vector3.new(0,2,0)),gold)
 cylinder(plaza,"Water",7,0.3,CFrame.new(c+Vector3.new(0,3.2,0)),cyan)
 for i=1,6 do
  local angle=i*math.pi/3
  part(plaza,"Petal",Vector3.new(4,2,7),CFrame.new(c+Vector3.new(math.cos(angle)*3,6,math.sin(angle)*3))*CFrame.Angles(0,-angle,0.5),pink,Enum.Material.Neon,false,Enum.PartType.Ball)
 end
 crystal(plaza,c+Vector3.new(0,5,0),gold,0.8)
 local pavilion=group(folder,"CrystalPavilion");c=origin+centers[2]
 for _,x in {-5,5} do for _,z in {-5,5} do part(pavilion,"Pillar",Vector3.new(1.3,10,1.3),CFrame.new(c+Vector3.new(x,5,z)),gold) end end
 part(pavilion,"Canopy",Vector3.new(14,3,14),CFrame.new(c+Vector3.new(0,11,0)),stone)
 crystal(pavilion,c+Vector3.new(0,12,0),cyan,0.8)
 for _,x in {-7,0,7} do crystal(pavilion,c+Vector3.new(x,1,0),if x==0 then pink else cyan,0.7) end
 local tree=group(folder,"MoonTree");c=origin+centers[3]
 part(tree,"Trunk",Vector3.new(5,11,5),CFrame.new(c+Vector3.new(0,5,0)),Color3.fromRGB(115,80,120))
 for _,x in {-5,0,5} do
  part(tree,"Canopy",Vector3.new(13,7,12),CFrame.new(c+Vector3.new(x,12-math.abs(x)*0.3,0)),Color3.fromRGB(89,129,235),nil,false,Enum.PartType.Ball)
  lamp(tree,c+Vector3.new(x,4,1))
 end
 for _,x in {-10,10} do
  local gate=group(folder,"ShrineGate")
  for _,z in {-3,3} do part(gate,"Post",Vector3.new(1.2,7,1.2),CFrame.new(c+Vector3.new(x,3.5,z)),gold) end
  part(gate,"Lintel",Vector3.new(2,1.5,10),CFrame.new(c+Vector3.new(x,7,0)),Color3.fromRGB(175,78,131))
 end
 local wheel=group(folder,"LanternWheel");c=origin+centers[4]+Vector3.new(0,10,-3)
 for i=1,8 do
  local a=i*math.pi/4
  local p=c+Vector3.new(math.cos(a)*8,math.sin(a)*8,0)
  part(wheel,"Spoke",Vector3.new(0.5,8,0.5),CFrame.new((p+c)/2)*CFrame.Angles(0,0,a-math.pi/2),gold)
  part(wheel,"WheelLantern",Vector3.new(2,2,2),CFrame.new(p),gold,Enum.Material.Neon)
 end
 part(wheel,"Support",Vector3.new(2,11,2),CFrame.new(c-Vector3.new(0,5,0)),stone)
 for _,x in {-9,9} do
  local tent=group(folder,"FestivalTent")
  local t=origin+centers[4]+Vector3.new(x,0,6)
  part(tent,"Counter",Vector3.new(6,3,4),CFrame.new(t+Vector3.new(0,1.5,0)),gold)
  part(tent,"Roof",Vector3.new(8,2,7),CFrame.new(t+Vector3.new(0,6,0)),pink)
  for _,dx in {-3,3} do part(tent,"Pole",Vector3.new(0.5,6,0.5),CFrame.new(t+Vector3.new(dx,3,0)),gold) end
 end
 -- Decorative circular mechanism has NO walkable surface outside the straight deck.
 cylinder(folder,"MoonMechanism",27,2,CFrame.new(origin-Vector3.new(0,2,0)),stone,false)
 local moving=group(folder,"RotatingMoonBridge")
 moving.WorldPivot=CFrame.new(origin)
 part(moving,"SingleStraightDeck",Vector3.new(10,1,63),CFrame.new(origin),Color3.fromRGB(233,215,198),nil,true)
 for _,x in {-5.5,5.5} do
  part(moving,"Rail",Vector3.new(0.6,2,61),CFrame.new(origin+Vector3.new(x,1,0)),gold)
 end
 world.Moving=moving
 world.MovingLocal={}
 for id=33,36 do
  world.Tiles[id].Parent=moving
  world.MovingLocal[id]=world.Tops[id]-origin
 end
 world.DockLabels={}
 world.DockBarriers={}
 for zone,id in {1,9,17,25} do
  local at=world.Tops[id]
  local sign=part(folder,"DockStatus"..zone,Vector3.new(1,1,1),CFrame.new(at+Vector3.new(0,5,0)),gold)
  sign.Transparency=1
  local gui=Instance.new("BillboardGui");gui.Size=UDim2.fromOffset(135,30);gui.AlwaysOnTop=true;gui.Parent=sign
  local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=0.3
  label.BackgroundColor3=stone;label.TextColor3=Color3.new(1,1,1);label.TextScaled=true;label.Font=Enum.Font.FredokaOne;label.Parent=gui
  world.DockLabels[zone]=label
  local inward=(origin-at)*Vector3.new(1,0,1)
  inward=inward.Unit
  local position=at+inward*4.7+Vector3.new(0,1,0)
  world.DockBarriers[zone]=part(folder,"ClosedDockBarrier"..zone,Vector3.new(9,2,0.7),CFrame.lookAt(position,position+inward),Color3.fromRGB(255,105,120),Enum.Material.Neon,true)
  local surface=Instance.new("SurfaceGui");surface.Face=Enum.NormalId.Top;surface.Parent=world.Tiles[id]
  local status=Instance.new("TextLabel");status.Name="ExitStatus";status.Size=UDim2.fromScale(1,1);status.BackgroundTransparency=1
  status.TextScaled=true;status.Font=Enum.Font.FredokaOne;status.TextColor3=Color3.new(1,1,1);status.Parent=surface
 end
 Scene.align(world,0)
end
function Scene.align(world,angle)
 world.Moving:PivotTo(CFrame.new(world.Origin)*CFrame.Angles(0,angle,0))
 for id,offset in world.MovingLocal do world.Tops[id]=(CFrame.new(world.Origin)*CFrame.Angles(0,angle,0)):PointToWorldSpace(offset) end
end
function Scene.status(world,state)
 for zone,label in world.DockLabels do
  local open=state.Docks[zone].Open
  label.Text=if open then "BRIDGE OPEN" else "CLOSED · LOOP"
  local barrier=world.DockBarriers[zone]
  barrier.Transparency=if open then 1 else 0
  barrier.CanCollide=not open
  world.Tiles[({1,9,17,25})[zone]].SurfaceGui.ExitStatus.Text=if open then "OPEN" else "CLOSED"
  label.TextColor3=if open then Color3.fromRGB(110,255,180) else Color3.fromRGB(255,170,130)
 end
end
return Scene
