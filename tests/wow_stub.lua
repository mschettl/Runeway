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
        if k == "SetVertexColor" then return function(self, r, g, b, a) self._color = { r, g, b, a } end end
        if k == "GetSize" then return function() return 700, 450 end end
        if k == "GetCenter" then return function() return 500, 400 end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "DrawNone" then return function() DRAWN = {} end end
        if k == "DrawBlob" then return function(self, q) DRAWN[q] = true end end
        if k == "UpdateMouseOverTooltip" then return function(self, x, y)
            -- test blobs: circles; probe frame tests draw quest 4242 only
            for q, c in pairs(BLOBS) do
                if (DRAWN[q] or not next(DRAWN)) and (x - c[1]) ^ 2 + (y - c[2]) ^ 2 < c[3] ^ 2 then return q, 1 end
            end
        end end
        if k:match("^Create") then return function(self)
            CREATED[k] = (CREATED[k] or 0) + 1
            local o = obj(k)
            if k == "CreateTexture" then ALL_TEX[#ALL_TEX + 1] = o end
            return o
        end end
        return function() end
    end })
end
TEXTURES = {}
ALL_TEX = {}
LOAD_FRAMES = 0      -- frames until a texture counts as loaded
CREATED = {}
DRAWN = {}
BLOBS = { [4242] = { 0.4, 0.6, 0.2 }, [4243] = { 0.55, 0.6, 0.15 } }
function InCombatLockdown() return false end
local clock = 0
function debugprofilestop() clock = clock + 0.01 return clock end
function GetQuestPOIBlobCount(q) return BLOBS[q] and 1 or 0 end
UIParent = obj("UIParent")
WorldMapFrame = obj("WorldMapFrame")
FRAMES = {}
function CreateFrame(_, name) local f = obj("Frame"); FRAMES[#FRAMES + 1] = f; if name then _G[name] = f end; return f end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function print(...) io.write(table.concat({ ... }, " "), "\n") end
SlashCmdList = {}
POS = { 1917.6, 84.9, 0, 0 }
function UnitPosition() return POS[1], POS[2], POS[3], POS[4] end
function GetPlayerFacing() return 0.5 end
function IsShiftKeyDown() return false end
function HideUIPanel() end
C_Map = { GetBestMapForUnit = function() return 1420 end,
          GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end }
C_Minimap = { IsInsideQuestBlob = function() return true end }
C_QuestLog = { GetQuestsOnMap = function() return { { questID = 4242, x = 0.4, y = 0.6 }, { questID = 4243, x = 0.55, y = 0.6 }, { questID = 4244, x = 0.45, y = 0.5 } } end,
               IsComplete = function(q) return q == 4244 end,
               GetTitleForQuestID = function(id) return "Test quest " .. id end }
function CreateVector2D(x, y) return { x = x, y = y } end
C_Map.GetWorldPosFromMapPos = function(_, v) return 0, { x = 3000 - v.y * 4000, y = 2000 - v.x * 6000 } end
function date() return "2026-10-07" end
