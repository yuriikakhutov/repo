-- Простая демо-сцена на Love2D, в которой главный герой перемещается по клику мыши,
-- как в MOBA-играх вроде Dota 2. Всё управление и логика сосредоточены в этом файле.

local hero = {
    x = 400,
    y = 300,
    speed = 260,
    size = 32,
    color = { r = 0.2, g = 0.6, b = 1.0 }
}

local target = {
    x = hero.x,
    y = hero.y
}

local clickDistance = 180 -- дистанция условного "клика" от клавиатурной команды

local function clampToWindow(x, y)
    local screenWidth, screenHeight = love.graphics.getDimensions()
    local minX = hero.size / 2
    local maxX = screenWidth - hero.size / 2
    local minY = hero.size / 2
    local maxY = screenHeight - hero.size / 2

    return math.max(minX, math.min(maxX, x)), math.max(minY, math.min(maxY, y))
end

local function setTarget(x, y)
    target.x, target.y = clampToWindow(x, y)
end

function love.load()
    love.window.setTitle("Mouse Click Hero Movement Demo")
end

local function handleMovement(dt)
    local dx = target.x - hero.x
    local dy = target.y - hero.y
    local distance = math.sqrt(dx * dx + dy * dy)

    if distance < 1 then
        hero.x = target.x
        hero.y = target.y
        return
    end

    local directionX = dx / distance
    local directionY = dy / distance

    local step = hero.speed * dt
    if step > distance then
        step = distance
    end

    hero.x = hero.x + directionX * step
    hero.y = hero.y + directionY * step

    hero.x, hero.y = clampToWindow(hero.x, hero.y)

    if math.abs(hero.x - target.x) < 1 and math.abs(hero.y - target.y) < 1 then
        hero.x = target.x
        hero.y = target.y
    end
end

function love.update(dt)
    handleMovement(dt)
end

function love.mousepressed(x, y, button)
    if button == 2 then -- правая кнопка мыши, как в Dota 2
        setTarget(x, y)
    end
end

function love.keypressed(key)
    local direction = nil

    if key == "w" then
        direction = { x = 0, y = -1 }
    elseif key == "s" then
        direction = { x = 0, y = 1 }
    elseif key == "a" then
        direction = { x = -1, y = 0 }
    elseif key == "d" then
        direction = { x = 1, y = 0 }
    end

    if not direction then
        return
    end

    local horizontal = 0
    if love.keyboard.isDown("a") then
        horizontal = horizontal - 1
    end
    if love.keyboard.isDown("d") then
        horizontal = horizontal + 1
    end

    local vertical = 0
    if love.keyboard.isDown("w") then
        vertical = vertical - 1
    end
    if love.keyboard.isDown("s") then
        vertical = vertical + 1
    end

    if horizontal == 0 and vertical == 0 then
        horizontal = direction.x
        vertical = direction.y
    end

    local length = math.sqrt(horizontal * horizontal + vertical * vertical)
    if length == 0 then
        return
    end

    local normX = horizontal / length
    local normY = vertical / length

    local newX = hero.x + normX * clickDistance
    local newY = hero.y + normY * clickDistance

    setTarget(newX, newY)
end

function love.draw()
    love.graphics.setColor(hero.color.r, hero.color.g, hero.color.b)
    love.graphics.rectangle("fill", hero.x - hero.size / 2, hero.y - hero.size / 2, hero.size, hero.size)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("ПКМ или WASD (клик-имитация) — отправьте героя в точку", 16, 16)

    love.graphics.setColor(0.8, 0.2, 0.2, 0.5)
    love.graphics.circle("fill", target.x, target.y, 6)
    love.graphics.setColor(1, 1, 1)
end
