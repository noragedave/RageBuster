local _, ns = ...

-- Criterion for inclusion: "Can a rage baiter use this word to spark rage?"
-- Collateral damage is accepted: this filter only hides messages from YOUR
-- chat window, it never stops anyone else from talking.
--
-- Hiding a word is NOT a judgment about the person who typed it. Whether a
-- player goes on the ignore list is a separate, much stricter decision made
-- by the review (tools/review.py and POLICY.md), from the full conversation.
--
-- How entries are matched (see Match.lua):
--   * case-insensitive, WHOLE WORD only ("trump" does not match "trumpet")
--   * a trailing "s" is tolerated ("democrats" matches "democrat")
--   * entries with spaces are matched as phrases
--   * punctuation and apostrophes are ignored, so write "lets go brandon"
--     and "ocasio cortez", not "let's go brandon" / "ocasio-cortez"
--   * "t r u m p", "t.r.u.m.p" and "tr4mp" style evasions are caught too
--
-- Every word goes under the heading for its type. Add a new heading when
-- nothing fits rather than parking a word somewhere it doesn't belong. The
-- headings are the categories users can switch on and off.

-- Each category can be switched off in the options panel (Esc > Options >
-- AddOns > RageBuster); its key is what that setting saves, so don't rename keys.
ns.wordCategories = {
    { key = "us_figures", name = "US politicians, pundits, personalities", words = {
        "trump", "biden", "obama", "hillary", "vance", "aoc",
        "kamala", "kamala harris", "walz", "pelosi", "schumer", "mcconnell",
        "desantis", "newsom", "bernie sanders", "ocasio cortez", "hegseth",
        "fauci", "soros", "elon", "elon musk", "mamdani", "charlie kirk",
        "tucker carlson", "alex jones", "infowars", "ben shapiro",
        "jordan peterson", "joe rogan", "andrew tate", "top g",
        "diddy", "diddler", "ghislaine maxwell",
        "fox news", "cnn", "msnbc", "breitbart", "daily wire",
    } },
    { key = "nicknames", name = "Nicknames / insults aimed at figures", words = {
        "brandon", "lets go brandon",
        "sleepy joe", "orange man", "drumpf", "dotard", "fjb",
        "trumper", "trumptard", "trumpist", "magat", "deplorable",
    } },
    { key = "international", name = "International figures / nationality bait", words = {
        "putin", "zelensky", "netanyahu", "trudeau", "farage", "brexit",
        "xi jinping",
        "murica", "merica", "amerifat",
        "europoor", "russia", "russian",
    } },
    { key = "politics", name = "Generic politics", words = {
        "politics", "political", "politician", "election", "vote", "voting",
        "president", "congress", "senate", "supreme court", "government",
        "propaganda", "fake news", "msm", "mainstream media",
        "misinformation", "disinformation",
        "tax the rich", "eat the rich", "billionaire", "capitalism", "capitalist",
        "welfare", "universal healthcare", "minimum wage",
    } },
    { key = "ideologies", name = "Parties and ideologies", words = {
        "maga", "maha", "great again", "antifa",
        "liberal", "conservative", "lib", "libtard",
        "democrat", "dems", "republican", "gop", "rino", "dnc", "rnc",
        "leftist", "left wing", "right wing", "far left", "far right", "alt right",
        "fascist", "fascism", "nazi", "neo nazi", "hitler", "heil", "sieg heil",
        "kkk", "swastika", "third reich", "1488",
        "communist", "communism", "commie", "socialist", "socialism",
        "marxist", "marxism", "tankie", "neocon", "globalist",
        "snowflake", "sheeple", "cuck", "cuckservative", "chud",
        "bootlicker", "bootlicking",
        "conservatard", "repugnican", "demoncrat",
    } },
    { key = "culture_war", name = "Culture-war bait vocabulary", words = {
        "woke",                 -- safePhrases below let "I woke up" through
        "blm", "black lives matter", "black life matter",
        "feminist", "feminism", "incel", "soyboy", "soy boy",
        "groomer", "grooming", "tranny", "troon", "transphobe", "transphobic",
        "homophobe", "homophobic", "terf",
        "sjw", "social justice warrior", "gamergate", "feminazi",
        "toxic masculinity", "patriarchy", "mansplain", "mansplaining",
        "racist", "racism", "sexist", "sexism", "misogyny", "misogynist",
        "misandry", "misandrist", "bigot", "bigotry", "oppression",
        "privilege", "privileged", "white privilege", "white supremacy",
        "white supremacist", "white power", "white genocide",
        "great replacement", "race war", "reverse racism", "slavery",
        "dei", "diversity", "inclusivity", "equity", "diversity hire",
        "forced diversity", "critical race theory", "reparations",
        "systemic racism", "cancel culture",
        "wokeness", "woketard", "woke mind virus", "go woke go broke",
        "attack helicopter", "apache helicopter", "drag queen",
        "gender ideology", "gay agenda", "trans agenda",
        "red pill", "redpilled", "black pill", "blackpilled",
        "mgtow", "manosphere", "femoid", "foid", "hypergamy", "femcel",
        "alpha male", "beta male", "sigma male",
    } },
    { key = "gender", name = "Gender / sexuality / identity flashpoints", words = {
        "trans", "transgender", "nonbinary", "enby", "cis", "cisgender",
        "lgbt", "lgbtq", "lgbtqia", "queer", "gay", "gays", "lesbian",
        "homo", "homosexual", "homosexuality", "bisexual", "straight pride",
        "pride month", "pride flag", "pronouns", "they them", "he him",
        "gender", "genders", "sexuality",
        "biological male", "biological female", "biological men",
        "biological women", "biological sex", "two genders",
        "females", "gamer girl", "gamer girls", "girl gamer", "girl gamers",
        "egirl", "e girl", "women cant", "girls cant",
        "get back in the kitchen", "male gaze",
    } },
    { key = "ethnicity", name = "Ethnicity flashpoints", words = {
        -- (Religion words were taken off this list on request.)
        "black people", "white people", "blacks", "whites", "asians",
        "mexicans", "immigrant", "immigration", "refugee", "migrant",
    } },
    { key = "slurs", name = "Slurs", words = {
        "nigger", "nigga", "faggot", "fag", "kike", "spic", "chink", "gook",
        "wetback", "coon", "towelhead", "raghead", "dyke", "shemale",
        "retard", "retarded", "tard", "autist", "autistic",
    } },
    { key = "harassment", name = "Harassment / sexual / taunt bait", words = {
        "kys", "kill yourself", "neck yourself", "rape", "raped", "rapist",
        "pedophile", "pedo", "pedophilia", "paedo", "paedophile",
        "molester", "child molester", "child predator", "nonce",
        "loli", "lolicon", "shota",
        "porn", "anal", "hentai", "onlyfans", "thot", "femboy", "furry", "furries",
        "virgin", "neckbeard", "basement dweller", "fat ass", "fatass",
        "uninstall", "delete the game", "git gud", "skill issue",
        "touch grass", "cry about it", "stay mad", "cope", "seethe",
        "dilate", "triggered", "ur mom", "yo mama", "rigged",
        "degen", "degenerate", "goon", "gooner", "gooning",
        "simp", "simping", "simped",
    } },
    { key = "hot_button", name = "Hot-button issues", words = {
        "abortion", "pro life", "prolife", "pro choice", "prochoice",
        "roe v wade", "baby killer", "my body my choice",
        "gun control", "second amendment", "nra",
        "mass shooting", "school shooting", "sandy hook",
        "open borders", "illegals", "illegal alien", "illegal immigrant",
        "deportation", "build the wall", "ice raid",
    } },
    { key = "conspiracy", name = "Conspiracy / election / grift", words = {
        "epstein", "olympus", "new world order", "nwo",
        "qanon", "q anon", "pizzagate", "deep state", "chemtrail",
        "flat earth", "flat earther", "illuminati", "reptilian", "lizard people",
        "false flag", "crisis actor", "psyop", "great reset",
        "world economic forum", "wef", "bilderberg",
        "stop the steal", "stolen election", "rigged election", "election fraud",
        "january 6", "jan 6", "j6", "insurrection",
        "client list", "adrenochrome", "child trafficking", "truther",
        "plandemic", "scamdemic", "antivax", "anti vax", "antivaxxer",
        "vaccine mandate", "mask mandate", "holohoax",
    } },
    { key = "geopolitics", name = "Geopolitics / war / terrorism", words = {
        "gaza", "palestine", "palestinian", "free palestine",
        "israel", "israeli", "hamas", "hezbollah", "zionist", "zionism",
        "intifada", "genocide",
        "islamophobia", "antisemite", "antisemitic", "antisemitism",
        "holocaust", "sharia",
        "terrorist", "terrorism", "isis", "jihad", "taliban", "al qaeda",
        "bin laden", "ww3", "world war 3", "world war three",
    } },
    { key = "wow_drama", name = "WoW / Blizzard-specific drama", words = {
        "cosby suite", "afrasiabi", "kotick", "blitzchung",
        "free hong kong", "boycott blizzard",
    } },
    { key = "drugs", name = "Drugs / vaping", words = {
        "vape", "vaping", "vaper",
    } },
}

-- Phrases that contain a blocked word but are harmless. They are removed
-- from the text before matching. Mainly exists for "woke" ("I woke up").
-- Set this to {} if you want "woke" blocked in every context.
ns.safePhrases = {
    "woke up", "woke me", "woke him", "woke her", "woke us", "woke them",
    "woke the", "woke to", "woke from", "woke in",
    "i woke", "we woke", "you woke", "he woke", "she woke", "they woke",
    "who woke", "just woke",
}