function love.load(args)
	if args[1] == "--server" then
		_G.IS_SERVER = true
		local fixed_update_fps = 20
		FRAME_TIME = 1 / fixed_update_fps

		require("server")
	else
		local fixed_update_fps = 40
		FRAME_TIME = 1 / fixed_update_fps

		require("client")
	end

	Load(args)
end

local accumulator = 0
local last_time = 0
function love.update(dt)
	accumulator = accumulator + dt

	while accumulator >= FRAME_TIME do
		local current_time = love.timer.getTime()
		local fixed_dt = current_time - last_time

		FixedUpdate(fixed_dt)

		accumulator = accumulator - FRAME_TIME
		last_time = current_time
	end

	Update(dt)
end
function love.draw()
	Draw()
end
