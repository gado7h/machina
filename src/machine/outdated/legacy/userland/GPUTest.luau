local GPUTest = {}
GPUTest.__index = GPUTest

local TAU = math.pi * 2
local SHADES = ".,-~:;=!*#$@"

function GPUTest.new(kernel, username, onExit)
	local self = setmetatable({}, GPUTest)
	self.kernel = kernel
	self.gpu = kernel.gpu
	self.keyboard = kernel.keyboard
	self.username = username or "user"
	self.onExit = onExit
	self._running = false
	self._A = 0
	self._B = 0
	self._cols = 64
	self._rows = 28
	return self
end

function GPUTest:start()
	if self._running then
		return
	end
	self._running = true
	self.gpu:setMode("PIXEL")
	self:_tick()
end

function GPUTest:stop()
	if not self._running then
		return
	end
	self._running = false
	self.gpu:setMode("TEXT")
	if self.onExit then
		self.onExit()
	end
end

function GPUTest:_tick()
	if not self._running then
		return
	end

	while self.keyboard do
		local ch = self.keyboard:readChar()
		if not ch then
			break
		end
		if ch == "\n" or ch == "\r" then
			self:stop()
			return
		end
	end

	self:_renderFrame()
	self._A = self._A + 0.045
	self._B = self._B + 0.02
	if self._A > TAU then
		self._A = self._A - TAU
	end
	if self._B > TAU then
		self._B = self._B - TAU
	end

	task.delay(0.033, function()
		self:_tick()
	end)
end

function GPUTest:_renderFrame()
	local cols = self._cols
	local rows = self._rows
	local size = cols * rows
	local depth = table.create(size, 0)
	local chars = table.create(size, " ")

	local sinA, cosA = math.sin(self._A), math.cos(self._A)
	local sinB, cosB = math.sin(self._B), math.cos(self._B)

	for theta = 0, TAU, 0.3 do
		local sinTheta = math.sin(theta)
		local cosTheta = math.cos(theta)

		for phi = 0, TAU, 0.08 do
			local sinPhi = math.sin(phi)
			local cosPhi = math.cos(phi)

			local circleX = 2 + cosTheta
			local circleY = sinTheta

			local x = circleX * (cosB * cosPhi + sinA * sinB * sinPhi) - circleY * cosA * sinB
			local y = circleX * (sinB * cosPhi - sinA * cosB * sinPhi) + circleY * cosA * cosB
			local z = 5 + cosA * circleX * sinPhi + circleY * sinA
			local ooz = 1 / z

			local xp = math.floor(cols * 0.5 + 30 * ooz * x)
			local yp = math.floor(rows * 0.5 + 15 * ooz * y)
			if xp >= 0 and xp < cols and yp >= 0 and yp < rows then
				local idx = yp * cols + xp + 1
				if ooz > depth[idx] then
					depth[idx] = ooz
					local L = cosPhi * cosTheta * sinB - cosA * cosTheta * sinPhi - sinA * sinTheta
						+ cosB * (cosA * sinTheta - cosTheta * sinA * sinPhi)
					local shade = math.max(1, math.min(#SHADES, math.floor((L + 1) * 0.5 * (#SHADES - 1)) + 1))
					chars[idx] = SHADES:sub(shade, shade)
				end
			end
		end
	end

	self.gpu:fillRect(0, 0, self.gpu.W, self.gpu.H, 0xFF040710)

	local pxW = self.gpu.CW
	local pxH = self.gpu.CH
	local originX = math.floor((self.gpu.W - cols * pxW) * 0.5)
	local originY = math.floor((self.gpu.H - rows * pxH) * 0.5)
	for row = 0, rows - 1 do
		local startIdx = row * cols + 1
		self.gpu:drawText(originX, originY + row * pxH, table.concat(chars, "", startIdx, startIdx + cols - 1), 0xFF55FF88)
	end

	self.gpu:drawText(8, 8, "NovaOS GPU test: rotating donut", 0xFFFFFF55)
	self.gpu:drawText(8, 20, "Press Enter to open shell", 0xFFAAAAAA)
end

return GPUTest
