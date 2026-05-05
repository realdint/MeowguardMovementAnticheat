local PositionHistoryWindow = {}

export type PositionSample = {
	time: number,
	position: Vector3,
	displacement: Vector3,
}

export type PositionHistoryWindow = {
	maxAge: number,
	samples: { PositionSample },
	
	add: (self: PositionHistoryWindow, position: Vector3) -> (),
	getSamples: (self: PositionHistoryWindow) -> ({PositionSample}),
	getNewestSample: (self: PositionHistoryWindow) -> (PositionSample?),
	getOldestSample: (self: PositionHistoryWindow) -> (PositionSample?),
	clear: (self: PositionHistoryWindow) -> (),
	prune: (self: PositionHistoryWindow) -> (),
}

function PositionHistoryWindow.new(maxAge: number): PositionHistoryWindow
	assert(maxAge > 0, "maxAge must be > 0")
	
	local self = setmetatable({}, {__index = PositionHistoryWindow})
	
	self.maxAge = maxAge
	self.samples = {}
	
	return self :: PositionHistoryWindow
end

function PositionHistoryWindow:add(position: Vector3)
	local samples = self.samples
	
	local lastSample = samples[#samples]
	local displacement = Vector3.zero
	
	if lastSample then
		displacement = position - lastSample.position
	end
	
	-- this structure causes the most memory usage and gc activity
	-- TODO: use a different structure like some precomputed fixed size thing
	-- max like 0.07 MB * 30 players = 2.1 MB, 
	table.insert(samples, {
		time = tick(),
		position = position,
		displacement = displacement
	})
	
	self:prune()
end

function PositionHistoryWindow:prune()
	local currentTime = tick()
	local cutoffTime = currentTime - self.maxAge
	local samples = self.samples
	
	local removeCount = 0
	
	for i = 1, #samples do
		if samples[i].time < cutoffTime then
			removeCount += 1
		else
			break
		end
	end
	
	if removeCount > 0 then
		for _ = 1, removeCount do
			table.remove(samples, 1)
		end
		
		if samples[1] then
			samples[1].displacement = Vector3.zero
		end
	end
end

function PositionHistoryWindow:getSamples(): {PositionSample}
	return self.samples
end

function PositionHistoryWindow:getNewestSample(): PositionSample?
	local samples = self.samples
	if #samples == 0 then
		return nil
	end
	
	return samples[#samples]
end

function PositionHistoryWindow:getOldestSample(): PositionSample?
	local samples = self.samples
	if #samples == 0 then
		return nil
	end
	
	return samples[1]
end

function PositionHistoryWindow:clear()
	table.clear(self.samples)
end

return PositionHistoryWindow
