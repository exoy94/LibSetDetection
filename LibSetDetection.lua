--[[ ------------------- ]]
--[[ -- ToDo / Notes  -- ]]
--[[ ------------------- ]]

--- check if the setId is provided when the mystical is equipped, that disables all set effects 

--- maybe add an determine changes in the SlotManger .... happens often to me, that I switch back and forth between two pieces. 
--- if this happens the lib should not do anything else 
--[[ 
  * so a table of the new setup, which is constantly updated with any slot update and compared to the current setup 
  * if something goes back, it will be removed again from that list 
  * so any further actions will only be done, if the table is not empty at the time of the "Transmission Call"
  * this should happen independently of update all or update non 
  * this means i need to make sure the lib initializes correctly. because there is a case, where I have nothing equipped. 
  * so the actual setup is identical to the template setup 
  * I probably need a proper initialization procedure anyways, cause I need to estables the state of the data share anyways 
]]

 

--[[
EventDataUpdate( newData, diffData )
both data are probably just going to be the *setData* table
([setId] = {numBody, numFront, numBack} )
-- anything more specific put limitations on the use message 

-- triggers, if any data change. This includes the changes by EventSetChange 
-- but also includes changes in the setup that do not result in an EventSetChange 
--- intented for addons which keep track of more things, e.g. "has a meaningful" setup 


returns either, the setData (in which case I can add a setId as an additional filter)
or it returns just the list with slotId to setId 
-- i currently tend towards the first option. it makes the information between player and 
-- groupmember more consistant. the only meaningful application I see is a very detailed analysis 
-- of the setup of the player (information for group member not available) 
-- this would only be relevant with a very in depth analysis of the usefullness of a setup, 
-- with the only example I can currently think of is, that you want to detect that for example you were 
-- light armor on armor pieces and medium armor on jewlery and it should be the other way arround 
--- not sure, if for this very specific case I just provide an additional api for the player 

--- GetMaxEquipThreshold (that function would probably the place to add an overwrite for shattered fate?!) 
  -- but it should probably not be a setting for the user, cuz different addons might have different use cases 
  -- so i either make the decision for for this set and future set, that i overwrite the max equipped and determine 
  -- the set as active as soon it hits the first threshold (how would I detect if more thresholds are reached and how would i inform the user? ) 
  -- it will probably get to the point, where the addons interested in this must do at least some additional manual work, but I should aim for 
  -- some way to at least address some way to be covered with the events, so addons need not constantly checking and all do the same thing 
  --- maybe some extra api for sets with exceptions? -- maybe an additional variable provided by the setChange event "isSpecial" 
  --- and then some API where you get additional information for a certain setId if it is special (the returned data could be unique for different special sets)
]]


LibSetDetection = LibSetDetection or {}
local libName = "LibSetDetection"
local libVersion = 4
local playerName = GetUnitName("player") 
local EM = GetEventManager() 
local SV 

--[[ -------------- ]]
--[[ -- Entities -- ]]
--[[ -------------- ]]
 
local CallbackManager = {}  -- CM 
local BroadcastManager = {} -- BM
local SetDetector = {}      -- SD 
local PlayerSets = {}       -- PS
local GroupManager = {}     -- GM

local SlotManager = {}      -- SM       
local Development = {}      -- Dev

--[[ --------------- ]]
--[[ -- Templates -- ]]
--[[ --------------- ]]



--[[ ------------------- ]]
--[[ -- Lookup Tables -- ]]
--[[ ------------------- ]]

local function MergeSlotTables(t1, t2)
  local t = {}
  for k, v in pairs(t1) do
     t[k] = v
  end
	for k, v in pairs(t2) do
	   t[k] = v
	end
	return t
end

local barList = {
  ["front"] = HOTBAR_CATEGORY_PRIMARY,
  ["back"] = HOTBAR_CATEGORY_BACKUP,
  ["body"] = -1,
}

local slotList = {
  ["body"] = {
    [EQUIP_SLOT_HEAD] = "Head",                   --  0
    [EQUIP_SLOT_NECK] = "Necklace",               --  1
    [EQUIP_SLOT_CHEST] = "Chest",                 --  2
    [EQUIP_SLOT_SHOULDERS] = "Shoulders",         --  3
    [EQUIP_SLOT_WAIST] = "Waist",                 --  6
    [EQUIP_SLOT_LEGS] = "Legs",                   --  8
    [EQUIP_SLOT_FEET] = "Feet",                   --  9
    [EQUIP_SLOT_RING1] = "Ring1",                 -- 11
    [EQUIP_SLOT_RING2] = "Ring2",                 -- 12
    [EQUIP_SLOT_HAND] = "Hand",                   -- 16
  },
  ["front"] = {
    [EQUIP_SLOT_MAIN_HAND] = "MainFront",         --  4
    [EQUIP_SLOT_OFF_HAND] = "OffFront",           --  5
  },
  ["back"] = {
    [EQUIP_SLOT_BACKUP_MAIN] = "MainBack",        -- 20
    [EQUIP_SLOT_BACKUP_OFF] = "OffBack",          -- 21
  }
}

local weaponSlotList = MergeSlotTables( slotList["front"], slotList["back"] )
local equipSlotList = MergeSlotTables( slotList["body"], weaponSlotList )

local twoHanderList = {
  [WEAPONTYPE_TWO_HANDED_SWORD] = "Greatsword",     --  4
  [WEAPONTYPE_TWO_HANDED_AXE] = "Battleaxe",        --  5
  [WEAPONTYPE_TWO_HANDED_HAMMER] = "Battlehammer",  --  6
  [WEAPONTYPE_BOW] = "Bow",                         --  8
  [WEAPONTYPE_HEALING_STAFF] = "Healingstaff",      --  9
  [WEAPONTYPE_FIRE_STAFF] = "Firestaff",            -- 12
  [WEAPONTYPE_FROST_STAFF] = "Froststaff",          -- 13
  [WEAPONTYPE_LIGHTNING_STAFF] = "Lightningstaff",  -- 15
}

--- result code definition for callback manager
local CALLBACK_RESULT_SUCCESS = 0 
local CALLBACK_RESULT_INVALID_CALLBACK = 1 
local CALLBACK_RESULT_INVALID_UNITTYPE = 2 
local CALLBACK_RESULT_INVALID_FILTER = 3
local CALLBACK_RESULT_INVALID_NAME = 4 
local CALLBACK_RESULT_DUPLICATE_NAME = 5
local CALLBACK_RESULT_UNKNOWN_NAME = 6

--- change types for events (global) 
LSD_CHANGE_TYPE_UNEQUIPPED = 1 
LSD_CHANGE_TYPE_EQUIPPED = 2
LSD_CHANGE_TYPE_UPDATE = 3


--[[ ------------------------------- ]]
--[[ -- Generic Utility Functions -- ]]
--[[ ------------------------------- ]]

local function IsNumber( n ) 
  return type(n) == "number"
end

local function IsString( str ) 
  return type(str) == "string"
end

local function IsTable(t)
  return type(t) == "table"
end

local function IsFunction(f)
  return type(f) == "function"
end

--[[ -------------------------------- ]]
--[[ -- Specific Utility Functions -- ]]
--[[ -------------------------------- ]]

local function GetSetId( slotId )
  local _, _, _, _, _, setId = GetItemLinkSetInfo( GetItemLink(BAG_WORN, slotId) )
  return setId
end

local function IsWeaponSlot( slotId )
  return weaponSlotList[slotId] ~= nil
end

local function IsTwoHander( slotId )
  local weaponType = GetItemWeaponType(BAG_WORN, slotId)
  return twoHanderList[weaponType] ~= nil
end

local function GetSetName( setId ) 
  local _, setName = GetItemSetInfo( setId )
  return setName
end 

local function GetMaxEquip( setId )
  local _, _, _, _, _, maxEquip = GetItemSetInfo( setId )
  return maxEquip
end

local function ConvertToUnperfected( setId ) 
  local unperf = GetItemSetUnperfectedSetId( setId ) 
  if unperf == 0 then 
    return setId 
  else 
    return unperf 
  end
end

--- rum arbeit
local function ExtendNumEquipData( numEquip ) 
  local numEquipExtended = ZO_DeepTableCopy(numEquip)
  for setId, _ in pairs( numEquip) do
    numEquipExtended[setId].setName = GetSetName(setId)
    numEquipExtended[setId].maxEquip = GetMaxEquip(setId) 
  end
  return numEquipExtended
end

local function DecodeChangeType( changeType ) 
  local changeStr = {"unequipped", "equipped", "updated"}
  return changeStr[changeType]
end

--[[ ----------- ]]
--[[ -- Debug -- ]] 
--[[ ----------- ]]

local function debugMsg( msg ) 
  if not SV.debug then return end
  d( zo_strformat("[<<1>>-LSD] <<2>>", GetTimeString(), msg) )
end

local function devMsg(id, msg) 
  d( zo_strformat("[<<1>> LSD - <<2>>] <<3>>", GetTimeString(), id, msg) )  
end

--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ---------------------- %% ]]
--[[ %% -- Callback Manager -- %% ]]
--[[ %% ---------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]

--[[Typical Inputs]]
-- *registryType* (string - case sensitive ): "SetChange" or "DataUpdate"
-- *unitType* (string - case sensitive) = "player" or "group" 
-- *id* (string - case sensitive): unique name (for each registryType/unitType) 
-- *filter*:nilable (if *registryType = "SetChange", needs to be numer or table of numbers (setIds) )

CallbackManager.debug = true

CallbackManager.results = {
  [CALLBACK_RESULT_SUCCESS] = "success",
  [CALLBACK_RESULT_INVALID_CALLBACK] = "invalid callback",
  [CALLBACK_RESULT_INVALID_UNITTYPE] = "invalid unitType",
  [CALLBACK_RESULT_INVALID_FILTER] = "invalid filter", 
  [CALLBACK_RESULT_INVALID_NAME] = "invalid name",
  [CALLBACK_RESULT_DUPLICATE_NAME] = "duplicate name",
  [CALLBACK_RESULT_UNKNOWN_NAME] = "unkown name",
}

--- registry initialization
CallbackManager.registry = {
  ["playerSetChange"] = {}, 
  ["groupSetChange"] = {}, 
  ["playerUpdateData"] = {}, 
  ["groupUpdateData"] = {}, 
}


function CallbackManager.UpdateRegistry(action, registryType, uniqueId, callback, unitType, filter)
  local CM = CallbackManager 
  if unitType == "all" or not unitType then   -- if unitType is nil or "all" execute function for "player" and "group"
    local resultPlayer = CM.UpdateRegistry(action, registryType, uniqueId, callback, "player", filterTable)
    local resultGroup = CM.UpdateRegistry(action, registryType, uniqueId, callback, "group", filterTable)
    return resultPlayer, resultGroup
  end
  --- verify general user inputs
  if not IsFunction(callback) then return CALLBACK_RESULT_INVALID_CALLBACK end
  if not IsString(uniqueId) then return CALLBACK_RESULT_INVALID_NAME end 
  local unitTypeList = { ["player"]=true, ["group"]=true } 
  if not unitTypeList[unitType] then return CALLBACK_RESULT_INVALID_UNITTYPE end 
  --- set change registry
  local registryName = unitType..registryType
  if registryType == "SetChange" then 
    return CM.UpdateSetChangeRegistry( action, registryName, uniqueId, callback, filter ) 
  end 
  --- data update registry
  if registryType == "DataUpdate" then 
    return CM.UpdateDataUpdateRegistry( action, registryName, uniqueId, callback, filter ) 
  end
end   -- End of "UpdateRegistry"



function CallbackManager.UpdateSetChangeRegistry( action, registryName, uniqueId, callback, filter ) 
  --- validate filter 
  local function IsValidSetChangeFilter() 
    if not filter then return true end --  
    if IsNumber(filter) then return true end 
    if IsTable(filter) then 
      for _, filterId in pairs(filter) do 
        if not IsNumber(filterId) then return false end 
      end
      return true 
    end
    return false 
  end
  if not IsValidSetChangeFilter() then return CALLBACK_RESULT_INVALID_FILTER end 
  --- format filter  
  filter = filter or {0}    -- events with no filter will be mapped to an arbitrary filter Id of 0 
  if IsNumber(filter) then filter = {filter} end      -- this makes subsequent code easier and clearer
  for key, filterId in pairs(filter) do 
    filter[key] = ConvertToUnperfected( filterId ) -- change perfected to unperfected setId
  end
  --- update registry
  for _, filterId in pairs(filter) do 
    local callbackList = CallbackManager.registry[registryName][filterId] or {}
    if action then    -- registration
      if callbackList[uniqueId] then return CALLBACK_RESULT_DUPLICATE_NAME end
      callbackList[uniqueId] = callback 
    else  -- unregistration
      if not callbackList[uniqueId] then return CALLBACK_RESULT_UNKNOWN_NAME end 
      callbackList[uniqueId] = nil
    end 
  end
  return CALLBACK_RESULT_SUCCESS
end   -- End of "UpdateSetChangeRegistry"


function CallbackManager.UpdateDataUpdateRegistry( action, registryName, uniqueId, callback, filter ) 
  --- validate filter
  if filter then return CALLBACK_RESULT_INVALID_FILTER end 
  --- update registry
  local callbackList = CallbackManager.registry[registryName] 
  if action then -- registration
    if callbackList[uniqueId] then return CALLBACK_RESULT_DUPLICATE_NAME end
    callbackList[uniqueId] = callback 
  else -- unregistration
    if not callbackList[uniqueId] then return CALLBACK_RESULT_UNKNOWN_NAME end 
    callbackList[uniqueId] = nil
  end
end   -- UpdateDataUpdateRegistry


function CallbackManager.FireCallbacks( eventType, unitType, setId, ... ) 
  local function FireCallbacks(callbackList, ...) 
    if ZO_IsTableEmpty( callbackList ) then return end 
    for _, callback in pairs( callbackList ) do 
      callback(...) 
    end
  end
  
  local CM = CallbackManager
  local registryName = unitType..eventType
  if eventType == "DataUpdate" then 
    FireCallbacks( CM.registry[registryName],... )
    -- unitTag
    -- numEquipExtended
    -- equippedGear
    if CM.debug and ExoyDev then 
      local p = {...} 
      devMsg("CM", zo_strformat("DataUpdate for <<1>>", p[1]) )
      d(p[2])
      d("---") 
      d(p[3])
      d("---")
    end
  elseif eventType == "SetChange" then 
    -- changeType 
    -- unperfSetId 
    -- unitTag 
    -- isActiveOnBody 
    -- isActiveOnFront
    -- isActiveOnBack
    if CM.debug and ExoyDev then --debug for "SetChange Event"
      local p = {...}
      local msgStart = zo_strformat( "<<1>> for <<2>>: <<3>> (<<4>>) ", eventType, p[3], DecodeChangeType(p[1]), p[1] ) 
      local msgEnd = zo_strformat("<<1>> (<<2>>) - {<<3>>, <<4>>, <<5>>}", 
        GetSetName( p[2] ), p[2], p[4] and 1 or 0, p[5] and 1 or 0, p[6] and 1 or 0 )
      devMsg("CM", msgStart..msgEnd )
    end
    FireCallbacks( CM.registry[registryName][0], ...)
    FireCallbacks( CM.registry[registryName][setId], ...)
  end
end


--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------ %% ]]
--[[ %% -- Set Detector -- %% ]]
--[[ %% ------------------ %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]

SetDetector.__index = SetDetector 

function SetDetector:New( unitType, unitTag )
  -- unitType ("player" or "group")
  -- unitTag at the time of creation
  if unitType == "player" then 
    self.debug = false
  end
  if unitType == "group" then 
    self.debug = true
  end
  self.unitType = unitType or "empty"
  self.numEquip = {} 
  self.activeOnBar = {}
  self.activeState = {}
  return self
end


function SetDetector:UpdateData( newData, unitTag )
  if self.debug and ExoyDev then  devMsg( "SD", "update data ("..unitTag..")" ) end
  self.unitTag = unitTag -- ensures always correct unitTag
  self:InitTables( newData )  -- updates archive and resets current 
  self:ConvertDataToUnperfected()   -- all perfected pieces are handled as unperfected  
  self:AnalyseData()  -- determines, which sets are active 
  local changeList = self:DetermineChanges()  -- determine, what has changed (un-)equip/ update
  self:FireCallbacks( changeList )  -- fire callbacks according to detected changes
end


function SetDetector:InitTables( data ) 
  if self.debug and ExoyDev then devMsg( "SD", "initialize tables") end
  self.archive = {} 
  self.archive["numEquip"] = ZO_ShallowTableCopy(self.numEquip)
  self.archive["activeOnBar"] = ZO_ShallowTableCopy(self.activeOnBar)
  self.archive["activeState"] = ZO_ShallowTableCopy(self.activeState)
  self.numEquip = data
  self.activeOnBar = {}
  self.activeState = {}
end


function SetDetector:ConvertDataToUnperfected() 
  -- initialize local tables
  local numEquipTemp = {}
  local listOfPerfected = {}
  local listOfNormal = {}
  -- check, if any perfected sets are equipped
  for setId, _ in pairs( self.numEquip ) do 
    if GetItemSetUnperfectedSetId(setId) ~= 0 then 
      table.insert( listOfPerfected, setId ) 
    else 
      table.insert( listOfNormal, setId )
    end
  end
  -- add all normal sets to temporary 
  for _, setId in ipairs( listOfNormal ) do 
    numEquipTemp[setId] = ZO_ShallowTableCopy(self.numEquip[setId]) 
  end
  -- add perfected count to corresponding unperfected version  
  for _, perfSetId in ipairs( listOfPerfected ) do 
    local unperfSetId = GetItemSetUnperfectedSetId(perfSetId) 
    if not numEquipTemp[unperfSetId] then 
    -- if no unperfected pieces are equipped, overwrite it with perfected
      numEquipTemp[unperfSetId] = ZO_ShallowTableCopy(self.numEquip[perfSetId])
    else 
    -- if unperfected pieces are equipped, add perfected ones
      for barName, numEquip in pairs( self.numEquip[perfSetId] ) do 
        numEquipTemp[unperfSetId][barName] = numEquipTemp[unperfSetId][barName] + numEquip
      end
    end
  end
  -- debug
  if self.debug and ExoyDev then 
    devMsg( "SD", "convert data to unperfected")
    d("raw data:")
    d(ExtendNumEquipData(self.numEquip) )
    d("------------ End of raw data")
    d("converted data:")
    d(ExtendNumEquipData(numEquipTemp) )
    d("------------ End of converted data")
    d("conversion list:")
    for _, id in ipairs(listOfPerfected) do 
      d( zo_strformat("<<1>> --> <<2>> (<<3>>)", id, GetItemSetUnperfectedSetId(id), GetSetName(id) ) )
    end
    d("------------ End of conversion list")
  end
  -- overwrite data with converted data
  self.numEquip = nil 
  self.numEquip = ZO_ShallowTableCopy(numEquipTemp)
end


function SetDetector:AnalyseData() 
  for setId, numEquip in pairs( self.numEquip ) do  
    local active = {} 
    local numFront = numEquip["body"] + numEquip["front"] 
    local numBack = numEquip["body"] + numEquip["back"] 
    local maxEquip = GetMaxEquip(setId)
    active["front"] = numFront >= maxEquip
    active["back"] = numBack >= maxEquip
    active["body"] = numEquip["body"] >= maxEquip
    self.activeOnBar[setId] = active 
  end
  if self.debug and ExoyDev then 
    devMsg("SD", "analyse data") 
    d("current activeOnBar list")
    d( self.activeOnBar )
    d("------------ End of current activeOnBar list")
  end
end


function SetDetector:DetermineChanges() 
  -- returns true if set is active on any bar, otherwise returns false 
  local function GetActiveState( activeTable ) 
    local isActive = false
    for _, isActiveOnBar in pairs( activeTable )do
      isActive = isActive or isActiveOnBar
    end
    return isActive
  end

  -- create table with current active states 
  for setId, activeTable in pairs( self.activeOnBar ) do 
    self.activeState[setId] = GetActiveState(activeTable) 
  end

  local changeList = {}
  -- check all current sets 
  for setId, activeState in pairs( self.activeState ) do 
    if activeState then -- if they are currently active:
      if self.archive.activeState[setId] then   -- if they were aleady active
        for barName, _ in pairs (barList) do    -- check if active for each individual bar
          if self.archive.activeOnBar[setId][barName] ~= self.activeOnBar[setId][barName] then 
            changeList[setId] = LSD_CHANGE_TYPE_UPDATE  -- if at least one bar has changed --> updated
            break
          end
        end
      else   -- and weren't active before -> equipped
        changeList[setId] = LSD_CHANGE_TYPE_EQUIPPED
      end
    end
  end
  -- check, if all previously active sets are still active, otherwise -> unequipped
  for setId, archiveActiveState in pairs( self.archive.activeState ) do 
    if archiveActiveState and not self.activeState[setId] then 
      changeList[setId] = LSD_CHANGE_TYPE_UNEQUIPPED
    end
  end
  if self.debug and ExoyDev then 
    devMsg("SD", "determine changes") 
    d("archive activeOnBar list ")
    d( self.archive.activeOnBar )
    d("------------ End of archive activeOnBar list")
    d("archive activeState")
    d(self.archive.activeState)
    d("------------ End of archive activeState")
    d("current activeState")
    d(self.activeState)
    d("------------ End of current activeState list ")
    d("changeList") 
    local changeListDecoded = {}
    for setId, changeType in pairs(changeList) do 
      changeListDecoded[setId] = DecodeChangeType(changeType)
    end
    d(changeListDecoded)
    d("------------ End of changeList")
  end
  return changeList 
end

function SetDetector:FireCallbacks( changeList ) 
  if self.debug and ExoyDev then devMsg("SD - "..self.unitType, "fire callbacks") end
  
  -- initialize, because activeOnBar does not exist for completely unquipped sets
  local activeOnBody = false
  local activeOnFront = false
  local activeOnBack = false 
 
  for setId, changeType in pairs( changeList ) do 
    -- update activeOnBar bools for existing sets
    if changeType == LSD_CHANGE_TYPE_EQUIPPED or changeType == LSD_CHANGE_TYPE_UPDATE then 
      activeOnBody = self.activeOnBar[setId]["body"]
      activeOnFront = self.activeOnBar[setId]["front"]
      activeOnBack =  self.activeOnBar[setId]["back"]
    end

    CallbackManager.FireCallbacks( "SetChange", self.unitType, setId, 
     changeType, setId, self.unitTag, activeOnBody, activeOnFront, activeOnBack) 
  end
end


--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------- %% ]]
--[[ %% -- Group Manager -- %% ]]
--[[ %% ------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]

GroupManager.groupSets = {}

function GroupManager.UpdateData( charName, unitTag, data ) 

  if GroupManager.groupSets[charName] then 
    GroupManager.groupSets[charName]:UpdateData( data, unitTag ) 
  else 
    GroupManager.groupSets[charName] = SetDetector:New("group")
    GroupManager.groupSets[charName]:UpdateData( data, unitTag )
  end

end

--GroupSets[charName] = SetManager:New("group")  --- This will be put in GroupSets 

-- GroupManager activates/deactives functionality when a player is joining/leaving a group 
-- or group members change 
-- needs to make sure, companions do not cause any problems  
-- will stand in direct contact with the broadcast manager to keep track of the state of things for group member 
-- will initialize data clean up when group members leave or the player leaves a group all together 
-- (even if somebody rejoints again, there could have been a set change in the mean time, so i always have to check anyways)

-- knowing who has addon active 
-- communication with broadcast manager to wake up, go dormant 
-- providing a unitTag characterName map? 


--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ---------------------- %% ]]
--[[ %% -- BroadcastManager -- %% ]]
--[[ %% ---------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]

--- ToDo-List 
-- Save variables for toggle 
-- handshake for group 
--    >>> send out greeting when joining group/after a relog/ reloadui 
--    >>> only enable data sharing when received at least one response 
--    >>> activate data share if addon is dormant and and receiving a handshake 
--    >>> handle change in group composition 
--    >>> send information if settings change 
--- dormant, sleep, wake up 

--- information about a group member 
--[[ 
  ["charName"] as key 
    for each setId = {numEq, fb, bb}  
]]
  -- function to convert between received data and save array 
  -- function to check, if something changeed before sending data
  -- function to convert player data to send data 
  -- api for information about group 

  local DataMsg = {} 
  function BroadcastManager.Initialize() 
    BroadcastManager.LGB = LibGroupBroadcast 
    BroadcastManager.DataMsg = DataMsg:Initialize() 
  end


--[[ -------------- ]]
--[[ -- Data Msg -- ]]
--[[ -------------- ]]

function DataMsg:Initialize() 
  local LGB = LibGroupBroadcast
  self.handler = LGB:DeclareProtocol(42, "LibSetDetection_Data")
  local dataArray = LGB.CreateArrayField(LGB.CreateTableField("SetData", {
      LGB.CreateNumericField("id", { min = 0, max = 1023 }),
      LGB.CreateNumericField("body", { min = 0, max = 10 }),
      LGB.CreateNumericField("front", { min = 0, max = 2 }),
      LGB.CreateNumericField("back", { min = 0, max = 2 }),
    }), { minSize = 1, maxSize = 8 })
  self.handler:AddField(dataArray)
  self.handler:OnData(function(unitTag, data) self:OnIncomingMsg(unitTag, data) end)
  self.handler:Finalize()
  return self
end

function DataMsg:StartQueue() 
  -- start callLater for send 
  self.queue = zo_callLater( self.EndQueue, self.queueDuration )   
end

function DataMsg:UpdateQueue() 
  zo_removeCallLater( self.queue ) 
  self.queue = zo_callLater( self.EndQueue, self.queueDuration )
end

function DataMsg:EndQueue() 
  local data = self:SerilizeData(self.buffer) 
  self.handler:Send( data ) 
  self:CleanQueue() 
end

function DataMsg:CleanQueue() 
  self.buffer = {}  -- reset buffer for data transmission
  self.queue = nil  -- delete entry of callLater id 
end

function DataMsg:AddToQueue(setId, setData ) 
  if self.queue then 
    self:UpdateQueue() 
  else 
    self:StartQueue() 
  end 
  self.buffer[setId] = setData
end

function DataMsg:SendCurrentSetup( numEquip ) 
  --- why doe I get extended data, when the DataUpdate Event is happening? 
  local data = self:SerilizeData( numEquip ) 
  local sendData = {["SetData"] = {data[1]} }
  self.handler:Send( sendData ) 
end

function DataMsg:SerilizeData( data ) 
  -- format data for data broadcast
  local formattedData = {}
  for setId, setData in pairs( data ) do 
    table.insert(formattedData, {
      id = setId, 
      body = setData.body, 
      front = setData.front, 
      back = setData.back,
    } )
  end
  return formattedData
end

function DataMsg:DeserilizeData( rawData ) 
  local data = {}
  for _, setData in ipairs(rawData) do  
    data[setData.id] = {
      ["body"] = setData.body, 
      ["front"] = setData.front, 
      ["back"] = setData.back,
    }
  end  
  return data
end

function DataMsg:OnIncomingMsg(unitTag, rawData) 
  local charName = GetUnitName(unitTag)
  local data = self:DeserilizeData(rawData.SetData)
  d("message received") 
  d(rawData) 
  d(data)
  if charName == playerName then 
    GroupManager.UpdateData( charName, unitTag, data ) 
    --- detected a messsage was send 
  else 

    --- send data to group manager 
    GroupManager.UpdateData( charName, unitTag, data ) 
  end
end

--[[ -------------------- ]]
--[[ -- End of DataMsg -- ]]
--[[ -------------------- ]]


--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------ %% ]]
--[[ %% -- Slot Manager -- %% ]]
--[[ %% ------------------ %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]] 


function SlotManager:Initialize() 
  self.debug = false
  self.equippedGear = {} 
  for slotId, _ in pairs( equipSlotList ) do 
    self.equippedGear[slotId] = 0 
  end
  self.queueDuration = 3000 --- ToDo add setting for advanced user ? 
end


function SlotManager:UpdateLoadout() 
  if self.debug and ExoyDev then devMsg( "SM", "loadout update" ) end
  for slotId, _ in pairs (equipSlotList) do 
    self:UpdateSetId( slotId ) 
  end
  self:SendData()  
end


function SlotManager:UpdateSlot( slotId ) 
  if self.debug and ExoyDev then devMsg( "SM", "slot update "..equipSlotList[slotId] ) end 
  self:UpdateSetId( slotId ) 
  self:ResetQueue() 
end


function SlotManager:UpdateSetId( slotId )
    -- keeping track, which slot has which set
    self.equippedGear[slotId] = GetSetId(slotId)
    -- if two-handers, assigns setId of main-hand to off-hand  
    if IsWeaponSlot( slotId ) then
      self.equippedGear[EQUIP_SLOT_OFF_HAND] = GetSetId( EQUIP_SLOT_OFF_HAND )
      self.equippedGear[EQUIP_SLOT_BACKUP_OFF] = GetSetId( EQUIP_SLOT_BACKUP_OFF )
      if IsTwoHander(EQUIP_SLOT_MAIN_HAND) then
        self.equippedGear[EQUIP_SLOT_OFF_HAND] = GetSetId(EQUIP_SLOT_MAIN_HAND)
      end
      if IsTwoHander(EQUIP_SLOT_BACKUP_MAIN) then
        self.equippedGear[EQUIP_SLOT_BACKUP_OFF] = GetSetId(EQUIP_SLOT_BACKUP_MAIN)
      end
    end  
end


function SlotManager:ResetQueue() 
  if self.queueId then 
    zo_removeCallLater( self.queueId )
    if self.debug and ExoyDev then devMsg("SM", "reset queue") end 
  else 
    if self.debug and ExoyDev then devMsg("SM", "start queue") end
  end
  self.queueId = zo_callLater( function() 
    if self.debug and ExoyDev then devMsg("SM", "end queue") end
    self:SendData()
    self.queueId = nil 
  end, self.queueDuration ) 
end


function SlotManager:SendData() 
  local numEquip = {} 
  for barName, _ in pairs(barList) do  -- body, front, back 
    for slotId, _ in pairs( slotList[barName]) do 
      local setId = self.equippedGear[slotId] 
      numEquip[setId] = numEquip[setId] or { ["body"]=0, ["front"]=0, ["back"]=0 }
      numEquip[setId][barName] = numEquip[setId][barName] + 1
    end
  end 
  numEquip[0] = nil
  if self.debug and ExoyDev then 
    devMsg("SM", "relay data")
    d( ExtendNumEquipData(numEquip) )
    d("---------- end: relay data")
  end
  --PlayerSets:UpdateData( numEquip, "player" ) 
  --BroadcastManager.DataMsg:SendCurrentSetup( numEquip ) 
  CallbackManager.FireCallbacks( "DataUpdate", "player", nil, 
    "player",                    
    ExtendNumEquipData( numEquip ),   
    self.equippedGear ) 
end

--[[ %%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ---------------- %% ]]
--[[ %% -- ZOS Events -- %% ]]
--[[ %% ---------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%% ]]

local function OnSlotUpdate(_, _, slotId, _, _, _) 
  SlotManager:UpdateSlot(slotId)
end

local function OnArmoryOperation() 
  zo_callLater( function() SlotManager:UpdateLoadout() end, 1000)
end

local function OnInitialPlayerActivated() 
  EM:UnregisterForEvent( libName .."InitialPlayerActivated", EVENT_PLAYER_ACTIVATED)
  SlotManager:UpdateLoadout() 
end

--[[ %%%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% -------------------- %% ]]
--[[ %% -- Initialization -- %% ]]
--[[ %% -------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%%% ]]

local function Initialize() 
  local defaults = {
    ["debug"] = false, 
  }
  SV = ZO_SavedVars:NewAccountWide( "LibSetDetectionSV", 0, nil, defaults, "SavedVariables" )
  SV.debug = true
  SV.dev = true
  SlotManager:Initialize() 
  BroadcastManager.Initialize() 

  PlayerSets = SetDetector:New("player") 

  --- Register Events 
  EM:RegisterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, OnSlotUpdate )
  EM:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_BAG_ID, BAG_WORN)
  EM:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_IS_NEW_ITEM, false)
  EM:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_INVENTORY_UPDATE_REASON , INVENTORY_UPDATE_REASON_DEFAULT)
  EM:RegisterForEvent( libName.."InitialPlayerActivated", EVENT_PLAYER_ACTIVATED, OnInitialPlayerActivated )
  EM:RegisterForEvent( libName.."ArmoryChange", EVENT_ARMORY_BUILD_OPERATION_STARTED, OnArmoryOperation )
end

local function OnAddonLoaded(_, name) 
  if name == libName then 
    Initialize() 
    EM:UnregisterForEvent( libName, EVENT_ADD_ON_LOADED)
  end
end

EM:RegisterForEvent( libName, EVENT_ADD_ON_LOADED, OnAddonLoaded)


--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ----------------------- %% ]]
--[[ %% -- Exposed Functions -- %% ]]
--[[ %% ----------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]

--- Utility
function LibSetDetection.GetSetIdFromItemLink( itemlink ) 
  local _, _, _, _, _, setId = GetItemLinkSetInfo( itemlink )
  return setId
end

--- for both functions above, make unitTag:nilable and then 
--- provide data for everybody? 
function LibSetDetection.GetUnitActiveSets( unitTag )  
  -- returns tables with setIds for 
  -- activeOnBody, activeOnFront, activeOnBack   --- probably processing on the fly 
end 


function LibSetDetection.GetUnitEquippedSets( unitTag ) 
  -- returns tables with setIds for
  -- euippedOnBody, equippedOnFront, equippedOnBack --- probably processing on the fly
end


function LibSetDetection.HasSomebodySet( setId, unitType ) 
  -- check, if somebody in the group has a specific set 
  -- unit: optional: 
  -- if nil then check both types 
end


--[[ Exposed Functions of CallbackManager ]]
--- User Input: 
--    1. id (string - case sensitive): unique name (for each registryType/unitType) 
--    2. callback (function): called when appropriate callbacks fire
--    3. unitType:nilable (string - case sensitive): "player" or "group" or "all" (nil = "all") 
--    4. filter:nilable (optional for "SetChange") - table of filter values (setId), for registration or unregistration  

--EventSetChange( action, setId, unitTag, isActiveOnBody, isActiveOnFrontbar, isActiveOnBackbar)
--*action*: 0 = unequip, 1 = equip, 2 = activityChange 

--- "SetChanged" Event
--- Variables provided by Event: 
--    1. changeType (number):  
--    2. setId (number): 
--    3. unitTag (string): "player" or "group"..i  (except group tag that corresponds with player)
--    4. isActiveOnBody (bool)
--    5. isActiveOnFront (bool) 
--    6. isActiveOnBack (bool) 

function LibSetDetection.RegisterForSetChange( ... )
  return CallbackManager.UpdateRegistry( true, "SetChange", ...)
end

function LibSetDetection.UnregisterSetChange( ... ) 
  return CallbackManager.UpdateRegistry( false, "SetChange", ...)
end


--- different trigger for player and group 
-- player when slots change (ToDo) 
-- group when number at any bar changes
function LibSetDetection.RegisterForDataUpdate( ... ) 
  return CallbackManager.UpdateRegistry( true, "DataUpdate", ...)
end

function LibSetDetection.UnregisterDataUpdate( ... ) 
  return CallbackManager.UpdateRegistry( false, "DataUpdate", ...)
end


--[[ ------------------- ]]
--[[ -- Chat Command  -- ]]
--[[ ------------------- ]]

SLASH_COMMANDS["/lsd"] = function( input ) 

  local cmdList = {
    ["equip"] = "output list of equipped sets",
    ["setid"] = "outputs id of all sets, that include search string",
  }

  --deserializ input 
  input = string.lower(input) 
  local param = {}
  for str in string.gmatch(input, "%S+") do
    table.insert(param, str)
  end

  local cmd = table.remove(param, 1) 
  if cmd == ""  then 
    d("[LibSetDetection] - command overview")
    for cmdName, cmdInfo in pairs( cmdList ) do 
      d( zo_strformat("<<1>> - <<2>>", cmdName, cmdInfo) )
    end
    d("--------------------")
  elseif cmd == "equip" then 
    local OutputSets = function(barName) 
      d("--- "..barName.." --- ")
      for slotId, slotName in pairs( slotList[string.lower(barName)] ) do 
        local setId = GetSetId( slotId )
        d( zo_strformat("<<1>>: <<2>> (<<3>>)", slotName, GetSetName(setId) , setId ) )
      end  
    end
    d("[LibSetDetection] equipped sets:")
    OutputSets("Body") 
    OutputSets("Front") 
    OutputSets("Back")
    d("--------------------")
  elseif cmd == "setid" then
    if IsString(param[1]) and param[1] ~= "" then 
      d("[LibSetDetection] matching set ids:")
      for i=0,1023,1 do 
        local setName = GetSetName(i)
        if string.find( string.lower(setName), string.lower(param[1]) ) then 
          d( zo_strformat("<<1>> - <<2>>", i, setName))
        end
      end
      d("--------------------")
    else 
      d("[LibSetDetection] search string is missing ")
    end
  else 
    if cmd == "dev" and ExoyDev  then 
      --- call development functions 
      --Development.OutputEquippedSets()
      Development.OutputPlayerSets()    
    else 
      d("[LibSetDetection] command unknown")
    end
  end

end


--[[ --------------------------- ]]
--[[ -- Development Functions -- ]]
--[[ --------------------------- ]]

function Development.OutputEquippedSets() 
  d(SlotManager.equippedGear)
end

function Development.OutputPlayerSets() 
  d(PlayerSets.numEquip)
end
