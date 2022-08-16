--[[
    Copyright (C) 2022 - Grabthar <https://github.com/grabthar>

    This program is free software you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
]]
----------------------------------------------------
--------------------- Handler ----------------------
----------------------------------------------------
-- available on client and server
-- possible improvement, event signature registering (arguments type/name)
-- pros can prevent bad use of EventHandler:ExecEvent() with bad args
-- cons can result in slower code
-- cons can prevent dynamic event type (event with changing signature)
--      e.g: you create a OnDestroy event wich is triggered once you destroy an object or creature 
--      the event can return the max life property of the creature, but object doesn't have a maxlife prop
--      So the call is sometime EventHandler:ExecEvent(OnDestroy, MaxLife), EventHandler:ExecEvent(OnDestroy)
-- Other improvement, bound event priorities... (Queues)



--[[ todo EventHandler
    List all Wow event in WoWEvents
    List all Eluna event in ElunaEvents
    Eluna event handling
    Documentation
--]]

local AIO = AIO or require("AIO")

-- Step to reference a file
local AddonName, Namespace = ...
local EventHandler = {}
if not AIO.IsServer() then
    if AIO.GetVersion() <= 1.74 then
        _G.AIONamespace = _G.AIONamespace or {}
        Namespace = _G.AIONamespace
    end
    Namespace.EventHandler = Namespace.EventHandler or {}
    EventHandler = Namespace.EventHandler
end


-- Ensure(Condition, Msg)
local function Ensure(Condition, ...)
    if not Condition then print(...) return end 
end

local WoWEvents = {["PLAYER_ENTER_COMBAT"] = true}
local ElunaEvents = {}
local WoWClientEvents = nil


function EventHandler:Register(Event)
    Ensure(Event ~= nil and type(Event) == "string", "Register Event error: ", tostring(Event))
    if WoWEvents[Event] ~= nil then
        print("register Event:" .. tostring(WoWClientEvents))
        WoWClientEvents:RegisterEvent(Event)
    end
    self.Events[Event] = {}
end

function EventHandler:Unregister(Event)
    Ensure(Event ~= nil and type(Event) == "string", "Unregister Event error: ", tostring(Event))
    if WoWEvents[Event] ~= nil then
        print("unregister Event:" .. tostring(WoWClientEvents))
        WoWClientEvents:UnregisterEvent(Event)
    end
    self.Events[Event] = nil
end

-- Handle Function and object(Table)
-- Callback is the bound element, it could be a raw function [function] or a bound object [table{objectRef, function}]
function EventHandler:BindEvent(Event, Callback)
    Ensure(Event ~= nil and type(Event) == "string", "BindEvent Event error: ", tostring(Event))
    if type(Callback) == "function" or type(Callback) == "table" then
        if self.Events[Event] ~= nil then
            if self.Events[Event][tostring(Callback)] == nil then
                self.Events[Event][tostring(Callback)] = Callback
                return tostring(Callback)
            end
            Ensure(false, "Callback: ", tostring(Callback), " already bound!")
        end
        Ensure(false, "Event: ", Event, " not registered")
    end
    Ensure(false, "EventHandler:BindEvent Callback type error: ", tostring(Callback))
end

function EventHandler:UnbindEvent(Event, Callback)
    Ensure(Event ~= nil and type(Event) == "string", "UnbindEvent Event error: ", tostring(Event))
    if type(Callback) == "function" or type(Callback) == "table" then
        if self.Events[Event] ~= nil then
            self.Events[Event][tostring(Callback)] = nil
        end
        return
    end
    Ensure(false, "EventHandler:UnbindEvent Callback type error: ", tostring(Callback))
end

function EventHandler:ExecEvent(Event, ...)
    if self.Events[Event] ~= nil then
        local Idx, Callback = next(self.Events[Event], nil)
        while Idx do
            if type(Callback) == "function" then
                -- print(Callback, "(", ..., ")")
                Callback(...)
            elseif type(Callback) == "table" then
                local Object, Func = unpack(Callback)
                if type(Object) == "table" and type(Func) == "function" then
                    -- print(Func, "(", Object, ..., ")")
                    Func(Object, ...)
                end
            end
            Idx, Callback = next(self.Events[Event], Idx)
        end
        return
    end
    Ensure(false, "EventHandler:ExecEvent Error unregistered event: ", Event)
    return
end

if AIO.IsServer() == false then
    WoWClientEvents = CreateFrame("Frame")
    WoWClientEvents:SetScript("OnEvent",
    function(self, event, ...)
        EventHandler:ExecEvent(event, ...)
    end)
end