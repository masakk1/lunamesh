<h1 align="center">LunaMesh</h1>
<p align="center">A basic starting point for networking in Lua</p>

## Description
LunaMesh is a simple networking library for lua / love2d. Aiming to simplify networking in projects.

> [!NOTE]
> This is a WIP for the moment. Feel free to try it out, any input from anyone is welcome!

#### Features
1. Easily set a server and client
2. Handle connections between server and client
3. Create custom packets and handlers for them

## Installation
Copy `lunamesh.lua` to your project. Or run:
```bash
wget https://raw.githubusercontent.com/masakk1/lunamesh/refs/heads/main/lunamesh.lua
```

## Example
Here's a working example of how you can use this library:

```lua
----------------------------------------
--main.lua 
----------------------------------------
local lunamesh = require("lunamesh")
local PKT_TYPE = require("net_handlers")

function love.load(args)
	if args[1] == "--server" then
		_G.IS_SERVER = true
		lunamesh:setServer("127.0.0.1", 8080) -- ip can be nil
		return
	end

	lunamesh:connect("127.0.0.1", 8089)

	-- wait until we have a connection
	local conn = lunamesh:waitUntilClientConnected(10)
	assert(conn, "Timed out")

	-- create and send a packet
	local echo_pkt = lunamesh:createPkt(PKT_TYPE.ECHO.REQUEST, "Hello, Server!")
	lunamesh:sendToServer(echo_pkt)
end

function love.update(dt)
	lunamesh:listen() --you can use lunamesh:update() if you like that instead
end

----------------------------------------
--net_handlers.lua
----------------------------------------
local lunamesh = require("lunamesh")
local PKT_TYPE = require("net_handlers")

function love.load(args)
	if args[1] == "--server" then
		_G.IS_SERVER = true
		lunamesh:setServer("127.0.0.1", 8080) -- ip can be nil
		return
	end

	lunamesh:connect("127.0.0.1", 8089)

	-- wait until we have a connection
	local conn = lunamesh:waitUntilClientConnected(10)
	assert(conn, "Timed out")

	-- create and send a packet
	local echo_pkt = lunamesh:createPkt(PKT_TYPE.ECHO.REQUEST, "Hello, Server!")
	lunamesh:sendToServer(echo_pkt)
end

function love.update(dt)
	lunamesh:listen() --you can use lunamesh:update() if you like that instead
end
```

If you want to add new protocols, or packets, just add them to the PKT_TYPE table, and implement a function for them, just like we did with the echo protocol.

## Documentation
Before we create either a server, or a client, know that **LunaMesh** returns an instance. You don't need to instintiate it. It will return the same one, no matter where in the love runtime you are. 

```lua
local lunamesh = require("LunaMesh") --will always return te same instance everywhere
```

## `:setServer(ip?, port)`
LunaMesh is a client by default, set it a server with `:setServer(ip | nil, port)`
```lua
lunamesh:setServer("127.0.0.1", 18080)
```

> [!WARNING] 
> Some OSs don't allow ports below 1024. Use a port above the reserved 1024. Check [wikipedia](https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers)

The IP can be `nil` if you want to accept connections from anywhere, if you only want to accept from yourself, then you set it to `"127.0.0.1"`.

## `:connect(ip, port)` 
Connects to a specified server at an ip and port
```lua
lunamesh:connect("127.0.0.1", 18080)
```

LunaMesh also needs to *receive* packets, so `:listen()` repeatedly as well.

```lua
lunamesh:connect("127.0.0.1", 18080)

repeat
    lunamesh:listen()
    love.timer.sleep(0.1) --use any function to wait. eg: socket.sleep
until lunamesh:isConnected()
```

## `addPktHandler(pkt_type, callback?)`
Implement your own handlers for the packets you need.
Create a packet type:
```lua
local PKT_TYPE = {
    UPDATE = {
        WORLD = 601, -- Use numbers above 500!
        INPUT = 602
    }
}
```
Then implement the handler:
```lua
-- A client example
luamesh:addPktHandler(PKT_TYPE.UPDATE.WORLD, function(self, pkt)
    local data = pkt.data
    -- Do your thing
end)

-- A server example
luamesh:addPktHandler(PKT_TYPE.UPDATE.INPUT, function(self, pkt, ip, port)
    local data = pkt.data
    -- Do your thing
end)
```

## Modifying

1. To use a different serialisation library, change the `serialise` and `deserialise` functions declared at the top of the file. Here are some benchmarks by adriweb: https://github.com/gvx/bitser/discussions/23
2. To use multiple instances, not just the same instance, change the `return` at the bottom of the file to `return LunaMesh`.

# Dependencies
- [lua-socket](https://lunarmodules.github.io/luasocket/) - probably installed by love2d
- [bitser](https://github.com/gvx/bitser) - This requires you use `luajit`!

# License
This software is released under the [MIT License](LICENSE)