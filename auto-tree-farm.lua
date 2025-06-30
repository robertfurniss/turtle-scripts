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
        - Fuel (coal, charcoal, etc.) in FUEL_SLOT (default: slot 1).
        - Spruce saplings in SAPLING_SLOT (default: slot 2).
        - DIRT/GRASS BLOCKS in DIRT_SLOT (default: slot 4) for replanting ground.
    4. The area in front of the turtle needs to be clear for a 6x6 farm grid.
       The turtle will manage its own movement within this grid.
]]--

-- Constants
local FUEL_SLOT = 1    -- The inventory slot where fuel (e.g., coal, charcoal) is kept.
local SAPLING_SLOT = 2 -- The inventory slot where spruce saplings are kept.
local DIRT_SLOT = 4    -- The inventory slot where dirt/grass blocks are kept for replanting ground.
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

-- Consolidates any fuel items found in other inventory slots into the designated FUEL_SLOT.
local function consolidateFuel()
    print("Consolidating fuel items.")
    local originalSlot = turtle.getSelectedSlot() -- Save current selected slot

    for i = 1, 16 do
        if i ~= FUEL_SLOT then -- Only check slots that are not the primary fuel slot
            turtle.select(i)
            local item = turtle.getItemDetail()
            if item then
                -- Check if the item is a fuel source. A simple way is to try to refuel 0 units.
                -- This will return true if it's fuel, false otherwise, without consuming it.
                local isFuel = turtle.refuel(0)
                if isFuel then
                    print("Found fuel (" .. item.name .. ") in slot " .. i .. ". Transferring to slot " .. FUEL_SLOT .. ".")
                    turtle.transferTo(FUEL_SLOT)
                end
            end
        end
    end
    turtle.select(originalSlot) -- Restore original selected slot
    print("Finished consolidating fuel.")
end

-- Deposits all items from the turtle's inventory (except saplings, fuel, and dirt) into a chest.
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
        -- Do NOT drop saplings, fuel, or dirt, they are needed for operations.
        if i ~= SAPLING_SLOT and i ~= FUEL_SLOT and i ~= DIRT_SLOT then
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
end

-- Plants a 2x2 square of spruce saplings at the turtle's current location.
-- Assumes the turtle is at the top-left corner of the 2x2 planting area, facing north.
local function plant2x2Tree()
    print("Attempting to plant 2x2 spruce saplings.")
    -- Save current position and direction to ensure the turtle returns to its exact spot.
    local originalX, originalY, originalZ, originalDir = currentX, currentY, currentZ, currentDir

    -- Explicit checks for turtle inventory/placement functions
    if not turtle or type(turtle.select) ~= "function" or type(turtle.getItemCount) ~= "function" or type(turtle.placeDown) ~= "function" or type(turtle.placeUp) ~= "function" then
        error("Turtle inventory/placement functions are missing/corrupted during planting.")
    end

    -- Check if enough saplings and dirt are available.
    local saplingCount = turtle.getItemCount(SAPLING_SLOT)
    local dirtCount = turtle.getItemCount(DIRT_SLOT)

    if type(saplingCount) ~= "number" then
        print("Error: turtle.getItemCount did not return a number for sapling slot " .. SAPLING_SLOT .. ". Got: " .. tostring(saplingCount))
        error("Unexpected return from getItemCount for saplings. Program halted.")
    end
    if type(dirtCount) ~= "number" then
        print("Error: turtle.getItemCount did not return a number for dirt slot " .. DIRT_SLOT .. ". Got: " .. tostring(dirtCount))
        error("Unexpected return from getItemCount for dirt. Program halted.")
    end

    if saplingCount < 4 then
        print("Not enough saplings to plant a 2x2 tree. Need 4, have " .. saplingCount .. ".")
        error("Insufficient saplings. Program halted.")
    end
    if dirtCount < 4 then
        print("Not enough dirt/ground blocks to plant a 2x2 tree. Need 4, have " .. dirtCount .. ".")
        error("Insufficient dirt/ground blocks. Program halted.")
    end

    -- Define the 4 relative positions for planting within the 2x2 plot
    local plantPositions = {
        {x = 0, z = 0},
        {x = 0, z = 1},
        {x = 1, z = 0},
        {x = 1, z = 1}
    }

    -- Iterate through each planting position
    for _, pos in ipairs(plantPositions) do
        -- Calculate absolute target position for this plant
        local targetPlotX = originalX + pos.x
        local targetPlotZ = originalZ + pos.z
        
        -- Move to the exact position for this plant (ground level, Y=0, which is currently a hole)
        moveToRelative(targetPlotX, originalY, targetPlotZ)

        local currentSelected = turtle.getSelectedSlot() -- Save current selected slot
        
        -- Step 1: Place dirt to fill the hole at Y=0
        safeUp() -- Move turtle to Y=1 (one block above the hole)
        turtle.select(DIRT_SLOT)
        local dirtSuccess, dirtReason = turtle.placeDown() -- Places dirt at Y=0 (into the hole)
        if not dirtSuccess then
            print("Warning: Failed to place dirt at (" .. targetPlotX .. "," .. originalY .. "," .. targetPlotZ .. "): " .. (dirtReason or "Unknown"))
            error("Failed to place ground block. Program halted.")
        end
        safeDown() -- Move turtle back to Y=0, now standing on the newly placed dirt

        -- Step 2: Place sapling on top of the dirt (at Y=1)
        turtle.select(SAPLING_SLOT)
        local saplingSuccess, saplingReason = turtle.placeUp() -- Places sapling at Y=1 (on top of the dirt)
        if not saplingSuccess then
            print("Warning: Failed to plant sapling at (" .. targetPlotX .. "," .. (originalY+1) .. "," .. targetPlotZ .. "): " .. (saplingReason or "Unknown"))
            error("Failed to plant sapling. Program halted.")
        end
        turtle.select(currentSelected) -- Restore original selected slot
    end

    -- Return to the original starting position of this 2x2 plot after planting all saplings.
    moveToRelative(originalX, originalY, originalZ)
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

    -- Define the 4 relative positions for digging within the 2x2 plot
    local digPositions = {
        {x = 0, z = 0},
        {x = 0, z = 1},
        {x = 1, z = 0},
        {x = 1, z = 1}
    }

    -- Dig the 4 base logs of the 2x2 tree by moving to each position and digging down
    for _, pos in ipairs(digPositions) do
        local targetPlotX = originalX + pos.x
        local targetPlotZ = originalZ + pos.z
        
        moveToRelative(targetPlotX, originalY, targetPlotZ) -- Turtle is at ground level (Y=0, on the tree base)
        
        safeUp() -- Move up to Y=1
        local success, reason = turtle.digDown() -- Digs the block at Y=0 (the tree base)
        if not success then print("Warning: Failed to dig down tree base at (" .. targetPlotX .. "," .. originalY .. "," .. targetPlotZ .. "): " .. (reason or "Unknown")) end
        safeDown() -- Move back down to Y=0
    end

    -- Return to the original starting position of this 2x2 plot after digging base logs.
    moveToRelative(originalX, originalY, originalZ)

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
    print("Finished harvesting 2x2 tree.")
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
    print("Also, ensure you have DIRT/GRASS BLOCKS in slot " .. DIRT_SLOT .. " for replanting the ground.")
    
    -- Initial setup: No need to select slot 1 if the pickaxe is a peripheral.

    -- The main farming cycle runs indefinitely.
    while true do
        refuel()       -- Check and refuel the turtle.
        consolidateFuel() -- Consolidate all fuel into the FUEL_SLOT
        depositItems() -- Deposit any collected items into the chest (excluding saplings, fuel, and dirt).
        plantFarm()    -- Plant new saplings in the farm area.
        waitForGrowth()-- Wait for the newly planted trees to grow.
        harvestFarm()  -- Harvest the grown trees.
        
        print("Cycle complete. Starting next cycle in 10 seconds.")
        os.sleep(10) -- A short break before the next farming cycle begins.
    end
end

-- Run the main program
main()
