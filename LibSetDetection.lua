-- changelog 2->3
-- shallow to deep table
-- performance improvements
-- GetCustomSetInfo

LibSetDetection = LibSetDetection or {}
local SetDetector = {}

local libName = "LibSetDetection"
local em = GetEventManager()

---------------
-- Variables --
---------------

local equippedSets = {}
local completeSets = {}
local mapSlotSet = {}
local updatedSlotsSequence = {}
local callbackList = {
        setChanges = {
          arbitrary = {},
          specific = {}
        },
        customSlotUpdateEvent = {},
      }

------------
-- Tables --
------------

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

------------
-- Lookup --
------------

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

---------------
-- Functions --
---------------

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

local function IsTable(t)
  return type(t) == "table"
end

local function IsFunction( var )
  return type(var) == "function"
end

---------------
-- Templates --
---------------

local function GetEquippedSetEntryTemplate(setId)
  local setName, maxEquipped = GetCustomSetInfo( setId )
  return { setName=setName, maxEquipped = maxEquipped, numEquipped = {front=0, back=0, body=0}, activeBar = {} }
end

local function GetMapBarSetTemplate()
  return {front={}, back={}, body={}, frontSpecific={}, backSpecific={}}
end

-----------------
-- Slot Update --
-----------------

function SetDetector.DelayedUpdateAllSlots(delay)
  if not delay then delay = 1000 end
  SetDetector.delayedUpdateCallback = zo_callLater( function()
    SetDetector.UpdateAllSlots()
  end, delay)
end

function SetDetector.UpdateAllSlots()
  SetDetector.pauseUpdate = true
  for slotId, _ in pairs( equipSlotList ) do
    table.insert(updatedSlotsSequence, slotId)
    SetDetector.UpdateSingleSlot( slotId )
  end
  SetDetector.pauseUpdate = false
  SetDetector.QueueLookupTableUpdate()
end

function SetDetector.UpdateSingleSlot( slotId )
  mapSlotSet[slotId] = GetSetIdBySlotId(slotId)
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

-------------------
-- Lookup Tables --
-------------------

function SetDetector.GetCurrentEquippedSetList()
  local t = {}
  -- numEquipped List
  for bar, _ in pairs( barList ) do
    for slotId, _ in pairs( slotList[bar] ) do
      local setId = mapSlotSet[slotId]
      if not IsTable( t[setId] ) then
        t[setId] = GetEquippedSetEntryTemplate( setId )
      end
      t[setId].numEquipped[bar] = t[setId].numEquipped[bar] + 1
    end
  end
  -- activeBar list
  for setId, setInfo in pairs(t) do
    local activeBar = t[setId]["activeBar"]
    for bar, _ in pairs( barList ) do
      local numEquipped = t[setId]["numEquipped"][bar]
      if bar ~= "body" then
          numEquipped = numEquipped + t[setId]["numEquipped"]["body"]
      end
      activeBar[bar] = numEquipped >= setInfo.maxEquipped
    end
    activeBar["body"] = activeBar["front"] and activeBar["back"]
  end
  t[0] = nil
  return t
end


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
    for bar, _ in pairs(barList) do
      if setInfo.activeBar[bar] then
        mapBarSet[bar][setId] = GetCustomSetInfo(setId)
      end
    end
  end
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

------------------
-- Table Update --
------------------

function SetDetector.QueueLookupTableUpdate()
  if SetDetector.updateCallback then
    zo_removeCallLater( SetDetector.updateCallback )
  end
  SetDetector.updateCallback = zo_callLater( function()
    SetDetector.updateCallback = nil
    SetDetector.LookupTableUpdate()
  end, 1000)
end

function SetDetector.LookupTableUpdate()
  SetDetector.lastCompleteSets = ZO_ShallowTableCopy(completeSets)
  equippedSets = SetDetector.GetCurrentEquippedSetList()
  completeSets = SetDetector.GetCurrentCompleteSetList()
  SetDetector.mapBarSet = SetDetector.GetCurrentBarSetMap()
  SetDetector.RunCallbackManager()
end

--------------
-- Analysis --
--------------

function SetDetector.DetermineSetChanges()
  local setChangesList = {}
  for setId, _ in pairs(completeSets) do
    if not SetDetector.lastCompleteSets[setId] then
      setChangesList[setId] = true
    end
  end
  for setId, _ in pairs(SetDetector.lastCompleteSets) do
    if not completeSets[setId] then
      setChangesList[setId] = false
    end
  end
  return setChangesList
end

---------------
-- Callbacks --
---------------

function SetDetector.RunCallbackManager()

  for _,callback in pairs(callbackList.customSlotUpdateEvent) do
    callback( updatedSlotsSequence )
  end
  updatedSlotsSequence = {}

  local setChangesList = SetDetector.DetermineSetChanges()
  for setId, changeStatus in pairs( setChangesList ) do
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

-----------------------
-- Exposed Functions --
-----------------------

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

------------
-- Events --
------------

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

----------------
-- Initialize --
----------------

function SetDetector.Initialize()

    -- Initialize Tables
    for slotId, _ in pairs( equipSlotList ) do
      mapSlotSet[slotId] = 0
    end

    -- Register Events
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
