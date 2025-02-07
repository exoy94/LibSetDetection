--[[ ------------------- ]]
--[[ -- ToDo / Notes  -- ]]
--[[ ------------------- ]]

--- check if the setId is provided when the mystical is equipped, that disables all set effects 
--- referenzen mit doppel punkt übergeben nur pointer, mit punkt hängt es davon ab, ob der tabellen 
---   eintrag vorher schon existiert (dann referenz auf den eintrag), ansonsten ist es nur ein sybolic value 
---   und es wird jedesmal danach gesucht 




LibSetDetection = LibSetDetection or {}
local libName = "LibSetDetection"
local libVersion = 4
local libDebug = false 
local playerName = GetUnitName("player") 
local EM = GetEventManager() 

--[[ -------------- ]]
--[[ -- Entities -- ]]
--[[ -------------- ]]
 
local CallbackManager = {}  -- CM 
local BroadcastManager = {} -- BM
local SetManager = {}      -- SD 
local GroupManager = {}     -- GM
local PlayerSets = {}       -- PS
local SlotManager = {}      -- SM       
local Development = {}      -- Dev

--[[ --------------- ]]
--[[ -- Templates -- ]]
--[[ --------------- ]]

local function Template_BarListSubtables( initType, initBody, initFront, initBack )
  if initType == "table" then return { ["body"] = {}, ["front"] = {}, ["back"] = {} } end
  if initType == "numeric" then 
    _initBody = initBody or 0 
    _initFront = initFront or 0 
    _initBack = initBack or 0
    return { ["body"] = _initBody, ["front"] = _initFront, ["back"] = _initBack }
  end
end


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

local barList = {"body", "front", "back"}

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

local function ConvertCharToUnitName( charName ) 
  return zo_strformat( SI_UNIT_NAME, charName )
end

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
  local exception = {
    [695]= 5, ---check id
  }
  
  local _, _, _, _, _, maxEquip = GetItemSetInfo( setId )

  if exception[setId] then
    maxEquip = exception[setId]
  end
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

local function ExtendNumEquipData( numEquip ) 
  local numEquipExtended = ZO_DeepTableCopy(numEquip)
  for setId, _ in pairs( numEquip) do
    numEquipExtended[setId].setName = GetSetName(setId)
    numEquipExtended[setId].maxEquip = GetMaxEquip(setId) 
  end
  return numEquipExtended
end

--[[ ----------- ]]
--[[ -- Debug -- ]] 
--[[ ----------- ]]

local function debugMsg(id, msg) 
  d( zo_strformat("[<<1>> LSD - <<2>>] <<3>>", GetTimeString(), id, msg) )  
end

local function DecodeChangeType( changeType ) 
  local changeStr = {"unequipped", "equipped", "updated"}
  return changeStr[changeType]
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

function CallbackManager:Initialize() 
  self.debug = true
  self.registry = {
    ["playerSetChange"] = {}, 
    ["groupSetChange"] = {}, 
    ["playerUpdateData"] = {}, 
    ["groupUpdateData"] = {}, 
  }
end

CallbackManager.results = {
  [CALLBACK_RESULT_SUCCESS] = "success",
  [CALLBACK_RESULT_INVALID_CALLBACK] = "invalid callback",
  [CALLBACK_RESULT_INVALID_UNITTYPE] = "invalid unitType",
  [CALLBACK_RESULT_INVALID_FILTER] = "invalid filter", 
  [CALLBACK_RESULT_INVALID_NAME] = "invalid name",
  [CALLBACK_RESULT_DUPLICATE_NAME] = "duplicate name",
  [CALLBACK_RESULT_UNKNOWN_NAME] = "unkown name",
}




function CallbackManager:UpdateRegistry(action, registryType, uniqueId, callback, unitType, filter)

  if unitType == "all" or not unitType then   -- if unitType is nil or "all" execute function for "player" and "group"
    local resultPlayer = self:UpdateRegistry(action, registryType, uniqueId, callback, "player", filterTable)
    local resultGroup = self:UpdateRegistry(action, registryType, uniqueId, callback, "group", filterTable)
    return resultPlayer, resultGroup
  end
  --- verify general user inputs
  if not IsFunction(callback) then return CALLBACK_RESULT_INVALID_CALLBACK end
  if not IsString(uniqueId) then return CALLBACK_RESULT_INVALID_NAME end 
  if not unitType == "player" or unitType == "group" then return CALLBACK_RESULT_INVALID_UNITTYPE end 
  --- set change registry
  local registryName = unitType..registryType
  if registryType == "SetChange" then 
    return self:UpdateSetChangeRegistry( action, registryName, uniqueId, callback, filter ) 
  end 
  --- data update registry
  if registryType == "DataUpdate" then 
    return self:UpdateDataUpdateRegistry( action, registryName, uniqueId, callback, filter ) 
  end
end   -- End of "UpdateRegistry"



function CallbackManager:UpdateSetChangeRegistry( action, registryName, uniqueId, callback, filter ) 
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
    self.registry[registryName][filterId] = self.registry[registryName][filterId] or {}
    local callbackList = self.registry[registryName][filterId]
    if action then    -- registration
      if callbackList[uniqueId] then return CALLBACK_RESULT_DUPLICATE_NAME end
      if self.debug then d(zo_strformat("Reigster '<<1>>' in <<2>> (<<3>>)", uniqueId, registryName, filterId)) end
      callbackList[uniqueId] = callback 
    else  -- unregistration
      if not callbackList[uniqueId] then return CALLBACK_RESULT_UNKNOWN_NAME end 
      callbackList[uniqueId] = nil
    end 
  end
  return CALLBACK_RESULT_SUCCESS
end   -- End of "UpdateSetChangeRegistry"


function CallbackManager:UpdateDataUpdateRegistry( action, registryName, uniqueId, callback, filter ) 
  --- validate filter
  if filter then return CALLBACK_RESULT_INVALID_FILTER end 
  --- update registry
  local callbackList = self.registry[registryName] 
  if action then -- registration
    if callbackList[uniqueId] then return CALLBACK_RESULT_DUPLICATE_NAME end
    callbackList[uniqueId] = callback 
  else -- unregistration
    if not callbackList[uniqueId] then return CALLBACK_RESULT_UNKNOWN_NAME end 
    callbackList[uniqueId] = nil
  end
end   -- UpdateDataUpdateRegistry


function CallbackManager:FireCallbacks( eventType, unitType, setId, ... ) 
  
  local function _FireCallbacks(callbackList, ...) 
    if ZO_IsTableEmpty( callbackList ) then return end 
    for _, callback in pairs( callbackList ) do 
      callback(...) 
    end
  end
  
  local registryName = unitType..eventType

  if eventType == "DataUpdate" then 
    -- unitTag, numEquipExtended, equippedGear
    if libDebug and self.debug then 
      local p = {...} 
      debugMsg("CM", zo_strformat("DataUpdate for <<1>>", p[1]) )
    end
    _FireCallbacks( self.registry[registryName],... )

  elseif eventType == "SetChange" then 
    -- changeType, unperfSetId, unitTag, isActiveOnBody, isActiveOnFront, isActiveOnBack
    if libDebug and self.debug then --debug for "SetChange Event"
      local p = {...}
      local msgStart = zo_strformat( "<<1>> for <<2>>: <<3>> (<<4>>) ", eventType, p[3], DecodeChangeType(p[1]), p[1] ) 
      local msgEnd = zo_strformat("<<1>> (<<2>>) - {<<3>>, <<4>>, <<5>>}", 
        GetSetName( p[2] ), p[2], p[4] and 1 or 0, p[5] and 1 or 0, p[6] and 1 or 0 )
        debugMsg("CM", msgStart..msgEnd )
    end
    _FireCallbacks( self.registry[registryName][0], ...)
    _FireCallbacks( self.registry[registryName][setId], ...)
  end

end


--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------ %% ]]
--[[ %% -- Set Manager --- %% ]]
--[[ %% ------------------ %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]

SetManager.__index = SetManager 

function SetManager:New( unitType, unitTag )
  -- unitType ("player" or "group")
  -- unitTag at the time of creation
  if unitType == "player" then 
    self.debug = true   --- entity debug toogle
  end
  if unitType == "group" then 
    self.debug = false     --- entity debug toogle
  end
  self.unitType = unitType or "empty"
  self.numEquip = {} 
  self.activeOnBar = {}
  self.activeState = {}
  return self
end


function SetManager:UpdateData( newData, unitTag )
  self.debugHeader = zo_strformat( "SM <<1>> (<<2>>)", unitTag, GetUnitName(unitTag) )
  if libDebug and self.debug then debugMsg( self.debugHeader, "update data" ) end
  self.unitTag = unitTag -- ensures always correct unitTag
  self:InitTables( newData )  -- updates archive and resets current 
  self:ConvertDataToUnperfected()   -- all perfected pieces are handled as unperfected  
  self:AnalyseData()  -- determines, which sets are active 
  local changeList = self:DetermineChanges()  -- determine, what has changed (un-)equip/ update
  self:FireCallbacks( changeList )  -- fire callbacks according to detected changes
end


function SetManager:InitTables( data ) 
  if libDebug and self.debug then debugMsg( self.debugHeader, "initialize tables") end
  self.archive = {} 
  self.archive["numEquip"] = ZO_ShallowTableCopy(self.numEquip)
  self.archive["activeOnBar"] = ZO_ShallowTableCopy(self.activeOnBar)
  self.archive["activeState"] = ZO_ShallowTableCopy(self.activeState)
  self.numEquip = data
  self.activeOnBar = {}
  self.activeState = {}
end


function SetManager:ConvertDataToUnperfected() 
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
  if libDebug and self.debug then 
    debugMsg( self.debugHeader, "convert data to unperfected")
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


function SetManager:AnalyseData() 
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
  if libDebug and self.debug then 
    debugMsg( self.debugHeader, "analyse data") 
    d("current activeOnBar list")
    d( self.activeOnBar )
    d("------------ End of current activeOnBar list")
  end
end


function SetManager:DetermineChanges() 
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
  -- create table with changes 
  local changeList = {}
  for setId, activeState in pairs( self.activeState ) do -- check all equipped sets
    if activeState then -- if they are currently active:
      if self.archive.activeState[setId] then   -- if they were aleady active
        for _, barName in pairs (barList) do    -- check if active for each individual bar
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
  if libDebug and self.debug then 
    debugMsg( self.debugHeader, "determine changes") 
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


function SetManager:FireCallbacks( changeList ) 
  if libDebug and self.debug then debugMsg( self.debugHeader, "fire callbacks") end
  for setId, changeType in pairs( changeList ) do 
     -- initialize, because activeOnBar does not exist for completely unquipped sets
    local activeOnBody = false
    local activeOnFront = false
    local activeOnBack = false 
    -- update activeOnBar bools for existing sets
    if changeType == LSD_CHANGE_TYPE_EQUIPPED or changeType == LSD_CHANGE_TYPE_UPDATE then 
      activeOnBody = self.activeOnBar[setId]["body"]
      activeOnFront = self.activeOnBar[setId]["front"]
      activeOnBack =  self.activeOnBar[setId]["back"]
    end
    CallbackManager:FireCallbacks( "SetChange", self.unitType, setId, 
      changeType, setId, self.unitTag, activeOnBody, activeOnFront, activeOnBack) 
  end
end


function SetManager:HasSet(setId) 
  local _activeState = self.activeState[setId] or false 
  local _activeOnBody = self.activeOnBar[setId] and self.activeOnBar["body"] or false 
  local _activeOnFront = self.activeOnBar[setId] and self.activeOnBar["front"] or false 
  local _activeOnBack = self.activeOnBar[setId] and self.activeOnBar["back"] or false 
  return _activeState, _activeOnBody, _activeOnFront, _activeOnBack
end 


function SetManager:GetActiveSets() 
  local _stateList = {}
  local _onBarList = Template_BarListSubtables{"table"}
  for setId, activeState in pairs( self.activeState ) do 
    if activeState then table.insert(_stateList, setId) end
    for _, barName in pairs(barList) do 
      if self.activeOnBar[setId][barName] then 
        table.insert(_onBarList[barName], setId)
      end
    end
  end
  return _stateList, _onBarList["body"], _onBarList["front"], _onBarList["back"]
end


function SetManager:GetNumEquip(setId)
  local _numEquip = Template_BarListSubtables("numeric")
  for _, barName in pairs(barList) do 
    _numEquip[barName] = self.numEquip[setId][barName]
  end
  return _numEquip["body"], numEquip["front"], numEquip["back"]  
end


function SetManager:GetEquippedSets() 
  return ExtendNumEquipData( self.numEquip )
end


--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------- %% ]]
--[[ %% -- Group Manager -- %% ]]
--[[ %% ------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]


function GroupManager:Initialize() 
  self.debug = true
  self.groupSets = {}

  --- local functions reference 
  --local function _OnGroupUpdate() self:OnGroupMemberUpdate() end
  local function _OnGroupMemberJoined(...) self:OnGroupMemberJoined(...) end
  local function _OnGroupMemberLeft(...) self:OnGroupMemberLeft(...) end 

  --- Events 
  --EM:RegisterForEvent(libName, EVENT_GROUP_UPDATE, _OnGroupUpdate)
  EM:RegisterForEvent(libName, EVENT_GROUP_MEMBER_JOINED, _OnGroupMemberJoined )
  EM:RegisterForEvent(libName, EVENT_GROUP_MEMBER_LEFT, _OnGroupMemberLeft )
end


function GroupManager:OnGroupUpdate()
  -- unitTags where changed, dont know yet if I need to do anything at that point 
end


function GroupManager:OnGroupMemberJoined(_, charName, _, isLocalPlayer) 
  if isLocalPlayer then 
    --- can use to determine, that i either entered a group or created one 
    --- when I join a group with members already, only ny name comes up 
  else 
    local unitName = zo_strformat( SI_UNIT_NAME, charName ) -- aligns format with unit name for unitTag

  end
end


function GroupManager:OnGroupMemberLeft(_, charName, _, isLocalPlayer)
  if isLocalPlayer then 

  else 
    local unitName = zo_strformat( SI_UNIT_NAME, charName )   -- aligns format with unit name for unitTag
    --- occurs when i leave group in some way 
    --- when I leave, event is also triggered 
      self.groupSets[unitName] = nil  -- remove SetManager instance
  end  
end


function GroupManager:UpdateSetData( unitName, unitTag, data ) 
  local _gs = self.groupSets  
  if _gs[unitName] then 
    _gs[unitName]:UpdateData( data, unitTag ) 
  else 
    _gs[unitName] = SetManager:New("group")
    _gs[unitName]:UpdateData( data, unitTag )
  end
end


function GroupManager:GetSetManager( unitTag ) 
  local unitName = GetUnitName(unitTag)
  -- check if there exists a set manager 
  if self.groupSets[unitName] then 
    return self.groupSets[unitName]
  else 
    --return DefaultSetManager --- entity, that returns default values for all tables 
  end

end 

-- GroupManager activates/deactives functionality when a player is joining/leaving a group 
-- or group members change 
-- needs to make sure, companions do not cause any problems  
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




--[[ -------------- ]]
--[[ -- Data Msg -- ]]
--[[ -------------- ]]

DataMsg = {}

function DataMsg:Initialize() 
  if not LibGroupBroadcast then return end
  local LGB = LibGroupBroadcast
  self.handlerId = LGB:RegisterHandler("IDK", "LibSetDetection")
  self.handler = LGB:DeclareProtocol(self.handlerId, 42, "LibSetDetection_Data")
  local dataArray = LGB.CreateArrayField( LGB.CreateTableField("SetData", {
      LGB.CreateNumericField("id", { minValue = 0, maxValue = 1023 }),
      LGB.CreateNumericField("body", { minValue = 0, maxValue = 10 }),
      LGB.CreateNumericField("front", { minValue = 0, maxValue = 2 }),
      LGB.CreateNumericField("back", { minValue = 0, maxValue = 2 }),
    }), { minLength = 1, maxLength = 8 } )
  self.handler:AddField(dataArray)
  self.handler:AddField( LGB.CreateFlagField("request") )
  local function _OnIncomingMsg(...)
    self:OnIncomingMsg(...)
  end
  self.handler:OnData( _OnIncomingMsg )  
  self.sucessfullFinalized = self.handler:Finalize()
  return self
end

-- /script d(LibSetDetection.output)

function DataMsg:SendSetup( numEquip ) 
  local data = self:SerilizeData( numEquip ) 
  local sendData = {
    ["SetData"] = data,
    ["request"] = true,
  }
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
  local unitName = GetUnitName(unitTag)
  local data = self:DeserilizeData(rawData.SetData)
  d(rawData.request)
  if ExoyDev then d( zo_strformat("Received Data from <<1>> (<<2>>)", GetUnitName(unitTag), unitTag ) ) end
  if unitName == playerName then 
    GroupManager:UpdateSetData( unitName, unitTag, data ) 
  else 
    GroupManager:UpdateSetData( unitName, unitTag, data ) 
  end
end


--[[ ----- End of DataMsg ----- ]]

function BroadcastManager:Initialize() 
  self.DataMsg = DataMsg:Initialize() 
end

function BroadcastManager:SendData(numEquip) 
--- toDo for early outs
  self.DataMsg:SendData(numEquip)
end



--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------ %% ]]
--[[ %% -- Slot Handler -- %% ]]
--[[ %% ------------------ %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]] 


function SlotManager:Initialize() 
  self.debug = false   --- entity debug toogle
  self.equippedGear = {} 
  for slotId, _ in pairs( equipSlotList ) do 
    self.equippedGear[slotId] = 0 
  end
  self.queueDuration = 3000 --- ToDo add setting for advanced user ? 
end


function SlotManager:UpdateLoadout() 
  if libDebug and self.debug then debugMsg( "SM", "loadout update" ) end
  for slotId, _ in pairs (equipSlotList) do 
    self:UpdateSetId( slotId ) 
  end
  self:SendData()  
end


function SlotManager:UpdateSlot( slotId ) 
  if libDebug and self.debug then debugMsg( "SM", "slot update "..equipSlotList[slotId] ) end 
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
    if libDebug and self.debug then debugMsg("SM", "reset queue") end 
  else 
    if libDebug and self.debug then debugMsg("SM", "start queue") end
  end
  self.queueId = zo_callLater( function() 
    if libDebug and self.debug then debugMsg("SM", "end queue") end
    self:SendData()
    self.queueId = nil 
  end, self.queueDuration ) 
end


function SlotManager:SendData() ---rename
  local numEquip = {} 
  for _, barName in pairs(barList) do  -- body, front, back 
    for slotId, _ in pairs( slotList[barName]) do 
      local setId = self.equippedGear[slotId] 
      numEquip[setId] = numEquip[setId] or Template_BarListSubtables("numeric") 
      numEquip[setId][barName] = numEquip[setId][barName] + 1
    end
  end 
  numEquip[0] = nil
  if libDebug and self.debug then 
    debugMsg("SM", "relay data")
    d( ExtendNumEquipData(numEquip) )
    d("---------- end: relay data")
  end
  PlayerSets:UpdateData( numEquip, "player" ) 
  BroadcastManager.DataMsg:SendSetup( numEquip ) 
  CallbackManager:FireCallbacks("DataUpdate", "player", nil, 
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

  libDebug = ExoyDev and true or libDebug 

  CallbackManager:Initialize()
  BroadcastManager:Initialize() 
  GroupManager:Initialize()
  SlotManager:Initialize() 

  PlayerSets = SetManager:New("player") 

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



--[[ %%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% --------------- %% ]]
--[[ %% -- Interface -- %% ]]
--[[ %% --------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%% ]]


local function ReadData( unitTag, setId, funcName ) 
  local SM
  if unitTag == "player" then 
    SM = PlayerSets
  else 
    SM = GroupManager:GetSetManager( unitTag ) 
  end
  return SM[funcName](SM, setId)
end


local function AccessSetManager(unitTag, setId, funcName)
  unitTag = unitTag or "player"
  if unitTag == "all" then 
    local playerData = {ReadData("player", setId, funcName)}
    local groupData  = {AccessSetManager("group", setId, funcName)}
    local combinedData = groupData  
    combinedData.player = playerData 
    return combinedData
  end
  if unitTag == "group" then 
    local groupData = {} 
    local groupResult = {}
    for i=1,GetGroupSize() do 
      local tag = GetGroupUnitTagByIndex( tag ) 
      if IsUnitPlayer(tag) then 
        groupData[tag] = {ReadData(tag, setId, funcName)}
      end
    end
    return groupData
  end 
  -- validate unitTag by checken for name of corresponding unit
  local unitName = GetUnitName(unitTag) 
  if not unitName or unitName == "" then return nil end 
  return ReadData(unitTag, setId, funcName)
end


--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ----------------------- %% ]]
--[[ %% -- Exposed Functions -- %% ]]
--[[ %% ----------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]

---Input 
-- *unitTag*: for which unit(s) the data are to be provided
--    + all - player and all group member (outputs table of data)
--    + group - all group members (outputs table of data)
--    + player - only the player 
--    + group..i - specific group member

function LibSetDetection.HasSet( setId, unitTag )
  return AccessSetManager( unitTag, setId, "HasSet")
end

function LibSetDetection.GetActiveSets(unitTag) 
  return AccessSetManager(unitTag, nil, "GetActiveSets")
end

function LibSetDetection.GetNumEquip(setId, unitTag) 
  return AccessSetManager(unitTag, setId, "GetNumEquip")  
end

function LibSetDetection.GetEquippedSets(unitTag) 
  return AccessSetManager(unitTag, nil, "GetEquippedSets")   
end


--- Utility
function LibSetDetection.GetSetIdFromItemLink( itemlink ) 
  local _, _, _, _, _, setId = GetItemLinkSetInfo( itemlink )
  return setId
end


--- Advanced 
function LibSetDetection.GetPlayerEquippedGear() 
  return SlotManager.equippedGear 
end


function LibSetDetection.GetUnitRawNumEquip() -- return data while still separating bettween normal and perf

end


--- Legacy (only for player) 
function LibSetDetection.GetEquippedSetsTable() 
  local PS = PlayerSets
  local returnTable = {}
  for setId, _ in pairs( PlayerSets.activeState ) do 
    local setData = {}
    setData.name = GetSetName( setId ) 
    setData.maxEquipped = GetMaxEquip( setId ) 
    setData.numEquipped = PS.numEquip[setId] 
    setData.activeBar = PS.activeOnBar[setId]
    returnTable[setId] = setData 
  end
  return returnTable
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
  return CallbackManager:UpdateRegistry( true, "SetChange", ...)
end

function LibSetDetection.UnregisterSetChange( ... ) 
  return CallbackManager:UpdateRegistry( false, "SetChange", ...)
end


--- different trigger for player and group 
-- player when slots change (ToDo) 
-- group when number at any bar changes
function LibSetDetection.RegisterForDataUpdate( ... ) 
  return CallbackManager:UpdateRegistry( true, "DataUpdate", ...)
end

function LibSetDetection.UnregisterDataUpdate( ... ) 
  return CallbackManager:UpdateRegistry( false, "DataUpdate", ...)
end


--[[ ------------------- ]]
--[[ -- Chat Command  -- ]]
--[[ ------------------- ]]

SLASH_COMMANDS["/lsd"] = function( input ) 

  local cmdList = {
    ["equip"] = "output list of equipped sets",
    ["setid"] = "outputs id of all sets, that include search string",
    ["debug"] = "toggles global debug variable"
  }

  --deserializ input 
  input = string.lower(input) 
  local param = {}
  for str in string.gmatch(input, "%S+") do
    table.insert(param, str)
  end

  local cmd = table.remove(param, 1) 

  
  if not cmd or cmd == ""  then 
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
  elseif cmd == "debug" then 
    libDebug = not libDebug 
    d( zo_strformat("[LibsetDetection] Debug switched > <<1>> <", libDebug and "on" or "off"))
  else 
    if cmd == "dev" and ExoyDev then 
      --- call development functions 
      --Development.OutputEquippedSets()
      --Development.OutputPlayerSets()    
      if param[1] == "registry" then 
        Development.OutputRegistry()
      elseif param[1] == "groupsets" then 
        Development.OutputGroupManager()         
      end
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

function Development.OutputRegistry()
  d("LSD - Output Registry") 
  d(CallbackManager.registry)
end

function Development.OutputGroupManager()
  d(GroupManager.groupSets)
end