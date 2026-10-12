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

ns.blockedWords = {
    ---------------------------------------------------------------------
    -- ORIGINAL LIST
    ---------------------------------------------------------------------
    "trump", "maga", "maha", "rfk", "great again",
    "degen", "degenerate", "new world order", "nwo",
    "olympus", "epstein", "aoc",
    "biden", "obama", "hillary", "vance", "brandon", "lets go brandon",
    "goon", "gooner", "gooning", "simp", "simping", "simped",
    "blm", "black lives matter", "black life matter",
    "antifa", "liberal", "conservative", "lib", "libtard",
    "incel", "soyboy", "soy boy",
    "feminist", "feminism",
    "pedophile", "pedo", "pedophilia", "paedo", "paedophile",
    "woke",                 -- safePhrases below let "I woke up" through
    "cringe", "cringey", "cringy",

    ---------------------------------------------------------------------
    -- US politicians, pundits, personalities
    ---------------------------------------------------------------------
    "kamala", "kamala harris", "walz", "pelosi", "schumer", "mcconnell",
    "desantis", "newsom", "bernie sanders", "ocasio cortez", "hegseth",
    "fauci", "soros", "elon", "elon musk", "mamdani", "charlie kirk",
    "tucker carlson", "alex jones", "infowars", "ben shapiro",
    "jordan peterson", "joe rogan", "andrew tate", "top g",
    "diddy", "diddler", "ghislaine maxwell",
    "fox news", "cnn", "msnbc", "breitbart", "daily wire",

    -- Nicknames / insults aimed at figures
    "sleepy joe", "orange man", "drumpf", "dotard", "fjb",
    "trumper", "trumptard", "trumpist", "magat", "deplorable",

    ---------------------------------------------------------------------
    -- International figures / nationality bait
    ---------------------------------------------------------------------
    "putin", "zelensky", "netanyahu", "trudeau", "farage", "brexit",
    "xi jinping",
    "usa", "america", "american", "murica", "merica", "amerifat",
    "europoor", "russia", "russian", "ukraine", "ukrainian",
    "china", "chinese",

    ---------------------------------------------------------------------
    -- Generic politics
    ---------------------------------------------------------------------
    "politics", "political", "politician", "election", "vote", "voting",
    "president", "congress", "senate", "supreme court", "government",
    "propaganda", "fake news", "msm", "mainstream media",
    "misinformation", "disinformation",
    "tax the rich", "eat the rich", "billionaire", "capitalism", "capitalist",
    "welfare", "universal healthcare", "minimum wage",

    ---------------------------------------------------------------------
    -- Parties and ideologies
    ---------------------------------------------------------------------
    "democrat", "dems", "republican", "gop", "rino", "dnc", "rnc",
    "leftist", "left wing", "right wing", "far left", "far right", "alt right",
    "fascist", "fascism", "nazi", "neo nazi", "hitler", "heil", "sieg heil",
    "kkk", "swastika", "third reich", "1488",
    "communist", "communism", "commie", "socialist", "socialism",
    "marxist", "marxism", "tankie", "neocon", "globalist",
    "snowflake", "sheeple", "cuck", "cuckservative", "chud",
    "bootlicker", "bootlicking",
    "conservatard", "repugnican", "demoncrat",

    ---------------------------------------------------------------------
    -- Culture-war bait vocabulary
    ---------------------------------------------------------------------
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

    -- Gender / sexuality / identity flashpoints
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

    -- Ethnicity flashpoints
    -- (Religion words were taken off this list on request.)
    "black people", "white people", "blacks", "whites", "asians",
    "mexicans", "immigrant", "immigration", "refugee", "migrant",

    ---------------------------------------------------------------------
    -- Slurs
    ---------------------------------------------------------------------
    "nigger", "nigga", "faggot", "fag", "kike", "spic", "chink", "gook",
    "wetback", "coon", "towelhead", "raghead", "dyke", "shemale",
    "retard", "retarded", "tard", "autist", "autistic",

    ---------------------------------------------------------------------
    -- Harassment / sexual / taunt bait
    ---------------------------------------------------------------------
    "kys", "kill yourself", "neck yourself", "rape", "raped", "rapist",
    "molester", "child molester", "child predator", "nonce",
    "loli", "lolicon", "shota",
    "porn", "hentai", "onlyfans", "thot", "femboy", "furry", "furries",
    "virgin", "neckbeard", "basement dweller", "fat ass", "fatass",
    "uninstall", "delete the game", "git gud", "skill issue",
    "touch grass", "cry about it", "stay mad", "cope", "seethe",
    "dilate", "triggered", "ur mom", "yo mama", "rigged",

    ---------------------------------------------------------------------
    -- Hot-button issues
    ---------------------------------------------------------------------
    "abortion", "pro life", "prolife", "pro choice", "prochoice",
    "roe v wade", "baby killer", "my body my choice",
    "gun control", "second amendment", "nra",
    "mass shooting", "school shooting", "sandy hook",
    "open borders", "illegals", "illegal alien", "illegal immigrant",
    "deportation", "build the wall", "ice raid",

    ---------------------------------------------------------------------
    -- Conspiracy / election / grift
    ---------------------------------------------------------------------
    "qanon", "q anon", "pizzagate", "deep state", "chemtrail",
    "flat earth", "flat earther", "illuminati", "reptilian", "lizard people",
    "false flag", "crisis actor", "psyop", "great reset",
    "world economic forum", "wef", "bilderberg",
    "stop the steal", "stolen election", "rigged election", "election fraud",
    "january 6", "jan 6", "j6", "insurrection",
    "client list", "adrenochrome", "child trafficking", "truther",
    "plandemic", "scamdemic", "antivax", "anti vax", "antivaxxer",
    "vaccine mandate", "mask mandate", "holohoax",

    ---------------------------------------------------------------------
    -- Geopolitics / war / terrorism
    ---------------------------------------------------------------------
    "gaza", "palestine", "palestinian", "free palestine",
    "israel", "israeli", "hamas", "hezbollah", "zionist", "zionism",
    "intifada", "genocide",
    "islamophobia", "antisemite", "antisemitic", "antisemitism",
    "holocaust", "sharia",
    "terrorist", "terrorism", "isis", "jihad", "taliban", "al qaeda",
    "bin laden", "ww3", "world war 3", "world war three",

    ---------------------------------------------------------------------
    -- WoW / Blizzard-specific drama
    ---------------------------------------------------------------------
    "cosby suite", "afrasiabi", "kotick", "blitzchung",
    "free hong kong", "boycott blizzard",
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