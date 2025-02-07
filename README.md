<h1 align="center">LunaMesh</h1>
<p align="center">A basic starting point for networking</p>

## Description
LuaMesh is a simple networking library for lua / love2d. Aiming to simplify networking in projects.

It strives to be **simple**.

Implement intricate networking protocols with ease.

> :note: Note: This is a WIP for the moment. So while it isn't production ready, any input from anyone is welcome!


## Installation


## Example
Here's a working example of how you can use this library:

```lua
----------------------------------------
--main.lua 
----------------------------------------
local lm = require("LunaMesh")
local PKT_TYPE = require("net_handlers")

function love.load(args)
    if args[1] == "--server" then
        _G.IS_SERVER = true
    end

    if IS_SERVER then
        lm:setServer("127.0.0.1", 8080) -- ip can be nil
        print("Server is running")
        -- run server code
        -- ie: require("server")
        return
    end

    -- if we're not a server:
    
    lm:connect("127.0.0.1", 8080)

    -- wait until we have a connection
    repeat
        lm:listen()
        love.timer.sleep(0.1)
    until lm:isConnected()
    
    print("Connected to server")
    print("Sending an echo")

    -- create and send a packet
    local echo_pkt = lm:createPkt(PKT_TYPE.ECHO.REQUEST, "Hello, Server!")
    lm:sendToServer(echo_pkt)
end

function love.update(dt)
    lm:listen() --you can use lm:update() if you like that instead
end

----------------------------------------
--net_handlers.lua
----------------------------------------
local lm = require("LunaMesh")

---Packets you yourself can implement
local PKT_TYPE = {
	ECHO = {
		REQUEST = 301,
		ANSWER = 302,
	},
}

lm:addPktHandler(PKT_TYPE.ECHO.REQUEST, function(self, pkt, ip, port)
	print("Received an echo request", ip, port, pkt.data)

	local answer_pkt = self:createPkt(PKT_TYPE.ECHO.ECHO_RESPONSE, { data = pkt.data })
	self:sendToAddress(answer_pkt, ip, port)
end)

lm:addPktHandler(PKT_TYPE.ECHO.ANSWER, function(self, pkt, ip, port)
	print("Received an echo response", ip, port, pkt.data)
end)

return PKT_TYPE
```

If you want to add new protocols, or packets, just add them to the PKT_TYPE table, and implement a function for them, just like we did with for the echo protocol.

## Documentation
Before we create either a server, or a client, we need to know that **LunaMesh** already returns an instance. You don't need to instintiate it. The same one, no matter where in the love runtime you are. 

```lua
local lunamesh = require("LunaMesh") --will always return te same instance everywhere
```

### Creating a server
LunaMesh is a client by default, set it a server with `:setServer(ip | nil, port)`
```lua
lunamesh:setServer("127.0.0.1", 18080)
```
> Some OSs do not allow ports below 1024. Use a high port number

The IP can be `nil` if you want to accept connections from anywhere, if you only want to accept from yoursel, then you set it to `"127.0.0.1"`.

### Creating a client
We only need to call `:connect(ip, port)` to connect to a desired server. You can call the connect whenever you want

```lua
lunamesh:connect("127.0.0.1", 18080)
```

LunaMesh also needs to *receive* packets, so we'll need to call `:listen()` as well.

We can loop and call `:listen()` until we are connected, which can be checked with `:isConnected()`.
```lua
lunamesh:connect("127.0.0.1", 18080)

repeat
    lunamesh:listen()
    love.timer.sleep(0.1) --use any function to wait. eg: socket.sleep
until lunamesh:isConnected()
```

## Modifying

1. To use a different serialisation library, change the `serialise` and `deserialise` functions declared at the top of the file. Here are some benchmarks by adriweb: https://github.com/gvx/bitser/discussions/23
2. To use multiple instances, not just the same instance, change the `return` at the bottom of the file to `return LunaMesh`.

# Dependencies
- [lua-socket](https://lunarmodules.github.io/luasocket/) - probably installed by love2d
- [bitser](https://github.com/gvx/bitser) - This requires you use `luajit`!

# License
This software is released under the [MIT License](LICENSE)