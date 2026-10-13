local addonName, ns = ...

-- Two kinds of build come from this file:
--   * Published releases: the word filter, the RageBuster player list
--     (PlayerList.lua) and each user's own blocks. Nothing is logged.
--   * Test builds (the author's own): all of that, plus logging chat for
--     review, importing verdicts, and the debug window.
-- Everything only test builds need sits between "alpha" markers. The packager
-- comments those blocks out of tagged, published releases, so the code isn't
-- there to run.
ns.debug = false   -- toggle in game with: /ragebuster debug (test builds only)

local PREFIX = "|cffff8800[RageBuster]|r "
local MAX_LOG = 1000        -- oldest entries are dropped past this
local CONTEXT_LINES = 25    -- lines before each hit, kept for the reviewer
local AFTER_LINES = 15      -- replies after each hit, so the reviewer sees the reaction
local AFTER_SECONDS = 300   -- stop waiting for replies after this long
local PLAYER_LINES = 20     -- the author's own recent messages kept with each hit
local PLAYER_FORGET = 1800  -- forget players silent this long, once many are tracked
local PLAYER_MAX = 500
local MAX_NATIVE = 50       -- Blizzard's per-character ignore list cap

local db, charDB

---------------------------------------------------------------------
-- Output: our own chat tab if there is one (/rbust window), else main chat
---------------------------------------------------------------------
local WINDOW_NAME = "RageBuster"

local function FindWindow()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local name, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
        -- a closed tab keeps its name, so also require it to be shown or docked
        if name == WINDOW_NAME and (shown or docked) and _G["ChatFrame" .. i] then
            return _G["ChatFrame" .. i]
        end
    end
end

local function Out(text)
    local frame = FindWindow()
    if frame then
        frame:AddMessage(text)
    else
        print(text)
    end
end

local function Print(...)
    Out(PREFIX .. string.format(...))
end
ns.Print = Print

-- Opens a "RageBuster" chat tab that shows only this add-on's output.
local function OpenWindow()
    local frame = FindWindow()
    if not frame and FCF_OpenNewWindow then
        FCF_OpenNewWindow(WINDOW_NAME)
        frame = FindWindow()
    end
    if not frame then
        return print(PREFIX .. "couldn't open a chat tab (the client allows 10). Close one and try again.")
    end
    -- keep regular chat out of it, so it holds only RageBuster lines
    if ChatFrame_RemoveAllMessageGroups then ChatFrame_RemoveAllMessageGroups(frame) end
    if ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(frame) end
    Print("this tab now shows RageBuster's output. Close it to send output back to the main chat.")
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
    db.ignored = db.ignored or {}     -- ["Name-Realm"] = { time, reason, ... }: your own blocks
    db.unhidden = db.unhidden or {}   -- ["Name-Realm"] = true: on the RageBuster list, but shown for you
    --@alpha@
    db.logging = db.logging ~= false
    db.seq = db.seq or 0
    db.log = db.log or {}
    --@end-alpha@
    db.pardoned = db.pardoned or {}   -- ["Name-Realm"] = time the player was unignored
    db.released = db.released or {}   -- ignore records kept after an unignore, for review
    db.customWords = db.customWords or {}                 -- words you added in the options panel
    db.disabledCategories = db.disabledCategories or {}   -- ["key"] = true: categories you switched off
    ns.customWords, ns.disabledCategories = db.customWords, db.disabledCategories
    ns.RebuildWords()

    RageBusterCharDB = RageBusterCharDB or {}
    charDB = RageBusterCharDB
    charDB.applied = charDB.applied or {}   -- names this character has native-ignored
end

--@alpha@
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
-- Whether a line is a joke or bait often shows only in the conversation around
-- it, so each hit keeps the lines before it and the replies that came after.
local recent = {}      -- [channel key] = last CONTEXT_LINES lines, "Author: text"
local following = {}   -- [channel key] = log entries still collecting replies
-- Each player's own recent public messages, caught or not, across channels, so
-- the reviewer can tell a one-off line from a pattern.
local spoken, spokenCount = {}, 0   -- [name] = { seen = time, lines = { "[Trade] text", ... } }

local function RememberPlayer(name, channel, text)
    local p = spoken[name]
    if not p then
        if spokenCount >= PLAYER_MAX then
            local cutoff = time() - PLAYER_FORGET
            for n, q in pairs(spoken) do
                if q.seen < cutoff then spoken[n] = nil; spokenCount = spokenCount - 1 end
            end
            if spokenCount >= PLAYER_MAX then spoken, spokenCount = {}, 0 end
        end
        p = { lines = {} }
        spoken[name] = p
        spokenCount = spokenCount + 1
    end
    p.seen = time()
    p.lines[#p.lines + 1] = "[" .. channel .. "] " .. text
    if #p.lines > PLAYER_LINES then table.remove(p.lines, 1) end
end

-- One line of conversation as the reviewer sees it. Your own lines read "(me)"
-- so your character names don't end up in the uploaded log.
local function Line(name, text)
    -- full Name-Realm, so the review can tell same-named players on different realms apart
    local speaker = (name == MyName()) and "(me)" or name
    return speaker .. ": " .. text
end

-- Adds this line to every earlier hit in the channel that is still waiting
-- for replies; a hit stops collecting after AFTER_LINES lines or AFTER_SECONDS.
local function AddReply(key, line)
    local waiting = following[key]
    if not waiting then return end
    local now, still = time(), {}
    for _, entry in ipairs(waiting) do
        if now - entry.time <= AFTER_SECONDS then
            entry.after[#entry.after + 1] = line
            if #entry.after < AFTER_LINES then still[#still + 1] = entry end
        end
    end
    following[key] = (#still > 0) and still or nil
end

local function NewId()
    db.seq = db.seq + 1
    -- time + random keeps ids unique across accounts sharing one Verdicts.lua
    return string.format("%x-%x-%x", time(), db.seq, math.random(0, 0xffff))
end

local function LogHit(event, name, text, word, channel, guid, key)
    local context = {}
    for i, line in ipairs(recent[key] or {}) do context[i] = line end
    local earlier = {}   -- this player's own messages before this one
    for i, line in ipairs(spoken[name] and spoken[name].lines or {}) do earlier[i] = line end

    local entry = {
        id = NewId(),
        time = time(),
        author = name,
        guid = guid,
        channel = channel,
        word = word,
        msg = text,
        context = context,
        after = {},   -- filled in by AddReply as the conversation goes on
        recent = earlier,
        by = MyName(),
    }
    local log = db.log
    log[#log + 1] = entry
    while #log > MAX_LOG do table.remove(log, 1) end

    following[key] = following[key] or {}
    table.insert(following[key], entry)
end

local function Remember(key, line)
    local lines = recent[key]
    if not lines then
        lines = {}
        recent[key] = lines
    end
    lines[#lines + 1] = line
    if #lines > CONTEXT_LINES then table.remove(lines, 1) end
end

-- Everything the review needs from one line of public chat.
local function Record(event, name, msg, hit, ...)
    local _, channelString, _, _, _, channelIndex, _, _, lineID, guid = ...
    local key = event .. (channelIndex or "")
    local text = ns.PlainText(msg)
    local line = Line(name, text)
    local channel = (channelString and channelString ~= "") and channelString or event:gsub("^CHAT_MSG_", "")

    -- every line, caught or not, is a possible reply to an earlier hit
    AddReply(key, line)

    if hit then
        if ns.debug and ns.DebugShow then
            ns.DebugShow(name, channel, text, hit, lineID)
        end
        if db.logging and name ~= MyName() then
            if issecretvalue and guid and issecretvalue(guid) then guid = nil end
            LogHit(event, name, text, hit, channel, guid, key)
        end
    end

    Remember(key, line)
    if name ~= MyName() then RememberPlayer(name, channel, text) end
end
--@end-alpha@

---------------------------------------------------------------------
-- The chat filter
---------------------------------------------------------------------
-- On the RageBuster list (PlayerList.lua), and not un-hidden by this user.
local function Listed(name)
    return ns.listedPlayers ~= nil and ns.listedPlayers[name] == true and not db.unhidden[name]
end

-- Temporary blocks from the debug window: kept in memory only, so they end at logout or /reload.
local tempIgnored = {}

local function Process(event, msg, author, ...)
    local name = FullName(author)

    if db.ignored[name] or tempIgnored[name] or Listed(name) then
        return true
    end

    local hit = ns.MatchBlocked(msg)
    --@alpha@
    Record(event, name, msg, hit, ...)
    --@end-alpha@
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
        --@alpha@
        ImportVerdicts()
        --@end-alpha@
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(10, function() ApplyNative(false) end)
        --@alpha@
        ns.ReopenDebug()   -- if it was open at logout or /reload
        --@end-alpha@
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
    local listed, shown = 0, 0
    for name in pairs(ns.listedPlayers or {}) do
        listed = listed + 1
        if db.unhidden[name] then shown = shown + 1 end
    end
    Print("%d players on the RageBuster list (%d shown again by you), %d on your own block list.",
        listed, shown, CountKeys(db.ignored))
    local on = 0
    for _, cat in ipairs(ns.wordCategories) do
        if not db.disabledCategories[cat.key] then on = on + 1 end
    end
    Print("%d of %d word categories on; your own words: %d.", on, #ns.wordCategories, #db.customWords)
    --@alpha@
    Print("logging %s, %d log entries awaiting review.", db.logging and "ON" or "OFF", #db.log)
    --@end-alpha@
end

--@alpha@
---------------------------------------------------------------------
-- Debug window (test builds only): every hidden message as it happens,
-- each with a Block button that ignores the player as your own decision,
-- and a Clear button that removes the row. Clearing only empties the window;
-- the review log is untouched. The window can be moved, and resized from its
-- bottom-right corner.
---------------------------------------------------------------------
local MAX_ROWS = 300    -- oldest rows are reused past this
local debugFrame, scroll, content
local rows = {}         -- oldest first: { frame, button, clear, text, author }
local spare = {}        -- cleared rows, kept to reuse

local function Bars(s)   -- "|" starts a WoW escape code, so double it in shown text
    return (tostring(s or ""):gsub("|", "||"))
end

local function FitButton(b)
    local fs = b.GetFontString and b:GetFontString()
    b:SetWidth(((fs and fs:GetStringWidth()) or 30) + 18)
end

local function SetBlocked(row)
    if db.ignored[row.author] then
        row.button:SetText("Blocked")
        row.button:Disable()
    else
        row.button:SetText("Block")
        row.button:Enable()
    end
    FitButton(row.button)
    if tempIgnored[row.author] then
        row.temp:SetText("Temp on")
        row.temp:Disable()
    elseif db.ignored[row.author] then
        row.temp:SetText("Temp")
        row.temp:Disable()
    else
        row.temp:SetText("Temp")
        row.temp:Enable()
    end
    FitButton(row.temp)
end

-- stacks the rows top to bottom; the message text wraps to the window's width
local function Layout()
    if not content then return end
    local width = math.max(scroll:GetWidth() or 0, 120)
    content:SetWidth(width)
    local y = 0
    for i, row in ipairs(rows) do
        if i % 2 == 0 then row.stripe:Show() else row.stripe:Hide() end
        -- the buttons sit on a line of their own at the right, the message wraps below them
        row.text:SetWidth(width - 6)
        local h = (row.text:GetStringHeight() or 0) + 32   -- buttons on top, message below
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row.frame:SetSize(width, h)
        y = y + h
    end
    content:SetHeight(math.max(y, 1))
end


-- Blocks a player until logout. Nothing is saved or recorded for review.
local function TempIgnore(name)
    if db.ignored[name] then return Print("%s is already ignored.", name) end
    tempIgnored[name] = true
    Print("temporarily ignoring %s until you log out.", name)
    for _, row in ipairs(rows) do
        if row.author == name then SetBlocked(row) end
    end
    Layout()
end

-- Clearing hides rows from the window only; db.log keeps every entry.
local function RemoveRow(row)
    for i, r in ipairs(rows) do
        if r == row then
            table.remove(rows, i)
            row.frame:Hide()
            spare[#spare + 1] = row
            break
        end
    end
    Layout()
end

local function ClearAll()
    for i = #rows, 1, -1 do
        rows[i].frame:Hide()
        spare[#spare + 1] = rows[i]
        rows[i] = nil
    end
    Layout()
end

local function ScrollToEnd()
    if scroll and scroll.GetVerticalScrollRange then
        scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
    end
end

-- Adding an entry is the standard way to define a popup; never reassign the table itself.
local confirmIgnore = {
    text = "Block %s?\n\nThey go on your ignore list, recorded as your own decision.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, name)
        commands.ignore(name)
        for _, row in ipairs(rows) do
            if row.author == name then SetBlocked(row) end
        end
        Layout()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
if StaticPopupDialogs then StaticPopupDialogs["RAGEBUSTER_CONFIRM_IGNORE"] = confirmIgnore end

local function AskIgnore(name)
    if db.ignored[name] then return Print("%s is already ignored.", name) end
    if StaticPopup_Show and StaticPopupDialogs then
        StaticPopup_Show("RAGEBUSTER_CONFIRM_IGNORE", name, nil, name)
    else
        Print("to ignore %s, type /rbust ignore %s", name, name)
    end
end

-- "Block (RageBuster)" in the menu you get by right-clicking a player's name
-- in chat. It asks first, like the window's Block button.
local function MenuName(name, server)
    if not name or name == "" then return nil end
    if server and server ~= "" and not name:find("-", 1, true) then
        name = name .. "-" .. server:gsub("[%s%-]", "")   -- realm names drop spaces, like "Area52"
    end
    return FullName(name)
end

if Menu and Menu.ModifyMenu then
    -- the menu system since 11.0 (and in clients that took it up since)
    Menu.ModifyMenu("MENU_UNIT_FRIEND", function(_, root, context)
        local name = context and MenuName(context.name, context.server)
        if not name or name == MyName() then return end
        root:CreateDivider()
        root:CreateButton("Block (RageBuster)", function() AskIgnore(name) end)
    end)
elseif hooksecurefunc and UnitPopup_ShowMenu and UIDropDownMenu_AddButton then
    -- older clients: add a line to the dropdown after Blizzard builds it
    hooksecurefunc("UnitPopup_ShowMenu", function(dropdown, which, _, name)
        if which ~= "FRIEND" or UIDROPDOWNMENU_MENU_LEVEL ~= 1 then return end
        local full = MenuName(name or (dropdown and dropdown.name), dropdown and dropdown.server)
        if not full or full == MyName() then return end
        UIDropDownMenu_AddButton({ text = "Block (RageBuster)", notCheckable = true,
                                   func = function() AskIgnore(full) end })
    end)
end

-- Clients differ in which frame templates they have, so try the modern ones first.
local function CreateWithTemplate(kind, name, parent, templates)
    for _, template in ipairs(templates) do
        local ok, frame = pcall(CreateFrame, kind, name, parent, template)
        if ok and frame then return frame, template end
    end
    return CreateFrame(kind, name, parent), nil
end

-- The window's place and size, saved account-wide whenever you move or resize it.
local function SaveWindow(f)
    if f.SetUserPlaced then f:SetUserPlaced(false) end   -- we keep the position, not WoW's layout cache
    local point, _, relativePoint, x, y = f:GetPoint(1)
    db.debugWindow = { point = point, relativePoint = relativePoint, x = x, y = y,
                       width = f:GetWidth(), height = f:GetHeight() }
end

local function PlaceWindow(f)
    local w = db.debugWindow
    f:ClearAllPoints()
    if w and w.point then
        f:SetSize(w.width or 620, w.height or 340)
        f:SetPoint(w.point, UIParent, w.relativePoint or w.point, w.x or 0, w.y or 0)
    else
        f:SetSize(620, 340)
        f:SetPoint("CENTER")
    end
end

local function DebugFrame()
    if debugFrame then return debugFrame end
    local f, template = CreateWithTemplate("Frame", "RageBusterDebugFrame", UIParent,
        { "DefaultPanelFlatTemplate", "PortraitFrameFlatTemplate", "BasicFrameTemplateWithInset" })
    -- The same dark, slightly see-through background as the Game Menu and other
    -- Blizzard dialogs, in place of the template's own.
    for _, key in ipairs({ "Bg", "InsetBg" }) do
        if f[key] and f[key].Hide then f[key]:Hide() end
    end
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "REPEAT", "REPEAT")
    if bg.SetHorizTile then
        bg:SetHorizTile(true)
        bg:SetVertTile(true)
    end
    if not f.CloseButton then
        local close = CreateWithTemplate("Button", nil, f, { "UIPanelCloseButtonDefaultAnchors", "UIPanelCloseButton" })
        close:SetPoint("TOPRIGHT", 0, 0)
    end
    PlaceWindow(f)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveWindow(self) end)
    local title = "RageBuster"
    if f.SetTitle then
        f:SetTitle(title)
    elseif f.TitleContainer and f.TitleContainer.TitleText then
        f.TitleContainer.TitleText:SetText(title)
    elseif f.TitleText then
        f.TitleText:SetText(title)
    end
    -- closing the window (X or /rbust debug) turns debug off, and says so.
    -- OnHide also fires when only a parent hides, as UIParent does during a
    -- loading screen; the window is still "shown" then and comes back after.
    f:SetScript("OnHide", function(self)
        if ns.debug and not self:IsShown() then
            ns.debug = false
            db.debugOpen = false
            Print("debug OFF")
        end
    end)

    -- resizing: a grip in the bottom-right corner, like a chat window
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(320, 160)
    elseif f.SetMinResize then
        f:SetMinResize(320, 160)
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); SaveWindow(f); Layout() end)
    f:SetScript("OnSizeChanged", function() Layout() end)

    local clearAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearAll:SetHeight(20)
    clearAll:SetPoint("BOTTOMLEFT", 12, 6)
    if clearAll.SetNormalFontObject then
        clearAll:SetNormalFontObject("GameFontNormalSmall")
        clearAll:SetHighlightFontObject("GameFontHighlightSmall")
    end
    clearAll:SetText("Clear all")
    FitButton(clearAll)
    clearAll:SetScript("OnClick", ClearAll)

    -- the modern thin scroll bar if this client has it, else the classic one
    local s, scrollTemplate = CreateWithTemplate("ScrollFrame", nil, f, { "ScrollFrameTemplate", "UIPanelScrollFrameTemplate" })
    if not scrollTemplate then
        s:EnableMouseWheel(true)
        s:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange() or 0
            self:SetVerticalScroll(math.min(math.max((self:GetVerticalScroll() or 0) - delta * 40, 0), range))
        end)
    end
    s:SetPoint("TOPLEFT", 12, -30)
    s:SetPoint("BOTTOMRIGHT", -30, 30)   -- room for the scroll bar, Clear all and the resize grip
    content = CreateFrame("Frame", nil, s)
    content:SetSize(1, 1)
    s:SetScrollChild(content)
    scroll = s

    f:Hide()
    debugFrame = f
    return f
end

-- Opens Blizzard's own report dialog for a chat line. The line ID is only good while the
-- game still holds that message, so older rows may fail; the player gets told rather than an error.
local function ReportChat(name, lineID)
    if not lineID then return Print("no chat line to report for %s.", name) end
    local ok, opened = pcall(function()
        if not (PlayerLocation and PlayerLocation.CreateFromChatLineID) then return false end
        local location = PlayerLocation:CreateFromChatLineID(lineID)
        if not location then return false end
        if ReportFrame and ReportFrame.InitiateReport and ReportInfo and Enum and Enum.ReportType then
            -- the dialog since 9.2.5 / 10.x
            local info = ReportInfo:CreateReportInfoFromType(Enum.ReportType.Chat)
            ReportFrame:InitiateReport(info, name, location)
            return true
        end
        if C_ReportSystem and C_ReportSystem.OpenReportPlayerDialog and PLAYER_REPORT_TYPE_LANGUAGE then
            C_ReportSystem.OpenReportPlayerDialog(PLAYER_REPORT_TYPE_LANGUAGE, name, location)
            return true
        end
        return false
    end)
    if not (ok and opened) then
        Print("couldn't open the report dialog for %s; right-click their name in chat to report instead.", name)
    end
end

local function AddRow(name, line, lineID)
    DebugFrame()
    local row
    if #rows >= MAX_ROWS then
        row = table.remove(rows, 1)
    elseif #spare > 0 then
        row = table.remove(spare)
    else
        local frame = CreateFrame("Frame", nil, content)
        local stripe = frame:CreateTexture(nil, "BACKGROUND")   -- faint stripe on every other row
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.04)
        local function SmallButton(label)
            local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            b:SetHeight(20)
            if b.SetNormalFontObject then
                b:SetNormalFontObject("GameFontNormalSmall")
                b:SetHighlightFontObject("GameFontHighlightSmall")
                b:SetDisabledFontObject("GameFontDisableSmall")
            end
            if label then b:SetText(label); FitButton(b) end
            return b
        end
        local button = SmallButton()
        button:SetPoint("TOPRIGHT", 0, -2)   -- Block sits at the right end of the row
        local temp = SmallButton("Temp")
        temp:SetPoint("TOPRIGHT", button, "TOPLEFT", -2, 0)
        local report = SmallButton("Report")
        report:SetPoint("TOPRIGHT", temp, "TOPLEFT", -2, 0)
        local clear = SmallButton("Clear")
        clear:SetPoint("TOPRIGHT", report, "TOPLEFT", -2, 0)
        local text = frame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        text:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -26)
        text:SetJustifyH("LEFT")
        if text.SetWordWrap then text:SetWordWrap(true) end
        row = { frame = frame, button = button, temp = temp, report = report, clear = clear, text = text, stripe = stripe }
        button:SetScript("OnClick", function() AskIgnore(row.author) end)
        temp:SetScript("OnClick", function() TempIgnore(row.author) end)
        report:SetScript("OnClick", function() ReportChat(row.author, row.lineID) end)
        clear:SetScript("OnClick", function() RemoveRow(row) end)
    end
    row.author = name
    row.lineID = lineID
    if lineID and not (issecretvalue and issecretvalue(lineID)) then row.report:Enable() else row.report:Disable() end
    row.text:SetText(line)
    SetBlocked(row)
    row.frame:Show()
    rows[#rows + 1] = row
    Layout()
    -- the scroll range only updates after the new size is applied
    if C_Timer and C_Timer.After then C_Timer.After(0, ScrollToEnd) else ScrollToEnd() end
end

function ns.DebugShow(name, channel, text, word, lineID)
    AddRow(name, string.format("|cff999999%s|r [%s] |cffffd100%s|r: %s  |cff999999(%s)|r",
        date("%H:%M"), Bars(channel), Bars(name), Bars(text), Bars(word)), lineID)
end

function commands.debug()
    local f = DebugFrame()
    if f:IsShown() then
        f:Hide()   -- OnHide turns debug off and prints it
    else
        ns.debug = true
        db.debugOpen = true   -- reopens after /reload or logging back in
        f:Show()
        Layout()
        Print("debug ON")
    end
end

function ns.ReopenDebug()
    if db.debugOpen and not ns.debug then commands.debug() end
end
--@end-alpha@

--@alpha@
function commands.log(arg)
    if arg == "on" or arg == "off" then
        db.logging = arg == "on"
    end
    Print("logging %s", db.logging and "ON" or "OFF")
end
--@end-alpha@

function commands.apply()
    ApplyNative(true)
end

function commands.ignore(arg)
    if arg == "" then return Print("usage: /ragebuster ignore Name-Realm") end
    local name = FullName(arg)
    if ns.listedPlayers and ns.listedPlayers[name] and db.unhidden[name] then
        db.unhidden[name] = nil
        return Print("hiding %s again (they're on the RageBuster list).", name)
    end
    -- byHand: tools/sync.py records this as your own decision, for the history and the casebook
    local record = { time = time(), reason = "added by hand", byHand = true }
    --@alpha@
    record.evidence = {}
    for _, e in ipairs(db.log) do
        if e.author == name then
            record.evidence[#record.evidence + 1] = { time = e.time, channel = e.channel, word = e.word, msg = e.msg, context = e.context, after = e.after, recent = e.recent }
        end
    end
    --@end-alpha@
    db.ignored[name] = record
    db.pardoned[name] = nil
    Print("ignoring %s.", name)
    ApplyNative(false)
end

--@alpha@
function commands.tempignore(arg)
    if arg == "" then return Print("usage: /ragebuster tempignore Name-Realm") end
    TempIgnore(FullName(arg))
end
--@end-alpha@

function commands.unignore(arg)
    if arg == "" then return Print("usage: /ragebuster unignore Name-Realm") end
    local name = FullName(arg)
    if tempIgnored[name] then
        tempIgnored[name] = nil
        Print("%s is no longer temporarily ignored.", name)
        if not db.ignored[name] then return end
    end
    if not db.ignored[name] then
        if ns.listedPlayers and ns.listedPlayers[name] then
            -- only for this user; the list itself is unchanged
            db.unhidden[name] = true
            return Print("%s is on the RageBuster list; showing their chat for you. /rbust ignore %s hides it again.", name, name)
        end
        return Print("%s isn't on your block list or the RageBuster list.", name)
    end
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

commands.unhide = commands.unignore

--@alpha@
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
        Out(string.format("  %s [%s] %s", e.time and date("%m-%d %H:%M", e.time) or "?", e.channel or "?", e.msg or ""))
    end
end
--@end-alpha@

function commands.window()
    OpenWindow()
end

--@alpha@
function commands.clearlog()
    db.log = {}
    Print("log cleared.")
end
--@end-alpha@

function commands.help()
    Print("commands:")
    Out("  /ragebuster status - how many players are hidden, and why")
    Out("  /ragebuster ignore Name-Realm - hide a player (your own block list)")
    Out("  /ragebuster unignore Name-Realm - show them again, including players on the RageBuster list")
    Out("  /ragebuster apply - add your own blocks to the Blizzard ignore list")
    Out("  /ragebuster options - choose word categories and add your own words")
    --@alpha@
    Out("  /ragebuster log on|off - record blocked messages for review (test builds only)")
    Out("  /ragebuster why Name-Realm - the messages that got a player ignored (test builds only)")
    Out("  /ragebuster tempignore Name-Realm - hide a player until you log out (test builds only)")
    Out("  /ragebuster clearlog - discard unreviewed log entries (test builds only)")
    Out("  /ragebuster debug - open or close the window of hidden messages, with Block buttons (test builds only)")
    --@end-alpha@
    Out("  /ragebuster window - give RageBuster its own chat tab")
end

function commands.options()
    if ns.OpenOptions then ns.OpenOptions() end
end
commands.config = commands.options

SLASH_RAGEBUSTER1 = "/ragebuster"
SLASH_RAGEBUSTER2 = "/rbust"
SlashCmdList["RAGEBUSTER"] = function(input)
    local cmd, arg = input:match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd:lower()] or commands.help
    fn(arg)
end
