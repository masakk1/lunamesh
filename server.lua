local lunamesh = require("lunamesh")
local PKT_TYPE = require("src.pkt_types")

local Player = require("src.player")

local clientList = {}
local entityList = {}

--#region Networking

-- ECHO
local function echo_request(self, pkt, ip, port) --connection-less
	print("Received an echo request", ip, port, pkt.data)

	local echo_pkt = self:createPkt(PKT_TYPE.ECHO.ANSWER, pkt.data or "")
	self:sendToAddress(echo_pkt, ip, port)
end

-- SYNC
local function update_clients()
	local world_state = {}

	for clientID, client in pairs(clientList) do
		local player = client.player
		world_state[clientID] = player:getState()
	end

	lunamesh:sendToAllClients(lunamesh:createPkt(PKT_TYPE.SYNC.WORLD, world_state))
end
local function client_input(self, pkt, ip, port, client)
	if not client then
		return
	end -- which means that it isn't a known and authenticated client

	local input_state = pkt.data
	local player = clientList[client.clientID].player

	-- should probably validate the input
	player:applyInput(input_state)
end
local function on_client_added(self, client)
	clientList[client.clientID] = client

	local player = Player.new()
	clientList[client.clientID].player = player
	entityList[client.clientID] = player
end

lunamesh:setPktHandler(PKT_TYPE.ECHO.REQUEST, echo_request)
lunamesh:setPktHandler(PKT_TYPE.SYNC.INPUT, client_input)
lunamesh:subscribeHook("clientAdded", on_client_added)
--#endregion

--#region Entry point
function Load(args)
	lunamesh:setServer("127.0.0.1", 18080)
end
function Update(dt) end
function FixedUpdate(fdt)
	lunamesh:listen(fdt)

	for _, entity in pairs(entityList) do
		if not entity.is_player then
			entity:update(fdt)
		end
	end

	update_clients()
end
function Draw()
	for _, entity in pairs(entityList) do
		entity:draw()
	end
end
--#endregion
