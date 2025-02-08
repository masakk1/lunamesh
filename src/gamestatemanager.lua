local GameStateManager = {}
GameStateManager.__index = GameStateManager

function GameStateManager.new()
	local self = setmetatable({}, GameStateManager)
	return self
end

function GameStateManager:capture(World) end

return GameStateManager.new()
