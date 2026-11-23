-- Kingdom Rush Origins - Xbox app / Microsoft Store (GDK Windows) speed control.
--
-- Press R to cycle: 1x -> 2x -> 3x -> 5x -> 1x ...
--
-- Save-folder-only mod: it loads through the game's built-in custom_script hook.
-- No EXE, DLL, asset or game script is modified.
--
-- Speed source: game.DBG_TIME_MULT, the engine's own time-warp field (the same
-- one the game's debug "z/Z: time warp" key uses). The mod re-applies it every
-- frame while a level is running, and clears it at 1x.
--
-- Diagnostics: kro_speed.log records load, key events, speed changes, level
-- transitions and the average delta game.simulation:update receives. That delta
-- is the multiplier actually reaching the simulation.
--
-- Target: Kingdom Rush Origins 6.0.03, package IronhideS.A.KingdomRushOrigins
-- (Xbox / Microsoft Store GDK build, kr3-gdk.exe).

local MODULE = "kro_speed"
local VERSION = "3.0.0"

local RATES = { 1, 2, 3, 5 }

local M = {
    version = VERSION,
    rates = RATES,
    index = 1,            -- 1x
    rate = 1,
    r_down = false,
    level = nil,
    sim = nil,
    button = nil,
    button_parent = nil,
    hooked_storage = false,
    key_hooked = false,
    keys_logged = 0,
    sim_accum = 0,
    sim_count = 0,
}

local function log(message)
    local line = "[kro_speed] " .. tostring(message)
    pcall(print, line)
    local ok, dir = pcall(function()
        return love.filesystem.getSaveDirectory()
    end)
    if not ok or type(dir) ~= "string" then return end
    local file = io.open(dir .. "/kro_speed.log", "a")
    if not file then return end
    file:write(os.date("%Y-%m-%d %H:%M:%S "), line, "\n")
    file:close()
end

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        log("guarded error: " .. tostring(result))
        return nil
    end
    return result
end

---------------------------------------------------------------------------
-- Speed
---------------------------------------------------------------------------

function M:in_level()
    return game ~= nil
        and game.game_gui ~= nil
        and game.simulation ~= nil
        and game.store ~= nil
end

function M:label()
    return tostring(self.rate) .. "x"
end

function M:apply()
    if game == nil then return end
    if self.rate ~= 1 then
        game.DBG_TIME_MULT = self.rate
    else
        game.DBG_TIME_MULT = nil
    end
end

function M:set_index(index)
    self.index = ((index - 1) % #self.rates) + 1
    self.rate = self.rates[self.index]
    self:apply()
    self:update_button_text()
    log("speed " .. self:label())
end

function M:cycle()
    self:set_index(self.index + 1)
end

---------------------------------------------------------------------------
-- Settings loader preservation
--
-- The game drops unknown keys when it rewrites settings.lua, which would
-- remove custom_script and silently disable the mod. Wrap the low-level save
-- writer so the loader key survives every settings write.
---------------------------------------------------------------------------

function M:preserve_loader()
    if self.hooked_storage then return end
    local ok, sio = pcall(require, "storage_io_generic")
    if not ok or type(sio) ~= "table" or type(sio.write_file) ~= "function" then
        log("storage_io_generic unavailable; loader may not persist")
        return
    end
    local original = sio.write_file
    sio.write_file = function(self_sio, filename, data_table, ...)
        if filename == "settings.lua" and type(data_table) == "table" then
            data_table.custom_script = MODULE
        end
        return original(self_sio, filename, data_table, ...)
    end
    self.hooked_storage = true
    log("settings loader preservation installed")
end

---------------------------------------------------------------------------
-- Diagnostics: measure the delta the simulation actually receives
---------------------------------------------------------------------------

function M:instrument_simulation()
    if not self:in_level() then return end
    local sim = game.simulation
    if sim == nil or sim == self.sim then return end
    local original = sim.update
    if type(original) ~= "function" then return end

    self.sim = sim
    self.sim_accum = 0
    self.sim_count = 0

    sim.update = function(self_sim, dt, ...)
        if type(dt) == "number" then
            M.sim_accum = M.sim_accum + dt
            M.sim_count = M.sim_count + 1
            if M.sim_count >= 120 then
                log(string.format(
                    "simulation dt %.1f ms avg; speed %s",
                    M.sim_accum / M.sim_count * 1000,
                    M:label()
                ))
                M.sim_accum = 0
                M.sim_count = 0
            end
        end
        return original(self_sim, dt, ...)
    end
    log("simulation probe installed")
end

---------------------------------------------------------------------------
-- Key handling
--
-- The game only forwards key events to custom scripts during a level, and it
-- may replace love.keypressed after the mod loads, so the LÖVE event handler
-- itself is wrapped. Polling is the last-resort path.
---------------------------------------------------------------------------

function M:toggle_from_key()
    if self.r_down then return end
    self.r_down = true
    self:cycle()
end

function M:install_key_hook()
    if self.key_hooked or type(love) ~= "table" then return end

    local handlers = love.handlers
    if type(handlers) == "table" and type(handlers.keypressed) == "function" then
        local original_handler = handlers.keypressed
        handlers.keypressed = function(key, scancode, isrepeat)
            if type(key) == "string" then
                if M.keys_logged < 12 then
                    M.keys_logged = M.keys_logged + 1
                    log("key event: " .. key .. (isrepeat and " (repeat)" or ""))
                end
                if key:lower() == "r" and not isrepeat then
                    M:toggle_from_key()
                end
            end
            return original_handler(key, scancode, isrepeat)
        end
    end

    local original = love.keypressed
    love.keypressed = function(key, scancode, isrepeat)
        if type(key) == "string" and key:lower() == "r" and not isrepeat then
            M:toggle_from_key()
        end
        if original then
            return original(key, scancode, isrepeat)
        end
    end

    self.key_hooked = true
    log("key hooks installed")
end

function M:poll_keys()
    local ok, down = pcall(function()
        return love.keyboard.isDown("r")
    end)
    if not ok then return end
    if down and not self.r_down then
        self:cycle()
    end
    self.r_down = down
end

function M:keypressed(key, scancode, isrepeat)
    if type(key) ~= "string" then return false end
    if key:lower() ~= "r" or isrepeat then return false end
    self:toggle_from_key()
    return false
end

function M:keyreleased(key)
    if type(key) == "string" and key:lower() == "r" then
        self.r_down = false
    end
    return false
end

---------------------------------------------------------------------------
-- HUD badge
---------------------------------------------------------------------------

function M:create_button()
    if not self:in_level() then return end
    local gg = game.game_gui
    if not gg or not gg.hud_bottom or not gg.next_wave_button then return end
    if not GGOptionsButton or not GGOptionsButton.new then return end

    local parent = gg.hud_bottom.next_wave
    if not parent then return end
    if self.button and self.button_parent == parent and self.button.parent == parent then
        return
    end

    self:remove_button()

    local ok, button = pcall(function()
        return GGOptionsButton:new(self:label())
    end)
    if not ok or not button or not button.size then return end

    local ok2 = pcall(function()
        local V = require("klua.vector")
        local nwb = gg.next_wave_button
        button.anchor = V.v(math.floor(button.size.x / 2), button.size.y)
        button.pos = V.v(
            nwb.pos.x - nwb.size.x / 2 - button.size.x / 2 - 6,
            nwb.pos.y
        )
        button.on_click = function()
            M:cycle()
        end
        parent:add_child(button)
    end)
    if not ok2 then return end

    self.button = button
    self.button_parent = parent
    self:update_button_text()
end

function M:update_button_text()
    local button = self.button
    if not button then return end
    local text = self:label()
    safe_call(function()
        if button.label then button.label.text = text end
        button.text = text
    end)
end

function M:remove_button()
    if not self.button then return end
    safe_call(function()
        if self.button.parent then self.button:remove_from_parent() end
    end)
    self.button = nil
    self.button_parent = nil
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function M:init()
    self:preserve_loader()
    self:install_key_hook()
    self.index = 1
    self.rate = 1
    log("v" .. VERSION .. " loaded; R: 1x -> 2x -> 3x -> 5x")
end

function M:update(dt)
    self:poll_keys()

    if game == nil then return end

    if self:in_level() then
        if self.level ~= game.game_gui then
            self.level = game.game_gui
            self:remove_button()
            log("level entered; speed " .. self:label())
        end
        self:instrument_simulation()
        self:create_button()
        self:update_button_text()
    elseif self.level ~= nil then
        self.level = nil
        self:remove_button()
        log("level left; speed " .. self:label())
    end

    -- Keep the time warp authoritative; the game's own debug keys can reset it.
    self:apply()
end

function M:game_init()
    self:apply()
end

custom_script = M
return M
