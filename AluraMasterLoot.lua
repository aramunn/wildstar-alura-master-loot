local AluraMasterLoot = {
  tSave = {
    arData = {},
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

-------------
-- General --
-------------

function AluraMasterLoot:ImportCsv(strCsv)
  if not strCsv then
    self:SystemPrint("Nothing to import")
    return
  end
  local arDataTmp = self:ParseCsv(strCsv)
  if not arDataTmp or #arDataTmp == 0 then
    self:SystemPrint("Failed to parse")
    return
  end
  self.tSave.arData = arDataTmp
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

function AluraMasterLoot:UpdateRaiders()
  self.tRaiders = {}
  local nMemberCount = GroupLib.GetMemberCount()
  for nIdx = 1, nMemberCount do
    local tMember = GroupLib.GetGroupMember(nIdx)
    local strName = tMember.strCharacterName
    strName = ktNameMap[strName] or strName
    self.tRaiders[strName] = true
  end
end

function AluraMasterLoot:CheckForRoll(strText)
  if not self.bInRollWindow then return end
  local strName, strRoll, strRange = string.match(strText, kstrRollRegex)
  if strName and strRoll and strRange then
    self.tRollers[strName] = self.tRollers[strName] or {}
    if self.tRollers[strName].tRoll then return end
    self.tRollers[strName].tRoll = {
      nRoll = tonumber(strRoll),
      nRange = tonumber(strRange),
    }
  end
end

function AluraMasterLoot:CheckForRollModifiers(strName, strText)
  if not self.bInRollWindow then return end
  if not strName or not strText then return end
  self.tRollers[strName] = self.tRollers[strName] or {}
  self.tRollers[strName].tMods = DetermineModifiers(strText)
end

function AluraMasterLoot:ParseItemRequest(strName, item, strText)
end

function AluraMasterLoot:DetermineModifiers(strText)
  return {}
end

function AluraMasterLoot:OnRollWindowEnd()
  self.bInRollWindow = false
  --TODO determine winner
end

-----------------------
-- Chat Input/Output --
-----------------------

function AluraMasterLoot:SystemPrint(message)
  ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_System, message, "AML")
end

function AluraMasterLoot:PartyPrint(message)
  ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Party, message, "AML")
end

function AluraMasterLoot:HandleSystemMessage(tMessage)
  for _, tSegment in ipairs(tMessage.arMessageSegments) do
    if tSegment.strText then
      self:CheckForRoll(tSegment.strText)
    end
  end
end

function AluraMasterLoot:HandlePartyMessage(tMessage)
  local strText, arItems = {}
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
  self.wndMain:FindChild("Raid"):SetCheck(self.bRaidOnly)
  self:UpdateGrid()
end

function AluraMasterLoot:UpdateGrid()
  if not self.wndMain or not self.wndMain:IsValid() then return end
  local wndGrid = self.wndMain:FindChild("Grid")
  wndGrid:DeleteAll()
  if not self.tSave.arData then return end
  self:UpdateRaiders()
  for _,arRow in ipairs(self.tSave.arData) do
    self:AddRow(wndGrid, arRow)
  end
  if self.nSortColumn > 0 then
    wndGrid:SetSortColumn(self.nSortColumn, self.bSortAscending)
  end
  wndGrid:SetVScrollPos(self.nVScrollPos)
end

function AluraMasterLoot:AddRow(wndGrid, arRow)
  local strName = arRow[knNameColumn]
  local strRank = arRow[knRankColumn]
  if self.bRaidOnly and not self.tRaiders[strName] then return end
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
  self.bRaidOnly = true
  self:UpdateGrid()
end

function AluraMasterLoot:OnRaidUncheck(wndHandler, wndControl)
  self.bRaidOnly = false
  self:UpdateGrid()
end

function AluraMasterLoot:OnMouseButtonUp(wndHandler, wndControl)
  local wndGrid = self.wndMain:FindChild("Grid")
  self.nSortColumn = wndGrid:GetSortColumn()
  self.bSortAscending = wndGrid:IsSortAscending()
end

function AluraMasterLoot:OnMouseWheel(wndHandler, wndControl)
  local wndGrid = self.wndMain:FindChild("Grid")
  self.nVScrollPos = wndGrid:GetVScrollPos()
end

function AluraMasterLoot:OnClose(wndHandler, wndControl)
  if self.wndMain and self.wndMain:IsValid() then
    self.wndMain:Destroy()
  end
end

function AluraMasterLoot:OnRollForItem(wndHandler, wndControl)
  self.tRollers = {}
  self.itemRoll = wndControl:GetData()
  self.bInRollWindow = true
  ApolloTimer.Create(self.tSave.nRollSeconds, false, "OnRollWindowEnd", self)
end

----------------------------
-- State Saving/Restoring --
----------------------------

function AluraMasterLoot:OnSave(eLevel)
  if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm then return nil end
  return self.tSave
end

function AluraMasterLoot:OnRestore(eLevel, tSave)
  if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm then return end
  for k,v in pairs(tSave) do
    if self.tSave[k] ~= nil then
      self.tSave[k] = v
    end
  end
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
  Apollo.RegisterSlashCommand("aml", "LoadMainWindow", self)
  Apollo.RegisterEventHandler("ChatMessage", "OnChatMessage", self)
  Apollo.RegisterEventHandler("Group_Join",   "UpdateGrid", self)
  Apollo.RegisterEventHandler("Group_Left",   "UpdateGrid", self)
  Apollo.RegisterEventHandler("Group_Add",    "UpdateGrid", self)
  Apollo.RegisterEventHandler("Group_Remove", "UpdateGrid", self)
end

local AluraMasterLootInst = AluraMasterLoot:new()
AluraMasterLootInst:Init()
