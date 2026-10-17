local addonName, addonTable = ...

local L = LibStub("AceLocale-3.0"):GetLocale("Rarity")
local CONSTANTS = addonTable.constants

-- A comment with stray braces { { } and a fake entry ["Not an entry"] = {
local sampleMounts = {
	["Reins of the Heavenly Onyx Cloud Serpent"] = {
		cat = CONSTANTS.ITEM_CATEGORIES.MOP,
		type = CONSTANTS.ITEM_TYPES.MOUNT,
		method = CONSTANTS.DETECTION_METHODS.BOSS,
		name = L["Reins of the Heavenly Onyx Cloud Serpent"],
		spellId = 127158,
		itemId = 87771,
		npcs = { 99999 },
		tooltipNpcs = { 60491 },
		questId = 32099,
		chance = 100,
		statisticId = { 6989 },
		sourceText = L["Drops from {the} Sha of Anger"],
		coords = { { m = 379, x = 53.7, y = 64.7 } },
	},
	["Reins of the Drake of the North Wind"] = {
		cat = CONSTANTS.ITEM_CATEGORIES.CATA,
		name = L["Reins of the Drake of the North Wind"],
		spellId = 88742,
		itemId = 63040,
		questId = { 52001, 52002 },
		chance = 100,
		coords = {
			{ m = CONSTANTS.UIMAPIDS.ULDUM, x = 1.0, y = 2.0 },
			{ m = 325 },
			{
				m = 325,
				x = 60.0,
				y = 58.0,
				i = true,
			},
		},
	},
	["Sean's \"Quoted\" Mount"] = {
		spellId = 1,
		itemId = 2,
		chance = 5,
	},
}

return sampleMounts
