--[[ ------------------- ]]
--[[ -- ToDo / Notes  -- ]]
--[[ ------------------- ]]

-- debugVar definition
-- setId threshold? 
-- think about error codes
-- not sure, if "IsValid....Type" is necessary
-- rethink debugFunc, put call behind debugVar to prevent unnecessary str building 
-- loop over filter if table for (un-)register
--- 0. remove remnants of first code playarounds 
--- 1. make list of entities and their tasks,
--- 2. then outline function 
--- 3. then programm them step by step


--- entities (CallbackManager, SetDetector, DataShare, Queue? )
-- define entities at the beginning 
-- use local tables within the entities, but access them through the entitty 

LibSetDetection = LibSetDetection or {}
local libName = "LibSetDetection"
local libVersion = 4
local EM = GetEventManager() 
local SV 

--[[ -------------- ]]
--[[ -- Entities -- ]]
--[[ -------------- ]]
 
local CallbackManager = {} --CM 
local BroadcastManager = {} -- BM
local SetDetector =  {} -- SM

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

local function GetSetIdBySlotId( slotId )
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

local function GetSetNameBySetId( setId ) 
  local _, setName = GetItemSetInfo( setId )
  return setName
end 

local function GetMaxEquipBySetId( setId )
  local _, _, _, _, _, maxEquip = GetItemSetInfo( setId )
  return maxEquip
end



--[[ ----------- ]]
--[[ -- Debug -- ]] 
--[[ ----------- ]]

debugMsg = function( msg,  ) 
  if not SV.debug then return end
  d( zo_strformat("[<<1>>-LSD] <<2>>", GetTimeString(), msg) )
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
-- *filter*:nilable (if *registryType = "SetChange", needs to be table of numbers (setIds) )

--- result code definition
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

--- registry initialization
CallbackManager.registry = {
    ["playerSetChange"] = {}, 
    ["playerSetChangeFiltered"] = {}, 
    ["playerDataUpdated"] = {}, 
    ["groupSetChange"] = {}, 
    ["groupSetChangeFiltered"] = {},
    ["groupDataUpdated"] = {},  
  }


function CallbackManager.IsValidUnitType( unitType )
  local unitTypeList = { ["player"] = true, ["group"] = true }
  return unitTypeList[unitType]
end


function CallbackManager.IsValidFilter( registryType, filter) 
  if not filter then return true end -- filter is nilable
  -- filter for setChanges needs to be number 
  if registryType == "SetChange" then 
    if IsTable(filter) then 
      for _, setId in pairs(filter) do 
        if not IsNumber(filter) then return false end
      end
      return true
    end
  else 
    return false
  end
end   


function CallbackManager.BuildRegistryName( registryType, unitType, filterTable ) 
  -- dynamically building name of table in registry
  -- adds suffix "Filtered" if filter exists
  return zo_strformat("<<1>><<2>>", unitType, registryType, filter and "Filtered" or "")
end 


function CallbackManager.HandleRegistration(action, registryType, unitType, id, callback, filterTable)
  --[[Info]]
  -- interface between exposed function and callback manager
  -- validates user input 
  --[[Inputs]] 
  -- *action* (bool) - true/registration or false/unregistration
  --[[Output]]
  -- *resultCode* (number) - code to determine outcome of (un-)registration
  local CM = CallbackManager
  local resultCode = CALLBACK_RESULT_SUCCESS 

  --- verify user inputs 
  if not IsString(id) then resultCode = CALLBACK_RESULT_INVALID_NAME end 
  if not CM.IsValidUnitType(unitType) then resultCode = CALLBACK_RESULT_INVALID_UNITTYPE end
  if not IsFunction(callback) then resultCode = CALLBACK_RESULT_INVALID_CALLBACK end 
  if not CM.IsValidFilter( reqistryType, filterTable) then result = CALLBACK_RESULT_INVALID_FILTER end 

  --- determine the correct registry table name 
  local registryName = CM.BuildRegistryName( registryType, unitType, filterTable)

  --- perform (un-)registration
  if resultCode == CALLBACK_RESULT_SUCCESS then 
    for _,filter in pairs(filterTable) do 
      if action then 
        resultCode = CM.RegisterCallback( registryName, filter, id, callback )
      else
        resultCode = CM.UnregisterCallback( registryType, filter, id )
      end 
    end
  end

  if SV.debug then 
    local filterStr = "{"
    for _, filter in pairs(filterTable) do 
      filterStr = zo_strformat("<<1>>, <<2>>", filterStr, filter) 
    end
    filterStr = filterStr.."}"
    debugMsg( zo_strformat("<<1>>: <<2>>register, <<3>>, <<4>>, <<5>>, <<6>>", CM.results[resultCode], action and "" or "un", registryType, unitType, id, filterStr) )  
  end

  --- provide result code to caller
  return resultCode
end   -- End of HandleRegistration



function CallbackManager.RegisterCallback( registryName, filter, id, callback )
  local CM = CallbackManager

  --- getting list of already registered callbacks 
  local callbackList
  if filter then  
    -- initializes filter subTable 
    CM.registry[registryName][filter] = CM.registry[registryName][filter] or {} 
    callbackList = CM.registry[registryName][filter] 
  else 
    callbackList = CM.registry[name]
  end

  --- verifying name is unique 
  if callbackList[id] then return CALLBACK_RESULT_DUPLICATE_NAME end
  
  --- add callback to list
  callbackList[id] = callback 
  return CALLBACK_RESULT_SUCCESS
end   -- End of RegisterCallback



function CallbackManager.UnregisterCallback( registryName, filter, id )  
  local callbackList 

  --- verify that name exists
  if not callbackList[id] then return CALLBACK_RESULT_UNKNOWN_NAME end 

  --- remove callback from list 
  callbackList[id] = nil 
  return CALLBACK_RESULT_SUCCESS
end   -- End of UnregisterCallback



function CallbackManager.FireCallbacks( registryType, unitType, filter, ...)  
  local CM = CallbackManager
  local name = CM.BuildRegistryName( registryType, uniType, filter) 
  local callbackList = {}

  -- get list of callbacks 
  if filter then 
    if CM.registry[name][filter] then  -- check if any entries for filter exist
      callbackList = CM.registry[name][filter] -- filtered case
    end
  else 
    callbackList = CM.registry[name] -- non filtered case
  end 

  -- early out if no callbacks exist 
  if ZO_IsTableEmpty(callbackList) then return end 

  -- debug of registryName and filter (if existing)
  if SV.debug then 
    debugMsg(zo_strformat("FireCallbacks for ><<1>>< <<2>>", name, filter and "("..tostring(filter)")") or "")
  end
  -- fire all callbacks with provided arguments 
  for _, callback in pairs( callbackList ) do 
    callback(...) 
  end
end   -- End of FireCallbacks



--- Exposed Functions for Registration/Unregistration 

-- user input: unitType, id, callback, {setIds} - optional
function LibSetDetection.RegisterForSetChange( ... )
  return CallbackManager.HandleRegistrations( true, "SetChange", ...)
end

-- user input: unitType, id, callback
function LibSetDetection.RegisterForDataUpdate( ... ) 
  return CallbackManager.HandleRegistrations( true, "DataUpdate", ...)
end

-- user input: unitType, id, callback, {setIds} - (optional)
function LibSetDetection.UnregisterSetChange( ... ) 
  return CallbackManager.HandleRegistrations( false, "SetChange", ...)
end

-- user input: unitType, id, callback
function LibSetDetection.UnregisterDataUpdate( ... ) 
  return CallbackManager.HandleRegistrations( false, "DataUpdate", ...)
end

--[[ End of CallbackManager ]]




--[[ %%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ----------------- %% ]]
--[[ %% -- Set Manager -- %% ]]
--[[ %% ----------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%% ]]

SetManager.__index = SetManager 

function SetManager:New() 
  self.
  self.data -- current datqa 
  self.reference = self:InitReference()  -- last setup to determine changes 
end


function SetManager:InitReference() 
  local reference = {
    ["data"] = {}, 
  }
  return reference
end

function SetManager:GetTemplate() 

end


function SetManager:HandlePerfectedSet() 

end


function SetManager:AnalyseData() 

end


function SetManager:DetermineChanges() 
  -- try the _eq thing, moony showed me

  -- do this after AnalyseData on all aspects 

end

function SetManager:UpdateData( newData )
  -- clear reference 
  -- safe current state as reference  
  -- write new data to data 
  for setId, setData in ipairs( newData ) 
    data[setId] = data 
  end


end


function SetManager:FinishedUpdatingData() 
  -- send data to callback manager or broadcast 
end


PlayerSets = SetManager:New("player") 




--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------- %% ]]
--[[ %% -- Group Manager -- %% ]]
--[[ %% ------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]

GroupSets[charName] = SetManager:New("group") 
 
-- knowing who has addon active 
-- communication with broadcast manager to wake up, go dormant 



--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------ %% ]]
--[[ %% -- Set Detector -- %% ]]
--[[ %% ------------------ %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]

--[[ IDEA ]]

--[[
* make a class for one unit (this can be player or group member) 
* contains function for analysis of setup, determining changes etc 
* attribut for player or group, to select correct callbacks/broadcast 
* or do it by name?! 
* 





]]


--[[ ----- ]]


--------

--- initialize set detector 

SetDetector.equippedSets = { ["player"]={}, ["group"]={} }

function SetDetector.Initialize() 
  for slotId, _ in pairs( equipSlotList ) do 
      equippedSet[slotId] = 0
  end
end

--[[ -- Player Sets -- ]]
function SetDetector.UpdateSlot( slotId )
  local setList = SetDetector.equippedSets.player
  -- keeping track, which slot has which set
  setList[slotId] = GetSetIdBySlotId(slotId)
  -- if two-handers, assigns setId of main-hand to off-hand  
  if IsWeaponSlot( slotId ) then
    setList[EQUIP_SLOT_OFF_HAND] = GetSetIdBySlotId( EQUIP_SLOT_OFF_HAND )
    setList[EQUIP_SLOT_BACKUP_OFF] = GetSetIdBySlotId( EQUIP_SLOT_BACKUP_OFF )
    if IsTwoHander(EQUIP_SLOT_MAIN_HAND) then
      setList[EQUIP_SLOT_OFF_HAND] = GetSetIdBySlotId(EQUIP_SLOT_MAIN_HAND)
    end
    if IsTwoHander(EQUIP_SLOT_BACKUP_MAIN) then
      setList[EQUIP_SLOT_BACKUP_OFF] = GetSetIdBySlotId(EQUIP_SLOT_BACKUP_MAIN)
    end
  end
  --- continue processing
end

function SetDetector.UpdateAllSlots() 
  for slotId, _ in pairs( equipSlotList ) do 
    SetDetector.UpdateSlot( slotId )    
  end 
end

function SetDetector.QueueAnalysis() --- only for player, group already has enough queue upto this point 
  if SetDetector.queue then 
    zo_removeCallLater( SetDetector.queue ) 
  end
  SetDetector.queue = zo_callLater( 
    function() 
      SetDetector.queue = nil 
      SetDetector.AnalyseSetup() 
    end, 1000)
end


function SetDetector.AnalyseSetup() --- for group and player
  -- input is table with entry for each setId 
  -- with numBody, numFront and numBack 

  -- determine 
end

-- determine which sets are equipped/ unequipped 
-- determine what has changed 

--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ---------------------- %% ]]
--[[ %% -- BroadcastManager -- %% ]]
--[[ %% ---------------------- %% ]]


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

local DataMsg = {} 
function DataMsg:Initialize() 
  self.handler = BroadcastManager.LGB:DefineMessageHandler( 1, "LibSetDetection_Data" )
  local dataArray = StructuredArrayField:New( "SetData", {minSize = 1, maxSize = 8} )
  dataArray:AddField( NumericField:New("setId", {min=0, max=1023} ) ) 
  dataArray:AddField( NumericField:New("numBody", {min=0, max=10} ) )
  dataArray:AddField( NumericField:New("numFront", {min=0, max=2}) )
  dataArray:AddField( NumericField:New("numBack", {min=0, max=2}) )
  self.handler:AddField( dataArray )
  self.handler:Finalize() 
  self.handler:OnData( self:OnIncomingMsg ) 
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

function DataMsg:SendCurrentSetup() 
  local currentSetup -- request current setup
  local data = self:SerilizeData( currentSetup ) 
  self.handler:Send( data ) 
end

function DataMsg:SerilizeData( data ) 
  -- format data for data broadcast
  local formattedData = {}
  for setId, setData in pairs( data ) do 
    table.insert(formattedData, {
      setId = setId, 
      numBody = setData.numBody, 
      numFront = setData.numFront, 
      numBack = setData.numBack,
    }
  end
  return formattedData
end

function DataMsg:DeserilizeData( rawData ) 
  local data 
  for _, setData in ipairs(rawData) do 
    data[setData.setId] = {
      ["numBody"] = setData.numBody, 
      ["numFront"] = setData.numFront, 
      ["numBack"] = setData.numBack, 
    }
  end  
  return data
end

function DataMsg:OnIncomingMsg(unitTag, rawData) 
  local charName = GetUnitName("unitTag")
  if GetUnitName("player") == charName then 
    return --- detected msg send by myself (ToDo)
  end
  local data = self:DeserilizeData(rawData)
  --- send data to group/set manager api 
end

--[[ -- End of DataMsg -- ]]
--[[ -------------------- ]]


function BroadcastManager.Initialize() 
  BroadcastManager.LGB = LibGroupBroadcast 
  BroadcastManager.DataMsg = DataMsg:Inialize() 
end


--[[ %% ----------------------------- %% ]]
--[[ %% -- End of BroadcastManager -- %% ]]
--[[ %% ----------------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ]]



--[[ ---------------- ]]
--[[ -- ZOS Events -- ]]
--[[ ---------------- ]]

local function OnSlotUpdate(_, _, slotId, _, _, _) 
  SetDetector.UpdateSlot(slotId)
end

local function OnArmoryOperation() 
  zo_callLater( function() SetDetector.UpdateAllSlots() end, 1000)
end

local function OnInitialPlayerActivated() 
  --- ScanSetup 
  SetDetector.UpdateAllSlots()
  EM:UnregisterForEvent( libName .."PlayerActivated", EVENT_PLAYER_ACTIVATED)
end

--[[ -------------------- ]]
--[[ -- Initialization -- ]]
--[[ -------------------- ]]

local function Initialize() 
  local defaults = {
    ["debug"] = false, 
  }
  SV = ZO_SavedVars:NewAccountWide( "LibSetDetectionSV", 0, nil, defaults, "SavedVariables" )

  SetDetector.Inialize() 
  BroadcastManager.Initalize() 

  --- Register Events 
  EM:RegisterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, SetDetector.OnSlotUpdate )
  EM:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_BAG_ID, BAG_WORN)
  EM:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_IS_NEW_ITEM, false)
  EM:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_INVENTORY_UPDATE_REASON , INVENTORY_UPDATE_REASON_DEFAULT)
  EM:RegisterForEvent( libName.."PlayerActivated", EVENT_PLAYER_ACTIVATED, SetDetector.OnInitialPlayerActivated )
  EM:RegisterForEvent( libName.."ArmoryChange", EVENT_ARMORY_BUILD_OPERATION_STARTED, SetDetector.OnArmoryOperation )
end


local function OnAddonLoaded(_, name) 
  if name == libName then 
    Initialize() 
    EM:UnregisterForEvent( libName, EVENT_ADD_ON_LOADED)
  end
end


EM:RegisterForEvent( libName, EVENT_ADD_ON_LOADED, OnAddonLoaded)



--[[ %%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ----------------- %% ]]
--[[ %% -- OLD VERSION -- %% ]]
--[[ %% ----------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%% ]]

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

--[[ -------------------------------- ]]
--[[ -- Exposed Functions (Legacy) -- ]]
--[[ -------------------------------- ]]

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
  
  --- Initialize Tables
    for slotId, _ in pairs( equipSlotList ) do
      mapSlotSet[slotId] = 0
    end

    --- Register Events
    em:RegisterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, SetDetector.OnSlotUpdate )
    em:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_BAG_ID, BAG_WORN)
    em:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_IS_NEW_ITEM, false)
    em:AddFilterForEvent( libName.."EquipChange", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_INVENTORY_UPDATE_REASON , INVENTORY_UPDATE_REASON_DEFAULT)
    ---new: INVENTORY_UPDATE_REASON_ARMORY_BUILD_CHANGED
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