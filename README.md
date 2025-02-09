<h1 align="center">LunaMesh</h1>
<p align="center">A basic starting point for networking in Lua</p>

## Description
LunaMesh is a simple networking library for lua / love2d. Aiming to simplify networking in projects.

> [!NOTE]
> This is a WIP for the moment. Feel free to try it out, any input from anyone is welcome!

> [!WARNING]
> It expects to have `bitser` on `lib.bitser`. Feel free to modify this.

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

> [!NOTE]
> Please take a look at [the demo](https://github.com/masakk1/lunamesh/tree/demo), since it has a more realistic example.

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
LunaMesh is a client by default, set it a server with `:setServer(ip?, port)`
```lua
lunamesh:setServer("127.0.0.1", 18080) --ip: string | port: integer
```

> [!WARNING] 
> Some OSs don't allow ports below 1024. Use a port above the reserved 1024. Check [wikipedia](https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers)

The IP can be `nil` or `"*"` if you want to accept connections from anywhere.
If you only want to accept connections from localhost, use `"127.0.0.1"`.

## `:connect(ip, port)` 
Connects to a specified server at an ip and port
```lua
lunamesh:connect("127.0.0.1", 18080)
```

LunaMesh also needs to *receive* packets while connecting.
There's a function that simplifies this, `lumamesh:waitUntilClientConnected(timeout: number) -> connected: boolean, clientID: client.clientID`

```lua
lunamesh:connect("127.0.0.1", 18080)
local connected, clientID = lunamesh:waitUntilClientConnected(10) --WARNING: this freezes the thread.
assert(connected, "Couldn't connect to server. Timed out.")
```

## `:setPktHandler(pkt_type, callback)`
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
-- on the client
local function update_world(self, pkt)
    local data = pkt.data
    World:update(data)
end
luamesh:setPktHandler(PKT_TYPE.UPDATE.WORLD, update_world)

-- on the server
local function client_input(self, pkt, ip, port, client)
	if not client then return end --dismiss if client is not connected
    local data = pkt.data
    client.player:applyInput(data)
end
luamesh:setPktHandler(PKT_TYPE.UPDATE.INPUT, client_input)
```

## `:subscribeHook(hookID, func)`
Subscribe to a hook to expand internal functions. Such has connected clients.
```lua
--Creating a player entity when a client joins
local function create_player(self, client)
	clientList[client.clientID] = client

	local player = Player.new()
	clientList[client.clientID].player = player
	entityList[client.clientID] = player
end
lunamesh:subscribeHook("clientAdded", create_player)
```

Currently supported hooks:
1. (SERVER) `"clientAdded" -> (self: LunaMesh, client: Client)` - when a client has connected and been authorised
2. (CLIENT) `"connectionSuccessful" -> (self: LunaMesh, clientID: clientID)` - when a client successfully connects to a server


## Modifying

1. To use a different serialisation library, change the `serialise` and `deserialise` functions declared at the top of the file. Here are some benchmarks by adriweb: https://github.com/gvx/bitser/discussions/23
2. To use multiple instances, not just the same instance, change the `return` at the bottom of the file to `return LunaMesh`.

# Dependencies
- [lua-socket](https://lunarmodules.github.io/luasocket/) - probably installed by love2d
- [bitser](https://github.com/gvx/bitser) - This requires you use `luajit`!

# License
This software is released under the [MIT License](LICENSE)
