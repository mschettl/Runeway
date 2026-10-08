-- Minimal WoW API stub to load and exercise the addon outside the game (lupa / Lua 5.x)
unpack = unpack or table.unpack
local function obj(name)
    local o = { _name = name, _shown = false, _scripts = {} }
    return setmetatable(o, { __index = function(t, k)
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "SetShown" then return function(self, v) self._shown = not not v end end
        if k == "SetScript" then return function(self, s, f) self._scripts[s] = f end end
        if k == "GetScript" then return function(self, s) return self._scripts[s] end end
        if k == "SetTexture" then return function(self, p) self._tex = p; self._loadIn = LOAD_FRAMES; TEXTURES[#TEXTURES + 1] = p end end
        if k == "IsObjectLoaded" then return function(self)
            self._loadIn = (self._loadIn or 0) - 1
            return self._loadIn < 0
        end end
        if k == "SetAlpha" then return function(self, a) self._alpha = a end end
        if k == "SetStartPoint" then return function(self, _, _, x, y) self._p0 = { x, y } end end
        if k == "SetEndPoint" then return function(self, _, _, x, y) self._p1 = { x, y } end end
        if k == "SetVertexColor" then return function(self, r, g, b, a) self._color = { r, g, b, a } end end
        if k == "GetSize" then return function() return 700, 450 end end
        if k == "GetCenter" then return function() return 500, 400 end end
        if k == "GetLeft" then return function() return 150 end end
        if k == "GetTop" then return function() return 750 end end
        if k == "GetEffectiveScale" then return function() return 1 end end
        if k == "GetChecked" then return function(self) return rawget(self, "_checked") end end
        if k == "SetChecked" then return function(self, v) self._checked = v end end
        if k == "SetValue" then return function(self, v) self._value = v end end
        if k == "SetText" then return function(self, v) self._text = v end end
        if k == "Text" or k == "Low" or k == "High" then local c = obj(k); rawset(t, k, c); return c end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "SetMapID" then return function(self, m) self._map = m end end
        if k == "GetMapID" then return function(self) return rawget(self, "_map") end end
        if k == "DrawNone" then return function() DRAWN = {} end end
        if k == "DrawBlob" then return function(self, q) DRAWN[q] = true end end
        if k == "UpdateMouseOverTooltip" then return function(self, x, y)
            -- test blobs: circles; probe frame tests draw quest 4242 only
            for q, c in pairs(BLOBS_BY_MAP[rawget(self, "_map")] or BLOBS) do
                if (DRAWN[q] or not next(DRAWN)) and (x - c[1]) ^ 2 + (y - c[2]) ^ 2 < c[3] ^ 2 then return q, 1 end
            end
        end end
        if k:match("^Create") then return function(self)
            CREATED[k] = (CREATED[k] or 0) + 1
            local o = obj(k)
            if k == "CreateTexture" then ALL_TEX[#ALL_TEX + 1] = o end
            if k == "CreateLine" then ALL_LINES[#ALL_LINES + 1] = o end
            return o
        end end
        return function() end
    end })
end
TEXTURES = {}
ALL_TEX = {}
ALL_LINES = {}
LOAD_FRAMES = 0      -- frames until a texture counts as loaded
CREATED = {}
DRAWN = {}
BLOBS = { [4242] = { 0.4, 0.6, 0.2 }, [4243] = { 0.55, 0.6, 0.15 } }
-- neighbouring zone 1421 (west of 1420): quest 4243 shows there too, cut off at the map border; 5001 only there
BLOBS_BY_MAP = { [1420] = BLOBS, [1421] = { [4243] = { 0.02, 0.6, 0.15 }, [5001] = { 0.1, 0.5, 0.05 } } }
function InCombatLockdown() return false end
local clock = 0
function debugprofilestop() clock = clock + 0.01 return clock end
function GetQuestPOIBlobCount(q) return (BLOBS[q] or BLOBS_BY_MAP[1421][q]) and 1 or 0 end
UIParent = obj("UIParent")
WorldMapFrame = obj("WorldMapFrame")
FRAMES = {}
function CreateFrame(_, name) local f = obj("Frame"); FRAMES[#FRAMES + 1] = f; if name then _G[name] = f end; return f end
function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a, SetRGBA = function(self, r2, g2, b2, a2) self.r, self.g, self.b, self.a = r2, g2, b2, a2 end,
             GetRGB = function(self) return self.r, self.g, self.b end,
             GenerateHexColor = function(self)
                 return ("ff%02x%02x%02x"):format(self.r * 255 + 0.5, self.g * 255 + 0.5, self.b * 255 + 0.5)
             end }
end
function CreateColorFromHexString(h)
    local r, g, b = h:match("^%x%x(%x%x)(%x%x)(%x%x)$")
    return CreateColor(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, 1)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function print(...) io.write(table.concat({ ... }, " "), "\n") end
SlashCmdList = {}
POS = { 1917.6, 84.9, 0, 0 }
function UnitPosition() return POS[1], POS[2], POS[3], POS[4] end
function GetPlayerFacing() return 0.5 end
function IsShiftKeyDown() return false end
function HideUIPanel() end
C_Map = { GetBestMapForUnit = function() return 1420 end,
          GetPlayerMapPosition = function(m) if m == 1420 then return { GetXY = function() return 0.4, 0.6 end } end end,
          GetMapInfo = function(m) return m == 1415 and { mapType = 2 } or { mapType = 3, parentMapID = 1415 } end,
          GetMapChildrenInfo = function() return { { mapID = 1420 }, { mapID = 1421 }, { mapID = 1422 } } end }
C_Minimap = { IsInsideQuestBlob = function() return true end }
QUESTS_BY_MAP = { [1420] = { { questID = 4242, x = 0.4, y = 0.6 }, { questID = 4243, x = 0.55, y = 0.6 }, { questID = 4244, x = 0.45, y = 0.5 } },
                  [1421] = { { questID = 4243, x = 0.02, y = 0.6 }, { questID = 5001, x = 0.1, y = 0.5 }, { questID = 5002, x = 0.2, y = 0.5 } } }
C_QuestLog = { GetQuestsOnMap = function(m) return QUESTS_BY_MAP[m] or {} end,
               IsComplete = function(q) return q == 4244 end,
               GetTitleForQuestID = function(id) return "Test quest " .. id end }
function CreateVector2D(x, y) return { x = x, y = y } end
MAP_WEST = { [1420] = 2000, [1421] = 8000, [1422] = 40000 }   -- west edge of each zone map (yards)
C_Map.GetWorldPosFromMapPos = function(m, v) return 0, { x = 3000 - v.y * 4000, y = MAP_WEST[m] - v.x * 6000 } end
function date() return "2026-10-07" end
-- 3.4: visibility, bindings, settings
function GetTime() return clock end
STATE = { combat = false, instance = false, mounted = false, resting = false }
function UnitAffectingCombat() return STATE.combat end
function IsInInstance() return STATE.instance, STATE.instance and "party" or "none" end
function IsMounted() return STATE.mounted end
function IsFlying() return false end
function UnitOnTaxi() return false end
function IsResting() return STATE.resting end
function IsAltKeyDown() return false end
function IsControlKeyDown() return false end
CURSOR = { 700, 300 }
function GetCursorPosition() return CURSOR[1], CURSOR[2] end
BINDINGS = {}
function GetBindingKey(cmd) return ({ TOGGLEWORLDMAP = "M", RUNEWAY_WORLDMAP = "SHIFT-M" })[cmd] end
function GetNumBindings() return 2 end
function GetBinding(i) return ({ "RUNEWAY_TOGGLE", "RUNEWAY_WORLDMAP" })[i] end
function SetOverrideBinding(_, _, key, cmd) BINDINGS[key] = cmd end
function ClearOverrideBindings() wipe(BINDINGS) end
function GetBindingAction(key, override) return override and BINDINGS[key] or (key == "M" and "TOGGLEWORLDMAP" or "") end
GameTooltip = obj("GameTooltip")
function GameTooltip_Hide() end
ColorPickerFrame = obj("ColorPickerFrame")
function ColorPickerFrame:SetupColorPickerAndShow(info) self.info = info end
function ColorPickerFrame:GetColorRGB() return 0.1, 0.2, 0.3 end
-- Settings API: proxy settings by variable name, rows as plain initializer tables
SETTINGS, INITS = {}, {}
local function Layout() return { AddInitializer = function(_, i) INITS[#INITS + 1] = i end } end
local function Row(kind) return function(_, setting, options) INITS[#INITS + 1] = { kind = kind, setting = setting,
    options = type(options) == "function" and options() or options } end end
Settings = {
    VarType = { Boolean = "boolean", Number = "number", String = "string" },
    RegisterVerticalLayoutCategory = function() return { GetID = function() return 77 end }, Layout() end,
    RegisterVerticalLayoutSubcategory = function() return {}, Layout() end,
    RegisterProxySetting = function(_, var, varType, name, default, get, set)
        assert(type(default) == varType, var .. ": default must be " .. varType)
        local st = { variable = var, default = default, GetValue = function() return get() end,
                     SetValue = function(_, v) set(v) end }
        SETTINGS[var] = st
        return st
    end,
    CreateCheckbox = Row("checkbox"), CreateSlider = Row("slider"), CreateDropdown = Row("dropdown"),
    CreateColorSwatch = Row("color"),
    CreateSliderOptions = function(min, max) return { min = min, max = max, SetLabelFormatter = function(o, _, f) o.fmt = f end } end,
    CreateControlTextContainer = function()
        local d = {}
        return { Add = function(_, v, label) d[#d + 1] = { value = v, label = label } end, GetData = function() return d end }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) OPENED = id end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
function CreateSettingsListSectionHeaderInitializer(name) return { kind = "header", name = name } end
function CreateSettingsButtonInitializer(name, text, click) return { kind = "button", click = click } end
function CreateSettingsCheckboxSliderInitializer(cb, _, _, slider, options) return { kind = "checkslider", setting = cb, slider = slider, options = options } end
function CreateKeybindingEntryInitializer(i) return { kind = "binding", action = GetBinding(i) } end
