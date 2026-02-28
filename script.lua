--[[
	TIC TAC TOE MULTI-BOARD SYSTEM
	VERSION: 7.1
	By : ItzMystVoid
	FIXED: Win lines disappear IMMEDIATELY after round ends
]]

--// SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--// CONFIGURATION & CONSTANTS
local TRANSPARENCY_OFF = 0
local TRANSPARENCY_ON = 1
local COLOR_X = BrickColor.new("Bright blue")
local COLOR_O = BrickColor.new("Bright red")
local COLOR_WIN = BrickColor.new("Bright green")
local NEON = Enum.Material.Neon

--// WIN PATTERNS
local winPatterns = {
	{1, 2, 3}, {4, 5, 6}, {7, 8, 9}, -- Horizontals
	{1, 4, 7}, {2, 5, 8}, {3, 6, 9}, -- Verticals
	{1, 5, 9}, {3, 5, 7}             -- Diagonals
}

--// REMOTE EVENT SETUP
local remoteFolder = ReplicatedStorage:FindFirstChild("TicTacToeRemotes") or Instance.new("Folder", ReplicatedStorage)
remoteFolder.Name = "TicTacToeRemotes"

local function createRemote(name)
	local r = remoteFolder:FindFirstChild(name) or Instance.new("RemoteEvent", remoteFolder)
	r.Name = name
	return r
end

local setCameraEvent = createRemote("SetCamera")
local resetCameraEvent = createRemote("ResetCamera")

--// BOARD CLASS
local Board = {}
Board.__index = Board

function Board.new(boardModel, boardNumber)
	local self = setmetatable({}, Board)

	-- References
	self.model = boardModel
	self.boardNumber = boardNumber
	self.ticTacToe = boardModel:WaitForChild("TicTacToe")
	self.scoreFrame = boardModel:WaitForChild("scoreFrame")
	self.seat1Model = boardModel:WaitForChild("Seat1")
	self.seat2Model = boardModel:WaitForChild("Seat2")
	self.cameraPart = boardModel:WaitForChild("CameraPart")

	-- UI References
	local interior = self.scoreFrame:WaitForChild("interior")
	local surfaceGui = interior:WaitForChild("SurfaceGui")
	local frame = surfaceGui:WaitForChild("Frame")
	self.p1NameLabel = frame:WaitForChild("player1Name")
	self.p2NameLabel = frame:WaitForChild("player2Name")
	self.p1WinsLabel = frame:WaitForChild("player1Wins")
	self.p2WinsLabel = frame:WaitForChild("player2Wins")
	self.p1Image = frame:WaitForChild("player1")
	self.p2Image = frame:WaitForChild("player2")

	-- Game State
	self.boardState = {0, 0, 0, 0, 0, 0, 0, 0, 0}
	self.currentTurn = 1
	self.gameActive = false
	self.player1 = nil
	self.player2 = nil
	self.player1Wins = 0
	self.player2Wins = 0

	-- Initialize
	self:initializeBoard()
	self:setupSeats()
	self:setupDetectors()
	self:clearScoreboard()

	print("✅ Board " .. self.boardNumber .. " initialized!")

	return self
end

--------------------------------------------------------------------
-- ENHANCED VISUAL EFFECTS
--------------------------------------------------------------------

function Board:createSparkleEffect(part)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Parent = part
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(part.Color)
	sparkle.Size = NumberSequence.new(0.5, 0)
	sparkle.Lifetime = NumberRange.new(0.3, 0.6)
	sparkle.Rate = 50
	sparkle.Speed = NumberRange.new(3, 5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Enabled = true

	task.delay(0.3, function()
		if sparkle and sparkle.Parent then
			sparkle.Enabled = false
			task.wait(1)
			sparkle:Destroy()
		end
	end)
end

function Board:createGlowEffect(part)
	local pointLight = Instance.new("PointLight")
	pointLight.Parent = part
	pointLight.Brightness = 0
	pointLight.Color = part.Color
	pointLight.Range = 8

	TweenService:Create(pointLight, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 2
	}):Play()

	task.delay(1, function()
		if pointLight and pointLight.Parent then
			TweenService:Create(pointLight, TweenInfo.new(0.5), {
				Brightness = 0.5
			}):Play()
		end
	end)
end

function Board:animatePieceAppearance(part)
	local originalSize = part.Size
	local originalTransparency = 0

	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.Material = NEON

	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local goal = {
		Size = originalSize,
		Transparency = originalTransparency
	}

	local tween = TweenService:Create(part, tweenInfo, goal)
	tween:Play()

	-- Rotation effect
	local spinValue = Instance.new("NumberValue")
	local startCFrame = part.CFrame

	spinValue.Changed:Connect(function(value)
		if part and part.Parent then
			part.CFrame = startCFrame * CFrame.Angles(0, math.rad(value * 360), 0)
		end
	end)

	local spinTween = TweenService:Create(
		spinValue,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Value = 1}
	)
	spinTween:Play()

	task.spawn(function()
		self:createSparkleEffect(part)
		self:createGlowEffect(part)
	end)

	tween.Completed:Connect(function()
		if part and part.Parent then
			local bounceTween = TweenService:Create(
				part,
				TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, true),
				{Size = originalSize * 1.1}
			)
			bounceTween:Play()
		end
		spinValue:Destroy()
	end)
end

function Board:pulseWinningLine(winLine)
	local pulseTween = TweenService:Create(
		winLine,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
		{Transparency = 0.3}
	)
	pulseTween:Play()

	local light = Instance.new("PointLight")
	light.Parent = winLine
	light.Color = Color3.fromRGB(0, 255, 0)
	light.Brightness = 3
	light.Range = 15

	-- ✅ AUTO HIDE ANY WIN LINE AFTER 2 SECONDS
	task.delay(2, function()
		if winLine and winLine.Parent then
			winLine.Transparency = TRANSPARENCY_ON
		end
	end)
end

--------------------------------------------------------------------
-- CLEANUP FUNCTIONS (CRITICAL FIX)
--------------------------------------------------------------------

function Board:cleanAllEffects()
	print("🧹 Board " .. self.boardNumber .. ": Cleaning all effects")

	-- Stop ALL tweens on win lines first
	for i = 1, 8 do
		local winLine = self.ticTacToe:FindFirstChild("Win" .. i)
		if winLine then 
			-- IMMEDIATELY hide the win line
			winLine.Transparency = TRANSPARENCY_ON
			winLine.BrickColor = COLOR_WIN
			winLine.Material = NEON

			-- Destroy all effects and tweens
			for _, child in ipairs(winLine:GetChildren()) do
				if child:IsA("PointLight") or child:IsA("ParticleEmitter") or child:IsA("Tween") then
					child:Destroy()
				end
			end
		end
	end

	-- Clean all X, O, and WIN LINE pieces (UNIFIED)
	for i = 1, 9 do
		for _, partName in ipairs({
			"X" .. i,
			"O" .. i,
			"Win" .. i -- ✅ Treat win lines like pieces
			}) do
			local part = self.ticTacToe:FindFirstChild(partName)
			if part then
				part.Transparency = TRANSPARENCY_ON

				for _, child in ipairs(part:GetChildren()) do
					if child:IsA("PointLight")
						or child:IsA("ParticleEmitter")
						or child:IsA("NumberValue") then
						child:Destroy()
					end
				end
			end
		end
	end

	print("✅ Board " .. self.boardNumber .. ": All effects cleaned")
end

--------------------------------------------------------------------
-- SCOREBOARD MANAGEMENT
--------------------------------------------------------------------

function Board:clearScoreboard()
	self.p1NameLabel.Text = "Waiting..."
	self.p1Image.Image = ""
	self.p1WinsLabel.Text = "Wins: 0"

	self.p2NameLabel.Text = "Waiting..."
	self.p2Image.Image = ""
	self.p2WinsLabel.Text = "Wins: 0"
end

function Board:updateScoreboard()
	if self.player1 then
		self.p1NameLabel.Text = self.player1.Name
		self.p1Image.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. self.player1.UserId .. "&width=420&height=420&format=png"
		self.p1WinsLabel.Text = "Wins: " .. self.player1Wins
	else
		self.p1NameLabel.Text = "Waiting..."
		self.p1Image.Image = ""
		self.p1WinsLabel.Text = "Wins: 0"
	end

	if self.player2 then
		self.p2NameLabel.Text = self.player2.Name
		self.p2Image.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. self.player2.UserId .. "&width=420&height=420&format=png"
		self.p2WinsLabel.Text = "Wins: " .. self.player2Wins
	else
		self.p2NameLabel.Text = "Waiting..."
		self.p2Image.Image = ""
		self.p2WinsLabel.Text = "Wins: 0"
	end
end

--------------------------------------------------------------------
-- BOARD VISUALS
--------------------------------------------------------------------

function Board:updateBoardVisuals(animateIndex)
	for _, part in ipairs(self.ticTacToe:GetChildren()) do
		if part.Name == "Line" or part.Name == "BoardBase" then
			part.Transparency = TRANSPARENCY_OFF
		end
	end

	for i = 1, 9 do
		local xPart = self.ticTacToe:FindFirstChild("X" .. i)
		local oPart = self.ticTacToe:FindFirstChild("O" .. i)

		if xPart then
			if self.boardState[i] == 1 then
				xPart.Transparency = TRANSPARENCY_OFF
				xPart.BrickColor = COLOR_X
				xPart.Material = NEON

				if i == animateIndex then
					self:animatePieceAppearance(xPart)
				end
			else
				xPart.Transparency = TRANSPARENCY_ON
			end
		end

		if oPart then
			if self.boardState[i] == 2 then
				oPart.Transparency = TRANSPARENCY_OFF
				oPart.BrickColor = COLOR_O
				oPart.Material = NEON

				if i == animateIndex then
					self:animatePieceAppearance(oPart)
				end
			else
				oPart.Transparency = TRANSPARENCY_ON
			end
		end
	end
end

--------------------------------------------------------------------
-- CAMERA MANAGEMENT
--------------------------------------------------------------------

function Board:resetPlayerCamera(player)
	if player then
		pcall(function()
			resetCameraEvent:FireClient(player)
		end)
	end
end

function Board:lockPlayerCamera(player)
	if player then
		pcall(function()
			setCameraEvent:FireClient(player, true, self.cameraPart)
		end)
	end
end

function Board:manageCamera(isStarting)
	if isStarting then
		if self.player1 then self:lockPlayerCamera(self.player1) end
		if self.player2 then self:lockPlayerCamera(self.player2) end
	else
		if self.player1 then self:resetPlayerCamera(self.player1) end
		if self.player2 then self:resetPlayerCamera(self.player2) end
	end
end

--------------------------------------------------------------------
-- GAME LOGIC
--------------------------------------------------------------------

function Board:startNewGame()
	print("🎮 Board " .. self.boardNumber .. ": Starting new game!")

	self:cleanAllEffects()

	self.boardState = {0, 0, 0, 0, 0, 0, 0, 0, 0}
	self.currentTurn = 1
	self.gameActive = true

	self:updateBoardVisuals()
	self:updateScoreboard()

	task.wait(0.2)
	self:manageCamera(true)
end

function Board:resetGame()
	print("🔄 Board " .. self.boardNumber .. ": Resetting game")

	self:cleanAllEffects()

	self.boardState = {0, 0, 0, 0, 0, 0, 0, 0, 0}
	self.currentTurn = 1
	self.gameActive = false

	self:updateBoardVisuals()
	self:updateScoreboard()

	if self.player1 and self.player2 then
		task.wait(0.3)
		self:startNewGame()
	end
end

function Board:checkWinner()
	for index, pattern in ipairs(winPatterns) do
		local a, b, c = pattern[1], pattern[2], pattern[3]
		if self.boardState[a] ~= 0 and self.boardState[a] == self.boardState[b] and self.boardState[a] == self.boardState[c] then
			return self.boardState[a], index
		end
	end
	for i = 1, 9 do if self.boardState[i] == 0 then return 0, nil end end
	return 3, nil
end

function Board:onGameEnd(winner, patternIndex)
	self.gameActive = false

	if winner == 1 then 
		self.player1Wins = self.player1Wins + 1
		print("🏆 Board " .. self.boardNumber .. ": Player 1 wins!")
	elseif winner == 2 then 
		self.player2Wins = self.player2Wins + 1
		print("🏆 Board " .. self.boardNumber .. ": Player 2 wins!")
	else
		print("🤝 Board " .. self.boardNumber .. ": Draw!")
	end

	-- WIN LINES DISABLED
--[[
if patternIndex then
	local winLine = self.ticTacToe:FindFirstChild("Win" .. patternIndex)
	if winLine then
		winLine.Transparency = TRANSPARENCY_OFF
		winLine.BrickColor = COLOR_WIN
		winLine.Material = NEON
		self:pulseWinningLine(winLine)
	end
end
]]

	self:updateScoreboard()

	-- Wait to show the win
	task.wait(2.5)

	-- IMMEDIATELY CLEAN EVERYTHING BEFORE CAMERA RESET
	self:cleanAllEffects()

	-- Then reset cameras
	self:manageCamera(false)
	task.wait(0.5)

	-- Reset the game
	self:resetGame()
end

function Board:onSquareClicked(index, clickingPlayer)
	if not self.gameActive or self.boardState[index] ~= 0 then return end

	if self.currentTurn == 1 and clickingPlayer ~= self.player1 then return end
	if self.currentTurn == 2 and clickingPlayer ~= self.player2 then return end

	self.boardState[index] = self.currentTurn
	self:updateBoardVisuals(index)

	local winner, pIdx = self:checkWinner()
	if winner ~= 0 then
		self:onGameEnd(winner, pIdx)
	else
		self.currentTurn = (self.currentTurn == 1) and 2 or 1
	end
end

--------------------------------------------------------------------
-- PLAYER MANAGEMENT
--------------------------------------------------------------------

function Board:onPlayerLeft(player)
	local wasPlaying = false

	if self.player1 == player then
		print("👋 Board " .. self.boardNumber .. ": Player 1 left")
		self:resetPlayerCamera(player)
		self.player1 = nil
		self.player1Wins = 0
		wasPlaying = true
	elseif self.player2 == player then
		print("👋 Board " .. self.boardNumber .. ": Player 2 left")
		self:resetPlayerCamera(player)
		self.player2 = nil
		self.player2Wins = 0
		wasPlaying = true
	end

	if wasPlaying then
		self.gameActive = false

		if self.player1 then self:resetPlayerCamera(self.player1) end
		if self.player2 then self:resetPlayerCamera(self.player2) end

		self:cleanAllEffects()
		self:updateScoreboard()

		self.boardState = {0, 0, 0, 0, 0, 0, 0, 0, 0}
		self.currentTurn = 1
		self:updateBoardVisuals()
	end
end

--------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------

function Board:initializeBoard()
	for _, p in ipairs(self.ticTacToe:GetChildren()) do
		if p.Name == "Line" or p.Name == "BoardBase" then 
			p.Transparency = 0 
		end
	end
end

function Board:setupDetectors()
	for i = 1, 9 do
		local det = self.ticTacToe:FindFirstChild("Detector" .. i)
		if det then
			det.Transparency = TRANSPARENCY_ON
			det.CanCollide = false
			local cd = det:FindFirstChildOfClass("ClickDetector") or Instance.new("ClickDetector", det)
			cd.MouseClick:Connect(function(ply)
				self:onSquareClicked(i, ply)
			end)
		end
	end
end

function Board:setupSeats()
	local function setupSeat(seatModel, seatIndex)
		local mainPart = seatModel:WaitForChild("main")

		if not mainPart:IsA("Seat") then
			local s = Instance.new("Seat")
			s.Name = "main"
			s.Size, s.CFrame, s.Parent = mainPart.Size, mainPart.CFrame, seatModel
			mainPart:Destroy()
			mainPart = s
		end

		for _, part in ipairs(seatModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				if part == mainPart then
					part.Transparency = TRANSPARENCY_ON
				else
					part.Transparency = TRANSPARENCY_OFF
				end
			end
		end

		mainPart:GetPropertyChangedSignal("Occupant"):Connect(function()
			local humanoid = mainPart.Occupant
			local ply = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)

			if seatIndex == 1 then
				if ply then
					print("🪑 Board " .. self.boardNumber .. ": Player 1 sat down - " .. ply.Name)
					self.player1 = ply
				else
					if self.player1 then
						print("🚶 Board " .. self.boardNumber .. ": Player 1 stood up")
						self:onPlayerLeft(self.player1)
					end
				end
			else
				if ply then
					print("🪑 Board " .. self.boardNumber .. ": Player 2 sat down - " .. ply.Name)
					self.player2 = ply
				else
					if self.player2 then
						print("🚶 Board " .. self.boardNumber .. ": Player 2 stood up")
						self:onPlayerLeft(self.player2)
					end
				end
			end

			self:updateScoreboard()

			if self.player1 and self.player2 and not self.gameActive then
				self:startNewGame()
			end
		end)
	end

	setupSeat(self.seat1Model, 1)
	setupSeat(self.seat2Model, 2)
end

--------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------

local boards = {}
local boardCount = 0

for _, model in ipairs(workspace:GetChildren()) do
	if model:IsA("Model") and string.match(model.Name, "^Tic Tac Toe Board%d+$") then
		local boardNum = tonumber(string.match(model.Name, "%d+"))
		if boardNum then
			local success, board = pcall(function()
				return Board.new(model, boardNum)
			end)

			if success then
				table.insert(boards, board)
				boardCount = boardCount + 1
			else
				warn("❌ Failed to initialize board: " .. model.Name)
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	for _, board in ipairs(boards) do
		board:onPlayerLeft(player)
	end
end)

print("🎮 TIC TAC TOE MULTI-BOARD SYSTEM LOADED!")
print("📊 Total Boards: " .. boardCount)
print("✅ WIN LINE BUG FIXED - Lines disappear immediately!")
