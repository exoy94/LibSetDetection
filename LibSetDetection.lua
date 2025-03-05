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

local function Template_SlotCategorySubtables( initBody, initFront, initBack )
  _initBody = initBody or 0 
  _initFront = initFront or 0 
  _initBack = initBack or 0
  return { ["body"] = _initBody, ["front"] = _initFront, ["back"] = _initBack }
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
 
--- eventId
LSD_EVENT_SET_CHANGE = 1 
LSD_EVENT_DATA_UPDATE = 2

local events = {
  [LSD_EVENT_SET_CHANGE] = "SetChange", 
  [LSD_EVENT_DATA_UPDATE] = "DataUpdate", 
}


--- changeType
LSD_CHANGE_TYPE_ACTIVATED = 1
LSD_CHANGE_TYPE_DEACTIVATED = 2 
LSD_CHANGE_TYPE_UPDATED = 3 

local changeTypes = {
  [LSD_CHANGE_TYPE_ACTIVATED] = "activated", 
  [LSD_CHANGE_TYPE_DEACTIVATED] = "deactivated", 
  [LSD_CHANGE_TYPE_UPDATED] = "updated",
}


--- unitType
LSD_UNIT_TYPE_PLAYER = 1 
LSD_UNIT_TYPE_GROUP = 2

local unitTypes = {
  [LSD_UNIT_TYPE_PLAYER] = "Player", 
  [LSD_UNIT_TYPE_GROUP] = "Group", 
}


--- activeType 
LSD_ACTIVE_TYPE_NONE = 0 
LSD_ACTIVE_TYPE_DUAL_BAR = 1
LSD_ACTIVE_TYPE_FRONT_BAR = 2
LSD_ACTIVE_TYPE_BACK_BAR = 3 


local activeTypes = {
  [LSD_ACTIVE_TYPE_NONE] = "None",
  [LSD_ACTIVE_TYPE_DUAL_BAR] = "Dual",
  [LSD_ACTIVE_TYPE_FRONT_BAR] = "Front",
  [LSD_ACTIVE_TYPE_BACK_BAR] = "Back",
  
}


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
local REGISTRY_RESULT_INVALID_PARAMETER = 4
local REGISTRY_RESULT_INVALID_NAME = 5
local REGISTRY_RESULT_DUPLICATE_NAME = 6
local REGISTRY_RESULT_UNKNOWN_NAME = 7

local SET_TYPE_NORMAL = 0 
local SET_TYPE_MYSTICAL = 1 
local SET_TYPE_UNDAUNTED = 2 
local SET_TYPE_WEAPON = 3




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
  local _, _, _, _, _, maxEquipZos = GetItemSetInfo( setId ) 
  maxEquip = CheckException(setId, "maxEquip") or maxEquipZos
  return maxEquip, maxEquipZos
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


function CallbackManager:Initialize() 
  self.debug = false

  --- initialize registry tables 
  self.registry = {}
  for _, eventName in ipairs(events) do 
    self.registry[eventName] = {}
    for _, unitTypeName in ipairs(unitTypes) do 
      self.registry[eventName][unitTypeName] = {}
    end
  end

end



local function IsValidEventSpecificParameter(eventId, param)
  if eventId == LSD_EVENT_SET_CHANGE then 
    if not param then return true end 
    if IsNumber(param) then return true end 
    if IsTable(param) then 
      for _, value in ipairs(param) do 
        if not IsNumber(value) then return false end 
      end
      return true 
    end
    return false 
  elseif eventId == LSD_EVENT_DATA_UPDATE then 
    return true 
  else 
    return false 
  end
end

function CallbackManager:UpdateRegistry(action, eventId, name, callback, unitType, param)
  local resultCode = 0 
  --- early outs 
  if not events[eventId] then resultCode = REGISTRY_RESULT_INVALID_EVENT end  
  if not unitTypes[unitType] then resultCode = REGISTRY_RESULT_INVALID_UNIT_TYPE end   
  if not IsString(name) then resultCode = REGISTRY_RESULT_INVALID_NAME end  
  if not IsValidEventSpecificParameter(eventId, param) then resultCode = REGISTRY_RESULT_INVALID_FILTER end
  if resultCode ~= 0 then return resultCode end 
  --- define registry 
  local eventName = events[LSD_EVENT_SET_CHANGE]
  local unitTypeName = unitTypes[unitType]
  local registry = self.registry[eventName][unitTypeName]
  --- (un-)registration
  if eventId == LSD_EVENT_SET_CHANGE then --- Set Change
    resultCode = self:UpdateSetChangeRegistry( action, name, callback, registry, param ) 
  elseif eventId == LSD_EVENT_DATA_UPDATE then  --- Data Update
    resultCode = self:UpdateDataUpdateRegistry( action, name, callback, registry ) 
  end
  --- debug
  if libDebug and self.debug then 
    local actionStr = action and "Register" or "Unregister" 
    debugMsg("CM", zo_strformat("<<1>> '<<2>>' in <<3>>-<<4>> (<<5>>) Result: <<6>>", actionStr, name, eventName, unitTypeName, param, resultCode))
  end
  --- return
  return resultCode
end 



function CallbackManager:UpdateSetChangeRegistry( action, name, callback, registry, param ) 
  --- define setId filter 
  local filter = {}   -- events with no filter will be mapped to an arbitrary filter Id of 0 
  if IsNumber(param) then 
    table.insert(filter, param)      -- this makes subsequent code easier and clearer
  elseif IsTable(param) then 
    for _, setId in ipairs(param) do 
      table.insert(filter, ConvertToUnperfected(setId) ) 
    end
  else 
    table.insert(filter, 0)
  end
  --- (un-)registration
  for _, setId in pairs(filter) do 
    registry[setId] = registry[setId] or {}
    local callbackList = registry[setId]
    if action then    
      if callbackList[name] then return REGISTRY_RESULT_DUPLICATE_NAME end
      if IsFunction(callback) then 
        callbackList[name] = callback 
      else 
        return REGISTRY_RESULT_INVALID_CALLBACK 
      end
    else  
      if not callbackList[name] then return REGISTRY_RESULT_UNKNOWN_NAME end 
      callbackList[name] = nil
    end 
  end
  return REGISTRY_RESULT_SUCCESS
end   --- End of "UpdateSetChangeRegistry"



function CallbackManager:UpdateDataUpdateRegistry( action, name, callback, callbackList ) 
  --- (un-)registration
  if action then
    if callbackList[name] then return REGISTRY_RESULT_DUPLICATE_NAME end
    if IsFunction(callback) then 
      callbackList[name] = callback 
    else 
      return REGISTRY_RESULT_INVALID_CALLBACK 
    end
    callbackList[name] = callback 
  else 
    if not callbackList[name] then return REGISTRY_RESULT_UNKNOWN_NAME end 
    callbackList[name] = nil
  end
end   --- End of "UpdateDataUpdateRegistry"




local function _FireCallbacks(callbackList, ...) 
  if ZO_IsTableEmpty( callbackList ) then return end 
  for _, callback in pairs( callbackList ) do 
    callback(...) 
  end
end

function CallbackManager:FireCallbacks( eventId, unitType, setId, ... ) 
  --- define registry 
  local eventName = events[LSD_EVENT_SET_CHANGE]
  local unitTypeName = unitTypes[unitType]
  local registry = self.registry[eventName][unitTypeName]
  --- fire callbacks
  if eventId == LSD_EVENT_SET_CHANGE then 
    -- parameter: setId, changeType, unitTag, localPlayer, activeType
    _FireCallbacks( registry[0], ...)
    _FireCallbacks( registry[setId], ...)
    --- debug
    if libDebug and self.debug then 
      local p = {...}
      local msgPartOne = zo_strformat( "<<1>> for <<2>> (<<3>>): ", 
        eventName, GetUnitName(p[3]), p[3] ) 
      local msgPartTwo = zo_strformat("<<1>> <<2>> (<<3>>) - Active:<<4>>", 
        changeTypes[p[2]], GetSetName( p[1] ), p[1], p[5] )
      debugMsg("CM-Fire", msgPartOne..msgPartTwo )
    end
  elseif eventId == LSD_EVENT_DATA_UPDATE then 
    -- parameter: unitTag, localPlayer, numEquipList, activeList
    _FireCallbacks( registry, ... )
    --- debug
    if libDebug and self.debug then 
      local p = {...} 
      debugMsg("CM", zo_strformat("<<1>> for <<2>> (<<3>>)", eventName, GetUnitName(p[1]), p[1]) )
    end
  end
end   --- End of "FireCallbacks"


--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------ %% ]]
--[[ %% -- Set Manager --- %% ]]
--[[ %% ------------------ %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]

SetManager.__index = SetManager 

function SetManager:New( unitType, unitName )
  local SM = setmetatable({}, SetManager) 
  if unitType == LSD_UNIT_TYPE_PLAYER then 
    SM.debug = true   
    SM.localPlayer = true
  elseif unitType == LSD_UNIT_TYPE_GROUP then 
    SM.debug = false 
    SM.localPlayer = false
  end
  SM.unitType = unitType
  SM.rawData = {}
  SM.numEquipList = {} 
  SM.activeList  = {}
  return SM
end


function SetManager:UpdateData( newRawData, unitTag )
  self.debugHeader = zo_strformat( "SM <<1>> (<<2>>)", GetUnitName(unitTag), unitTag )
  if libDebug and self.debug then debugMsg( self.debugHeader, "update data" ) end
  self.unitTag = unitTag -- ensures always correct unitTag
  self:InitTables( newRawData )  -- updates archive and resets current 
  self:ConvertDataToUnperfected()   -- all perfected pieces are handled as unperfected  
  self:AnalyseData()  -- determines, which sets are active 
  local changeList = self:DetermineChanges()  -- determine, what has changed (un-)equip/ update
  self:FireCallbacks( changeList )  -- fire callbacks according to detected changes
end


function SetManager:InitTables( newRawData ) 
  self.archive = {} 
  self.archive["rawData"] = ZO_ShallowTableCopy(self.rawData)
  self.archive["numEquipList"] = ZO_ShallowTableCopy(self.numEquipList)
  self.archive["activeList"] = ZO_ShallowTableCopy(self.activeList)
  self.rawData = newRawData
  self.numEquipData = {}
  self.activeData = {}
end


function SetManager:ConvertDataToUnperfected() 
  --- initialize temporary tables
  local numEquipTemp = {}
  local listOfPerfected = {}
  local listOfNormal = {}
  --- check, if any perfected sets are equipped
  for setId, _ in pairs( self.rawData ) do 
    if GetItemSetUnperfectedSetId(setId) ~= 0 then 
      table.insert( listOfPerfected, setId ) 
    else 
      table.insert( listOfNormal, setId )
    end
  end
  --- add all normal sets to temporary 
  for _, setId in ipairs( listOfNormal ) do 
    numEquipTemp[setId] = ZO_ShallowTableCopy(self.rawData[setId]) 
  end
  --- add perfected count to corresponding unperfected version  
  for _, perfSetId in ipairs( listOfPerfected ) do 
    local unperfSetId = GetItemSetUnperfectedSetId(perfSetId) 
    if not numEquipTemp[unperfSetId] then 
    -- if no unperfected pieces are equipped, overwrite it with perfected
      numEquipTemp[unperfSetId] = ZO_ShallowTableCopy(self.rawData[perfSetId])
    else 
    -- if unperfected pieces are equipped, add perfected ones
      for slotCategory, numEquip in pairs( self.rawData[perfSetId] ) do 
        numEquipTemp[unperfSetId][slotCategory] = numEquipTemp[unperfSetId][slotCategory] + numEquip
      end
    end
  end
  self.numEquipList = numEquipTemp
  --- debug
  if libDebug and self.debug then 
    if ZO_IsTableEmpty(listOfPerfected) then 
      d("no normal/perfected conversion occured")
    else 
      d("conversionList:")
      for _, id in ipairs(listOfPerfected) do 
        local unperfId  = GetItemSetUnperfectedSetId(id)
        d( zo_strformat("<<1>> --> <<2>> (<<3>>)", id, unperfId, GetSetName(unperfId) ) )
      end
      d("------------ End of conversionList")
    end

    debugMsg( self.debugHeader, "numEquipList")
    d(ExtendNumEquipData(numEquipTemp) )
    d("------------ End of numEquipList")

  end
end

function SetManager:AnalyseData() 
  for setId, numEquip in pairs( self.numEquipList ) do  

    local numBody = numEquip["body"]
    local numFront = numBody + numEquip["front"] 
    local numBack = numBody + numEquip["back"] 
    local maxEquip = GetMaxEquip(setId)
    
    local activeOnFront = numFront >= maxEquip
    local activeOnBack = numBack >= maxEquip

    local activeType = LSD_ACTIVE_TYPE_NONE

    if activeOnFront and activeOnBack then activeType = LSD_ACTIVE_TYPE_DUAL_BAR 
    elseif activeOnFront then activeType = LSD_ACTIVE_TYPE_FRONT_BAR 
    elseif activeOnBack then activeType = LSD_ACTIVE_TYPE_BACK_BAR
    end

    self.activeList[setId] = activeType
  end
  if libDebug and self.debug then 
    debugMsg( self.debugHeader, "activeList") 
    local activeListDecoded = {}
    for setId, activeType in pairs(self.activeList) do 
      activeListDecoded[setId] = activeTypes[activeType]
    end
    d( activeListDecoded)
    d("------------ End of activeList")
  end
end


function SetManager:DetermineChanges() 

  local changeList = {}
  --- check if changes occured to currently equipped sets
  for setId, activeType in pairs( self.activeList ) do 
    local previousActiveType = self.archive.activeList[setId] or LSD_ACTIVE_TYPE_NONE
    if activeType ~= previousActiveType then -- only changes in activeType are of interest 
      if activeType > 0 and previousActiveType == 0 then changeList[setId] = LSD_CHANGE_TYPE_ACTIVATED
      elseif activeType > 0 then changeList[setId] = LSD_CHANGE_TYPE_UPDATED
      elseif activeType == 0 then changeList[setId] = LSD_CHANGE_TYPE_DEACTIVATED 
      end
    end
  end
  --- check if any previously equipped set was unequipped 
  for setId, _ in pairs(self.archive.activeList ) do 
    if not changeList[setId] then changeList[setId] = LSD_CHANGE_TYPE_DEACTIVATED end
  end

  if libDebug and self.debug then 
    debugMsg( self.debugHeader, "changeList") 
    local changeListDecoded = {}
    for setId, changeType in pairs(changeList) do 
      changeListDecoded[setId] = changeTypes[changeType]
    end
    d(changeListDecoded)
    d("------------ End of changeList")
  end
  return changeList 
end


function SetManager:FireCallbacks( changeList ) 
  if libDebug and self.debug then debugMsg( self.debugHeader, "fire callbacks") end
  for setId, changeType in pairs( changeList ) do 
    CallbackManager:FireCallbacks( LSD_EVENT_SET_CHANGE, self.unitType, setId, 
      setId, changeType, self.unitTag, self.localPlayer, self.activeList[setId] ) 
  end
  CallbackManager:FireCallbacks( LSD_EVENT_DATA_UPDATE, self.unitType, nil, 
    self.unitTag, self.localPlayer, self.numEquipList, self.activeList)
end



--[[ ---------------------------- ]]
--[[ -- SetManager Exposed API -- ]]
--[[ ---------------------------- ]] 

function SetManager:GetSetActiveType( setId ) 
  return self.activeList[setId] or LSD_ACTIVE_TYPE_NONE
end

function SetManager:GetSetNumEquip( setId ) 
  local numEquip = self.numEquipList[setId] or Template_SlotCategorySubtables()
  return numEquip["body"], numEquip["front"], numEquip["back"]
end

function SetManager:GetSetData() 
  local setData = {}
  for setId, activeType in pairs( self.activeList ) do 
    setData[setId].activeType = self.activeList[setId]
    setData[setId].numEquip = self.numEquipList[setId] or Template_SlotCategorySubtables()
    setData[setId].setName = GetSetName(setId) 
    setData[setId].maxEquip = GetMaxEquip(setId)
  end
  return setData
end

function SetManager:GetRawNumEquipList() 
  return  ZO_DeepTableCopy( self.rawData )
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
    _gs[unitName] = SetManager:New( LSD_UNIT_TYPE_GROUP )
    _gs[unitName]:UpdateData( data, unitTag )
  end
end


function GroupManager:GetSetManager( unitTag, provideEmptySM ) 
  local unitName = GetUnitName(unitTag)
  -- check if there exists a set manager 
  if self.groupSets[unitName] then 
    return self.groupSets[unitName]
  elseif unitName == playerName then 
    return PlayerSets
  else
    if provideEmptySM then return EmptySetManager end
  end
end 


function GroupManager:UpdateGroupMap() 
  self.groupMap = {}
  for ii = 1, GetGroupSize() do 
    local groupTag = GetGroupUnitTagByIndex(ii)
    if IsUnitPlayer(unitTag) then 
      self.groupMap[GetUnitName(groupTag)] = groupTag
    end
  end
  self.mapOutdated = false 
end



function GroupManager:AreUnitDataAvailable( unitTag )  
  local unitName = GetUnitName(unitTag) 
  if unitName == playerName then return true end 
  return self.groupSets[unitName] and true or false 
end



function GroupManager:Initialize() 
  self.debug = false
  self.isGrouped = IsUnitGrouped("player") 
  self.groupSets = {}
  self.groupMap = {}
  self.mapOutdated = true 

  --- event callbacks
  local function OnGroupMemberJoined(_, charName, _, isLocalPlayer) 
    if isLocalPlayer then 
      self.isGrouped = true
      BroadcastManager:UpdateActivityState()
      BroadcastManager.synchronized = false
      BroadcastManager:SendData( PlayerSets.numEquip )
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
  local function OnGroupUpdate() 
    self.mapOutdated = true 
  end
  --- event registration 
  EM:RegisterForEvent(libName, EVENT_GROUP_MEMBER_JOINED, OnGroupMemberJoined )
  EM:RegisterForEvent(libName, EVENT_GROUP_MEMBER_LEFT, OnGroupMemberLeft )
  EM:RegisterForEvent(libName, EVENT_GROUP_UPDATE, OnGroupUpdate )
end



--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ---------------------- %% ]]
--[[ %% -- BroadcastManager -- %% ]]
--[[ %% ---------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]



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


function DataMsg:SerilizeData( rawNumEquipList, requestSync ) 
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
      data[setId] = Template_SlotCategorySubtables( 0, setData.front, setData.back )
    end
  end
  if not ZO_IsTableEmpty(rawData.UndauntedSets) then 
    for _, setData in pairs(rawData.UndauntedSets) do 
      local setId = self:InternalToExternalId("undaunted", setData.id )
      data[setId] = Template_SlotCategorySubtables( setData.body )
    end
  end
  if rawData.mystical ~= 0 then 
    local setId = self:InternalToExternalId("mystical", rawData.mystical )
    data[setId] = Template_SlotCategorySubtables( 1 )
  end
  for _, setData in ipairs(rawData.NormalSets) do 
    data[setData.id] = Template_SlotCategorySubtables( setData.body, setData.front, setData.back )
  end
  return data, rawData.requestSync
end


function DataMsg:OnIncomingMsg(unitTag, rawData) 
  local unitName = GetUnitName(unitTag) -- who send information 
  if unitName == playerName then 
    if libDebug and self.debug then 
      debugMsg("BM", "Received Data from player" ) 
    end
  else 
    if libDebug and self.debug then 
      debugMsg("BM", zo_strformat("Received Data from <<1>> (<<2>>)", unitName, unitTag ) ) 
    end

    local data, requestSync = self:DeserilizeData(rawData)
    if requestSync then 
      if libDebug and self.debug then 
        debugMsg("BM", zo_strformat("Sync requested by <<1>> (<<2>>)", unitName, unitTag))
      end
      self:SendData( PlayerSets.numEquipList ) 
      BroadcastManager.synchronized = true
    end
    GroupManager:UpdateSetData( unitName, unitTag, data ) 
  end
end


function DataMsg:SendData( rawNumEquipList ) 
  local requestSync = not BroadcastManager.synchronized
  local data = self:SerilizeData( rawNumEquipList, requestSync ) 
  if libDebug and self.debug then debugMsg("BM", zo_strformat("sending data; requestSync = <<1>>", requestSync and "true" or "false") ) end
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
  if not LibGroupBroadcast then return end
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
      LGB.CreateNumericField("id", { minValue = 0, maxValue = 63}),     -- 6 bit
      LGB.CreateNumericField("front", {minValue = 0, maxValue = 2}),    -- 2 bit 
      LGB.CreateNumericField("back", {minValue = 0, maxValue = 2}),     -- 2 bit
    }), { minLength = 0, maxLength = 2 } )  
  local undauntedSetsArray = LGB.CreateArrayField( LGB.CreateTableField("UndauntedSets", {
      LGB.CreateNumericField("id", { minValue = 0, maxValue = 127}),  -- 7 bit
      LGB.CreateNumericField("body", {minValue = 1, maxValue = 2})    -- 1 bit
    }), { minLength = 0, maxLength = 2 } )
  self.protocol:AddField( normalSetsArray ) -- 4 bit length + x*18 bit 
  self.protocol:AddField( weaponSetsArray ) -- 2 bit length +  x*10 bit
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
end

--[[ -------------------------- ]]
--[[ ----- End of DataMsg ----- ]]
--[[ -------------------------- ]]


function BroadcastManager:SendData(rawNumEquipList) 
  if not LibGroupBroadcast then return end
  self.DataMsg:SendData(rawNumEquipList)
  self.synchronized = true
end


function BroadcastManager:Initialize() 
  self.debug = false
  self.synchronized = false 
  DataMsg:Initialize( self.debug ) 
end


--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------ %% ]]
--[[ %% -- Slot Handler -- %% ]]
--[[ %% ------------------ %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]] 


function SlotManager:Initialize() 
  self.debug = false
  self.equippedGear = {} 
  for slotId, _ in pairs( equipSlotList ) do 
    self.equippedGear[slotId] = 0 
  end
  self.queueDuration = 3000 
end


function SlotManager:UpdateLoadout() 
  if libDebug and self.debug then debugMsg( "SM", "loadout update" ) end
  for slotId, _ in pairs (equipSlotList) do 
    self:UpdateSetId( slotId ) 
  end
  self:RelayData()  
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
    self:RelayData()
    self.queueId = nil 
  end, self.queueDuration ) 
end


function SlotManager:ApplySpecialCases( numEquip ) 
  --- no need to populate tables for "no setId"
  numEquip[0] = nil
  --- ignore all other sets, when "Torq of the last ayleid king" mystical is equipped
  local ayleidKing = 693
  if numEquip[ayleidKing] then 
    for setId, data in pairs(numEquip) do 
      if setId ~= ayleidKing then numEquip[setId] = nil end 
    end
  end
  return numEquip 
end


function SlotManager:RelayData() 
  local rawNumEquipList = {} 
  for _, category in pairs(slotCategories) do  
    for slotId, _ in pairs( slotList[category]) do 
      local setId = self.equippedGear[slotId] 
      rawNumEquipList[setId] = rawNumEquipList[setId] or Template_SlotCategorySubtables() 
      rawNumEquipList[setId][category] = rawNumEquipList[setId][category] + 1
    end
  end 

  rawNumEquipList = self:ApplySpecialCases(rawNumEquipList) 
  
  if libDebug and self.debug then 
    debugMsg("SM", "relay data")
    d( ExtendNumEquipData(rawNumEquipList) )
    d("---------- end: relay data")
  end

  PlayerSets:UpdateData( rawNumEquipList, "player" ) 
  BroadcastManager:SendData( rawNumEquipList ) 
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

  PlayerSets = SetManager:New( LSD_UNIT_TYPE_PLAYER ) 
  EmptySetManager = SetManager:New( LSD_UNIT_TYPE_GROUP )

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

local function AccessSetManager( api, unitTag, setId ) 
  setId = ConvertDataToUnperfected(setId) 
  local SM  
  if unitTag == "player" then 
    SM = PlayerSets
  else 
    SM = GroupManager:GetSetManager( unitTag )
  end
  --- return values 
  if SM then 
    return SM[api](SM, setId)
  else 
    return 
  end
end

--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ----------------------- %% ]]
--[[ %% -- Exposed Functions -- %% ]]
--[[ %% ----------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]

--- Event (Un-)Registration 
-- eventId, name, callback, unitType, param
function LibSetDetection.RegisterEvent( eventId, name, callback, unitType, param ) 
  return CallbackManager:UpdateRegistry( true, eventId, name, callback, unitType, param)
end

function LibSetDetection.UnregsiterEvent( eventId, name, unitType, param )
  return CallbackManager:UpdateRegistry( false, eventId, name, nil, unitType, param)
end


--- Standard Data Access 
function LibSetDetection.GetUnitSetActiveType( unitTag, setId )
  return AccessSetManager( "GetSetActiveType", unitTag, setId )
end

function LibSetDetection.GetUnitSetNumEquip( unitTag, setId )
  return AccessSetManager( "GetSetNumEquip", unitTag, setId )  
end

function LibSetDetection.GetUnitSetData( unitTag )
  return AccessSetManager( "GetSetData", unitTag, setId )
end


--- Raw Data Access 
function LibSetDetection.GetUnitRawNumEquipList( unitTag ) 
  return AccessSetManager( "GetRawNumEquipList", unitTag )
end

function LibSetDetection.GetPlayerEquippedGear( )
  return ZO_DeepTableCopy( SlotManager.equippedGear )
end


--- Data Availability 
function LibSetDetection.AreUnitDataAvailable( unitTag ) 
  local unitName = GetUnitName(unitTag) 
  if unitName == playerName then return true end 
  return GroupManager.groupSets[unitName] and true or false 
end

function LibSetDetection.GetAvailableUnitTags() 
  local GM = GroupManager 
  if GM.remapRequired then GM:UpdateGroupMap() end 
  local availableTags = {}
  table.insert(availableTags, "player")
  for unitName, _ in pairs(GM.groupSets) do 
    table.insert( availableTags, GM.groupMap[unitName])
  end 
  if GM.isGrouped then table.insert(availableTags, GetLocalPlayerGroupUnitTag() ) end
  return availableTags 
end


--- Utility Functions
function LibSetDetection.ConvertActiveType( activeType ) 
  local activeTypeConversion = {
    [LSD_ACTIVE_TYPE_NONE] = {false, false, false, false},
    [LSD_ACTIVE_TYPE_FRONT_BAR] = {true, false, true, false}, 
    [LSD_ACTIVE_TYPE_BACK_BAR] = {true, false, false, true}, 
    [LSD_ACTIVE_TYPE_DUAL_BAR] = {true, true, true, true},
  }
  if activeTypeConversion[activeType] then 
    local returnTable = activeTypeConversioni[activeType]
    return returnTable[1], returnTable[2], returnTable[3], returnTable[4]
  else 
    return 
  end
end

function LibSetDetection.GetSetIdByItemLink( itemLink )
  local _, _, _, _, _, setId = GetItemLinkSetInfo( itemlink )
  return setId
end

function LibSetDetection.GetSetName( setId ) 
  return GetSetName( setId ) 
end 

function LibSetDetection.GetSetMaxEquip( setId )
  return GetMaxEquip( setId ) 
end

function LibSetDetection.GetEquipSlotList() 
  return ZO_ShallowTableCopy(slotList)
end



--[[ ----------------------------- ]]
--[[ -- Backwards Compatibility -- ]]
--[[ -- for function used in V3 -- ]] 
--[[ --    according to esoui   -- ]]
--[[ ----------------------------- ]]

function LibSetDetection.GetEquippedSetsTable() 
  local PS = PlayerSets
  local returnTable = {}
  for setId, activeType in pairs( PS.activeList ) do 
    local setData = {}
    setData.name = GetSetName( setId ) 
    setData.maxEquipped = GetMaxEquip( setId ) 
    setData.numEquipped = PS.numEquip[setId] 
    local _, activeOnBody, activeOnFront, activeOnBack = LibSetDetection.ConvertActiveType( activeType)
    setData.activeBar = {
        ["body"] = activeOnBody, 
        ["front"] = activeOnFront, 
        ["back"] = activeOnBack,
    }
    returnTable[setId] = setData 
  end
  return returnTable
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

  ---deserializ input 
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
    if cmd == "dev" and ExoyDev then 
      --- call development functions 
    else 
      d("[LibSetDetection] command unknown")
    end
  end

end


--[[ --------------------------- ]]
--[[ -- Development Functions -- ]]
--[[ --------------------------- ]]

