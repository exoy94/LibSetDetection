LibSetDetection = LibSetDetection or {}
local SetDetector = {}



--- ToDo 
--[[

[ ] queue functionality 
[ ] callback manager with simplified api 
[ ] dataShare:  
    *bool* request bit 
    array:  *10 bit* setId (irgendwann 11)
            *1 bit* - equip/unequipp or *4bit* numEquip - ( this would be only relevant for sets like shattered fate  but add 3 bits for every set )

(
]]

--- queue

local function AddToQueue()
  -- check if call_later exist 
  -- if yes, update timer (probably unregister and register) 
  -- 
end


-- events for set equipped and unequipped happen after queue is done and current table is compared with old table 
-- 




--[[ -- OLD VERSION -- ]]

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
local updatedSlotsSequence = {} --order, in which slots are changed 
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


--[[ ------------------- ]]
--[[ -- Lookup Tables -- ]]
--[[ ------------------- ]]

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


--[[ ------------------ ]]
--[[ -- Table Update -- ]]
--[[ ------------------ ]]

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

  for _,callback in pairs(callbackList.customSlotUpdateEvent) do
    callback( updatedSlotsSequence )
  end
  updatedSlotsSequence = {}

  local setChangesList = SetDetector.DetermineSetChanges()
  -- runn callbacks for every newly equipped and unequipped set
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

--- (un-)registration for callbacks (WIP)
-- origin can be "player" or "group" or "all" (group and player) 
-- setId can be one setId or a setId-table
function LibSetDetection.RegisterForSetChange( origin, callback, setId ) 
  CM:RegisterCallback('SetChange'..origin, callback, setId)
end

function LibSetDetection.UnregisterForSetChange( )
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
