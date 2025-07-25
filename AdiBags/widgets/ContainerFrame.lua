--[[
AdiBags - Adirelle's bag addon.
Copyright 2010-2011 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local addonName, addon = ...
local L = addon.L

--<GLOBALS
local _G = _G
local assert = _G.assert
local BACKPACK_CONTAINER = _G.BACKPACK_CONTAINER
local band = _G.bit.band
local BANK_CONTAINER = _G.BANK_CONTAINER
local CreateFrame = _G.CreateFrame
local format = _G.format
local GetContainerFreeSlots = _G.GetContainerFreeSlots
local GetContainerItemID = _G.GetContainerItemID
local GetContainerItemInfo = _G.GetContainerItemInfo
local GetContainerItemLink = _G.GetContainerItemLink
local GetContainerNumFreeSlots = _G.GetContainerNumFreeSlots
local GetContainerNumSlots = _G.GetContainerNumSlots
local GetCursorInfo = _G.GetCursorInfo
local GetItemFamily = _G.GetItemFamily
local GetItemInfo = _G.GetItemInfo
local GetMerchantItemLink = _G.GetMerchantItemLink
local ipairs = _G.ipairs
local KEYRING_CONTAINER = _G.KEYRING_CONTAINER
local max = _G.max
local next = _G.next
local NUM_BAG_SLOTS = _G.NUM_BAG_SLOTS
local pairs = _G.pairs
local PlaySound = _G.PlaySound
local select = _G.select
local strjoin = _G.strjoin
local tinsert = _G.tinsert
local tostring = _G.tostring
local tremove = _G.tremove
local tsort = _G.table.sort
local UIParent = _G.UIParent
local unpack = _G.unpack
local wipe = _G.wipe
--GLOBALS>

local GetSlotId = addon.GetSlotId
local GetBagSlotFromId = addon.GetBagSlotFromId

local ITEM_SIZE = addon.ITEM_SIZE
local ITEM_SPACING = addon.ITEM_SPACING
local SECTION_SPACING = addon.SECTION_SPACING
local BAG_INSET = addon.BAG_INSET
local HEADER_SIZE = addon.HEADER_SIZE



local EasyMenu = EasyMenu
local CreateFrame = CreateFrame
local ToggleDropDownMenu = ToggleDropDownMenu


local menuFrame = CreateFrame("Frame", "menuFrame", UIParent, "UIDropDownMenuTemplate")
local menuList = {
	{text = "|TInterface\\Buttons\\UI-Panel-MinimizeButton-Up:24|t |cffFFA500Close|r", func = function() CloseMenus() end, 
	fontObject = GameFontNormalLarge},

	{text = "  ", notClickable = true},
	{text = "  |TInterface\\Icons\\INV_Misc_Spyglass_03:20|t    "..L["Reset bag position"], func = function() addon:ResetBagPositions() end},	
	{text = "  |TInterface\\Icons\\INV_Misc_Spyglass_03:20|t    "..L["Unlock Anchor"], func = function() addon:ToggleAnchor() end},
	{text = "  |TInterface\\Icons\\INV_TradeskillItem_03:20|t    "..L["Manual Filtering"], func = function() addon:OpenOptions("filters", "FilterOverride") end},
	{text = "  |TInterface\\Icons\\INV_Misc_Gear_01:20|t    "..L["Settings"], func = function() addon:OpenOptions() end},
}

local menuFrame2 = CreateFrame("Frame", "menuFrame2", UIParent, "UIDropDownMenuTemplate")

local menuList2 = {
	{text = "|TInterface\\Buttons\\UI-Panel-MinimizeButton-Up:24|t |cffFFA500Close|r", func = function() CloseMenus() end, 
	fontObject = GameFontNormalLarge},

	{text = "  ", notClickable = true},
	{text = "  |TInterface\\Icons\\INV_Misc_Spyglass_03:20|t    "..L["Reset bag position"], func = function() addon:ResetBagPositions() end},
	{text = "  |TInterface\\Icons\\INV_TradeskillItem_03:20|t    "..L["Manual Filtering"], func = function() addon:OpenOptions("filters", "FilterOverride") end},
	{text = "  |TInterface\\Icons\\INV_Misc_Gear_01:20|t    "..L["Settings"], func = function() addon:OpenOptions() end},
	
}

--------------------------------------------------------------------------------
-- Widget scripts
--------------------------------------------------------------------------------

local function BagSlotButton_OnClick(button)
	if button:GetChecked() then
		button.panel:Show()
		CloseMenus()
	else
		button.panel:Hide()
		CloseMenus()
	end
end

--------------------------------------------------------------------------------
-- Bag creation
--------------------------------------------------------------------------------

local containerClass, containerProto, containerParentProto = addon:NewClass("Container", "LayeredRegion", "AceEvent-3.0", "AceBucket-3.0")

function addon:CreateContainerFrame(...) return containerClass:Create(...) end

local SimpleLayeredRegion = addon:GetClass("SimpleLayeredRegion")

local bagSlots = {}
function containerProto:OnCreate(name, bagIds, isBank)
	self:SetParent(UIParent)
	containerParentProto.OnCreate(self)

	--self:EnableMouse(true)
	self:SetFrameStrata("HIGH")

	self:SetBackdrop(addon.BACKDROP)

	self:SetScript('OnShow', self.OnShow)
	self:SetScript('OnHide', self.OnHide)

	self.name = name
	self.bagIds = bagIds
	self.isBank = isBank

	self.buttons = {}
	self.dirtyButtons = {}
	self.content = {}
	self.stacks = {}
	self.sections = {}

	self.added = {}
	self.removed = {}
	self.changed = {}

	for bagId in pairs(self.bagIds) do
		self.content[bagId] = { size = 0 }
		tinsert(bagSlots, bagId)
		if not addon.itemParentFrames[bagId] then
			local f = CreateFrame("Frame", addonName..'ItemContainer'..bagId, self)
			f.isBank = isBank
			f:SetID(bagId)
			addon.itemParentFrames[bagId] = f
		end
	end

	local button = CreateFrame("Button", nil, self)
	button:SetAllPoints(self)
	button:RegisterForClicks("AnyUp")
	button:SetScript('OnClick', function(_, ...) return self:OnClick(...) end)
	button:SetScript('OnReceiveDrag', function() return self:OnClick("LeftButton") end)
	self.ClickReceiver = button
	local minFrameLevel = button:GetFrameLevel() + 1

	local headerLeftRegion = SimpleLayeredRegion:Create(self, "TOPLEFT", "RIGHT", 4)
	headerLeftRegion:SetPoint("TOPLEFT", BAG_INSET, -BAG_INSET)
	self.HeaderLeftRegion = headerLeftRegion
	self:AddWidget(headerLeftRegion)
	headerLeftRegion:SetFrameLevel(minFrameLevel)

	local headerRightRegion = SimpleLayeredRegion:Create(self, "TOPRIGHT", "LEFT", 4)
	headerRightRegion:SetPoint("TOPRIGHT", -32, -BAG_INSET)
	self.HeaderRightRegion = headerRightRegion
	self:AddWidget(headerRightRegion)
	headerRightRegion:SetFrameLevel(minFrameLevel)

	local bottomLeftRegion = SimpleLayeredRegion:Create(self, "BOTTOMLEFT", "UP", 4)
	bottomLeftRegion:SetPoint("BOTTOMLEFT", BAG_INSET, BAG_INSET)
	self.BottomLeftRegion = bottomLeftRegion
	self:AddWidget(bottomLeftRegion)
	bottomLeftRegion:SetFrameLevel(minFrameLevel)

	local bottomRightRegion = SimpleLayeredRegion:Create(self, "BOTTOMRIGHT", "UP", 4)
	bottomRightRegion:SetPoint("BOTTOMRIGHT", -BAG_INSET, BAG_INSET)
	self.BottomRightRegion = bottomRightRegion
	self:AddWidget(bottomRightRegion)
	bottomRightRegion:SetFrameLevel(minFrameLevel)

	local bagSlotPanel = addon:CreateBagSlotPanel(self, name, bagSlots, isBank)
	bagSlotPanel:Hide()
	self.BagSlotPanel = bagSlotPanel
	wipe(bagSlots)

	local closeButton = CreateFrame("Button", nil, self, "UIPanelCloseButton")
	self.CloseButton = closeButton
	closeButton:SetPoint("TOPRIGHT", -2, -2)
	addon.SetupTooltip(closeButton, L["Close"])
	closeButton:SetFrameLevel(minFrameLevel)

	local bagSlotButton = CreateFrame("CheckButton", nil, self)
	bagSlotButton:SetNormalTexture([[Interface\Buttons\Button-Backpack-Up]])
	bagSlotButton:SetCheckedTexture([[Interface\Buttons\CheckButtonHilight]])
	bagSlotButton:GetCheckedTexture():SetBlendMode("ADD")
	bagSlotButton:SetScript('OnClick', BagSlotButton_OnClick)
	bagSlotButton.panel = bagSlotPanel
	bagSlotButton:SetWidth(18)
	bagSlotButton:SetHeight(18)
	addon.SetupTooltip(bagSlotButton, {
		L["Equipped bags"],
		L["Click to toggle the equipped bag panel, so you can change them."]
	}, "ANCHOR_BOTTOMLEFT", -8, 0)
	headerLeftRegion:AddWidget(bagSlotButton, 50)

	if select(4, GetBuildInfo()) == 40300 then
		-- Search boxes are provided by the 4.3 client
		local searchBox = CreateFrame("EditBox", self:GetName().."SearchBox", self, "BagSearchBoxTemplate")
		searchBox:SetSize(130, 20)
		searchBox:SetFrameLevel(minFrameLevel)
		headerRightRegion:AddWidget(searchBox, -10, 130, 0, -1)
		tinsert(_G.ITEM_SEARCHBAR_LIST, searchBox:GetName())
	end

	local title = self:CreateFontString(self:GetName().."Title","OVERLAY")
	self.Title = title
	title:SetFontObject(addon.bagFont)
	title:SetText(L[name])
	title:SetHeight(18)
	title:SetJustifyH("LEFT")
	title:SetPoint("LEFT", headerLeftRegion, "RIGHT", 4, 0)
	title:SetPoint("RIGHT", headerRightRegion, "LEFT", -4, 0)


	--------------------------------------------------------------------------------
	-- Create Anchored Bag Menu
	--------------------------------------------------------------------------------

		-- create the frame
		local AdiBagsBagMenu = CreateFrame("Frame", "AdiBagsBagMenu", self)
		AdiBagsBagMenu:SetHeight(18)
		AdiBagsBagMenu:SetPoint("LEFT", headerLeftRegion, "RIGHT", 4, 0)
		AdiBagsBagMenu:SetPoint("RIGHT", headerRightRegion, "LEFT", -20, 0)


		--===== Create Tooltip for Anchored Bag Menu =====--
		local function ShowTooltipAnchored()
			GameTooltip:SetOwner(AdiBagsBagMenu, "ANCHOR_TOPLEFT", -25, 8)
			GameTooltip:SetText("\124cFF00FF00"..L["Anchored"].."\124r\124cff00bfff "..L["Mode"].."\124r")
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cffeda55f"..L["Click"].."|r |cff99ff00"..L["to toggle the anchor."].."|r")
			GameTooltip:AddLine("|cffeda55f"..L["Shift-Click"].."|r |cff99ff00"..L["to open bag menu."].."|r")			
			GameTooltip:AddLine("|cffeda55f"..L["Right-Click"].."|r |cff99ff00"..L["to open AdiBags options."].."|r")
			GameTooltip:AddLine("|cffeda55f"..L["Alt-Left-Click"].."|r |cff99ff00"..L["to toggle anchor mode."].."|r")				
			GameTooltip:SetBackdropColor(0, 0, 0, 1) -- Change the alpha value here
			GameTooltip:Show()
		end


		-- create the texture for the background
		local background = AdiBagsBagMenu:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetTexture(0, 1, 0, 0) -- green background with 60% opacity

		-- set the size of the background texture to match the size of the clickable frame
		background:SetSize(AdiBagsBagMenu:GetSize())

		-- create the texture for the border
		local border = AdiBagsBagMenu:CreateTexture(nil, "BORDER")
		border:SetAllPoints()
		border:SetTexture(0.4, 0.4, 0.4, 0) -- gray border

		-- set the frame strata to be higher than the title text's strata
		AdiBagsBagMenu:SetFrameStrata("HIGH")
		AdiBagsBagMenu:SetFrameLevel(100)

		-- add function to hide tooltip
		local function HideTooltip()
			GameTooltip:Hide()
		end



		-- set the frame to be clickable
		AdiBagsBagMenu:SetScript("OnMouseUp", function(self, button)

			local position = self:GetPoint()
			HideTooltip() -- Call the hide tooltip function here

			if button == "RightButton" then -- check if right button was clicked

			addon:OpenOptions()
			self.lastClickTime = 0
			CloseMenus()

			elseif button == "LeftButton" then -- check if left button was clicked

				--===== Create a menu  =====--
				--===== And adjust its position if bag is too close to top edge of screen. =====--
				local x, y = GetCursorPosition()
				local screenHeight = UIParent:GetTop()
				local threshold = 200 -- adjust this value to change the distance from the top edge


				if y > screenHeight - threshold and not IsAltKeyDown() and IsShiftKeyDown() and GetTime() - (self.lastClickTime or 0) < 1 then

    				CloseMenus()
   					self.lastClickTime = 0
   					if addon.db.profile.showAnchorTooltip then
   						ShowTooltipAnchored()
   					end


				elseif y > screenHeight - threshold and not IsAltKeyDown() and IsShiftKeyDown() then -- if the cursor is within the "threshold" distance

					self.lastClickTime = GetTime()
					EasyMenu(menuList, menuFrame, "AdiBagsBagMenu", 0, 0, "MENU", 2)


				elseif not IsShiftKeyDown() and not IsAltKeyDown() then

					addon:ToggleAnchor()
					CloseMenus()
					self.lastClickTime = 0

				elseif IsAltKeyDown() then

					addon:ToggleCurrentLayout()
					self.lastClickTime = 0


				elseif button == "LeftButton" and IsShiftKeyDown() and GetTime() - (self.lastClickTime or 0) < 1 then

    				CloseMenus()
   					self.lastClickTime = 0
   					if addon.db.profile.showAnchorTooltip then
   						ShowTooltipAnchored()
   					end

				elseif button == "LeftButton" and IsShiftKeyDown() then

					self.lastClickTime = GetTime()
					EasyMenu(menuList, menuFrame, "AdiBagsBagMenu", -23, 146, "MENU", 2)

				end

			end

		end)


		AdiBagsBagMenu:SetScript("OnEnter", function()
			if addon.db.profile.showAnchorHighlight then
				background:SetTexture(0, 1, 0, 0.5)
			end
			if addon.db.profile.showAnchorTooltip then
				ShowTooltipAnchored()
			end
		end)


		AdiBagsBagMenu:SetScript("OnLeave", function()
			if addon.db.profile.showAnchorHighlight then
				background:SetTexture(0, 1, 0, 0)
			end
			if addon.db.profile.showAnchorTooltip then
				GameTooltip:Hide()
			end
		end)

		AdiBagsBagMenu:EnableMouse(true)


	--------------------------------------------------------------------------------
	-- Create Anchor to move bag in Manual Mode and add bag menu to it.
	--------------------------------------------------------------------------------

		self.isMovingContainer = false
		local anchor = addon:CreateAnchorWidget(self, name, L[name], self)
		anchor:SetAllPoints(title)
		anchor:EnableMouse(true)
		anchor:SetFrameLevel(self:GetFrameLevel() + 10)



		local function ShowTooltipManual()
			GameTooltip:SetOwner(anchor, "ANCHOR_TOPLEFT", -25, 8)
			GameTooltip:SetText("\124cFFFFA500"..L["Manual"].."\124r \124cff00bfff"..L["Mode"].."\124r")
			GameTooltip:AddLine(" ")
			if addon.db.profile.clickMode == 0 then
			GameTooltip:AddLine("|cffeda55f"..L["Click"].."|r |cff99ff00"..L["to open bag menu."].."|r")
			GameTooltip:AddLine("|cffeda55f"..L["Shift-Click"].."|r |cff99ff00"..L["to move bag container."].."|r")
			else

			GameTooltip:AddLine("|cffeda55f"..L["Click"].."|r |cff99ff00"..L["to move bag container."].."|r")
			GameTooltip:AddLine("|cffeda55f"..L["Shift-Click"].."|r |cff99ff00"..L["to open bag menu."].."|r")
			end

			GameTooltip:AddLine("|cffeda55f"..L["Right-Click"].."|r |cff99ff00"..L["to open AdiBags options."].."|r")
			GameTooltip:AddLine("|cffeda55f"..L["Alt-Left-Click"].."|r |cff99ff00"..L["to toggle anchor mode."].."|r")	
			GameTooltip:SetBackdropColor(0, 0, 0, 1) -- Change the alpha value here
			GameTooltip:Show()
		end

		-- create the texture for the background
		local background = anchor:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetTexture(0, 1, 0, 0) -- green background with 60% opacity

		-- set the size of the background texture to match the size of the clickable frame
		background:SetSize(anchor:GetSize())

		-- create the texture for the border
		local border = anchor:CreateTexture(nil, "BORDER")
		border:SetAllPoints()
		border:SetTexture(0.4, 0.4, 0.4, 0) -- gray border

		-- set the frame strata to be higher than the title text's strata
		anchor:SetFrameStrata("HIGH")
		anchor:SetFrameLevel(100)

		-- add function to hide tooltip
		local function HideTooltip()
			GameTooltip:Hide()
		end





		anchor:SetScript('OnMouseDown', function(self, button, ...)
			if button == 'LeftButton' then

				if IsAltKeyDown() then

					addon:ToggleCurrentLayout()
					
				elseif addon.db.profile.clickMode == 0 and IsShiftKeyDown() then

					self:StartMoving()
					GameTooltip:Hide()
					CloseMenus()
					self.isMovingContainer = true
				elseif addon.db.profile.clickMode == 1 and not IsShiftKeyDown() then
					self:StartMoving()
					GameTooltip:Hide()
					CloseMenus()
					self.isMovingContainer = true


				-- else
				-- CloseMenus()


				end
		end

			if button == 'RightButton' then

				addon:OpenOptions()
				GameTooltip:Hide()
				CloseMenus()
				self.lastClickTime = 0

		    end
		end)


		anchor:SetScript('OnMouseUp', function(self, button, ...)
			if button == 'LeftButton' and self.isMovingContainer then

				self:StopMoving()
				self.isMovingContainer = false
				if not self.isMovingContainer then 

					CloseMenus()
					if addon.db.profile.showAnchorTooltip then
						ShowTooltipManual()
					end

				end

			elseif addon.db.profile.clickMode == 0 and button == 'LeftButton' and not IsShiftKeyDown() then

				GameTooltip:Hide()

				-- create a menu and adjust its position if dropdown is too close to top edge of screen.  
				local x, y = GetCursorPosition()
				local screenHeight = UIParent:GetTop()
				local threshold = 200

				if y > screenHeight - threshold and not IsAltKeyDown() and not IsShiftKeyDown() and GetTime() - (self.lastClickTime or 0) < 1 then

    				CloseMenus()
   					self.lastClickTime = 0
   					if addon.db.profile.showAnchorTooltip then
   						ShowTooltipManual()
   					end


				elseif y > screenHeight - threshold and not IsAltKeyDown() and not IsShiftKeyDown() then 

					self.lastClickTime = GetTime()
					EasyMenu(menuList2, menuFrame2, background, 0, 0, "MENU", 2)

				elseif button == "LeftButton" and GetTime() - (self.lastClickTime or 0) < 1 then

    				CloseMenus()
   					self.lastClickTime = 0
   					if addon.db.profile.showAnchorTooltip then
   						ShowTooltipManual()
   					end

				elseif button == "LeftButton" then

					self.lastClickTime = GetTime()
					EasyMenu(menuList2, menuFrame2, background, -23, 130, "MENU", 2) -- default position
				end

			elseif addon.db.profile.clickMode == 1 and button == 'LeftButton' and IsShiftKeyDown() then


				GameTooltip:Hide()

				-- create a menu and adjust its position if dropdown is too close to top edge of screen.  
				local x, y = GetCursorPosition()
				local screenHeight = UIParent:GetTop()
				local threshold = 200

				if addon.db.profile.clickMode == 1 and y > screenHeight - threshold and not IsAltKeyDown() and not IsShiftKeyDown() and GetTime() - (self.lastClickTime or 0) < 1 then

    				CloseMenus()
   					self.lastClickTime = 0
   					if addon.db.profile.showAnchorTooltip then
   						ShowTooltipManual()
   					end


				elseif addon.db.profile.clickMode == 1 and y > screenHeight - threshold and not IsAltKeyDown() and IsShiftKeyDown() then 

					self.lastClickTime = GetTime()
					EasyMenu(menuList2, menuFrame2, background, 0, 0, "MENU", 2)

				elseif addon.db.profile.clickMode == 1 and button == "LeftButton" and GetTime() - (self.lastClickTime or 0) < 1 then

    				CloseMenus()
   					self.lastClickTime = 0
   					if addon.db.profile.showAnchorTooltip then
   						ShowTooltipManual()
   					end

				elseif addon.db.profile.clickMode == 1 and button == "LeftButton" and IsShiftKeyDown() then

					self.lastClickTime = GetTime()
					EasyMenu(menuList2, menuFrame2, background, -23, 130, "MENU", 2) -- default position
				end


			end
		end)


		anchor:SetScript("OnEnter", function()
			if addon.db.profile.showAnchorHighlight then
				background:SetTexture(1, 0.5, 0, 0.5)
			end
			if addon.db.profile.showAnchorTooltip then
				ShowTooltipManual()
			end
		end)


		anchor:SetScript("OnLeave", function()
			if addon.db.profile.showAnchorHighlight then
				background:SetTexture(0, 1, 0, 0)
			end
			if addon.db.profile.showAnchorTooltip then
				GameTooltip:Hide()
			end
		end)


		-- print("Anchor created for frame:", self:GetName())
		if addon.db.profile.positionMode == 'manual' then
			anchor:Show()
		end

		self.Anchor = anchor






	--------------------------------------------------------------------------------
	-- Show or Hide the title frames depending on current positionmode setting.
	--------------------------------------------------------------------------------

	local RegisterMessage = LibStub('AceEvent-3.0').RegisterMessage

	self.RegisterMessage(anchor, "AdiBags_ManualLayout", function()
		if addon.db.profile.positionMode == 'manual' then
			-- If positionMode is 'anchored', show the frame
			AdiBagsBagMenu:Hide()
			anchor:Show()

		else
			-- If positionMode is NOT 'anchored', hide the frame
			AdiBagsBagMenu:Show()
			anchor:Hide()
		end
	end)


	self.RegisterMessage(AdiBagsBagMenu, "AdiBags_AnchoredLayout", function()
		if addon.db.profile.positionMode == 'anchored' then
			-- If positionMode is 'manual', show the frame
			anchor:Hide()
			AdiBagsBagMenu:Show()
		else
			-- If positionMode is NOT 'manual', hide the frame
			anchor:Show()
			AdiBagsBagMenu:Hide()
		end
	end)



	self.RegisterMessage(anchor, "AdiBags_TimeToCheckAnchorMode", function()
		if addon.db.profile.positionMode == 'manual' then
			-- If positionMode is 'anchored', show the frame
			AdiBagsBagMenu:Hide()
			anchor:Show()

		else
			-- If positionMode is NOT 'anchored', hide the frame
			AdiBagsBagMenu:Show()
			anchor:Hide()
		end
	end)



		self.RegisterMessage(AdiBagsBagMenu, "AdiBags_TimeToCheckAnchorMode", function()
		if addon.db.profile.positionMode == 'anchored' then
			-- If positionMode is 'manual', show the frame
			anchor:Hide()
			AdiBagsBagMenu:Show()
		else
			-- If positionMode is NOT 'manual', hide the frame
			anchor:Show()
			AdiBagsBagMenu:Hide()
		end
	end)



	--------------------------------------------------------------------------------
	-- Some Updating Bag Slots Stuff
	--------------------------------------------------------------------------------


	local content = CreateFrame("Frame", nil, self)
	content:SetPoint("TOPLEFT", BAG_INSET, -addon.TOP_PADDING)
	self.Content = content
	self:AddWidget(content)

	-- self:UpdateBackgroundColor()
	self:UpdateSkin()
	self.paused = true
	self.forceLayout = true

		-- Register persitent listeners
		local name = self:GetName()
		local RegisterMessage = LibStub('AceEvent-3.0').RegisterMessage
		RegisterMessage(name, 'AdiBags_FiltersChanged', self.FiltersChanged, self)
		RegisterMessage(name, 'AdiBags_LayoutChanged', self.LayoutChanged, self)
		RegisterMessage(name, 'AdiBags_ConfigChanged', self.ConfigChanged, self)
end

function containerProto:ToString() return self.name or self:GetName() end

--------------------------------------------------------------------------------
-- Scripts & event handlers
--------------------------------------------------------------------------------

function containerProto:BagsUpdated(bagIds)
	for bag in pairs(bagIds) do
		if self.bagIds[bag] then
			self:UpdateContent(bag)
		end
	end
	self:UpdateButtons()
	self:LayoutSections()
end

function containerProto:CanUpdate()
	return not addon.holdYourBreath and not addon.globalLock and not self.paused and self:IsVisible()
end

function containerProto:FiltersChanged(event, forceLayout)
	if forceLayout then
		self.forceLayout = true
	end
	self.filtersChanged = true
	if self:CanUpdate() then
		self:RedispatchAllItems()
		self:LayoutSections(1)
	end
end

function containerProto:LayoutChanged()
	self.forceLayout = true
	if self:CanUpdate() then
		self:LayoutSections()
	end
end

function containerProto:ConfigChanged(event, name)
	if strsplit('.', name) == 'skin' then
		return self:UpdateSkin()
	end
end

function containerProto:OnShow()
	PlaySound(self.isBank and "igMainMenuOpen" or "igBackPackOpen")
	self:RegisterEvent('EQUIPMENT_SWAP_PENDING', "PauseUpdates")
	self:RegisterEvent('EQUIPMENT_SWAP_FINISHED', "ResumeUpdates")
	self:ResumeUpdates()
	containerParentProto.OnShow(self)
end

function containerProto:OnHide()
	containerParentProto.OnHide(self)
	PlaySound(self.isBank and "igMainMenuClose" or "igBackPackClose")
	self:PauseUpdates()
	self:UnregisterAllEvents()
	self:UnregisterAllMessages()
	self:UnregisterAllBuckets()
end

function containerProto:ResumeUpdates()
	if not self.paused then return end
	self.paused = false
	self.bagUpdateBucket = self:RegisterBucketMessage('AdiBags_BagUpdated', 0.2, "BagsUpdated")
	self:Debug('ResumeUpdates')
	for bag in pairs(self.bagIds) do
		self:UpdateContent(bag)
	end
	if self.filtersChanged  then
		self:RedispatchAllItems()
	else
		self:UpdateButtons()
	end
	self:LayoutSections(0)
end

function containerProto:PauseUpdates()
	if self.paused then return end
	self:Debug('PauseUpdates')
	self:UnregisterBucket(self.bagUpdateBucket, true)
	self.paused = true
end

--------------------------------------------------------------------------------
-- Backdrop click handler
--------------------------------------------------------------------------------

local function FindBagWithRoom(self, itemFamily)
	local fallback
	for bag in pairs(self.bagIds) do
		local numFree, family = GetContainerNumFreeSlots(bag)
		if numFree and numFree > 0 then
			if band(bag == KEYRING_CONTAINER and 256 or family, itemFamily) ~= 0 then
				return bag
			elseif not fallback then
				fallback = bag
			end
		end
	end
	return fallback
end

local FindFreeSlot
do
	local slots = {}
	FindFreeSlot = function(self, item)
		local bag = FindBagWithRoom(self, GetItemFamily(item))
		if not bag then return end
		wipe(slots)
		GetContainerFreeSlots(bag, slots)
		return GetSlotId(bag, slots[1])
	end
end

function containerProto:OnClick(...)
	local kind, data1, data2 = GetCursorInfo()
	local itemLink
	if kind == "item" then
		itemLink = data2
	elseif kind == "merchant" then
		itemLink = GetMerchantItemLink(data1)
	else
		return
	end
	self:Debug('OnClick', kind, data1, data2, '=>', itemLink)
	if itemLink then
		local slotId = FindFreeSlot(self, itemLink)
		if slotId then
			local button = self.buttons[slotId]
			if button then
				local button = button:GetRealButton()
				self:Debug('Redirecting click to', button)
				return button:GetScript('OnClick')(button, ...)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Regions and global layout
--------------------------------------------------------------------------------

function containerProto:AddHeaderWidget(widget, order, width, yOffset, side)
	local region = (side == "LEFT") and self.HeaderLeftRegion or self.HeaderRightRegion
	region:AddWidget(widget, order, width, 0, yOffset)
end

function containerProto:AddBottomWidget(widget, side, order, height, xOffset, yOffset)
	local region = (side == "RIGHT") and self.BottomRightRegion or self.BottomLeftRegion
	region:AddWidget(widget, order, height, xOffset, yOffset)
end

function containerProto:GetContentMinWidth()
	return max(
		(self.BottomLeftRegion:IsShown() and self.BottomLeftRegion:GetWidth() or 0) +
		(self.BottomRightRegion:IsShown() and self.BottomRightRegion:GetWidth() or 0),
		self.Title:GetStringWidth() + 32 +
		(self.HeaderLeftRegion:IsShown() and (self.HeaderLeftRegion:GetWidth() + 4) or 0) +
		(self.HeaderRightRegion:IsShown() and (self.HeaderRightRegion:GetWidth() + 4) or 0)
		)
end

function containerProto:OnLayout()
	local bottomHeight = 0
	if self.BottomLeftRegion:IsShown() then
		bottomHeight = self.BottomLeftRegion:GetHeight() + BAG_INSET
	end
	if self.BottomRightRegion:IsShown() then
		bottomHeight = max(bottomHeight, self.BottomRightRegion:GetHeight() + BAG_INSET)
	end
	self:SetWidth(BAG_INSET * 2 + max(self:GetContentMinWidth(), self.Content:GetWidth()))
	self:SetHeight(addon.TOP_PADDING + BAG_INSET + bottomHeight + self.Content:GetHeight())
end

--------------------------------------------------------------------------------
-- Miscellaneous
--------------------------------------------------------------------------------

function containerProto:UpdateSkin()
	local backdrop, r, g, b, a = addon:GetContainerSkin(self.name)
	self:SetBackdrop(backdrop)
	self:SetBackdropColor(r, g, b, a)
	local m = max(r, g, b)
	if m == 0 then
		self:SetBackdropBorderColor(0.5, 0.5, 0.5, a)
	else
		self:SetBackdropBorderColor(0.5+(0.5*r/m), 0.5+(0.5*g/m), 0.5+(0.5*b/m), a)
	end
end

--------------------------------------------------------------------------------
-- Bag content scanning
--------------------------------------------------------------------------------

local GetDistinctItemID = addon.GetDistinctItemID
local IsValidItemLink = addon.IsValidItemLink

function containerProto:UpdateContent(bag)
	self:Debug('UpdateContent', bag)
	local added, removed, changed = self.added, self.removed, self.changed
	local content = self.content[bag]
	local newSize = GetContainerNumSlots(bag)
	local _, bagFamily = GetContainerNumFreeSlots(bag)
	bagFamily = bag == KEYRING_CONTAINER and 256 or bagFamily
	content.family = bagFamily
	for slot = 1, newSize do
		local itemId = GetContainerItemID(bag, slot)
		-- Explicitly clear empty keyring slots to remove ghost buttons
		if bag == KEYRING_CONTAINER and not itemId then
			if content[slot] then
				removed[content[slot].slotId] = content[slot].link
				content[slot] = nil
			end

		else
			-- ✅ Normal item handling logic
			local link = GetContainerItemLink(bag, slot)
			if not itemId or (link and IsValidItemLink(link)) then
				local slotData = content[slot]
				if not slotData then
					slotData = {
						bag = bag,
						slot = slot,
						slotId = GetSlotId(bag, slot),
						bagFamily = bagFamily,
						count = 0,
						isBank = self.isBank,
					}
					content[slot] = slotData
				end

				local name, count, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice
				if link then
					name, _, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(link)
					count = select(2, GetContainerItemInfo(bag, slot)) or 0
				else
					link, count = false, 0
				end

				if GetDistinctItemID(slotData.link) ~= GetDistinctItemID(link) then
					removed[slotData.slotId] = slotData.link
					slotData.count = count
					slotData.link = link
					slotData.itemId = itemId
					slotData.name, slotData.quality, slotData.iLevel, slotData.reqLevel, slotData.class, slotData.subclass, slotData.equipSlot, slotData.texture, slotData.vendorPrice = name, quality, iLevel, reqLevel, class, subclass, equipSlot, texture, vendorPrice
					slotData.maxStack = maxStack or (link and 1 or 0)
					added[slotData.slotId] = slotData
				elseif slotData.count ~= count then
					slotData.count = count
					changed[slotData.slotId] = slotData
				end
			end -- if not itemId or valid link
		end -- skip empty keyring
	end
	for slot = content.size, newSize + 1, -1 do
		local slotData = content[slot]
		if slotData then
			removed[slotData.slotId] = slotData.link
			content[slot] = nil
		end
	end
	content.size = newSize
end

function containerProto:HasContentChanged()
	return not not (next(self.added) or next(self.removed) or next(self.changed))
end

--------------------------------------------------------------------------------
-- Item dispatching
--------------------------------------------------------------------------------

function containerProto:GetStackButton(key)
	local stack = self.stacks[key]
	if not stack then
		stack = addon:AcquireStackButton(self, key)
		self.stacks[key] = stack
	end
	return stack
end

function containerProto:GetSection(name, category)
	local key = addon:BuildSectionKey(name, category)
	local section = self.sections[key]
	if not section then
		section = addon:AcquireSection(self, name, category)
		self.sections[key] = section
	end
	return section
end

local function FilterByBag(slotData)
	local bag = slotData.bag
	local name
	if bag == KEYRING_CONTAINER then
		name = L['Keyring']
	elseif bag == BACKPACK_CONTAINER then
		name = L['Backpack']
	elseif bag == BANK_CONTAINER then
		name = L['Bank']
	elseif bag <= NUM_BAG_SLOTS then
		name = format(L["Bag #%d"], bag)
	else
		name = format(L["Bank bag #%d"], bag - NUM_BAG_SLOTS)
	end
	if slotData.link then
		local shouldStack, stackHint = addon:ShouldStack(slotData)
		return name, nil, nil, shouldStack, stackHint and strjoin('#', tostring(stackHint), name)
	else
		return name, nil, nil, addon.db.profile.virtualStacks.freeSpace, name
	end
end

local MISCELLANEOUS = addon.BI['Miscellaneous']
local FREE_SPACE = L["Free space"]
function containerProto:FilterSlot(slotData)
	if self.BagSlotPanel:IsShown() then
		return FilterByBag(slotData)
	elseif slotData.link then
		local section, category, filterName = addon:Filter(slotData, MISCELLANEOUS)
		return section, category, filterName, addon:ShouldStack(slotData)
	else
		return FREE_SPACE, nil, nil, addon:ShouldStack(slotData)
	end
end

function containerProto:DispatchItem(slotData)
	local slotId = slotData.slotId
	local sectionName, category, filterName, shouldStack, stackHint = self:FilterSlot(slotData)
	assert(sectionName, "sectionName is nil, item: "..(slotData.link or "none"))
	local stackKey = shouldStack and strjoin('#', stackHint, tostring(slotData.bagFamily)) or nil
	local button = self.buttons[slotId]
	if button then
		if shouldStack then
			if not button:IsStack() or button:GetKey() ~= stackKey then
				self:RemoveSlot(slotId)
				button = nil
			end
		elseif button:IsStack() then
			self:RemoveSlot(slotId)
			button = nil
		end
	end
	if not button then
		if shouldStack then
			button = self:GetStackButton(stackKey)
			button:AddSlot(slotId)
		else
			button = addon:AcquireItemButton(self, slotData.bag, slotData.slot)
		end
	else
		button:FullUpdate()
	end
	local section = self:GetSection(sectionName, category or sectionName)
	if button:GetSection() ~= section then
		section:AddItemButton(slotId, button)
	end
	button.filterName = filterName
	self.buttons[slotId] = button
end

function containerProto:RemoveSlot(slotId)
	local button = self.buttons[slotId]
	if button then
		self.buttons[slotId] = nil
		if button:IsStack() then
			button:RemoveSlot(slotId)
			if button:IsEmpty() then
				self.stacks[button:GetKey()] = nil
				button:Release()
			end
		else
			button:Release()
		end
	end
end

function containerProto:UpdateButtons()
	if not self:HasContentChanged() then return end
	self:Debug('UpdateButtons')

	local added, removed, changed = self.added, self.removed, self.changed
	self:SendMessage('AdiBags_PreContentUpdate', self, added, removed, changed)

	--[===[@debug@
	local numAdded, numRemoved, numChanged = 0, 0, 0
	--@end-debug@]===]

	for slotId in pairs(removed) do
		self:RemoveSlot(slotId)
		--[===[@debug@
		numRemoved = numRemoved + 1
		--@end-debug@]===]
	end

	if next(added) then
		self:SendMessage('AdiBags_PreFilter', self)
		for slotId, slotData in pairs(added) do
			self:DispatchItem(slotData)
			--[===[@debug@
			numAdded = numAdded + 1
			--@end-debug@]===]
		end
		self:SendMessage('AdiBags_PostFilter', self)
	end

	-- Just push the buttons into dirtyButtons
	local buttons = self.buttons
	for slotId in pairs(changed) do
		buttons[slotId]:FullUpdate()
		--[===[@debug@
		numChanged = numChanged + 1
		--@end-debug@]===]
	end

	self:SendMessage('AdiBags_PostContentUpdate', self, added, removed, changed)

	--[===[@debug@
	self:Debug(numRemoved, 'slot(s) removed', numAdded, 'slot(s) added and', numChanged, 'slot(s) changed')
	--@end-debug@]===]

	wipe(added)
	wipe(removed)
	wipe(changed)
end

function containerProto:RedispatchAllItems()
	self:UpdateButtons()
	if self.filtersChanged then
		self:Debug('RedispatchAllItems')
		self:SendMessage('AdiBags_PreFilter', self)
		for bag, content in pairs(self.content) do
			for slotId, slotData in ipairs(content) do
				self:DispatchItem(slotData)
			end
		end
		self:SendMessage('AdiBags_PostFilter', self)
		self.filtersChanged = nil
	end
end

--------------------------------------------------------------------------------
-- Section layout
--------------------------------------------------------------------------------

local function CompareSections(a, b)
	local orderA, orderB = a:GetOrder(), b:GetOrder()
	if orderA == orderB then
		if a.category == b.category then
			return a.name < b.name
		else
			return a.category < b.category
		end
	else
		return orderA > orderB
	end
end

local sections = {}

local function GetBestSection(maxWidth, maxHeight, xOffset, rowHeight, category)
	local bestIndex, leastWasted, bestWidth, bestHeight
	for index, section in ipairs(sections) do
		if category and section.category ~= category then
			break
		end
		local fit, width, height, wasted = section:FitInSpace(maxWidth, maxHeight, xOffset, rowHeight)
		if fit then
			if not leastWasted or wasted < leastWasted then
				bestIndex, bestWidth, bestHeight, leastWasted = index, width, height, wasted
			end
		end
	end
	return bestIndex, bestWidth, bestHeight
end

local getNextSection = {
	-- 0: keep section of the same category together and in the right order
	[0] = function(maxWidth, maxHeight, xOffset, rowHeight)
	local fit, width, height = sections[1]:FitInSpace(maxWidth, maxHeight, xOffset, rowHeight)
	if fit then
		return 1, width, height
	end
end,
	-- 1: keep categories together
	[1] = function(maxWidth, maxHeight, xOffset, rowHeight)
	return GetBestSection(maxWidth, maxHeight, xOffset, rowHeight, sections[1].category)
end,
	-- 2: do not care about ordering
	[2] = function(maxWidth, maxHeight, xOffset, rowHeight)
	return GetBestSection(maxWidth, maxHeight, xOffset, rowHeight)
end
}

local function DoLayoutSections(self, rowWidth, maxHeight)
	rowWidth = rowWidth + ITEM_SIZE - SECTION_SPACING

	local minHeight = 0
	for key, section in pairs(self.sections) do
		if not section:IsCollapsed() then
			local fit, _, _, _, height = section:FitInSpace(rowWidth, 10000, 0, 0)
			if fit and height > minHeight then
				minHeight = height
			end
			tinsert(sections, section)
		end
	end
	tsort(sections, CompareSections)
	if minHeight > maxHeight then
		maxHeight = minHeight
	end

	local content = self.Content
	local getNext = getNextSection[addon.db.profile.laxOrdering]

	local wasted = 0
	local contentWidth, contentHeight = 0, 0
	local columnX, numColumns = 0, 0
	local section
	local num = #sections
	while num > 0 do
		local columnWidth, y = 0, 0
		while num > 0 and y < maxHeight do
			local rowHeight, x = 0, 0
			while num > 0 and x < rowWidth do
				local index, width, height = getNext(rowWidth - x, maxHeight - y, x, rowHeight)
				if not index then
					break
				end
				section = tremove(sections, index)
				num = num - 1
				section:SetPoint("TOPLEFT", content, columnX + x, -y)
				section:SetSizeInSlots(width, height)
				section:SetHeaderOverflow(true)
				x = x + section:GetWidth() + SECTION_SPACING
				rowHeight = max(rowHeight, section:GetHeight())
			end
			if section then
				section:SetHeaderOverflow(false)
			end			
			if x > 0 then
				y = y + rowHeight + ITEM_SPACING
				columnWidth = max(columnWidth, x)
				contentHeight = max(contentHeight, y)
			else
				break
			end
		end
		wasted = max(wasted, contentHeight - y)
		if y > 0 then
			numColumns = numColumns + 1
			columnX = columnX + columnWidth
			contentWidth = max(contentWidth, columnX)
		else
			break
		end
	end
	return contentWidth - SECTION_SPACING, contentHeight - ITEM_SPACING, numColumns, wasted, minHeight
end

function containerProto:LayoutSections(cleanLevel)

	local num = 0
	local dirtyLevel = self.dirtyLevel or 0
	local stickyDirty = 0
	for key, section in pairs(self.sections) do
		if section:IsEmpty() then
			section:Release()
			self.sections[key] = nil
			dirtyLevel = max(dirtyLevel, 1)
		elseif section:IsCollapsed() then
			if section:IsShown() then
				section:Hide()
				dirtyLevel = max(dirtyLevel, 1)
			end
		else
			num = num + 1
			if not section:IsShown() then
				section:Show()
				dirtyLevel = max(dirtyLevel, 2, section:GetDirtyLevel())
			else
				dirtyLevel = max(dirtyLevel, section:GetDirtyLevel())
			end
		end
	end

	if self.forceLayout then
		cleanLevel = -1
		self.forceLayout = nil
	elseif cleanLevel == true then
		cleanLevel = 0
	elseif not cleanLevel then
		cleanLevel = 1
	end

	self:Debug('LayoutSections: #sections=', num, 'cleanLevel=', cleanLevel, 'dirtyLevel=', dirtyLevel, '=>', (dirtyLevel > cleanLevel) and "cleanup required" or "NO-OP")

	if dirtyLevel > cleanLevel then

		if num == 0 then
			self.Content:SetSize(0.5, 0.5)

		else
			local rowWidth = (ITEM_SIZE + ITEM_SPACING) * addon.db.profile.rowWidth[self.name] - ITEM_SPACING
			local maxHeight = addon.db.profile.maxHeight * UIParent:GetHeight() * UIParent:GetEffectiveScale() / self:GetEffectiveScale()
			local contentWidth, contentHeight, numColumns, wastedHeight, minHeight = DoLayoutSections(self, rowWidth, maxHeight)
			if numColumns > 1 and wastedHeight / contentHeight > 0.1 then
				local totalHeight = contentHeight * numColumns - wastedHeight
				if totalHeight / numColumns < minHeight then
					numColumns = numColumns - 1
				end
				maxHeight = totalHeight / numColumns + (ITEM_SIZE + ITEM_SPACING)
				contentWidth, contentHeight, numColumns, wastedHeight = DoLayoutSections(self, rowWidth, maxHeight)
			elseif numColumns == 1 and contentWidth < self:GetContentMinWidth()  then
				contentWidth, contentHeight, numColumns, wastedHeight = DoLayoutSections(self, self:GetContentMinWidth(), maxHeight)
			end

			self.Content:SetSize(contentWidth, contentHeight)
		end

		dirtyLevel = 0
	end

	for key, section in pairs(self.sections) do
		if section:IsShown() then
			section:Layout(cleanLevel)
			dirtyLevel = max(dirtyLevel, section:GetDirtyLevel())
		end
	end

	self.dirtyLevel = dirtyLevel
	local dirtyLayout = dirtyLevel > 0
	self:Debug('LayoutSections: done, layout is', dirtyLayout and "dirty" or "clean")
	if self.dirtyLayout ~= dirtyLayout then
		self.dirtyLayout = dirtyLayout
		self:SendMessage('AdiBags_ContainerLayoutDirty', self, dirtyLayout)
	end
end
