LibSetDetection = LibSetDetection or {}

local libName = "LibSetDetection"
local libVersion = 4
local libDebug = false 
local playerName = GetUnitName("player") 
local EM = GetEventManager() 



--[[ ----------------------- ]]
--[[ -- Internal Entities -- ]]
--[[ ----------------------- ]]
 
local BroadcastManager = {} 
local CallbackManager = {}   
local GroupManager = {}     
local SetManager = {}        
local SlotManager = {}       
local PlayerSets = {}       
local EmptySetManager = {}  
local Development = {}      



--[[ --------------- ]]
--[[ -- Templates -- ]]
--[[ --------------- ]]

local function Template_SlotCategorySubtables( initType, initBody, initFront, initBack )
  if initType == "table" then return { ["body"] = {}, ["front"] = {}, ["back"] = {} } end
  if initType == "numeric" then 
    _initBody = initBody or 0 
    _initFront = initFront or 0 
    _initBack = initBack or 0
    return { ["body"] = _initBody, ["front"] = _initFront, ["back"] = _initBack }
  end
end



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

local function InvertTable( t ) 
  local invertedT = {} 
  for k,v in pairs(t) do 
    invertedT[v] = k 
  end
  return invertedT
end

local function MergeTables(t1, t2)
  local t = {}
  for k, v in pairs(t1) do
     t[k] = v
  end
	for k, v in pairs(t2) do
	   t[k] = v
	end
	return t
end



--[[ ---------------------- ]]
--[[ -- Global Variables -- ]]
--[[ ---------------------- ]]
 
LSD_CHANGE_TYPE_DEACTIVATED = 0 ---DEACTIVATED
LSD_CHANGE_TYPE_ACTIVATED = 1 
LSD_CHANGE_TYPE_UPDATE = 2

LSD_UNIT_TYPE_PLAYER = 1 
LSD_UNIT_TYPE_GROUP = 2
LSD_UNIT_TYPE_ALL = 3
LSD_UNIT_TYPE_GROUP_MEMBER = 4

LSD_EVENT_SET_CHANGE = 1 
LSD_EVENT_DATA_UPDATE = 2

--[[ --------------------- ]]
--[[ -- Local Variables -- ]]
--[[ --------------------- ]]

local slotCategories = {"body", "front", "back"}

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


local weaponSlotList = MergeTables( slotList["front"], slotList["back"] )
local equipSlotList = MergeTables( slotList["body"], weaponSlotList )


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


local exceptionList = {
  [695] = { ["maxEquip"] = 5 }  -- Shattered-Fate
}


--- result code definition for callback manager
local REGISTRY_RESULT_SUCCESS = 0 
local REGISTRY_RESULT_INVALID_EVENT = 1
local REGISTRY_RESULT_INVALID_CALLBACK = 2 
local REGISTRY_RESULT_INVALID_UNIT_TYPE = 3 
local REGISTRY_RESULT_INVALID_FILTER = 4
local REGISTRY_RESULT_INVALID_NAME = 5
local REGISTRY_RESULT_DUPLICATE_NAME = 6
local REGISTRY_RESULT_UNKNOWN_NAME = 7

local SET_TYPE_NORMAL = 0 
local SET_TYPE_MYSTICAL = 1 
local SET_TYPE_UNDAUNTED = 2 
local SET_TYPE_WEAPON = 3

local eventList = {
  [LSD_EVENT_SET_CHANGE] = "SetChange", 
  [LSD_EVENT_DATA_UPDATE] = "DataUpdate",
}

local unitTypeList = {
  [LSD_UNIT_TYPE_PLAYER] = "player", 
  [LSD_UNIT_TYPE_GROUP] = "group", 
  [LSD_UNIT_TYPE_ALL] = "all", 
}

local changeTypeList = {
  [LSD_CHANGE_TYPE_DEACTIVATED] = "unequipped", 
  [LSD_CHANGE_TYPE_ACTIVATED] = "activated", 
  [LSD_CHANGE_TYPE_UPDATE] = "update",
}


--[[ -------------------------------- ]]
--[[ -- Specific Utility Functions -- ]]
--[[ -------------------------------- ]]

local function CheckException(setId, attribute) 
  if not setId then return exceptionList end  -- returns entire list, if no setId is provided
  local hasExceptions = exceptionList[setId]  -- checks if there is an entry for the specific set
  if not attribute then return hasExceptions end  -- returns all entries for specific set 
  if not hasExceptions then return end  -- returns nil, if there are no entries
  local hasSpecificException = hasExceptions[attribute] -- checks for specific entry, if provided
  return hasSpecificException  -- returns the specific entry or nil
end


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
  local _, _, _, _, _, maxEquip = GetItemSetInfo( setId ) 
  maxEquip = CheckException(setId, "maxEquip") or maxEquip
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


function CallbackManager:UpdateRegistry(action, eventId, uniqueId, callback, unitType, filter)
  
  if unitType == LSD_UNIT_TYPE_ALL then   -- if unitType is nil or "all" execute function for "player" and "group"
    local resultPlayer = self:UpdateRegistry(action, eventId, uniqueId, callback, LSD_UNIT_TYPE_PLAYER, filter)
    local resultGroup = self:UpdateRegistry(action, eventId, uniqueId, callback, LSD_UNIT_TYPE_GROUP, filter)
    return resultPlayer, resultGroup
  end

  local registryType = eventList[eventId] 
  local unitTypeStr = unitTypeList[unitType]

  if not IsString(uniqueId) then return REGISTRY_RESULT_INVALID_NAME end
  if not registryName then return REGISTRY_RESULT_INVALID_EVENT end
  if not unitTypeStr then return REGISTRY_RESULT_INVALID_UNIT_TYPE end

    --- set change registry
  local registryName = unitTypeStr..registryType
  if eventId == LSD_EVENT_SET_CHANGE then 
    return self:UpdateSetChangeRegistry( action, registryName, uniqueId, callback, filter ) 
  end 
  --- data update registry
  if eventId == LSD_EVENT_DATA_UPDATE then 
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
  if not IsValidSetChangeFilter() then return REGISTRY_RESULT_INVALID_FILTER end 
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
      if callbackList[uniqueId] then return REGISTRY_RESULT_DUPLICATE_NAME end
      if IsFunction(callback) then 
        if self.debug then d(zo_strformat("Reigster '<<1>>' in <<2>> (<<3>>)", uniqueId, registryName, filterId)) end
        callbackList[uniqueId] = callback 
      else 
        return REGISTRY_RESULT_INVALID_CALLBACK 
      end
    else  -- unregistration
      if not callbackList[uniqueId] then return REGISTRY_RESULT_UNKNOWN_NAME end 
      callbackList[uniqueId] = nil
    end 
  end
  return REGISTRY_RESULT_SUCCESS
end   -- End of "UpdateSetChangeRegistry"


function CallbackManager:UpdateDataUpdateRegistry( action, registryName, uniqueId, callback, filter ) 
  --- validate filter
  if filter then return REGISTRY_RESULT_INVALID_FILTER end 
  --- update registry
  local callbackList = self.registry[registryName] 
  if action then -- registration
    if callbackList[uniqueId] then return REGISTRY_RESULT_DUPLICATE_NAME end
    if IsFunction(callback) then 
      callbackList[uniqueId] = callback 
    else 
      return REGISTRY_RESULT_INVALID_CALLBACK 
    end
    callbackList[uniqueId] = callback 
  else -- unregistration
    if not callbackList[uniqueId] then return REGISTRY_RESULT_UNKNOWN_NAME end 
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
      local msgStart = zo_strformat( "<<1>> for <<2>>: <<3>> (<<4>>) ", eventType, p[3], changeTypeList[p[1]], p[1] ) 
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

function SetManager:New( unitType )
  local SM = setmetatable({}, SetManager) 
  --local SM = ZO_DeepTableCopy(SetManager) 
  -- unitType ("player" or "group")
  -- unitTag at the time of creation
  if unitType == "player" then 
    SM.debug = false   --- entity debug toogle
  end
  if unitType == "group" then 
    SM.debug = false     --- entity debug toogle
  end
  SM.unitType = unitType or "empty"
  SM.numEquip = {} 
  SM.activeOnBar = {}
  SM.activeState = {}
  return SM
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
      for slotCategory, numEquip in pairs( self.numEquip[perfSetId] ) do 
        numEquipTemp[unperfSetId][slotCategory] = numEquipTemp[unperfSetId][slotCategory] + numEquip
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
        for _, category in pairs (slotCategories) do    -- check if active for each individual bar
          if self.archive.activeOnBar[setId][category] ~= self.activeOnBar[setId][category] then 
            changeList[setId] = LSD_CHANGE_TYPE_UPDATE  -- if at least one bar has changed --> updated
            break
          end
        end
      else   -- and weren't active before -> equipped
        changeList[setId] = LSD_CHANGE_TYPE_ACTIVATED
      end
    end
  end
  -- check, if all previously active sets are still active, otherwise -> unequipped
  for setId, archiveActiveState in pairs( self.archive.activeState ) do 
    if archiveActiveState and not self.activeState[setId] then 
      changeList[setId] = LSD_CHANGE_TYPE_DEACTIVATED
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
      changeListDecoded[setId] = changeTypeList[changeType]
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
    if changeType == LSD_CHANGE_TYPE_ACTIVATED or changeType == LSD_CHANGE_TYPE_UPDATE then 
      activeOnBody = self.activeOnBar[setId]["body"]
      activeOnFront = self.activeOnBar[setId]["front"]
      activeOnBack =  self.activeOnBar[setId]["back"]
    end
    CallbackManager:FireCallbacks( "SetChange", self.unitType, setId, 
      setId, changeType, self.unitTag, activeOnBody, activeOnFront, activeOnBack, CheckException(setId)) 
  end
end


function SetManager:HasSet(setId) 
  local _activeState = self.activeState[setId] or false 
  local _activeOnBody = self.activeOnBar[setId] and self.activeOnBar[setId]["body"] or false 
  local _activeOnFront = self.activeOnBar[setId] and self.activeOnBar[setId]["front"] or false 
  local _activeOnBack = self.activeOnBar[setId] and self.activeOnBar[setId]["back"] or false 
  return _activeState, _activeOnBody, _activeOnFront, _activeOnBack
end 


function SetManager:GetActiveSets() 
  local _stateList = {}
  local _onBarList = Template_SlotCategorySubtables("table")
  for setId, activeState in pairs( self.activeState ) do 
    if activeState then table.insert(_stateList, setId) 
      for _, category in pairs(slotCategories) do 
        if self.activeOnBar[setId][category] then 
          table.insert(_onBarList[category], setId)
        end
      end
    end
  end
  return _stateList, _onBarList["body"], _onBarList["front"], _onBarList["back"]
end


function SetManager:GetNumEquip(setId)
  local _numEquip = Template_SlotCategorySubtables("numeric")
  for _, category in pairs(slotCategories) do 
    _numEquip[category] = self.numEquip[setId] and self.numEquip[setId][category] or 0
  end
  return _numEquip["body"], _numEquip["front"], _numEquip["back"]  
end


function SetManager:GetEquippedSets() 
  return ExtendNumEquipData( self.numEquip )
end


--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------- %% ]]
--[[ %% -- Group Manager -- %% ]]
--[[ %% ------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]


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
  elseif unitName == playerName then 
    return PlayerSets
  else
    return EmptySetManager
  end
end 


function GroupManager:Initialize() 
  self.debug = true
  self.isGrouped = IsUnitGrouped("player") 
  self.groupSets = {}

  --- events
  local function OnGroupMemberJoined(_, charName, _, isLocalPlayer) 
    if isLocalPlayer then 
      self.isGrouped = true
      BroadcastManager:UpdateActivityState()
    else 
      
    end
  end
  local function OnGroupMemberLeft(_, charName, _, isLocalPlayer)
    if isLocalPlayer then 
      self.isGrouped = false 
      BroadcastManager:UpdateActivityState()
    else 
      local unitName = ConvertCharToUnitName(charName) 
      self.groupSets[unitName] = nil  
    end 
  end
  EM:RegisterForEvent(libName, EVENT_GROUP_MEMBER_JOINED, OnGroupMemberJoined )
  EM:RegisterForEvent(libName, EVENT_GROUP_MEMBER_LEFT, OnGroupMemberLeft )
end



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

--[[ -------------- ]]
--[[ -- Data Msg -- ]]
--[[ -------------- ]]

DataMsg = {}

function DataMsg:GetSetType( setId )  
  if self:ExternalToInternalId("mystical", setId) then return SET_TYPE_MYSTICAL 
  elseif self:ExternalToInternalId("undaunted", setId) then return SET_TYPE_UNDAUNTED
  elseif self:ExternalToInternalId("weapon", setId) then return SET_TYPE_WEAPON
  else 
    return SET_TYPE_NORMAL 
  end
end

function DataMsg:ExternalToInternalId(category, externalId)
  return self.internalId[category][externalId]
end

function DataMsg:InternalToExternalId(category, internalId)
  return self.externalId[category][internalId]
end


function DataMsg:SerilizeData( numEquipData, requestSync ) 
  local formattedData = { 
    ["requestSync"] = requestSync, 
    ["mystical"] = 0, 
    ["NormalSets"] = {}, 
    ["WeaponSets"] = {},
    ["UndauntedSets"] = {},  
  }
  for setId, setData in pairs( numEquipData ) do 
    local setType = self:GetSetType( setId ) 
    if setType == SET_TYPE_NORMAL then 
      table.insert(formattedData["NormalSets"], {
        id=setId, 
        body=setData.body, 
        front = setData.front, 
        back = setData.back} )
    elseif setType == SET_TYPE_MYSTICAL then
      formattedData["mystical"] = self:ExternalToInternalId("mystical", setId)
    elseif setType == SET_TYPE_UNDAUNTED then 
      table.insert(formattedData["UndauntedSets"], {
        id=self:ExternalToInternalId("undaunted", setId), 
        body = setData.body
      })
    elseif setType == SET_TYPE_WEAPON then 
      table.insert( formattedData["WeaponSets"], {
        id = self:ExternalToInternal("weapon", setId),
        front = setData.front,
        back = setData.back
      })
    end
  end
  return formattedData
end


function DataMsg:DeserilizeData( rawData ) 
  local data = {}
  if not ZO_IsTableEmpty(rawData.WeaponSets) then 
    for _, setData in ipairs(rawData.WeaponSets) do 
      local setId = self:InternalToExternalId("weapon", setData.id )
      data[setId] = Template_SlotCategorySubtables("numeric", 0, setData.front, setData.back)
    end
  end
  if not ZO_IsTableEmpty(rawData.UndauntedSets) then 
    for _, setData in pairs(rawData.UndauntedSets) do 
      local setId = self:InternalToExternalId("undaunted", setData.id )
      data[setId] = Template_SlotCategorySubtables("numeric", setData.body)
    end
  end
  if rawData.mystical ~= 0 then 
    local setId = self:InternalToExternalId("mystical", rawData.mystical )
    data[setId] = Template_SlotCategorySubtables("numeric", 1)
  end
  for _, setData in ipairs(rawData.NormalSets) do 
    data[setData.id] = Template_SlotCategorySubtables("numeric", setData.body, setData.front, setData.back)
  end
  if rawData.requestSync then 
    --- send message with current setup 
    BroadcastManager.synchronized = true
  end 
  return data
end


function DataMsg:OnIncomingMsg(unitTag, rawData) 
  --GetLocalPlayerGroupUnitTag() 
  local unitName = GetUnitName(unitTag)
  d( zo_strformat("Received Data from <<1>> (<<2>>)", GetUnitName(unitTag), unitTag ) ) 
  d(rawData)
  local data = self:DeserilizeData(rawData
)
  if libDebug and self.debug then 
    d( zo_strformat("Received Data from <<1>> (<<2>>)", GetUnitName(unitTag), unitTag ) ) 
    d(rawData)
    d("----")
    d(self:DeserilizeData( rawData) )
  end
  if unitName == playerName then 

  else 
    GroupManager:UpdateSetData( unitName, unitTag, data ) 
  end
end


function DataMsg:SendData( numEquip ) 
  local requestSync = not BroadcastManager.synchronized
  local data = self:SerilizeData( numEquip, requestSync ) 
  d("formatted data for sending")
  d(data)
  self.protocol:Send( data ) 
end


function DataMsg:DefineIdMapping() 
  local mysticalList = {}
  local twoBoniSets = {} 
  for ii = 0, 2047 do 
    local maxEquip = GetMaxEquip( ii )
    if maxEquip == 1 then table.insert(mysticalList, ii) end
    if maxEquip == 2 then table.insert(twoBoniSets, ii) end 
  end 

  -- filter two boni into undaunted and abilityAltering 
  -- based on the fact that all abilityAltering sets have a perfected and normal version 
  local twoBoniSetsInverted = InvertTable(twoBoniSets)
  local abilityAlteringList = {}
  for setId, key in pairs( twoBoniSetsInverted ) do 
    local unperfSetId = GetItemSetUnperfectedSetId(setId)
    if unperfSetId ~= 0 then 
      table.insert( abilityAlteringList, unperfSetId )
      table.insert( abilityAlteringList, setId) 
      twoBoniSetsInverted[unperfSetId] = nil 
      twoBoniSetsInverted[setId] = nil
    end
  end

  self.internalId = {}
  self.internalId["mystical"] = InvertTable(mysticalList)  
  self.internalId["undaunted"] =  InvertTable(twoBoniSetsInverted)
  self.internalId["weapon"] = abilityAlteringList

  self.externalId = {}
  self.externalId["mystical"] = mysticalList 
  self.externalId["undaunted"] = twoBoniSetsInverted
  self.externalId["weapon"] = InvertTable(abilityAlteringList)
end


function DataMsg:InitMsgHandler() 
  local LGB = LibGroupBroadcast
  self.handler = LGB:RegisterHandler("LibSetDetection")
  self.protocol = self.handler:DeclareProtocol(42, "SetData")
  local normalSetsArray = LGB.CreateArrayField( LGB.CreateTableField("NormalSets", {
      LGB.CreateNumericField("id", { minValue = 0, maxValue = 1023 }),  --10 bit
      LGB.CreateNumericField("body", { minValue = 0, maxValue = 10 }),  -- 4 bit
      LGB.CreateNumericField("front", { minValue = 0, maxValue = 2 }),  -- 2 bit
      LGB.CreateNumericField("back", { minValue = 0, maxValue = 2 }),   -- 2 bit
    }), { minLength = 0, maxLength = 15 } )
  local weaponSetsArray = LGB.CreateArrayField( LGB.CreateTableField("WeaponSets", {
      LGB.CreateNumericField("id", { minValue = 0, maxValue = 31}),     -- 5 bit
      LGB.CreateNumericField("front", {minValue = 0, maxValue = 2}),    -- 2 bit 
      LGB.CreateNumericField("back", {minValue = 0, maxValue = 2}),     -- 2 bit
    }), { minLength = 0, maxLength = 2 } )  
  local undauntedSetsArray = LGB.CreateArrayField( LGB.CreateTableField("UndauntedSets", {
      LGB.CreateNumericField("id", { minValue = 0, maxValue = 127}),  -- 7 bit
      LGB.CreateNumericField("body", {minValue = 1, maxValue = 2})    -- 1 bit
    }), { minLength = 0, maxLength = 2 } )
  self.protocol:AddField( normalSetsArray ) -- 4 bit length + x*18 bit 
  self.protocol:AddField( weaponSetsArray ) -- 2 bit length + x* 9 bit
  self.protocol:AddField( undauntedSetsArray ) -- 2bit length + x*8 bit
  self.protocol:AddField( LGB.CreateNumericField("mystical", {minValue = 0, maxValue = 63} ) )
  self.protocol:AddField( LGB.CreateFlagField("requestSync") )
  self.protocol:OnData( function(...) self:OnIncomingMsg(...) end )  
  self.protocol:Finalize()
end


function DataMsg:Initialize(debug) 
  self.debug = debug
  self:DefineIdMapping()
  self:InitMsgHandler() 
  return self
end

--[[ -------------------------- ]]
--[[ ----- End of DataMsg ----- ]]
--[[ -------------------------- ]]


function BroadcastManager:UpdateActivityState()
  local function GetBool( var ) 
    return var and true or false
  end

  if libDebug and self.debug then debugMsg("BM", "activity state update ("..tostring(self.active)..")")  end
  local previousState = self.active
  local updatedState = false 

  --- true setter (or arguments) 
  -- state is set to true, if any of the following conditions is not met
  if libDebug and self.debug then d("--- true setter ---") end
  if libDebug and self.debug then d("is grouped: "..tostring(GroupManager.isGrouped)) end
  updatedState = updatedState or GroupManager.isGrouped

  --- false setter (and arguments) 
  -- state is set to false, if any of the following conditions is not met
  if libDebug and self.debug then d("--- false setter ---") end
  if libDebug and self.debug then d("is LibGroupBroadcast: "..tostring( GetBool(LibGroupBroadcast) ) ) end
  updateState = updateState and GetBool(LibGroupBroadcast) 

  if libDebug and self.debug then d("updated state: "..tostring(updatedState) ) end
  self.active = updatedState
end 


function BroadcastManager:SendData(numEquip) 
  if self.dormant then return end
  self.DataMsg:SendData(numEquip)
  self.synchronized = true
end


function BroadcastManager:Initialize() 
  if not LibGroupBroadcast then 
    self.dormant = true
    return 
  end
  self.debug = true
  self.synchronized = false 
  BroadcastManager:UpdateActivityState()
  self.DataMsg = DataMsg:Initialize( self.debug ) 
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
  for _, category in pairs(slotCategories) do  -- body, front, back 
    for slotId, _ in pairs( slotList[category]) do 
      local setId = self.equippedGear[slotId] 
      numEquip[setId] = numEquip[setId] or Template_SlotCategorySubtables("numeric") 
      numEquip[setId][category] = numEquip[setId][category] + 1
    end
  end 
  numEquip[0] = nil
  if libDebug and self.debug then 
    debugMsg("SM", "relay data")
    d( ExtendNumEquipData(numEquip) )
    d("---------- end: relay data")
  end
  PlayerSets:UpdateData( numEquip, "player" ) 
  BroadcastManager:SendData( numEquip ) 
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
  GroupManager:Initialize()
  BroadcastManager:Initialize() 
  SlotManager:Initialize() 

  PlayerSets = SetManager:New("player") 
  EmptySetManager = SetManager:New("group")

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


local function ReadData(api, setId, unitTag) 
  local SM
  if unitTag == "player" then 
    SM = PlayerSets
  else 
    SM = GroupManager:GetSetManager( unitTag ) 
  end
  return SM[api](SM, setId)
end


local function FormatGroupData(groupData) 
  local tab = { {}, {}, {}, {} }
  for unit, data in pairs(groupData) do 
    for ii = 1,4,1 do
      tab[ii][unit] = data[ii]
    end
  end
  return tab[1], tab[2], tab[3], tab[4]
end 


local function FormatAllData(playerData, ...) 
  local tab = {...} 
  for ii = 1,4,1 do 
    tab[ii]["player"] = playerData[ii]
  end
  return tab[1], tab[2], tab[3], tab[4]
end


local function AccessSetManager(api, setId, unitType, groupTag)

  unitType = unitType or LSD_UNIT_TYPE_PLAYER
  if unitType == LSD_UNIT_TYPE_ALL then 
    local playerData = {ReadData(api, setId, "player")}
    return FormatAllData(playerData, AccessSetManager(api, setId, LSD_UNIT_TYPE_GROUP) )
  end

  if unitType == LSD_UNIT_TYPE_GROUP then 
    local groupData = {}
    for ii=1,GetGroupSize() do 
      local unitTag = GetGroupUnitTagByIndex( ii ) 
      if IsUnitPlayer(unitTag) then 
        groupData[unitTag] = {ReadData(api, setId, unitTag)}
      end
    end
    return FormatGroupData(groupData)
  end 

  local unitTag
  if unitType == LSD_UNIT_TYPE_PLAYER then 
    unitTag = "player" 
  elseif unitType == LSD_UNIT_TYPE_GROUP_MEMBER then 
    unitTag = groupTag
  end
  
  if not IsUnitPlayer(unitTag) then return end
  -- validate unitTag by checking for name of corresponding unit
  local unitName = GetUnitName(unitTag) 
  if not unitName or unitName == "" then return nil end
  
  return ReadData(api, setId, unitTag)
end


--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ----------------------- %% ]]
--[[ %% -- Exposed Functions -- %% ]]
--[[ %% ----------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]

function LibSetDetection.HasSet( setId, unitType, groupTag )
  setId = ConvertToUnperfected(setId) 
  return AccessSetManager( "HasSet", setId, unitType, groupTag)
end -- activeState, activeOnBody, activeOnFront, activeOnBack 

function LibSetDetection.GetActiveSets( unitType, groupTag) 
  return AccessSetManager("GetActiveSets", nil, unitType, groupTag)
end -- activeList, activeOnBodyList, activeOnFrontList, activeOnBackList 

function LibSetDetection.GetNumEquip(setId, unitType, groupTag) 
  setId = ConvertToUnperfected(setId)
  return AccessSetManager("GetNumEquip", setId, unitType, groupTag )  
end -- numBody, numFront, numBack

function LibSetDetection.GetEquippedSets(unitType, groupTag) 
  return AccessSetManager("GetEquippedSets", nil, unitType, groupTag)   
end -- table equip


--- Advanced 
LibSetDetection.CheckException = CheckException

function LibSetDetection.GetPlayerEquippedGear() 
  return SlotManager.equippedGear 
end

function LibSetDetection.GetUnitRawNumEquip() -- return data while still separating bettween normal and perf

end


--- Utility for Developer
function LibSetDetection.GetSetIdFromItemLink( itemlink ) 
  local _, _, _, _, _, setId = GetItemLinkSetInfo( itemlink )
  return setId
end


--[[ Exposed Functions of CallbackManager ]]

--- User Input: 
--    1. id (string - case sensitive): unique name (for each registryType/unitType) 
--    2. callback (function): called when appropriate callbacks fire
--    3. unitType (number): "player" or "group" or "all" (nil = "all") 
--    4. filter:nilable (optional for "SetChange") - table of filter values (setId), for registration or unregistration  

--EventSetChange( action, setId, unitTag, isActiveOnBody, isActiveOnFrontbar, isActiveOnBackbar)
--*action*: 0 = unequip, 1 = equip, 2 = activityChange 

--- "SetChanged" Event
--- Variables provided by Event:
--    1. setId (number):  
--    2. changeType (number):  
--    3. unitTag (string): "player" or "group"..i  (except group tag that corresponds with player)
--    4. isActiveOnBody (bool)
--    5. isActiveOnFront (bool) 
--    6. isActiveOnBack (bool) 
--    7. hasException


function LibSetDetection:RegisterEvent( eventId, ... )
  return CallbackManager:UpdateRegistry( true, eventId, ...)
end


function LibSetDetection:UnregisterEvent( eventId, uniqueId, ... ) 
  return CallbackManager:UpdateRegistry( false, eventId, uniqueId, nil, ... )
end


--[[ Temporary Backwards Compatibility ]]
function LibSetDetection.RegisterForSetChanges(uniqueId, callback) 
  LibSetDetection.RegisterEvent( LSD_EVENT_SET_CHANGE, uniqueId, callback, LSD_UNIT_TYPE_PLAYER)
end

function LibSetDetection.RegisterForSpecificSetChanges(uniqueId, setId, callback)
  LibsSetDetection.RegisterEvent( LSD_EVENT_SET_CHANGE, uniqueId, callback, LSD_UNIT_TYPE_PLAYER, setId)
end

function LibSetDetection.RegisterForCustomSlopUpdateEvent(uniqueId, callback) 
  LibSetDetection.RegisterEvent( LSD_EVENT_DATA_UPDATE, uniqueId, callback, LSD_UNIT_TYPE_PLAYER) 
end

function LibSetDetection.UnregisterForCustomSlopUpdateEvent(uniqueId)
  LibSetDetection.RegisterEvent( LSD_EVENT_DATA_UPDATE, uniqueId, nil, LSD_UNIT_TYPE_PLAYER)
end


function LibSetDetection.GetCompleteSetsList() ---checked
  local PS = PlayerSets 
  local returnTable = {}
  for setId, complete in pairs( PS.activeState ) do 
    if complete then 
      returnTable[setId] = GetSetName(setId) 
    end
  end
  return returnTable
end


function LibSetDetection.GetEquipSlotList() ---checked
  return slotList
end


function LibSetDetection.GetSlotIdSetIdMap() ---checked
  return SlotManager.equippedGear
end


function LibSetDetection.GetEquippedSetsTable() ---checked
  local PS = PlayerSets
  local returnTable = {}
  for setId, _ in pairs( PS.activeState ) do 
    local setData = {}
    setData.name = GetSetName( setId ) 
    setData.maxEquipped = GetMaxEquip( setId ) 
    setData.numEquipped = PS.numEquip[setId] 
    setData.activeBar = PS.activeOnBar[setId]
    returnTable[setId] = setData 
  end
  return returnTable
end


function LibSetDetection.GetNumSetPiecesForHotbar(setId, slotCategory)
  local barList = {"front", "back", "body"}
  local PS = PlayerSets 
  return PS.numEquip[setId][barlist[slotCategory]]
end


function LibSetDetection.GetBarActiveSetIdMap()
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
    local OutputSets = function(slotCategory) 
      d("--- "..slotCategory.." --- ")
      for slotId, slotName in pairs( slotList[string.lower(slotCategory)] ) do 
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
    else 
      d("[LibSetDetection] incorrect input for setId search")
    end
  elseif cmd == "setname" then 
    local setId = tonumber(param[1])
    if IsNumber(setId) then  
      local setName = GetSetName(setId) 
      if setName == "" then 
        d(zo_strformat("[LibSetDetection] no set name found for id=<<1>>", setId))
      else 
        d(zo_strformat("[LibSetDetection] <<1>> (<<2>>)", GetSetName(setId), setId))
      end
    else 
      d("[LibSetDetection] incorrect input for setName search")
    end
  elseif cmd == "debug" then 
    if param[1] == "toggle" then 
      libDebug = not libDebug 
      d( zo_strformat("[LibsetDetection] Debug switched > <<1>> <", libDebug and "on" or "off"))
    else 
      d("[LibSetDetection - Debug] lib: "..tostring(libDebug))
      d("BroadcastManager: "..tostring(BroadcastManager.debug))
      d("CallbackManager: "..tostring(CallbackManager.debug))
      d("GroupManager: "..tostring(GroupManager.debug))
      d("SetManager - Player: "..tostring(PlayerSets.debug))
      d("SetManager - Group: "..tostring(EmptySetManager.debug))
      d("SlotManager: "..tostring(SlotManager.debug))
    end
  else 
    if cmd == "dev" and libDebug then 
      --- call development functions 
      --Development.OutputEquippedSets()
      --Development.OutputPlayerSets()    
      if param[1] == "registry" then 
        Development.OutputRegistry()
      elseif param[1] == "active" then 
        BroadcastManager:UpdateActivityState()    
      elseif param[1] == "groupsets" then 
        Development.OutputGroupManager()   
      elseif param[1] == "equipped" then 
        Development.OutputEquippedSets() 
      elseif param[1] == "test" then 
        Development.Test()      
      end
    else 
      d("[LibSetDetection] command unknown")
    end
  end

end




--[[ --------------------------- ]]
--[[ -- Development Functions -- ]]
--[[ --------------------------- ]]

function Development.Test() 
  local a,b,c,e = LibSetDetection.GetEquippedSets(1) 
  local v,w,x,y = LibSetDetection.GetEquippedSets(2) 
  d(a) 
  d("---") 
  d(v)
end


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

function Development.OutputLookupTables()
  d("Executing LookupTable Init")
  Init_LookupTables() 
end