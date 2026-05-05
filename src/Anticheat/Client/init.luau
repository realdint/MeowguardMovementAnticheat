-- dint 5/3/2026
-- 646258008 (roblox id), _dint (discord)
-- streaming safe
--!optimize 2
--!strict

const ANTIFLING_ROOT_SIZE = Vector3.new(1.8, 1.68, 0.95) -- size of fake part that maintains collision
const ANTIFLING_FOLLOW_PART = "UpperTorso" -- name of part to follow, if nil then it will follow the root
const ROOT_PARENT = game.Workspace.CurrentCamera -- we COULD parent to the players character but this may cause some ownership issues so we wont
const PING_FREQUENCY = 1 / 5 --  1/x fires x times per second

local Maid = require(script.Maid)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local replicatedFolder = game.ReplicatedStorage:WaitForChild("_mg") :: Folder
local pingRemote = replicatedFolder:WaitForChild("ping") :: UnreliableRemoteEvent
local lastPing = 0

if replicatedFolder:GetAttribute("ANTIFLING_WITH_COLLISION") then
	local states = {}
	
	local function handlePlayer(player: Player)
		if player == Players.LocalPlayer then
			return
		end
		
		local maid = Maid.new()
		
		local fakeRoot = Instance.new("Part", ROOT_PARENT)
		fakeRoot.Name = "FakeRoot_" .. player.Name
		fakeRoot.Transparency = 0.5
		fakeRoot.Color = Color3.new(0, 0, 0)
		fakeRoot.Anchored = true
		fakeRoot.Size = ANTIFLING_ROOT_SIZE
		maid:Give(fakeRoot)
		
		local state = {
			maid = maid,
			root = fakeRoot,
		}
		
		states[player] = state
	end
	
	local function playerRemoving(player: Player)
		if states[player] then
			states[player].maid:Clean()
			states[player] = nil
		end
	end
	
	for i, player in pairs(Players:GetPlayers()) do
		handlePlayer(player)
	end
	
	Players.PlayerAdded:Connect(handlePlayer)
	Players.PlayerRemoving:Connect(playerRemoving)
	
	RunService.RenderStepped:Connect(function()
		for player, state in pairs(states) do
			local character = player.Character
			
			if character == nil then
				state.root.CFrame = CFrame.new(0, 50000, 0)
				continue
			end
			
			local root = character:FindFirstChild(ANTIFLING_FOLLOW_PART or "HumanoidRootPart") :: BasePart
			
			if root == nil then
				state.root.CFrame = CFrame.new(0, 50000, 0)
				continue
			end
			
			state.root.CFrame = root.CFrame
		end
	end)
end

RunService.Heartbeat:Connect(function()
	local now = tick()
	
	if now - lastPing >= PING_FREQUENCY then
		lastPing = now
		pingRemote:FireServer()
	end
end)
