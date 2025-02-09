local lunamesh = require("lunamesh")
local PKT_TYPE = require("src.pkt_types")

local Player = require("src.player")

local entityList = {}
local player

--#region Networking

-- ECHO
local function answered_echo(self, pkt)
	print("Received an echo response", pkt.data)
end

-- SYNC
local function update_world(self, pkt)
	local world_state = pkt.data
	if not world_state then
		return
	end

	for entityID, entity_state in pairs(world_state) do
		local entity = entityList[entityID]
		if not entity then
			print("Creating new entity", entityID)
			entity = Player.new()
			entityList[entityID] = entity
		end

		entity:applyState(entity_state)
	end
end
lunamesh:addPktHandler(PKT_TYPE.ECHO.ANSWER, answered_echo)
lunamesh:addPktHandler(PKT_TYPE.SYNC.WORLD, update_world)
--#endregion

--#region Entry point

function Load(args)
	lunamesh:connect("127.0.0.1", 18080)
	local connected, clientID = lunamesh:waitUntilClientConnected(10)
	assert(connected, "Timed out")

	print("Connected")

	player = Player.new()
	entityList[clientID] = player
end
function Update(dt) end

function FixedUpdate(fdt)
	lunamesh:listen()

	for _, entity in pairs(entityList) do
		if not entity.is_player then
			entity:update(fdt)
		end
	end

	player:update(fdt)
end
function Draw()
	for _, entity in pairs(entityList) do
		entity:draw()
	end
end

--#endregion
