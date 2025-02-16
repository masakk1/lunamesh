local LunaMesh = require("lunamesh").class
local socket = require("socket")

local helper = {}
helper.__index = helper
helper.base_port = 47000
helper.port_accumulator = math.random(0, 900)

function helper.setupFullClientServerConnection()
	local port = helper.base_port + helper.port_accumulator
	helper.port_accumulator = helper.port_accumulator + 1
	print("Using port " .. port)

	local server, client = helper.setupClientServer(port)

	local closed = false
	local function closed_check()
		return closed
	end

	local server_thread = helper.serverHostCorountine(server, closed_check)
	local client_thread = helper.clientConnectionCorountine(client, function()
		closed = true
	end)
	return server, client, server_thread, client_thread, closed_check
end

function helper.setupClientServer(port)
	local server = LunaMesh.new()
	local client = LunaMesh.new()

	server:setServer("127.0.0.1", port)
	client:connect("127.0.0.1", port)
	return server, client
end

function helper.serverHostCorountine(server, closed_check)
	assert(closed_check, "must provide a function to check if we're done")
	assert(server, "must provide a server")
	local server_thread = coroutine.create(function()
		while not closed_check() do
			server:listen(0.1)
			coroutine.yield()
		end
	end)

	return server_thread
end

function helper.clientConnectionCorountine(client, mark_finish)
	assert(mark_finish, "must provide a function to mark the connection loop as done")
	assert(client, "must provide a connected client")

	local client_thread = coroutine.create(function()
		repeat
			client:listen(0.1)
			coroutine.yield()
		until client:isConnected()

		mark_finish()
	end)

	return client_thread
end

function helper.runCorountineLoopUntil(closed_check, timeout, coroutines)
	local accumulator = 0
	while not closed_check() and accumulator <= timeout do
		for _, corountine in pairs(coroutines) do
			coroutine.resume(corountine)
		end
		socket.sleep(0.1)
		accumulator = accumulator + 0.1
	end
end

return helper
