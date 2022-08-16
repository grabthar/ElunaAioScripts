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
    Messaging, Eluna/AIO utility to make server authoritative property (table) replication.
    With this you no more have to handle server/client data exchange.
    Anytime the server change a value in a replicated table, the value is sent to the client.
    There is two type of replicated property, shared across all players (Multicast) and personnal for each player (Unicast).
    The Multicast table reflect it's state when a player log in. It means player has access to variables that were set before he logs in.
    A player could not access another player table, only the server can.
    The replicated table can be either a global table or a local table but it must exist on both client and server.
    If it's a local it may reside in the addon namespace

-- How to use:
-- Prerequisite:
local AIO = AIO or require("AIO")

local AddonName, Namespace = ...
local MyTable = {}
if not AIO.IsServer() then
    Namespace.MyTable = Namespace.MyTable or {}
    MyTable = Namespace.MyTable
end
-- Access to Messaging
local Messaging = AIO.IsServer() and require("Messaging") or Namespace.Messaging
AIO.Include("MyAddon", "./Messaging.lua")


-- Replicate a global table
MyGlobalTable = {}
MyGlobalTable.Replicated = {}
-- Messaging.Replicate("ReplicationHandler", MyGlobalTable.Replicated)

-- Replicate a local table
MyTable.Replicated = {}
Messaging.Replicate("ReplicationHandler", MyTable.Replicated)


if AIO.Include("MyAddon", "./MyAddon.lua") then
    -- SERVER CODE
    -- To replicate a property to all client
    MyTable.Replicated.Multicast.prop = "some data"
    local function OnLogin(event, player)
        playername = player:GetName()
        -- To replicate a property to a specific client
        SP.Replicated[playername] = {prop = "some unique data"} -- the table will be parsed
        SP.Replicated[playername].container = {} -- replication is also recursive
        SP.Replicated[playername].container.prop = 999
    end
    RegisterPlayerEvent(3, OnLogin)
else
    -- CLIENT CODE
    -- Client can catch(detect) when it receive a replicated data
    Messaging.OnReceiveReplicatedData(
        function(Table, key, value)
            print("Receiving replicated data...")
            -- Detect any new value
            if Table[key] ~= nil then
                print("Added to Table: " .. tostring(Table) .. " Value:" .. tostring(Table[key]))
                -- if you uncomment you stop the delegate, it will no more register this event
                -- return true 
            end
            if Table == MyTable.Replicated.Multicast then
                print("Received a value in Multicast table, key:" .. key .. " value:" .. Table[key])
            end
        end
    )
end
]]



--[[ MESSAGING TODO
 (Client/server) maybe some invalidation todo?
 (Server) remove bismulticast in MT
 (Client) event handler (script) support
 (server/client) safe RPC system
--]]

local AIO = AIO or require("AIO")
local AIOBackPort = AIOBackPort or require("AIOBackPort")

-- Step to reference a file
local AddonName, Namespace = ...
local Messaging = {}

if not AIO.IsServer() then
    if AIO.GetVersion() <= 1.74 then
        _G.AIONamespace = _G.AIONamespace or {}
        Namespace = _G.AIONamespace
    end
    Namespace.Messaging = Namespace.Messaging or {}
    Messaging = Namespace.Messaging
end


local DebugPrint = false
local DebugReplication = false

local function LogDebugServer(Condition, Msg)
    if DebugPrint == true and Condition and AIO.IsServer() then
        print(Msg)
    end
end

local function LogDebugClient(Condition, Msg)
    if DebugPrint == true and Condition and AIO.IsServer() == false then
        print(Msg)
    end
end

local function RootSearch(SearchTable, Ns, SearchedRootTable)
    if AIO.IsServer() then
        -- search the "namespace" of the replicated table
        RootTableSkipFilter = {["Smallfolk"] = true, ["os"] = true, ["Object"] = true, ["PlayerSeasonInfo"] = true, ["WorldPacket"] = true, 
            ["Creature"] = true, ["string"] = true, ["PlayerSeasonObjectiveStatus"] = true, ["Season"] = true, ["SeasonPass"] = true, 
            ["Guild"] = true, ["SeasonInfo"] = true, ["long long"] = true, ["BattleGround"] = true, ["AuctionHouseEntry"] = true, 
            ["table"] = true, ["lualzw"] = true, ["unsigned long long"] = true, ["Player"] = true, ["debug"] = true, 
            ["Corpse"] = true, ["Quest"] = true, ["Spell"] = true, ["Group"] = true, ["Vehicle"] = true, ["Item"] = true, 
            ["GameObject"] = true, ["SeasonObjective"] = true, ["SeasonReward"] = true, ["coroutine"] = true, ["package"] = true, 
            ["Map"] = true, ["ChatHandler"] = true, ["Unit"] = true, ["ElunaQuery"] = true, ["_G"] = true, ["WorldObject"] = true, 
            ["math"] = true, ["AIO"] = true, ["io"] = true, ["bit32"] = true, ["Aura"] = true, ["RootTableSkipFilter"] = true
        }
        local function RootSearch(SearchTable, Ns, SearchedRootTable)
            if type(SearchTable) == "table" then
                for Key, Value in pairs(SearchTable) do

                    if RootTableSkipFilter[Key] ~= true then
                        if Ns == "" then
                            CurrentNs =  Ns .. Key
                        else
                            CurrentNs =  Ns .. "." .. tostring(Key)
                        end

                        if Value == SearchedRootTable then
                            result = CurrentNs
                            -- result = Ns .. "." .. tostring(Key)
                            return result
                        end
                        res = RootSearch(Value, CurrentNs, SearchedRootTable)
                        if res ~= nil then return res end
                        CurrentNs = Ns
                    end
                end
            end
        end
        return RootSearch(SearchTable, Ns, SearchedRootTable)
    end
end

function Messaging.DisplayTable(Table)
    assert(Table ~= nil)
    local Resolver = {}
    -- Used to prevent infinite recursion (for table that reference any parent table)
    local CachedTable = {}

    local function CountElem(InTable)
        total = 0
        for _ in pairs(InTable) do total = total + 1 end
        return total
    end

    local function Resolve(InTable)
        local chain = ""

        local function Traverse(InTable)
            local name, parent = nil
            if Resolver[InTable] ~= nil then
                name = Resolver[InTable].name
                parent = Resolver[InTable].parent
            end
            chain = tostring(name) .. "." .. chain            
            if parent ~= nil then
                Traverse(parent)
            end
        end

        Traverse(InTable)
        return chain
    end

    local function Traverse(InTable, Depth, CallbackTask)
        local count = 0
        CachedTable[InTable] = true
        for Key, Value in pairs(InTable) do
            count = count + 1
            CallbackTask(InTable, Key, Value, count, Depth)
            if type(Value) == "table" and CachedTable[Value] ~= true then
                Traverse(Value, Depth + 1, CallbackTask)
            end
        end        
    end

    local function PrintLine(InTable, Key, Value, Count, Depth)
        DisplayStr = string.rep(" ", (Depth + 1) * 12) .. " (" .. Count .. "/" .. CountElem(InTable) .. ") " .. tostring(Key)

        if type(Value) == "table" then
            DisplayStr = DisplayStr .. " [" .. tostring(Value) .. "]"
        elseif type(Value) == "string" then
            DisplayStr = DisplayStr .. " = \"" .. tostring(Value) .. "\""
        else
            DisplayStr = DisplayStr .. " = " .. tostring(Value)
        end
        print(DisplayStr)
    end

    local function BuildRefTable(InTable, Key, Value, count, Depth)
        if Depth >= MaxDepth then
            MaxDepth = Depth
        end
        if type(Value) == "table" and InTable ~= Value then
            -- print("BuildRefTable: Resolver[" .. tostring(Value) .. "]: {" .. tostring(Key) .. ", " .. tostring(InTable) .. "}")         
            Resolver[Value] = {name = Key, parent = InTable}
        end
    end

    local Depth = 0
    MaxDepth = 0
    -- Traverse(Table, Depth, BuildRefTable)
    
    TableName = RootSearch(_G, "", Table)
    if not TableName then TableName = tostring(Table) end
    print("")
    print("DisplayTable: " .. TableName)
    print( TableName .. " [" .. tostring(Table) .. "]")
    Traverse(Table, Depth, PrintLine)
    print("")

end

-- return the parent table from a KeyVal and the keyname
local function GetParent(KeyVal, SearchTable)
    -- Global search by default
    if not SearchTable then SearchTable = _G end
    assert(type(SearchTable) == "table")
    -- assert(type(KeyVal) == "table")

    local result = nil
    local t = nil
    local k = nil
    local Cached = {}
    -- tables to skip in _G
    RootTableSkipFilter = {["Smallfolk"] = true, ["os"] = true, ["Object"] = true, ["PlayerSeasonInfo"] = true, ["WorldPacket"] = true, 
        ["Creature"] = true, ["string"] = true, ["PlayerSeasonObjectiveStatus"] = true, ["Season"] = true, ["SeasonPass"] = true, 
        ["Guild"] = true, ["SeasonInfo"] = true, ["long long"] = true, ["BattleGround"] = true, ["AuctionHouseEntry"] = true, 
        ["table"] = true, ["lualzw"] = true, ["unsigned long long"] = true, ["Player"] = true, ["debug"] = true, 
        ["Corpse"] = true, ["Quest"] = true, ["Spell"] = true, ["Group"] = true, ["Vehicle"] = true, ["Item"] = true, 
        ["GameObject"] = true, ["SeasonObjective"] = true, ["SeasonReward"] = true, ["coroutine"] = true, ["package"] = true, 
        ["Map"] = true, ["ChatHandler"] = true, ["Unit"] = true, ["ElunaQuery"] = true, ["_G"] = true, ["WorldObject"] = true, 
        ["math"] = true, ["AIO"] = true, ["io"] = true, ["bit32"] = true, ["Aura"] = true, ["RootTableSkipFilter"] = true
    }

    local function Traverse(KeyVal, SearchTable)
        for Key, Value in pairs(SearchTable) do
            if RootTableSkipFilter[Key] ~= true then
                if Value == KeyVal then
                    -- print("FOUND  Value:" .. tostring(Value) .. " Key:" .. tostring(Key) .. " SearchTable:" .. tostring(SearchTable))
                    if SearchTable == _G then
                        return _G, tostring(Key)
                    else
                        return SearchTable, tostring(Key)
                    end
                    -- return SearchTable would crash lua/server
                end              
                if type(Value) == "table" and Cached[Value] ~= true then
                    Cached[Value] = true
                    t, k = Traverse(KeyVal, Value)
                end
                if t ~= nil then return t, k end
            end
        end
    end

    -- this part only works for server
    local i = 1
    while true do
        local n, v = debug.getlocal(3, i)
        if not n then break end
        if type(v) == "table" then
            local t, k = Traverse(KeyVal, v)
            if t ~= nil then return t, k end
        end
        i = i + 1
    end

    -- global search
    return Traverse(KeyVal, SearchTable)
end

function Messaging.Replicate(ReplicationHandlerName, ReplicatedTable)
    assert(type(ReplicationHandlerName) == "string")
    assert(type(ReplicatedTable) == "table")

    local ReplicationHandler = AIO.AddHandlers(ReplicationHandlerName, {})

    -- SERVER
    if AIO.IsServer() then
        local index = {}
        local OwnerKeys = {} -- contain all tables references ownership. Flat table(list) index/insert is O(1)
        local MulticastRefState = {}
        local Initialized = 0

        function ReflectRootOnLogin(event, Players)
            -- TODO simplify with a multicast?
            if type(Players) ~= "table" then
                Players = {Players}
            end
            for _,Player in pairs(Players) do 
                if DebugReplication == true then
                    print("---------------------------------------------------------------------------")
                    print("New Player has logged in, Player: " .. Player:GetName() ..  " sending the following multicast table:")
                    Messaging.DisplayTable(ReplicatedTable.Multicast)
                    print("---------------------------------------------------------------------------")
                end

                -- We only send the Multicast table player shouldn't know about other players data
                AIO.Handle(Player, ReplicationHandlerName, "ReflectReplicatedTable", 
                MulticastRefState, 
                ReplicatedTable.Multicast, 
                tostring(ReplicatedTable.Multicast), 
                tostring(ReplicatedTable)) 
            end

        end

        function PushToLoginEvent(msg, player)
            -- avoid re-registering (AddOnInit) called when any player log-in
            if Initialized == 1 then
                Initialized = 2
                RegisterPlayerEvent(3, ReflectRootOnLogin)
            end
        end

        function SetupServerStateReflection(Players)
            if Initialized == 0 then
                    Initialized = 1
                    -- the firsts players can't bind to OnloginEvent they need to reflect server state early
                    -- by chance Multicast is the first value assigned internally, we can always access it
                    ReflectRootOnLogin(3, Players)
                    -- Registered eluna events are LIFO stacks, we need our event (OnLogin) to be processed first before the user (addon author) defined one
                    -- This hack let's you push to the end of an event stack
                    AIO.AddOnInit(PushToLoginEvent)
                -- end
            end
        end

        function UnrefRecursive(t, index, OwnerKeys)
            for ik, iv in pairs(t) do
                OwnerKeys[t[index][ik]] = nil
                MulticastRefState[tostring(t[index][ik])] = nil                     
                if type(iv) == "table" then
                    UnrefRecursive(iv, index, OwnerKeys)
                end
            end
        end

        local mt = {
            __index = function (t,k)
                return t[index][k]
            end,
            __newindex = function (t,k,v)
                -- cleanup if we override an existant table
                if type(t[index][k]) == "table" then
                    MulticastRefState[tostring(t[index][k])] = nil
                    UnrefRecursive(t[index][k], index, OwnerKeys)                       
                end

                -- Assign the value in the original table
                if type(v) == "table" then
                    -- break original table reference we need it, otherwise new keys can have multiple owner etc
                    -- each table act as a uuid
                    local NewRef = {} 
                    t[index][k] = NewRef                 
                    t[index][k] = track(NewRef)
                elseif type(v) == "nil" then
                    OwnerKeys[t[index][k]] = nil -- remove owner reference
                    t[index][k] = v
                else
                    t[index][k] = v
                end
                -- From here do not use v as val but -> t[index][k]            


                -- Detect data replication cast type and target
                local bIsMulticast = false
                local Owner = nil
                -- base replicated table and v is table
                if t == ReplicatedTable and type(t[index][k]) == "table" then
                    OwnerKeys[t[index][k]] = k
                    Owner = k
                else
                    Owner = OwnerKeys[t]
                    if Owner then
                        -- Add sub table to the matching owner
                        if type(t[index][k]) == "table" then
                            OwnerKeys[t[index][k]] = Owner
                        end
                    end
                end
                if Owner == "Multicast" then 
                    bIsMulticast = true
                    if type(v) == "table" then
                        MulticastRefState[tostring(t[index][k])] = {RefKey=k, OwningTable=tostring(t)}
                    end
                end
                
                Send(t, k, t[index][k], Owner)

                LogDebugServer(DebugReplication, "New value assigned:"
                .. "\n\t\t [table]:" .. tostring(t)
                .. "\n\t\t [key]" .. tostring(k)
                .. "\n\t\t [value]" .. tostring(t[index][k])
                .. "\n\t\t [Multicast]:" .. tostring(bIsMulticast)
                .. "\n\t\t [Owner]:" .. tostring(Owner))

                -- If the new table have key then track them
                if type(v) == "table" then 
                    for ik, iv in pairs(v) do -- should be done after the previous data is handheld
                        t[k][ik] = iv
                    end
                end
            end,
            __pairs = function (t)
                return next, t[index], nil
            end
        }

        function track (t)
            local proxy = {}
            proxy[index] = t
            setmetatable(proxy, mt)
            return proxy
        end

        function Send(table, key, value, Owner)
            local Players = nil
            if Owner ~= "Multicast" then
                Players = {GetPlayerByName(Owner)}
            else
                Players = GetPlayersInWorld()
            end

            if #Players ~= 0 then -- do not init (send replication state) until there is a player
                SetupServerStateReflection(Players)
                AIO.Msg():Add(ReplicationHandlerName, "ReplicateServerData", 
                    tostring(table), -- table reference are not preserved during send
                    key, 
                    value, 
                    tostring(value)
                ):Send(unpack(Players)) -- multicast to all players                
            end
        end

        local ReplicatedTableParent, TableKeyName = GetParent(ReplicatedTable)
        ReplicatedTable = track(ReplicatedTable)
        ReplicatedTable.Multicast = {}
        ReplicatedTableParent[TableKeyName] = ReplicatedTable

        LogDebugServer(DebugReplication, "REPLICATION:"
        .. "\n\t ReplicatedTable: \t" .. tostring(ReplicatedTable) .. " -> " .. tostring(ReplicatedTableParent[TableKeyName])
        .. "\n\t ReplicatedTableParent: \t" .. tostring(ReplicatedTableParent)
        .. "\n\t ReplicatedTable KeyName: \t" .. tostring(TableKeyName)
        .. "\n\t Multicast: \t" .. tostring(ReplicatedTable.Multicast))

    end

    -- CLIENT
    if AIO.IsServer() == false then
        local ServerReference = {}
        ReplicationCallbacks = {}

        local function ParseMulticastReferenceTree(References)
            -- Reference may be in wrong order
            -- B is referenced before A but is within A
            -- we need to repeat until there is no more missing reference
            -- Some caching is done to skip already parsed elems
            local Cache = {}
            local function Traverse(Tree, Cache)

                local Remaining = 0
                local NoAssignment = true
                for TableRef,Infos in pairs(Tree) do
                    if Cache[TableRef] ~= true then
                        -- print("|cff77AAFF TableRef:" .. TableRef .. "RefKey:" .. tostring(Infos.RefKey) .. " OwningTable:" .. tostring(Infos.OwningTable) .. "|r")
                        if ServerReference[Infos.OwningTable] == nil then
                            -- print("ServerReference do not contain index called: " .. tostring(Infos.OwningTable))
                            Remaining = Remaining + 1
                        else
                            if ServerReference[Infos.OwningTable][Infos.RefKey] == nil then
                                LogDebugClient(DebugReplication, 
                                    tostring(ServerReference[Infos.OwningTable])
                                    .. " do not contain index called:"
                                    .. tostring(Infos.RefKey))
                            else
                                ServerReference[TableRef] = ServerReference[Infos.OwningTable][Infos.RefKey]
                                Cache[TableRef] = true
                                NoAssignment = false
                            end
                        end
                    end
                end

                if Remaining > 0 and NoAssignment == false then
                    Traverse(Tree, Cache)
                else
                    if Remaining > 0 then
                        print("|cffFF5555 Could not parse " .. Remaining .. " properties references |r")
                    end
                end
            end
            Traverse(References, Cache)
        end

        -- called when a player log, we need the state of the server replication (e.g) Multicast table data changed over time
        function ReplicationHandler.ReflectReplicatedTable(Player, MulticastRefState, MulticastTable, MulticastValueName, ReplicatedTableValueName)
            
            LogDebugClient(DebugReplication, 
            "|cff4444CC ReflectReplicatedTable"
            .. " \n MulticastTable:" .. tostring(MulticastTable)
            .. " \n MulticastValueName:" .. tostring(MulticastValueName)
            .. " \n ReplicatedTableValueName:" .. tostring(ReplicatedTableValueName))

            ReplicatedTable.Multicast = {}
            ReplicatedTable.Multicast = MulticastTable
            ServerReference[ReplicatedTableValueName] = ReplicatedTable
            ServerReference[MulticastValueName] = ReplicatedTable.Multicast
            
            ParseMulticastReferenceTree(MulticastRefState)

            if DebugReplication == true then
                print("---------------------------------------------------------------------------")
                print("Received Multicast is:")
                Messaging.DisplayTable(ReplicatedTable.Multicast)
                print("---------------------------------------------------------------------------")

            end
        end

        -- called when the player receive data from the server
        function ReplicationHandler.ReplicateServerData(player, table, key, value, valueName)
            LogDebugClient(DebugReplication, 
            "|cffAA00CC player:" .. player .. " receive:"
            .. " \n    [table]:" .. tostring(table)
            .. " \n    [key]:" .. tostring(key)
            .. " \n    [value]:" .. tostring(value)
            .. " \n    [valueName]:".. tostring(valueName) 
            .. "|r")

            if ServerReference[table] ~= nil then
                ServerReference[table][key] = value
                if type(value) == "table" then
                    ServerReference[valueName] = value
                elseif type(value) == "nil" then
                    ServerReference[valueName] = nil
                end
                -- fire event handler
                for k,v in pairs(ReplicationCallbacks) do
                    res = v(ServerReference[table], key, value)
                    if res == true then
                        ReplicationCallbacks[k] = nil
                    end
                end                
            else
                LogDebugClient(DebugReplication, "|cffFF0000 ServerReference[table]:" .. tostring(table) .. " doesn't exist! |r")
            end
        end
    end
end

-- Used for the client to detect new incoming replicated data
-- Add a function callback that is called when any replicated data is received from the server
-- with this signature: function(Table, key, value)
-- once your function return true it won't be called anymore
function Messaging.OnReceiveReplicatedData(Callback)
    if AIO.IsServer() == false then
        ReplicationCallbacks[{}] = Callback
    end
end


return Messaging