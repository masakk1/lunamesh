local socket = require("socket")
local bitser = require("lib.bitser")

local serialise = bitser.dumps
local deserialise = bitser.loads

--#region Types

---@alias ip string
---@alias port number
---@alias clientID number | any

---@class Client
---@field ip ip
---@field port port
---@field clientID clientID

---@class Packet
---@field type INTERNAL_PKT_TYPE | number | any -- should be a number, but in practice anything works fine
---@field data any

---@alias PKT_TYPE INTERNAL_PKT_TYPE

---@alias PacketHandlerCallback fun(self: LunaMesh, pkt: Packet, ip: ip?, port: port?, client: Client?)

---@alias INTERNAL_PKT_TYPE number
local INTERNAL_PKT_TYPE = {
	CONNECT = {
		REQUEST = 101,
		ACCEPT = 102,
		DENY = 103,
		-- CLOSE = 104, --we can't trust that a close connection actually comes from the server, yet
	},
}

--#endregion

---@class LunaMesh
local LunaMesh = {
	socket = socket.udp(),
	handlers = {},

	--client
	state = "disconnected",

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

---@param ip ip | nil
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
		self.handlers[pkt_type](self, pkt, ip, port)
	end
end

---Add's a function to handle specific packets
---@param pkt_type PKT_TYPE
---@param handler PacketHandlerCallback
function LunaMesh:addPktHandler(pkt_type, handler)
	assert(pkt_type, "Packet type is required")
	assert(type(handler) == "function", "Handler must be a function")
	self.handlers[pkt_type] = handler
end

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

--#region Sending packets

---@param pkt Packet
---@ip string
---@port number
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

	return client
end

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
LunaMesh:addPktHandler(INTERNAL_PKT_TYPE.CONNECT.ACCEPT, function(self, pkt)
	if self.state == "connecting" then
		self.state = "connected"
	end
end)
LunaMesh:addPktHandler(INTERNAL_PKT_TYPE.CONNECT.DENY, function(self, pkt)
	-- Can't yet trust a deny packet, and allow someone to disconnect us from a match
	if self.state == "connecting" then
		self.state = "disconnected"
		self.socket:setpeername("*")
	end
end)

-- Server connection

LunaMesh:addPktHandler(INTERNAL_PKT_TYPE.CONNECT.REQUEST, function(self, pkt, ip, port)
	local client = self:addClient(ip, port)
	local answer_pkt = self:createPkt(INTERNAL_PKT_TYPE.CONNECT.ACCEPT, { clientID = client.clientID })
	self:sendToClient(answer_pkt, client)
end)
--#endregion

return LunaMesh.new()
