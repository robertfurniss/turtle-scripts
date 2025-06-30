local FUEL_SLOT = 1
local SAPLING_SLOT = 2

local TREE_PLOT = {
    {x = 0, z = 0},
    {x = 0, z = 3},
    {x = 3, z = 0},
    {x = 3, z = 3}
}

local currentX = 0
local currentY = 0 
local currentZ = 0
local currentDir = "north"

local function updatePosition(moveType, success)
    if not success then return end -- Only update if the move was successful

    if moveType == "forward" then
        if currentDir == "north" then currentZ = currentZ - 1
        elseif currentDir == "east" then currentX = currentX + 1
        elseif currentDir == "south" then currentZ = currentZ + 1
        elseif currentDir == "west" then currentX = currentX - 1
        end
    elseif moveType == "back" then
        if currentDir == "north" then currentZ = currentZ + 1
        elseif currentDir == "east" then currentX = currentX - 1
        elseif currentDir == "south" then currentZ = currentZ - 1
        elseif currentDir == "west" then currentX = currentX + 1
        end
    elseif moveType == "up" then
        currentY = currentY + 1
    elseif moveType == "down" then
        currentY = currentY - 1
    elseif moveType == "turnLeft" then
        if currentDir == "north" then currentDir = "west"
        elseif currentDir == "east" then currentDir = "north"
        elseif currentDir == "south" then currentDir = "east"
        elseif currentDir == "west" then currentDir = "south"
        end
    elseif moveType == "turnRight" then
        if currentDir == "north" then currentDir = "east"
        elseif currentDir == "east" then currentDir = "south"
        elseif currentDir == "south" then currentDir = "west"
        elseif currentDir == "west" then currentDir = "north"
        end
    end
end

local function attemptMove(moveFunc, digFunc)
    local success, reason = moveFunc()
    if not success then
        print("Blocked: " .. (reason or "Unknown reason") .. ". Attempting to dig.")
        if digFunc then
            local digSuccess, digReason = digFunc()
            if not digSuccess then
                print("Failed to dig: " .. (digReason or "Unknown reason") .. ". Cannot proceed.")
                error("Turtle stuck and cannot clear path. Program halted.")
            else
                print("Dug successfully. Retrying move.")
                success, reason = moveFunc() -- Retry move after digging
                if not success then
                    print("Still blocked after digging: " .. (reason or "Unknown reason") .. ". Cannot proceed.")
                    error("Turtle still stuck after digging. Program halted.")
                end
            end
        else
            print("Cannot dig in this direction (no dig function provided). Cannot proceed.")
            error("Turtle stuck and no dig function provided for this direction. Program halted.")
        end
    end
    return success
end

local function safeForward()
    local success = attemptMove(turtle.forward, turtle.dig)
    updatePosition("forward", success)
    return success
end

local function safeBack()
    local success = attemptMove(turtle.back, turtle.dig)
    updatePosition("back", success)
    return success
end

local function safeUp()
    local success = attemptMove(turtle.up, turtle.digUp)
    updatePosition("up", success)
    return success
end

local function safeDown()
    local success = attemptMove(turtle.down, turtle.digDown)
    updatePosition("down", success)
    return success
end

local function safeTurnLeft()
    local success = attemptMove(turtle.turnLeft)
    updatePosition("turnLeft", success)
    return success
end

local function safeTurnRight()
    local success = attemptMove(turtle.turnRight)
    updatePosition("turnRight", success)
    return success
end

local function refuel()
    if turtle.getFuelLevel() < turtle.getFuelLimit() * 0.2 then
        print("Fuel low. Attempting to refuel.")
        local currentSlot = turtle.getSelectedSlot() 
        turtle.select(FUEL_SLOT) 
        local success = turtle.refuel()
        turtle.select(currentSlot)
        if success then
            print("Refueled successfully. Current fuel: " .. turtle.getFuelLevel())
        else
            print("Failed to refuel. Check for fuel items in slot " .. FUEL_SLOT .. ".")
            error("Failed to refuel. Program halted.")
        end
    end
end

local function depositItems()
    print("Depositing surplus items into chest.")
    local originalX, originalY, originalZ, originalDir = currentX, currentY, currentZ, currentDir

    safeTurnLeft()
    safeTurnLeft()

    for i = 1, 16 do
        if i ~= SAPLING_SLOT or i ~= FUEL_SLOT then
            turtle.select(i)
            local item = turtle.getItemDetail()
            if item then
                print("Dropping " .. item.count .. " " .. item.name .. " from slot " .. i .. ".")
                turtle.drop() 
            end
        end
    end
    
    safeTurnLeft()
    safeTurnLeft()
    
    currentX, currentY, currentZ, currentDir = originalX, originalY, originalZ, originalDir
    print("Finished depositing items.")
end

-- Moves the turtle to a specific relative (x, y, z) coordinate from its starting point.
-- This function calculates the necessary turns and movements.
local function moveToRelative(targetX, targetY, targetZ)
    print(string.format("Moving to relative position: (%d, %d, %d). Current: (%d, %d, %d), Dir: %s",
                        targetX, targetY, targetZ, currentX, currentY, currentZ, currentDir))
    
    -- Adjust Y (vertical) position first.
    while currentY < targetY do safeUp() end
    while currentY > targetY do safeDown() end

    -- Adjust X (horizontal) position.
    if targetX > currentX then
        while currentDir ~= "east" do safeTurnRight() end -- Turn towards east
        while currentX < targetX do safeForward() end      -- Move until target X is reached
    elseif targetX < currentX then
        while currentDir ~= "west" do safeTurnRight() end  -- Turn towards west
        while currentX > targetX do safeForward() end      -- Move until target X is reached
    end

    -- Adjust Z (depth/forward) position.
    if targetZ > currentZ then
        while currentDir ~= "south" do safeTurnRight() end -- Turn towards south
        while currentZ < targetZ do safeForward() end      -- Move until target Z is reached
    elseif targetZ < currentZ then
        while currentDir ~= "north" do safeTurnRight() end -- Turn towards north
        while currentZ > targetZ do safeForward() end      -- Move until target Z is reached
    end
    
    print(string.format("Reached relative position: (%d, %d, %d).", currentX, currentY, currentZ))
end

-- Plants a 2x2 square of spruce saplings at the turtle's current location.
-- Assumes the turtle is at the top-left corner of the 2x2 planting area, facing north.
local function plant2x2Tree()
    print("Attempting to plant 2x2 spruce saplings.")
    -- Save current position and direction to ensure the turtle returns to its exact spot.
    local originalX, originalY, originalZ, originalDir = currentX, currentY, currentZ, currentDir

    turtle.select(SAPLING_SLOT) -- Select the sapling slot
    -- Check if enough saplings are available.
    if turtle.getItemCount(SAPLING_SLOT) < 4 then
        print("Not enough saplings to plant a 2x2 tree. Need 4, have " .. turtle.getItemCount(SAPLING_SLOT) .. ".")
        error("Insufficient saplings. Program halted.")
    end

    -- Plant saplings in a 2x2 pattern:
    -- 1 2
    -- 3 4
    -- (Relative to the turtle's starting point for planting this 2x2)
    
    local success, reason = turtle.placeDown() -- Plant sapling 1 (at current position)
    if not success then print("Warning: Failed to plant sapling at (0,0) of plot: " .. (reason or "Unknown")) end

    safeForward()      -- Move one block forward
    success, reason = turtle.placeDown() -- Plant sapling 2
    if not success then print("Warning: Failed to plant sapling at (0,1) of plot: " .. (reason or "Unknown")) end

    safeBack()         -- Move back to original Z
    safeTurnRight()    -- Turn right (now facing east)
    safeForward()      -- Move one block right (now at (1,0) of the 2x2 area)
    success, reason = turtle.placeDown() -- Plant sapling 3
    if not success then print("Warning: Failed to plant sapling at (1,0) of plot: " .. (reason or "Unknown")) end

    safeForward()      -- Move one block forward (now at (1,1) of the 2x2 area)
    success, reason = turtle.placeDown() -- Plant sapling 4
    if not success then print("Warning: Failed to plant sapling at (1,1) of plot: " .. (reason or "Unknown")) end

    safeBack()         -- Move back to (1,0)
    safeBack()         -- Move back to (1,-1) (relative to origin of 2x2 area)
    safeTurnLeft()     -- Turn left (now facing north, back at (0,0) of the 2x2 area)

    -- Restore internal position tracking to original state after planting sequence.
    currentX, currentY, currentZ, currentDir = originalX, originalY, originalZ, originalDir
    print("Finished planting 2x2 saplings.")
end

-- Plants all trees in the defined farm layout (TREE_PLOTS).
local function plantFarm()
    print("Starting planting phase for the entire farm.")
    -- Save current position and direction to return to the farm's origin.
    local originalX, originalY, originalZ, originalDir = currentX, currentY, currentZ, currentDir
    
    -- Ensure turtle is at the farm's origin (0,0,0) and facing north before starting.
    moveToRelative(0, 0, 0)
    while currentDir ~= "north" do safeTurnLeft() end

    -- Iterate through each defined tree plot and plant saplings.
    for _, plot in ipairs(TREE_PLOTS) do
        moveToRelative(plot.x, 0, plot.z) -- Move to the base (ground level) of each tree plot.
        plant2x2Tree() -- Plant the 2x2 saplings for this tree.
    end
    
    -- Return to the farm's origin after planting all trees.
    moveToRelative(0, 0, 0)
    while currentDir ~= "north" do safeTurnLeft() end
    
    -- Restore the turtle's initial starting position and orientation.
    currentX, currentY, currentZ, currentDir = originalX, originalY, originalZ, originalDir
    print("Finished planting farm.")
}

-- Waits for trees to grow.
-- Spruce trees can take a while to grow, so a longer sleep duration is used.
local function waitForGrowth()
    print("Waiting for trees to grow (5 minutes).")
    os.sleep(300) -- Wait for 300 seconds (5 real-world minutes).
    print("Finished waiting.")
}

-- Harvests a single 2x2 spruce tree at the turtle's current location.
-- Assumes the turtle is at the top-left corner of the 2x2 sapling area, facing north.
local function harvest2x2Tree()
    print("Harvesting 2x2 spruce tree.")
    -- Save current position and direction to return to it after harvesting.
    local originalX, originalY, originalZ, originalDir = currentX, currentY, currentZ, currentDir

    -- Harvest the 4 base logs of the 2x2 tree.
    -- The tree trunks are at (0,0), (0,1), (1,0), (1,1) relative to the sapling origin.
    local success, reason = turtle.dig()       -- Dig the block under the turtle (first base log).
    if not success then print("Warning: Failed to dig at (0,0) of plot: " .. (reason or "Unknown")) end

    safeForward()      -- Move one block forward.
    success, reason = turtle.dig()       -- Dig second base log.
    if not success then print("Warning: Failed to dig at (0,1) of plot: " .. (reason or "Unknown")) end

    safeBack()         -- Move back to original Z.
    safeTurnRight()    -- Turn right (now facing east).
    safeForward()      -- Move one block right.
    success, reason = turtle.dig()       -- Dig third base log.
    if not success then print("Warning: Failed to dig at (1,0) of plot: " .. (reason or "Unknown")) end

    safeForward()      -- Move one block forward.
    success, reason = turtle.dig()       -- Dig fourth base log.
    if not success then print("Warning: Failed to dig at (1,1) of plot: " .. (reason or "Unknown")) end

    safeBack()         -- Move back to (1,0).
    safeBack()         -- Move back to (1,-1) (relative to origin of 2x2 area).
    safeTurnLeft()     -- Turn left (now facing north, back at (0,0) of the 2x2 area)

    -- Now, go up and harvest the rest of the tree (logs and leaves).
    -- Spruce trees can grow quite tall (up to ~30 blocks).
    local maxHarvestHeight = 25 -- Set a practical maximum height to ascend and dig.
    local currentHeight = 0

    while currentHeight < maxHarvestHeight do
        if turtle.detectUp() then -- Check if there's a block directly above.
            safeUp() -- Move up.
            success, reason = turtle.digDown() -- Dig the block it just moved off of (leaves or logs).
            if not success then print("Warning: Failed to dig down at height " .. currentHeight .. ": " .. (reason or "Unknown")) end
            currentHeight = currentHeight + 1
        else
            break -- No more blocks above, reached the top of the tree (or max height).
        end
    end
    
    -- Come back down to ground level, digging any remaining blocks on the way down.
    while currentY > originalY do
        safeDown() -- Move down.
        success, reason = turtle.digUp() -- Dig any blocks below (leaves or logs) that might have been missed.
        if not success then print("Warning: Failed to dig up while descending: " .. (reason or "Unknown")) end
    end
    
    -- Collect all dropped items around the turtle.
    -- Trees drop items randomly, so suck in all directions.
    for i = 1, 4 do -- Check 4 cardinal directions.
        turtle.suck() -- Suck items in front.
        safeTurnRight() -- Turn to check next direction.
    end
    turtle.suckDown() -- Suck items directly below.
    turtle.suckUp()   -- Suck items directly above.

    -- Restore internal position tracking to original state.
    currentX, currentY, currentZ, currentDir = originalX, originalY, originalZ, originalDir
    print("Finished harvesting 2x2 spruce tree.")
end

-- Harvests all trees in the defined farm layout (TREE_PLOTS).
local function harvestFarm()
    print("Starting harvesting phase for the entire farm.")
    -- Save current position and direction to return to the farm's origin.
    local originalX, originalY, originalZ, originalDir = currentX, currentY, currentZ, originalDir
    
    -- Ensure turtle is at the farm's origin (0,0,0) and facing north before starting.
    moveToRelative(0, 0, 0)
    while currentDir ~= "north" do safeTurnLeft() end

    -- Iterate through each defined tree plot and harvest the tree.
    for _, plot in ipairs(TREE_PLOTS) do
        moveToRelative(plot.x, 0, plot.z) -- Move to the base (ground level) of each tree plot.
        harvest2x2Tree() -- Harvest the tree at this location.
        refuel() -- Refuel after each tree harvest, as digging consumes a lot of fuel.
    end
    
    -- Return to the farm's origin after harvesting all trees.
    moveToRelative(0, 0, 0)
    while currentDir ~= "north" do safeTurnLeft() end

    -- Restore the turtle's initial starting position and orientation.
    currentX, currentY, currentZ, currentDir = originalX, originalY, originalZ, originalDir
    print("Finished harvesting farm.")
}

-- Main program loop
local function main()
    print("Spruce Tree Farm Automation Started!")
    print("Ensure a pickaxe/axe is attached as a peripheral, saplings in slot " .. SAPLING_SLOT .. ", and fuel in slot " .. FUEL_SLOT .. ".")
    print("Place a chest directly behind the turtle for surplus items.")
    
    -- Initial setup: No need to select slot 1 if the pickaxe is a peripheral.

    -- The main farming cycle runs indefinitely.
    while true do
        refuel()       -- Check and refuel the turtle.
        depositItems() -- Deposit any collected items into the chest.
        plantFarm()    -- Plant new saplings in the farm area.
        waitForGrowth()-- Wait for the newly planted trees to grow.
        harvestFarm()  -- Harvest the grown trees.
        
        print("Cycle complete. Starting next cycle in 10 seconds.")
        os.sleep(10) -- A short break before the next farming cycle begins.
    end
end

-- Run the main program
main()
