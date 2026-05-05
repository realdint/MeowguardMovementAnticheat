local Maid = {}

export type Maid = {
	tasks: {any},
	Give: (Maid, any) -> (),
	Clean: (Maid) -> ()
}

function Maid.Give(self, x)
	table.insert(self.tasks, x)
	return x
end

function Maid.Clean(self)
	for i = #self.tasks, 1, -1 do
		local t = table.remove(self.tasks, i)
		if typeof(t) == "RBXScriptConnection" then
			t:Disconnect()
		elseif typeof(t) == "Instance" then
			t:Destroy()
		elseif type(t) == "function" then
			pcall(t)
		elseif type(t) == "table" and t.Clean then
			pcall(t.Clean, t)
		end
	end
end

function Maid.new(): Maid
	return {
		tasks = {},
		Give = Maid.Give,
		Clean = Maid.Clean
	}
end

return Maid
