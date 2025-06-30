--[[
    Spruce Tree Farm Automation for CC: Tweaked Turtles

    This program automates the process of planting, growing, and harvesting
    spruce trees in a 2x2 grid pattern. Spruce trees grow as 2x2 blocks
    and benefit from a 1-block clear space around their base for faster growth.

    Features:
    - Plants 4 spruce trees in a 2x2 grid with optimal spacing.
    - Waits for trees to grow.
    - Intelligently harvests trees by moving up and digging.
    - Replants saplings after harvesting.
    - Deposits surplus logs and saplings into a chest placed directly behind
      the turtle's starting position.
    - Automatically refuels the turtle when necessary from a designated slot.
    - Includes basic stuck detection and recovery by attempting to dig obstacles.

    Setup:
    1. Place your turtle facing forward (e.g., North).
    2. Place a chest directly behind the turtle.
    3. Ensure the turtle has:
        - An axe/pickaxe attached as a peripheral (e.g., on the side).
        - Spruce saplings in SAPLING_SLOT (default: slot 2).
        - Fuel (coal, charcoal, etc.) in FUEL_SLOT (default: slot 3).
    4. The area in front of the turtle needs to be clear for a 6x6 farm grid.
       The turtle will manage its own movement within this grid.
]]--

-- Constants
local SAPLING_SLOT = 2 -- The inventory slot where spruce saplings are kept.
local FUEL_SLOT = 3    -- The inventory slot where fuel (e.g., coal, charcoal) is kept.
local CHEST_SLOT = 16  -- A temporary slot used for managing inventory when dropping items.
                       -- This should ideally be an empty slot or one not critical for operations.

-- Configuration for the farm layout
-- This table defines the relative (x, z) coordinates for the top-left corner
-- of each 2x2 sapling planting area.
-- The turtle starts at (0,0) of the farm grid, facing "north" (negative Z).
-- Each tree plot (including its 1-block border for optimal growth) is 3x3 blocks.
-- This layout creates a 2x2 grid of spruce trees with 1-block spacing between their
-- 3x3 growth areas, resulting in a total farm area of 6x6 blocks.
local TREE_PLOTS = {
    {x = 0, z = 0}, -- Tree 1: Top-left tree
    {x = 0, z = 3}, -- Tree 2: Top-right tree (3 blocks along Z from Tree 1's origin)
    {x = 3, z = 0}, -- Tree 3: Bottom-left tree (3 blocks along X from Tree 1's origin)
    {x = 3, z = 3}  -- Tree 4: Bottom-right tree (3 blocks along X and Z from Tree 1's origin)
}

-- Global state for turtle's current relative position and direction
-- These variables track the turtle's position relative to its starting point (0,0,0)
-- and its current facing direction. "north" corresponds to its initial forward direction.
local currentX = 0
local currentY = 0
local currentZ = 0
local currentDir = "north" -- "north", "east", "south", "west"

-- Helper function to update the turtle's internal position tracking
-- This is crucial for the `moveToRelative` function to work correctly.
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

-- Function to safely attempt a turtle movement, handling obstacles by digging.
-- `moveFunc`: The turtle movement function (e.g., `turtle.forward`).
-- `digFunc`: The corresponding digging function (e.g., `turtle.dig`, `turtle.digUp`).
-- Returns true if the move was successful, false otherwise (though it will error out on persistent blockages).
local function attemptMove(moveFunc, digFunc)
    -- Ensure the turtle object and the move function exist
    if not turtle or type(moveFunc) ~= "function" then
        error("Turtle object or move function is missing/corrupted during attemptMove.")
    end

    local success, reason = moveFunc()
    if not success then
        print("Blocked: " .. (reason or "Unknown reason") .. ". Attempting to dig.")
        if digFunc then
            -- Ensure the dig function exists
            if type(digFunc) ~= "function" then
                error("Dig function is missing/corrupted during attemptMove.")
            end
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

-- Wrapper functions for turtle movements that update internal position and handle stuck situations.
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
    local success = attemptMove(turtle.turnLeft) -- No digging for turning
    updatePosition("turnLeft", success)
    return success
end

local function safeTurnRight()
    local success = attemptMove(turtle.turnRight) -- No digging for turning
    updatePosition("turnRight", success)
    return success
end

-- Refuels the turtle if its fuel level falls below a certain threshold.
-- Checks the designated FUEL_SLOT for fuel items.
local function refuel()
    -- Explicit checks for turtle fuel functions
    if not turtle or type(turtle.getFuelLevel) ~= "function" or type(turtle.getFuelLimit) ~= "function" then
        error("Turtle fuel functions (getFuelLevel/getFuelLimit) are missing/corrupted.")
    end

    -- Refuel when fuel is below 20% of its limit.
    if turtle.getFuelLevel() < turtle.getFuelLimit() * 0.2 then
        print("Fuel low. Attempting to refuel.")
        
        -- Explicit checks for turtle inventory/selection functions
        if not turtle or type(turtle.getSelectedSlot) ~= "function" or type(turtle.select) ~= "function" or type(turtle.refuel) ~= "function" then
            error("Turtle inventory/refuel functions are missing/corrupted.")
        end

        local currentSlot = turtle.getSelectedSlot() -- Save current selected slot
        turtle.select(FUEL_SLOT) -- Select the fuel slot
        local success = turtle.refuel() -- Attempt to refuel
        turtle.select(currentSlot) -- Restore original selected slot
        if success then
            print("Refueled successfully. Current fuel: " .. turtle.getFuelLevel())
        else
            print("Failed to refuel. Check for fuel items in slot " .. FUEL_SLOT .. ".")
            error("Failed to refuel. Program halted.")
        end
    end
end

-- Deposits all items from the turtle's inventory (except saplings and fuel) into a chest.
-- Assumes the chest is directly behind the turtle's starting position.
local function depositItems()
    print("Depositing surplus items into chest.")
    -- Save the turtle's current position and direction to return to it later.
    local originalX, originalY, originalZ, originalDir = currentX, currentY, currentZ, currentDir
    
    -- Turn 180 degrees to face the chest. The turtle remains on its original block.
    safeTurnLeft()
    safeTurnLeft()

    -- Iterate through all inventory slots.
    for i = 1, 16 do
        -- Do NOT drop saplings or fuel, they are needed for operations.
        if i ~= SAPLING_SLOT and i ~= FUEL_SLOT then
            -- Explicit checks for turtle inventory functions
            if not turtle or type(turtle.select) ~= "function" or type(turtle.getItemDetail) ~= "function" or type(turtle.drop) ~= "function" then
                error("Turtle inventory functions (select/getItemDetail/drop) are missing/corrupted during deposit.")
            end
            turtle.select(i)
            local item = turtle.getItemDetail()
            if item then
                print("Dropping " .. item.count .. " " .. item.name .. " from slot " .. i .. ".")
                -- Drop items forward, which is now into the chest behind the turtle's original position.
                turtle.drop() 
            end
        end
    end
    
    -- Turn back to the original orientation.
    safeTurnLeft()
    safeTurnLeft()
    
    -- Reset internal position tracking to reflect the actual movement (no change in position).
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
}

-- Plants a 2x2 square of spruce saplings at the turtle's current location.
-- Assumes the turtle is at the top-left corner of the 2x2 planting area, facing north.
local function plant2x2Tree()
    print("Attempting to plant 2x2 spruce saplings.")
    -- Save current position and direction to ensure the turtle returns to its exact spot.
    local originalX, originalY, originalZ, originalDir = currentX, currentY, currentZ, currentDir

    -- Explicit checks for turtle inventory/placement functions
    if not turtle or type(turtle.select) ~= "function" or type(turtle.getItemCount) ~= "function" or type(turtle.placeDown) ~= "function" then
        error("Turtle inventory/placement functions are missing/corrupted during planting.")
    end

    turtle.select(SAPLING_SLOT) -- Select the sapling slot
    
    -- Robust check for getItemCount return value
    local saplingCount = turtle.getItemCount(SAPLING_SLOT)
    if type(saplingCount) ~= "number" then
        print("Error: turtle.getItemCount did not return a number for slot " .. SAPLING_SLOT .. ". Got: " .. tostring(saplingCount))
        error("Unexpected return from getItemCount. Program halted.")
    end

    -- Check if enough saplings are available.
    if saplingCount < 4 then -- LINE 239
        print("Not enough saplings to plant a 2x2 tree. Need 4, have " .. saplingCount .. ".")
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
end

-- Waits for trees to grow.
-- Spruce trees can take a while to grow, so a longer sleep duration is used.
local function waitForGrowth()
    print("Waiting for trees to grow (5 minutes).")
    os.sleep(300) -- Wait for 300 seconds (5 real-world minutes).
    print("Finished waiting.")
end

-- Harvests a single 2x2 spruce tree at the turtle's current location.
-- Assumes the turtle is at the top-left corner of the 2x2 sapling area, facing north.
local function harvest2x2Tree()
    print("Harvesting 2x2 spruce tree.")
    -- Save current position and direction to return to it after harvesting.
    local originalX, originalY, originalZ, originalDir = currentX, currentY, currentZ, currentDir

    -- Explicit checks for turtle digging/sucking functions
    if not turtle or type(turtle.dig) ~= "function" or type(turtle.digUp) ~= "function" or type(turtle.digDown) ~= "function" or type(turtle.suck) ~= "function" or type(turtle.suckUp) ~= "function" or type(turtle.suckDown) ~= "function" then
        error("Turtle digging/sucking functions are missing/corrupted during harvest.")
    end

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
end

-- Main program loop
local function main()
    -- Crucial initial check for the 'turtle' global object
    assert(turtle, "Error: The 'turtle' global object is missing or corrupted! Ensure you are running this script on a ComputerCraft Turtle.")

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
