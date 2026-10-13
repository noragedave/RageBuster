local _, ns = ...

---------------------------------------------------------------------
-- Options panel (Esc > Options > AddOns > RageBuster, or /rbust options):
-- switch word categories on and off, and keep a list of your own words.
-- Settings live in RageBusterDB (customWords, disabledCategories); see
-- InitDB in RageBuster.lua.
---------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name = "RageBuster"
panel:Hide()

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, "RageBuster")
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)   -- the first call can open the wrong page
    end
end

local ROW = 26
local built, content, checks, customTop, input, feedback
local catBlock, catHeight   -- the categories, which sit below your words
local customRows = {}   -- rows in use, in list order: { frame, text, button }

local function FitButton(b)
    local fs = b.GetFontString and b:GetFontString()
    b:SetWidth(((fs and fs:GetStringWidth()) or 30) + 18)
end

local function SmallButton(parent, label)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(20)
    if b.SetNormalFontObject then
        b:SetNormalFontObject("GameFontNormalSmall")
        b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetDisabledFontObject("GameFontDisableSmall")
    end
    b:SetText(label)
    FitButton(b)
    return b
end

local function Header(text, y)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 0, -y)
    fs:SetText(text)
    return fs
end

-- the list of your own words, each with a Remove button, under the input box
local function RefreshCustom()
    local words = ns.customWords
    for i, word in ipairs(words) do
        local row = customRows[i]
        if not row then
            local frame = CreateFrame("Frame", nil, content)
            frame:SetSize(360, ROW)
            local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            text:SetPoint("LEFT", 4, 0)
            text:SetJustifyH("LEFT")
            local button = SmallButton(frame, "Remove")
            button:SetPoint("LEFT", frame, "LEFT", 260, 0)
            row = { frame = frame, text = text, button = button }
            button:SetScript("OnClick", function()
                for j, w in ipairs(ns.customWords) do
                    if w == row.word then
                        table.remove(ns.customWords, j)
                        break
                    end
                end
                ns.RebuildWords()
                RefreshCustom()
            end)
            customRows[i] = row
        end
        row.word = word
        row.text:SetText(word)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", 0, -(customTop + (i - 1) * ROW))
        row.frame:Show()
    end
    for i = #words + 1, #customRows do customRows[i].frame:Hide() end
    local listEnd = customTop + #words * ROW + 16
    catBlock:ClearAllPoints()
    catBlock:SetPoint("TOPLEFT", 0, -listEnd)
    content:SetHeight(listEnd + catHeight + 16)
end

local function AddWord()
    local word = ns.CleanWord(input:GetText())
    if #word < 2 then
        feedback:SetText("Enter a word or phrase of at least 2 letters.")
        return
    end
    for _, w in ipairs(ns.customWords) do
        if w == word then
            feedback:SetText(string.format("\"%s\" is already on your list.", word))
            return
        end
    end
    table.insert(ns.customWords, word)
    ns.RebuildWords()
    input:SetText("")
    feedback:SetText(string.format("Added \"%s\".", word))
    RefreshCustom()
end

local function Build()
    built = true
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RageBuster")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -48)
    scroll:SetPoint("BOTTOMRIGHT", -32, 16)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(math.max(scroll:GetWidth() or 0, 400), 1)
    scroll:SetScrollChild(content)

    -- your own words first, so they're in view without scrolling
    local y = 0
    Header("Your words", y)
    y = y + 22
    input = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    input:SetSize(220, 20)
    input:SetPoint("TOPLEFT", 6, -y)   -- the template's left edge art sits outside the box
    input:SetAutoFocus(false)
    input:SetMaxLetters(40)
    input:SetScript("OnEnterPressed", AddWord)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local add = SmallButton(content, "Add")
    add:SetPoint("LEFT", input, "RIGHT", 8, 0)
    add:SetScript("OnClick", AddWord)
    feedback = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    feedback:SetPoint("LEFT", add, "RIGHT", 10, 0)
    y = y + 28

    -- the categories go below your words; RefreshCustom moves them down as
    -- the list grows
    catBlock = CreateFrame("Frame", nil, content)
    catBlock:SetSize(400, 1)
    local catHeader = catBlock:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    catHeader:SetPoint("TOPLEFT", 0, 0)
    catHeader:SetText("Word categories")
    checks = {}
    for i, cat in ipairs(ns.wordCategories) do
        local cb = CreateFrame("CheckButton", nil, catBlock, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", 0, -(20 + (i - 1) * ROW))
        local label = catBlock:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(string.format("%s |cff999999(%d)|r", cat.name, #cat.words))
        cb:SetScript("OnClick", function(self)
            ns.disabledCategories[cat.key] = (not self:GetChecked()) or nil
            ns.RebuildWords()
        end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(cat.name)
            GameTooltip:AddLine(table.concat(cat.words, ", "), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        checks[cat.key] = cb
    end
    catHeight = 20 + #ns.wordCategories * ROW
    customTop = y
end

panel:SetScript("OnShow", function()
    if not ns.customWords then return end   -- saved settings not loaded yet
    if not built then Build() end
    for key, cb in pairs(checks) do
        cb:SetChecked(not ns.disabledCategories[key])
    end
    feedback:SetText("")
    RefreshCustom()
end)
