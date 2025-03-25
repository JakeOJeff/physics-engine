local objects = {}
local spacetimePoints = {}
local pointSpacing = 20
local G = 800 -- Increased gravitational constant
local baseOpacity = 0
local spawnMass = 10
local spawnRadius = math.sqrt(spawnMass) * 2
local shiftFactor = 1
local atmosphereDensity = 0
local massText = "Mass: "..spawnMass
local displayVelocity = true
local spaceTimeCurvatureDisplay = false
local spaceTimeFactor = 0
local massTextTimer = 0
local draggedObject = nil
local draggedObjectPos = 0
local showPaths = true
local atmosphereTextTimer = 0
local pathHistory = {}
local colors = {
    {0.8,0.4,0.4}, {0.4,0.8,0.4}, 
    {0.4,0.4,0.8}, {0.8,0.8,0.4}
}

-- New variables for selection and merging
local selectedObjects = {}
local isSelecting = false
local selectionRect = {x1 = 0, y1 = 0, x2 = 0, y2 = 0}
local blackHoleMassThreshold = 1000 -- Mass threshold for black hole creation
local zoomFactor = 1 -- Initial zoom level (1 = 100%)
local zoomSpeed = 0.1 -- How fast zooming happens
local minZoom = 0.1 -- Minimum zoom level
local maxZoom = 5 -- Maximum zoom level
local cameraOffsetX, cameraOffsetY = 0, 0 -- Camera offset for panning

function love.load()
    love.window.setTitle("Orbital Physics Simulator")
    love.graphics.setBackgroundColor(0.1,0.1,0.1)
    generateSpacetimePoints()
end

function generateSpacetimePoints()
    local w,h = love.graphics.getDimensions()
    for x=0,w,pointSpacing do
        for y=0,h,pointSpacing do
            table.insert(spacetimePoints, {x=x,y=y,opacity=baseOpacity})
        end
    end
end

function love.resize(w, h)
    spacetimePoints = {}
    generateSpacetimePoints()
end

function love.update(dt)
    if love.keyboard.isDown("lshift", "rshift") then
        shiftFactor = 10
    else
        shiftFactor = 1
    end
    if atmosphereTextTimer > 0 then
        atmosphereTextTimer = atmosphereTextTimer - dt
    end
    massText = "Mass: "..spawnMass
    if massTextTimer > 0 then
        massTextTimer = massTextTimer - dt
    end

    for i=1,#objects do
        local obj1 = objects[i]
        for j=i+1,#objects do
            local obj2 = objects[j]
            local dx, dy = obj2.x - obj1.x, obj2.y - obj1.y
            local dist = math.sqrt(dx^2 + dy^2)
            local radius1 = obj1.radius
            local radius2 = obj2.radius
            
            if dist > radius1 + radius2 then
                local F = G * obj1.mass * obj2.mass / (dist^2 + 1)
                local relativistic_correction = G * obj1.mass * obj2.mass / (dist^3 + 1) * 0.1
                local angle = math.atan2(dy, dx)
                
                obj1.vx = obj1.vx + (F/obj1.mass)*math.cos(angle)*dt - (relativistic_correction/obj1.mass)*math.cos(angle)*dt
                obj1.vy = obj1.vy + (F/obj1.mass)*math.sin(angle)*dt - (relativistic_correction/obj1.mass)*math.sin(angle)*dt
                obj2.vx = obj2.vx - (F/obj2.mass)*math.cos(angle)*dt + (relativistic_correction/obj2.mass)*math.cos(angle)*dt
                obj2.vy = obj2.vy - (F/obj2.mass)*math.sin(angle)*dt + (relativistic_correction/obj2.mass)*math.sin(angle)*dt

                local massRatio = math.max(obj1.mass/obj2.mass, obj2.mass/obj1.mass)
                local smallerObj = obj1.mass < obj2.mass and obj1 or obj2
                local largerObj = obj1.mass < obj2.mass and obj2 or obj1

                local minOrbitDistance = math.sqrt(largerObj.mass) * 10
                if dist < minOrbitDistance then
                    local orbitVel = math.sqrt(G * largerObj.mass / dist)
                    local dxOrbit = largerObj.x - smallerObj.x
                    local dyOrbit = largerObj.y - smallerObj.y
                    local distOrbit = math.sqrt(dxOrbit^2 + dyOrbit^2)
                    if distOrbit == 0 then goto continue end

                    local radialUnitX = dxOrbit / distOrbit
                    local radialUnitY = dyOrbit / distOrbit
                    local tangentialUnitX = -dyOrbit / distOrbit
                    local tangentialUnitY = dxOrbit / distOrbit

                    local velRadial = smallerObj.vx * radialUnitX + smallerObj.vy * radialUnitY
                    local velTangential = smallerObj.vx * tangentialUnitX + smallerObj.vy * tangentialUnitY

                    velTangential = orbitVel

                    smallerObj.vx = velRadial * radialUnitX + velTangential * tangentialUnitX
                    smallerObj.vy = velRadial * radialUnitY + velTangential * tangentialUnitY
                end
                ::continue::
            else
                local nx, ny = dx/dist, dy/dist
                local p = 2*(obj1.vx*nx + obj1.vy*ny - obj2.vx*nx - obj2.vy*ny)
                        / (1/obj1.mass + 1/obj2.mass)
                
                obj1.vx = obj1.vx - p*nx/obj1.mass
                obj1.vy = obj1.vy - p*ny/obj1.mass
                obj2.vx = obj2.vx + p*nx/obj2.mass
                obj2.vy = obj2.vy + p*ny/obj2.mass
                
                local overlap = (radius1 + radius2) - dist
                obj1.x = obj1.x - nx*overlap*0.5
                obj1.y = obj1.y - ny*overlap*0.5
                obj2.x = obj2.x + nx*overlap*0.5
                obj2.y = obj2.y + ny*overlap*0.5
            end
        end

        if atmosphereDensity > 0 then
            obj1.vx = obj1.vx * (1 - atmosphereDensity*dt)
            obj1.vy = obj1.vy * (1 - atmosphereDensity*dt)
        end

        obj1.x = obj1.x + obj1.vx*dt
        obj1.y = obj1.y + obj1.vy*dt

        if showPaths then
            pathHistory[i] = pathHistory[i] or {}
            table.insert(pathHistory[i], {x=obj1.x, y=obj1.y})
            if #pathHistory[i] > 100 then table.remove(pathHistory[i],1) end
        end
    end

    for _,p in ipairs(spacetimePoints) do
        p.opacity = baseOpacity
        for _,obj in ipairs(objects) do
            local dx,dy = p.x-obj.x, p.y-obj.y
            p.opacity = p.opacity + obj.mass/2/(math.sqrt(dx^2+dy^2)+1)*0.1
        end
        p.opacity = math.min(p.opacity, 1)
    end

    if isSelecting then
        print("Selecting")
    end
end

function love.draw()
        -- Apply zoom and camera offset
        love.graphics.push()
        love.graphics.translate(love.graphics.getWidth() / 2, love.graphics.getHeight() / 2) -- Center the view
        love.graphics.scale(zoomFactor, zoomFactor) -- Apply zoom
        love.graphics.translate(-love.graphics.getWidth() / 2 + cameraOffsetX, -love.graphics.getHeight() / 2 + cameraOffsetY) -- Adjust for camera offset

        
    for _,p in ipairs(spacetimePoints) do
        love.graphics.setColor(1,1,1,p.opacity)
        love.graphics.points(p.x,p.y)
    end

    if spaceTimeCurvatureDisplay then
        local function distance(x1, y1, x2, y2)
            return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
        end
    
        local function areImmediateNeighbors(p1, p2, threshold)
            return distance(p1.x, p1.y, p2.x, p2.y) <= threshold
        end
    
        local neighborThreshold = 50
    
        for i = 1, #spacetimePoints do
            for j = i + 1, #spacetimePoints do
                local p1 = spacetimePoints[i]
                local p2 = spacetimePoints[j]
    
                if areImmediateNeighbors(p1, p2, neighborThreshold) and
                   math.floor(p1.opacity * 10) / 10 == p2.opacity - spaceTimeFactor and
                   p1.opacity > 0.1 then
                    love.graphics.setColor(1, 1, 1, 0.1)
                    love.graphics.line(p1.x, p1.y, p2.x, p2.y)
                end
            end
        end
        local function isEdgePoint(p)
            return p.x == minX or p.x == maxX or p.y == minY or p.y == maxY
        end
    
        local edgePoints = {}
        for i = 1, #spacetimePoints do
            local p = spacetimePoints[i]
            if isEdgePoint(p) then
                table.insert(edgePoints, p)
            end
        end
    
        if #edgePoints >= 2 then
            love.graphics.setColor(1, 1, 1, 0.1)
            for i = 1, #edgePoints do
                local p1 = edgePoints[i]
                local p2 = edgePoints[(i % #edgePoints) + 1]
                love.graphics.line(p1.x, p1.y, p2.x, p2.y)
            end
        end
    end

    if showPaths then
        for i,history in ipairs(pathHistory) do
            if #history >=2 then
                love.graphics.setColor(1,0.5,0.5,0.3)
                for j=2,#history do
                    love.graphics.line(history[j-1].x,history[j-1].y,history[j].x,history[j].y)
                end
            end
        end
    end

    for i,obj in ipairs(objects) do
        local color = colors[(i-1)%#colors+1]
        love.graphics.setColor(color)
        love.graphics.circle("fill", obj.x, obj.y, obj.radius)
        if displayVelocity then
        love.graphics.setColor(1,1,1)
        love.graphics.print(tostring(math.floor(math.abs(obj.vx))), obj.x, obj.y)
        love.graphics.print(tostring(math.floor(math.abs(obj.vy))), obj.x, obj.y+10)
        end
        
        if showPaths then
            love.graphics.setColor(0.7,0.7,0.7,0.4)
            love.graphics.line(obj.x,obj.y, obj.x+obj.vx*5, obj.y+obj.vy*5)
        end
    end

    if atmosphereTextTimer > 0 then
        love.graphics.setColor(1,1,1)
        love.graphics.print("Atmosphere density: "..atmosphereDensityText, 10, 10)
    end

    if massTextTimer > 0 then
        love.graphics.setColor(1,1,1)
        love.graphics.print(massText, 10, 30)
    end

    love.graphics.setColor(1,1,1)
    love.graphics.print("Objects :"..#objects, 10, 50)

    -- Draw selection rectangle
    if isSelecting then
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.rectangle("line", selectionRect.x1, selectionRect.y1, selectionRect.x2 - selectionRect.x1, selectionRect.y2 - selectionRect.y1)
    end

    -- Highlight selected objects
    for _, obj in ipairs(selectedObjects) do
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("line", obj.x, obj.y, math.sqrt(obj.mass)*2 + 5)
    end
    love.graphics.pop() -- Reset transformation

end

function love.mousepressed(x, y, button)
    -- Adjust mouse coordinates for zoom and camera offset
    local adjustedX = (x - love.graphics.getWidth() / 2) / zoomFactor + love.graphics.getWidth() / 2 - cameraOffsetX
    local adjustedY = (y - love.graphics.getHeight() / 2) / zoomFactor + love.graphics.getHeight() / 2 - cameraOffsetY

    if button == 1 then
        if love.keyboard.isDown("lctrl", "rctrl") then
            -- Start rectangle selection
            isSelecting = true
            selectionRect.x1 = adjustedX
            selectionRect.y1 = adjustedY
            selectionRect.x2 = adjustedX
            selectionRect.y2 = adjustedY
        else
            -- Single object selection
            for _, obj in ipairs(objects) do
                if math.sqrt((adjustedX - obj.x)^2 + (adjustedY - obj.y)^2) < math.sqrt(obj.mass) * 2 then
                    if love.keyboard.isDown("lshift", "rshift") then
                        -- Add to selection
                        table.insert(selectedObjects, obj)
                    else
                        -- Replace selection
                        selectedObjects = {obj}
                    end
                    break
                end
            end
        end
    elseif button == 3 then
        spawnAmount = 1
        if love.keyboard.isDown("q") then
            spawnAmount = 10
        end
        for i = 1, spawnAmount do
            local color = colors[(#objects % #colors) + 1]

            table.insert(objects, {
                x = adjustedX + 2 * i, y = adjustedY + 2 * i,
                vx = 0, vy = 0, -- Zero initial velocity
                mass = spawnMass,
                radius = math.sqrt(spawnMass) * 2,
                color = color
            })
        end
    elseif button == 2 then
        for _, obj in ipairs(objects) do
            if math.sqrt((adjustedX - obj.x)^2 + (adjustedY - obj.y)^2) < 20 then
                draggedObject = obj
                draggedObjectPos = _
                dragStartX, dragStartY = adjustedX, adjustedY
                break
            end
        end
    end
end

function love.mousemoved(x, y)
    -- Adjust mouse coordinates for zoom and camera offset
    local adjustedX = (x - love.graphics.getWidth() / 2) / zoomFactor + love.graphics.getWidth() / 2 - cameraOffsetX
    local adjustedY = (y - love.graphics.getHeight() / 2) / zoomFactor + love.graphics.getHeight() / 2 - cameraOffsetY

    if draggedObject then
        draggedObject.vx = (adjustedX - dragStartX) * 0.5
        draggedObject.vy = (adjustedY - dragStartY) * 0.5
    end

    if isSelecting then
        selectionRect.x2 = adjustedX
        selectionRect.y2 = adjustedY
    end
end
function love.mousereleased(x, y, button)
    if button == 1 and isSelecting then
        isSelecting = false
        -- Select objects within the rectangle
        selectedObjects = {}
        for _, obj in ipairs(objects) do
            if obj.x >= math.min(selectionRect.x1, selectionRect.x2) and
               obj.x <= math.max(selectionRect.x1, selectionRect.x2) and
               obj.y >= math.min(selectionRect.y1, selectionRect.y2) and
               obj.y <= math.max(selectionRect.y1, selectionRect.y2) then
                table.insert(selectedObjects, obj)
            end
        end
    end
    draggedObject = nil
end

function love.wheelmoved(x, y)
    if love.keyboard.isDown("lctrl", "rctrl") then
        atmosphereDensity = math.max(0, atmosphereDensity + y*1)
        atmosphereDensityText = string.format("%.1f", atmosphereDensity)
        atmosphereTextTimer = 6
        if love.mouse.isDown(2) then
            table.remove(objects, draggedObjectPos)
        end
    elseif love.keyboard.isDown("d") then
        spaceTimeFactor = math.max(0, spaceTimeFactor + y*0.1)
        print(spaceTimeFactor)
    elseif love.keyboard.isDown("e") then
        -- Zoom in/out with mouse wheel
        local newZoom = zoomFactor + y * zoomSpeed
        zoomFactor = math.max(minZoom, math.min(maxZoom, newZoom))
    else
        spawnMass = math.max(1, spawnMass + y*5 * shiftFactor)
        spawnRadius = math.sqrt(spawnMass)*2
        massTextTimer = 6
        massText = "Mass: "..spawnMass
    end
end

function love.keypressed(k)
    if k == "p" then
        showPaths = not showPaths
        if not showPaths then pathHistory = {} end
    elseif k == "r" then
        objects = {}
        pathHistory = {}
        selectedObjects = {}
    elseif k == "f" then
        displayVelocity = not displayVelocity
    elseif k == "s" then
        spaceTimeCurvatureDisplay = not spaceTimeCurvatureDisplay
    elseif k == "f11" then
        love.window.setFullscreen(not love.window.getFullscreen())
    elseif k == "m" then
        mergeSelectedObjects()
    end
end

function mergeSelectedObjects()
    if #selectedObjects < 2 then return end

    -- Calculate combined mass and average position/velocity
    local totalMass = 0
    local totalX, totalY = 0, 0
    local totalVx, totalVy = 0, 0

    for _, obj in ipairs(selectedObjects) do
        totalMass = totalMass + obj.mass
        totalX = totalX + obj.x
        totalY = totalY + obj.y
        totalVx = totalVx + obj.vx
        totalVy = totalVy + obj.vy
    end

    local newX = totalX / #selectedObjects
    local newY = totalY / #selectedObjects
    local newVx = totalVx / #selectedObjects
    local newVy = totalVy / #selectedObjects

    -- Remove selected objects
    for _, obj in ipairs(selectedObjects) do
        for i = #objects, 1, -1 do
            if objects[i] == obj then
                table.remove(objects, i)
                break
            end
        end
    end

    -- Create new object
    local newObj = {
        x = newX,
        y = newY,
        vx = newVx,
        vy = newVy,
        mass = totalMass,
        radius = math.sqrt(totalMass/10) * 2,
        color = {1, 1, 1} -- White color for merged objects
    }

    -- Check for black hole creation
    if totalMass >= blackHoleMassThreshold then
        newObj.isBlackHole = true
        newObj.color = {0, 0, 0} -- Black color for black holes
    end

    table.insert(objects, newObj)
    selectedObjects = {}
    
end