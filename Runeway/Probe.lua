-- Runeway quest area probe (test tool, /rnw probe)
-- Lets the game draw the quest areas into a QuestPOIFrame (same frame type as the world map)
-- and samples it on a grid via UpdateMouseOverTooltip(x, y). Results go to RunewayDB.probe.

local function Print(msg)
    print("|cff66ccffRuneway probe:|r " .. msg)
end

local frame, sampler
local RES_DEFAULT, PER_FRAME = 64, 1000
local FINE_STEP, FINE_MAX, FINE_WINDOW = 1 / 1024, 200, 0.06   -- fine pass: map units, max cells per axis

local function QuestTitle(questID)
    if C_QuestLog.GetTitleForQuestID then return C_QuestLog.GetTitleForQuestID(questID) end
    local idx = GetQuestLogIndexByID and GetQuestLogIndexByID(questID)
    return idx and GetQuestLogTitle(idx)
end

local function WorldCorners(mapID)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local _, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
    local _, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
    if a and b then return { a.x, a.y, b.x, b.y } end
end

local function GetFrame()
    if frame then return frame end
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", "RunewayProbeFrame", UIParent)
    if not ok or not f then
        Print("CreateFrame(\"QuestPOIFrame\") failed: " .. tostring(f))
        return
    end
    f:SetSize(512, 512)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    pcall(f.SetFillTexture, f, "Interface\\WorldMap\\UI-QuestBlob-Inside")
    pcall(f.SetBorderTexture, f, "Interface\\WorldMap\\UI-QuestBlob-Outside")
    pcall(f.SetFillAlpha, f, 128)
    pcall(f.SetBorderAlpha, f, 192)
    pcall(f.SetBorderScalar, f, 1.0)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    f.bg = bg
    frame = f
    return f
end

-- Samples a map rectangle (normalized x0, y0 .. x1, y1) on an nx x ny grid for the blob currently drawn;
-- calls done(result) when finished (spread over several frames)
local function SampleRect(f, questID, x0, y0, x1, y1, nx, ny, done)
    local rows, hits, other, errors = {}, 0, 0, 0
    local minX, minY, maxX, maxY = nx, ny, -1, -1
    local dx, dy = (x1 - x0) / nx, (y1 - y0) / ny
    local i, wait = 0, 0.2           -- give the engine a moment to build the blob
    sampler:SetScript("OnUpdate", function(self, e)
        if wait > 0 then wait = wait - e return end
        for _ = 1, PER_FRAME do
            local row, col = math.floor(i / nx), i % nx
            if col == 0 then rows[row + 1] = {} end
            local ok, a, b = pcall(f.UpdateMouseOverTooltip, f, x0 + (col + 0.5) * dx, y0 + (row + 0.5) * dy)
            local c = "0"
            if not ok then
                errors = errors + 1
                if errors == 1 then Print("UpdateMouseOverTooltip error: " .. tostring(a)) end
            elseif a then
                if a == questID or (b and b > 0) then
                    c = "1"
                    hits = hits + 1
                    minX, minY = math.min(minX, col), math.min(minY, row)
                    maxX, maxY = math.max(maxX, col), math.max(maxY, row)
                else
                    c = "2"          -- inside, but a different value than expected
                    other = other + 1
                end
            end
            rows[row + 1][col + 1] = c
            i = i + 1
            if i >= nx * ny then
                self:SetScript("OnUpdate", nil)
                for r = 1, #rows do rows[r] = table.concat(rows[r]) end
                done({ rect = { x0, y0, x1, y1 }, nx = nx, ny = ny, hits = hits, other = other, errors = errors,
                       rows = rows,
                       bbox = hits > 0 and { x0 + minX * dx, y0 + minY * dy, x0 + (maxX + 1) * dx, y0 + (maxY + 1) * dy } or nil })
                return
            end
        end
    end)
end

-- Coarse pass over the whole map, then a fine pass around the hits (or around the quest pin if the
-- coarse grid missed a small area)
local function SampleQuest(f, q, res, done)
    f:DrawNone()
    f:DrawBlob(q.questID, true)
    SampleRect(f, q.questID, 0, 0, 1, 1, res, res, function(coarse)
        local x0, y0, x1, y1
        if coarse.bbox then
            local m = 2 / res
            x0, y0, x1, y1 = coarse.bbox[1] - m, coarse.bbox[2] - m, coarse.bbox[3] + m, coarse.bbox[4] + m
        elseif (GetQuestPOIBlobCount and GetQuestPOIBlobCount(q.questID) or 0) > 0 and q.x then
            x0, y0, x1, y1 = q.x - FINE_WINDOW, q.y - FINE_WINDOW, q.x + FINE_WINDOW, q.y + FINE_WINDOW
        end
        local r = { questID = q.questID, title = QuestTitle(q.questID), pin = { q.x, q.y }, coarse = coarse }
        if not x0 then return done(r) end
        x0, y0, x1, y1 = math.max(0, x0), math.max(0, y0), math.min(1, x1), math.min(1, y1)
        local step = math.max(FINE_STEP, (x1 - x0) / FINE_MAX, (y1 - y0) / FINE_MAX)
        local nx, ny = math.max(1, math.ceil((x1 - x0) / step)), math.max(1, math.ceil((y1 - y0) / step))
        SampleRect(f, q.questID, x0, y0, x0 + nx * step, y0 + ny * step, nx, ny, function(fine)
            r.fine = fine
            done(r)
        end)
    end)
end

function Runeway_Probe(arg)
    arg = arg or ""
    if arg == "hide" then
        if frame then frame:Hide() end
        return
    end
    local visible = arg:find("show") ~= nil
    local res = tonumber(arg:match("(%d+)")) or RES_DEFAULT

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then Print("no map for player") return end
    local quests = C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID) or {}
    Print(("map %d, %d quest(s) on map, POI frame test with grid %d x %d"):format(mapID, #quests, res, res))
    for _, q in ipairs(quests) do
        local blobs = GetQuestPOIBlobCount and GetQuestPOIBlobCount(q.questID)
        Print(("  quest %d %s  pos %.3f/%.3f  blobs %s"):format(q.questID, tostring(QuestTitle(q.questID)),
            q.x or -1, q.y or -1, tostring(blobs)))
    end
    if #quests == 0 then return end

    -- Same steps as the retail/Forever quest log (QuestLogMixin:UpdatePOIs): select the map for the quest POI
    -- system and ask for an update; the data arrives with QUEST_POI_UPDATE
    local prevMap = C_QuestLog.GetMapForQuestPOIs and C_QuestLog.GetMapForQuestPOIs()
    if C_QuestLog.SetMapForQuestPOIs then pcall(C_QuestLog.SetMapForQuestPOIs, mapID) end
    sampler = sampler or CreateFrame("Frame")
    sampler:RegisterEvent("QUEST_POI_UPDATE")
    local gotEvent, waited = false, 0
    sampler:SetScript("OnEvent", function() gotEvent = true end)
    if QuestPOIUpdateIcons then pcall(QuestPOIUpdateIcons) end
    sampler:SetScript("OnUpdate", function(self, e)
        waited = waited + e
        if not gotEvent and waited < 3 then return end
        self:SetScript("OnUpdate", nil)
        self:UnregisterEvent("QUEST_POI_UPDATE")
        Print(("QUEST_POI_UPDATE %s after %.1f s (POI map %s -> %d)"):format(gotEvent and "received" or "NOT received",
            waited, tostring(prevMap), mapID))
        for _, q in ipairs(quests) do
            local blobs = GetQuestPOIBlobCount and GetQuestPOIBlobCount(q.questID)
            local inside = C_Minimap and C_Minimap.IsInsideQuestBlob and C_Minimap.IsInsideQuestBlob(q.questID)
            Print(("  quest %d: blobs %s, player inside %s"):format(q.questID, tostring(blobs), tostring(inside)))
        end
        Runeway_ProbeSample(mapID, quests, res, visible, prevMap)
    end)
end

function Runeway_ProbeSample(mapID, quests, res, visible, prevMap)
    local f = GetFrame()
    if not f then return end
    local ok, err = pcall(f.SetMapID, f, mapID)
    if not ok then Print("SetMapID failed: " .. tostring(err)) return end
    f:SetAlpha(visible and 1 or 0)
    f:Show()

    RunewayDB.probe = { time = date and date("%Y-%m-%d %H:%M:%S"), mapID = mapID,
                        corners = WorldCorners(mapID), quests = {} }
    local n = 0
    local function Next()
        n = n + 1
        local q = quests[n]
        if not q then
            if prevMap and prevMap > 0 and C_QuestLog.SetMapForQuestPOIs then pcall(C_QuestLog.SetMapForQuestPOIs, prevMap) end
            Print("done, results saved in RunewayDB.probe (written on /reload or logout)")
            if visible then
                f:DrawNone()
                for _, qq in ipairs(quests) do f:DrawBlob(qq.questID, true) end
                Print("frame stays visible in the screen centre, /rnw probe hide")
            else
                f:Hide()
            end
            return
        end
        SampleQuest(f, q, res, function(r)
            RunewayDB.probe.quests[#RunewayDB.probe.quests + 1] = r
            local c, fi = r.coarse, r.fine
            Print(("  quest %d: coarse %d hits%s, fine %s"):format(r.questID, c.hits,
                c.errors > 0 and (" (" .. c.errors .. " errors)") or "",
                fi and ("%d x %d, %d hits, bbox %.3f,%.3f - %.3f,%.3f"):format(fi.nx, fi.ny, fi.hits,
                    unpack(fi.bbox or { 0, 0, 0, 0 })) or "-"))
            Next()
        end)
    end
    Next()
end
