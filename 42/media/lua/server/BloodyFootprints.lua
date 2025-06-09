if not BloodyFootprints then
    BloodyFootprints = {}
end

-- Configuration
BloodyFootprints.Config = {
    enablePlayerFootsteps = true,  -- Toggle for player footprints
    enableZombieFootsteps = true,  -- Toggle for zombie footprints
    maxFootprints = 200,          -- Max footprints displayed
    footprintLifespan = 4500,     -- Footprint duration (seconds)
    zombieMaxDistance = 25,       -- Max distance for zombie footprints
    zombieCheckInterval = 120,    -- Zombie footprint check interval (ms)
    zombieBatchSize = 12,         -- Zombies processed per cycle
    zombieProcessFrequency = 2,   -- Process zombies every X ticks
    bloodSteps = 5                -- Steps after stepping in blood
}

-- Footprint tile sprites
BloodyFootprints.FOOTPRINT_TILES = {
    [0] = {left = "bloody_footsteps_8", right = "bloody_footsteps_0"},
    [1] = {left = "bloody_footsteps_1", right = "bloody_footsteps_9"},
    [2] = {left = "bloody_footsteps_24", right = "bloody_footsteps_16"},
    [3] = {left = "bloody_footsteps_9", right = "bloody_footsteps_1"},
    [4] = {left = "bloody_footsteps_10", right = "bloody_footsteps_2"},
    [5] = {left = "bloody_footsteps_2", right = "bloody_footsteps_10"},
    [6] = {left = "bloody_footsteps_11", right = "bloody_footsteps_3"},
    [7] = {left = "bloody_footsteps_3", right = "bloody_footsteps_11"},
}

-- State management
BloodyFootprints.State = {
    placedFootprints = {},      -- Track active footprints
    footprintQueue = {},        -- Queue for footprint management
    zombieLastPositions = {},   -- Last known zombie positions
    lastSquare = nil,           -- Last player square
    isLeftStep = true,          -- Alternates left/right for player
    playerTimer = 0,            -- Player footprint timer
    zombieTimer = 0,            -- Zombie footprint timer
    cleanupTimer = 0,           -- Cleanup timer
    cleanupIndex = 1,           -- Cleanup queue index
    lastCleanupTime = 0,        -- Last cleanup timestamp
    zombieIndex = 0,            -- Current zombie processing index
    lastTickProcessed = 0,      -- Last zombie processing tick
    playerBloodSteps = 0,       -- Player blood steps
    zombieBloodSteps = {}       -- Zombie blood steps (by zombie ID)
}

-- Utility functions
BloodyFootprints.GetMovementDirection = function(lastSquare, square)
    if not lastSquare or not square then return nil end
    local dx = square:getX() - lastSquare:getX()
    local dy = square:getY() - lastSquare:getY()
    if dx == 0 and dy < 0 then return 0
    elseif dx > 0 and dy == 0 then return 1
    elseif dx == 0 and dy > 0 then return 2
    elseif dx < 0 and dy == 0 then return 3
    elseif dx > 0 and dy < 0 then return 4
    elseif dx < 0 and dy > 0 then return 5
    elseif dx > 0 and dy > 0 then return 6
    elseif dx < 0 and dy < 0 then return 7
    end
    return nil
end

BloodyFootprints.GetZombieID = function(zombie)
    local id = zombie:getID() or zombie:getOnlineID() or -1
    if id > 0 then return tostring(id) end
    return tostring(zombie:getX()) .. "_" .. tostring(zombie:getY())
end

BloodyFootprints.HasBloodOnSquare = function(square)
    if not square then return false end
    if square:haveBloodFloor() then return true end
    for i = 0, square:getObjects():size() - 1 do
        local object = square:getObjects():get(i)
        if object and object:getSprite() then
            local spriteName = object:getSprite():getName()
            for _, bloodTile in ipairs(BloodyFootprints_Config.BloodFloorTiles) do
                if spriteName == bloodTile then return true end
            end
        end
    end
    return false
end

-- Footprint management
BloodyFootprints.CreateFootprint = function(square, direction, isLeftStep, isZombie, entityID)
    if not square or not BloodyFootprints.FOOTPRINT_TILES[direction] then return end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local key = x * 10000 + y * 10 + z
    if BloodyFootprints.State.placedFootprints[key] then return end

    local side = isLeftStep and "left" or "right"
    local tile = BloodyFootprints.FOOTPRINT_TILES[direction][side]
    if not tile then return end

    local footprint = IsoObject.new(square, tile, "footprint", false)
    if getWorld():getGameMode() == "Multiplayer" then
        square:transmitAddObjectToSquare(footprint, 1)
    else
        square:AddTileObject(footprint)
    end

    BloodyFootprints.State.placedFootprints[key] = { footprint = footprint, square = square, time = getGameTime():getWorldAgeHours() * 3600 }
    table.insert(BloodyFootprints.State.footprintQueue, key)

    if #BloodyFootprints.State.footprintQueue > BloodyFootprints.Config.maxFootprints then
        BloodyFootprints.RemoveFootprint(table.remove(BloodyFootprints.State.footprintQueue, 1))
    end

    if not isZombie then
        BloodyFootprints.State.isLeftStep = not BloodyFootprints.State.isLeftStep
    end
end

BloodyFootprints.RemoveFootprint = function(key)
    local data = BloodyFootprints.State.placedFootprints[key]
    if not data or not data.square or not data.footprint then return end
    data.square:RemoveTileObject(data.footprint)
    BloodyFootprints.State.placedFootprints[key] = nil
end

-- Player footprint handling
BloodyFootprints.AddPlayerFootprints = function()
    if not BloodyFootprints.Config.enablePlayerFootsteps then return end

    local player = getSpecificPlayer(0)
    if not player or player:getVehicle() then
        BloodyFootprints.State.lastSquare = player and player:getSquare()
        return
    end

    local square = player:getSquare()
    if not square or square == BloodyFootprints.State.lastSquare then return end

    -- Check for blood on player's current square
    if BloodyFootprints.HasBloodOnSquare(square) then
        BloodyFootprints.State.playerBloodSteps = BloodyFootprints.Config.bloodSteps
    end

    if BloodyFootprints.State.playerBloodSteps > 0 then
        local direction = BloodyFootprints.GetMovementDirection(BloodyFootprints.State.lastSquare, square)
        if direction then
            BloodyFootprints.CreateFootprint(square, direction, BloodyFootprints.State.isLeftStep, false, nil)
            BloodyFootprints.State.playerBloodSteps = BloodyFootprints.State.playerBloodSteps - 1
        end
    end

    BloodyFootprints.State.lastSquare = square
end

-- Zombie footprint handling
BloodyFootprints.AddZombieFootprints = function()
    if not BloodyFootprints.Config.enableZombieFootsteps then return end

    local gameTime = getGameTime()
    BloodyFootprints.State.zombieTimer = BloodyFootprints.State.zombieTimer + gameTime:getTimeDelta() * 1000
    if BloodyFootprints.State.zombieTimer < BloodyFootprints.Config.zombieCheckInterval then return end
    BloodyFootprints.State.zombieTimer = 0

    local player = getSpecificPlayer(0)
    local cell = getCell()
    if not player or not cell then return end

    local zombieList = cell:getZombieList()
    if not zombieList or zombieList:size() == 0 then return end

    local playerSquare = player:getSquare()
    if not playerSquare then return end

    local playerX, playerY = playerSquare:getX(), playerSquare:getY()
    local tick = gameTime:getWorldAgeHours() * 3600
    if tick - BloodyFootprints.State.lastTickProcessed < BloodyFootprints.Config.zombieProcessFrequency then return end
    BloodyFootprints.State.lastTickProcessed = tick

    local zombieCount = zombieList:size()
    local zombiesProcessed = 0
    local startIndex = BloodyFootprints.State.zombieIndex

    while zombiesProcessed < BloodyFootprints.Config.zombieBatchSize do
        if BloodyFootprints.State.zombieIndex >= zombieCount then
            BloodyFootprints.State.zombieIndex = 0
            if startIndex == 0 then break end
        end

        local zombie = zombieList:get(BloodyFootprints.State.zombieIndex)
        BloodyFootprints.State.zombieIndex = BloodyFootprints.State.zombieIndex + 1

        if zombie and not zombie:isDead() then
            local zombieSquare = zombie:getSquare()
            if zombieSquare then
                local zombieX, zombieY = zombieSquare:getX(), zombieSquare:getY()
                local distanceSquared = (playerX - zombieX)^2 + (playerY - zombieY)^2
                if distanceSquared <= BloodyFootprints.Config.zombieMaxDistance^2 then
                    local zombieID = BloodyFootprints.GetZombieID(zombie)
                    local lastPos = BloodyFootprints.State.zombieLastPositions[zombieID]
                    BloodyFootprints.State.zombieLastPositions[zombieID] = zombieSquare

                    -- Check for blood on zombie's current square
                    if BloodyFootprints.HasBloodOnSquare(zombieSquare) then
                        BloodyFootprints.State.zombieBloodSteps[zombieID] = BloodyFootprints.Config.bloodSteps
                    end

                    if BloodyFootprints.State.zombieBloodSteps[zombieID] and BloodyFootprints.State.zombieBloodSteps[zombieID] > 0 then
                        if lastPos and (lastPos:getX() ~= zombieX or lastPos:getY() ~= zombieY) then
                            local direction = BloodyFootprints.GetMovementDirection(lastPos, zombieSquare)
                            if direction then
                                BloodyFootprints.CreateFootprint(zombieSquare, direction, ZombRand(2) == 0, true, zombieID)
                                BloodyFootprints.State.zombieBloodSteps[zombieID] = BloodyFootprints.State.zombieBloodSteps[zombieID] - 1
                            end
                        end
                    else
                        BloodyFootprints.State.zombieBloodSteps[zombieID] = nil
                    end
                else
                    BloodyFootprints.State.zombieLastPositions[zombieID] = nil
                    BloodyFootprints.State.zombieBloodSteps[zombieID] = nil
                end
            end
        end

        zombiesProcessed = zombiesProcessed + 1
        if BloodyFootprints.State.zombieIndex == startIndex then break end
    end
end

-- Cleanup
BloodyFootprints.CleanupFootprints = function()
    if not BloodyFootprints.Config.enablePlayerFootsteps and not BloodyFootprints.Config.enableZombieFootsteps then return end

    local gameTime = getGameTime()
    BloodyFootprints.State.cleanupTimer = BloodyFootprints.State.cleanupTimer + gameTime:getTimeDelta() * 1000
    if BloodyFootprints.State.cleanupTimer < 5000 then return end
    BloodyFootprints.State.cleanupTimer = 0

    local now = gameTime:getWorldAgeHours() * 3600
    if now - BloodyFootprints.State.lastCleanupTime < 60 then return end
    BloodyFootprints.State.lastCleanupTime = now

    local processed = 0
    local queueLength = #BloodyFootprints.State.footprintQueue
    while processed < 40 and BloodyFootprints.State.cleanupIndex <= queueLength do
        local key = BloodyFootprints.State.footprintQueue[BloodyFootprints.State.cleanupIndex]
        local data = BloodyFootprints.State.placedFootprints[key]
        if data and now - data.time > BloodyFootprints.Config.footprintLifespan then
            BloodyFootprints.RemoveFootprint(key)
            table.remove(BloodyFootprints.State.footprintQueue, BloodyFootprints.State.cleanupIndex)
            queueLength = queueLength - 1
        else
            BloodyFootprints.State.cleanupIndex = BloodyFootprints.State.cleanupIndex + 1
        end
        processed = processed + 1
    end
    if BloodyFootprints.State.cleanupIndex > queueLength then
        BloodyFootprints.State.cleanupIndex = 1
    end
end

-- Initialization
BloodyFootprints.OnGameStart = function()
    BloodyFootprints.State.lastSquare = nil
    BloodyFootprints.State.isLeftStep = true
    BloodyFootprints.State.playerBloodSteps = 0
    BloodyFootprints.State.zombieBloodSteps = {}
    BloodyFootprints.State.placedFootprints = {}
    BloodyFootprints.State.footprintQueue = {}
    BloodyFootprints.State.zombieLastPositions = {}
    BloodyFootprints.State.playerTimer = 0
    BloodyFootprints.State.zombieTimer = 0
    BloodyFootprints.State.cleanupTimer = 0
    BloodyFootprints.State.cleanupIndex = 1
    BloodyFootprints.State.lastCleanupTime = 0
    BloodyFootprints.State.zombieIndex = 0
    BloodyFootprints.State.lastTickProcessed = 0
    print("[FecalFootprints] Mod initialized with blood-based player and zombie support")
end

-- Event registration with conditional checks
BloodyFootprints.RegisterEvents = function()
    Events.OnGameStart.Add(BloodyFootprints.OnGameStart)
    if BloodyFootprints.Config.enablePlayerFootsteps then
        Events.OnPlayerMove.Add(BloodyFootprints.AddPlayerFootprints)
    end
    if BloodyFootprints.Config.enableZombieFootsteps then
        Events.OnTick.Add(BloodyFootprints.AddZombieFootprints)
    end
    if BloodyFootprints.Config.enablePlayerFootsteps or BloodyFootprints.Config.enableZombieFootsteps then
        Events.OnTick.Add(BloodyFootprints.CleanupFootprints)
    end
end

BloodyFootprints.RegisterEvents()