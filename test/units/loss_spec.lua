require("busted.runner")()

local socket = require("socket")
local helper = require("test.units.helper")

local TIMEOUT = 3

local function common_connection_test(timeout)
	local server, client, server_thread, client_thread, closed_check = helper.setupFullClientServerConnection()
	helper.runCorountineLoopUntil(closed_check, timeout or 3, { server_thread, client_thread })
	return client:isConnected()
end

describe("reliable packets", function()
	teardown(function()
		os.execute("tc qdisc del dev lo root netem")
	end)
	before_each(function()
		os.execute("tc qdisc del dev lo root netem")
	end)
	it("100% packet loss connection. Should timeout.", function()
		os.execute("tc qdisc add dev lo root netem loss 100%")

		local success = common_connection_test(3)
		assert.is_false(success)
	end)
	it("50% packet loss connection. Shouldn't timeout.", function()
		os.execute("tc qdisc add dev lo root netem loss 50%")

		local success = common_connection_test(20)
		assert.is_true(success)
	end)
	it("0% packet loss connection. Shouldn't timeout.", function()
		local success = common_connection_test(3)
		assert.is_true(success)
	end)
end)
