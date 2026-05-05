--[[
	dint 5/3/2026
    --	roblox: 646258008
	--	discord: _dint
	
	meowguard anti teleport, speed, fling
	
	depends on:
	--	Client script
	--	PositionBuffer
	--	Maid
	contact dint if you have this but are missing those (somehow)
	this also wont run if you never require it anywhere
	
	Anticheat.isActive(player) or Anticheat.active[player]
	--	checks if a player should be able to do things,
	--	it does not matter if you use the function or table index
	
	Anticheat.getScore(player)
	--	gets a players exploiting score (useful for debug)
	
	Anticheat.teleport(player)
	--	call this before a player teleports to temp ignore them
	
	Anticheat.setMaxXZVelocity(player, velocity: number)
	--	call this when a player equips or does something that makes 
	--	their velocity not depend on walkspeed, like vehicles and such
	
	Anticheat.resetMaxXZVelocity(player)
	--	use in conjunction with setMaxXZVelocity, when they stop doing
	--	whatever it was they were doing
	
	Anticheat.permWhitelist(player)
	--	whitelists a player until they leave or it is removed with
	-- 	the removeWhitelist function
	
	Anticheat.tempWhitelist(player, time: number?)
	-- 	whitelists a players character, if a time is provided it will
	-- 	only whitelist for that number of seconds
	
	Anticheat.removeWhitelist(player)
	-- 	removes all whitelists from a player
]]
--!strict
--!optimize 2
debug.setmemorycategory("MG Anticheat")
const SCALED_WALKSPEED = 16 -- walkspeed to scale to, used for % over default speed calculation
const LAG_THRESHHOLD = 0.5 -- if the player hasnt pinged in this many seconds theyre lagging
const LAGSPIKE_RECOVERY = 0.2 -- after a lagspike from LAG_THRESHHOLD, allow things that should be recovering to recover for this many seconds
const VELOCITY_RECOVERY = 0.3 -- velocity recovery time
const MAX_VELOCITY_DIFFERENCE = 100 -- difference between measured and player stated velocity (detecting teleports)
const MAX_XZ_VELOCITY_DEFAULT = 7 -- how far over walkspeed you can go
const VELOCITY_PUNISHMENT = 1 -- confidence gain per amount over walkspeed (this builds up really fast)
const EXPLOIT_SCORE_DROPOFF = 5 -- scores per second
const EXPLOIT_TICK_DROPOFF = 50 -- per second
const CONFIDENCE_TICK_THRESHHOLD = 100 -- when exploitTickConfidence reaches this it will give them one exploitscore
const MAX_EXPLOIT_SCORE = 15
const ANTIFLING = true
const ANTIFLING_WITH_COLLISION = true -- disables player to player collision, but uses a fake part that players cannot control to maintain collision
const PLAYER_GROUP_NAME = "Players" -- collisiongroup

-- this is so the client can see it too, but a better option is to just
-- use maid everywhere and put it somewhere like replicatedstorage
local Maid = require(script.Client.Maid)
local PositionBuffer = require(script.PositionBuffer)

local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Anticheat = {
	active = {} :: { [Player]: boolean },
}

type characterState = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	maid: Maid.Maid,
	
	lastUpdated: number?,
	lastLagspike: number?,
	position: Vector3?,
	velocity: Vector3?,
	positionBufferTenth: PositionBuffer.PositionHistoryWindow,
	velocityBufferTenth: PositionBuffer.PositionHistoryWindow,
	
	exploitScore: number, -- how MUCH the person is exploiting
	exploitTickConfidence: number, -- how confident we are, threshhold is CONFIDENCE_TICK_THRESHHOLD, gives 1 exploitScore per threshhold reached
	
	whitelist: true | number?,
	maxXZVelocity: number,
	maxXZVelocityGoal: number,
	maxXZVelocitySet: number?,
}

local characterStates: { [Player]: characterState } = {}
local lastPing: { [Player]: number } = {}
local whitelist: { [Player]: boolean } = {}

local replicatedFolder: Folder
local pingRemote: UnreliableRemoteEvent
-- init / client setup
do
	replicatedFolder = Instance.new("Folder", game.ReplicatedStorage)
	replicatedFolder.Name = "_mg"
	replicatedFolder:SetAttribute("ANTIFLING_WITH_COLLISION", ANTIFLING_WITH_COLLISION)
	
	pingRemote = Instance.new("UnreliableRemoteEvent", replicatedFolder)
	pingRemote.Name = "ping"
	
	script.Client:Clone().Parent = game.StarterPlayer.StarterPlayerScripts
	
	if ANTIFLING then
		PhysicsService:RegisterCollisionGroup(PLAYER_GROUP_NAME)
		PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP_NAME, PLAYER_GROUP_NAME, false)
	end
end

local function characterRemoved(character: Model, player: Player)
	local state = characterStates[player]
	
	if state and state.character == character then
		state.maid:Clean()
		characterStates[player] = nil
	end
end

local function characterAdded(character: Model, player: Player)
	local oldState = characterStates[player]
	
	if oldState then
		oldState.maid:Clean()
		characterStates[player] = nil
	end
	
	local maid = Maid.new()
	local positionBuffer = PositionBuffer.new(0.1)
	local velocityBuffer = PositionBuffer.new(0.1)
	
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	
	local state: characterState = {
		positionBufferTenth = positionBuffer,
		velocityBufferTenth = velocityBuffer,
		character = character,
		humanoid = humanoid,
		root = root,
		maid = maid,
		
		position = nil,
		velocity = nil,
		lastUpdated = nil,
		
		exploitScore = 0,
		exploitTickConfidence = 0,
		maxXZVelocity = MAX_XZ_VELOCITY_DEFAULT,
		maxXZVelocityGoal = MAX_XZ_VELOCITY_DEFAULT,
	}
	
	maid:Give(humanoid.Died:Connect(function()
		characterRemoved(character, player)
	end))
	
	maid:Give(character.Destroying:Connect(function()
		characterRemoved(character, player)
	end))
	
	if ANTIFLING then
		-- disables player to player collisions
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "FakeRoot" then
				part.CollisionGroup = PLAYER_GROUP_NAME
			end
		end
		
		maid:Give(character.ChildAdded:Connect(function(part)
			if part:IsA("BasePart") and part.Name ~= "FakeRoot" then
				part.CollisionGroup = PLAYER_GROUP_NAME
			end
		end))
	end
	
	characterStates[player] = state
end

-- returns rate of change (vector), speed (number) and timeframe
local function getDerivatives(buffer: PositionBuffer.PositionHistoryWindow)
	local oldest = buffer:getOldestSample()
	local newest = buffer:getNewestSample()
	local samples = buffer:getSamples()
	
	-- if theyre nil or the same dont do anything
	if oldest == newest or oldest == nil or newest == nil or newest.time - oldest.time <= 0 then
		return Vector3.zero, 0, 0
	end
	
	local timeframe = newest.time - oldest.time
	local derivative = (newest.position - oldest.position) / timeframe
	
	local totalDistance = 0
	for i, sample in samples do
		totalDistance += sample.displacement.Magnitude
	end
	local speed = totalDistance / timeframe
	
	return derivative, speed, timeframe
end

Players.PlayerAdded:Connect(function(player)
	Anticheat.active[player] = true
	player.CharacterAdded:Connect(function(character)
		characterAdded(character, player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	Anticheat.active[player] = nil
	lastPing[player] = nil
	whitelist[player] = nil
	
	if player.Character then
		characterRemoved(player.Character, player)
	end
	
	-- REALLY make sure theres no state left over
	local state = characterStates[player]
	if state then
		state.maid:Clean()
		characterStates[player] = nil
	end
end)

RunService.Heartbeat:Connect(function(dt)
	debug.profilebegin("MG Anticheat")
	local now = tick()
	for player, state in pairs(characterStates) do
		-- if they never ping, theyve tampered with it
		-- so just treat it as them never lagging ever
		local lastResponse = lastPing[player] or state.lastUpdated or now
		local timeSinceLastResponse = now - lastResponse
		local timeSinceLastLagspike = now - (state.lastLagspike or 0)
		local dtScale = dt * 60 -- scale all values to time
		
		local position: Vector3 = state.root.Position
		local walkSpeed: number = state.humanoid.WalkSpeed
		local speedFactor = walkSpeed / SCALED_WALKSPEED
		local isWhitelisted = false
		
		-- whitelist
		if state.whitelist == true or (state.whitelist and now < state.whitelist) then
			isWhitelisted = true
		end
		if whitelist[player] then
			isWhitelisted = true
		end
		
		-- lag
		if timeSinceLastResponse >= LAG_THRESHHOLD and isWhitelisted == false then
			Anticheat.active[player] = false
			state.lastLagspike = now
			continue
		end
		
		-- goal lerp
		if state.maxXZVelocityGoal > state.maxXZVelocity then
			state.maxXZVelocity = state.maxXZVelocityGoal
		elseif state.maxXZVelocityGoal < state.maxXZVelocity and state.maxXZVelocitySet then
			local alpha = math.clamp((now - state.maxXZVelocitySet) / VELOCITY_RECOVERY, 0, 1)
			state.maxXZVelocity = state.maxXZVelocity + (state.maxXZVelocityGoal - state.maxXZVelocity) * alpha
		end
		
		state.positionBufferTenth:add(position)
		
		local velocityDerivative, speed, velocityTimeframe = getDerivatives(state.positionBufferTenth)
		
		-- first update
		if state.position == nil or state.lastUpdated == nil then
			state.position = position
			state.lastUpdated = now
			
			continue
		end
		
		local instantVelocity = (position - state.position) / (now - state.lastUpdated)
		local assemblyVelocity: Vector3 = state.root.AssemblyLinearVelocity
		-- sign matters here, >0 means it was greater than expected, <0 means it was less than expected
		-- slight differences are expected we wont punish for anything <100 in difference
		local difference = (instantVelocity - assemblyVelocity).Magnitude
		local XZVelocity = math.sqrt(velocityDerivative.X ^ 2 + velocityDerivative.Z ^ 2)
		
		state.position = position
		state.lastUpdated = now
		
		-- detections
		if not isWhitelisted then
			-- measured vs "real" velocity difference flag
			if difference >= MAX_VELOCITY_DIFFERENCE and timeSinceLastLagspike >= LAGSPIKE_RECOVERY then
				state.exploitTickConfidence += (difference / speedFactor) * dtScale
			end
			
			-- max velocity flag
			if XZVelocity >= walkSpeed + state.maxXZVelocity and timeSinceLastLagspike >= LAGSPIKE_RECOVERY then
				local amountOver = XZVelocity - walkSpeed
				state.exploitTickConfidence += VELOCITY_PUNISHMENT * amountOver * dtScale
			end
		end
		
		-- final exploit score calculation
		local scoreAmount = state.exploitTickConfidence // CONFIDENCE_TICK_THRESHHOLD
		state.exploitTickConfidence -= scoreAmount * CONFIDENCE_TICK_THRESHHOLD
		state.exploitScore += scoreAmount
		
		state.exploitScore = math.clamp(state.exploitScore - dt * EXPLOIT_SCORE_DROPOFF, 0, MAX_EXPLOIT_SCORE)
		state.exploitTickConfidence = math.clamp(state.exploitTickConfidence - dt * EXPLOIT_TICK_DROPOFF, 0, math.huge)
		
		if state.exploitScore == 0 then
			Anticheat.active[player] = true
		elseif not isWhitelisted then
			Anticheat.active[player] = false
		end
	end
	debug.profileend()
end)

pingRemote.OnServerEvent:Connect(function(player)
	lastPing[player] = tick()
end)

-- whitelist a player forever
function Anticheat.permWhitelist(player: Player)
	whitelist[player] = true
end

-- if time is provided will whitelist their character for time seconds
function Anticheat.tempWhitelist(player: Player, time: number?)
	local now = tick()
	local state = characterStates[player]
	if state and state.whitelist ~= true then
		state.whitelist = if time then now + time else true
	end
end

-- ignore a teleport
function Anticheat.teleport(player: Player)
	local state = characterStates[player]
	if state and state.whitelist ~= true then
		state.whitelist = tick() + 0.5
	end
end

-- can a player do things
function Anticheat.isActive(player: Player)
	return Anticheat.active[player]
end

function Anticheat.getScore(player: Player)
	if characterStates[player] then
		return characterStates[player].exploitScore
	else
		return 0
	end
end

-- remove a players whitelist completley
function Anticheat.removeWhitelist(player: Player)
	whitelist[player] = nil
	if characterStates[player] then
		characterStates[player].whitelist = nil
	end
end

-- set max speed
function Anticheat.setMaxXZVelocity(player: Player, velocity: number)
	if characterStates[player] then
		characterStates[player].maxXZVelocityGoal = velocity
		characterStates[player].maxXZVelocitySet = tick()
	end
end

-- reset max speed
function Anticheat.resetMaxXZVelocity(player: Player)
	if characterStates[player] then
		characterStates[player].maxXZVelocityGoal = MAX_XZ_VELOCITY_DEFAULT
		characterStates[player].maxXZVelocitySet = tick()
	end
end

return Anticheat
