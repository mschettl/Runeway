-- Runeway quest area probe (test tool, /rnw probe)
-- Lets the game draw the quest areas into a QuestPOIFrame (same frame type as the world map)
-- and samples it on a grid via UpdateMouseOverTooltip(x, y). Results go to RunewayDB.probe.

local function Print(msg)
    print("|cff66ccffRuneway probe:|r " .. msg)
end

local frame, sampler
local RES_DEFAULT, PER_FRAME = 64, 400

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

-- Samples one quest; calls done(result) when finished (spread over several frames)
local function SampleQuest(f, mapID, questID, res, done)
    f:DrawNone()
    f:DrawBlob(questID, true)
    local rows, hits, other, errors = {}, 0, 0, 0
    local minX, minY, maxX, maxY = res, res, -1, -1
    local i, wait = 0, 0.2           -- give the engine a moment to build the blob
    sampler:SetScript("OnUpdate", function(self, e)
        if wait > 0 then wait = wait - e return end
        for _ = 1, PER_FRAME do
            local row, col = math.floor(i / res), i % res
            if col == 0 then rows[row + 1] = {} end
            local ok, a, b = pcall(f.UpdateMouseOverTooltip, f, (col + 0.5) / res, (row + 0.5) / res)
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
            if i >= res * res then
                self:SetScript("OnUpdate", nil)
                for r = 1, #rows do rows[r] = table.concat(rows[r]) end
                done({ questID = questID, title = QuestTitle(questID), mapID = mapID, res = res,
                       hits = hits, other = other, errors = errors, rows = rows,
                       bbox = hits > 0 and { minX, minY, maxX, maxY } or nil })
                return
            end
        end
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
        SampleQuest(f, mapID, q.questID, res, function(r)
            RunewayDB.probe.quests[#RunewayDB.probe.quests + 1] = r
            Print(("  quest %d: %d hits, %d other, %d errors, bbox %s"):format(r.questID, r.hits, r.other, r.errors,
                r.bbox and table.concat(r.bbox, ",") or "-"))
            Next()
        end)
    end
    Next()
end
