local addonName, addonTable = ...

addonTable.constants = addonTable.constants or {}

local C = addonTable.constants

C.TOOLTIP = { ACTIVATION_METHOD_HOVER = "ACTIVATION_METHOD_HOVER" }

-- Embedded mapIDs { with a brace in a comment }
C.UIMAPIDS = {
	-- Dummy Zone (For items that can be obtained anywhere.)
	NONE = 0,
	-- Cataclysm Zones
	ULDUM = 249,
	SKYWALL = 325, -- trailing comment = 999
	VASHJIR = 203,
}

C.DEFEAT_DETECTION = { MODE_OR = 1, MODE_AND = 2 }
