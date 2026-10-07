-- Runeway quest areas
-- The game draws the quest areas (server data, no Lua access to the geometry) into a hidden QuestPOIFrame,
-- the same frame type the world map uses. We sample it with UpdateMouseOverTooltip(x, y), trace the outline
-- (marching squares), convert it to world coordinates and draw it as lines that rotate and zoom with the map.

local _, ns = ...

local COARSE = 64                 -- coarse grid over the whole map
local FINE_STEP = 1 / 1024        -- fine grid step in map units (~4 yd in a 4000 yd zone)
local FINE_MAX = 160              -- max fine cells per axis
local FINE_WINDOW = 0.06          -- fine window around the quest pin if the coarse grid missed the area
local BUDGET = 600                -- samples per frame
local SIMPLIFY = 0.8              -- outline simplification tolerance in fine cells
local WARMUP_MAP, WARMUP_QUEST = 1.0, 0.2   -- seconds before sampling (first draw after SetMapID is slow)
local THICKNESS = 2

local blobFrame, mapID, corners
local areas = {}          -- [questID] = { sig = string, loops = { {n1, w1, n2, w2, ...}, ... }, box = {n0, n1, w0, w1},
                          --               rect = {x0, y0, x1, y1} map units of the hits }
local groups = {}         -- overlapping quests sampled together: [key] = { loops, box, members = {questID, ...} }
local inGroup = {}        -- [questID] = group key (drawn by the group instead of on its own)
local queue = {}          -- quests to sample: { questID = , x = , y = , sig = }
local job                 -- quest being sampled
local dirty = 0           -- > 0: refresh the quest list after this many seconds
local lines, shownLines = {}, 0
ns.questAreas, ns.questGroups = areas, groups   -- for tests

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
-- Loops in doubled grid coordinates (sample c, r sits at 2c + 4, 2r + 4)
local function Trace(grid, nx, ny)
    local function v(c, r)
        return c >= 0 and r >= 0 and c < nx and r < ny and grid[r * nx + c + 1] or false
    end
    local adj = {}
    local function node(x, y)
        local key = x * 8192 + y
        local nd = adj[key]
        if not nd then nd = { x = x, y = y }; adj[key] = nd end
        return key, nd
    end
    local function link(ax, ay, bx, by)
        local ka, na = node(ax, ay)
        local kb, nb = node(bx, by)
        na[#na + 1] = kb
        nb[#nb + 1] = ka
    end
    for r = -1, ny - 1 do
        for c = -1, nx - 1 do
            local tl, tr, br, bl = v(c, r), v(c + 1, r), v(c + 1, r + 1), v(c, r + 1)
            if not (tl == tr and tr == br and br == bl) then
                local X, Y = 2 * c + 4, 2 * r + 4
                local top, right, bottom, left = { X + 1, Y }, { X + 2, Y + 1 }, { X + 1, Y + 2 }, { X, Y + 1 }
                local e = {}
                if tl ~= tr then e[#e + 1] = top end
                if tr ~= br then e[#e + 1] = right end
                if br ~= bl then e[#e + 1] = bottom end
                if bl ~= tl then e[#e + 1] = left end
                if #e == 2 then
                    link(e[1][1], e[1][2], e[2][1], e[2][2])
                elseif tl then        -- saddle: tl and br inside, keep them separate
                    link(top[1], top[2], left[1], left[2])
                    link(bottom[1], bottom[2], right[1], right[2])
                else                  -- saddle: tr and bl inside
                    link(top[1], top[2], right[1], right[2])
                    link(bottom[1], bottom[2], left[1], left[2])
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
                local nd = adj[cur]
                xs[#xs + 1], ys[#ys + 1] = nd.x, nd.y
                local nxt = (nd[1] ~= prev) and nd[1] or nd[2]
                prev, cur = cur, nxt
            until cur == nil or seen[cur]
            if #xs >= 4 then loops[#loops + 1] = { xs, ys } end
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

-- Closed loop in grid units -> smoothed world loop { n1, w1, n2, w2, ... }; also extends box
local function ToWorldLoop(xs, ys, box)
    local n = #xs
    -- split the closed loop at the point farthest from the first one
    local far, fd = 1, 0
    for m = 2, n do
        local d = (xs[m] - xs[1]) ^ 2 + (ys[m] - ys[1]) ^ 2
        if d > fd then far, fd = m, d end
    end
    xs[n + 1], ys[n + 1] = xs[1], ys[1]
    local keep = { [1] = true, [far] = true }
    Simplify(xs, ys, 1, far, SIMPLIFY * 2, keep)
    Simplify(xs, ys, far, n + 1, SIMPLIFY * 2, keep)
    local px, py = {}, {}
    for m = 1, n do
        if keep[m] then px[#px + 1], py[#py + 1] = xs[m], ys[m] end
    end
    local out, cnt = {}, #px
    if cnt < 3 then return end
    local n0, n1, w0, w1 = corners[1], corners[2], corners[3], corners[4]
    local function add(gx, gy)
        local mx = job.x0 + ((gx - 4) / 2 + 0.5) * job.dx
        local my = job.y0 + ((gy - 4) / 2 + 0.5) * job.dy
        local north, west = n0 + (n1 - n0) * my, w0 + (w1 - w0) * mx
        out[#out + 1], out[#out + 2] = north, west
        box[1], box[2] = math.min(box[1], north), math.max(box[2], north)
        box[3], box[4] = math.min(box[3], west), math.max(box[4], west)
    end
    for m = 1, cnt do                -- one Chaikin step: rounds the corners like the world map blobs
        local m2 = m % cnt + 1
        add(0.75 * px[m] + 0.25 * px[m2], 0.75 * py[m] + 0.25 * py[m2])
        add(0.25 * px[m] + 0.75 * px[m2], 0.25 * py[m] + 0.75 * py[m2])
    end
    return out
end

local function Finish()
    local area = { sig = job.sig, loops = {}, box = { math.huge, -math.huge, math.huge, -math.huge } }
    if job.hits > 0 and corners then
        for _, l in ipairs(Trace(job.grid, job.nx, job.ny)) do
            local wl = ToWorldLoop(l[1], l[2], area.box)
            if wl then area.loops[#area.loops + 1] = wl end
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
    for _ = 1, BUDGET do
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
        if job.i >= total then break end
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
        wipe(areas)
        wipe(groups)
        wipe(inGroup)
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
    dirty = 0.5               -- debounce: QUEST_LOG_UPDATE fires in bursts
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
        l:SetThickness(THICKNESS)
        local c = ns.db().colors.questAreas
        l:SetColorTexture(c.r, c.g, c.b, c.a)
        ns.Fade(l)
        lines[i] = l
    end
    return l
end

function ns.ApplyQuestAreaColor()
    local c = ns.db().colors.questAreas
    for _, l in ipairs(lines) do l:SetColorTexture(c.r, c.g, c.b, c.a) end
end

function ns.HideQuestAreas()
    for i = 1, shownLines do lines[i]:Hide() end
    shownLines = 0
end

local function DrawArea(a, n, pN, pW, reach, W2, H2)
    local b = a.box
    if not (b[1] < pN + reach and b[2] > pN - reach and b[3] < pW + reach and b[4] > pW - reach) then return n end
    local view, ToScreen = ns.view, ns.ToScreen
    for _, loop in ipairs(a.loops) do
        local cnt = #loop
        local x0, y0 = ToScreen(loop[cnt - 1], loop[cnt])
        for m = 1, cnt, 2 do
            local x1, y1 = ToScreen(loop[m], loop[m + 1])
            -- soft edge: same oval fade as the tile mask (lines do not take mask textures)
            local mx, my = (x0 + x1) / (2 * W2), (y0 + y1) / (2 * H2)
            local t = (1 - math.sqrt(mx * mx + my * my)) / 0.38
            if t > 0 then
                t = t >= 1 and 1 or t * t * (3 - 2 * t)
                n = n + 1
                local l = GetLine(n)
                l:SetStartPoint("CENTER", view, x0, y0)
                l:SetEndPoint("CENTER", view, x1, y1)
                l:SetAlpha(t)
                l:Show()
            end
            x0, y0 = x1, y1
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
        for _, g in pairs(groups) do
            if #g.loops > 0 then n = DrawArea(g, n, pN, pW, reach, W / 2, H / 2) end
        end
        for qid, a in pairs(areas) do
            local g = groups[inGroup[qid] or ""]
            if not (g and #g.loops > 0) then n = DrawArea(a, n, pN, pW, reach, W / 2, H / 2) end
        end
    end
    for i = n + 1, shownLines do lines[i]:Hide() end
    shownLines = n
end
