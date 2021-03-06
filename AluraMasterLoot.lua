local AluraMasterLoot = {
  tRaiders = {},
  tLootList = {},
  tSave = {
    tRanks = {},
    bRaidOnly = false,
    nVScrollPos = 0,
    nSortColumn = 0,
    bSortAscending = true,
    nRollSeconds = 16,
  }
}

local knColumns     = string.byte("R") - string.byte("A") + 1
local knNameColumn  = string.byte("A") - string.byte("A") + 1
local knRankColumn  = string.byte("R") - string.byte("A") + 1

local ktNameMap = {
  -- ["Aramunn"] = "Via Aramunn",
}

local kstrRollRegex = "(%S+ %S+) rolls (%d+) %(1%-(%d+)%)"

local ktModsMap = {
  ["MS"] = "bIsMainSpec",
  ["OS"] = "bIsOffSpec",
  ["SG"] = "bIsSidegrade",
  ["SS"] = "bIsSidegrade",
}

-------------
-- General --
-------------

function AluraMasterLoot:OnSlashCommand(strCmd, strParams)
  strParams = string.lower(strParams)
  local strSub, strVal = string.match(strParams, "^%s*(%S+)%s+(%S+)%s*$")
  if not strSub then
    self:SystemPrint("To change settings do /aml SETTING VALUE")
    self:SystemPrint("Available settings:")
    self:SystemPrint("  rolltime")
    self:SystemPrint("Current settings:")
    self:SystemPrint("  Roll Time: "..tostring(self.tSave.nRollSeconds).." seconds")
  elseif strSub == "rolltime" then
    local nTime = tonumber(strVal)
    if nTime then
      self.tSave.nRollSeconds = nTime
      self:SystemPrint("Roll Time set to: "..tostring(self.tSave.nRollSeconds).." seconds")
    else
      self:SystemPrint("Bad value for roll time")
    end
  else
    self:SystemPrint("Unrecognized setting")
  end
end

function AluraMasterLoot:ImportCsv(strCsv)
  if not strCsv then
    self:SystemPrint("Nothing to import")
    return
  end
  local arData = self:ParseCsv(strCsv)
  if not arData or #arData == 0 then
    self:SystemPrint("Failed to parse")
    return
  end
  self:UpdateRankData(arData)
  self:UpdateGrid()
end

function AluraMasterLoot:ParseCsv(strCsv)
  local arTable = {}
  for line in strCsv:gmatch("[^\r\n]+") do
    local arRow = {}
    for cell in line:gmatch("[^\t]+") do
      table.insert(arRow, cell)
    end
    if #arRow == knColumns then
      table.insert(arTable, arRow)
    end
  end
  return arTable
end

function AluraMasterLoot:UpdateRankData(arData)
  self.tSave.tRanks = {}
  for _, arRow in ipairs(arData) do
    self:UpdateMemberRank(arRow)
  end
end

function AluraMasterLoot:UpdateMemberRank(arRow)
  local strName = arRow[knNameColumn]
  local strValue = arRow[knRankColumn]
  local nValue = tonumber(strValue)
  self.tSave.tRanks[strName] = self:ConvertToRank(nValue)
end

function AluraMasterLoot:ConvertToRank(nValue)
  if nValue then
    if nValue > 2.75 then return "T1" end
    if nValue >= 2.0 then return "T2" end
  end
  return "T3"
end

function AluraMasterLoot:UpdateRaiders()
  self.tRaiders = {}
  local nMemberCount = GroupLib.GetMemberCount()
  for idx = 1, nMemberCount do
    local tMember = GroupLib.GetGroupMember(idx)
    local strName = tMember.strCharacterName
    strName = ktNameMap[strName] or strName
    self.tRaiders[strName] = true
  end
end

function AluraMasterLoot:UpdateLootList()
  local arLootList = GameLib.GetMasterLoot()
  local tLootList = {}
  for _, item in ipairs(arLootList) do
    local tLootInfo = self.tLootList[item.nLootId] or {
      tRequests = {}
    }
    tLootList[item.nLootId] = tLootInfo
    tLootList[item.itemDrop:GetItemId()] = tLootInfo
  end
  self.tLootList = tLootList
end

function AluraMasterLoot:CheckForRoll(strText)
  if not self.tRollInfo then return end
  local strName, strRoll, strRange = string.match(strText, kstrRollRegex)
  if strName and strRoll and strRange then
    self.tRollInfo.tRollers[strName] = self.tRollInfo.tRollers[strName] or {}
    if self.tRollInfo.tRollers[strName].tRoll then return end
    self.tRollInfo.tRollers[strName].tRoll = {
      nRoll = tonumber(strRoll),
      nRange = tonumber(strRange),
    }
  end
end

function AluraMasterLoot:CheckForRollModifiers(strName, strText)
  if not self.tRollInfo then return end
  if not (strName and strText) then return end
  self.tRollInfo.tRollers[strName] = self.tRollInfo.tRollers[strName] or {}
  self.tRollInfo.tRollers[strName].tMods = self:DetermineModifiers(strText)
end

function AluraMasterLoot:ParseItemRequest(strName, item, strText)
  local tItem = self.tLootList[item:GetItemId()]
  if not tItem then return end
  tItem.tRequests[strName] = self:DetermineModifiers(strText)
end

function AluraMasterLoot:DetermineModifiers(strText)
  local tMods = {}
  for strWord in string.gmatch(strText, "[^ ]+") do
    local strMod = ktModsMap[string.upper(strWord)]
    if strMod then tMods[strMod] = true end
  end
  return tMods
end

function AluraMasterLoot:OnRollWindowEnd()
  if not self.tRollInfo then
    self:SystemPrint("Roll timer ended but no roll info??")
    return
  end
  local arResults = {}
  for strName, tInfo in pairs(self.tRollInfo.tRollers) do
    self:InsertRollResult(arResults, strName, tInfo)
  end
  if #arResults == 0 then
    self:PartyPrint("============================")
    self:PartyPrint("Nobody rolled. Random it!")
    self:PartyPrint("============================")
    return
  end
  self:PartyPrint("============================")
  self:PartyPrint("Rolling has closed. Results:")
  table.sort(arResults, function(a, b)
    return self:ResultSorter(a, b)
  end)
  for _, tResult in ipairs(arResults) do
    local strRoll = string.format("%3d ", tResult.nRoll)
    strRoll = strRoll..self:GetResultString(tResult)
    self:PartyPrint(strRoll.."    "..tResult.strName)
  end
  self:PartyPrint("============================")
  local tLootInfo = self.tLootList[self.tRollInfo.nLootId]
  if not tLootInfo then
    self:SystemPrint("No longer in the loot table?")
    return
  end
  tLootInfo.arRollResults = arResults
  self.tRollInfo = nil
end

function AluraMasterLoot:InsertRollResult(arResults, strName, tInfo)
  tInfo.tRoll = tInfo.tRoll or {}
  tInfo.tMods = tInfo.tMods or {}
  if tInfo.tRoll.nRange == 100 then
    local tResult = {
      strName = strName,
      strRank = self.tSave.tRanks[strName],
      nRoll = tInfo.tRoll.nRoll,
    }
    for k,v in pairs(tInfo.tMods) do
      tResult[k] = v
    end
    table.insert(arResults, tResult)
  end
end

local karInfo = {
  {
    strKey = "nRoll",
    funcRet = function(a, b)
      return a > b
    end
  }, {
    strKey = "bIsMainSpec",
    funcRet = function(a, b)
      return a
    end
  }, {
    strKey = "bIsOffSpec",
    funcRet = function(a, b)
      return a
    end
  }, {
    strKey = "strRank",
    funcRet = function(a, b)
      return a < b
    end
  }, {
    strKey = "strName",
    funcRet = function(a, b)
      return a < b
    end
  }
}

function AluraMasterLoot:ResultSorter(tA, tB)
  if not tA or not tB then
    return tA ~= nil
  end
  for _, tInfo in ipairs(karInfo) do
    local a = tA[tInfo.strKey]
    local b = tB[tInfo.strKey]
    if a ~= b then
      if a == nil or b == nil then
        return a ~= nil
      else
        return tInfo.funcRet(a, b)
      end
    end
  end
  return false
end

function AluraMasterLoot:GetResultString(tResult)
  return string.format(
    "%s %s %s %s ",
    tResult.bIsMainSpec and "MS" or "      ",
    tResult.bIsOffSpec and "OS" or "     ",
    tResult.bIsSidegrade and "SG" or "    ",
    tResult.strRank or "    "
  )
end

----------------
-- Loot Squid --
----------------

function AluraMasterLoot:HookLootSquid()
  local addon = Apollo.GetAddon("LootSquid")
  if not addon then return end
  local funcItems = addon.RefreshItemList
  addon.RefreshItemList = function(ref, ...)
    funcItems(ref, ...)
    self:UpdateLootSquidItems(ref)
  end
  local funcPlayers = addon.RefreshPlayerList
  addon.RefreshPlayerList = function(ref, item, ...)
    funcPlayers(ref, item, ...)
    self:UpdateLootSquidPlayers(ref, item)
  end
end

function AluraMasterLoot:UpdateLootSquidItems(ref)
  if not GroupLib.AmILeader() and not self.bDebug then return end
  for _, wndItem in ipairs(ref.tItemWindows) do
    local wndOpenRoll = Apollo.LoadForm(self.xmlDoc, "OpenRoll", wndItem, self)
    local item = wndOpenRoll:GetParent():GetData()
    wndOpenRoll:FindChild("Button"):SetData(item)
  end
end

function AluraMasterLoot:UpdateLootSquidPlayers(ref, item)
  if not item then return end
  local tInfo = self.tLootList[item.nLootId]
  if not tInfo then return end
  local arResults = {}
  if tInfo.arRollResults then
    arResults = tInfo.arRollResults
  else
    for strName, tMods in pairs(tInfo.tRequests) do
      local tResult = {
        strName = strName,
        strRank = self.tSave.tRanks[strName],
      }
      for k,v in pairs(tMods) do
        tResult[k] = v
      end
      table.insert(arResults, tResult)
    end
    table.sort(arResults, function(a, b)
      return self:ResultSorter(a, b)
    end)
  end
  local tPlayerInfo = {}
  for idx, tResult in ipairs(arResults) do
    local strResult = self:GetResultString(tResult)
    if tResult.nRoll then
      strResult = string.format("%3d ", tResult.nRoll)..strResult
    end
    tPlayerInfo[tResult.strName] = {
      nPosition = idx,
      strPrefix = strResult,
    }
  end
  for strName, wndPlayer in pairs(ref.tPlayerWindows) do
    local tInfo = tPlayerInfo[strName]
    if tInfo then
      local wndName = wndPlayer:FindChild("Name")
      wndName:SetText(tInfo.strPrefix.."    "..wndName:GetText())
    end
  end
  ref.wndPlayerList:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop, function(a, b)
    local aName = a:GetData().name
    local bName = b:GetData().name
    local aInfo = tPlayerInfo[aName]
    local bInfo = tPlayerInfo[bName]
    if aInfo and bInfo then
      return aInfo.nPosition < bInfo.nPosition
    elseif aInfo or bInfo then
      return aInfo ~= nil
    else
      return aName < bName
    end
  end)
end

-----------------------
-- Chat Input/Output --
-----------------------

function AluraMasterLoot:FindChannels()
  for _, channel in pairs(ChatSystemLib.GetChannels()) do
    if channel:GetType() == ChatSystemLib.ChatChannel_Party then
      self.channelParty = channel
    elseif channel:GetType() == ChatSystemLib.ChatChannel_Whisper then
      self.channelWhisper = channel
    end
  end
  if not self.channelParty then
    self:SystemPrint("Error: Party channel not found")
  end
end

function AluraMasterLoot:SystemPrint(message)
  ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_System, message, "AML")
end

function AluraMasterLoot:PartyPrint(message)
  if not self.channelParty or self.bDebug then
    self:SystemPrint("[PARTY] "..message)
  else
    self.channelParty:Send(message)
  end
end

function AluraMasterLoot:WhisperAramunn(message)
  if not self.channelWhisper then return end
  for strName in pairs(self.tRaiders) do
    if string.match(strName, " Aramunn") then
      self.channelWhisper:Send(strName.." "..message)
      return
    end
  end
end

function AluraMasterLoot:HandleSystemMessage(tMessage)
  for _, tSegment in ipairs(tMessage.arMessageSegments) do
    if tSegment.strText then
      self:CheckForRoll(tSegment.strText)
    end
  end
end

function AluraMasterLoot:HandlePartyMessage(tMessage)
  local strText = ""
  local arItems = {}
  for _, tSegment in ipairs(tMessage.arMessageSegments) do
    if tSegment.strText then
      strText = strText.." "..tSegment.strText
    end
    if tSegment.uItem then
      table.insert(arItems, tSegment.uItem)
    end
  end
  self:CheckForRollModifiers(tMessage.strSender, strText)
  for _, item in ipairs(arItems) do
    self:ParseItemRequest(tMessage.strSender, item, strText)
  end
end

function AluraMasterLoot:OnChatMessage(channel, tMessage)
  local eType = channel:GetType()
  if eType == ChatSystemLib.ChatChannel_System then
    self:HandleSystemMessage(tMessage)
  elseif eType == ChatSystemLib.ChatChannel_Party then
    self:HandlePartyMessage(tMessage)
  end
end

-----------------
-- UI Updating --
-----------------

function AluraMasterLoot:LoadMainWindow()
  if self.wndMain and self.wndMain:IsValid() then
    self.wndMain:Destroy()
  end
  self.wndMain = Apollo.LoadForm(self.xmlDoc, "Main", nil, self)
  self.wndMain:FindChild("Raid"):SetCheck(self.tSave.bRaidOnly)
  self:UpdateGrid()
end

function AluraMasterLoot:UpdateGrid()
  if not self.wndMain or not self.wndMain:IsValid() then return end
  local wndGrid = self.wndMain:FindChild("Grid")
  wndGrid:DeleteAll()
  if not self.tSave.tRanks then return end
  self:UpdateRaiders()
  for strName, strRank in pairs(self.tSave.tRanks) do
    self:AddRow(wndGrid, strName, strRank)
  end
  if self.tSave.nSortColumn > 0 then
    wndGrid:SetSortColumn(self.tSave.nSortColumn, self.tSave.bSortAscending)
  end
  wndGrid:SetVScrollPos(self.tSave.nVScrollPos)
end

function AluraMasterLoot:AddRow(wndGrid, strName, strRank)
  if self.tSave.bRaidOnly then
    if not self.tRaiders[strName] then
      return
    end
  end
  local nRow = wndGrid:AddRow("blah")
  wndGrid:SetCellText(nRow, 1, strName)
  wndGrid:SetCellText(nRow, 2, strRank)
  wndGrid:SetCellSortText(nRow, 2, strRank..strName)
end

---------------
-- UI Events --
---------------

function AluraMasterLoot:OnImport(wndHandler, wndControl)
  local wndClipboard = self.wndMain:FindChild("Clipboard")
  wndClipboard:SetText("")
  wndClipboard:PasteTextFromClipboard()
  self:ImportCsv(wndClipboard:GetText())
end

function AluraMasterLoot:OnRaidCheck(wndHandler, wndControl)
  self.tSave.bRaidOnly = true
  self:UpdateGrid()
end

function AluraMasterLoot:OnRaidUncheck(wndHandler, wndControl)
  self.tSave.bRaidOnly = false
  self:UpdateGrid()
end

function AluraMasterLoot:OnMouseButtonUp(wndHandler, wndControl)
  local wndGrid = self.wndMain:FindChild("Grid")
  self.tSave.nSortColumn = wndGrid:GetSortColumn()
  self.tSave.bSortAscending = wndGrid:IsSortAscending()
end

function AluraMasterLoot:OnMouseWheel(wndHandler, wndControl)
  local wndGrid = self.wndMain:FindChild("Grid")
  self.tSave.nVScrollPos = wndGrid:GetVScrollPos()
end

function AluraMasterLoot:OnClose(wndHandler, wndControl)
  if self.wndMain and self.wndMain:IsValid() then
    self.wndMain:Destroy()
  end
end

function AluraMasterLoot:OnOpenRoll(wndHandler, wndControl)
  local item = wndControl:GetData()
  self:PartyPrint("=======================================")
  self:PartyPrint("Rolling now open for the following item")
  self:PartyPrint(item.itemDrop:GetChatLinkString())
  self:PartyPrint("=======================================")
  self.tRollInfo = {
    nLootId = item.nLootId,
    tRollers = {},
  }
  self.timerRoll = ApolloTimer.Create(self.tSave.nRollSeconds, false, "OnRollWindowEnd", self)
end

----------------------------
-- State Saving/Restoring --
----------------------------

function AluraMasterLoot:OnSave(eLevel)
  if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm then return nil end
  return self.tSave
end

function AluraMasterLoot:OnRestore(eLevel, tSave)
  for k,v in pairs(tSave) do
    if self.tSave[k] ~= nil then
      self.tSave[k] = v
    end
  end
end

----------------------------
-- Debug Stuff --
----------------------------

function AluraMasterLoot:OnDebug()
  self.bDebug = not self.bDebug
  local str = self.bDebug and "ON" or "off"
  self:SystemPrint("Debug is "..str)
end

function AluraMasterLoot:OnTestRoll()
  self.bDebug = true
  self.tRollInfo = {
    nLootId = 0,
    tRollers = {},
  }
  local nMemberCount = GroupLib.GetMemberCount()
  for idx = 1, nMemberCount do
    local tMember = GroupLib.GetGroupMember(idx)
    local strName = tMember.strCharacterName
    if math.random() < .1 then
      self.tRollInfo.tRollers[strName] = {
        tRoll = {
          nRoll = math.random(100),
          nRange = 100
        }
      }
    end
  end
  self:OnRollWindowEnd()
end

function InspectTable(t)
  local str = "{ "
  for k,v in pairs(t) do
    str = str.."\""..tostring(k).."\"="
    if type(v) == "table" then
      str = str..InspectTable(v).." "
    else
      str = str.."\""..tostring(v).."\" "
    end
  end
  return str.."}"
end

--------------------
-- Initialization --
--------------------

function AluraMasterLoot:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function AluraMasterLoot:Init()
  Apollo.RegisterAddon(self)
end

function AluraMasterLoot:OnLoad()
  self.xmlDoc = XmlDoc.CreateFromFile("AluraMasterLoot.xml")
  self.xmlDoc:RegisterCallback("OnDocumentReady", self)
end

function AluraMasterLoot:OnDocumentReady()
  if not self.xmlDoc then return end
  if not self.xmlDoc:IsLoaded() then return end
  Apollo.RegisterSlashCommand("arv", "LoadMainWindow", self)
  Apollo.RegisterSlashCommand("aml", "OnSlashCommand", self)
  Apollo.RegisterSlashCommand("amldebug", "OnDebug", self)
  Apollo.RegisterSlashCommand("amltestroll", "OnTestRoll", self)
  Apollo.RegisterEventHandler("ChatMessage",      "OnChatMessage",  self)
  Apollo.RegisterEventHandler("Group_Join",       "UpdateGrid",     self)
  Apollo.RegisterEventHandler("Group_Left",       "UpdateGrid",     self)
  Apollo.RegisterEventHandler("Group_Add",        "UpdateGrid",     self)
  Apollo.RegisterEventHandler("Group_Remove",     "UpdateGrid",     self)
  Apollo.RegisterEventHandler("MasterLootUpdate", "UpdateLootList", self)
  Apollo.RegisterEventHandler("LootAssigned",     "UpdateLootList", self)
  Apollo.RegisterEventHandler("Group_Left",       "UpdateLootList", self)
  self:FindChannels()
  self:HookLootSquid()
  self:UpdateLootList()
end

local AluraMasterLootInst = AluraMasterLoot:new()
AluraMasterLootInst:Init()
