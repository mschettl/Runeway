-- Runeway 0.5
-- Spielerzentriertes, mitdrehendes Konturen-Overlay (Linienbilder je ADT-Kachel in Weltkoordinaten)

local ADDON = ...
local T = 1600 / 3                 -- Kantenlaenge einer ADT-Kachel in Yards (533,33)
local PATH = "Interface\\AddOns\\Runeway\\tiles\\"
local MEDIA = "Interface\\AddOns\\Runeway\\media\\"
local ZOOM_MIN, ZOOM_MAX = 0.08, 5

local defaults = {
    x = nil, y = nil, w = 700, h = 450,
    zoom = 1.5, alpha = 0.7, rotate = true, locked = false, shown = false,
}
local db

BINDING_HEADER_RUNEWAY = "Runeway"
BINDING_NAME_RUNEWAY_TOGGLE = "Overlay-Karte ein/aus"

local function Print(msg)
    print("|cff66ccffRuneway:|r " .. msg)
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local view = CreateFrame("Frame", "RunewayFrame", UIParent)
view:SetFrameStrata("BACKGROUND")
view:SetClampedToScreen(true)
view:SetMovable(true)
view:SetResizable(true)
view:RegisterForDrag("LeftButton")
view:Hide()

-- Weiches Ausblenden zum Rand (wie PoE). Ohne Masken-Unterstuetzung: harter Zuschnitt
local fade
if view.CreateMaskTexture then
    fade = view:CreateMaskTexture()
    fade:SetTexture(MEDIA .. "fade.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fade:SetAllPoints()
else
    view:SetClipsChildren(true)
end
local function Fade(tex)
    if fade then tex:AddMaskTexture(fade) end
end

local canvas = CreateFrame("Frame", nil, view)
canvas:SetAllPoints()

local top = CreateFrame("Frame", nil, view)
top:SetAllPoints()
top:SetFrameLevel(canvas:GetFrameLevel() + 5)

local editHint = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
editHint:SetPoint("TOP", 0, -4)
editHint:SetText("Ziehen = verschieben  |  Mausrad = Zoom  |  Shift+Mausrad = Groesse  |  /rnw lock")

local status = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOM", 0, 6)

-- Spielerpfeil, fest in der Mitte
local arrow = top:CreateTexture(nil, "OVERLAY")
arrow:SetTexture(MEDIA .. "arrow.tga")
arrow:SetSize(40, 40)
arrow:SetPoint("CENTER")

---------------------------------------------------------------------------
-- Weltkoordinaten -> Bildschirm
---------------------------------------------------------------------------
-- UnitPosition liefert (Nord, West). Bildschirm: x nach rechts = Osten, y nach oben = Norden.
local pN, pW, cosA, sinA, k = 0, 0, 1, 0, 1

local function ToScreen(n, w)
    local sx = -(w - pW) * k
    local sy = (n - pN) * k
    return sx * cosA - sy * sinA, sx * sinA + sy * cosA
end

---------------------------------------------------------------------------
-- Kontur-Kacheln
---------------------------------------------------------------------------
local tileTex = {}     -- ["inst:c_r"] = Texture

local function GetTileTex(inst, key, lod)
    local id = inst .. ":" .. key
    local t = tileTex[id]
    if not t then
        t = canvas:CreateTexture(nil, "ARTWORK")
        Fade(t)
        tileTex[id] = t
    end
    if t.lod ~= lod then
        t:SetTexture(PATH .. inst .. "\\" .. (lod < 512 and (lod .. "\\") or "") .. key .. ".tga")
        t.lod = lod
    end
    return t
end

local function HideTiles()
    for _, t in pairs(tileTex) do t:Hide() end
end

local function UpdateTiles(inst, angle)
    local data = RunewayTiles and RunewayTiles[inst]
    HideTiles()
    if not data then return false end

    local W, H = view:GetSize()
    local reach = math.sqrt(W * W + H * H) / 2 / k + T   -- sichtbarer Radius in Yards plus Kachel
    local size = T * k
    local lod = (size < 160 and 128) or (size < 360 and 256) or 512   -- herausgezoomt: grobere Kacheln

    for key in pairs(data) do
        local c, r = key:match("(%d+)_(%d+)")
        c, r = tonumber(c), tonumber(r)
        local cn = (32 - r) * T - T / 2
        local cw = (32 - c) * T - T / 2
        if math.abs(cn - pN) < reach and math.abs(cw - pW) < reach then
            local t = GetTileTex(inst, key, lod)
            local x, y = ToScreen(cn, cw)
            t:ClearAllPoints()
            t:SetPoint("CENTER", view, "CENTER", x, y)
            t:SetSize(size, size)
            t:SetRotation(angle)
            t:Show()
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Quest-Marker (Kartenposition -> Weltposition, einmal je Aktualisierung)
---------------------------------------------------------------------------
local quests = {}      -- { {n, w}, ... }
local qpins = {}

local function WorldFromMap(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local _, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if pos then return pos.x, pos.y end
end

local function RefreshQuests()
    wipe(quests)
    local mapID = C_Map.GetBestMapForUnit("player")
    if not (mapID and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end

    -- Achsenreihenfolge der API einmal am Spieler pruefen
    local swap = false
    local mp = C_Map.GetPlayerMapPosition(mapID, "player")
    local un, uw = UnitPosition("player")
    if mp and un then
        local a, b = WorldFromMap(mapID, mp:GetXY())
        if a then swap = math.abs(a - un) + math.abs(b - uw) > math.abs(b - un) + math.abs(a - uw) end
    end

    for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
        local n, w = WorldFromMap(mapID, q.x, q.y)
        if n then
            if swap then n, w = w, n end
            quests[#quests + 1] = { n, w }
        end
    end
end

local function UpdateQuestPins()
    for i, q in ipairs(quests) do
        local t = qpins[i]
        if not t then
            t = top:CreateTexture(nil, "ARTWORK")
            t:SetSize(14, 14)
            t:SetTexture(MEDIA .. "dot.tga")
            Fade(t)
            qpins[i] = t
        end
        local x, y = ToScreen(q[1], q[2])
        t:ClearAllPoints()
        t:SetPoint("CENTER", view, "CENTER", x, y)
        t:Show()
    end
    for i = #quests + 1, #qpins do qpins[i]:Hide() end
end

---------------------------------------------------------------------------
-- Hauptschleife
---------------------------------------------------------------------------
local elapsed = 0
view:SetScript("OnUpdate", function(self, e)
    elapsed = elapsed + e
    if elapsed < 0.025 then return end
    elapsed = 0

    local n, w, _, inst = UnitPosition("player")
    if not n then
        HideTiles()
        status:SetText("Keine Position (Instanz?)")
        return
    end
    pN, pW, k = n, w, db.zoom

    local facing = GetPlayerFacing() or 0
    local angle = db.rotate and -facing or 0
    cosA, sinA = math.cos(angle), math.sin(angle)
    arrow:SetRotation(db.rotate and 0 or facing)

    if UpdateTiles(inst, angle) then
        status:SetText("")
    else
        status:SetText("Fuer dieses Gebiet gibt es noch keine Konturen")
    end
    UpdateQuestPins()
end)

---------------------------------------------------------------------------
-- Position / Groesse / Sperre
---------------------------------------------------------------------------
local function SavePos()
    db.x, db.y = view:GetCenter()
end

local function ApplyPos()
    view:ClearAllPoints()
    if db.x then
        view:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        view:SetPoint("CENTER")
    end
end

local function ApplySize()
    view:SetSize(db.w, db.h)
end

local function ApplyLock()
    local unlocked = not db.locked
    view:EnableMouse(unlocked)          -- gesperrt: Klicks gehen durch
    view:EnableMouseWheel(unlocked)
    editHint:SetShown(unlocked)
end

local function SetZoom(z)
    db.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, z))
end

view:SetScript("OnDragStart", function(self) self:StartMoving() end)
view:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePos()
    ApplyPos()
end)
view:SetScript("OnMouseWheel", function(_, delta)
    if IsShiftKeyDown() then
        db.w = math.max(200, math.min(2000, db.w + delta * 40))
        db.h = math.max(150, math.min(1400, db.h + delta * 26))
        ApplySize()
    else
        SetZoom(db.zoom * (delta > 0 and 1.15 or 1 / 1.15))
    end
end)
view:SetScript("OnShow", RefreshQuests)

---------------------------------------------------------------------------
-- Position kopierbar anzeigen (/rnw pos)
---------------------------------------------------------------------------
local copy
local function ShowCopy(text)
    if not copy then
        copy = CreateFrame("EditBox", "RunewayCopyBox", UIParent, "InputBoxTemplate")
        copy:SetSize(360, 24)
        copy:SetPoint("CENTER", 0, 200)
        copy:SetAutoFocus(true)
        copy:SetScript("OnEscapePressed", copy.Hide)
        copy:SetScript("OnEnterPressed", copy.Hide)
    end
    copy:SetText(text)
    copy:Show()
    copy:SetFocus()
    copy:HighlightText()
end

---------------------------------------------------------------------------
-- Umschalten
---------------------------------------------------------------------------
function Runeway_Toggle()
    db.shown = not db.shown
    view:SetShown(db.shown)
end

local function CreateWorldMapButton()
    if not WorldMapFrame then return end
    local b = CreateFrame("Button", nil, WorldMapFrame, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    b:SetText("Overlay")
    b:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -40, -2)
    b:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 20)
    b:SetScript("OnClick", function()
        HideUIPanel(WorldMapFrame)
        db.shown = true
        view:Show()
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        RunewayDB = RunewayDB or {}
        db = RunewayDB
        for key, v in pairs(defaults) do
            if db[key] == nil then db[key] = v end
        end
        db.scale, db.style = nil, nil          -- Altlasten aus 0.2
        view:SetAlpha(db.alpha)
        ApplySize()
        ApplyPos()
        ApplyLock()
        CreateWorldMapButton()
        if not fade then Print("Hinweis: Dieser Client unterstuetzt keine Masken, Rand wird hart abgeschnitten.") end
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("QUEST_LOG_UPDATE")
    elseif event == "PLAYER_ENTERING_WORLD" then
        view:SetShown(db.shown)
        RefreshQuests()
    elseif view:IsShown() then
        RefreshQuests()
    end
end)

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------
SLASH_RUNEWAY1 = "/runeway"
SLASH_RUNEWAY2 = "/rnw"
SlashCmdList.RUNEWAY = function(msg)
    local cmd, arg = msg:lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(arg)

    if cmd == "" or cmd == "toggle" then
        Runeway_Toggle()
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = (cmd == "lock")
        ApplyLock()
        Print(db.locked and "gesperrt (Klicks gehen durch)" or "entsperrt")
    elseif cmd == "alpha" and n then
        db.alpha = math.max(5, math.min(100, n)) / 100
        view:SetAlpha(db.alpha)
        Print(("Deckkraft %d %%"):format(db.alpha * 100))
    elseif cmd == "zoom" and n then
        SetZoom(n)
        Print(("Zoom %.2f"):format(db.zoom))
    elseif cmd == "size" then
        local w, h = arg:match("(%d+)%s+(%d+)")
        if w then
            db.w, db.h = tonumber(w), tonumber(h)
            ApplySize()
        end
        Print(("Groesse %d x %d"):format(db.w, db.h))
    elseif cmd == "rotate" then
        db.rotate = not db.rotate
        Print(db.rotate and "Karte dreht mit" or "Norden oben")
    elseif cmd == "pos" then
        local pn, pw, _, inst = UnitPosition("player")
        local mapID = C_Map.GetBestMapForUnit("player")
        ShowCopy(("%s %s %s map=%s facing=%.3f"):format(
            tostring(pn), tostring(pw), tostring(inst), tostring(mapID), GetPlayerFacing() or -1))
    elseif cmd == "reset" then
        for key, v in pairs(defaults) do
            if key ~= "shown" then db[key] = v end
        end
        view:SetAlpha(db.alpha)
        ApplySize()
        ApplyPos()
        ApplyLock()
        Print("zurueckgesetzt")
    else
        Print("/rnw [toggle] | lock | unlock | alpha 5-100 | zoom 0.08-5 | size B H | rotate | pos | reset")
    end
end
