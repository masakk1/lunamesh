local socket = require("socket")

-- Require bitser in multiple locations
local originalpackagepath = package.path
package.path = package.path .. ";./lib/?.lua"
local bitser = require("bitser")
package.path = originalpackagepath

local serialise = bitser.dumps
local deserialise = bitser.loads
local _LUNAMESH_DEBUG = true
local _LUNAMESH_RELIABLES_DEBUG = true

local function debugprint(...)
	if _LUNAMESH_DEBUG then
		print(...)
	end
end
local function debugprintif(condition, ...)
	if _LUNAMESH_DEBUG and condition then
		print(...)
	end
end

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

---@alias PacketHandlerCallback fun(self: LunaMesh, pkt: Packet, ip: ip?, port: port?, client: Client?)

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

---@class LunaMesh
---@field socket any
---@field handlers table<PKT_TYPE, PacketHandlerCallback>
---@field hooks table<LunaMeshHooks, PacketHandlerCallback>
---@field state "disconnected" | "connecting" | "connected"
---@field clientID clientID?
---@field clients table<clientID, Client>
---@field client_count number
---@field max_clients number
---@field accumulators table<string, { t: number, threshold: number }>
---@field reliable_pkt_watcher table<number, { pkt: Packet, ip: ip, port: port, count: number }>
---@field reliable_pkt_seq number
---@field reliable_pkt_count_giveup number
local LunaMesh = {}
LunaMesh.__index = LunaMesh

--#endregion

function LunaMesh.fresh_instance(...)
	assert(select("#", ...) == 0, "expected 0 arguments, got `" .. select("#", ...) .. "` instead. Did you use `:`?`")
	local self = setmetatable({
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

		accumulators = {
			unacked_rel_pkts = { t = 0, threshold = 1 },
		},

		reliable_pkt_watcher = {},
		reliable_pkt_seq = 1,
		reliable_pkt_count_giveup = 10,
	}, LunaMesh)

	self.socket:settimeout(0)

	self:_invokeInternalProtocols()
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
	pkt.relc = config.reliable_custom or (config.reliable_custom_ack and true or nil)
	pkt.rela = config.reliable_auto
	pkt.seq = config.reliable_custom_ack
	if pkt.relc and not pkt.seq then
		pkt.seq = self.reliable_pkt_seq
		self.reliable_pkt_seq = self.reliable_pkt_seq + 1
	end

	return pkt
end

---@param pkt Packet
---@param ip ip
---@param port port
function LunaMesh:sendToAddress(pkt, ip, port)
	self:_matchOutgoingInternalProtocolHandler(pkt, ip, port)
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
function LunaMesh:_invokeInternalProtocols()
	self:_internalProtocolReliablePackets()
	self:_internalProtocolConnection()
end

function LunaMesh:_updateInternalProtocolHandlers(dt)
	local acc = self.accumulators.unacked_rel_pkts
	acc.t = acc.t + dt
	if acc.t >= acc.threshold then
		acc.t = acc.t - acc.threshold
		self:_watchUnacknowledgedReliablePackets()
	end
end
function LunaMesh:_matchIncomingInternalProtocolHandler(pkt, ip, port, client)
	if pkt.relc or pkt.rela then --incoming reliable_custom or auto
		self:_handleIncomingReliablePacket(pkt, ip, port, client)
	end
end
function LunaMesh:_matchOutgoingInternalProtocolHandler(pkt, ip, port, client)
	if pkt.rela or pkt.relc then
		self:_handleOutgoingReliablePacket(pkt, ip, port, client)
	end
end

-- Reliable packets
function LunaMesh:_handleIncomingReliablePacket(pkt, ip, port, client)
	if not pkt.rela then
		return
	end
	local ack_pkt = self:createPkt(INTERNAL_PKT_TYPE.RELIABLE.ACK, pkt.seq, { reliable_auto = true })

	if (ip and port) or self.is_server then
		self:sendToAddress(ack_pkt, ip, port)
	else
		self:sendToServer(ack_pkt)
	end
end
function LunaMesh:_handleOutgoingReliablePacket(pkt, ip, port, client)
	local seq = pkt.seq or pkt.data
	if self.reliable_pkt_watcher[seq] then
		return
	end
	self.reliable_pkt_watcher[seq] = { pkt = pkt, ip = ip, port = port, count = 1 }
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
			self:removeReliablePktWatcher(seq)
		end
	end
end
function LunaMesh:removeReliablePktWatcher(seq)
	if seq or not self.reliable_pkt_watcher[seq] then
		return
	end
	table.remove(self.reliable_pkt_watcher, seq)
end
function LunaMesh:_internalProtocolReliablePackets()
	local function remove_auto_reliable_pkt_watcher_from_ack(self, ack_pkt, ip, port, client)
		self:removeReliablePktWatcher(ack_pkt.data)
	end
	self:setPktHandler(INTERNAL_PKT_TYPE.RELIABLE.ACK, remove_auto_reliable_pkt_watcher_from_ack)
end
--#endregion

--#region Connection protocol
-- Client connection

---@param ip ip
---@param port port
function LunaMesh:connect(ip, port)
	self.socket:setsockname("*", 0) --use ephemeral port

	local pkt = self:createPkt(INTERNAL_PKT_TYPE.CONNECT.REQUEST, nil, { reliable_custom = true })
	self.socket:setpeername(ip, port)
	self:sendToServer(pkt)

	self.state = "connecting"
end
function LunaMesh:_internalProtocolConnection()
	local function connection_successful(self, pkt)
		if self.state == "connecting" then
			self:removeReliablePktWatcher(pkt.seq)

			self.state = "connected"
			self.clientID = pkt.data.clientID

			self:_callHook(HOOKS.connetionSuccessful, self.clientID)
		end
	end
	local function connection_denied(self, pkt)
		-- Can't yet trust a deny packet, and allow someone to disconnect us from a match
		if self.state == "connecting" then
			self:removeReliablePktWatcher(pkt.seq)
			self.state = "disconnected"
			self.socket:setpeername("*")
		end
	end
	self:setPktHandler(INTERNAL_PKT_TYPE.CONNECT.ACCEPT, connection_successful)
	self:setPktHandler(INTERNAL_PKT_TYPE.CONNECT.DENY, connection_denied)

	-- Server connection
	local function connection_requested(self, pkt, ip, port)
		local client = self:addClient(ip, port)
		local answer_pkt = self:createPkt(
			INTERNAL_PKT_TYPE.CONNECT.ACCEPT,
			{ clientID = client.clientID },
			{ reliable_custom_ack = pkt.seq, reliable_auto = true }
		)
		self:sendToClient(answer_pkt, client)
	end
	self:setPktHandler(INTERNAL_PKT_TYPE.CONNECT.REQUEST, connection_requested)
end
--#endregion

local instance = LunaMesh.fresh_instance()
return instance
