LibSetDetection = LibSetDetection or {}

local SetDetector = {}
local CallbackManager = {}

local LibExoY = LibExoYsUtilities

--[[ ------------------- ]]
--[[ -- ToDo / Notes  -- ]]
--[[ ------------------- ]]

-- debugVar definition
-- setId threshold? 
-- think about error codes
-- not sure, if "IsValid....Type" is necessary
-- rethink debugFunc, put call behind debugVar to prevent unnecessary str building 
-- loop over filter if table for (un-)register


--[[ ----------------------- ]]
--[[ -- Utility Functions -- ]]
--[[ ----------------------- ]]

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


--[[ ----------- ]]
--[[ -- Debug -- ]] 
--[[ ----------- ]]

debugMsg = function( dType, msg ) 
  if LibExoY then LibExoY.Debug( dType, debugVar, "LibSetDetection", msg ) end
  if dType == "dev" then return end -- ignore dev debug without my lib
  d( zo_strformat("[LSD-<<1>>] <<2>>", dType, msg) )
end


--[[ ---------------------- ]]
--[[ -- Callback Manager -- ]]
--[[ ---------------------- ]]

--- initialize registry structure 
CallbackManager.registry = {
    ["playerSetChange"] = {}, 
    ["playerSetChangeFiltered"] = {}, 
    ["playerDataUpdated"] = {}, 
    ["groupSetChange"] = {}, 
    ["groupSetChangeFiltered"] = {},
    ["groupDataUpdated"] = {},  
  }

--- define callback results
local CALLBACK_RESULT_SUCCESS = 0 
local CALLBACK_RESULT_INVALID_CALLBACK = 1 
local CALLBACK_RESULT_INVALID_UNITTYPE = 2 
local CALLBACK_RESULT_INVALID_FILTER = 3
local CALLBACK_RESULT_INVALID_NAME = 4 
local CALLBACK_RESULT_DUPLICATE_NAME = 5
local CALLBACK_RESULT_UNKNOWN_NAME = 6

CallbackManager.results = {
  [CALLBACK_RESULT_SUCCESS] = "success",
  [CALLBACK_RESULT_INVALID_CALLBACK] = "invalid callback",
  [CALLBACK_RESULT_INVALID_UNITTYPE] = "invalid unitType",
  [CALLBACK_RESULT_INVALID_FILTER] = "invalid filter", 
  [CALLBACK_RESULT_INVALID_NAME] = "invalid name",
  [CALLBACK_RESULT_DUPLICATE_NAME] = "duplicate name",
  [CALLBACK_RESULT_UNKNOWN_NAME] = "unkown name",
}


--- callback manager utility

function CallbackManager.IsValidUnitType( unitType )
  local unitTypeList = { ["player"] = true, ["group"] = true }
  return unitTypeList[unitType]
end

function CallbackManager.IsValidFilter( registryType, filter) 
  if not filter then return true end -- filter is nilable
  -- filter for setChanges can be a setId (number) or a table of setIds
  if registryType == "SetChange" then 
    if IsNumber(filter) then return end 
    if IsTable(filter) then 
      for _, setId in pairs(filter) do 
        if not IsNumber(filter) then return false end
      end
      return true
    end
  end
end   

function CallbackManager.BuildRegistryName( registryType, unitType, filter ) 
  -- *registryType* (string - case sensitive ) = "SetChange" or "DataUpdate"
  -- *unitType* (string - case sensitive) = "player" or "group" 
  -- *filter*:nilable - determines if suffix is "Filtered" 
  return zo_strformat("<<1>><<2>>", unitType, registryType, filter and "Filtered" or "")
end   


--- HandleRegistration
-- called by exposed functions for (un-)registration of callbacks 
-- respondsable to check values/format of all inputs provided by user 
-- outputs result of action (success or error code)
function CallbackManager:HandleRegistration(action, registryType, unitType, id, callback, filter) 

  local resultCode = CALLBACK_RESULT_SUCCESS

  --- verify inputs 
  if not IsString(id) then resultCode = CALLBACK_RESULT_INVALID_NAME end 
  if not self.IsValidUnitType(unitType) then resultCode = CALLBACK_RESULT_INVALID_UNITTYPE end
  if not IsFunction(callback) then resultCode = CALLBACK_RESULT_INVALID_CALLBACK end 
  if not self.IsValidFilter( reqistryType, filter) then result = CALLBACK_RESULT_INVALID_FILTER end 

  local registryName = self.BuildRegistryName( registryType, unitType, filter)

  --- perform (un-)registration
  if resultCode == CALLBACK_RESULT_SUCCESS then 
    if action then 
      resultCode = self:RegisterCallback( registryName, filter, id, callback )
    else
      resultCode = self:UnregisterCallback( registryType, filter, id )
    end 
  end

  --- development debug
  if LibExoY and ExoyDev then 
    local filterStr = ""
    if IsNumber(filter) then filterStr = tostring(filter) end 
    if IsTable(filter) then 
      filterStr = "{"
      for _, subFilter in pairs(filter) do 
        filterStr = zo_strformat("<<1>>, <<2>>", filterStr, subFilter)  
      end
      filterStr = filterStr.."}"
    end
    dbgMsg("dev", zo_strformat("<<1>>: <<2>>register, <<3>>, <<4>>, <<5>>, <<6>>", self.results[resultCode], action and "" or "un", registryType, unitType, id, filterStr) )  
  end

  --- provide resultCode to caller
  return resultCode

end   -- End of HandleRegistration


function CallbackManager:RegisterCallback( registryName, filter, id, callback )
  -- *registryName* (string)
  -- *filter*:nilable 

  --- getting list of already registered callbacks 
  local callbackList
  if filter then  
    -- initializes filter subTable 
    self.registry[registryName][filter] = self.registry[registryName][filter] or {} 
    callbackList = self.registry[registryName][filter] 
  else 
    callbackList = self.registry[name]
  end

  --- verifying name is unique 
  if callbackList[id] then return CALLBACK_RESULT_DUPLICATE_NAME end
  
  --- add callback to list
  callbackList[id] = callback 
  return CALLBACK_RESULT_SUCCESS

end   -- End of RegisterCallback


function CallbackManager:UnregisterCallback( registryName, filter, id ) 
  -- *registryName* (string) 
  -- *filter*:nilable
  -- *id (string)
  
  local callbackList 

  --- verify that name exists
  if not callbackList[id] then return CALLBACK_RESULT_UNKNOWN_NAME end 

  --- remove callback from list 
  callbackList[id] = nil 
  return CALLBACK_RESULT_SUCCESS

end   -- End of UnregisterCallback



function CallbackManager:FireCallbacks( registryType, unitType, filter, ...)  
  -- *name* of registry table 
  -- *filter*:nilable (used to provide setId filter for setChange callbacks) 
  
  local name = self:BuildRegistryName( registryType, uniType, filter) 
  local callbackList = {}

  -- get list of callbacks 
  if filter then 
    if self.registry[name][filter] then  -- check if any entries for filter exist
      callbackList = self.registry[name][filter] -- filtered case
    end
  else 
    callbackList = self.registry[name] -- non filtered case
  end 

  -- early out if no callbacks exist 
  if ZO_IsTableEmpty(callbackList) then return end 

  -- debug of registryName and filter (if existing)
  debugMsg("dev", zo_strformat("FireCallbacks for ><<1>>< <<2>>", name, filter and "("..tostring(filter)")") or "")
  
  -- fire all callbacks with provided arguments 
  for _, callback in pairs( callbackList ) do 
    callback(...) 
  end

end   -- End of FireCallbacks



--- Exposed Functions for Registration/Unregistration 

--input: unitType, id, callback, setId
function LibSetDetection.RegisterForSetChange( ... )
  return CallbackManager:HandleRegistrations( true, "SetChange", ...)
end

--input: unitType, id, callback
function LibSetDetection.RegisterForDataUpdate( ... ) 
  return CallbackManager:HandleRegistrations( true, "DataUpdate", ...)
end

--input: unitType, id, callback, setId
function LibSetDetection.UnregisterSetChange( ... ) 
  return CallbackManager:HandleRegistrations( false, "SetChange", ...)
end

--input: unitType, id, callback
function LibSetDetection.UnregisterDataUpdate( ... ) 
  return CallbackManager:HandleRegistrations( false, "DataUpdate", ...)
end



--- End of CallbackManager


--[[ ------------------- ]]
--[[ -- Queue Manager -- ]]
--[[ ------------------- ]]

-- keeping track of callLater ids

-- application:  wait for slot updates 
-- wait for setUpdates 
--- are those two things actually different? 
--- cuz there can only be a set update if there is a slot update 

-- maybe hook functions in wizzard, dressing room etc to reduce waiting time 
-- start with simple queue 

--- queue for setChanges can be short 
--- but collect data for broadcast (like wait 5sec or something?! )

--- keep those values easy accessable for further tuning 


--[[ -- SetDetector -- ]]

-- account for the possibility, that somebody switches back and forth, 
-- so check, if something actually changed before fireing callbacks 

--- perfected sets 
-- rethink current approach, to reduce everything to non perfected Id 
-- keep track of actual id's 
-- in post processing handle perfect and non-perfected sets 

-- decide, if SetDetector 



--[[ %%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ----------------- %% ]]
--[[ %% -- OLD VERSION -- %% ]]
--[[ %% ----------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%% ]]

local libName = "LibSetDetection"
local libVersion = 4
local em = GetEventManager()
local CM = ZO_CallbackObject:New()
local SV 

local LibExoY = LibExoYsUtilities
local debugMsg

--[[ --------------- ]]
--[[ -- Variables -- ]]
--[[ --------------- ]]

local equippedSets = {}
local completeSets = {}
local mapSlotSet = {}
local updatedSlotsSequence = {} -- records order, in which slots are changed 
local callbackList = {
        setChanges = {
          arbitrary = {},
          specific = {}
        },
        customSlotUpdateEvent = {},
}

--[[ ------------- ]]
--[[ -- Utility -- ]]
--[[ ------------- ]]

-- combines two tables
-- entries with same key will end have value of second table
-- this is not a problem here, because I use it to comebine tables with 
-- slot ids (which are unique) 
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

local function IsNumber( n ) 
  return type(n) == "number"
end

local function IsTable(t)
  return type(t) == "table"
end

local function IsFunction(f)
  return type(f) == "function"
end

--[[ ------------ ]]
--[[ -- Tables -- ]]
--[[ ------------ ]]

local barList = {
    ["front"] = HOTBAR_CATEGORY_PRIMARY,
    ["back"] = HOTBAR_CATEGORY_BACKUP,
    ["body"] = -1,
}

local slotList = {
  ["body"] = {
    [EQUIP_SLOT_HEAD] = "head",                   --  0
    [EQUIP_SLOT_NECK] = "necklace",               --  1
    [EQUIP_SLOT_CHEST] = "chest",                 --  2
    [EQUIP_SLOT_SHOULDERS] = "shoulders",         --  3
    [EQUIP_SLOT_WAIST] = "waist",                 --  6
    [EQUIP_SLOT_LEGS] = "legs",                   --  8
    [EQUIP_SLOT_FEET] = "feet",                   --  9
    [EQUIP_SLOT_RING1] = "ring1",                 -- 11
    [EQUIP_SLOT_RING2] = "ring2",                 -- 12
    [EQUIP_SLOT_HAND] = "hand",                   -- 16
  },
  ["front"] = {
    [EQUIP_SLOT_MAIN_HAND] = "mainFront",         --  4
    [EQUIP_SLOT_OFF_HAND] = "offFront",           --  5
  },
  ["back"] = {
    [EQUIP_SLOT_BACKUP_MAIN] = "mainBack",        -- 20
    [EQUIP_SLOT_BACKUP_OFF] = "offBack",          -- 21
  }
}

local weaponSlotList = MergeTables( slotList["front"], slotList["back"] )
local equipSlotList = MergeTables( slotList["body"], weaponSlotList )

local twoHanderList = {
    [WEAPONTYPE_TWO_HANDED_SWORD] = "greatsword",     --  4
    [WEAPONTYPE_TWO_HANDED_AXE] = "battleaxe",        --  5
    [WEAPONTYPE_TWO_HANDED_HAMMER] = "battlehammer",  --  6
    [WEAPONTYPE_BOW] = "bow",                         --  8
    [WEAPONTYPE_HEALING_STAFF] = "healingstaff",      --  9
    [WEAPONTYPE_FIRE_STAFF] = "firestaff",            -- 12
    [WEAPONTYPE_FROST_STAFF] = "froststaff",          -- 13
    [WEAPONTYPE_LIGHTNING_STAFF] = "lightningstaff",  -- 15
}


--[[ --------------- ]]
--[[ -- Functions -- ]]
--[[ --------------- ]]

local function ConvertToUnperfectedSetId( setId )
  local unperfectedSetId = GetItemSetUnperfectedSetId( setId )
  if unperfectedSetId == 0 then
    return setId
  else
    return unperfectedSetId
  end
end

local function GetSetIdBySlotId( slotId )
  local _, _, _, _, _, setId = GetItemLinkSetInfo( GetItemLink(BAG_WORN, slotId) )
  setId = ConvertToUnperfectedSetId( setId )
  return setId
end

local function GetCustomSetInfo( setId )
  local _, setName, _, _, _, maxEquipped = GetItemSetInfo( setId )
  return setName, maxEquipped
end

local function IsWeaponSlot( slotId )
  return weaponSlotList[slotId] ~= nil
end

local function IsTwoHander( slotId )
  local weaponType = GetItemWeaponType(BAG_WORN, slotId)
  return twoHanderList[weaponType] ~= nil
end


--[[ --------------- ]]
--[[ -- Templates -- ]]
--[[ --------------- ]]

-- templates for table initializations to
-- ensure propper structure and prevent lua
-- errors by referring to unexisting subtables
local function GetEquippedSetEntryTemplate(setId)
  local setName, maxEquipped = GetCustomSetInfo( setId )
  return { setName=setName, maxEquipped = maxEquipped, numEquipped = {front=0, back=0, body=0}, activeBar = {} }
end

local function GetMapBarSetTemplate()
  return {front={}, back={}, body={}, frontSpecific={}, backSpecific={}}
end


--[[ ----------------- ]]
--[[ -- Slot Update -- ]]
--[[ ----------------- ]]

function SetDetector.DelayedUpdateAllSlots(delay)
  if not delay then delay = 1000 end
  SetDetector.delayedUpdateCallback = zo_callLater( function()
    SetDetector.UpdateAllSlots()
  end, delay)
end

function SetDetector.UpdateAllSlots()
  -- looping through all slots (e.g. after a reload)
  -- pauseUpdate prevents unnessary register/stopping of queue timer 
  SetDetector.pauseUpdate = true
  for slotId, _ in pairs( equipSlotList ) do
    table.insert(updatedSlotsSequence, slotId)
    SetDetector.UpdateSingleSlot( slotId )
  end
  SetDetector.pauseUpdate = false
  SetDetector.QueueLookupTableUpdate()
end

function SetDetector.UpdateSingleSlot( slotId )
  -- keeping track, which slot has which set
  mapSlotSet[slotId] = GetSetIdBySlotId(slotId)
  -- handle twohanders
  -- assigns setId to offhand if it is a two hander 
  if IsWeaponSlot( slotId ) then
      mapSlotSet[EQUIP_SLOT_OFF_HAND] = GetSetIdBySlotId( EQUIP_SLOT_OFF_HAND )
      mapSlotSet[EQUIP_SLOT_BACKUP_OFF] = GetSetIdBySlotId( EQUIP_SLOT_BACKUP_OFF )
      if IsTwoHander(EQUIP_SLOT_MAIN_HAND) then
        mapSlotSet[EQUIP_SLOT_OFF_HAND] = GetSetIdBySlotId(EQUIP_SLOT_MAIN_HAND)
      end
      if IsTwoHander(EQUIP_SLOT_BACKUP_MAIN) then
        mapSlotSet[EQUIP_SLOT_BACKUP_OFF] = GetSetIdBySlotId(EQUIP_SLOT_BACKUP_MAIN)
      end
  end
  if not SetDetector.pauseUpdate then 
    SetDetector.QueueLookupTableUpdate()
  end
end


--[[ ------------------- ]]
--[[ -- Lookup Tables -- ]]
--[[ ------------------- ]]

function SetDetector.GetCurrentEquippedSetList()
  local t = {}

  --- numEquipped List
  for bar, _ in pairs( barList ) do   -- front, back, body
    for slotId, _ in pairs( slotList[bar] ) do    -- slotIds of bars
      local setId = mapSlotSet[slotId]
      if not IsTable( t[setId] ) then
        t[setId] = GetEquippedSetEntryTemplate( setId )   -- table, with numEquip for each bar
      end
      t[setId].numEquipped[bar] = t[setId].numEquipped[bar] + 1   -- incremently increase counter for equipped pieces
    end
  end

  --- activeBar list
  for setId, setInfo in pairs(t) do   -- loop through each equipped set
    local activeBar = t[setId]["activeBar"]
    for bar, _ in pairs( barList ) do   -- front, back, body 
      local numEquipped = t[setId]["numEquipped"][bar]
      if bar ~= "body" then   
          numEquipped = numEquipped + t[setId]["numEquipped"]["body"]   -- add body pieces to bar counts
      end
      activeBar[bar] = numEquipped >= setInfo.maxEquipped   -- decides if fully equipped (true) for each bar
    end 
    -- something is active on body, if it is active on front and back
    activeBar["body"] = activeBar["front"] and activeBar["back"]  
  end
  t[0] = nil --- why???
  return t
end

-- 
function SetDetector.GetCurrentCompleteSetList()
  local t = {}
  for setId, setInfo in pairs(equippedSets) do
    for bar, active in pairs(setInfo.activeBar) do
      if active and not t[setId] then
        t[setId] = GetCustomSetInfo(setId)
      end
    end
  end
  return t
end


function SetDetector.GetCurrentBarSetMap()
  local mapBarSet = GetMapBarSetTemplate()
  for setId, setInfo in pairs(equippedSets) do
    for bar, _ in pairs(barList) do   -- front, back, body
      if setInfo.activeBar[bar] then  -- list active sets for each bar
        mapBarSet[bar][setId] = GetCustomSetInfo(setId) -- [setId] = *setName* 
      end
    end
  end
  -- determines sets, they are explusively front or backbar
  for setId, _ in pairs(mapBarSet.front) do
    if not mapBarSet.body[setId] then
      mapBarSet.frontSpecific[setId] = GetCustomSetInfo(setId)
    end
  end
  for setId, _ in pairs(mapBarSet.back) do
    if not mapBarSet.body[setId] then
      mapBarSet.backSpecific[setId] = GetCustomSetInfo(setId)
    end
  end
  return mapBarSet
end


--[[ ------------------ ]]
--[[ -- Table Update -- ]]
--[[ ------------------ ]]

function SetDetector.QueueLookupTableUpdate()
  -- performane a "LookupTableUpdate" after a second 
  -- timer resets if function is re-called 
  if SetDetector.updateCallback then
    zo_removeCallLater( SetDetector.updateCallback )
  end
  SetDetector.updateCallback = zo_callLater( function()
    SetDetector.updateCallback = nil
    SetDetector.LookupTableUpdate()
  end, 1000)
end

function SetDetector.LookupTableUpdate()
  -- update/ recalculate all tables 
  SetDetector.lastCompleteSets = ZO_ShallowTableCopy(completeSets)
  equippedSets = SetDetector.GetCurrentEquippedSetList()
  completeSets = SetDetector.GetCurrentCompleteSetList()
  SetDetector.mapBarSet = SetDetector.GetCurrentBarSetMap()
  SetDetector.RunCallbackManager()  -- perform all registered callbacks
end


--[[ -------------- ]]
--[[ -- Analysis -- ]]
--[[ -------------- ]]

function SetDetector.DetermineSetChanges()
  -- compare currently complete sets with last recorded list of complete sets
  local setChangesList = {}
  -- determine which sets were newly equipped
  for setId, _ in pairs(completeSets) do
    if not SetDetector.lastCompleteSets[setId] then
      setChangesList[setId] = true
    end
  end
  -- determine, which sets where newly unequipped
  for setId, _ in pairs(SetDetector.lastCompleteSets) do
    if not completeSets[setId] then
      setChangesList[setId] = false
    end
  end
  -- setChangesList contains a table with 
  --    key: setId 
  --    value: equipped (true) or unequipped (false) 
  return setChangesList
end

--[[ --------------- ]]
--[[ -- Callbacks -- ]]
--[[ --------------- ]]

function SetDetector.RunCallbackManager()
  -- run callbacks for every newly equipped and unequipped set

  for _,callback in pairs(callbackList.customSlotUpdateEvent) do
    -- callback all registered slot updates 
    callback( updatedSlotsSequence )
  end
  updatedSlotsSequence = {}

  local setChangesList = SetDetector.DetermineSetChanges()

  for setId, changeStatus in pairs( setChangesList ) do
    debugMsg( zo_strformat("player <<1>>equipped <<2>> (<<3>>)", changeStatus and "" or "un", GetCustomSetInfo(setId), setId) )

    if SV.enableDataShare then 
      MsgHandler.SetChange:Send( {setId = setId, status = changeStatus} )
    end

    for _,callback in pairs(callbackList.setChanges.arbitrary) do
      callback(setId, changeStatus)
    end
    if IsTable(callbackList.setChanges.specific[setId]) and not ZO_IsTableEmpty(callbackList.setChanges.specific[setId]) then
      for _, callback in pairs( callbackList.setChanges.specific[setId] ) do
        callback(setId, changeStatus)
      end
    end
  end

end


--[[ ------------ ]]
--[[ -- Events -- ]]
--[[ ------------ ]]

function SetDetector.OnInitialPlayerActivated()
  SetDetector.DelayedUpdateAllSlots()
  em:UnregisterForEvent( libName.."InitialPlayerActivated", EVENT_PLAYER_ACTIVATED)
end

function SetDetector.OnArmoryOperation()
  SetDetector.DelayedUpdateAllSlots()
end

function SetDetector.OnSlotUpdate(_, _, slotId, _, _, _)
  table.insert(updatedSlotsSequence, slotId) 
  SetDetector.UpdateSingleSlot( slotId )
end


--[[ -------------------------------------- ]]
--[[ -- Sets of GroupMembers (DataShare) -- ]]
--[[ -------------------------------------- ]]

local LGB = LibGroupBroadcast
local MsgHandler = {}
local GroupSets = {}

--- send functions 
local function SendSetChange( setId, status ) 
    MsgHandler.SetChange:Send( {setId = setId, status = status} ) 
end

local function SendLoadout( request ) 
  local setTable = {}
  for setId, _ in pairs(completeSets) do 
    table.insert(setTable, setId) 
  end
  MsgHandler.SetChange:Send( {request = request, setTable = setTable} ) 
end

--- receive functions
local function OnGroupSetChange( tag, data ) 
  local charName = GetUnitName(tag) 
  GroupSets[charName] = GroupSets[charName] or {}
  GroupSets[charName][data.setId] = data.status
  -- fire some events  
  debugMsg( zo_strformat("<<1>> (<<2>>) <<3>> equipped <<4>> (<<5>>)", charName, tag, data.status and "" or "un", GetCustomSetInfo(data.setId, setId) ) )
end

local function OnGroupLoadout( tag, data ) 
  local charName = GetUnitName(tag) 
  GroupSets[charName] = GroupSets[charName] or {}
  for _, setId in ipairs(data.setTable) do 
    GroupSets[charName][data.setId] = true
  end
  if data.request then 
     SendLoadout( false )  
  end
  -- fire some events  
  -- add some debug 
end

local function InitializeMsgHandler() 
  MsgHandler.SetChange = LGB:DefineMessageHandler( 101, "LSD_SetChange" )
  MsgHandler.SetChange:AddField( NumericField:New("setId", {min = 0, max = 2047}) )
  MsgHandler.SetChange:AddField( FlagField:New("status")) 
  MsgHandler.SetChange:Finalize( ) 
  MsgHandler.SetChange:OnData( OnGroupSetChange )

  MsgHandler.Loadout = LGB:DefineMessageHandler( 102, "LSD_Loadout" )
  MsgHandler.Loadout:AddField( NumericArrayField:New("setTable", {minSize = 0, maxSize = 7}, {min = 0, max = 2047}) )
  MsgHandler.Loadout:AddField( FlagField:New("request")) 
  MsgHandler.Loadout:Finalize() 
end



--[[ ----------------------- ]]
--[[ -- Exposed Functions -- ]]
--[[ ----------------------- ]]

--- Custom Callback Manager 

local CallbackManager = {} 

--- callbacks for setChanges 
function CallbackManager:FireSetChangeCallbacks( unitType, unitTag, setId, changeType ) 
  for _, callback in ipairs( self.setChangeCallbacks[unitType] ) do 
    callback( unitTag, setId, changeType )
  end
  for _, callback in ipais( self.setChangeCallbacks.specific[unitType][setId] ) do 
    callback( unitTag, setId, changeType )  
  end
end

function CallbackManager:RegisterSetChangeCallback(callback, unitType, setId) 
  if not setId then 
    table.insert( self.setChangeCallbacks[unitType], callback ) 
  else 
    if not IsTable( self.setChangeCallbacks.specific[unitType][setId] ) then 
      self.setChangeCallbacks.specific[unitType][setId] = {}
    end
    table.insert( self.setChangeCallbacks.specific[unitType][setId], callback )
  end
end

--- callback for custom player Slot Update event 

--- callbacks for group data have changed 

function CallbackManager:RegisterCallback(  )


------ 
local function IsSetIdFilterCorrectFormat( var ) 
  if not IsNumber(var) then return false end 
  if IsTable(var) then 
    for k,v in pairs(var) do 
      if not IsNumber(v) then return false end 
    end
  end
  return true
end

local function CM:RegisterCallbacks() 

end

function LibSetDetection.RegisterForPlayerSetUpdate( name, callback, setIdFilter) 
  
  --- verify inputs 
  -- check if name exist 
  -- check if callback is function 
  -- check if filter is of correct format 

  local result = RegisterCallbacks( )
  return result
end

function LibSetDetection.UnregisterForPlayerSetUpdate( name ) 

end


local unitList = {
  ["player"] = 1,
  ["group"] = 2,
  ["all"] = 3,
}
--- (un-)registration for callbacks (WIP)
-- origin can be "player" or "group" or "all" (group and player) 
-- callback needs to be a function 
-- origin nilable (default = "player")
-- setId:nilable (default = nil) - number or numericTable with numbers 

-- Result List: 
  -- Result = 0 (Successful Registration) 
  -- Result = 1 (Duplicate Id)
  -- Result = 2 (Unvalid Callback)
  -- Result = 3 (Invalid Origin)
  -- Result = 4 (Invalid Format for SetId Filter)
local list = {}

function FireCallbacks( unit, setId, changeType )

  for _, data in pairs(list[unit]) do 
    
    -- setId = 0 means all 
    if data.setId == 0 or data.setId == setId then 
      data.callback(unit, setId, changeType)
    end

  end


end


function LibSetDetection.RegisterForSetChange(name, callback, unitType, setId )

  --- defaults 
  
  --- verfiy inputs
  if not CallbackManager:IsNameAvailable( name, "setChange", unitType, ) then return 1 end
  if cccmList[id] then return 1 end   -- check for duplicate id 
  if not IsFunction(callback) then return 2 end   -- check for invalid callback (not a function)
  unitType = unitType and unitType or "player"    -- apply origin default value 
  if not unitList[unitType] then return 3 end   -- check for invalid origin (nil, player, group, all) 
  if not IsNumber(setId) then return 4 end ---TODO support table
  


  local AddToTable = function( unitType ) 
    table.insert(list[unitType], {callback = callback, setId = setId})
  end

  if origin == "all" then 
    AddToTable("player")
    AddToTable("group")
  else 
    AddToTable(origin)
  end

    -- custom callback manager 
    --[[ CCM = {

        } ]]
  return 0
end


--- (un-)registration for callbacks of player
function LibSetDetection.RegisterForSetChanges(name, callback)
  if IsFunction(callback) then
    callbackList.setChanges.arbitrary[name] = callback
  end
end

function LibSetDetection.RegisterForSpecificSetChanges(name, setId, callback)
  setId = ConvertToUnperfectedSetId(setId)
  if IsFunction(callback) then
    if not IsTable(callbackList.setChanges.specific[setId]) then
      callbackList.setChanges.specific[setId] = {}
    end
    callbackList.setChanges.specific[setId][name] = callback
  end
end

function LibSetDetection.RegisterForCustomSlotUpdateEvent(name, callback)
  if IsFunction(callback) then
    callbackList.customSlotUpdateEvent[name] = callback
  end
end

function LibSetDetection.UnregisterForCustomSlotUpdateEvent(name)
  callbackList.customSlotUpdateEvent[name] = nil
end

--- advanced informations 
function LibSetDetection.GetNumSetPiecesForHotbar(setId, hotbar)
  setId = ConvertToUnperfectedSetId(setId)
  local barKey = ""
  for k, v in pairs( barList) do
    if v == hotbar then barKey = k end
  end
  if barKey == "" then return 0 end
  if not equippedSets[setId] then return 0 end
  return equippedSets[setId]["numEquipped"][barKey]
end

function LibSetDetection.GetBarActiveSetIdMap()
  return ZO_ShallowTableCopy(SetDetector.mapBarSet)
end

function LibSetDetection.GetEquippedSetsTable()
  return ZO_ShallowTableCopy(equippedSets)
end

function LibSetDetection.GetSlotIdSetIdMap()
  return ZO_ShallowTableCopy(mapSlotSet)
end

function LibSetDetection.GetCompleteSetsList()
  return ZO_ShallowTableCopy(completeSets)
end

function LibSetDetection.GetEquipSlotList()
  return ZO_ShallowTableCopy(slotList)
end



--- GroupMember Sets 

function LibSetDetection.GetGroupMemberSets( tag )
  local charName = GetUnitName( tag ) 
  return GroupSets[charName] 
end 

function LibSetDetection.GetAllGroupMemberSets( )
  return GroupSets
end 


--[[ ------------------- ]]
--[[ -- Settings Menu -- ]] 
--[[ ------------------- ]]

local function GetMenuPanelData()

  local isServerEU = GetWorldName() == "EU Megaserver"

  local function SendIngameMail() 
      SCENE_MANAGER:Show('mailSend')
      zo_callLater(function() 
              ZO_MailSendToField:SetText("@Exoy94")
              ZO_MailSendSubjectField:SetText( libName )
              ZO_MailSendBodyField:TakeFocus()   
          end, 250)
  end

  local function FeedbackButton() 
      ClearMenu() 
      if isServerEU then 
          AddCustomMenuItem("Ingame Mail", SendIngameMail)
      end
      AddCustomMenuItem("Esoui.com", function() RequestOpenUnsafeURL("https://www.esoui.com/downloads/info3338-LibSetDetection.html") end )  
      AddCustomMenuItem("Discord", function() RequestOpenUnsafeURL("https://discord.com/invite/MjfPKsJAS9") end )  

      ShowMenu() 
  end

  local function DonationButton() 
      ClearMenu() 
      if isServerEU then 
          AddCustomMenuItem("Ingame Mail", SendIngameMail)
      end
      AddCustomMenuItem("Buy Me a Coffee!", function() RequestOpenUnsafeURL("https://www.buymeacoffee.com/exoy") end )  
      ShowMenu() 
  end

  return    
  {
      type                = "panel",
      name                = libName,
      displayName         = "Lib Set Detection",
      author              = "|c00FF00ExoY|r (PC/EU)",
      version             = "|cFF8800"..tostring(libVersion).."|r",
      feedback            = FeedbackButton, 
      donation            = isServerEU and DonationButton or "https://www.buymeacoffee.com/exoy",
      registerForRefresh = true,
      registerForUpdate = true,
  }
end

local function CreateSettingsMenu() 
  local LAM2 = LibAddonMenu2

  local optionControls = {} 
  table.insert(optionControls, {
    type = "checkbox", 
    name = "Enable DataShare", 
    getFunc = function() return SV.enableDataShare end,
    setFunc = function(bool) SV.enableDataShare = bool end, 
    warning = "Reloadui required"
  })
  table.insert(optionControls, {type = "divider"} )
  table.insert(optionControls, {
    type = "checkbox", 
    name = "Enable Debug", 
    getFunc = function() return SV.enableDebug end,
    setFunc = function(bool) SV.enableDebug = bool end, 
  })

  LAM2:RegisterAddonPanel(libName.."Menu", GetMenuPanelData() )
  LAM2:RegisterOptionControls(libName.."Menu", optionControls)
end




--[[ ---------------- ]]
--[[ -- Initialize -- ]]
--[[ ---------------- ]]

function SetDetector.Initialize() 

  --- Saved Variables and Settings
  local defaults = { 
    ["enableDebug"] = false,
    ["enableDataShare"] = true,
  }
  SV = ZO_SavedVars:NewAccountWide("LibSetDetectionSV", 0, nil, defaults, "SavedVariables")
  CreateSettingsMenu()
  

  --- Initialize DataShare
  if GetAPIVersion() < 101045 then SV.enableDataShare = false end
  if SV.enableDataShare then 
    InitializeMsgHandler()
  end

  --- Define Debug
  debugMsg = function(msg, dType) 
    if LibExoY then 
      LibExoY.Debug(dType, chatDebug, libName, msg)  
    else 
      d(msg)
    end
  end 

  --- Initialize Tables
    for slotId, _ in pairs( equipSlotList ) do
      mapSlotSet[slotId] = 0
    end

    --- Register Events
    em:RegisterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, SetDetector.OnSlotUpdate )
    em:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_BAG_ID, BAG_WORN)
    em:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_IS_NEW_ITEM, false)
    em:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_INVENTORY_UPDATE_REASON , INVENTORY_UPDATE_REASON_DEFAULT)
    em:RegisterForEvent( libName.."InitialPlayerActivated", EVENT_PLAYER_ACTIVATED, SetDetector.OnInitialPlayerActivated )
    em:RegisterForEvent( libName.."ArmoryChange", EVENT_ARMORY_BUILD_OPERATION_STARTED, SetDetector.OnArmoryOperation )
end

function SetDetector.OnAddonLoaded(_, addonName)
  if addonName == libName then
    SetDetector.Initialize()
    em:UnregisterForEvent(libName, EVENT_ADD_ON_LOADED)
  end
end

em:RegisterForEvent(libName, EVENT_ADD_ON_LOADED, SetDetector.OnAddonLoaded)



--[[ ------------ ]]
--[[ -- Legacy -- ]]
--[[ ------------ ]]