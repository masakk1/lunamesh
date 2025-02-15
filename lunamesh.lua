local socket = require("socket")
local bitser = require("lib.bitser")
local pretty = require("lib.batteries.pretty")

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
	RELIABLE = {
		ACK = 201, --actually kind of useless, since we don't use a handler for this. But whatever :)
	},
}

---@enum LunaMeshHooks
local HOOKS = {
	clientAdded = "clientAdded",

	connetionSuccessful = "connetionSuccessful",
}

--credit: batteries
--maps a sequence {a, b, c} -> {f(a), f(b), f(c)}
-- (automatically drops any nils to keep a sequence, so can be used to simultaneously map and filter)
local function functional_map(t, f)
	local result = {}
	for i = 1, #t do
		local v = f(t[i], i)
		if v ~= nil then
			table.insert(result, v)
		end
	end
	return result
end

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

---@param dt number
function LunaMesh:listen(dt)
	if not dt then
		error("dt is required")
	end
	if self.is_server then
		self:_serverListen()
	else
		self:_clientListen()
	end
	self:_updateInternalProtocolHandlers(dt or 0)
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
		self:_matchIncomingInternalProtocolHandler(pkt, ip, port, client)
		self.handlers[pkt_type](self, pkt, ip, port, client)
	end
end

--#region Internal Protocol Extensions
--#endregion

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
---@param data any?
---@param config table?
function LunaMesh:createPkt(pkt_type, data, config)
	assert(pkt_type, "Packet type is required")
	local pkt = {
		type = pkt_type,
		data = data, --fine if nil
	}
	config = config or {}
	if config.reliable then
		pkt.rel = true
	end
	return pkt
end

---@param pkt Packet
---@param ip ip
---@param port port
function LunaMesh:sendToAddress(pkt, ip, port)
	self:_matchOutgoingInternalProtocolHandler(pkt, ip, port, nil)
	local ser_pkt = serialise(pkt)
	self.socket:sendto(ser_pkt, ip, port)
end

---@param client Client
function LunaMesh:sendToClient(pkt, client)
	self:_matchOutgoingInternalProtocolHandler(pkt, client.ip, client.port, client)
	self:sendToAddress(pkt, client.ip, client.port)
end

---@param pkt Packet
function LunaMesh:sendToServer(pkt)
	self:_matchOutgoingInternalProtocolHandler(pkt)
	local ser_pkt = serialise(pkt)
	self.socket:send(ser_pkt)
end

---@param pkt Packet
function LunaMesh:sendToAllClients(pkt)
	for _, client in pairs(self.clients) do
		self:_matchOutgoingInternalProtocolHandler(pkt, client.ip, client.port)
		local ser_pkt = serialise(pkt)
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
function LunaMesh:isConnected()
	return self.state == "connected"
end

---@param timeout number
---@return boolean, clientID
function LunaMesh:waitUntilClientConnected(timeout)
	local accumulator = 0

	repeat
		self:listen(0.1)
		socket.sleep(0.1)
		accumulator = accumulator + 0.1
	until self:isConnected() or accumulator >= timeout

	return self:isConnected(), self.clientID
end

--#endregion

--#region Internal protocols

LunaMesh.accumulators = {
	unacked_rel_pkts = { t = 0, threshold = 3 },
}
function LunaMesh:_updateInternalProtocolHandlers(dt)
	local acc = self.accumulators.unacked_rel_pkts
	acc.t = acc.t + dt
	if acc.t >= acc.threshold then
		acc.t = acc.t - acc.threshold
		self:_watchUnacknowledgedReliablePackets()
	end
end
function LunaMesh:_matchIncomingInternalProtocolHandler(pkt, ip, port, client)
	if pkt.rel then
		self:_handleIncomingReliablePacket(pkt, ip, port, client)
	end
end
function LunaMesh:_matchOutgoingInternalProtocolHandler(pkt, ip, port, client)
	if pkt.rel and not self.reliable_pkt_watcher[pkt.seq] then
		self:_handleOutgoingReliablePacket(pkt, ip, port, client)
	end
end

-- Reliable packets
LunaMesh.reliable_pkt_watcher = {}
LunaMesh.reliable_pkt_seq = 1
LunaMesh.reliable_pkt_count_giveup = 10
function LunaMesh:_handleIncomingReliablePacket(pkt, ip, port, client)
	local ack_pkt = self:createPkt(INTERNAL_PKT_TYPE.RELIABLE.ACK, pkt.seq)

	if (ip and port) or self.is_server then
		self:sendToAddress(ack_pkt, ip, port)
	else
		self:sendToServer(ack_pkt)
	end
end
function LunaMesh:_handleOutgoingReliablePacket(pkt, ip, port, client)
	pkt.seq = self.reliable_pkt_seq
	self.reliable_pkt_seq = self.reliable_pkt_seq + 1

	self.reliable_pkt_watcher[pkt.seq] = { pkt = pkt, ip = pkt.ip, port = pkt.port, count = 0 }
end
function LunaMesh:_watchUnacknowledgedReliablePackets()
	for seq, meta in pairs(self.reliable_pkt_watcher) do
		if self.is_server then
			self:sendToAddress(meta.pkt, meta.ip, meta.port)
		else
			self:sendToServer(meta.pkt)
		end

		meta.count = meta.count + 1
		if meta.count > self.reliable_pkt_count_giveup then
			self.reliable_pkt_watcher[seq] = nil
		end
	end
end
local function handle_reliable_pkt_acknowledgment(self, ack_pkt, ip, port, client)
	--data is the ACK seq
	if (not ack_pkt.data) or not self.reliable_pkt_watcher[ack_pkt.data] then
		return
	end

	table.remove(self.reliable_pkt_watcher, ack_pkt.data)
end
LunaMesh:setPktHandler(INTERNAL_PKT_TYPE.RELIABLE.ACK, handle_reliable_pkt_acknowledgment)
--#endregion

--#region Connection protocol
-- Client connection

---@param ip ip
---@param port port
function LunaMesh:connect(ip, port)
	self.socket:setsockname("*", 0) --use ephemeral port

	local pkt = self:createPkt(INTERNAL_PKT_TYPE.CONNECT.REQUEST, nil, { reliable = true })
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
	local answer_pkt = self:createPkt(
		INTERNAL_PKT_TYPE.CONNECT.ACCEPT,
		{ clientID = client.clientID },
		{ reliable = true }
	)
	self:sendToClient(answer_pkt, client)
end
LunaMesh:setPktHandler(INTERNAL_PKT_TYPE.CONNECT.REQUEST, connection_requested)
--#endregion

return LunaMesh.new()
