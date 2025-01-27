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



Search on ESOUI Source Code GetItemSetUnperfectedSetId(integer itemSetId)
  Returns: integer unperfectedSetId 
]]


LibSetDetection = LibSetDetection or {}
local libName = "LibSetDetection"
local libVersion = 4
local EM = GetEventManager() 
local SV 

--[[ -------------- ]]
--[[ -- Entities -- ]]
--[[ -------------- ]]
 
local CallbackManager = {}  -- CM 
local BroadcastManager = {} -- BM
local SetDetector = {}      -- SD 
local PlayerSets = {}       -- PS
local GroupSets = {}        -- GS
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
LSD_CHANGETYPE_UNEQUIPPED = 1 
LSD_CHANGETYPE_EQUIPPED = 2
LSD_CHANGETYPE_UPDATE = 3

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


--[[ ----------- ]]
--[[ -- Debug -- ]] 
--[[ ----------- ]]

local function debugMsg( msg ) 
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
  return zo_strformat("<<1>><<2>><<3>>", unitType, registryType, filterTable and "Filtered" or "")
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
  local name = CM.BuildRegistryName( registryType, unitType, filter) 
  local callbackList = {}

  -- get list of callbacks 
  if filter then 
    if CM.registry[name][filter] then  -- check if any entries for filter exist
      callbackList = CM.registry[name][filter] -- filtered case
    end
  else 
    callbackList = CM.registry[name] -- non filtered case
  end 

  -- debug of registryName and filter (if existing)
  if SV.debug then 
    debugMsg(zo_strformat("FireCallbacks for ><<1>>< <<2>>", name, filter and "("..tostring(filter)..")" or "") )
  end

    -- early out if no callbacks exist 
    if ZO_IsTableEmpty(callbackList) then return end 

  -- fire all callbacks with provided arguments 
  for _, callback in pairs( callbackList ) do 
    callback(...) 
  end
end   -- End of FireCallbacks

--[[ End of CallbackManager ]]




--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------ %% ]]
--[[ %% -- Set Detector -- %% ]]
--[[ %% ------------------ %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]

SetDetector.__index = SetDetector 

function SetDetector:New( unitType, unitTag )
  -- unitType ("player" or "group")
  -- unitTag at the time of creation
  self.setData = initSetData or {}
  self.unitType = unitType
  self.unitTag = unitType == "player" and "player" or unitTag 

  self.numEquip = {}
  self.active = {}
  self.lastChanges = {}
  self.archive = {}   -- last setup to determine changes 
  return self
end


function SetDetector:AnalyseData()
  self.active = {}
  --- handle perfect/unperfect
  local numEquipTemp = {}
  for setId, numEquip in pairs(self.numEquip) do 
    local unperfSetId = GetItemSetUnperfectedSetId(setId)
    if unperfSetId ~= 0 then 
      numEquipTemp[unperfSetId] = {}
      for barName, _ in pairs(barList) do 
        numEquipTemp[unperfSetId][barName] = numEquip[barName] + self.numEquip[unperfSetId] 
      end
    else 
      -- making sure values for unperfected set are not overwritten
      -- if it is done after the perfected
      numEquipTemp[setId] = numEquipTemp[setId] or numEquip 
    end
  end
  --- determine active sets
  local active = {}
  for setId, numEquip in pairs( numEquipTemp ) do   
    local numFront = numEquip["body"] + numEquip["front"] 
    local numBack = numEquip["body"] + numEquip["back"] 
    local maxEquip = GetMaxEquip(setId)
    active["front"] = numFront > maxEquip
    active["back"] = numBack > maxEquip
    active["body"] = numEquip["body"] > maxEquip
    self.active[setId] = active 
  end
end


function SetDetector:DetermineChanges() 
  local changes = {}
  for setId, active in pairs(self.active) do
    local function GetActiveState( t )
      -- active state refers to if the set is active on any bar 
      -- result false = all false 
      -- result true = one is true
      local isActive = false
      for _, isActiveOnBar in pairs( t )do
        isActive = isActive or isActiveOnBar
      end
    end
    local oldState = self.archive.active[setId] and GetActiveState(self.archive.active[setId]) or false
    local newState = GetActiveState( active ) 
    if oldState ~= newState then
      changes[setId] = newState and LSD_CHANGETYPE_EQUIPPED or LSD_CHANGETYPE_UNEQUIPPED -- use local Vars
    else
      -- check if the activeBar changed without changing the 
      -- overall active state 
      local wasUpdate = false 
      for barName, _ in pairs (barList) do 
        if self.archive.active[setId][barName] ~= self.active[setId][barName] then 
          wasUpdate = true
          break
        end
      end
      changes[setId] = wasUpdate and LSD_CHANGETYPE_UPDATE or nil 
    end
    self.lastChanges = changes
  end

  -- check if any set is no longer included in current table 
  -- this means it was unequipped 
  for setId, active in pairs(self.archive.active) do 
    if not self.active[setId] then diff[setId] = false end 
  end
end


function SetDetector:UpdateArchive() 
  self.archive = {} 
  self.archive["numEquip"] = self.numEquip
  self.archive["active"] = self.active
end


function SetDetector:UpdateData( numEquipUpdate, unitTag )
  self.unitTag = unitTag
  self:UpdateArchive() 
  for setId, numEquip in pairs(numEquipUpdate) do 
    self.numEquip[setId] = numEquip
  end
  self:AnalyseData() 
  self:DetermineChanges() 
  
  d("numEquip")
  d(self.numEquip)
  d("-----")
  d("numEquip Archive")
  d(self.archive.numEquip)
  d("-----")
  d("active")
  d(self.active)
  d("----")
  d("active Archive")
  d(self.archive.active)
  d("-----")
  d("lastChanges")
  d(self.lastChanges) 
  d("=====")
  --self:FireCallbacks() 
end


function SetDetector:FireCallbacks() 
  for setId, changeType in pairs(self.lastChanges) do 
    CallbackManager.FireCallbacks("SetChange", self.unitType, nil, changeType, setId, self.unitTag, self.active["body"], self.active["front"], self.active["back"]) 
    CallbackManager.FireCallbacks("SetChange", self.unitType, setId, changeType, setId, self.unitTag, self.active["body"], self.active["front"], self.active["back"]) 
  end
  CallbackManager.FireCallbacks("DataUpdate", "player")
end


--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------- %% ]]
--[[ %% -- Group Manager -- %% ]]
--[[ %% ------------------- %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%%% ]]

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
    -- BroadcastManager.LGB = LibGroupBroadcast 
    -- BroadcastManager.DataMsg = DataMsg:Inialize() 
  end


--[[ -------------- ]]
--[[ -- Data Msg -- ]]
--[[ -------------- ]]

function DataMsg:Initialize() 
  self.handler = BroadcastManager.LGB:DefineMessageHandler( 1, "LibSetDetection_Data" )
  local dataArray = StructuredArrayField:New( "SetData", {minSize = 1, maxSize = 8} )
  dataArray:AddField( NumericField:New("setId", {min=0, max=1023} ) ) 
  dataArray:AddField( NumericField:New("numBody", {min=0, max=10} ) )
  dataArray:AddField( NumericField:New("numFront", {min=0, max=2}) )
  dataArray:AddField( NumericField:New("numBack", {min=0, max=2}) )
  self.handler:AddField( dataArray )
  self.handler:Finalize() 
  self.handler:OnData( function() self:OnIncomingMsg() end ) 
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
    } )
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

--[[ -------------------- ]]
--[[ -- End of DataMsg -- ]]
--[[ -------------------- ]]


--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]]
--[[ %% ------------------ %% ]]
--[[ %% -- Slot Manager -- %% ]]
--[[ %% ------------------ %% ]]
--[[ %%%%%%%%%%%%%%%%%%%%%%%% ]] 


function SlotManager:Initialize() 
  self.equippedSets = {} 
  for slotId, _ in pairs( equipSlotList ) do 
    self.equippedSets[slotId] = 0 
  end
  self.waitTime = 1000 --- ToDo add setting for advanced user ? 
  self.pauseTransmission = false
end


function SlotManager:UpdateSlot( slotId ) 
  -- keeping track, which slot has which set
  self.equippedSets[slotId] = GetSetId(slotId)
  -- if two-handers, assigns setId of main-hand to off-hand  
  if IsWeaponSlot( slotId ) then
    self.equippedSets[EQUIP_SLOT_OFF_HAND] = GetSetId( EQUIP_SLOT_OFF_HAND )
    self.equippedSets[EQUIP_SLOT_BACKUP_OFF] = GetSetId( EQUIP_SLOT_BACKUP_OFF )
    if IsTwoHander(EQUIP_SLOT_MAIN_HAND) then
      self.equippedSets[EQUIP_SLOT_OFF_HAND] = GetSetId(EQUIP_SLOT_MAIN_HAND)
    end
    if IsTwoHander(EQUIP_SLOT_BACKUP_MAIN) then
      self.equippedSets[EQUIP_SLOT_BACKUP_OFF] = GetSetId(EQUIP_SLOT_BACKUP_MAIN)
    end
  end
  if not self.pauseTransmission then self:QueueTransmission() end --- ToDo SendData with queue
end


function SlotManager:QueueTransmission() 
  if self.queue then zo_removeCallLater( self.queue ) end
  self.queue = zo_callLater( function() self:TransmitData() end, self.waitTime)
end


function SlotManager:UpdateAllSlots() 
  self.pauseTransmission = true
  for slotId, _ in pairs (equipSlotList) do 
    self:UpdateSlot( slotId ) 
  end 
  self.pauseTransmission = false 
  self:TransmitData() 
end


function SlotManager:TransmitData() 
  local numEquipUpdate = {} 
  for barName, _ in pairs(barList) do  -- body, front, back 
    for slotId, _ in pairs( slotList[barName]) do 
      local setId = self.equippedSets[slotId] 
      numEquipUpdate[setId] = numEquipUpdate[setId] or { ["body"]=0, ["front"]=0, ["back"]=0 }
      numEquipUpdate[setId][barName] = numEquipUpdate[setId][barName] + 1
    end
  end
  self.queue = nil 
  PlayerSets:UpdateData( numEquipUpdate ) 
end   -- End of SendData


--[[ ---------------- ]]
--[[ -- ZOS Events -- ]]
--[[ ---------------- ]]

local function OnSlotUpdate(_, _, slotId, _, _, _) 
  SlotManager:UpdateSlot(slotId)
end

local function OnArmoryOperation() 
  zo_callLater( function() SlotManager:UpdateAllSlots() end, 1000)
end

local function OnInitialPlayerActivated() 
  EM:UnregisterForEvent( libName .."InitialPlayerActivated", EVENT_PLAYER_ACTIVATED)
  SlotManager:UpdateAllSlots()
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
--    1. unitType (string - case sensitive): "player" or "group" 
--    2. id (string - case sensitive): unique name (for each registryType/unitType) 
--    3. callback (function): called when appropriate callbacks fire
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
  return CallbackManager.HandleRegistrations( true, "SetChange", ...)
end

function LibSetDetection.UnregisterSetChange( ... ) 
  return CallbackManager.HandleRegistrations( false, "SetChange", ...)
end



function LibSetDetection.RegisterForDataUpdate( ... ) 
  return CallbackManager.HandleRegistrations( true, "DataUpdate", ...)
end

function LibSetDetection.UnregisterDataUpdate( ... ) 
  return CallbackManager.HandleRegistrations( false, "DataUpdate", ...)
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
        if string.find( string.lower(setName), string.lower(param[2]) ) then 
          d( zo_strformat("<<1>> - <<2>>", i, setName))
        end
      end
      d("--------------------")
    else 
      d("[LibSetDetection] search string is missing ")
    end
  else 
    if cmd == "dev" then 
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
  d(SlotManager.equippedSets)
end

function Development.OutputPlayerSets() 
  d(PlayerSets)
end
