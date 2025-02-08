local lunamesh = require("lunamesh")
local PKT_TYPE = require("src.pkt_types")

local Player = {
	is_player = true,

	x = 0,
	y = 0,
	w = 64,
	h = 64,

	aimx = 0,
	aimy = 0,

	speed = 200,
}
Player.__index = Player

function Player.new()
	local self = setmetatable({}, Player)
	return self
end

function Player:update(dt)
	local state = self:getInputState(dt)
	self.input_state = state

	self:applyInput(state)

	local input_pkt = lunamesh:createPkt(PKT_TYPE.SYNC.INPUT, state)
	lunamesh:sendToServer(input_pkt)
end

function Player:getInputState(dt)
	local state = { move = { x = 0, y = 0 }, aim = { x = 0, y = 0 } }
	state.dt = dt

	if love.keyboard.isDown("up") then
		state.move.y = state.move.y - 1
	end
	if love.keyboard.isDown("down") then
		state.move.y = state.move.y + 1
	end
	if love.keyboard.isDown("right") then
		state.move.x = state.move.x + 1
	end
	if love.keyboard.isDown("left") then
		state.move.x = state.move.x - 1
	end

	local mx, my = love.mouse.getPosition()
	state.aim.x = mx
	state.aim.y = my

	return state
end

function Player:getState()
	return {
		pos = { x = self.x or 0, y = self.y or 0 },
	}
end

function Player:applyInput(input_state)
	self.x = self.x + (input_state.move.x * input_state.dt) * self.speed
	self.y = self.y + (input_state.move.y * input_state.dt) * self.speed

	self.input_state = input_state
end

function Player:applyState(state)
	self:setPosition(state.pos)
end
function Player:setPosition(pos)
	self.x = pos.x or self.x
	self.y = pos.y or self.y
end

function Player:draw()
	love.graphics.rectangle("line", self.x, self.y, self.w, self.h)
end

return Player
