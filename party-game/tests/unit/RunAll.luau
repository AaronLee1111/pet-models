--[[
	Runs every unit test suite. Command bar (edit mode is fine):
	  require(game.ServerStorage.PartyTests.RunAll)()
]]

return function()
	local passed, failed = 0, 0
	for _, name in { "BoardTests", "FestivalTests", "EconomyTests", "ModeTests", "MinigameTests", "ShopTests", "ReclaimTests", "TrailTangleTests", "BumperBoutTests", "OnboardingTests", "SunnyLoopV2Tests" } do
		local p, f = require(script.Parent[name])()
		passed += p
		failed += f
	end
	print(("[RunAll] %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
