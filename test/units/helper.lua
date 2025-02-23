local LunaMesh = require("lunamesh")
local socket = require("socket")
local lunamesh = require("lunamesh")
local bitser = require("lib.bitser")
lunamesh:setSerialiser(bitser.dumps, bitser.loads)

local helper = {}
helper.__index = helper
helper.base_port = 47000
local seed = os.time()
math.randomseed(seed)
helper.port_accumulator = math.random(0, 900)

function helper.setupFullClientServerConnection()
	local port = helper.base_port + helper.port_accumulator
	helper.port_accumulator = helper.port_accumulator + 1

	local server, client = helper.setupClientServer(port)

	local closed = false
	local function closed_check()
		return closed
	end

	local server_thread = helper.serverHostCorountine(server)
	local client_thread = helper.clientConnectionCorountine(client, function()
		closed = true
	end)
	return server, client, server_thread, client_thread, closed_check
end

function helper.setupClientServer(port)
	local server = LunaMesh.fresh_instance()
	local client = LunaMesh.fresh_instance()
	server:setSerialiser(bitser.dumps, bitser.loads)
	client:setSerialiser(bitser.dumps, bitser.loads)

	server:setServer("127.0.0.1", port)
	client:connect("127.0.0.1", port)
	return server, client
end

function helper.serverHostCorountine(server)
	assert(server, "must provide a server")
	local server_thread = function(dt)
		server:listen(dt)
	end

	return server_thread
end

function helper.clientConnectionCorountine(client, mark_finish)
	assert(mark_finish, "must provide a function to mark the connection loop as done")
	assert(client, "must provide a connected client")

	local client_thread = function(dt)
		client:listen(dt)

		if client:isConnected() then
			mark_finish()
		end
	end

	return client_thread
end

function helper.runCorountineLoopUntil(closed_check, timeout, update_funcs)
	local accumulator = 0
	while not closed_check() and accumulator <= timeout do
		for _, update_func in pairs(update_funcs) do
			update_func(0.1)
		end
		socket.sleep(0.1)
		accumulator = accumulator + 0.1
	end
end

return helper
