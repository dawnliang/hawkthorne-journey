local anim8 = require 'vendor/anim8'
local game = require 'game'
local utils = require 'utils'
local Timer = require 'vendor/timer'
local window = require 'window'
local Player = require 'player'

local Projectile = {}
Projectile.__index = Projectile
Projectile.isProjectile = true

--node requires:
-- an x and y coordinate,
-- a width and height, 
-- properties.sheet
-- properties.defaultAnimation
function Projectile.new(node, collider)
    local proj = {}
    setmetatable(proj, Projectile)

    local name = node.name
    
    proj.type = 'projectile'
    proj.name = name
    proj.props = require( 'nodes/projectiles/' .. name )

    local dir = node.directory or ""
    proj.sheet = love.graphics.newImage('images/'..dir..name..'.png')
    proj.foreground = proj.props.foreground

    proj.collider = collider
    proj.bb = collider:addRectangle(node.x, node.y, node.width , node.height )
    proj.bb.node = proj
    proj.stayOnScreen = proj.props.stayOnScreen
    proj.start_x = node.x

    local animations = proj.props.animations
    local g = anim8.newGrid( proj.props.frameWidth,
                             proj.props.frameHeight,
                             proj.sheet:getWidth(),
                             proj.sheet:getHeight() )

    proj.defaultAnimation = anim8.newAnimation(
                animations.default[1],
                g(unpack(animations.default[2])),
                animations.default[3])
    proj.thrownAnimation = anim8.newAnimation(
                animations.thrown[1],
                g(unpack(animations.thrown[2])),
                animations.thrown[3])
    proj.finishAnimation = anim8.newAnimation(
                animations.finish[1],
                g(unpack(animations.finish[2])),
                animations.finish[3])
    proj.animation = proj.defaultAnimation
    proj.position = { x = node.x, y = node.y }
    proj.velocity = { x = proj.props.velocity.x, 
                      y = proj.props.velocity.y}
    proj.bounceFactor = proj.props.bounceFactor or 0
    proj.friction = proj.props.friction or 0.7
    proj.velocityMax = proj.props.velocityMax or 400
    proj.throwVelocity = {x = proj.props.throwVelocityX or 500,
                          y = proj.props.throwVelocityY or -800,}
    proj.dropVelocity = {x = proj.props.dropVelocityX or 50}
    proj.horizontalLimit = proj.props.horizontalLimit or 2000

    proj.thrown = proj.props.thrown
    proj.holder = nil
    proj.lift = proj.props.lift or 0
    proj.width = proj.props.width
    proj.height = proj.props.height
    proj.complete = false --updated by finish()
    proj.damage = proj.props.damage or 0

    proj.playerCanPickUp = proj.props.playerCanPickUp
    proj.enemyCanPickUp = proj.props.enemyCanPickUp
    return proj
end

function Projectile:destroy()
    self.dead = true
    self.complete = true
    self.holder = nil
    self.collider:remove(self.bb)
end    

function Projectile:draw()
    if self.dead then return end
    local scalex = 1
    if self.velocity.x < 0 then
        scalex = -1
    end
    self.animation:draw(self.sheet, math.floor(self.position.x), self.position.y, 0, scalex, 1)
end

function Projectile:update(dt)
    if self.dead then return end
    if math.abs(self.start_x - self.position.x) > self.horizontalLimit then
        self.dead = true
        if self.holder then self.holder:throw() end
        self.holder = nil
        self.collider:remove(self.bb)
    end
    if self.holder and self.holder.currently_held == self then
        local holder = self.holder
        self.position.x = math.floor(holder.position.x) + holder.offset_hand_right[1] + (self.width / 2) + 15
        self.position.y = math.floor(holder.position.y) + holder.offset_hand_right[2] - self.height + 2
        if holder.offset_hand_right[1] == 0 then
            print(string.format("Need hand offset for %dx%d", holder.frame[1], holder.frame[2]))
        end
        self:moveBoundingBox()
    end

    if self.thrown then
    
        --update speed
        if self.velocity.x < 0 then
            self.velocity.x = math.min(self.velocity.x + self.friction * dt, 0)
        else
            self.velocity.x = math.max(self.velocity.x - self.friction * dt, 0)
        end
        self.velocity.y = self.velocity.y + (game.gravity-self.lift)*dt

        if self.velocity.y > self.velocityMax then
            self.velocity.y = self.velocityMax
        end
        self.velocity.x = Projectile.clip(self.velocity.x,self.velocityMax)

        --update position
        self.position.x = self.position.x + self.velocity.x * dt
        self.position.y = self.position.y + self.velocity.y * dt
        
        if self.stayOnScreen then
            if self.position.x < 0 then
                self.position.x = 0
                self.rebounded = false
                self.velocity.x = -self.velocity.x
            end

            if self.position.x + self.width > window.width then
                self.position.x = window.width - self.width
                self.rebounded = false
                self.velocity.x = -self.velocity.x
            end
        end
    end

    self.animation:update(dt)

    self:moveBoundingBox()
end

function Projectile.clip(value,bound)
    bound = math.abs(bound)
    if value > bound then
        return bound
    elseif value < -bound then
        return -bound
    else
        return value
    end
end

function Projectile:moveBoundingBox()
    self.bb:moveTo(self.position.x + self.width / 2,
                   self.position.y + self.height / 2 )
end

function Projectile:collide(node, dt, mtv_x, mtv_y)
    if not node then return end

    if (node.isPlayer and self.playerCanPickUp and not self.currently_held) or
       (node.isEnemy and self.enemyCanPickUp and not self.currently_held) then
        node:registerHoldable(self)
    end
    if self.props.collide then
        self.props.collide(node, dt, mtv_x, mtv_y,self)
    end
end

function Projectile:collide_end(node, dt)
    if not node then return end
    
    if (node.isEnemy and self.enemyCanPickUp) then 
        node:cancelHoldable(self)
    end
    if (node.isPlayer and self.playerCanPickUp) then
        node:cancelHoldable(self)
    end
    if self.props.collide_end then
        self.props.collide_end(node, dt, self)
    end
end

function Projectile:pickup(node)
    if node.isPlayer and not self.playerCanPickUp  then return end
    if node.isEnemy and not self.enemyCanPickUp  then return end

    self.animation = self.defaultAnimation

    self.holder = node
    self.thrown = false
    self.velocity.y = 0
    self.velocity.x = 0
end

function Projectile:floor_pushback(node, new_y)
    if not self.thrown then return end
    if self.bounceFactor < 0 then
        self.velocity.y = -self.velocity.y * self.bounceFactor
        self.velocity.x = self.velocity.x * self.friction
    elseif self.velocity.y<25 then
        self.velocity.y = 0
        self.position.y = new_y
        self.thrown = false
        self:finish()
    else
        self.position.y = new_y
        self.velocity.y = -self.velocity.y * self.bounceFactor
        self.velocity.x = self.velocity.x * self.friction
    end
end

function Projectile:wall_pushback(node, new_x)
    self.velocity.y = self.velocity.y * self.friction
    self.velocity.x = -self.velocity.x * self.bounceFactor
end

--used only for objects when hitting cornelius
function Projectile:rebound( x_change, y_change )
    if not self.rebounded then
        if x_change then
            self.velocity.x = -( self.velocity.x / 2 )
        end
        if y_change then
            self.velocity.y = -self.velocity.y
        end
        self.rebounded = true
    end
end
function Projectile:throw(thrower)
    self.animation = self.thrownAnimation

    thrower.currently_held = nil
    self.holder = nil
    self.thrown = true
    local direction = thrower.direction or thrower.character.direction
    if direction == "left" then
        self.velocity.x = -self.throwVelocity.x + thrower.velocity.x
    else
        self.velocity.x = self.throwVelocity.x + thrower.velocity.x
    end
    self.velocity.y = self.throwVelocity.y
end

function Projectile:throw_vertical(thrower)
    self.holder = nil
    self.thrown = true
    self.velocity.x = thrower.velocity.x
    self.velocity.y = self.throwVelocity.y
end

--launch() executes the following in order(if they exist)
--1) charge()
--2) throw()
--3) finish()
function Projectile:launch(thrower)
    self:charge(thrower)
    Timer.add(self.chargeTime or 0, function()
        self:throw(thrower)
    end)
end

function Projectile:charge(thrower)
    self.animation = self.defaultAnimation
    if self.props.charge then
        self.props.charge(thrower,self)
    end
end

function Projectile:finish(thrower)
    self.complete = true
    self.animation = self.finishAnimation
    if self.props.finish then
        self.props.finish(thrower,self)
    end
end

function Projectile:drop(thrower)
    self.holder = nil
    self.thrown = true
    self.velocity.x = ( ( ( thrower.character.direction == "left" ) and -1 or 1 ) * thrower.velocity.x)
    self.velocity.y = 0
end

return Projectile

