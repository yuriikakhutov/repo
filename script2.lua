-- Простая демо-сцена на Love2D, в которой главный герой может двигаться
-- с помощью клавиш WASD. Всё управление и логика сосредоточены в этом файле.

local hero = {
    x = 400,
    y = 300,
    speed = 220,
    size = 32,
    color = { r = 0.2, g = 0.6, b = 1.0 }
}

function love.load()
    love.window.setTitle("WASD Hero Movement Demo")
end

local function handleMovement(dt)
    local dx, dy = 0, 0

    if love.keyboard.isDown("a") then
        dx = dx - 1
    end
    if love.keyboard.isDown("d") then
        dx = dx + 1
    end
    if love.keyboard.isDown("w") then
        dy = dy - 1
    end
    if love.keyboard.isDown("s") then
        dy = dy + 1
    end

    if dx ~= 0 or dy ~= 0 then
        local length = math.sqrt(dx * dx + dy * dy)
        dx, dy = dx / length, dy / length
    end

    hero.x = hero.x + dx * hero.speed * dt
    hero.y = hero.y + dy * hero.speed * dt

    local screenWidth, screenHeight = love.graphics.getDimensions()
    hero.x = math.max(hero.size / 2, math.min(screenWidth - hero.size / 2, hero.x))
    hero.y = math.max(hero.size / 2, math.min(screenHeight - hero.size / 2, hero.y))
end

function love.update(dt)
    handleMovement(dt)
end

function love.draw()
    love.graphics.setColor(hero.color.r, hero.color.g, hero.color.b)
    love.graphics.rectangle("fill", hero.x - hero.size / 2, hero.y - hero.size / 2, hero.size, hero.size)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Двигайтесь при помощи клавиш W, A, S и D", 16, 16)
end
