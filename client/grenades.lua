local GRENADE_DEBUG = false

class "Grenades"

Grenades.OverThrowTime = 0.36
Grenades.UnderThrowTime = 0.48
Grenades.GrenadeOffset = Vector3(0.3, -0.06, -0.02)

if GRENADE_DEBUG then
	function Sphere(center, radius, nLatitude, nLongitude)
		local vertices = {}
		local fVert    = 2
		local nPitch   = nLongitude + 1
		local pitchInc = (180 / nPitch) * (math.pi / 180)
		local rotInc   = (360 / nLatitude) * (math.pi / 180)

		-- table.insert(vertices, Vertex(Vector3(center.x, center.y + radius, center.z), Color(255, 0, 0, 125)))
		-- table.insert(vertices, Vertex(Vector3(center.x, center.y - radius, center.z), Color(255, 0, 0, 125)))

		local p, s, x, y, z, out

		for p = 1, nPitch do
			out = radius * math.sin(p * pitchInc)

			if out < 0 then
				out = -out
			end

			y = radius * math.cos(p * pitchInc)

			for s = 0, nLatitude do
				x = out * math.cos(s * rotInc)
				z = out * math.sin(s * rotInc)

				table.insert(vertices, Vertex(Vector3(center.x + x, center.y + y, center.z + z), Color(255, 0, 0, 125)))
			end
		end

		return vertices
	end

	Grenades.DebugModel = Model.Create(Sphere(Vector3.Zero, 1, 8, 256))
	Grenades.DebugModel:SetTopology(Topology.LineStrip)
end

function Grenades:__init()
	Events:Subscribe("ModuleLoad", self, self.ModuleLoad)
	Events:Subscribe("ModuleUnload", self, self.ModuleUnload)
	Events:Subscribe("InputPoll", self, self.InputPoll)
	Events:Subscribe("KeyDown", self, self.KeyDown)
	Events:Subscribe("PostTick", self, self.PostTick)
	Events:Subscribe("Render", self, self.Render)
	Events:Subscribe("GameRender", self, self.GameRender)
	Events:Subscribe("PostRender", self, self.PostRender)
	Network:Subscribe("GrenadeTossed", self, self.GrenadeTossed)
end

function Grenades:ModuleLoad()
	self.grenades = {}
	self.dummies = {}
	self.thrown = true
	self.thrownType = false
	self.thrownPosition = Vector3()
	self.thrownVelocity = Vector3()
	self.thrownTimer = Timer()
	self.flashedTimer = Timer()
end

function Grenades:ModuleUnload()
	for k, grenade in ipairs(self.grenades) do
		grenade:Remove()
	end

	for k, dummy in ipairs(self.dummies) do
		dummy:Remove()
	end
end

function Grenades:InputPoll()
	if not self.thrown then
		if not self.thrownTimer then
			self.thrownTimer = Timer()
		end

		if LocalPlayer:GetBaseState() ~= AnimationState.SParachute then
			Input:SetValue(Action.TurnLeft, 0)
			Input:SetValue(Action.TurnRight, 0)
			Input:SetValue(Action.LookLeft, 0)
			Input:SetValue(Action.LookUp, 0)
			Input:SetValue(Action.LookRight, 0)
			Input:SetValue(Action.LookDown, 0)

			LocalPlayer:SetAngle(Angle(Camera:GetAngle().yaw, LocalPlayer:GetAngle().pitch, LocalPlayer:GetAngle().roll))
		end

		if self.thrownUnder then
			LocalPlayer:SetLeftArmState(AnimationState.LaSUnderThrowGrenade)
		else
			LocalPlayer:SetLeftArmState(AnimationState.LaSOverThrowGrenade)
		end
	end
end

function Grenades:KeyDown(args)
	if args.key == string.byte("G") then
		self:TossGrenade(Grenade.Types.Frag)
	elseif args.key == string.byte("H") then
		self:TossGrenade(Grenade.Types.Flashbang)
	elseif args.key == string.byte("J") then
		self:TossGrenade(Grenade.Types.Smoke)
	elseif args.key == string.byte("K") then
		self:TossGrenade(Grenade.Types.MichaelBay)
	end
end

function Grenades:PostTick(args)
	if not self.thrown then
		local position = LocalPlayer:GetBonePosition("ragdoll_LeftForeArm") + LocalPlayer:GetBoneAngle("ragdoll_LeftForeArm") * Grenades.GrenadeOffset

		self.thrownVelocity = (Camera:GetAngle() * Vector3.Forward * 25) * ((Camera:GetAngle().pitch + (math.pi / 2)) / (math.pi / 2))
		self.thrownPosition = position

		if self.thrownTimer and self.thrownTimer:GetSeconds() > (self.thrownUnder and Grenades.UnderThrowTime or Grenades.OverThrowTime) then
			local grenade = {
				["position"] = self.thrownPosition,
				["velocity"] = self.thrownVelocity,
				["type"] = self.thrownType
			}

			Network:Send("GrenadeTossed", grenade)
			self:GrenadeTossed(grenade)

			self.thrown = true
		end
	end

	for k, grenade in ipairs(self.grenades) do
		grenade:Update()

		if not IsValid(grenade.object) or not IsValid(grenade.effect) then
			table.remove(self.grenades, k)
		end
	end
end

function Grenades:Render()
	for player in Client:GetPlayers() do
		self:ApplyDummy(player)
	end

	self:ApplyDummy(LocalPlayer)
end

function Grenades:GameRender()
	if GRENADE_DEBUG then
		for k, grenade in ipairs(self.grenades) do
			local transform = Transform3():Translate(grenade.object:GetPosition()):Rotate(Angle.AngleAxis(math.rad(90), Vector3.Left))

			Render:SetTransform(transform:Scale(0.1))
			Grenades.DebugModel:Draw()

			if grenade.timer:GetSeconds() > grenade.fusetime - 1 then
				Render:SetTransform(transform:Scale(10):Scale(grenade.radius * 0.4))
				Grenades.DebugModel:Draw()

				Render:SetTransform(transform:Scale(1 / 0.4))
				Grenades.DebugModel:Draw()

				Render:ResetTransform()
			end
		end

		collectgarbage()
	end
end

function Grenades:PostRender()
	if self.flashedTimer:GetSeconds() < Grenade.FlashTime and self.flashed then
		Render:FillArea(Vector2.Zero, Render.Size, Color(255, 255, 255, self.flashedOpacity * (Grenade.FlashTime - self.flashedTimer:GetSeconds()) / Grenade.FlashTime))
	else
		self.flashed = false
	end
end

function Grenades:ApplyDummy(player)
	local state = player:GetLeftArmState()
	local dummy = self.dummies[player:GetId()]

	if table.find({AnimationState.LaSUnderThrowGrenade, AnimationState.LaSOverThrowGrenade}, state) then
		if not dummy then
			dummy = ClientStaticObject.Create({
				model = "wea33-wea33.lod",
				position = Vector3(),
				angle = Angle()
			})

			self.dummies[player:GetId()] = dummy
		end

		dummy:SetAngle(player:GetBoneAngle("ragdoll_LeftForeArm"))
		dummy:SetPosition(player:GetBonePosition("ragdoll_LeftForeArm") + dummy:GetAngle() * Grenades.GrenadeOffset)
	elseif dummy then
		dummy:Remove()
		self.dummies[player:GetId()] = nil
	end
end

function Grenades:TossGrenade(type)
	if self.thrown and not table.find({AnimationState.LaSUnderThrowGrenade, AnimationState.LaSOverThrowGrenade}, LocalPlayer:GetLeftArmState()) then
		self.thrown = false
		self.thrownUnder = Camera:GetAngle().pitch < -math.pi / 12
		self.thrownType = type
		self.thrownTimer = false
	end
end

function Grenades:GrenadeTossed(args)
	if GRENADE_DEBUG then
		local type = false

		for k, v in pairs(Grenade.Types) do
			if table.compare(args.type, v) then
				type = k
			end
		end

		if type then
			Chat:Print(type .. " Grenade:", Color.Yellow)
			for k, v in pairs(args.type) do
				Chat:Print("		" .. k .. ": " .. v, Color.Yellow)
			end
		else
			Chat:Print("Unknown Grenade:", Color.Red)
			for k, v in pairs(args.type) do
				Chat:Print("		" .. k .. ": " .. v, Color.Red)
			end
		end
	end

	table.insert(self.grenades, Grenade(args.position, args.velocity, args.type))
end

Grenades = Grenades()
