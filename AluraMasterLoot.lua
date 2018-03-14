local AluraMasterLoot = {
  tSave = {
    arData = {},
    bRaidOnly = false,
    nVScrollPos = 0,
    nSortColumn = 0,
    bSortAscending = true,
  }
}

local knColumns     = string.byte("R") - string.byte("A") + 1
local knNameColumn  = string.byte("A") - string.byte("A") + 1
local knRankColumn  = string.byte("R") - string.byte("A") + 1

local ktNameMap = {
  -- ["Aramunn"] = "Via Aramunn",
}

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

-----------------------
-- Chat Input/Output --
-----------------------

function AluraMasterLoot:SystemPrint(message)
  ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_System, message, "AML")
end

function AluraMasterLoot:PartyPrint(message)
  ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Party, message, "AML")
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
  Apollo.RegisterEventHandler("Group_Join",   "UpdateGrid", self)
  Apollo.RegisterEventHandler("Group_Left",   "UpdateGrid", self)
  Apollo.RegisterEventHandler("Group_Add",    "UpdateGrid", self)
  Apollo.RegisterEventHandler("Group_Remove", "UpdateGrid", self)
end

local AluraMasterLootInst = AluraMasterLoot:new()
AluraMasterLootInst:Init()
