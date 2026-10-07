-- Runeway quest areas
-- The game draws the quest areas (server data, no Lua access to the geometry) into a hidden QuestPOIFrame,
-- the same frame type the world map uses. We sample it with UpdateMouseOverTooltip(x, y), trace the outline
-- (marching squares), convert it to world coordinates and draw it as lines that rotate and zoom with the map.

local _, ns = ...

local COARSE = 48                 -- coarse grid over the whole map
local FINE_STEP = 1 / 640         -- fine grid step in map units (~6 yd in a 4000 yd zone; the outline is interpolated)
local FINE_MAX = 112              -- max fine cells per axis
local FINE_WINDOW = 0.06          -- fine window around the quest pin if the coarse grid missed the area
local BUDGET_MS = 3                -- sampling time per frame in milliseconds
local SIMPLIFY = 0.35             -- outline simplification tolerance in fine cells
local WARMUP_MAP, WARMUP_QUEST = 1.0, 0.2   -- seconds before sampling (first draw after SetMapID is slow)
local MIN_SEG = 5                 -- minimum drawn segment length in screen pixels (shorter ones WoW drops)
local SUB_SEG = 6                 -- zoomed in, the outline is subdivided (Catmull-Rom) into pieces of ~this px
-- Outline: one bright anti-aliased edge line (an inner glow made of offset lines showed cross stripes at
-- the segment joints, so there is none).
-- Line textures fade to 0 at their borders: WoW does not anti-alias line quads, the texture does.
local MEDIA = "Interface\\AddOns\\Runeway\\media\\"
-- Widths follow the zoom like the terrain lines in the tiles: edge = tile size on screen / EDGE_DIV px
local EDGE_DIV, EDGE_MIN, EDGE_MAX = 140, 2, 7     -- edge line (media/edge.tga: core = half the width)

local blobFrame, mapID, corners
local areas = {}          -- [questID] = { sig = string, loops = { {n1, w1, n2, w2, ...}, ... }, box = {n0, n1, w0, w1},
                          --               rect = {x0, y0, x1, y1} map units of the hits }
local groups = {}         -- overlapping quests sampled together: [key] = { loops, box, members = {questID, ...} }
local inGroup = {}        -- [questID] = group key (drawn by the group instead of on its own)
local queue = {}          -- quests to sample: { questID = , x = , y = , sig = }
local job                 -- quest being sampled
local dirty = 0           -- > 0: refresh the quest list after this many seconds
local lines, shownLines = {}, 0
ns.QuestAreaState = function() return areas, groups end   -- for tests

---------------------------------------------------------------------------
-- Sampling
---------------------------------------------------------------------------
local function GetBlobFrame()
    if blobFrame then return blobFrame end
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, UIParent)
    if not ok or not f then return end
    f:SetSize(512, 512)
    f:SetPoint("CENTER")
    f:SetFrameStrata("BACKGROUND")
    f:SetAlpha(0)
    if f.EnableMouse then f:EnableMouse(false) end
    f:Hide()
    blobFrame = f
    return f
end

local function IsHit(questID, x, y)
    local ok, a, b = pcall(blobFrame.UpdateMouseOverTooltip, blobFrame, x, y)
    -- questID nil: group job, any drawn blob counts
    return ok and a ~= nil and (questID == nil or a == questID or (b ~= nil and b > 0))
end

-- Starts sampling rectangle x0, y0 .. x1, y1 (map units) on an nx x ny grid
local function StartPass(phase, x0, y0, x1, y1, nx, ny, wait)
    job.phase, job.wait, job.i = phase, wait or 0, 0
    job.x0, job.y0, job.nx, job.ny = x0, y0, nx, ny
    job.dx, job.dy = (x1 - x0) / nx, (y1 - y0) / ny
    job.grid, job.hits = {}, 0
    job.minC, job.minR, job.maxC, job.maxR = nx, ny, -1, -1
end

---------------------------------------------------------------------------
-- Outline: marching squares -> loops -> simplify -> smooth -> world coordinates
---------------------------------------------------------------------------
-- Outline loops in sample coordinates (sample c, r sits at c, r). The hit grid is blurred first and the
-- iso line 0.5 is interpolated along the cell edges, which removes the staircase of the sample grid.
local function Trace(grid, nx, ny)
    local PAD = 3
    local W = nx + 2 * PAD
    local f = {}
    for r = -PAD, ny + PAD - 1 do
        for c = -PAD, nx + PAD - 1 do
            f[(r + PAD) * W + c + PAD + 1] = (c >= 0 and r >= 0 and c < nx and r < ny and grid[r * nx + c + 1]) and 1 or 0
        end
    end
    -- two passes of a 3x3 box blur (close to a small gaussian)
    for _ = 1, 2 do
        local g = {}
        for r = 0, ny + 2 * PAD - 1 do
            for c = 0, W - 1 do
                local sum, cnt = 0, 0
                for dr = -1, 1 do
                    local rr = r + dr
                    if rr >= 0 and rr < ny + 2 * PAD then
                        for dc = -1, 1 do
                            local cc = c + dc
                            if cc >= 0 and cc < W then
                                sum, cnt = sum + f[rr * W + cc + 1], cnt + 1
                            end
                        end
                    end
                end
                g[r * W + c + 1] = sum / cnt
            end
        end
        f = g
    end
    local function v(c, r) return f[(r + PAD) * W + c + PAD + 1] end
    local ISO = 0.5
    -- edge ids: horizontal edge (c, r)-(c+1, r) and vertical edge (c, r)-(c, r+1)
    local pos, adj = {}, {}
    local function edge(horiz, c, r)
        local key = ((r + PAD) * W + c + PAD) * 2 + (horiz and 0 or 1)
        if not pos[key] then
            local a, b
            if horiz then a, b = v(c, r), v(c + 1, r) else a, b = v(c, r), v(c, r + 1) end
            local t = (ISO - a) / (b - a)
            pos[key] = horiz and { c + t, r } or { c, r + t }
            adj[key] = {}
        end
        return key
    end
    local function link(ka, kb)
        local A, B = adj[ka], adj[kb]
        A[#A + 1] = kb
        B[#B + 1] = ka
    end
    for r = -PAD, ny + PAD - 2 do
        for c = -PAD, nx + PAD - 2 do
            local tl, tr, br, bl = v(c, r) > ISO, v(c + 1, r) > ISO, v(c + 1, r + 1) > ISO, v(c, r + 1) > ISO
            if not (tl == tr and tr == br and br == bl) then
                local e = {}
                if tl ~= tr then e[#e + 1] = edge(true, c, r) end
                if tr ~= br then e[#e + 1] = edge(false, c + 1, r) end
                if br ~= bl then e[#e + 1] = edge(true, c, r + 1) end
                if bl ~= tl then e[#e + 1] = edge(false, c, r) end
                if #e == 2 then
                    link(e[1], e[2])
                else
                    -- saddle (e = top, right, bottom, left): decide by the centre value
                    local centre = (v(c, r) + v(c + 1, r) + v(c + 1, r + 1) + v(c, r + 1)) / 4 > ISO
                    if centre == tl then
                        link(e[1], e[2]); link(e[3], e[4])
                    else
                        link(e[1], e[4]); link(e[2], e[3])
                    end
                end
            end
        end
    end
    local loops, seen = {}, {}
    for start in pairs(adj) do
        if not seen[start] then
            local xs, ys = {}, {}
            local prev, cur = nil, start
            repeat
                seen[cur] = true
                local p = pos[cur]
                xs[#xs + 1], ys[#ys + 1] = p[1], p[2]
                local nd = adj[cur]
                local nxt = (nd[1] ~= prev) and nd[1] or nd[2]
                prev, cur = cur, nxt
            until cur == nil or seen[cur]
            if #xs >= 4 then
                -- which side of the loop is the area: probe the blurred field next to the first segment
                local dx, dy = xs[2] - xs[1], ys[2] - ys[1]
                local len = math.sqrt(dx * dx + dy * dy)
                local mx, my = (xs[1] + xs[2]) / 2 - dy / len * 0.6, (ys[1] + ys[2]) / 2 + dx / len * 0.6
                local c0, r0 = math.floor(mx), math.floor(my)
                local fx, fy = mx - c0, my - r0
                local val = (v(c0, r0) * (1 - fx) + v(c0 + 1, r0) * fx) * (1 - fy)
                    + (v(c0, r0 + 1) * (1 - fx) + v(c0 + 1, r0 + 1) * fx) * fy
                loops[#loops + 1] = { xs, ys, plus = val > ISO }   -- plus: area at (-dy, dx) of the direction
            end
        end
    end
    return loops
end

-- Douglas-Peucker on xs/ys[i..j], marks kept points
local function Simplify(xs, ys, i, j, tol, keep)
    local ax, ay, bx, by = xs[i], ys[i], xs[j], ys[j]
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    local maxd, idx = 0
    for m = i + 1, j - 1 do
        local d = len < 1e-9 and math.sqrt((xs[m] - ax) ^ 2 + (ys[m] - ay) ^ 2)
            or math.abs(dy * xs[m] - dx * ys[m] + bx * ay - by * ax) / len
        if d > maxd then maxd, idx = d, m end
    end
    if idx and maxd > tol then
        keep[idx] = true
        Simplify(xs, ys, i, idx, tol, keep)
        Simplify(xs, ys, idx, j, tol, keep)
    end
end

-- Closed loop -> fewer points (Douglas-Peucker) -> rounded (two Chaikin steps), sample coordinates
local function SmoothLoop(xs, ys)
    local n = #xs
    local far, fd = 1, 0             -- split the closed loop at the point farthest from the first one
    for m = 2, n do
        local d = (xs[m] - xs[1]) ^ 2 + (ys[m] - ys[1]) ^ 2
        if d > fd then far, fd = m, d end
    end
    xs[n + 1], ys[n + 1] = xs[1], ys[1]
    local keep = { [1] = true, [far] = true }
    Simplify(xs, ys, 1, far, SIMPLIFY, keep)
    Simplify(xs, ys, far, n + 1, SIMPLIFY, keep)
    local px, py = {}, {}
    for m = 1, n do
        if keep[m] then px[#px + 1], py[#py + 1] = xs[m], ys[m] end
    end
    if #px < 3 then return end
    for _ = 1, 2 do
        local qx, qy, cnt = {}, {}, #px
        for m = 1, cnt do
            local m2 = m % cnt + 1
            qx[#qx + 1], qy[#qy + 1] = 0.75 * px[m] + 0.25 * px[m2], 0.75 * py[m] + 0.25 * py[m2]
            qx[#qx + 1], qy[#qy + 1] = 0.25 * px[m] + 0.75 * px[m2], 0.25 * py[m] + 0.75 * py[m2]
        end
        px, py = qx, qy
    end
    return px, py
end
ns.TraceOutline = function(grid, nx, ny)   -- for tests: smoothed loops in sample coordinates
    local out = {}
    for _, l in ipairs(Trace(grid, nx, ny)) do
        local px, py = SmoothLoop(l[1], l[2])
        if px then out[#out + 1] = { px, py, plus = l.plus } end
    end
    return out
end

-- Closed loop in sample coordinates -> smoothed world loop { n1, w1, n2, w2, ... }; also extends box
local function ToWorldLoop(xs, ys, box)
    local px, py = SmoothLoop(xs, ys)
    if not px then return end
    local out = {}
    local n0, n1, w0, w1 = corners[1], corners[2], corners[3], corners[4]
    for m = 1, #px do
        local mx = job.x0 + (px[m] + 0.5) * job.dx
        local my = job.y0 + (py[m] + 0.5) * job.dy
        local north, west = n0 + (n1 - n0) * my, w0 + (w1 - w0) * mx
        out[#out + 1], out[#out + 2] = north, west
        box[1], box[2] = math.min(box[1], north), math.max(box[2], north)
        box[3], box[4] = math.min(box[3], west), math.max(box[4], west)
    end
    return out
end

local function Finish()
    local area = { sig = job.sig, loops = {}, box = { math.huge, -math.huge, math.huge, -math.huge } }
    if job.hits > 0 and corners then
        for _, l in ipairs(Trace(job.grid, job.nx, job.ny)) do
            local wl = ToWorldLoop(l[1], l[2], area.box)
            if wl then
                -- inward normal on screen for a segment (dx, dy): inward * (dy, -dx)
                -- (sample -> world mirrors, world -> screen keeps the orientation)
                wl.inward = l.plus and 1 or -1
                area.loops[#area.loops + 1] = wl
            end
        end
        area.rect = { job.x0 + job.minC * job.dx, job.y0 + job.minR * job.dy,
                      job.x0 + (job.maxC + 1) * job.dx, job.y0 + (job.maxR + 1) * job.dy }
    end
    if job.group then
        area.members = job.members
        groups[job.group] = area
        for _, qid in ipairs(job.members) do inGroup[qid] = job.group end
    else
        areas[job.questID] = area
    end
    job = nil
end

-- Runs a slice of the current job
local function Step(e)
    if job.wait > 0 then
        job.wait = job.wait - e
        return
    end
    local f, qid, nx, ny = blobFrame, job.questID, job.nx, job.ny
    local total = nx * ny
    local stop = debugprofilestop() + BUDGET_MS
    while true do
        local i = job.i
        local r, c = math.floor(i / nx), i % nx
        local hit = IsHit(qid, job.x0 + (c + 0.5) * job.dx, job.y0 + (r + 0.5) * job.dy)
        job.grid[i + 1] = hit
        if hit then
            job.hits = job.hits + 1
            job.minC, job.minR = math.min(job.minC, c), math.min(job.minR, r)
            job.maxC, job.maxR = math.max(job.maxC, c), math.max(job.maxR, r)
        end
        job.i = i + 1
        if job.i >= total or (i % 64 == 0 and debugprofilestop() > stop) then break end
    end
    if job.i < total then return end

    if job.group then
        Finish()
    elseif job.phase == "coarse" then
        local x0, y0, x1, y1
        if job.hits > 0 then
            x0, y0 = job.x0 + (job.minC - 2) * job.dx, job.y0 + (job.minR - 2) * job.dy
            x1, y1 = job.x0 + (job.maxC + 3) * job.dx, job.y0 + (job.maxR + 3) * job.dy
        elseif job.x then
            x0, y0, x1, y1 = job.x - FINE_WINDOW, job.y - FINE_WINDOW, job.x + FINE_WINDOW, job.y + FINE_WINDOW
        end
        if not x0 then return Finish() end
        x0, y0, x1, y1 = math.max(0, x0), math.max(0, y0), math.min(1, x1), math.min(1, y1)
        local step = math.max(FINE_STEP, (x1 - x0) / FINE_MAX, (y1 - y0) / FINE_MAX)
        local fx, fy = math.max(1, math.ceil((x1 - x0) / step)), math.max(1, math.ceil((y1 - y0) / step))
        StartPass("fine", x0, y0, x0 + fx * step, y0 + fy * step, fx, fy)
    elseif job.hits == 0 and not job.retried then
        -- the blob was not ready yet: draw again and repeat once
        job.retried = true
        f:DrawNone()
        f:DrawBlob(qid, true)
        StartPass("coarse", 0, 0, 1, 1, COARSE, COARSE, WARMUP_MAP)
    else
        Finish()
    end
end

-- Overlapping quest areas are sampled once more with all their blobs drawn, so they get one outline
local function NextGroupJob()
    local ids = {}
    for qid, a in pairs(areas) do
        if a.rect then ids[#ids + 1] = qid end
    end
    table.sort(ids)
    local parent = {}
    local function root(q) while parent[q] do q = parent[q] end return q end
    for i = 1, #ids do
        for j = i + 1, #ids do
            local a, b = areas[ids[i]].rect, areas[ids[j]].rect
            if a[1] <= b[3] and b[1] <= a[3] and a[2] <= b[4] and b[2] <= a[4] then
                local ri, rj = root(ids[i]), root(ids[j])
                if ri ~= rj then parent[rj] = ri end
            end
        end
    end
    local sets = {}
    for _, qid in ipairs(ids) do
        local r = root(qid)
        sets[r] = sets[r] or {}
        table.insert(sets[r], qid)
    end
    for _, members in pairs(sets) do
        if #members > 1 then
            local key = {}
            for _, qid in ipairs(members) do key[#key + 1] = qid .. "=" .. areas[qid].sig end
            key = table.concat(key, ",")
            if not groups[key] then
                local x0, y0, x1, y1 = 1, 1, 0, 0
                for _, qid in ipairs(members) do
                    local r = areas[qid].rect
                    x0, y0, x1, y1 = math.min(x0, r[1]), math.min(y0, r[2]), math.max(x1, r[3]), math.max(y1, r[4])
                end
                return key, members, x0, y0, x1, y1
            end
        end
    end
end

local function StartGroupJob(key, members, x0, y0, x1, y1)
    job = { group = key, members = members }
    blobFrame:DrawNone()
    for _, qid in ipairs(members) do blobFrame:DrawBlob(qid, true) end
    local m = 2 * FINE_STEP
    x0, y0, x1, y1 = math.max(0, x0 - m), math.max(0, y0 - m), math.min(1, x1 + m), math.min(1, y1 + m)
    local step = math.max(FINE_STEP, (x1 - x0) / FINE_MAX, (y1 - y0) / FINE_MAX)
    local fx, fy = math.max(1, math.ceil((x1 - x0) / step)), math.max(1, math.ceil((y1 - y0) / step))
    StartPass("fine", x0, y0, x0 + fx * step, y0 + fy * step, fx, fy, WARMUP_QUEST)
end

local function StartJob(q, warmup)
    job = { questID = q.questID, x = q.x, y = q.y, sig = q.sig }
    blobFrame:DrawNone()
    blobFrame:DrawBlob(q.questID, true)
    StartPass("coarse", 0, 0, 1, 1, COARSE, COARSE, warmup)
end

---------------------------------------------------------------------------
-- Quest list: which quests need (re)sampling
---------------------------------------------------------------------------
local function Signature(q)
    local s = ("%d:%.3f:%.3f"):format(GetQuestPOIBlobCount and GetQuestPOIBlobCount(q.questID) or -1, q.x or 0, q.y or 0)
    local obj = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.questID)
    for _, o in ipairs(obj or {}) do
        s = s .. ":" .. tostring(o.numFulfilled) .. (o.finished and "f" or "")
    end
    return s
end

local mapWarm = false     -- false: next job needs the long warm-up (new map set on the blob frame)

local function Refresh()
    local m = C_Map.GetBestMapForUnit("player")
    if not (m and C_QuestLog.GetQuestsOnMap and GetBlobFrame()) then return end
    if m ~= mapID then
        mapID = m
        -- areas are kept per map in the saved variables, so they show up at once after /reload or relog
        local db = ns.db()
        if db.questAreaCacheVersion ~= 2 then        -- 2: loops know the side of the area (inward glow)
            db.questAreaCache, db.questAreaCacheVersion = {}, 2
        end
        local cache = db.questAreaCache
        cache[m] = cache[m] or { areas = {}, groups = {} }
        areas, groups = cache[m].areas, cache[m].groups
        wipe(inGroup)
        for key, g in pairs(groups) do
            for _, qid in ipairs(g.members) do inGroup[qid] = key end
        end
        wipe(queue)
        job = nil
        local n0, w0 = ns.MapToWorld(m, 0, 0)
        local n1, w1 = ns.MapToWorld(m, 1, 1)
        corners = n0 and n1 and { n0, n1, w0, w1 } or nil
        blobFrame:SetMapID(m)
        mapWarm = false
    end
    local onMap = {}
    wipe(queue)
    for _, q in ipairs(C_QuestLog.GetQuestsOnMap(m) or {}) do
        onMap[q.questID] = true
        local blobs = GetQuestPOIBlobCount and GetQuestPOIBlobCount(q.questID)
        local sig = Signature(q)
        if blobs == 0 then
            areas[q.questID] = nil
        elseif not (areas[q.questID] and areas[q.questID].sig == sig) and not (job and job.questID == q.questID) then
            queue[#queue + 1] = { questID = q.questID, x = q.x, y = q.y, sig = sig }
        end
    end
    for qid in pairs(areas) do
        if not onMap[qid] then areas[qid] = nil end
    end
    -- nearest quests first
    local mp = C_Map.GetPlayerMapPosition(m, "player")
    local px, py
    if mp then px, py = mp:GetXY() end
    if px then
        table.sort(queue, function(a, b)
            return ((a.x or 0) - px) ^ 2 + ((a.y or 0) - py) ^ 2 < ((b.x or 0) - px) ^ 2 + ((b.y or 0) - py) ^ 2
        end)
    end
    -- a group stays valid only while all members are unchanged and not queued
    local queued = {}
    for _, q in ipairs(queue) do queued[q.questID] = true end
    for key, g in pairs(groups) do
        for _, qid in ipairs(g.members) do
            if not areas[qid] or queued[qid] then
                for _, m in ipairs(g.members) do if inGroup[m] == key then inGroup[m] = nil end end
                groups[key] = nil
                break
            end
        end
    end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, e)
    if dirty > 0 then
        dirty = dirty - e
        if dirty <= 0 then Refresh() end
    end
    if not ns.view:IsShown() or InCombatLockdown() then return end
    if not job and #queue > 0 then
        blobFrame:Show()
        StartJob(table.remove(queue, 1), mapWarm and WARMUP_QUEST or WARMUP_MAP)
        mapWarm = true
    elseif not job and blobFrame then
        local key, members, x0, y0, x1, y1 = NextGroupJob()
        if key then
            blobFrame:Show()
            StartGroupJob(key, members, x0, y0, x1, y1)
        end
    end
    if job then
        Step(e)
    elseif blobFrame and blobFrame:IsShown() then
        blobFrame:Hide()
    end
end)
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:RegisterEvent("QUEST_LOG_UPDATE")
driver:RegisterEvent("QUEST_POI_UPDATE")
driver:SetScript("OnEvent", function()
    dirty = 0.3               -- debounce: QUEST_LOG_UPDATE fires in bursts
end)
ns.view:HookScript("OnShow", function() dirty = 0.1 end)

---------------------------------------------------------------------------
-- Drawing (called by Core.lua every update)
---------------------------------------------------------------------------
local lineParent = CreateFrame("Frame", nil, ns.view)
lineParent:SetAllPoints()
lineParent:SetFrameLevel(ns.view:GetFrameLevel() + 3)
lineParent:SetClipsChildren(true)       -- hard edge if lines do not take the fade mask

local function GetLine(i)
    local l = lines[i]
    if not l then
        l = lineParent:CreateLine(nil, "ARTWORK")
        l:SetTexture(MEDIA .. "edge.tga")
        ns.NoSnap(l)
        lines[i] = l
    end
    return l
end

function ns.ApplyQuestAreaColor() end      -- colours are set per segment in DrawArea

function ns.HideQuestAreas()
    for i = 1, shownLines do lines[i]:Hide() end
    shownLines = 0
end

-- true if the quest has an outline (its pin is then hidden)
function ns.HasQuestArea(questID)
    local a, g = areas[questID], groups[inGroup[questID] or ""]
    return (a and #a.loops > 0) or (g and #g.loops > 0) or false
end

local px, py, qx, qy, qa = {}, {}, {}, {}, {}   -- reused buffers: screen points, subdivided points, fade

local function DrawArea(a, n, pN, pW, reach, W2, H2, ew)
    local b = a.box
    if not (b[1] < pN + reach and b[2] > pN - reach and b[3] < pW + reach and b[4] > pW - reach) then return n end
    local view, ToScreen = ns.view, ns.ToScreen
    local c = ns.db().colors.questAreas
    local ov = math.min(1, ew / 2)       -- 1 px overlap closes the joints; more would show in the fade
    local fw = ns.FadeWidth()
    local function fade(x, y)            -- soft edge of the map: same oval fade as the tile mask
        local mx, my = x / W2, y / H2
        local t = (1 - math.sqrt(mx * mx + my * my)) / fw
        if t <= 0 then return 0 end
        return t >= 1 and 1 or t * t * (3 - 2 * t)
    end
    for _, loop in ipairs(a.loops) do
        -- screen points, at least MIN_SEG apart (zoomed out)
        local cnt, k = #loop, 0
        for m = 1, cnt, 2 do
            local x, y = ToScreen(loop[m], loop[m + 1])
            if k == 0 or (x - px[k]) ^ 2 + (y - py[k]) ^ 2 >= MIN_SEG * MIN_SEG then
                k = k + 1
                px[k], py[k] = x, y
            end
        end
        if k >= 3 then
            -- zoomed in: Catmull-Rom subdivision, so the curve stays round instead of showing straight pieces
            local q = 0
            for i = 1, k do
                local h, j, l = (i - 2) % k + 1, i % k + 1, (i + 1) % k + 1
                local len = math.sqrt((px[j] - px[i]) ^ 2 + (py[j] - py[i]) ^ 2)
                local steps = math.min(12, math.max(1, math.floor(len / SUB_SEG)))
                for st = 0, steps - 1 do
                    local t = st / steps
                    local t2, t3 = t * t, t * t * t
                    local w0, w1 = -0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1
                    local w2, w3 = -1.5 * t3 + 2 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2
                    q = q + 1
                    qx[q] = w0 * px[h] + w1 * px[i] + w2 * px[j] + w3 * px[l]
                    qy[q] = w0 * py[h] + w1 * py[i] + w2 * py[j] + w3 * py[l]
                end
            end
            for i = 1, q do qa[i] = fade(qx[i], qy[i]) end
            for i = 1, q do
                local j = i % q + 1
                local x0, y0, x1, y1 = qx[i], qy[i], qx[j], qy[j]
                local dx, dy = x1 - x0, y1 - y0
                local len = math.sqrt(dx * dx + dy * dy)
                local t = (qa[i] + qa[j]) / 2
                if t > 0 and len > 0 then
                    n = n + 1
                    local l = GetLine(n)
                    -- overlap only at full opacity: semi-transparent overlaps show as dots in the fade
                    local o = t >= 0.999 and ov or 0
                    local ex, ey = dx / len * o, dy / len * o
                    if l.w ~= ew then
                        l.w = ew
                        l:SetThickness(ew)
                    end
                    l:SetStartPoint("CENTER", view, x0 - ex, y0 - ey)
                    l:SetEndPoint("CENTER", view, x1 + ex, y1 + ey)
                    -- fade per segment (lines do not take mask textures); segments are ~6 px, so the steps are small
                    l:SetVertexColor(c.r, c.g, c.b, c.a * t)   -- not SetAlpha: it overwrites the vertex alpha
                    l:Show()
                end
            end
        end
    end
    return n
end

function ns.DrawQuestAreas()
    local n = 0
    if ns.db().layers.questAreas and (next(areas) or next(groups)) then
        local pN, pW, k = ns.Player()
        local W, H = ns.view:GetSize()
        local reach = math.sqrt(W * W + H * H) / 2 / k
        local ew = math.min(EDGE_MAX, math.max(EDGE_MIN, (1600 / 3) * k / EDGE_DIV))   -- edge width follows the zoom
            * ns.db().questEdge
        for _, g in pairs(groups) do
            if #g.loops > 0 then n = DrawArea(g, n, pN, pW, reach, W / 2, H / 2, ew) end
        end
        for qid, a in pairs(areas) do
            local g = groups[inGroup[qid] or ""]
            if not (g and #g.loops > 0) then n = DrawArea(a, n, pN, pW, reach, W / 2, H / 2, ew) end
        end
    end
    for i = n + 1, shownLines do lines[i]:Hide() end
    shownLines = n
end
