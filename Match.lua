local _, ns = ...

---------------------------------------------------------------------
-- Text normalisation
---------------------------------------------------------------------
local LEET = {
    ["@"] = "a", ["$"] = "s", ["0"] = "o", ["1"] = "i",
    ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t",
}

-- lowercase, drop apostrophes, turn every other symbol into a space
local function Clean(s)
    s = s:lower()
    s = s:gsub("\226\128\153", ""):gsub("'", "")   -- curly + straight apostrophes
    s = s:gsub("[^%w%s]", " ")
    s = s:gsub("%s+", " ")
    return (s:match("^%s*(.-)%s*$"))
end

-- "t r u m p" -> "trump" (only joins runs of 4+ single characters)
local function JoinSpelledOut(s)
    local out, run = {}, {}
    local function flush()
        if #run >= 4 then
            out[#out + 1] = table.concat(run)
        else
            for _, t in ipairs(run) do out[#out + 1] = t end
        end
        run = {}
    end
    for token in s:gmatch("%S+") do
        if #token == 1 then
            run[#run + 1] = token
        else
            flush()
            out[#out + 1] = token
        end
    end
    flush()
    return table.concat(out, " ")
end

-- remove hyperlinks, textures and colour codes (BEFORE lowercasing: |H vs |h)
local function StripEscapes(msg)
    return (msg:gsub("|H.-|h.-|h", " "):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

---------------------------------------------------------------------
-- Lookup tables (built lazily so file load order doesn't matter)
---------------------------------------------------------------------
local singles, phrases, safe, built

-- ns.disabledCategories (["key"] = true) and ns.customWords (a list) are the
-- user's settings from RageBuster.lua; call ns.RebuildWords() after changing them.
local function Build()
    built = true
    singles, phrases, safe = {}, {}, {}

    local function Add(w)
        local n = Clean(w)
        if n ~= "" and not singles[n] then
            if n:find(" ", 1, true) then
                phrases[#phrases + 1] = { word = n, a = " " .. n .. " ", b = " " .. n .. "s " }
            else
                singles[n] = true
            end
        end
    end

    local off = ns.disabledCategories or {}
    for _, cat in ipairs(ns.wordCategories or {}) do
        if not off[cat.key] then
            for _, w in ipairs(cat.words) do Add(w) end
        end
    end
    for _, w in ipairs(ns.customWords or {}) do Add(w) end

    for _, p in ipairs(ns.safePhrases or {}) do
        safe[#safe + 1] = " " .. Clean(p) .. " "
    end
end

-- returns the text that matched and the list entry it matched, or nil
local function FindBlockedWord(text)
    local padded = " " .. text .. " "

    for _, s in ipairs(safe) do
        padded = padded:gsub(s, " ")
    end

    for tok in padded:gmatch("%S+") do
        if singles[tok] then return tok, tok end
        if tok:sub(-1) == "s" and singles[tok:sub(1, -2)] then return tok, tok:sub(1, -2) end
    end

    for _, ph in ipairs(phrases) do
        if padded:find(ph.a, 1, true) or padded:find(ph.b, 1, true) then
            return ph.word, ph.word
        end
    end
end

function ns.RebuildWords()
    built = false
end

-- a word the way matching sees it: lowercase, no punctuation ("Let's go!" -> "lets go")
function ns.CleanWord(w)
    return Clean(w or "")
end

-- returns the blocked word that matched and the list entry it came from, or nil
function ns.MatchBlocked(msg)
    if not built then Build() end

    local stripped = StripEscapes(msg)

    local hit, entry = FindBlockedWord(JoinSpelledOut(Clean(stripped)))
    if hit then return hit, entry end

    -- second pass with leetspeak undone ("tr4mp", "b1den", "$imp")
    local low = stripped:lower()
    if low:find("[@$013457]") then
        local deleeted = low:gsub("[@$013457]", LEET)
        return FindBlockedWord(JoinSpelledOut(Clean(deleeted)))
    end
end

-- true when a matched list entry is one of the slurs that ignore a player
-- immediately, without waiting for review (POLICY.md, "Auto adding")
function ns.IsAutoIgnore(entry)
    if not ns.autoIgnoreSet then
        ns.autoIgnoreSet = {}
        for _, w in ipairs(ns.autoIgnoreWords or {}) do ns.autoIgnoreSet[Clean(w)] = true end
    end
    return entry ~= nil and ns.autoIgnoreSet[entry] == true
end

-- plain text for the log: links reduced to their visible name, colours removed
function ns.PlainText(msg)
    return (msg:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
