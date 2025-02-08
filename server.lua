local lunamesh = require("lunamesh")
local PKT_TYPE = require("src.pkt_types")

local Player = require("src.player")

local clientList = {}
local entityList = {}

--#region Networking
-- ECHO
lunamesh:addPktHandler(PKT_TYPE.ECHO.REQUEST, function(self, pkt, ip, port)
	print("Received an echo request", ip, port, pkt.data)

	local echo_pkt = self:createPkt(PKT_TYPE.ECHO.ANSWER, pkt.data or "")
	self:sendToAddress(echo_pkt, ip, port)
end)

-- SYNC
local function updateClients()
	local world_state = {}

	for clientID, client in pairs(clientList) do
		local player = client.player
		world_state[clientID] = player:getState()
	end

	lunamesh:sendToAllClients(lunamesh:createPkt(PKT_TYPE.SYNC.WORLD, world_state))
end
lunamesh:addPktHandler(PKT_TYPE.SYNC.INPUT, function(self, pkt, ip, port, client)
	if not client then
		return
	end -- which means that it isn't a known and authenticated client

	local input_state = pkt.data
	local player = clientList[client.clientID].player

	-- should probably validate the input
	player:applyInput(input_state)
end)

lunamesh:addHook("clientAdded", function(self, client)
	clientList[client.clientID] = client

	local player = Player.new()
	clientList[client.clientID].player = player
	entityList[client.clientID] = player
end)
--#endregion

--#region Entry point
function Load(args)
	lunamesh:setServer("127.0.0.1", 18080)
end
function Update(dt) end
function FixedUpdate(fdt)
	lunamesh:listen()

	for _, entity in pairs(entityList) do
		if not entity.is_player then
			entity:update(fdt)
		end
	end

	updateClients()
end
function Draw()
	for _, entity in pairs(entityList) do
		entity:draw()
	end
end
--#endregion
