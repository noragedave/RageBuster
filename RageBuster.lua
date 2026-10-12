local addonName, ns = ...

ns.debug = false   -- toggle in game with: /ragebuster debug

local PREFIX = "|cffff8800[RageBuster]|r "
local MAX_LOG = 1000        -- oldest entries are dropped past this
local CONTEXT_LINES = 4     -- preceding lines kept with each hit for the reviewer
local MAX_NATIVE = 50       -- Blizzard's per-character ignore list cap

local db, charDB

local function Print(...)
    print(PREFIX .. string.format(...))
end

---------------------------------------------------------------------
-- Names
---------------------------------------------------------------------
-- chat authors are usually "Name-Realm", but some clients omit the realm
-- for players on your own realm
local function FullName(name)
    if name:find("-", 1, true) then return name end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return realm and (name .. "-" .. realm) or name
end

local function MyName()
    return FullName(UnitName("player"))
end

---------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------
local function InitDB()
    RageBusterDB = RageBusterDB or {}
    db = RageBusterDB
    db.logging = db.logging ~= false
    db.seq = db.seq or 0
    db.log = db.log or {}
    db.ignored = db.ignored or {}     -- ["Name-Realm"] = { time, reason, msg, guid, evidence }
    db.pardoned = db.pardoned or {}   -- ["Name-Realm"] = time the player was unignored
    db.released = db.released or {}   -- ignore records kept after an unignore, for review

    RageBusterCharDB = RageBusterCharDB or {}
    charDB = RageBusterCharDB
    charDB.applied = charDB.applied or {}   -- names this character has native-ignored
end

-- merge what tools/review.py wrote into Verdicts.lua
local function ImportVerdicts()
    local imp = RageBuster_Imported
    if type(imp) ~= "table" then return end
    RageBuster_Imported = nil

    local added = 0
    for name, v in pairs(imp.ignored or {}) do
        local pardon = db.pardoned[name]
        if not db.ignored[name] and not (pardon and (v.time or 0) <= pardon) then
            db.ignored[name] = v
            added = added + 1
        end
    end

    local reviewed = imp.reviewed or {}
    local kept, removed = {}, 0
    for _, e in ipairs(db.log) do
        if reviewed[e.id] then
            removed = removed + 1
        else
            kept[#kept + 1] = e
        end
    end
    db.log = kept

    if added > 0 or removed > 0 then
        Print("imported review: %d newly ignored, %d log entries cleared.", added, removed)
    end
end

---------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------
local recent = {}   -- [channel key] = { "Author: text", ... }

local function NewId()
    db.seq = db.seq + 1
    -- time + random keeps ids unique across accounts sharing one Verdicts.lua
    return string.format("%x-%x-%x", time(), db.seq, math.random(0, 0xffff))
end

local function LogHit(event, name, text, word, channel, guid, key)
    local context = {}
    for i, line in ipairs(recent[key] or {}) do context[i] = line end

    local log = db.log
    log[#log + 1] = {
        id = NewId(),
        time = time(),
        author = name,
        guid = guid,
        channel = channel,
        word = word,
        msg = text,
        context = context,
        by = MyName(),
    }
    while #log > MAX_LOG do table.remove(log, 1) end
end

local function Remember(key, name, text)
    local lines = recent[key]
    if not lines then
        lines = {}
        recent[key] = lines
    end
    lines[#lines + 1] = Ambiguate(name, "none") .. ": " .. text
    if #lines > CONTEXT_LINES then table.remove(lines, 1) end
end

---------------------------------------------------------------------
-- The chat filter
---------------------------------------------------------------------
local function Process(event, msg, author, ...)
    local name = FullName(author)

    if db.ignored[name] then
        return true
    end

    local _, channelString, _, _, _, channelIndex, _, _, _, guid = ...
    local key = event .. (channelIndex or "")
    local text = ns.PlainText(msg)
    local hit = ns.MatchBlocked(msg)

    if hit then
        if ns.debug then
            Print("blocked on '%s': %s", hit, msg)
        end
        if db.logging and name ~= MyName() then
            local channel = (channelString and channelString ~= "") and channelString or event:gsub("^CHAT_MSG_", "")
            if issecretvalue and guid and issecretvalue(guid) then guid = nil end
            LogHit(event, name, text, hit, channel, guid, key)
        end
    end

    Remember(key, name, text)
    return hit ~= nil
end

-- Each chat frame runs the filter for the same line, so the result is cached
-- by lineID: one log entry per message, not one per chat tab.
local lastLineID, lastResult

local function ChatFilter(self, event, msg, author, ...)
    if not db then return false end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(author)) then
        return false
    end

    local lineID = select(9, ...)
    if lineID and lineID == lastLineID then
        return lastResult
    end

    local result = Process(event, msg, author, ...)
    lastLineID, lastResult = lineID, result
    return result
end

---------------------------------------------------------------------
-- Blizzard ignore list
---------------------------------------------------------------------
-- Ignoring a character natively hides every character on that player's
-- account, but only for the character that did the ignoring, and the list
-- holds 50 names. Everyone past that is still hidden by the filter above.
local NativeAddIgnore = (C_FriendList and C_FriendList.AddIgnore) or AddIgnore
local NativeNumIgnores = (C_FriendList and C_FriendList.GetNumIgnores) or GetNumIgnores
local NativeIsIgnored = (C_FriendList and C_FriendList.IsIgnored) or IsIgnored

local applying = false

local function ApplyNative(verbose)
    if applying or not NativeAddIgnore then return end

    local pending = {}
    for name, v in pairs(db.ignored) do
        if not charDB.applied[name] then
            pending[#pending + 1] = { name = name, time = v.time or 0 }
        end
    end
    -- newest offenders first, since the room is limited
    table.sort(pending, function(a, b) return a.time > b.time end)

    local room = MAX_NATIVE - (NativeNumIgnores() or 0)
    local count = math.min(#pending, math.max(room, 0))

    if verbose or count > 0 then
        Print("adding %d of %d pending players to the Blizzard ignore list (%d slots free).",
            count, #pending, math.max(room, 0))
    end
    if count == 0 then return end

    applying = true
    for i = 1, count do
        -- spaced out so the server doesn't throttle the requests
        C_Timer.After(i, function()
            local name = pending[i].name
            if db.ignored[name] then
                local short = Ambiguate(name, "none")
                if not NativeIsIgnored(short) then
                    NativeAddIgnore(short)
                end
                charDB.applied[name] = true
            end
            if i == count then applying = false end
        end)
    end
end

---------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------
-- Newer clients moved this into ChatFrameUtil; fall back to the old global.
local AddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter

-- Public chat only. Party, raid, instance, guild, whispers and communities
-- are deliberately NOT filtered.
local events = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_CHANNEL",   -- General, Trade, LookingForGroup, etc.
    "CHAT_MSG_EMOTE",     -- custom /e emotes, which are visible to nearby players
}
for _, e in ipairs(events) do
    AddFilter(e, ChatFilter)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitDB()
        ImportVerdicts()
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(10, function() ApplyNative(false) end)
    end
end)

---------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------
local function CountKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local commands = {}

function commands.status()
    Print("logging %s, %d log entries awaiting review, %d players ignored.",
        db.logging and "ON" or "OFF", #db.log, CountKeys(db.ignored))
end

function commands.debug()
    ns.debug = not ns.debug
    Print("debug %s", ns.debug and "ON" or "OFF")
end

function commands.log(arg)
    if arg == "on" or arg == "off" then
        db.logging = arg == "on"
    end
    Print("logging %s", db.logging and "ON" or "OFF")
end

function commands.apply()
    ApplyNative(true)
end

function commands.ignore(arg)
    if arg == "" then return Print("usage: /ragebuster ignore Name-Realm") end
    local name = FullName(arg)
    local evidence = {}
    for _, e in ipairs(db.log) do
        if e.author == name then
            evidence[#evidence + 1] = { time = e.time, channel = e.channel, word = e.word, msg = e.msg, context = e.context }
        end
    end
    db.ignored[name] = { time = time(), reason = "added by hand", evidence = evidence }
    db.pardoned[name] = nil
    Print("ignoring %s.", name)
    ApplyNative(false)
end

function commands.unignore(arg)
    if arg == "" then return Print("usage: /ragebuster unignore Name-Realm") end
    local name = FullName(arg)
    if not db.ignored[name] then return Print("%s is not on the list.", name) end
    local record = db.ignored[name]
    record.releasedAt = time()
    db.released[name] = record
    db.ignored[name] = nil
    db.pardoned[name] = time()
    if charDB.applied[name] then
        charDB.applied[name] = nil
        local del = (C_FriendList and C_FriendList.DelIgnore) or DelIgnore
        if del then del(Ambiguate(name, "none")) end
    end
    Print("%s removed. Other characters keep their Blizzard ignore until you remove it there.", name)
end

function commands.why(arg)
    if arg == "" then return Print("usage: /ragebuster why Name-Realm") end
    local name = FullName(arg)
    local v = db.ignored[name] or db.released[name]
    if not v then return Print("no record for %s.", name) end
    Print("%s%s, %s: %s", name, v.releasedAt and " (unignored)" or "",
        date("%Y-%m-%d", v.time or 0), v.reason or "no reason recorded")
    local evidence = v.evidence or {}
    if #evidence == 0 and v.msg then evidence = { { msg = v.msg } } end
    for _, e in ipairs(evidence) do
        print(string.format("  %s [%s] %s", e.time and date("%m-%d %H:%M", e.time) or "?", e.channel or "?", e.msg or ""))
    end
end

function commands.clearlog()
    db.log = {}
    Print("log cleared.")
end

function commands.help()
    Print("commands:")
    print("  /ragebuster status - log and ignore counts")
    print("  /ragebuster log on|off - record blocked messages for review")
    print("  /ragebuster apply - add pending players to the Blizzard ignore list")
    print("  /ragebuster ignore Name-Realm / unignore Name-Realm")
    print("  /ragebuster why Name-Realm - the messages that got a player ignored")
    print("  /ragebuster clearlog - discard unreviewed log entries")
    print("  /ragebuster debug - print each blocked message")
end

SLASH_RAGEBUSTER1 = "/ragebuster"
SLASH_RAGEBUSTER2 = "/rbust"
SlashCmdList["RAGEBUSTER"] = function(input)
    local cmd, arg = input:match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd:lower()] or commands.help
    fn(arg)
end
