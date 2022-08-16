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
--[[
    AIOBackPort allow support for old aio api
    Each of your AIO addons that must support 1.74 will be available with the 1.75 api

    Even though the 1.74 backport works it remains restricted by:
    The file name (duplicate not permitted)
    The namespace (can't get injected)
    eg:
    You have "FileLib.lua" you access with Mylib=Namespace.Mylib, it is used in many addons but, "FileLib.lua" is not an addon itself
    The addon Namespace will be null from "FileLib.lua" perspective
    If you set the namespace to _G.AIONamespace then it won't match the caller addon namespace "_G.AIONamespace.AddonA.Mylib"
    You can't inject namespace because any included file is read before the injector
    I tried some hacks but still no result

    How to use: on top of your addon use the following and replace with your addonname

    -- As always, on top
    local AIO = AIO or require("AIO")
    local AIOBackPort = AIOBackPort or require("AIOBackPort")

    
    -- Step to reference a file
    local AddonName, Namespace = ...
    local MyTable = {}
    if not AIO.IsServer() then
        if AIO.GetVersion() <= 1.74 then
            _G.AIONamespace = _G.AIONamespace or {}
            Namespace = _G.AIONamespace
        end
        Namespace.MyTable = Namespace.MyTable or {}
        MyTable = Namespace.MyTable
    end
    -- ...
    return MyTable -- for require to work (server)


    -- Step to include a file
    local MyTable = AIO.IsServer() and require("MyTable") or Namespace.MyTable
    AIO.Include("MyAddon", "./MyTable.lua")

--]]


local AIO = AIO or require("AIO")
if AIO.IsServer() then
    print("AIOBACKPORT CALLED FROM SERVER")
else
    print("AIOBACKPORT CALLED FROM CLIENT")
end


local bIsServer = true
local bIsBackport = false

AIOBackPort = AIOBackPort or {}
AIOBackPort.bIsSetup = false

if AIO then
    bIsServer = AIO.IsServer()
    bIsBackport = AIO.GetVersion() <= 1.74


    _G.AIONamespace = _G.AIONamespace or {} -- create if not exist
    -- print("_G.AIONamespace SET:"..tostring(AIONamespace) )

    local function Override(table, key)
        if key == "Include" then
            return function(...)
                if bIsServer then
                    local args = {...}
                    local AddonName = args[1]
                    local FileName = args[2]
                    local CurrentPath = debug.getinfo(2, 'S').source:sub(2)
                    local CurrentFolder = string.match(CurrentPath, "(.*[/\\])")
                    if FileName == nil then
                        FileName = string.match(( debug.getinfo(2, 'S').source:sub(1) ), "([^/\\]*)$")
                    else
                        FileName = string.match(( FileName) , "([^/\\]*)$")
                    end                
                    -- the return is important it allow the if AIO.AddAddon() then ...
                    return AIO.AddAddon(CurrentFolder .. FileName, AddonName..FileName)
                end
            end
        elseif key == "AddAddonFile" and bIsServer then
            return function(...)
                local args = {...}
                local AddonName = args[1]
                local FileName = args[2]
                local Code = args[3]
                -- print(tostring(AddonName),tostring(FileName),tostring(Code))
                AIO.AddAddonCode(AddonName..FileName, Code)
            end
        end
    end
    -- catch non existant function from 1.75, otherwise the regular function (__index is only fired for unknown index)
    if AIOBackPort.bIsSetup == false then
        setmetatable(AIO, { __index = Override })
        AIOBackPort.bIsSetup = true
    end
    if bIsServer then        
        AIO.Include("AIOBackport", "./AIOBackport.lua")        
    end
end

return AIOBackPort