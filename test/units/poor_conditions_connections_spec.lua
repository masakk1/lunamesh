require("busted.runner")()

local socket = require("socket")
local helper = require("test.units.helper")

local TIMEOUT = 3

local function common_connection(timeout)
	local server, client, server_thread, client_thread, closed_check = helper.setupFullClientServerConnection()
	helper.runCorountineLoopUntil(closed_check, timeout or TIMEOUT, { server_thread, client_thread })
	return server, client
end

describe("network traffic alteration connections", function()
	teardown(function()
		os.execute("tc qdisc del dev lo root netem 2>/dev/null")
	end)
	before_each(function()
		os.execute("tc qdisc del dev lo root netem 2>/dev/null")
	end)
	it("Unaltered. Shouldn't timeout.", function()
		local server, client = common_connection()
		assert.is_true(client:isConnected())
	end)
	it("100% loss. Should timeout.", function()
		os.execute("tc qdisc add dev lo root netem loss 100%")

		local server, client = common_connection()
		assert.is_false(client:isConnected())
	end)
	it("50% loss. Shouldn't timeout.", function()
		os.execute("tc qdisc add dev lo root netem loss 50%")

		local server, client = common_connection(10)
		assert.is_true(client:isConnected())
	end)
	-- it("100% duplication. Should have 1 client", function()
	-- 	os.execute("tc qdisc add dev lo root netem duplicate 100%")

	-- 	local server, client = common_connection()

	-- 	assert.is_true(client:isConnected())
	-- 	assert.are_equal(1, server.client_count)
	-- end)
	-- it("50% duplication. Should have 1 client.", function()
	-- 	os.execute("tc qdisc add dev lo root netem duplicate 50%")

	-- 	local server, client = common_connection()

	-- 	assert.is_true(client:isConnected())
	-- 	assert.are_equal(1, server.client_count)
	-- end)
end)
