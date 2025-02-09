local socket = require("socket")
local bitser = require("lib.bitser")

local serialise = bitser.dumps
local deserialise = bitser.loads

--#region Types

---@alias ip string
---@alias port number
---@alias clientID number

---@class Client
---@field ip ip
---@field port port
---@field clientID clientID

---@alias PKT_TYPE INTERNAL_PKT_TYPE -- should be a number, but in practice anything works fine

---@class Packet
---@field type PKT_TYPE
---@field data any

---@alias PacketHandlerCallback fun(self: LunaMesh, pkt: Packet, ip: ip, port: port, client: Client)

---@alias INTERNAL_PKT_TYPE number
local INTERNAL_PKT_TYPE = {
	CONNECT = {
		REQUEST = 101,
		ACCEPT = 102,
		DENY = 103,
		-- CLOSE = 104, --we can't trust that a close connection actually comes from the server, yet
	},
}

---@enum LunaMeshHooks
local HOOKS = {
	clientAdded = "clientAdded",

	connetionSuccessful = "connetionSuccessful",
}

--#endregion

---@class LunaMesh
local LunaMesh = {
	socket = socket.udp(),
	handlers = {},
	hooks = {},

	--client
	state = "disconnected",
	clientID = nil,

	--server
	clients = {},
	client_count = 1,
	max_clients = 12,
}
LunaMesh.__index = LunaMesh

function LunaMesh.new()
	local self = setmetatable({}, LunaMesh)
	self.socket:settimeout(0)
	return self
end

---@param ip ip?
---@param port port
function LunaMesh:setServer(ip, port)
	assert(port, "Port is required")
	self.socket:setsockname(ip or "*", port)
	self.is_server = true
end

function LunaMesh:listen()
	if self.is_server then
		self:_serverListen()
	else
		self:_clientListen()
	end
end
function LunaMesh:_serverListen()
	repeat
		local ser_pkt, ip, port = self.socket:receivefrom()
		local pkt = ser_pkt and deserialise(ser_pkt)

		if pkt then
			self:_handlePacket(pkt, ip, port)
		end

	until not ser_pkt
end
function LunaMesh:_clientListen()
	repeat
		local ser_pkt, err = self.socket:receive()
		local pkt = ser_pkt and deserialise(ser_pkt)
		if pkt then
			self:_handlePacket(pkt)
		end

	until not ser_pkt
end

function LunaMesh:_handlePacket(pkt, ip, port)
	local pkt_type = pkt.type

	if pkt_type and self.handlers[pkt_type] then
		local client = self:matchClient(ip, port)
		self.handlers[pkt_type](self, pkt, ip, port, client)
	end
end

---Associate a handler (function) to a packet type
---@param pkt_type PKT_TYPE
---@param handler PacketHandlerCallback
function LunaMesh:setPktHandler(pkt_type, handler)
	assert(pkt_type, "Packet type is required")
	assert(handler and type(handler) == "function", "Handler must be a function")
	assert(not self.handlers[pkt_type], "Cannot assign two handlers to the same packet type")

	self.handlers[pkt_type] = handler
end

---Add's a hook to listen for
---@param hookID LunaMeshHooks
---@param func function
function LunaMesh:subscribeHook(hookID, func)
	assert(hookID, "A Hook ID is required")
	assert(func and type(func) == "function", "A function is required")
	assert(not self.hooks[hookID], "Cannot assign two hooks to the same event")

	self.hooks[hookID] = func
end

---Calls a hook
function LunaMesh:_callHook(hookID, ...)
	if self.hooks[hookID] then
		self.hooks[hookID](self, ...)
	end
end

--#region Sending/Creating packets

---@param pkt_type PKT_TYPE
function LunaMesh:createPkt(pkt_type, data, ...)
	assert(pkt_type, "Packet type is required")
	local pkt = {
		type = pkt_type,
		data = data, --fine if nil
		...,
	}
	return pkt
end

---@param pkt Packet
---@param ip ip
---@param port port
function LunaMesh:sendToAddress(pkt, ip, port)
	local ser_pkt = serialise(pkt)
	self.socket:sendto(ser_pkt, ip, port)
end

---@param client Client
function LunaMesh:sendToClient(pkt, client)
	self:sendToAddress(pkt, client.ip, client.port)
end

---@param pkt Packet
function LunaMesh:sendToServer(pkt)
	local ser_pkt = serialise(pkt)
	self.socket:send(ser_pkt)
end

---@param pkt Packet
function LunaMesh:sendToAllClients(pkt)
	local ser_pkt = serialise(pkt)
	for _, client in pairs(self.clients) do
		self.socket:sendto(ser_pkt, client.ip, client.port)
	end
end

--#endregion

--#region Client management
function LunaMesh:_generateClientID()
	self.client_count = self.client_count + 1
	return self.client_count
end
---@return Client
function LunaMesh:addClient(ip, port)
	local clientID = self:_generateClientID()
	local client = { ip = ip, port = port, clientID = clientID }
	self.clients[clientID] = client

	self:_callHook(HOOKS.clientAdded, client)
	return client
end

---@param ip ip
---@param port port
---@return Client?
function LunaMesh:matchClient(ip, port)
	for _, client in pairs(self.clients) do
		if client.ip == ip and client.port == port then
			return client
		end
	end
end
--#endregion

--#region Pretty API wrappers

---Alias of `LunaMesh:listen()`
function LunaMesh:update()
	self:listen()
end

function LunaMesh:isConnected()
	return self.state == "connected"
end

---@param timeout number
---@return boolean, clientID
function LunaMesh:waitUntilClientConnected(timeout)
	local accumulator = 0

	repeat
		self:listen()
		socket.sleep(0.1)
		accumulator = accumulator + 0.1
	until self:isConnected() or accumulator >= timeout

	return self:isConnected(), self.clientID
end

--#endregion

--#region Connection protocol
-- Client connection

---@param ip ip
---@param port port
function LunaMesh:connect(ip, port)
	self.socket:setsockname("*", 0) --use ephemeral port

	local pkt = self:createPkt(INTERNAL_PKT_TYPE.CONNECT.REQUEST, nil)
	self.socket:setpeername(ip, port)
	self:sendToServer(pkt)

	self.state = "connecting"
end
local function connection_successful(self, pkt)
	if self.state == "connecting" then
		local data = pkt.data
		self.state = "connected"
		self.clientID = data.clientID

		self:_callHook(HOOKS.connetionSuccessful, self.clientID)
	end
end
local function connection_denied(self, pkt)
	-- Can't yet trust a deny packet, and allow someone to disconnect us from a match
	if self.state == "connecting" then
		self.state = "disconnected"
		self.socket:setpeername("*")
	end
end
LunaMesh:setPktHandler(INTERNAL_PKT_TYPE.CONNECT.ACCEPT, connection_successful)
LunaMesh:setPktHandler(INTERNAL_PKT_TYPE.CONNECT.DENY, connection_denied)

-- Server connection
local function connection_requested(self, pkt, ip, port)
	local client = self:addClient(ip, port)
	local answer_pkt = self:createPkt(INTERNAL_PKT_TYPE.CONNECT.ACCEPT, { clientID = client.clientID })
	self:sendToClient(answer_pkt, client)
end
LunaMesh:setPktHandler(INTERNAL_PKT_TYPE.CONNECT.REQUEST, connection_requested)
--#endregion

return LunaMesh.new()
