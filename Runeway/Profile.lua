-- Runeway profile: export all settings as one line of text and import it again (e.g. after a reinstall).
-- Format: "RNW1;path=value;path=value;..." with paths like "colors.fill.r". Import only takes known
-- settings with the right type; nothing is ever run as code. Key bindings are WoW's and not included.

local ADDON, ns = ...
local L = ns.L
local HEADER = "RNW1"
local SKIP = { questAreaCache = true, style = true, shown = true, probe = true }
local MODES = { key = true, mapkey = true, permanent = true }

-- Every exportable setting: { [path] = default value }, from the defaults plus the window position
local function Paths()
    local out = { x = 0, y = 0 }
    local function walk(t, prefix)
        for k, v in pairs(t) do
            local path = prefix .. k
            if not SKIP[path] then
                if type(v) == "table" then walk(v, path .. ".") else out[path] = v end
            end
        end
    end
    walk(ns.DEFAULTS, "")
    return out
end

-- Value at a dotted path such as "colors.fill.a" (also used by Options.lua)
function ns.GetPath(t, path)
    for part in path:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

function ns.SetPath(t, path, v)
    local last = path:match("([^.]+)$")
    for part in path:gmatch("([^.]+)%.") do
        if type(t[part]) ~= "table" then t[part] = {} end
        t = t[part]
    end
    t[last] = v
end

function ns.ExportProfile()
    local paths, keys = Paths(), {}
    for path in pairs(paths) do keys[#keys + 1] = path end
    table.sort(keys)
    local parts = { HEADER }
    for _, path in ipairs(keys) do
        local v = ns.GetPath(ns.db(), path)
        if type(v) == "number" then
            parts[#parts + 1] = ("%s=%.17g"):format(path, v)   -- exact round trip
        elseif type(v) == "boolean" or type(v) == "string" then
            parts[#parts + 1] = ("%s=%s"):format(path, tostring(v))
        end
    end
    return table.concat(parts, ";")
end

-- Returns the number of settings taken over, or nil if the text is no Runeway profile
function ns.ImportProfile(text)
    text = (text or ""):gsub("%s+", "")
    if text:sub(1, #HEADER + 1) ~= HEADER .. ";" then return nil end
    local paths, values = Paths(), {}
    for path, raw in text:gmatch(";([%w_.]+)=([^;]*)") do
        local default = paths[path]
        local kind = type(default)
        local v
        if kind == "number" then
            v = tonumber(raw)
        elseif kind == "boolean" then
            v = (raw == "true" and true) or (raw == "false" and false) or nil
        elseif kind == "string" and raw:match("^[%w_]+$") then
            v = raw
        end
        if path == "mode" and not MODES[v] then v = nil end
        if v ~= nil then values[path] = v end
    end
    local n = 0
    for path, v in pairs(values) do
        ns.SetPath(ns.db(), path, v)
        n = n + 1
    end
    if n == 0 then return nil end
    ns.ApplyAll()
    if ns.SetZoom then
        ns.SetZoom(ns.db().zoom, "zoom")
        ns.SetZoom(ns.db().zoomInside, "zoomInside")
    end
    if ns.NotifyAllSettings then ns.NotifyAllSettings() end
    return n
end

---------------------------------------------------------------------------
-- Dialog: one text box for export (selected, ready to copy) and import (paste, then Import)
---------------------------------------------------------------------------
local dialog
local function Dialog()
    if dialog then return dialog end
    dialog = CreateFrame("Frame", "RunewayProfileDialog", UIParent, "BasicFrameTemplateWithInset")
    dialog:SetSize(520, 260)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    tinsert(UISpecialFrames, "RunewayProfileDialog")          -- Escape closes it

    dialog.hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.hint:SetPoint("TOPLEFT", 16, -32)
    dialog.hint:SetPoint("TOPRIGHT", -16, -32)
    dialog.hint:SetJustifyH("LEFT")

    dialog.scroll = CreateFrame("ScrollFrame", nil, dialog, "InputScrollFrameTemplate")
    dialog.scroll:SetPoint("TOPLEFT", 20, -70)
    dialog.scroll:SetPoint("BOTTOMRIGHT", -30, 46)
    if dialog.scroll.CharCount then dialog.scroll.CharCount:Hide() end
    local edit = dialog.scroll.EditBox
    edit:SetWidth(460)
    edit:SetFontObject("ChatFontNormal")
    edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
    dialog.edit = edit

    dialog.action = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.action:SetSize(120, 22)
    dialog.action:SetPoint("BOTTOMRIGHT", -16, 14)
    dialog.action:SetText(L.PROFILE_IMPORT)
    dialog.action:SetScript("OnClick", function()
        local n = ns.ImportProfile(edit:GetText())
        if n then
            ns.Print(L.PROFILE_IMPORTED:format(n))
            dialog:Hide()
        else
            ns.Print(L.PROFILE_INVALID)
        end
    end)
    return dialog
end

function ns.ShowExport()
    local d = Dialog()
    d.TitleText:SetText(L.PROFILE_EXPORT_TITLE)
    d.hint:SetText(L.PROFILE_EXPORT_HINT)
    d.action:Hide()
    d:Show()
    d.edit:SetText(ns.ExportProfile())
    d.edit:SetFocus()
    d.edit:HighlightText()
end

function ns.ShowImport()
    local d = Dialog()
    d.TitleText:SetText(L.PROFILE_IMPORT_TITLE)
    d.hint:SetText(L.PROFILE_IMPORT_HINT)
    d.action:Show()
    d:Show()
    d.edit:SetText("")
    d.edit:SetFocus()
end
