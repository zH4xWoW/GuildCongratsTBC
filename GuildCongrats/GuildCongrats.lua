-- GuildCongrats: TBC-Compatible Version
-- Burning Crusade (2.5.5) Compatible

GuildCongrats = GuildCongrats or {}
local GC = GuildCongrats
--------------------------------------------------------
-- BOOT / DIAGNOSTIC BEACON (TBC)
--------------------------------------------------------
do
    -- If you don't see this, the file is not loading at all.
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[GuildCongrats]|r Booting GuildCongrats.lua...")

    -- Catch and print errors that happen during init
    local _oldErrorHandler = geterrorhandler()
    seterrorhandler(function(err)
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[GuildCongrats ERROR]|r " .. tostring(err))
        if _oldErrorHandler then
            _oldErrorHandler(err)
        end
    end)

    -- Minimal slash beacon (proves file executed)
    SLASH_GCBOOT1 = "/gcboot"
    SlashCmdList["GCBOOT"] = function()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[GuildCongrats]|r /gcboot works. File loaded and slash registry is alive.")
    end
end

-- Saved vars
GCongratsDB = GCongratsDB or {}
-- Keep the older internal name as an alias of the actual TOC SavedVariables table.
-- This preserves existing GuildCongrats code while making levels/settings persist under GCongratsDB.
GuildCongratsDB = GCongratsDB

GCongratsDB.mode = GCongratsDB.mode or 1 -- 1 = Flavor, 2 = Flavor + Tip, 3 = Flavor + Roast

GC.guildCache = GC.guildCache or {}

--------------------------------------------------------
-- Leader election / addon comms
--------------------------------------------------------

local ADDON_PREFIX = "GCONGRATS"
local seenCandidates = {}   -- name -> true

GC.isLeader   = GC.isLeader   or false
GC.leaderName = GC.leaderName or nil
GC.hasLeader  = GC.hasLeader  or false

--------------------------------------------------------
-- DB helpers and print
--------------------------------------------------------

local function GC_EnsureDB()
    if type(GuildCongratsDB) ~= "table" then
        GuildCongratsDB = {}
    end
    if type(GuildCongratsDB.levels) ~= "table" then
        GuildCongratsDB.levels = {}
    end
    if GuildCongratsDB.enabled == nil then
        GuildCongratsDB.enabled = true
    end
    if GuildCongratsDB.initialized == nil then
        GuildCongratsDB.initialized = false
    end
end

local function GC_Print(msg)
    print("|cff00ff00[|r|cff00aeffGuild|r|cFFDDDDDDCongrats|r|cff20a30fTBC|r|cff00ff00]|r " .. tostring(msg))
end

--------------------------------------------------------
-- Non-repeating selection helpers
--------------------------------------------------------

local lastUsed = {
    flavor = {},
    tip    = {},
    roast  = {},
    flirt  = {},
}

local function makeKey(...)
    return table.concat({...}, ":")
end

local function pickRandomNonRepeating(pool, bucket, key)
    if not pool or #pool == 0 then return nil end
    local count = #pool
    if count == 1 then
        bucket[key] = 1
        return pool[1]
    end

    local lastIdx = bucket[key]
    local idx = math.random(1, count)

    if lastIdx and count > 1 then
        local tries = 0
        while idx == lastIdx and tries < 20 do
            idx = math.random(1, count)
            tries = tries + 1
        end
    end

    bucket[key] = idx
    return pool[idx]
end

--------------------------------------------------------
-- Timer helper for TBC (since C_Timer doesn't exist)
--------------------------------------------------------

local function GC_CreateTimer(delay, callback)
    local timerFrame = CreateFrame("Frame")
    local elapsed = 0
    timerFrame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= delay then
            self:Hide()
            self:SetScript("OnUpdate", nil)
            callback()
        end
    end)
    timerFrame:Show()
end

--------------------------------------------------------
-- Data Tables: Flavor (race+class)
-- (Keeping your original data tables as they were)
--------------------------------------------------------

local flavorLines = {
["Dwarf"] = {
Hunter = {
"Time to pick your pet; sadly a keg of ale doesn't count as a beast.",
"Level %d and already out-leveling half the tavern. Go tame something with more hair than you.",
"Your rifle's loud, your beard's loud, your fashion sense… also loud. Perfect hunter material.",
"Somewhere a boar just felt a shiver and doesn't know why. It's you.",
"You've got the aim of a cannon and the legs of a barstool. Classic dwarven hunter energy.",
"Another level closer to being Hemet Nesingwary's drinking rival.",
"Your pet has more sense than you, but you have the explosives.",
"Ding! The sound of another perfect shot... and another broken gnome gadget.",
"You don't track prey, you just follow the trail of empty tankards.",
"Even the rarest beasts fear the scent of Thunderbrew Stout on your breath.",
},
Warrior = {
"Another level of armor, still the same tiny legs sprinting into danger.",
"Your axe is big, your hitbox is small. That's tactical dwarf technology.",
"More levels, more rage, same number of brain cells dedicated to charging first.",
"Every time you ding, a blacksmith hears a cash register sound.",
"Ale in the belly, steel in the hands, and zero regard for personal safety.",
"You've achieved a new level of stubbornness. Magni would be proud.",
"Ding! The sound of another two-handed weapon that's taller than you are.",
"Your shield is now officially classified as a movable wall.",
"You don't generate rage, you distill it from pure, aged spite.",
"Another level of 'tanking' and 'not understanding what 'running away' means.'",
},
Paladin = {
"The Light has blessed you... and also your extremely sturdy beard.",
"You judge with the force of a mountain and the height of a molehill.",
"Your hammer is holy, your resolve is iron, and your legs are still really short.",
"Ding! Another bubble ready to pop at the worst possible moment.",
"You protect your allies with a zeal usually reserved for protecting ale casks.",
"The Light finds your stubbornness 'endearing, but problematic.'",
"Another level of being a walking, talking, plate-covered fortress of faith.",
"Your Divine Storm now has 15% more spinning and 100% more dwarf.",
"You've been added to the Dark Iron's list of 'annoyingly righteous obstacles.'",
"The only thing harder than your armor is your head.",
},
Rogue = {
"Sneaky for a dwarf usually means 'quieter than a rockslide.'",
"Your stealth is less about shadows and more about people not looking down.",
"You pick pockets and locks with the delicate touch of a master miner.",
"Ding! The sound of a backstab delivered from knee-height.",
"You've mastered the art of being underestimated. The first mistake.",
"Even the deadliest poisons are served in a shot glass.",
"Your vanish is just you ducking behind a conveniently placed keg.",
"The Syndicate never saw you coming. Mostly because you're below eye level.",
"You bring a new meaning to 'low blow.'",
"Another level of subterfuge, perfected in the deep, dark mines.",
},
Priest = {
"You heal with the warmth of a hearthfire and the grumble of a mountain.",
"Your holy words have the comforting tone of a gravel landslide.",
"Even your Power Word: Shield has a beard.",
"Ding! The Light now answers your prayers with a faint Khaz Modan accent.",
"You mend bones as easily as you'd mend a broken pickaxe.",
"Your faith is as unshakable as the Stonewrought Dam.",
"Shadow Word: Pain sounds much more threatening in Dwarvish.",
"You're on a first-name basis with the Anvil, figuratively and literally.",
"Another level of keeping your allies alive so they can make more poor decisions.",
"Your renew spell smells faintly of peat smoke and nostalgia.",
},
Mage = {
"Your fireballs have the explosive power of a well-placed powder keg.",
"You don't just cast Frostbolt, you serve it chilled from the heart of Dun Morogh.",
"Arcane intellect? More like 'ale-enhanced stubbornness.'",
"Ding! Another spell in your tome, right between 'Brew' and 'More Brew.'",
"You teleport with a reliability that would make a gnomish engineer weep.",
"Your polymorph turns enemies into sheep... which you then mentally price for wool.",
"You've mastered the arcane, but you still light your pipe with a match.",
"The Kirin Tor finds your methods 'unorthodox, but strangely effective.'",
"Another level of burning your enemies and toasting your friends.",
"Your mana regenerates at the same pace as a good barrel ages.",
},
Warlock = {
"Your demon minion is just as grumpy as you are. A perfect match.",
"You harvest souls like you harvest iron ore: with grim efficiency.",
"Your fel magic has a distinct aftertaste of sulfur and Thunderbrew Ale.",
"Ding! Another curse, and another demon who owes you a favor.",
"Your Imp's insults are the only thing sharper than your axe.",
"You've made pacts with entities darker than the deepest mine.",
"Your healthstones are suspiciously crunchy and taste of lichen.",
"Even the Burning Legion respects your capacity for controlled destruction.",
"Another level of corrupting the land, one carefully-placed seed of ruin at a time.",
"Your Voidwalker is the only 'wall' you've ever trusted.",
},
},
["Human"] = {
Paladin = {
"More levels, more righteousness. The Light is starting to take your side in arguments.",
"You've unlocked 12% more smugness in plate armor.",
"Another level closer to judging everyone and being technically correct.",
"Your hammer gets heavier and your patience for heresy gets shorter.",
"Somewhere, a demon just felt a mild sense of inconvenience.",
"You fight with the moral certainty of someone who's never been to Ratchet.",
"Ding! The sound of a Crusader who hasn't yet become Scarlet.",
"Your Devotion Aura is just your natural sense of superiority given form.",
"You've leveled up. Your cape now billows 30% more dramatically in slow motion.",
"Stormwind's taxpayers are funding your holy war, and they'd better be grateful.",
},
Priest = {
"Another level of healing, another reason your group can stand in the fire.",
"Your holy words hurt feelings and heal hit points. Efficient.",
"You're now certified to fix both flesh wounds and bad decisions.",
"The Light approves. Your mana bar, less so.",
"You heal, they pull extra. Circle of life… and repair bills.",
"Your Power Word: Shield is a metaphor for emotional walls. Also a real shield.",
"Ding! You've achieved a new tier of passive-aggressive renew ticks.",
"You mend the body while silently judging the life choices that broke it.",
"The Shadow whispers of power. You tell it to wait until after vespers.",
"Another level of keeping the tank alive despite their best efforts to die.",
},
Warrior = {
"Another angry human with a big sword. Azeroth's most reliable export.",
"Your rage is as refined as Stormwind's sewer system.",
"You charge first, ask questions later, and usually die in the middle.",
"Ding! Your shoulder pads just grew three sizes.",
"You're not tanking damage, you're just collecting it as a hobby.",
"Victory Rush tastes like triumph and the blood of Murlocs.",
"Your tactical awareness begins and ends with 'hit it until it stops moving.'",
"Another level of being the reason Priests drink.",
"You've mastered the art of turning every battle into a conga line of pain.",
"Your mortal strike is only slightly less devastating than your student loan.",
},
Rogue = {
"You skulk in the shadows of a kingdom built on literal, shining hope.",
"Your stealth is funded by a surprisingly robust pickpocketing pension.",
"You've unlocked the ability to vanish from both combat and social obligations.",
"Ding! Another subtlety talent, used exclusively for unsubtle ganks.",
"You're on SI:7's watchlist as 'promising, but needs to work on teamwork.'",
"Your poison kit is more organized than the Stormwind library.",
"You see a patrol. You don't see a patrol. Depends on who's asking.",
"Another level of finding creative uses for a dagger besides cutting cheese.",
"You make gold the old-fashioned way: you steal it from Defias.",
"Your sense of honor is as flexible as your blade.",
},
Mage = {
"You bend reality to your will, mostly to create portals to the auction house.",
"Your fireball is the solution to 90% of Azeroth's problems. The other 10% require Frost Nova.",
"The Kirin Tor sees your potential and your overdue library fines.",
"Ding! Another spell mastered, another gnome's invention exploded for comparison.",
"You've learned to conjure refreshments, but they still taste like defeat.",
"Your intellect is arcane, your patience for melee classes is not.",
"Polymorph: turning major threats into minor inconveniences since the First War.",
"Another level of blaming lag for every time you get caught in a cleave.",
"You teleport with the confidence of someone who's never ended up in a wall.",
"Your mana gem is just a socially acceptable form of magical caffeine.",
},
Warlock = {
"You dabble in fel magic in a city that literally has a Cathedral of Light.",
"Your demon minion is the only entity in Stormwind that returns your calls.",
"You harvest souls to power your spells and also your minor grudges.",
"Ding! Another step down a dark path that's surprisingly well-lit with green fire.",
"Your fear spell is just you projecting your own social anxieties.",
"The Summoning Stone is for amateurs. You have a personal teleportation service.",
"Your healthstone business has a better profit margin than the trade district.",
"Another level of corruption, perfectly balanced with a sensible haircut.",
"Your Voidwalker is a better bodyguard than most of the city guard.",
"You've read the fine print on every demonic pact. It's all about clauses.",
},
},
["Night Elf"] = {
Hunter = {
"Graceful ears, deadly arrows, and an animal best friend. You're basically a nature influencer now.",
"Silent steps, loud crits. Very on-brand.",
"Another level of night-time aesthetic and daytime DPS.",
"You and your pet just unlocked a new tier of synchronized murder ballet.",
"Somewhere a Furbolg just added you to their list of anxieties.",
"Your aim is true, your hair is flawless, and your pet matches your armor set.",
"Ding! The sound of an arrow finding a new home in a Satyr's backside.",
"You don't track, you simply become one with the prey's impending demise.",
"Even your traps are aesthetically pleasing and ecologically sound.",
"Another level of being Teldrassil's ghost... too soon?",
},
Druid = {
"More levels, more forms, fewer reasons to ever wear pants again.",
"You're one ding closer to becoming a full-time bear rug with opinions.",
"Trees love you, animals trust you, pug groups fear you.",
"You heal, you claw, you moonfire things that look at you funny. Versatile!",
"The Emerald Dream left you on read, but at least the XP bar notices you.",
"You shapeshift so often you've forgotten what your original knees look like.",
"Ding! Another point to spend on being slightly better at everything.",
"Your travel form is 80% majestic stag, 20% desperate sprint to the instance.",
"You don't cast Entangling Roots, you just ask the plants nicely to help.",
"Another level of tranquil fury, waiting to be unleashed as a chicken.",
},
Warrior = {
"You fight with the grace of a Sentinel and the rage of a corrupted Ancient.",
"Your war cries sound like a melancholy poem about shattered moonlight.",
"You charge into battle with the elegance of a falling tree. A very angry tree.",
"Ding! Your elusiveness stat just went down, but your armor went way up.",
"You protect the wilds by ensuring nothing in them is alive to threaten it.",
"Your weapon is an extension of your arm, which is an extension of your grudge.",
"Another level of being surprisingly sturdy for someone who sleeps in a tree.",
"You've mastered the art of looking contemplative while covered in gore.",
"Your victory is a silent, solemn affair, punctuated by loot sounds.",
"You are the reason 'kaldorei' translates to 'children of the stars and also murder.'",
},
Priest = {
"You heal with the gentle light of Elune... and also stab with her shadows.",
"Your faith is as deep and mysterious as the forests of Ashenvale.",
"You've learned to embrace the shadow without losing your spot in the moonlight.",
"Ding! Another prayer answered, probably involving the suffering of Horde.",
"Your Power Word: Shield shimmers with the silver light of the moonwell.",
"You mend the wounds of the world, one stubborn Tauren at a time.",
"Another level of being dangerously serene in the middle of a raid wipe.",
"Your Starshard looks pretty, right up until it melts someone's face.",
"You are the calm center of the storm, and also the lightning that started it.",
"Elune's gaze is upon you, and it's a little judgmental about your gear score.",
},
Rogue = {
"You move through shadows so deep, even the Worgen get jealous.",
"Your stealth is so good, you once snuck up on a sound.",
"Dagger in the dark, vengeance in the heart. Standard night elf evening.",
"Ding! Another subtlety talent for your not-at-all-subtle vendettas.",
"You pick pockets with the silent grace of a falling leaf. A stabby leaf.",
"The Wardens haven't caught you yet, but they've definitely sensed a disturbance.",
"Another level of holding a grudge with lethal precision.",
"Your ambush is the last thing many Horde see. They die confused and aesthetically offended.",
"You vanish not into thin air, but into the profound, ancient darkness of the woods.",
"Even your poisons are derived from rare, blooming nightflowers. Fatal beauty.",
},
Druid = { -- Balance
"You're one with the cosmos, and the cosmos is telling you to throw more moonfire.",
"Your wrath is as inevitable as the tide, and twice as messy.",
"You've traded tree-hugging for star-chucking. An upgrade, really.",
"Ding! Your eclipse bar just got more confusing for everyone, including you.",
"You are a walking celestial event with a hitbox.",
"The chickens of Azeroth look up to you as their glorious, feathered overlord.",
"Another level of explaining to groups that 'Balance' doesn't mean you'll heal.",
"Your Starfall is a beautiful way to accidentally pull three extra packs.",
"You draw power from sun and moon, and all you ask is a safe casting distance.",
"The Titans themselves nod in approval at your orbital bombardment.",
},
},
["Blood Elf"] = {
Paladin = {
"Another level of pretty and judgmental. Truly a dangerous combo.",
"You swing a hammer like it's performance art.",
"The Light didn't choose you; you kidnapped it and made it a fashion accessory.",
"Every ding polishes your armor just a little bit more.",
"You radiate holy energy and main character syndrome.",
"Your Crusader Strike has a 50% chance to crit and a 100% chance to look fabulous.",
"Ding! The Blood Knights have updated your file: 'Promising, still vain.'",
"You purify the land of scourge and also of poorly coordinated color schemes.",
"Your bubble hearth is the most dramatic exit in all of Azeroth.",
"Another level of using holy power to achieve flawless skin.",
},
Hunter = {
"Your arrows are sharp, but your cheekbones are still the deadliest weapon.",
"You and your pet both look like you were styled by the same dramatic tailor.",
"Every crit is followed by a hair flip. As it should be.",
"You hunt, you strut, and mobs die confused and attracted.",
"Even your quiver looks expensive.",
"Your pet is a loyal extension of your own impeccable aesthetic.",
"Ding! Another perfectly fletched arrow for a perfectly executed kill shot.",
"You don't just track prey, you make sure the lighting is good for the kill.",
"Beast Mastery is less about commanding animals and more about leading a photoshoot.",
"Another level of making survival look utterly effortless and glamorous.",
},
Mage = {
"You weave magic with the precision of a master jeweler and the drama of a poet.",
"Your fireballs are less 'explosive ordnance' and more 'artisanal conflagration.'",
"The Sunwell's energy flows through you, mostly to power your hair highlights.",
"Ding! Another spell mastered, another gnomish rival's wand snapped in envy.",
"You teleport with a flash of light that's been professionally color-graded.",
"Your frost magic doesn't just slow enemies, it gives them a chic, icy sheen.",
"Arcane intellect? Darling, you invented intellect.",
"Another level of solving problems with elegantly destructive beams of energy.",
"Your mana shield shimmers with the tragic beauty of a fallen dynasty.",
"You make the Kirin Tor look like a bunch of poorly dressed librarians.",
},
Rogue = {
"You move through shadows with the grace of a dancer and the malice of a critic.",
"Your daggers are polished to a mirror shine, the better to check your reflection mid-fight.",
"Subtlety isn't just a spec, it's a lifestyle of silent, gorgeous menace.",
"Ding! Another vial of poison that smells faintly of expensive cologne.",
"You pick pockets not for the gold, but for the thrill of being unnoticed.",
"Your vanish is so complete, even your drama leaves no trace.",
"Another level of holding a grudge with impeccable posture.",
"You don't backstab, you deliver a tragically beautiful coup de grâce.",
"The Undercity's shadows are too grungy for you. You prefer Silvermoon's ambiance.",
"Your poisons are as complex and refined as a fine Quel'Thalas wine.",
},
Priest = {
"Your holy magic is a refined, cultured version of the human's brutish Light.",
"You heal with the serene detachment of someone who's seen civilizations fall.",
"The Shadow calls to you, and it sounds like a melancholic aria.",
"Ding! Another hymn of hope that subtly implies you're better than everyone.",
"Your Power Word: Shield is a bubble of pure, disdainful energy.",
"You mend flesh with a sigh, as if the very act of being wounded is gauche.",
"Another level of being divinely powerful and utterly bored by it.",
"Your mind control is simply convincing others your ideas were theirs all along.",
"You are a symphony of light and shadow, and everyone else is off-key.",
"Your renew spell doesn't just heal, it provides a temporary, blissful vanity.",
},
Warlock = {
"You channel fel energy with the practiced ease of a sommelier decanting a rare vintage.",
"Your demon is less a minion and more a tragically bound accessory.",
"You've turned soul-shattering magic into a high art form.",
"Ding! Another soul fragment added to your collection. They make lovely decor.",
"Your curses are delivered with a sigh and a perfectly arched eyebrow.",
"The Burning Legion is a crude tool. You are a precise, beautiful instrument of ruin.",
"Another level of corruption that somehow improves your complexion.",
"Your healthstones are crystallized agony, served on a silver platter.",
"You summon infernals not for destruction, but for the dramatic entrance.",
"Your felguard doesn't just cleave enemies, it critiques their fighting form.",
},
},
["Draenei"] = {
Shaman = {
"Hooves, totems, and lightning. That's a very specific nightmare for your enemies.",
"Every time you ding, an elementals support group forms.",
"Those hooves were made for walking, but the totems were made for deleting health bars.",
"You channel the elements and somehow remain incredibly polite.",
"Your totems are now 23% more judgmental of bad positioning.",
"You ask the fire nicely to burn your foes, and it complies out of respect.",
"Ding! The sound of a perfectly balanced Elemental asking for more mana.",
"Your chain heal doesn't just mend wounds, it spreads a sense of quiet optimism.",
"You commune with the spirits of Azeroth, who find your accent 'charming but strange.'",
"Another level of being the calm, blue, hoofed center of the storm.",
},
Priest = {
"You heal, you shine, and your tail does most of the emoting.",
"Another level of holy power and confused pronunciation of your own city's name.",
"You brighten the room and also set it on psychic fire when needed.",
"Even your heals have an accent.",
"Your halo is getting heavier; that's all the responsibility.",
"The Light flows through you with the gentle power of a Naaru's lullaby.",
"Ding! Another prayer of the devoted, answered with geometric precision.",
"Your Power Word: Shield has a faint, celestial hum to it.",
"You mend the scars of the world, one polite 'be healed' at a time.",
"Another level of being the reason the party survives its own curiosity.",
},
Paladin = {
"The Light chose you because you were the only one who could pronounce 'Vindicaar' correctly.",
"Your hammer of justice is delivered with a serene smile and crushing force.",
"You are a beacon of hope, a bastion of faith, and your hooves are impeccably clean.",
"Ding! Your devotion aura now repels evil and also minor stains.",
"You fight with the righteous certainty of someone who's seen their homeworld explode.",
"Your bubble is less a shield and more a temporary zone of impeccable holy conduct.",
"Another level of making the Legion regret ever looking at your ship funny.",
"Your consecration purifies the very earth, which then thanks you politely.",
"You are the living embodiment of 'forgiving, but not forgetting.'",
"Your judgment is swift, fair, and accompanied by a subtle, holy glow.",
},
Hunter = {
"Your aim is as true as your people's navigation was... historically questionable.",
"You and your talbuk have a bond forged in the crystalline fields of Azuremyst.",
"Ding! Another arrow fletched with feathers from a careful, respectful plucking.",
"You hunt not for sport, but for the preservation of cosmic balance. And nice pelts.",
"Your pet doesn't just obey, it contemplates the existential meaning of the fight.",
"Even your traps are engineered with elegant, alien geometry.",
"Another level of providing ranged support with an air of dignified sorrow.",
"Your multi-shot is a symphony of perfectly parallel arrows.",
"You see the beauty in all of Azeroth's creatures, right before you crit them.",
"Your steadiness comes from centuries of standing perfectly still on spaceships.",
},
Warrior = {
"You charge into battle with the weight of a lost homeworld on your shoulders. It's great for momentum.",
"Your rage is a deep, mournful thing, channeled into very smashy results.",
"You tank hits that would level a city, and you do it with good posture.",
"Ding! Another piece of armor to polish until it reflects the stars you came from.",
"Your shield is a piece of the Exodar, and you're not letting anything else scratch it.",
"You fight with the precision of advanced technology and the fury of ancient loss.",
"Another level of being the immovable, blue object in a world of chaotic, green fel.",
"Your victory rush feels less like triumph and more like bittersweet remembrance.",
"You are the anvil upon which the Legion's hopes are crushed.",
"Your intimidating shout is just you politely asking the enemy to reconsider.",
},
Mage = {
"You weave arcane magic with the precision of a dimensional engineer.",
"Your frost nova is a localized, perfectly spherical winter.",
"The Arcane is a science to you, and everyone else is just guessing.",
"Ding! Another spell matrix calculated to five-dimensional accuracy.",
"Your portals don't just move you through space, they do it with zero turbulence.",
"You polymorph threats into harmless creatures, then study them politely.",
"Another level of applying crystal-based logic to the problem of 'things that need burn.'",
"Your intellect is as vast as the Great Dark Beyond, and just as cold.",
"You don't just cast Blizzard, you engineer a targeted precipitation event.",
"Your mana gem is a perfectly cut crystal of distilled potential.",
},
}
}

-- Generic flavor fallback (same as before)
local genericFlavorFallback = {
    "Ding! The sound of one more step towards being Khadgar's errand boy.",
    "Level up. Your new power is offset by a new, shinier shoulder pad model. Wouldn't you just kill for a Transmog right now?",
    "You grind XP with the relentless efficiency of an Argent Dawn quartermaster, who every that is...",
    "Another level closer to being the reason raid warnings exist.",
    "The Light... or maybe just obsessive grinding... has blessed you.",
    "You dinged so hard, Millhouse Manastorm felt a surge of unwarranted confidence.",
    "Your leveling pace would make a Scarlet Crusade zealot say 'Whoa, slow down.'",
    "New level unlocked: 'Can Now Be Ganked by Higher-Level Rogues.'",
    "Even Hemet Nesingwary would call your slaughter 'a bit much.'",
    "The Threads of Fate just snapped because you pulled too hard.",
    "You're gaining levels like a bank alt gains auction house cuts.",
    "Ding! The Lich King's patience for your insolence wanes by one more degree.",
    "Your XP bar filled faster than a Pandaren's lunchbox.",
    "Another ding, another few copper toward your inevitable 5,000g flying tax.",
    "You are now officially too powerful for Westfall. The Defias Brotherhood sends its regards.",
    "The Titans themselves look upon your progress and whisper: 'Meh, seen better.'",
    "You level with the chaotic energy of a zug-zugging Frostwolf.",
    "Your new power tier is 'Moderate Inconvenience to Elemental Lords.'",
    "Ding! The sound of a thousand Quillboar respawn timers crying out.",
    "At this rate, you'll be 60 before Onyxia takes a deep breath.",
    "You have ascended. Your mount's ground speed remains disappointingly the same.",
    "The Dragon Aspects note your progress in a ledger labeled 'Potential Future Problem.'",
    "Another level for the pile. Thrall's hopeful smile widens imperceptibly.",
    "Your relentless advancement is an affront to natural Azerothian nap schedules.",
    "Ding! Your weapon proficiency is now 'Competent Menace.'",
    "You farm mobs with the cold precision of a goblin shredder operator. Profit!",
    "New level achieved. The Barrens chat is now 0.4% more relevant to you.",
    "You are now strong enough to carry more junk. The vendor trash industry rejoices.",
    "Even A.F.K. players in Orgrimmar can sense your growing threat level.",
    "Your leveling is so efficient, it's giving Spreadsheet Lords a strange warmth.",
    "Ding! The Echo Isles tremble at your burgeoning potential, Vol'jin's ghost side-eyes you.",
    "You've graduated from 'Punching Bag' to 'Nuisance' in the Black Dragonflight's eyes. Onyxia sighs.",
    "Another step towards max level, and an equal step towards crippling raid consumable debt. Flask yourself.",
    "Your prowess now warrants a dismissive sniff from the Windrunner sisters. All three of them.",
    "You grind like a Dwarf digs: with unwavering focus, a hint of ale, and zero regard for Dark Iron property rights.",
    "Ding! The Forsaken apothecaries are now taking notes... on your surprisingly resilient liver.",
    "You are now officially a 'Regional Problem' on the Kirin Tor's watch list. Rhonin's ghost is filing the report.",
    "Your leveling speed breaks no laws of Azeroth, but definitely violates several of good taste and common decency.",
    "Another ding. The Maelstrom's chaos is now 1.7% more chaotic, and Neptulon blames you personally.",
    "You're collecting levels like a Collector collects socks: relentlessly, mysteriously, and with a faint odor of cheese.",
    "The Old Gods dream of your ascent... not as a champion, but as a particularly stubborn case of athlete's foot for Azeroth.",
    "Ding! Your reputation with 'Common Sense' has decreased to Hated. Your reputation with 'Leeroy Jenkins' is now Friendly.",
    "You have the persistence of a gnome and the subtlety of a kodo in a china shop. A potent, deeply alarming combo.",
    "New level unlocked: 'Can and Will Pull the Entire Cave, Then Blame the Healer.'",
    "Your power grows, mirroring the ever-increasing, physics-defying size of your character's pauldrons.",
    "Even the infinite dragonflight is getting tired of trying to mess with your timeline. It's just too boringly efficient.",
    "Ding! The sound of one more talent point about to be spent in a build that will make the class forums weep.",
    "You farm with the joyous, uncontainable abandon of a Fire Mage who just discovered the 'Living Bomb' spell in a thatched hut village.",
    "Another milestone. May your loot be epic, your disconnect rates be zero, and your world buffs never drop to a roguedispeller.",
    "The Scourge detects a new, vibrant life force to extinguish. The Lich King has added you to his 'To-Raise' list. Congrats.",
    "You're not just leveling; you're building an airtight case for Blizzard to issue a direct, personal nerf in the next patch.",
    "Ding! The Burning Crusade was less about demons and more about grinders like you. Illidan was just the final boss of your to-do list.",
    "Your journey impresses even the flight masters, who have seen it all... twice, and are still bored.",
    "Another level closer to becoming someone's embarrassing, story-of-the-week anecdote in a Blackrock Depths pug.",
    "You progress with the grim, unyielding determination of a Death Knight on a fetch quest for ten wolf pelts.",
    "The very ley lines of Azeroth hum with the energy of your misplaced zeal. Nozdormu has a headache because of you.",
    "Ding! Your achievements are now worthy of a two-line tooltip. Maybe three, if you count the flavor text no one reads.",
    "You're carving a path of glory that will one day be trivialized into a boring daily quest route for alts. Legacy!",
    "The Cenarion Circle observes your growth, concerned for the local flora, fauna, and general state of peaceful greenery.",
    "Another ding. The legacy of Legendaries weeps for the soulbound, green-quality garbage you just equipped with pride.",
    "You are now a 'Hero of Azeroth,' as officially defined by the minimum level requirements of a Stranglethorn Vale quest giver.",
    "Your relentless ascent is an inspiration to bank alts everywhere and a terror to the continent's rapidly depopulating boars.",
    "Ding! The sound of destiny... or just the sound of another 10 copper repair bill you'll ignore until your armor is red.",
    "Witnessed by the stunned silence of the thousands of beasts you've rendered locally extinct. The Timbermaw are furious.",
    "The Earthen Ring shudders as you disturb the delicate elemental peace of another zone. Thrall is getting a complaint form ready.",
    "Another level. May your crits be high, your aggro range be impossibly higher, and your threat drop abilities be firmly on cooldown.",
    "You train with the fervor of a pandaren who just found the last peach in the Vale of Eternal Blossoms. Pure, delicious focus.",
    "Ding! The Sha of Pride nods in distant, ambiguous approval. The Sha of Sloth wonders how you're not napping right now.",
    "Your name is now whispered in the halls of Ulduar... probably as a typo on a Titan maintenance log. 'Subject: Minor Anomaly.'",
    "You are now officially too dangerous for peaceful roleplay in Goldshire. The ERP community salutes your disruptive, bloody arrival.",
    "Another step towards being the primary reason the dungeon finder will one day need a deserter debuff. A pioneer.",
    "You harvest experience like the Lich King harvests souls: indiscriminately, in bulk, and with a chilling lack of remorse.",
    "Ding! The dragonscale is in the mail. Please allow 4-6 weeks for delivery. The black dragonflight postal service is unionized.",
    "The Prophet Velen has foreseen your arrival at the Dark Portal... and sighed a very long, 25,000-year-old sigh.",
    "Your growing might is a beacon of hope for your faction and a perfect, blinking beacon for every accidental patrol pull in Outland.",
    "Another level. The fabric of reality is fine, but the local wolf, bear, and spider populations are drafting a strongly worded petition.",
    "You achieve with the quiet dignity of a Rogue in a PvP zone. Which is to say, none whatsoever, and from behind.",
    "Ding! The echo is heard from Teldrassil to the Undercity. Mostly it's just complaints about 'another one grinding mobs near the inn.'",
    "You are the living embodiment of 'zug zug.' The Horde/Alliance is... cautiously optimistic? Deeply concerned? Let's go with 'noted.'",
    "Your legend grows, along with the size of the repair bill you're actively ignoring and the mountain of soulbound greys in your bags.",
    "Another ding. The naaru have composed a new, slightly judgmental hymn about your methods. It's in the key of 'A Minor Inconvenience.'",
    "You progress like a siege engine: slow, inevitable, terrible for architecture, and requiring a small army to keep you fueled.",
    "Ding! Magni Bronzebeard would say 'Magnificent!' if he wasn't currently made of diamond and deeply disappointed in your lack of mining.",
    "The Infinite Dragonflight is checking their watches. You're not just ahead of schedule, you're ruining their carefully plotted temporal mischief.",
    "You are now a 'Champion,' as stated by the lowest-bidding, most desperate quest-giver in the bug-infested hellscape of Silithus.",
    "Another level closer to being the person who confidently wipes the raid on the first trash pull because 'the guide said I could AoE this.'",
    "You farm with the cold, unfeeling, algorithmic efficiency of an auction house bot. We salute you, our new robotic overlord.",
    "Ding! The Legion's invasion plans just got moved up a notch. Sargeras felt a tremor in the Nether and assumes it's your DPS meter.",
    "Your journey is a testament to willpower, dangerous amounts of caffeine, and the heroic ignoring of your entire social tab.",
    "Another milestone. May your bags be deep, your greed rolls be justified with a 'need for off-spec,' and your ninja looting go unnoticed.",
    "You are now powerful enough to be a minor, misspelled footnote in a future expansion's lore book. Aspirations achieved!",
    "Ding! The sound of one more compelling reason to never, ever, under any circumstances, visit Stranglethorn Vale on a PvP server again.",
    "Your leveling soundtrack is the mournful cry of murlocs and the soft 'clink' of yeti hides hitting your bag. It's a symphony of progress.",
    "The Guardians of Tirisfal are arguing over whether your growing power is a natural anomaly or should be politely, magically corrected.",
    "You've gained a level, and the denizens of Deadwind Pass have gained a new, profound sense of existential dread. Correlation? Probably.",
}

-- Tips, tables 
local tipLines = {
    Hunter = {
        "Don't forget your pet's happiness; sad pets do sad DPS.",
        "Keep your weapon skill trained; a fancy bow is useless if you can't hit a kodo.",
        "Aspect swapping is free. Your mana bar will thank you later.",
        "Dead zone awareness saves lives, mostly yours.",
        "Traps are not just decoration; drop them like confetti before pulls.",
        -- NEW TIPS --
        "Feign Death resets mobs' threat and their 'on-damage' enrage timers. Use it tactically.",
        "Scare Beast is a full-duration CC on beasts. In dungeons like Wailing Caverns, it's a free win.",
        "Your pet's 'Growl' can be turned off. In a group with a real tank, do everyone a favor: turn it off.",
        "Aspect of the Cheetah/Pack's daze effect applies even indoors. Careful running ahead in dungeons.",
        "Mend Pet is a powerful heal over time. Cast it pre-emptively when your pet is about to take damage.",
        "Aimed Shot is a casted weapon attack; it resets your auto-shot timer. Use it right *after* an auto-shot fires.",
        "Use 'Eyes of the Beast' for scouting ahead in dangerous zones or to pull mobs from tricky positions.",
        "Serpent Sting costs mana and does low damage. In long fights, it's worth it. On trash, it's a waste.",
        "You can use 'Freezing Trap' and 'Frost Trap' simultaneously. Aoe slow + single-target CC = crowd control god.",
        "Track Humanoids/Beasts/Etc. It's not just for questing; it's for knowing what's about to jump you in PvP.",
    },
    Warrior = {
        "Keep your weapon skill maxed; missing is just angry cardio.",
        "Swap stances like you mean it; each one is a toolbox, not a prison.",
        "Carry a shield, even if you swear you're 'pure DPS, bro'.",
        "Demoralizing Shout is free mitigation. Use your outside voice.",
        "Hamstring kiting saves you from expensive repair bills.",
        -- NEW TIPS --
        "‘Mocking Blow’ and ‘Challenging Shout’ are your only real taunts. Know their cooldowns and ranges.",
        "You generate rage from taking damage. As a tank, let yourself get hit a few times *before* a big pull for initial rage.",
        "‘Sunder Armor’ is a stacking debuff that increases *all* physical damage. Five stacks is a raid DPS buff.",
        "In Battle Stance, ‘Overpower’ procs on dodges. Use it against rogues and druids for massive crits.",
        "‘Intercept’ stuns the target. Use it as an interrupt or to stop a caster in PvP.",
        "‘Whirlwind’ hits 4 targets. ‘Cleave’ hits 2. Use Whirlwind when you have 3+ mobs for better rage efficiency.",
        "As Fury, ‘Bloodthirst’ scales with Attack Power, not weapon damage. A fast one-hander is fine for the ability.",
        "‘Shield Block’ guarantees a block, which can proc ‘Revenge’. This is your core active mitigation loop.",
        "You can use ‘Berserker Rage’ to break and become immune to fear, sap, and incapacitate effects for 10 seconds.",
        "Charge generates rage. In dungeons, charge the farthest mob in a pack to group them up nicely for your team.",
    },
    Paladin = {
        "Blessings are like snacks: keep them refreshed and share with the group.",
        "Seal, judge, reseal. The loop is your friend.",
        "Carry multiple weapon types; you never know which epic will drop first.",
        "Cleanse is basically a full-time job in some fights. Bill by the debuff.",
        "Don't be afraid to bubble and hearth; we both know you were going to anyway.",
        -- NEW TIPS --
        "‘Judgement of Wisdom’ or ‘Light’ returns mana to the attacker. This includes your entire raid. Keep it up.",
        "‘Blessing of Salvation’ reduces threat by 30%. This is your main job in raids. Reapply it after every wipe.",
        "As a tank, ‘Holy Shield’ blocks 4 attacks and deals damage. It’s incredible threat and mitigation on fast-attacking bosses.",
        "‘Consecration’ is a massive mana drain. As Ret/Healer, avoid it. As Prot, it's your primary AOE threat tool.",
        "You can ‘Blessing of Protection’ a healer to make them immune to physical damage and drop threat. It also makes them unable to attack.",
        "‘Hammer of Justice’ is a 6-second stun (PvP talent reduces it). Use it to interrupt casts or chain-CC a target.",
        "‘Seal of Command’ (SoC) can proc on any attack, including from ‘Hand of Justice’ and other on-hit effects. Stacking proc chances is key.",
        "‘Aura Mastery’ doubles the effect of your current aura for the party. Combine with Fire/Frost/Shadow Resist auras for boss mechanics.",
        "‘Divine Shield’ (Bubble) removes ALL debuffs when used. It can clear poisons, diseases, curses, and magical effects. Use it as a cleanse.",
        "Retribution Paladins get +8% crit from talents. This makes them surprisingly good at using slow, hard-hitting two-handers.",
    },
    Priest = {
        "Downranking your heals saves mana and friendships.",
        "Keep an eye on your wand; it's your best friend between pulls.",
        "Power Word: Shield is great, but overhealing it is just expensive padding.",
        "Fade is not a suggestion; it's a survival instinct.",
        "Drink early, drink often. You're not made of mana.",
        -- NEW TIPS --
        "‘Power Word: Shield’ puts a debuff called ‘Weakened Soul’ on the target, preventing another shield for 15 seconds. Don't waste it.",
        "‘Inner Focus’ makes your next spell free and increases its critical strike chance by 25%. Perfect for a big ‘Prayer of Healing’.",
        "‘Dispel Magic’ works on friendly targets (buffs) and enemy targets (debuffs). In PvP, strip those blessings and magic buffs.",
        "‘Mind Control’ is a full CC that works on humanoids. Use it in Strat, Scholo, or to make an enemy player jump off a cliff.",
        "‘Shadow Word: Pain’ is instant and does full damage. Use it on runners or as you move. It's free damage.",
        "‘Psychic Scream’ fears up to 5 targets. It breaks on damage. Use it as an 'oh no' button, not as controlled CC.",
        "‘Vampiric Embrace’ heals your party for 15% of your shadow damage. In a dungeon as Shadow, it's significant off-healing.",
        "The ‘Spiritual Guidance’ talent adds Spirit to your Spell Damage/Healing. Stacking Spirit as Shadow/Disc is legitimately powerful.",
        "‘Starshards’ (Night Elf racial) is a channeled arcane DoT. It's a mana-free damage source while wanding for low-level priests.",
        "‘Levitate’ prevents fall damage. Cast it on your party before jumps in Blackrock Mountain or other zones.",
    },
    Warlock = {
        "Keep your DoTs rolling; lazy locks have sad meters.",
        "Life Tap early, not when everything is chewing on you.",
        "Soulstones save wipes; remember to place one before the pull, not after.",
        "Your pet has abilities too; teach it to do more than just stand there.",
        "Healthstones are free potions. Hand them out like cursed candy.",
        -- NEW TIPS --
        "‘Curse of Recklessness’ prevents fear effects. Use it on enemies that fear (like certain dungeon bosses) to make the fight trivial.",
        "‘Curse of Shadows’ and ‘Curse of the Elements’ increase magic damage taken. They are massive raid DPS buffs. Assign them.",
        "‘Death Coil’ is an instant fear, heal, and threat dump. It’s your ultimate ‘get off me’ button in PvE and PvP.",
        "‘Soul Link’ (Demonology) transfers 30% of damage you take to your pet. This makes you deceptively tanky, especially in PvP.",
        "You can use ‘Eye of Kilrogg’ to scout entire dungeons, check for patrols, or pull mobs from extreme range.",
        "‘Banish’ is a full CC on demons and elementals. In places like DM West or Molten Core, it’s essential.",
        "Your ‘Create Soulstone’ spell creates a usable item. You can store multiple soul shards' worth of them in your bags for later.",
        "‘Howl of Terror’ is an AoE fear. Unlike Psychic Scream, it has a cast time. Use it pre-emptively to control adds.",
        "‘Drain Soul’ does extra damage to low-health targets AND has a high chance to generate a soul shard if the target dies during the channel.",
        "The Imp's ‘Fire Shield’ (Firebolt off) gives your melee party members a damage buff. It's a small but free raid DPS increase.",
    },
    Mage = {
        "Conjure food, make friends. Conjure water, keep them.",
        "Sheep first, explain your targeting choices later.",
        "Downranked Frostbolt can be your best kiting tool.",
        "Blink is not just for fun, it's for escaping that mess you made.",
        "Don't forget to refresh your armor buffs; they're more than just fashion.",
        -- NEW TIPS --
        "‘Polymorph’ is a curse. Druids and Shamans can remove it with ‘Remove Curse’ and ‘Cure Poison/Disease’ respectively.",
        "‘Counterspell’ silences the school of magic interrupted for 10 seconds. Lock out a healer from Holy or a mage from Frost.",
        "‘Remove Lesser Curse’ dispels one curse from an ally. Use it on tanks with ‘Curse of Tongues’ or DPS with damage curses.",
        "‘Frost Nova’ roots enemies in place. It breaks on damage. Use it to create space, not as damage (unless you're Frost spec).",
        "The ‘Impact’ talent gives your Fire spells a 10% chance to stun. This makes ‘Fire Blast’ a potential interrupt/stun in PvP.",
        "‘Evocation’ regens mana based on your Spirit. Stacking some Spirit gear (like from dungeons) dramatically improves its efficiency.",
        "‘Slow Fall’ is not just for jumps. It completely negates knockback effects from boss abilities if cast before the hit.",
        "As Arcane, your ‘Presence of Mind’ allows an instant cast of any spell. Use it for an instant Polymorph or Pyroblast.",
        "‘Blizzard’ and ‘Flamestrike’ are channeled and instant-cast DoT fields respectively. They are your only real AoE options.",
        "‘Dampen Magic’ reduces magic damage taken AND healing received. ‘Amplify Magic’ does the opposite. Use Dampen on heavy magic damage fights.",
    },
    Shaman = {
        "Totem placement matters; don't buff the wall behind you.",
        "Windfury is a love language. Choose your targets wisely.",
        "Grounding Totem can eat spells your face would regret.",
        "Earthbind fixes many mistakes. Not all, but many.",
        "Keep your weapon enchants up; the elements like being invited.",
        -- NEW TIPS --
        "‘Earth Shock’ interrupts spellcasting. ‘Rank 1 Earth Shock’ costs very little mana and is perfect for interrupting heals in PvP.",
        "‘Purge’ strips one enemy buff per cast. It's essential against mages (Ice Armor), paladins (blessings), and priests (Power Word: Shield).",
        "‘Water Walking’ allows you and your party to walk on water. Cast it before crossing large bodies of water to avoid fatigue.",
        "‘Stoneclaw Totem’ has a tiny health pool but taunts nearby mobs. Use it as a mini-emergency tank to buy a few seconds.",
        "‘Chain Heal’ jumps to injured targets within range. It's incredibly mana-efficient for healing spread, sustained raid damage.",
        "Enhancement Shaman’s ‘Stormstrike’ debuff increases Nature damage taken by 20%. This buffs your own shocks and other shaman's damage.",
        "‘Ancestral Spirit’ is an out-of-combat resurrection. It saves a warlock's soul shard or a paladin's mana on corpse runs.",
        "The ‘Elemental Mastery’ talent gives your next Nature, Fire, or Frost spell a 100% crit chance. Combine it with a max-rank Chain Lightning.",
        "‘Frost Shock’ is an instant-cast snare. Use it to kite melee enemies or to prevent a flag carrier from escaping in PvP.",
        "Totems are magic effects and can be dispelled or destroyed by AoE. Place them strategically, not in obvious fire patches.",
    },
    Druid = {
        "Carry multiple sets: bear, cat, caster. You're your own raid pug.",
        "Innervate early, not when the healer is already crying.",
        "Faerie Fire on bosses is free value. Press the button.",
        "HoTs work best when cast before people panic-scream.",
        "Shift forms to break roots and snares when needed.",
        -- NEW TIPS --
        "‘Barkskin’ reduces damage taken by 20% and prevents spell pushback. Use it when tanking casters or during heavy AoE damage.",
        "‘Nature's Swiftness’ allows an instant-cast Healing Touch, Regrowth, or Entangling Roots. It's your ‘oh #$%&’ button.",
        "‘Faerie Fire (Feral)’ reduces armor and prevents stealth/invisibility. Use it to keep Rogues/Druids from vanishing and to buff physical DPS.",
        "In Cat form, ‘Prowl’ is a stealth with a movement speed penalty. ‘Dash’ or ‘Tiger's Fury’ can be used while prowling to close gaps.",
        "‘Rebirth’ (Battle Rez) uses a reagent (Seed). Always carry them. It can be cast in combat, saving a wipe or a key player.",
        "Bear form's ‘Enrage’ generates rage but reduces armor. Use it at the start of a pull for instant threat, not when actively taking heavy hits.",
        "‘Remove Curse’ and ‘Abolish Poison’ are your dispels. Abolish Poison is a HoT that tries to cleanse a poison every 2 seconds for 8 seconds.",
        "‘Hibernate’ is a CC that works on beasts and dragonkin. It's full duration and is broken by damage. Essential in places like UBRS.",
        "Travel Form is faster than a mount indoors and underwater. Use it in dungeons and caves to keep up with mounted players.",
        "‘Innervate’ restores mana based on the caster's Spirit (the Druid's). A Resto Druid with high Spirit is the best Innervate target.",
    },
    Rogue = {
        "Keep your poisons up; you're not just here for the leather transmog.",
        "Kick early, kick often; silence is golden.",
        "Positioning behind the boss is not optional, it's your religion.",
        "Vanish is both a threat drop and a drama tool.",
        "Slice and Dice is mandatory, not 'nice to have'.",
        -- NEW TIPS --
        "‘Kick’ interrupts spellcasting and locks that school of magic for 5 seconds. Time it to lock out a healer's Holy school.",
        "‘Gouge’ is an incapacitate that breaks on damage. Use it to reset a mob's auto-attack swing timer, giving your healer a break.",
        "‘Sap’ is a long-duration CC that only works out of combat and on humanoids, beasts, and demon. It's your primary dungeon CC tool.",
        "‘Evasion’ gives you a 50% dodge chance. Use it to tank a physical damage boss for a short time if your tank dies.",
        "‘Blind’ uses a reagent (Flash Powder) and is a full-duration CC on humanoids. It's your best non-sap CC in and out of combat.",
        "Combat Swords Rogues: ‘Blade Flurry’ doubles your attacks and hits one extra nearby target. It's your massive AoE cooldown.",
        "‘Preparation’ resets the cooldown on Evasion, Vanish, Sprint, and Blind. It effectively gives you two vanishes in a PvP fight.",
        "Your poisons are applied on a ‘Proc Per Minute’ (PPM) system. A faster weapon applies the same number of poisons, just more consistently.",
        "‘Expose Armor’ reduces a target's armor significantly. In raids without a Warrior tank (who uses Sunder), this is your job.",
        "‘Distract’ doesn't break stealth and can redirect patrols or turn enemies around for a clean Sap or pickpocket.",
    },
}

local roastLines = {
    ["Dwarf"] = {
        Hunter = {
            "Your beard has more survival instincts than you do.",
            "You tamed your bear because it was the only thing that couldn't outrun you.",
            "Your 'aspect of the cheetah' is just you rolling downhill.",
            "You track beasts by following the trail of empty ale bottles.",
            "Your pet's IQ is higher than your vertical clearance.",
            "You use Feign Death so often the healers have stopped checking.",
            "Your traps are just fancy beer bottle openers.",
            "You think 'kiting' means bringing alcohol to a picnic.",
            "Your racial stoneform is just you pretending not to hear raid instructions.",
            "The only thing you've mastered shot is whiskey.",
        },
        Warrior = {
            "You charge into battle because walking takes too long.",
            "Your defense strategy is 'more beard, less fear'.",
            "You think 'tanking' is what you do at the tavern.",
            "Your interrupt is just yelling 'OY!' three seconds too late.",
            "You've died so many times the spirit healer knows your clan name.",
            "Your shield is just a giant coaster for your ale.",
            "You use Heroic Leap to reach the top shelf.",
            "Your battle cry is just belching the alphabet.",
            "You think 'enrage' is when they run out of dark ale.",
            "The only thing you're protecting is your brewing recipe.",
        },
        Paladin = {
            "Your bubble is just fermented holy light.",
            "You think the Ashbringer is a bottle opener.",
            "Your consecration smells suspiciously of barley and hops.",
            "You lay on hands... usually your own, after too much drinking.",
            "Your divine shield is just you being too stubborn to die.",
            "You judge others more than you use Judgment.",
            "Your mount is a ram because horses look down on you.",
            "You think 'retribution' means getting the last round.",
            "Your holy light is just reflected beard shine.",
            "You're basically a walking, talking tankard with attitude.",
        },
        Priest = {
            "You heal with one hand and hold a drink with the other.",
            "Your Power Word: Shield is just extra beer insulation.",
            "You think 'shadow' form is just standing in mine shafts.",
            "Your prayers are just requests for more ale.",
            "You levitate to reach what your stubby legs can't.",
            "Your holy nova is just you burping after too much stout.",
            "You fear ward yourself from sober conversations.",
            "Your mind control only works on other drunk dwarves.",
            "You're basically a walking brewery with delusions of grandeur.",
            "Your greatest miracle is not passing out mid-raid.",
        },
        Rogue = {
            "You're so short, even stealth is redundant.",
            "Your pickpocketing is just 'borrowing' from clan mates.",
            "You vanish when it's time to pay the tab.",
            "Your backstab is just asking for a piggyback ride.",
            "You think poison is just what you call cheap ale.",
            "Your lockpicking skills only work on kegs.",
            "You sap people by hitting them in the kneecaps.",
            "Your evasion is just falling over drunk.",
            "You're the only rogue who leaves footprints in snow... because you're too heavy.",
            "Your garrote is just your beard getting caught on things.",
        },
        DeathKnight = {
            "Your army of the dead are just hungover clan mates.",
            "You raise ghouls to fetch you more ale.",
            "Your runeblade has 'Property of Ironforge' engraved on it.",
            "You think anti-magic shell is for keeping your beer cold.",
            "Your death grip is just you demanding another round.",
            "You're what happens when a dwarf holds a grudge... forever.",
            "Your presence is just really bad body odor from undeath.",
            "You've frozen so many people, they call you 'Walking Keg'.",
            "Your unholy aura is just pickled herring breath.",
            "You're basically a fossil with anger issues.",
        },
        Shaman = {
            "Your totems are just fancy beer taps.",
            "You talk to elements because other dwarves ignore you.",
            "Your chain heal is just passing around a keg.",
            "You think lava burst is just spicy ale.",
            "Your ghost wolf form is just a very hairy dwarf on all fours.",
            "You reincarnate as another, slightly drunker dwarf.",
            "Your earth elemental is just a pile of rocks you bribed with ale.",
            "You're the reason storm, earth, and fire all smell like whiskey.",
            "Your water walking is just you being too buoyant from all the ale.",
            "You commune with ancestors who are also drinking.",
        },
        Mage = {
            "Your portals always lead to the nearest tavern.",
            "You polymorph things into sheep to count them while drunk.",
            "Your frostbolt is just chilled ale.",
            "You teleport to avoid stairs your short legs can't manage.",
            "Your arcane intellect is just beer-fueled confidence.",
            "You conjure food that tastes suspiciously like mutton and ale.",
            "Your blink usually ends with you face-first in a wall.",
            "You think time warp is just drinking faster.",
            "You're basically a walking brewery explosion waiting to happen.",
            "Your spellsteal is just taking someone else's drink.",
        },
        Warlock = {
            "Your imp is just a drunk dwarf with wings.",
            "You summon demons to have someone to drink with.",
            "Your fear is just your morning breath.",
            "You think soulstone is a fancy whiskey bottle.",
            "Your felhunter is just a mangy beard with legs.",
            "You corrupt things... like good ale with cheap mixers.",
            "Your drain life is just stealing sips from others' drinks.",
            "You're what happens when a dwarf discovers edginess.",
            "Your demonic gateway always leads to the Dark Iron Tavern.",
            "You sacrifice imps for more pocket space for ale.",
        },
        Monk = {
            "Your brewmaster spec is just your normal personality.",
            "You roll because walking is for tall people.",
            "Your healing spheres are just floating ale droplets.",
            "You think touch of death is just a really strong handshake.",
            "Your storm, earth, and fire are just you in three drunken states.",
            "You transcend because your legs are tired from being short.",
            "Your fistweaving is just bar fighting with extra steps.",
            "You're basically a bowling ball with delusions of enlightenment.",
            "Your spinning crane kick is just you falling over artistically.",
            "Your elusive brawl is just dodging the tab at the tavern.",
        },
        DemonHunter = {
            "You're what happens when a dwarf gets tired of being short.",
            "Your double jump is just you hitting your head twice.",
            "You think spectral sight is just sobering up briefly.",
            "Your glaives are just oversized bottle openers.",
            "You metamorph into a slightly taller, angrier dwarf.",
            "You're basically a beard with too many piercings.",
            "Your fel rush is just tripping with style.",
            "You consume magic because ale wasn't destructive enough.",
            "You're proof that even dwarves can have a mid-life crisis.",
            "Your eyebeams are just really intense stares from someone who can't reach the top shelf.",
        },
        Druid = {
            "Your bear form is just a dwarf in a fur coat.",
            "You travel form into a ram because you miss your mount.",
            "Your moonkin form is a drunken owl-bear hybrid.",
            "You restore balance to the ale supply, not nature.",
            "Your cat form is just a grumpy, hairy dwarf.",
            "You're the only druid who needs a step stool to reach tree form.",
            "Your innervate is just passing around a keg.",
            "You think wild growth is just your beard expanding.",
            "You're basically a walking ecosystem of bad decisions.",
            "Your flight form is just you being thrown from a catapult.",
        },
        Evoker = {
            "You're what happens when a dwarf dreams of being tall and scaly.",
            "Your disintegrate is just really hot ale breath.",
            "You hover because the ground is too far away.",
            "You think deep breath is just inhaling before a drinking contest.",
            "Your tail sweep is just you turning around too fast.",
            "You're basically a bearded gecko with altitude envy.",
            "Your living flame is just heartburn from too much spicy ale.",
            "You rewind time to get more drinking hours in.",
            "You're proof that even ancient dragons can have stubby legs.",
            "Your soar is just falling with extra glitter.",
        },
    },
    ["Human"] = {
        Paladin = {
            "Your righteousness is only outmatched by your mediocrity.",
            "You bubble-hearth so often it's your racial ability.",
            "You think you're Arthas, but you're more like Larry from Accounting.",
            "Your divine purpose is to be the raid's moral compass and biggest liability.",
            "You judge others because your DPS can't.",
            "Your mount is a charger because your credit score is heroic.",
            "You're basically a tin can filled with white bread and entitlement.",
            "Your light only works when it's convenient for you.",
            "You've been saved more times than your raid progression.",
            "Your entire personality is 'Ctrl+Click to summon'.",
        },
        Priest = {
            "You heal because you can't handle real responsibility.",
            "Your shadow form is just your natural state of edginess.",
            "You power word: shield yourself from accountability.",
            "You think you're a discipline priest, but you're just undisciplined.",
            "Your levitate is the only thing keeping you above ground in meters.",
            "You fade when the repair bill comes.",
            "You're basically a band-aid with delusions of grandeur.",
            "Your mind control only works on yourself.",
            "You've resurrected so many bad players, you're an enabler.",
            "Your holy nova is just you being explosively average.",
        },
        Warrior = {
            "You charge first, think never.",
            "Your victory rush is just you being surprised you survived.",
            "You think tanking is a personality trait.",
            "Your heroic leap usually lands in fire.",
            "You're basically a meat shield with anger management issues.",
            "Your shout is just verbal diarrhea in plate armor.",
            "You've been battle-rezzed more times than you've batted.",
            "You think 'enraged regeneration' is just your normal mood.",
            "Your interrupt is as consistent as your attendance.",
            "You're the reason healers have trust issues.",
        },
        Rogue = {
            "You vanish when the fight gets interesting.",
            "Your stealth is just you avoiding responsibility.",
            "You think cheap shot is a valid negotiation tactic.",
            "Your lockpicking skills only work on your own potential.",
            "You're basically a walking trust issue in leather.",
            "Your kidney shot is just you hitting where it hurts... socially.",
            "You've been caught so many times, they call you 'Visible'.",
            "Your evasion is just you dodging accountability.",
            "You think sap is a form of greeting.",
            "Your backstab is usually preceded by actual backstabbing.",
        },
        Mage = {
            "Your intelligence is entirely arcane.",
            "You polymorph things to avoid difficult conversations.",
            "Your portals always have a convenience fee.",
            "You think you're Jaina, but you're more like Karen from HR.",
            "You're basically a walking mana battery with attitude.",
            "Your blink usually ends with you in a wall... or worse.",
            "You've been spellstealing since you were a child.",
            "Your time warp is just you being chronically late.",
            "You think frost nova is a valid personal space enforcement.",
            "Your greatest achievement is not setting yourself on fire.",
        },
        Warlock = {
            "Your demons are your only friends by choice.",
            "You summon pets because people avoid you.",
            "Your fear is just your natural aura.",
            "You think soulstone is a personality.",
            "You're basically an emo phase that never ended.",
            "Your corruption is just your bad influence on others.",
            "You drain life because you have none of your own.",
            "You've been sacrificing imps since it was cool.",
            "Your demonic gateway always leads to disappointment.",
            "You're the reason we can't have nice summoning circles.",
        },
        Hunter = {
            "Your pet has more common sense than you.",
            "You feign death so well even the healers believe it.",
            "Your traps are usually triggered by your own feet.",
            "You think aspect of the cheetah makes you interesting.",
            "You're basically a walking pet food dispenser.",
            "Your misdirect is just passing the blame to the tank.",
            "You've been disengaged from reality since level 1.",
            "Your volley is just spraying and praying with arrows.",
            "You think tracking is a substitute for awareness.",
            "Your greatest skill is blaming your pet for everything.",
        },
        DeathKnight = {
            "Your runeblade has more personality than you.",
            "You raise dead because you can't make living friends.",
            "Your anti-magic shell is just emotional armor.",
            "You think you're the Lich King, but you're more like the Lich Intern.",
            "You're basically a freezer-burned hero with daddy issues.",
            "Your death grip is just desperate clinginess.",
            "You've been unholy since your teen years.",
            "Your plague strike is just your morning breath.",
            "You think frost presence is a cool attitude.",
            "Your greatest achievement is not thawing in sunlight.",
        },
        Monk = {
            "Your brew is just cheap ale with fancy names.",
            "You roll because walking is too mainstream.",
            "Your healing spheres are just misplaced optimism.",
            "You think you're Chen, but you're more like Chad from Marketing.",
            "You're basically a yoga instructor with combat benefits.",
            "Your touch of death is just your passive-aggressive nature.",
            "You've been mistweaving since it was a trend.",
            "Your storm, earth, and fire are just your multiple personalities.",
            "You think transcendence is just avoiding problems.",
            "Your greatest skill is falling over gracefully.",
        },
        Druid = {
            "Your bear form is just you with extra body hair.",
            "You shapeshift to avoid human responsibilities.",
            "Your travel form is just you running from problems.",
            "You think you're Malfurion, but you're more like Melvin from IT.",
            "You're basically a furry with delusions of grandeur.",
            "Your moonkin form is what happens when a human and a chicken love each other too much.",
            "You've been restoring balance since your last therapy session.",
            "Your cat form is just you being passively aggressive.",
            "You think innervate is a valid pickup line.",
            "Your greatest achievement is not getting stuck in animal form.",
        },
        DemonHunter = {
            "Your edginess is only outmatched by your blindness.",
            "You double jump because you can't see where you're going.",
            "Your metamorphosis is just an emo phase with wings.",
            "You think you're Illidan, but you're more like Ian from Sales.",
            "You're basically a leather jacket with anger issues.",
            "Your fel rush is just you tripping with demonic energy.",
            "You've been prepared since your last identity crisis.",
            "Your spectral sight is just you pretending to see the obvious.",
            "You think eyebeams are a valid form of communication.",
            "Your greatest sacrifice was your fashion sense.",
        },
        Evoker = {
            "You're what happens when a human really likes lizards.",
            "Your disintegrate is just really focused disappointment.",
            "You hover because the ground is beneath you.",
            "You think you're an ancient dragon, but you're more like Larry from Legal.",
            "You're basically a scaly mid-life crisis.",
            "Your deep breath is just you sighing dramatically.",
            "You've been living flame since your last heartburn.",
            "Your tail is just a fancy scarf that attacks people.",
            "You think rewind is just denying your mistakes.",
            "Your greatest power is making everyone uncomfortable.",
        },
    },
    ["Blood Elf"] = {
        Paladin = {
            "Your light is just stolen goods with a holy filter.",
            "You bubble-hearth to fix your hair.",
            "You think you're a sunwell, but you're just a mood ring with armor.",
            "Your divine purpose is to accessorize the raid.",
            "You judge others based on their fashion choices.",
            "Your mount matches your eyes... because of course it does.",
            "You're basically a disco ball with delusions of righteousness.",
            "Your consecration is just you marking your territory.",
            "You've been redeemed more times than your glamour shots.",
            "Your entire rotation is just striking a pose.",
        },
        Hunter = {
            "Your pet is just a mobile accessory.",
            "You feign death when your hair gets messed up.",
            "Your traps are designed to complement your outfit.",
            "You think aspect of the cheetah makes you look faster and sleeker.",
            "You're basically a walking photoshoot with a bow.",
            "Your misdirect is just blaming your pet for your mistakes.",
            "You've been disengaged from anything that might cause sweat.",
            "Your volley is just you showing off your manicure.",
            "You think tracking is beneath you.",
            "Your greatest skill is looking good while failing.",
        },
        Mage = {
            "Your portals always lead to the best salons.",
            "You polymorph things that clash with your aesthetic.",
            "Your spellsteal is just borrowing without asking.",
            "You think you're Kael'thas, but you're more like Kevin from PR.",
            "You're basically a mana addict with style.",
            "Your blink is just you avoiding anything messy.",
            "You've been frost since fire might singe your hair.",
            "Your time warp is just you being fashionably late.",
            "You think arcane intellect is a substitute for actual intelligence.",
            "Your greatest achievement is not wrinkling your robes.",
        },
        Rogue = {
            "Your stealth is just you avoiding eye contact.",
            "You vanish when the conversation gets boring.",
            "Your pickpocketing is just collecting style inspiration.",
            "You think garrote is a type of necklace.",
            "You're basically a shadow with better highlights.",
            "Your kidney shot is just you hitting where it hurts... their fashion sense.",
            "You've been subtle since subtlety became trendy.",
            "Your evasion is just you dodging responsibility.",
            "You think cloak of shadows is a new fabric.",
            "Your greatest skill is backstabbing with a smile.",
        },
        Priest = {
            "You heal because damage is beneath you.",
            "Your shadow form is just you in a bad mood.",
            "You power word: shield yourself from criticism.",
            "You think you're a discipline priest, but you're just vain.",
            "Your levitate is to keep your robes clean.",
            "You fade when someone mentions your mana addiction.",
            "You're basically a health potion with an attitude.",
            "Your mind control is just you being persuasive.",
            "You've been holy since shadow might stain your robes.",
            "Your greatest spell is making everyone else look worse.",
        },
        Warlock = {
            "Your demons coordinate with your outfit.",
            "You summon pets because they're the only ones who listen.",
            "Your fear is just your resting bitch face.",
            "You think soulstone matches your eyes.",
            "You're basically goth with a sun tan.",
            "Your corruption is just your bad influence.",
            "You drain life to maintain your youthful appearance.",
            "You've been sacrificing imps since it was stylish.",
            "Your demonic gateway always leads to better parties.",
            "You're the reason fel magic has a bad reputation.",
        },
        DeathKnight = {
            "Your runeblade is accessorized to match.",
            "You raise dead because living servants are unreliable.",
            "Your anti-magic shell is just emotional distance.",
            "You think you're a scourge prince, but you're more like Preston from Fashion.",
            "You're basically a corpse with great skincare.",
            "Your death grip is just demanding attention.",
            "You've been frost since unholy might mess your hair.",
            "Your plague strike is just really bad perfume.",
            "You think blood presence is just being anemic with style.",
            "Your greatest achievement is looking good while decomposing.",
        },
        Warrior = {
            "You charge because walking might cause a sweat.",
            "Your victory rush is just you celebrating your reflection.",
            "You think tanking is just being stubborn with style.",
            "Your heroic leap usually lands in a puddle... of regret.",
            "You're basically a mannequin with anger issues.",
            "Your shout is just you complaining loudly.",
            "You've been battle-rezzed more times than you've batted an eye.",
            "You think 'enraged regeneration' is just fixing your makeup.",
            "Your interrupt is as timely as your fashion sense.",
            "You're the reason tanks have diva reputations.",
        },
        Monk = {
            "Your brew is just fancy tea with a kick.",
            "You roll because walking is for commoners.",
            "Your healing spheres are just floating skin care.",
            "You think you're a brewmaster, but you're more like a barista with issues.",
            "You're basically a yoga model with combat abilities.",
            "Your touch of death is just your passive-aggressive criticism.",
            "You've been mistweaving since it sounded elegant.",
            "Your storm, earth, and fire are just your multiple outfits.",
            "You think transcendence is just rising above the rabble.",
            "Your greatest skill is looking serene while failing.",
        },
        Druid = {
            "Your bear form has better hair than most humans.",
            "You shapeshift only into aesthetically pleasing animals.",
            "Your travel form is just you avoiding pedestrian travel.",
            "You think you're connected to nature, but you just like the colors.",
            "You're basically a glamorous furry.",
            "Your moonkin form is just a phase you're going through.",
            "You've been restoring balance to your chakras, not the world.",
            "Your cat form is just you being cattier.",
            "You think innervate is a skincare routine.",
            "Your greatest achievement is making deforestation look good.",
        },
        DemonHunter = {
            "Your blindness is just you ignoring everyone else.",
            "You double jump to show off your form.",
            "Your metamorphosis is just an extreme makeover.",
            "You think you're sacrificing everything, but you kept your hair gel.",
            "You're basically an edgy model with wings.",
            "Your fel rush is just you being dramatic.",
            "You've been prepared since your last photoshoot.",
            "Your spectral sight is just you judging everyone's aura.",
            "You think eyebeams are a valid beauty treatment.",
            "Your greatest sacrifice was your matching outfit set.",
        },
        Evoker = {
            "You're what happens when a blood elf really commits to a dragon theme.",
            "Your disintegrate is just intense criticism.",
            "You hover to avoid touching the common ground.",
            "You think you're preserving the isles, but you're just preserving your looks.",
            "You're basically a reptile with fantastic hair.",
            "Your deep breath is just you sighing at everyone's failures.",
            "You've been living flame since your last spa treatment.",
            "Your tail is just another accessory to worry about.",
            "You think rewind is just undoing a bad fashion choice.",
            "Your greatest power is making dragon aspects look boring.",
        },
        ["Death Knight"] = {
            "Your runeblade has more emotional depth than you.",
            "You raise ghouls because they don't criticize your fashion.",
            "Your anti-magic zone is just your personal space bubble.",
            "You think chains of ice are a new jewelry trend.",
            "You're basically a walking freezer with daddy issues.",
            "Your death and decay is just your cooking skills.",
            "You've been unholy since you discovered black eyeliner.",
            "Your frost presence is just you being cold and distant.",
            "You think blood boil is just your skincare routine failing.",
            "Your greatest achievement is matching your eyes to your weapon glow.",
        },
    },
}

local genericRoastByClass = {
    Warrior = {
        "Your battle plan is still 'hit it until it stops moving' after all these levels.",
        "You charge in like your repair bill is someone else's problem.",
        "Your DPS rotation is just yelling and hoping for the best.",
        "You think 'tanking' means being too stubborn to die first.",
        "Your interrupt is three expansions late and a taunt short.",
        "You've been battle-rezzed more times than you've landed a successful charge.",
        "Your defensive cooldowns are just elaborate ways to die slower.",
        "You think Heroic Leap is a valid substitute for awareness.",
        "You're basically a walking, talking loot piñata for mobs.",
        "Your greatest achievement is making healers question their career choices.",
    },
    Paladin = {
        "Your moral compass spins faster than your seal swapping.",
        "Bubble-hearth is your only escape plan and personality trait.",
        "You judge others more often than you use Judgment.",
        "Your divine purpose is to be wrong with confidence.",
        "You think the Light chose you, but it was just desperate.",
        "Your consecration is just you marking your territory like a dog.",
        "You lay on hands... usually on yourself after a bad pull.",
        "You're a tin can filled with holy water and bad decisions.",
        "Your mount is the only thing that follows your commands.",
        "You've been saved more times than your raid logs.",
    },
    Hunter = {
        "Your pet has higher DPS and better instincts than you.",
        "You feign death so often the healers stopped rezzing you.",
        "Your traps are just fancy paperweights with delusions of grandeur.",
        "You pull threat just by existing in the same zone.",
        "Your pet is basically your service animal for awareness.",
        "You misdirect to the tank because even you know you can't handle it.",
        "You think aspect of the cheetah makes you look cool.",
        "You've been disengaged from reality since level 10.",
        "Your volley is just praying and spraying with arrows.",
        "The only thing you track consistently is your own failure.",
    },
    Rogue = {
        "You vanish when things get interesting and reappear for loot.",
        "Your stealth is just you avoiding responsibility in leather armor.",
        "You think cheap shot is a valid conversation starter.",
        "Your lockpicking skills only work on your own potential.",
        "You're basically a walking trust issue with daggers.",
        "You sap the wrong target more often than you hit the right one.",
        "Your evasion is just you dodging accountability.",
        "You've been caught so many times they call you 'Visible'.",
        "Your backstab is usually preceded by actual backstabbing.",
        "Your greatest skill is making the rest of the group paranoid.",
    },
    Priest = {
        "You heal because you enjoy enabling bad behavior.",
        "Your Power Word: Shield is just emotional armor for the group.",
        "You think you're a discipline priest but you're just undisciplined.",
        "You fade when the repair bill gets mentioned.",
        "You're basically a band-aid with messiah complex.",
        "Your shadow form is just your natural state of edginess.",
        "You've resurrected so many bad players you should be arrested.",
        "Your mind control only works on yourself.",
        "Your holy nova is just you being explosively average.",
        "You're the reason DPS think standing in fire is a strategy.",
    },
    Mage = {
        "Your intelligence is entirely arcane and entirely useless.",
        "You polymorph things to avoid difficult conversations.",
        "Your portals always come with a convenience fee and attitude.",
        "You blink into walls more often than you blink out of danger.",
        "Your spellsteal is just taking what you want because you can.",
        "You think you're Jaina but you're more like a Karen with mana.",
        "Your frost nova is just you enforcing personal space with violence.",
        "You've been time warping at the wrong moment since Vanilla.",
        "Your conjured food tastes like despair and low expectations.",
        "You're basically a walking mana explosion waiting to happen.",
    },
    Warlock = {
        "Your demons are your only friends by mutual necessity.",
        "You summon pets because people avoid you naturally.",
        "Your fear is just your resting demonic presence.",
        "You think soulstone is a substitute for skill.",
        "You're an emo phase that became a lifestyle choice.",
        "Your corruption is just your bad influence made manifest.",
        "You drain life because you have none of your own.",
        "You've been sacrificing imps since before it was cool.",
        "Your demonic gateway always leads to disappointment.",
        "You're the reason we can't have nice summoning circles.",
    },
    Shaman = {
        "You drop totems like you're planting a garden of failure.",
        "You're a melee, a caster, and a liability all in one.",
        "Your chain heal is just passing around the blame.",
        "You think Windfury procs are a personality trait.",
        "You reincarnate as another, slightly more useless shaman.",
        "Your earth elemental is just a pile of rocks with bad AI.",
        "You're the reason storm, earth, and fire all have trust issues.",
        "Your ghost wolf form is just you giving up on walking.",
        "You've been lava bursting your own feet since Cataclysm.",
        "Your greatest achievement is not shocking yourself.",
    },
    Druid = {
        "You shapeshift because you can't commit to anything.",
        "Your bear form is just you with less body hair issues.",
        "You moonfire-tag like a loot-hungry raccoon.",
        "You're part tank, part healer, fully confused.",
        "Your travel form is just you running from your problems.",
        "You think innervate is a valid pickup line.",
        "You've been restoring balance since your last identity crisis.",
        "Your cat form is just you being passively aggressive.",
        "You're basically a furry with delusions of grandeur.",
        "Your greatest skill is being mediocre at everything.",
    },
    DeathKnight = {
        "Your runeblade has more personality than you do.",
        "You raise dead because you can't make living friends.",
        "Your anti-magic shell is just emotional armor.",
        "You think you're Arthas but you're more like a freezer burn.",
        "You're basically a corpse with anger management issues.",
        "Your death grip is just desperate clinginess.",
        "You've been unholy since your teen years.",
        "Your plague strike is just your morning breath weaponized.",
        "You think frost presence makes you look cool.",
        "Your greatest achievement is not thawing in sunlight.",
    },
    Monk = {
        "Your brew is just cheap ale with fancy names.",
        "You roll because walking is beneath you.",
        "Your healing spheres are just misplaced optimism.",
        "You think you're a martial artist but you're just flailing.",
        "You're basically a yoga instructor with combat benefits.",
        "Your touch of death is just your passive-aggressive nature.",
        "You've been mistweaving since it sounded mystical.",
        "Your storm, earth, and fire are just multiple personality disorder.",
        "You think transcendence is just avoiding your problems.",
        "Your greatest skill is falling over artistically.",
    },
    DemonHunter = {
        "Your edginess is only outmatched by your blindness.",
        "You double jump because you can't see where you're going.",
        "Your metamorphosis is just an emo phase with wings.",
        "You think you're Illidan but you're just edgy.",
        "You're basically a leather jacket with anger issues.",
        "Your fel rush is just you tripping with demonic energy.",
        "You've been prepared since your last identity crisis.",
        "Your spectral sight is just you pretending to see the obvious.",
        "You think eyebeams are a valid form of communication.",
        "Your greatest sacrifice was your fashion sense.",
    },
    Evoker = {
        "You're what happens when a dragon and an identity crisis mate.",
        "Your disintegrate is just really focused disappointment.",
        "You hover because the ground is beneath you.",
        "You think you're an ancient being but you're just confused.",
        "You're basically a lizard with delusions of grandeur.",
        "Your deep breath is just you sighing dramatically.",
        "You've been living flame since your last temper tantrum.",
        "Your tail is just a fancy accessory that attacks people.",
        "You think rewind is just denying your mistakes.",
        "Your greatest power is making everyone uncomfortable.",
    },
}
local genericRoastByRace = {
    ["Orc"] = {
        "Your battle plan consists entirely of 'see enemy, hit enemy'.",
        "You have two settings: 'Angry' and 'About to be angry'.",
        "Lok'tar ogar means 'victory or death' but you always choose both.",
        "Your forehead is harder than your brain and you use it more often.",
        "You solve puzzles by beating them until they stop being puzzles.",
        "Your idea of stealth is yelling from farther away.",
        "Blood fury isn't a racial ability, it's your default emotional state.",
        "You think strategy is what other races do when they're not winning.",
        "Your war cry is 90% volume, 10% actual tactical information.",
        "You're basically a walking, talking can of whoop-ass with anger issues.",
    },
    ["Troll"] = {
        "Your posture is permanently stuck between 'relaxed' and 'about to murder'.",
        "You talk so slow enemies die of old age waiting for you to finish.",
        "Your regeneration heals wounds but not your terrible life choices.",
        "You're basically a walking, talking voodoo doll of bad decisions.",
        "Your berserking is just your normal speed with extra screaming.",
        "You da voodoo, and you da problem in this raid group.",
        "You move like a predator who just remembered they left the oven on.",
        "Those tusks aren't for show, they're for opening beer and enemies.",
        "You're so tall you pull mobs from the next zone over.",
        "Your shadow is more intimidating than most other races' actual presence.",
    },
    ["Undead"] = {
        "You smell like a graveyard that lost a fight with a brewery.",
        "Your will of the forsaken is just you refusing to admit you're dead.",
        "You're basically a skeleton with commitment issues and a bad smell.",
        "You cannibalize enemies because even death won't stop your hunger.",
        "Your bones rattle louder than your threat meter, which is saying something.",
        "You've been decaying since Vanilla and you still haven't improved.",
        "Your touch of the grave is just your cold, dead personality.",
        "You're proof that sometimes death should have been permanent.",
        "You don't breathe, which explains why you never stop talking.",
        "Your existence is a medical hazard and a social liability.",
    },
    ["Tauren"] = {
        "You're not a tank, you're a walking geometry problem for the camera.",
        "Your hoof beats signal the ground and your arrival equally well.",
        "You're so big you pull aggro just by existing in the same continent.",
        "War stomp is just you complaining with your feet.",
        "You're basically a walking mountain with anger management issues.",
        "Your horns are for decoration and for catching on door frames.",
        "You don't dodge attacks, you just absorb them like a furry sponge.",
        "You're so tall you need a ladder to reach your own potential.",
        "Your endurance isn't a racial trait, it's stubbornness made flesh.",
        "You take up more space than your DPS justifies.",
    },
    ["Gnome"] = {
        "You're basically a walking, talking gnomish grenade with legs.",
        "Your escape artist is just you wiggling out of responsibility.",
        "You're so small the ground itself is a threat to your survival.",
        "Arcane resistance? More like resistance to being taken seriously.",
        "You look like a child's toy that learned how to commit war crimes.",
        "Your engineering specialty is making bigger problems from small ones.",
        "You're proof that evolution has a sense of humor and a grudge.",
        "You're not short, you're just concentrated trouble.",
        "Your entire race is a cautionary tale about ambition and explosions.",
        "You survive on pure spite and a complete lack of common sense.",
    },
    ["Night Elf"] = {
        "You shadowmeld so often we're not sure you actually exist.",
        "Your wisp form is just your soul admitting defeat early.",
        "You're 10,000 years old and still haven't learned to stand out of fire.",
        "Quickness is a racial trait, not a personality, but you're trying.",
        "You're basically an emo phase that became an entire civilization.",
        "You've been brooding since before other races learned to walk upright.",
        "Your nature resistance doesn't protect you from being a natural disaster.",
        "You move like a whisper and hit like a particularly dramatic leaf.",
        "You're allergic to sunlight and common sense.",
        "Your entire aesthetic is 'moody forest creature with daddy issues'.",
    },
    ["Dwarf"] = {
        "Stoneform is just you turning into what you already are: a rock.",
        "You're half the height but twice the headache of any other race.",
        "Your beard has more personality than your entire character.",
        "You find treasure because you're too short to see anything else.",
        "You're basically a walking beer barrel with delusions of grandeur.",
        "Your frost resistance is just being too drunk to feel the cold.",
        "You tunnel vision like it's a racial ability and a lifestyle choice.",
        "You're so dense light bends around you, and so does common sense.",
        "Your entire culture is based on digging holes and bad decisions.",
        "You're what happens when a mountain decides it wants to fight back.",
    },
    ["Human"] = {
        "Diplomacy is just you convincing others to do what you want.",
        "You're the racial equivalent of plain toast with delusions of grandeur.",
        "Every man for himself is your motto in combat and in loot rolls.",
        "You're aggressively average and somehow still think you're special.",
        "Your sword specialization is compensating for your personality.",
        "You're what happens when 'default settings' develop ambition.",
        "You think you're the protagonist but you're really just the tutorial.",
        "Your entire racial identity is 'we showed up and never left'.",
        "You're the reason every other race needs racial abilities to compete.",
        "You're basic, boring, and somehow still winning, which is infuriating.",
    },
    ["Blood Elf"] = {
        "Arcane torrent is just you stealing attention like you stole the Sunwell.",
        "You're so pretty you blind enemies, and unfortunately, allies too.",
        "Your magic resistance doesn't protect you from being a magical disaster.",
        "You're basically a disco ball with delusions of grandeur.",
        "You pose more than you DPS and somehow still get invited back.",
        "Your entire race is an addiction with better hair than you deserve.",
        "You're what happens when vanity becomes a national identity.",
        "Your silence isn't a racial ability, it's you judging everyone else.",
        "You're so dramatic even your spells have special effects.",
        "You're proof that sometimes beauty really is only skin deep.",
    },
    ["Draenei"] = {
        "Gift of the Naaru is just you apologizing in advance for what you're about to do.",
        "Your hooves are so loud you pull mobs through walls and time.",
        "You're basically a space goat with anger issues and a glow stick.",
        "Your shadow resistance is just being too bright to have a shadow.",
        "You're from another planet but still haven't learned to avoid fire.",
        "You're majestic, confusing, and constantly in the wrong place.",
        "Your gem obsession is just pretty rocks for a pretty useless race.",
        "You're so alien even your mistakes are from another dimension.",
        "Your entire existence is a failed prophecy that won't admit it failed.",
        "You're what happens when a holy being develops a drinking problem.",
    },
    ["Goblin"] = {
        "Your rocket jump is just you literally bouncing away from your problems.",
        "You're basically a walking, talking pyramid scheme with legs.",
        "Your best deals always involve someone else dying for profit.",
        "Time is money, and you waste everyone's time trying to save yours.",
        "Your rocket barrage is just fireworks of failure and regret.",
        "You're so greedy you'd charge your own mother for a resurrection.",
        "Your entire culture is based on exploiting loopholes and common sense.",
        "You're proof that capitalism and explosives shouldn't mix.",
        "Your engineering is just creative ways to avoid personal responsibility.",
        "You're what happens when a calculator develops ambition and matches.",
    },
    ["Worgen"] = {
        "Your running wild is just you finally admitting you're an animal.",
        "You're basically a furry's mid-life crisis given physical form.",
        "Your darkflight is just you running from your problems... again.",
        "You're so edgy you cut yourself on your own personality.",
        "You're what happens when a human and a wolf have a bad breakup.",
        "Your entire race is a cautionary tale about anger and poor hygiene.",
        "You're constantly shedding, both fur and responsibility.",
        "Your viciousness is just untreated anger management issues.",
        "You're proof that sometimes the beast within should stay within.",
        "You're a walking identity crisis with fangs and bad breath.",
    },
    ["Pandaren"] = {
        "Your bounce is just you literally rolling away from confrontation.",
        "You're basically a walking, talking food coma with martial arts.",
        "Your inner peace is just you napping through the entire raid.",
        "You're so round you roll more than you run.",
        "Your entire culture is based on food and avoiding responsibility.",
        "You're what happens when a bear decides to become a philosopher.",
        "Your epicurean is just an excuse to eat everything in sight.",
        "You're proof that meditation and obesity aren't mutually exclusive.",
        "You're constantly eating, even when you should be fighting.",
        "Your tranquility is just you sleeping through the boss fight.",
    },
    ["Vulpera"] = {
        "Your bag of tricks is just random junk you found on the ground.",
        "You're basically a raccoon that learned how to stand upright.",
        "Your make camp is just you giving up and taking a nap mid-dungeon.",
        "You're so small you get lost in your own backpack.",
        "Your entire race is based on stealing and looking cute while doing it.",
        "You're what happens when a fox and a kleptomaniac have a baby.",
        "Your nose for trouble finds it more often than loot.",
        "You're proof that sometimes evolution goes sideways.",
        "You're constantly rummaging through trash, both literal and metaphorical.",
        "Your survival instincts are just running away with extra steps.",
    },
    ["Mechagnome"] = {
        "Your emergency failsafe is just you rebooting from another bad decision.",
        "You're basically a toaster with delusions of grandeur.",
        "Your combat analysis is just overthinking your way into failure.",
        "You're so mechanical even your personality needs calibration.",
        "Your entire existence is a warranty violation waiting to happen.",
        "You're what happens when a gnome and a junkyard have a baby.",
        "Your hyper organic light originator is just a fancy flashlight.",
        "You're proof that some things shouldn't be upgraded.",
        "You're constantly breaking down at the worst possible moment.",
        "Your skeleton is made of spare parts and poor life choices.",
    },
    ["Lightforged Draenei"] = {
        "Your light's reckoning is just you overcompensating for being extra.",
        "You're basically a regular Draenei with a superiority complex and LEDs.",
        "Your forged in battle is just you being too stubborn to die correctly.",
        "You're so holy you glow, and so does your ego.",
        "Your entire existence is a retcon with better special effects.",
        "You're what happens when a space goat discovers electricity.",
        "Your demon hunter training didn't take because you're too bright.",
        "You're proof that sometimes more light just means more to blind.",
        "You're constantly judging everyone for not being shiny enough.",
        "Your light judgment is just you being judgmental with extra steps.",
    },
    ["Nightborne"] = {
        "Your ancient history is just excuses for being a magical disaster.",
        "You're basically a Night Elf who discovered magic and never recovered.",
        "Your arcane pulse is just you leaking magic like a broken faucet.",
        "You're so magical you confuse yourself with your own spells.",
        "Your entire civilization collapsed from arrogance and you didn't learn.",
        "You're what happens when an elf and a mana addiction have a baby.",
        "Your magical resistance doesn't protect you from being insufferable.",
        "You're proof that 10,000 years of isolation breeds bad attitudes.",
        "You're constantly floating because walking is beneath you.",
        "Your withered training is just practice for being useless.",
    },
    ["Highmountain Tauren"] = {
        "Your mountaineer is just you being too stubborn to fall off cliffs.",
        "You're basically a regular Tauren with extra horns and extra ego.",
        "Your rugged tenacity is just you being too dense to know when to quit.",
        "You're so high mountain you're literally above everyone else's problems.",
        "Your entire culture is based on headbutting and not much else.",
        "You're what happens when a cow climbs a mountain and gets ideas.",
        "Your waste not, want not is just you being cheap with extra steps.",
        "You're proof that sometimes more horns just means more to get stuck.",
        "You're constantly getting your antlers caught in doorways.",
        "Your pride of ironhorn is just stubbornness with a fancy name.",
    },
    ["Mag'har Orc"] = {
        "Your ancestral call is just you yelling for help from better Orcs.",
        "You're basically a regular Orc with better tattoos and worse attitudes.",
        "Your savage strikes are just regular strikes with extra grunting.",
        "You're so savage even your fashion is aggressive.",
        "Your entire existence is 'what if Orcs but browner and grumpier?'",
        "You're what happens when an Orc discovers leatherworking and anger.",
        "Your unburdened doesn't apply to emotional baggage, apparently.",
        "You're proof that sometimes brown is just a different shade of angry.",
        "You're constantly reminding everyone you're from another timeline.",
        "Your heritage is just excuses for being even more violent.",
    },
    ["Zandalari Troll"] = {
        "Your embrace of the loa is just you making excuses for being extra.",
        "You're basically a regular Troll who discovered gold leaf and never recovered.",
        "Your regal bearing is just arrogance with better jewelry.",
        "You're so ancient even your insults are in dead languages.",
        "Your entire civilization is built on pyramids and poor decisions.",
        "You're what happens when a troll decides they're better than everyone.",
        "Your city's sinking and so are your chances of being useful.",
        "You're proof that sometimes height just means farther to fall.",
        "You're constantly posing like someone's taking your picture.",
        "Your loa guidance is just making animal noises and calling it wisdom.",
    },
}

local flirtyRoastByRace = {
    ["Human"] = {
        "Every time you fight, I forget which is more dangerous - the mobs or how badly I want to pull you aside.",
        "That confidence isn't just heroic - it's making me consider very un-heroic thoughts.",
        "You move like you own every battlefield, and right now I'm wishing you'd conquer me next.",
        "If fighting were a dance, you'd be leading, and I'd follow you straight into trouble.",
        "There's something about watching you handle a sword that makes me want to be disarmed.",
        "You wear victory like it was made for you, and I'm starting to think I was made for you.",
        "Every strategic move you make has me strategizing how to get you alone.",
        "That 'savior of the world' look is working a little too well on me right now.",
        "You're making me reconsider every life choice that didn't end up with you.",
        "If focus were a resource, I'd be completely drained watching you work.",
    },
    ["Dwarf"] = {
        "I've seen mountains less sturdy, and I've never wanted to climb one more.",
        "That beard isn't the only thing that's legendary - the way you fight is making me weak.",
        "You're compact, powerful, and making me reconsider my entire 'type' right now.",
        "Every time you charge, you're charging straight through my better judgment.",
        "You handle that axe like it's part of you, and I'm jealous of a weapon.",
        "There's nothing small about your presence - you fill every room you enter, especially my thoughts.",
        "You're solid, unbreakable, and making me want to test both those qualities.",
        "That stubbornness looks good on you - makes me want to give you something to be stubborn about.",
        "You fight like you were carved from the mountains themselves, and I want to explore every inch.",
        "Every ale you drink just makes me wonder what else those lips are good at.",
    },
    ["Night Elf"] = {
        "You move through shadows like they're welcoming you home, and I want to be your next refuge.",
        "That moonlight isn't just in your hair - it's in how you move, and I'm completely bewitched.",
        "You're ancient, graceful, and making me feel very young and very eager.",
        "Every time you vanish, all I can think about is where I'd follow you.",
        "You're like a dream I don't want to wake up from, even if it kills me.",
        "That ethereal beauty is a weapon, and I'm willingly surrendering.",
        "You fight like poetry written in blood, and I want to be your next verse.",
        "Thousands of years of wisdom, and you're using it to make me completely foolish for you.",
        "Your shadowmeld isn't the only thing that disappears - my common sense goes with it.",
        "You're elegance wrapped in danger, and I want to unwrap every layer.",
    },
    ["Gnome"] = {
        "You're small enough to pick up, and dangerous enough that I'd let you.",
        "That intellect is almost as attractive as the chaos you create with it.",
        "You're proof that good things come in small packages - and right now I want to unwrap you.",
        "Every explosion you cause just makes me want to create some of our own.",
        "You're tiny, brilliant, and taking up way too much of my imagination.",
        "That engineering genius isn't just for machines - you've clearly engineered my attraction.",
        "You're a concentrated dose of trouble, and I'm ready for the overdose.",
        "Small frame, big personality, and you're making me think very big thoughts.",
        "Every gadget you invent just makes me wonder what you could invent for two.",
        "You're proof that dynamite comes in small packages, and I'm ready to be blown away.",
    },
    ["Draenei"] = {
        "You're heavenly to look at and hell on the battlefield - my favorite combination.",
        "That glow isn't just magical - it's highlighting every curve I shouldn't be staring at.",
        "You're literally divine, and I'm developing some very sinful thoughts.",
        "Every hoofbeat echoes straight through me, and I don't want it to stop.",
        "You're otherworldly beautiful, and making me forget which world I'm in.",
        "That strength isn't just physical - it's in how you carry yourself, and it's carrying me away.",
        "You're a vision from the Light, making me consider some very shadowy possibilities.",
        "Every blessing you channel just makes me want to be your next miracle.",
        "You're majestic, powerful, and reducing me to a very un-majestic puddle.",
        "Your grace defies your size, and my restraint is defying common sense.",
    },
    ["Orc"] = {
        "That raw power isn't just intimidating - it's doing things to me I can't explain.",
        "You fight like fury personified, and I want to be what calms the storm.",
        "Every muscle moves with purpose, and I'm becoming your new purpose.",
        "You're strength wrapped in green skin, and I want to be wrapped in you.",
        "That battle cry isn't just for enemies - it's awakening something in me.",
        "You're unapologetically fierce, and I'm apologizing for nothing I'm thinking.",
        "Every scar tells a story, and I want to hear them all with my lips.",
        "You're primal, powerful, and making me forget civilization exists.",
        "That confidence in battle translates to... other areas, and I want the translation.",
        "You're a force of nature, and I'm ready to be swept away.",
    },
    ["Troll"] = {
        "You move like liquid danger, and I want to drown in you.",
        "That relaxed attitude disappears when you fight, and so does my ability to think straight.",
        "Every lanky, lethal movement is rewriting what I find attractive.",
        "You're tall, confident, and giving me ideas that require a ladder.",
        "That predatory grace is hunting more than just mobs right now.",
        "You're effortless in everything you do, and making me put in all the effort not to jump you.",
        "Every tooth in that smile promises something dangerous, and I'm ready to risk it.",
        "You're the jungle given form, and I want to get lost in you.",
        "That rhythm in your movements has me moving to a beat only you can hear.",
        "You're laid back until you're not, and I want to be what makes you not.",
    },
    ["Tauren"] = {
        "You're massive, gentle, and making me feel very small in the best way.",
        "Every powerful movement is a promise of strength, and I want you to keep it.",
        "You're solid ground in a shifting world, and I want to stand on you.",
        "That deep voice rumbles straight through me, and I want more vibrations.",
        "You're protective by nature, and I'm volunteering to be protected.",
        "Every hoof-fall shakes the ground, and something else is shaking too.",
        "You're strength and softness in perfect balance, and I'm completely unbalanced.",
        "That horned silhouette against the sky is the only view I want.",
        "You're a walking sanctuary, and I want to worship at your altar.",
        "Your size should be intimidating, but all I feel is safe... and very turned on.",
    },
    ["Undead"] = {
        "You've cheated death, and now you're cheating me out of my sanity.",
        "That dark elegance is more alive than most living things I know.",
        "Every bone moves with purpose, and I'm developing new purposes.",
        "You're cold to the touch, but you're heating up my imagination.",
        "That defiance of nature is the sexiest rebellion I've ever seen.",
        "You're proof that some things only get better with age... and undeath.",
        "Every rattle of those bones rattles something in me too.",
        "You're beautifully broken, and I want to be the one who puts you back together.",
        "That smirk says you know exactly what you're doing to me, and you enjoy it.",
        "You're death warmed over, and I'm ready to catch fire.",
    },
    ["Blood Elf"] = {
        "You're so beautiful it should be illegal, and I'm ready to be your criminal.",
        "Every move is calculated perfection, and I'm done calculating - I just want.",
        "You glow with magic, and I'm under your spell completely.",
        "That arrogance isn't just attractive - it's a promise you can back up.",
        "You're grace with an edge, and I want to walk that edge with you.",
        "Every spell you cast just makes me want to be your next enchantment.",
        "You're elegance with bite, and I'm volunteering my neck.",
        "That confidence says you're used to getting what you want, and I want to be it.",
        "You're magic made flesh, and I'm developing a very physical reaction.",
        "You're the sin I never knew I wanted to commit, repeatedly.",
    },
    ["Worgen"] = {
        "You're wildness contained, and I want to be what makes you break free.",
        "Every growl vibrates through me in places it shouldn't.",
        "You're the beast and the beauty, and I want both at once.",
        "That transformation isn't just physical - it's transforming what I want.",
        "You're feral elegance, and I'm ready to be tamed.",
        "Every hair stands on end when you fight, and so do I.",
        "You're the danger in the dark, and I want to be your next midnight.",
        "That primal energy is calling to something primal in me.",
        "You're the nightmare I want to have every night.",
        "You're wild, untamed, and making me forget civilization.",
    },
    ["Goblin"] = {
        "You're small, sharp, and cutting right through my defenses.",
        "Every scheme in your eyes just makes me want to be your next big score.",
        "You're trouble with a capital 'T' and a very attractive interest rate.",
        "That rocket isn't the only thing that's going to blast off around you.",
        "You're proof that the best things come in explosive packages.",
        "Every deal you make just makes me want to make one with you.",
        "You're greedy, clever, and I'm willing to pay any price.",
        "That entrepreneurial spirit is entrepreneurial with my attention.",
        "You're chaos with a business plan, and I'm buying stock.",
        "You're small enough to hold, and big enough to wreck me completely.",
    },
    ["Pandaren"] = {
        "You're soft strength, and I want to feel how soft that strength really is.",
        "Every gentle movement hides power, and I want to uncover both.",
        "You're balance personified, and you're throwing me completely off mine.",
        "That roundness is just more of you to hold, and I want all of it.",
        "You're calm in the storm, and I want to be your storm.",
        "Every roll isn't just evasion - it's rolling straight into my fantasies.",
        "You're wisdom and warmth, and I want to learn from your body.",
        "That fur looks soft, and I'm developing very hands-on questions.",
        "You're peaceful until provoked, and I want to do the provoking.",
        "You're cuddly and deadly, and I'm ready for either outcome.",
    },
    ["Void Elf"] = {
        "You're walking temptation from the Void, and I'm void of resistance.",
        "Every whisper of the shadows whispers your name in my mind.",
        "You're beauty touched by darkness, and I want that touch.",
        "That corruption looks good on you - makes me want to be corrupted too.",
        "You're the void given form, and I want to explore your space.",
        "Every portal you open just makes me want to enter you.",
        "You're elegance with an edge of madness, and I'm going over that edge.",
        "That otherworldly beauty is from another world, and I want to visit.",
        "You're the darkness I never knew I needed until now.",
        "You're void-touched and touching something in me that wasn't void before.",
    },
    ["Lightforged Draenei"] = {
        "You're the Light made flesh, and I'm developing some very fleshly thoughts.",
        "Every holy glow just highlights how unholy my imagination is getting.",
        "You're divine perfection, and I want to commit sins with you.",
        "That righteousness isn't just armor - it's making me want to disarm you.",
        "You're blessed by the Light, and I want to be your next blessing.",
        "Every laser from your eyes just targets my self-control.",
        "You're heaven sent, and I'm ready to fall for you.",
        "That holy power radiates, and I'm having very unholy reactions.",
        "You're too pure for this world, and I want to make it worth your while.",
        "You're the Light's vengeance, and I want to be your reward.",
    },
}
local flirtLines = {
    ["Dwarf"] = {
        Hunter = {
            "Save a /drink for me next time you're in Ironforge.",
            "If your pet ever needs a night off, I volunteer as tribute.",
            "Careful, with that aim and that smile, you're a raid wipe waiting to happen.",
            "You, me, and a campfire, let the pet stand guard.",
            "Tame a beast that matches your energy. Or just tame me.",
        },
    },
    ["Human"] = {
        Paladin = {
            "Plate and charm? You're going to cause a threat spike.",
            "If the Light had favorites, you'd be on the shortlist.",
            "Queue us for a dungeon and call it a date.",
            "You stun more hearts than mobs.",
            "You're the reason /flirt was invented.",
        },
        Priest = {
            "Remind me to fake an injury later so you can heal me.",
            "You're dangerously good at patching people up, emotionally too.",
            "Your smiles crit harder than your heals.",
            "If holiness had a face, it'd look a lot like yours.",
            "You're proof that support roles are the real main characters.",
        },
    },
}

local genericFlirtByClass = {
    Warrior = {
        "Strong, shiny, and dangerous. Remind me not to duel you after drinks.",
        "You swing that weapon like you mean it. I'm taking notes... from a safe distance.",
        "All that armor and you still manage to look good in it. Impressive.",
        "If courage was a stat, you'd be hard-capped.",
    },
    Paladin = {
        "Plate, light, and that smile? You're a walking buff.",
        "You protect everyone else; someone should be protecting you. I volunteer.",
        "If the Light has favorites, you're definitely on the list.",
        "You could bless me any time. Spirit, stamina, the works.",
    },
    Hunter = {
        "Deadly aim, loyal pet, and you look good doing it. Unfair, really.",
        "If your charm is half as strong as your crits, we're in trouble.",
        "Careful, with you and that pet around, hearts aren't safe either.",
        "You tame beasts and still somehow steal the spotlight.",
    },
    Rogue = {
        "You sneak, you stab, and still manage to look mysterious doing it.",
        "You're the reason /wink was invented.",
        "If you vanish from the fight, at least don't vanish from my whispers.",
        "You're dangerously good at making an entrance... and an exit.",
    },
    Priest = {
        "You mend wounds and break hearts. Balanced, really.",
        "If I fake a mortal injury will you come check on me personally?",
        "You shine in a way even the Light envies.",
        "Your heals are strong, but your presence is stronger.",
    },
    Mage = {
        "You set everything on fire and somehow still look flawless.",
        "Your spells are flashy, but you might be the real spectacle.",
        "You conjure food and water, but I'm much more interested in you.",
        "If frost and fire had a favorite caster, it'd be you.",
    },
    Warlock = {
        "You command demons and still manage to be the most captivating one present.",
        "You're dangerous, dramatic, and weirdly charming. Concerning combination.",
        "If your smile is half as cursed as your magic, I'm doomed.",
        "You tempt fate, demons, and probably me too.",
    },
    Shaman = {
        "You call lightning and still somehow light up the room more.",
        "Your totems aren't the only things keeping everyone standing.",
        "If the elements are listening to you, I should probably start as well.",
        "You're part storm, part healer, and entirely distracting.",
    },
    Druid = {
        "You could tank, heal, or DPS--and I'd still pick you as my first choice.",
        "You move like you belong in every form you take.",
        "You're as dangerous as you are graceful. Nature approves.",
        "You make 'one with nature' look extremely appealing.",
    },
}

local genericFlirtByRace = {
    ["Human"] = {
        "Classic never goes out of style. Case in point: you.",
        "You look like you walked straight out of a hero's story.",
        "You're what NPCs think of when they say 'champion'.",
        "If destiny needed a poster child, it'd probably use your portrait.",
    },
    ["Dwarf"] = {
        "Short, fierce, and somehow the tallest presence in the room.",
        "You could probably bench-press half of Ironforge and I respect that.",
        "You're living proof good things come in heavily armored packages.",
        "If we share a drink, I'm not responsible for my decisions after.",
    },
    ["Night Elf"] = {
        "You belong in moonlight and trouble in equal measure.",
        "Elegant, deadly, and entirely distracting.",
        "You move like a whisper and hit like a shout.",
        "If I get lost in the shadows, I'm blaming your eyes.",
    },
    ["Gnome"] = {
        "Tiny frame, huge presence. Honestly kind of unfair.",
        "You're proof the most dangerous things come in compact form.",
        "If trouble had a mascot, it'd probably look a little like you.",
        "You're small enough to sneak in and bright enough to own the room.",
    },
    ["Draenei"] = {
        "You're basically walking prophecy with excellent posture.",
        "Those eyes, that glow--you're hard to ignore in any crowd.",
        "You look like you stepped out of a vision and into the fight.",
        "If grace was a stat, you'd soft-cap the universe.",
    },
    ["Orc"] = {
        "Strong, fierce, and surprisingly good-looking under all that fury.",
        "You charge first and ask questions never, and it's oddly attractive.",
        "You're the kind of trouble banners are written about.",
        "You look like victory and very poor impulse control.",
    },
    ["Troll"] = {
        "You move like a dance and hit like a drumbeat.",
        "You've got the kind of smile that starts either a party or a fight.",
        "You're a little wild, a little reckless, and very hard to ignore.",
        "You make chaos look stylish.",
    },
    ["Tauren"] = {
        "Tall, calm, and quietly unstoppable.",
        "You make 'gentle giant' look like a serious buff.",
        "You walk like the earth itself makes room for you.",
        "If I lean against you during downtime, that's tactical, not sentimental. Probably.",
    },
    ["Undead"] = {
        "You've already died once and somehow came back looking like that.",
        "You're proof that charm survives just about anything.",
        "Those eyes say 'I've seen things' and I kind of want to hear about them.",
        "You make undeath look strangely appealing.",
    },
    ["Blood Elf"] = {
        "You're drama, danger, and divine lighting all in one.",
        "You could start a fight just by walking into a room and smirking.",
        "You glow like you know you're the main attraction.",
        "You swing weapons like props and still somehow land every hit.",
    },
}

--------------------------------------------------------
-- Getter helpers (unchanged)
--------------------------------------------------------

local function getFlavor(race, className, level)
    local pool, key

    -- 1) Try race/class-specific flavor
    if race and className and flavorLines[race] and flavorLines[race][className] then
        pool = flavorLines[race][className]
        key  = makeKey("RACECLASS_FLAVOR", race, className)

        local text = pickRandomNonRepeating(pool, lastUsed.flavor, key)
        if text then
            if text:find("%%d") then
                return string.format(text, level or 0)
            end
            return text
        end
    end

    -- 2) Fall back to a generic flavor pool
    pool = genericFlavorFallback
    key  = makeKey("GENERICFLAVOR", className or "NONE")

    local text = pickRandomNonRepeating(pool, lastUsed.flavor, key)
    if not text then return nil end

    -- support %d formatting just in case
    if text:find("%%d") then
        return string.format(text, level or 0)
    end

    return text
end

local function getTip(className)
    if not className then return nil end

    local key  = className
    local pool = tipLines[className]
    if not pool then return nil end

    return pickRandomNonRepeating(pool, lastUsed.tip, key)
end

local function getRoast(race, className, gender)
    local genderIsFemale = (gender == "FEMALE" or gender == 3)
    local pool, key

    -- 0) If FEMALE, flirting is enabled, and we have flirty race-roasts, give them priority (but not 100%)
    if genderIsFemale and race and flirtyRoastByRace[race] and (GCongratsDB.enableFlirting ~= false) then
        -- 60% chance to use a flirty roast instead of normal one (only if flirting is enabled)
        if math.random() < 0.60 then
            pool = flirtyRoastByRace[race]
            key  = makeKey("FLIRTYRACE", race)
            return pickRandomNonRepeating(pool, lastUsed.roast, key)
        end
    end

    -- 1) Most specific: race + class
    if race and className and roastLines[race] and roastLines[race][className] then
        pool = roastLines[race][className]
        key  = makeKey("RACECLASS", race, className)
        return pickRandomNonRepeating(pool, lastUsed.roast, key)
    end

    -- 2) Class-only generic roast
    if className and genericRoastByClass[className] then
        pool = genericRoastByClass[className]
        key  = makeKey("CLASS", className)
        return pickRandomNonRepeating(pool, lastUsed.roast, key)
    end

    -- 3) Race-only generic roast
    if race and genericRoastByRace[race] then
        pool = genericRoastByRace[race]
        key  = makeKey("RACE", race)
        return pickRandomNonRepeating(pool, lastUsed.roast, key)
    end

    -- 4) No roast available
    return nil
end

local function getFlirt(race, className)
    local pool, key

    -- 1) Most specific: race + class
    if race and className and flirtLines[race] and flirtLines[race][className] then
        pool = flirtLines[race][className]
        key  = makeKey("RACECLASS", race, className)
        return pickRandomNonRepeating(pool, lastUsed.flirt, key)
    end

    -- 2) Generic by class
    if className and genericFlirtByClass[className] then
        pool = genericFlirtByClass[className]
        key  = makeKey("CLASS", className)
        return pickRandomNonRepeating(pool, lastUsed.flirt, key)
    end

    -- 3) Generic by race
    if race and genericFlirtByRace[race] then
        pool = genericFlirtByRace[race]
        key  = makeKey("RACE", race)
        return pickRandomNonRepeating(pool, lastUsed.flirt, key)
    end

    -- 4) Nothing available
    return nil
end


--------------------------------------------------------
-- Public API: BuildMessage (unchanged)
--------------------------------------------------------

function GC:BuildMessage(name, race, className, level, gender, mode)
    if not name or not level then return nil end

    mode = mode or (GCongratsDB and GCongratsDB.mode) or 1
    local genderUpper = type(gender) == "string" and gender:upper() or gender

    local base = string.format("Congrats %s on level %d!", name, level)

    local flavor = getFlavor(race, className, level)
    if not flavor then
        flavor = string.format("Looking good out there as a %s %s!", race or "Unknown", className or "Adventurer")
    end

    local tip, roast, flirt

    if mode == 2 then
        tip = getTip(className)
    elseif mode == 3 then
        roast = getRoast(race, className, genderUpper)
    end

    -- Female flirt logic (occasional)
    if genderUpper == "FEMALE" or genderUpper == 3 then
        local roll = math.random()
        if roll < 0.35 then
            flirt = getFlirt(race, className)
        end
    end

    local parts = { base }

    if flavor and flavor ~= "" then
        table.insert(parts, flavor)
    end

    if mode == 2 and tip then
        table.insert(parts, tip)
    elseif mode == 3 then
        if roast then
            table.insert(parts, roast)
        end
        if flirt then
            table.insert(parts, flirt)
        end
    else
        if flirt then
            table.insert(parts, flirt)
        end
    end

    return table.concat(parts, " ")
end

--------------------------------------------------------
-- TBC-Compatible Guild Roster Tracking (FIXED FOR 2.4.3)
--------------------------------------------------------

local function GC_ShortName(fullName)
    if not fullName then return nil end
    -- Ambiguate() does NOT exist in TBC 2.4.3; strip realm manually.
    local short = string.match(fullName, "([^%-]+)")
    return short or fullName
end

local function GC_ScanGuildRoster()
    GC_EnsureDB()

    if not IsInGuild() then return end

    local firstRun = not GuildCongratsDB.initialized

    local num = GetNumGuildMembers()
    if not num or num == 0 then return end

    for i = 1, num do
        -- TBC: GetGuildRosterInfo returns:
        -- name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName
        local fullName, _, _, level, classDisplayName, _, _, _, _, _, classFileName = GetGuildRosterInfo(i)

        if fullName and classFileName and level then
            local shortName = GC_ShortName(fullName)
            local prevLevel = GuildCongratsDB.levels[shortName]

            -- Try to get race/gender from cache (TBC can't reliably read race from roster)
            local raceName   = "Unknown"
            local genderLabel = nil

            if GC.guildCache[shortName] then
                raceName     = GC.guildCache[shortName].race or "Unknown"
                genderLabel  = GC.guildCache[shortName].gender
            end

            -- Cache what we can
            GC.guildCache[shortName] = {
                token  = classFileName,
                class  = classDisplayName or classFileName or "Unknown",
                race   = raceName,
                gender = genderLabel
            }

            -- Level-up detection (skip first snapshot)
            if GuildCongratsDB.enabled
               and (not firstRun)
               and prevLevel
               and level > prevLevel then

                if GC.isLeader then
                    local cName = classDisplayName or classFileName or "Unknown"
                    local text  = GC:BuildMessage(shortName, raceName, cName, level, genderLabel, GCongratsDB.mode or 1)

                    if text and text ~= "" then
                        SendChatMessage(text, "GUILD")
                    end

                    GC_Print(string.format(
                        "Detected level up: %s %d -> %d (%s, %s)",
                        shortName, prevLevel, level, raceName or "?", classFileName or "?"
                    ))
                end
            end

            -- Always store latest level
            GuildCongratsDB.levels[shortName] = level
        end
    end

    if not GuildCongratsDB.initialized then
        GuildCongratsDB.initialized = true
        GC_Print("Initial guild level snapshot taken. Future level ups will be announced.")
    end
end

--------------------------------------------------------
-- Leader Election + Addon Comms (TBC 2.4.3 FIXED)
--------------------------------------------------------

local function GC_CommsRegisterPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ADDON_PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, ADDON_PREFIX)
    end
end

local function GC_SendAddon(msg)
    -- TBC uses SendAddonMessage(prefix, msg, "GUILD")
    if SendAddonMessage then
        SendAddonMessage(ADDON_PREFIX, msg, "GUILD")
    end
end

local function GC_HandleAddonMessage(prefix, msg, channel, sender)
    if prefix ~= ADDON_PREFIX then return end
    if not msg or msg == "" then return end
    if not sender or sender == "" then return end

    sender = GC_ShortName(sender)

    local cmd, who = string.match(msg, "^([A-Z]+)%:?(.*)$")
    if not cmd then return end

    if cmd == "HELLO" then
        who = GC_ShortName(who)
        if who and who ~= "" then
            seenCandidates[who] = true
        end
        return
    end

    if cmd == "LEADER" then
        who = GC_ShortName(who)
        if who and who ~= "" then
            GC.leaderName = who
            GC.hasLeader  = true
            GC.isLeader   = (who == GC_ShortName(UnitName("player")))
        end
        return
    end
end

local function GC_StartLeaderElection()
    if not IsInGuild() then return end

    local me = GC_ShortName(UnitName("player"))
    if not me or me == "" then return end

    GC_CommsRegisterPrefix()

    seenCandidates = {}
    seenCandidates[me] = true

    GC_SendAddon("HELLO:" .. me)

    -- elect after 2 seconds
    GC_CreateTimer(2, function()
        -- If someone already declared leader, keep it
        if GC.hasLeader and GC.leaderName then
            GC.isLeader = (GC.leaderName == me)
            return
        end

        local chosen
        for name in pairs(seenCandidates) do
            if not chosen or name < chosen then
                chosen = name
            end
        end

        if chosen then
            GC.leaderName = chosen
            GC.hasLeader  = true
            GC.isLeader   = (chosen == me)

            GC_SendAddon("LEADER:" .. chosen)

            if GC.isLeader then
                GC_Print("I am the active announcer for the guild.")
            else
                GC_Print("Active announcer is " .. chosen .. ". Standing by quietly.")
            end
        end
    end)
end
--------------------------------------------------------
-- OPTIONS PANEL (Modern Settings API + fallback) - SELF CONTAINED
--------------------------------------------------------

GC.optionsPanel     = GC.optionsPanel     or nil
GC.settingsCategory = GC.settingsCategory or nil

-- One-time init guard for post-load nudges
GC._postInitRan = GC._postInitRan or false

local function GC_SafeLoadSettingsUI()
    -- Modern clients may load Settings lazily; safe to attempt.
    if not Settings and LoadAddOn then
        pcall(LoadAddOn, "Blizzard_Settings")
    end
end

local function GC_RegisterOptionsPanel(panel)
    -- Prefer modern Settings API (Retail / some modern Classic builds)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        if not GC.settingsCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name or "GuildCongrats")
            Settings.RegisterAddOnCategory(category)
            GC.settingsCategory = category
        end
        return true
    end

    -- Legacy Interface Options (TBC / older)
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        return true
    end
    if InterfaceOptionsFrame_AddCategory then
        InterfaceOptionsFrame_AddCategory(panel)
        return true
    end

    return false
end

local function GC_OpenToOptions(panel)
    GC_SafeLoadSettingsUI()

    -- Modern Settings open
    if Settings and Settings.OpenToCategory and GC.settingsCategory then
        local ok = pcall(function()
            if GC.settingsCategory.ID then
                Settings.OpenToCategory(GC.settingsCategory.ID)
            else
                Settings.OpenToCategory(GC.settingsCategory)
            end
        end)

        -- Some builds want the -1 id nudge
        if (not ok) and GC.settingsCategory and GC.settingsCategory.ID then
            pcall(function()
                Settings.OpenToCategory(GC.settingsCategory.ID - 1)
            end)
        end

        return true
    end

    -- Legacy Interface Options open (TBC 2.4.3)
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel) -- double-call fixes scroll focus on some clients
        if InterfaceOptionsFrame and InterfaceOptionsFrame.Show then
            InterfaceOptionsFrame:Show()
        end
        return true
    end

    return false
end

-- Checkbox factory: tries known templates, otherwise builds a simple checkbox.
local function GC_CreateCheckbox(name, parent)
    -- Prefer templates that exist across more versions
    local template =
        (InterfaceOptionsCheckButtonTemplate and "InterfaceOptionsCheckButtonTemplate")
        or (UICheckButtonTemplate and "UICheckButtonTemplate")
        or nil

    local cb
    if template then
        cb = CreateFrame("CheckButton", name, parent, template)
    else
        -- Manual checkbox fallback (should be rare, but safe)
        cb = CreateFrame("CheckButton", name, parent)
        cb:SetSize(24, 24)

        local bg = cb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(true)
        bg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")

        local check = cb:CreateTexture(nil, "ARTWORK")
        check:SetAllPoints(true)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        check:Hide()
        cb._checkTex = check

        cb:SetScript("OnClick", function(self)
            local on = not not self:GetChecked()
            if self._checkTex then
                if on then self._checkTex:Show() else self._checkTex:Hide() end
            end
        end)
    end

    -- Normalize label behavior across templates
    if cb.Text then
        cb._label = cb.Text
    elseif cb.text then
        cb._label = cb.text
    else
        cb._label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        cb._label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    end

    -- Some templates use different textures; ensure it looks clickable
    if cb.SetNormalTexture and cb:GetNormalTexture() == nil then
        cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end

    return cb
end

local function GC_EnsureAttuneOptionsDB()
    if not GCongratsDB then GCongratsDB = {} end
    if type(GCongratsDB.attunements) ~= "table" then GCongratsDB.attunements = {} end

    local db = GCongratsDB.attunements
    if db.enabled == nil then db.enabled = true end
    if db.debug == nil then db.debug = false end
    if db.announceSelf == nil then db.announceSelf = false end
    if db.whoLookup == nil then db.whoLookup = true end
    if db.includeTips == nil then db.includeTips = true end
    if db.cooldownSeconds == nil then db.cooldownSeconds = 300 end
    if db.minDelay == nil then db.minDelay = 0.8 end
    if db.maxDelay == nil then db.maxDelay = 2.4 end
    if db.guildChannel == nil then db.guildChannel = "GUILD" end
    if db.whoTimeout == nil then db.whoTimeout = 2.0 end
    if db.whoCooldownSeconds == nil then db.whoCooldownSeconds = 10 end
    return db
end

local function GC_SetCheckboxState(cb, checked)
    if not cb then return end
    checked = not not checked
    cb:SetChecked(checked)
    if cb._checkTex then
        if checked then cb._checkTex:Show() else cb._checkTex:Hide() end
    end
end

local function GC_AttuneOptionsPrint(settingName, checked)
    if GC_Print then
        GC_Print("Attunement " .. settingName .. " " .. (checked and "enabled" or "disabled"))
    end
end

-- Self-contained UI builder (DO NOT rely on CreateOptionsUI existing elsewhere)
local function GC_CreateOptionsUI(panel)
    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|TInterface/AddOns/GuildCongrats/art/gc-big.tga:32:32:0:0|t |cff00aeffGuild|r|cFFDDDDDDCongrats|r|cff20a30fTBC|r")

    -- Description
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Configure level-up & attunement congratulations messages.")

    -- Separator
    local line = panel:CreateTexture(nil, "ARTWORK")
    if line.SetColorTexture then
        line:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    else
        line:SetTexture("Interface\\Buttons\\WHITE8x8")
        line:SetVertexColor(0.3, 0.3, 0.3, 0.6)
    end
    line:SetSize(380, 1)
    line:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)

    -- Mode label
    local modeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    modeLabel:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -20)
    modeLabel:SetText("Level-Up Message Style:")

    -- Slider
    local slider = CreateFrame("Slider", "GuildCongratsModeSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", 0, -10)
    slider:SetWidth(200)
    slider:SetHeight(17)
    slider:SetMinMaxValues(1, 3)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end

    -- Slider labels (guarded for clients that name them differently)
    local low  = _G[slider:GetName() .. "Low"]
    local high = _G[slider:GetName() .. "High"]
    local text = _G[slider:GetName() .. "Text"]
    if low  and low.SetText  then low:SetText("Simple") end
    if high and high.SetText then high:SetText("Spicy") end
    if text and text.SetText then text:SetText("Style") end

    -- Current value display
    local valueText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", slider, "RIGHT", 20, 0)

    -- Mode descriptions
    local desc1 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc1:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -15)
    desc1:SetText("|cff00ff001:|r Flavor only - Simple congratulations")

    local desc2 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc2:SetPoint("TOPLEFT", desc1, "BOTTOMLEFT", 0, -2)
    desc2:SetText("|cff00ff002:|r Flavor + Tip - Adds class tips")

    local desc3 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc3:SetPoint("TOPLEFT", desc2, "BOTTOMLEFT", 0, -2)
    desc3:SetText("|cff00ff003:|r Flavor + Roast - Adds playful roasts")

    -- Ensure DB exists (defensive; avoids nil errors on first load)
    if not GCongratsDB then GCongratsDB = {} end
    if GCongratsDB.enableFlirting == nil then
        GCongratsDB.enableFlirting = true
    end

    -- Flirting checkbox (TBC-safe; no OptionsCheckButtonTemplate)
    local flirtCheckbox = GC_CreateCheckbox("GuildCongratsFlirtCheckbox", panel)
    flirtCheckbox:SetPoint("TOPLEFT", desc3, "BOTTOMLEFT", 0, -15)
    flirtCheckbox._label:SetText("Enable Flirting")
    flirtCheckbox:SetChecked(GCongratsDB.enableFlirting)

    -- Click handler (also updates manual checkbox visuals if needed)
    flirtCheckbox:SetScript("OnClick", function(self)
        local checked = not not self:GetChecked()
        GCongratsDB.enableFlirting = checked

        if self._checkTex then
            if checked then self._checkTex:Show() else self._checkTex:Hide() end
        end

        if GC_Print then
            GC_Print("Flirting " .. (checked and "enabled" or "disabled"))
        end
    end)

    -- Update display function
    function panel.updateDisplay(value)
        value = math.floor((tonumber(value) or 1) + 0.5)
        if value == 1 then
            valueText:SetText("Simple")
        elseif value == 2 then
            valueText:SetText("Normal")
        else
            valueText:SetText("Spicy")
        end
    end

    -- Slider change handler
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor((tonumber(value) or 1) + 0.5)
        GCongratsDB.mode = value
        panel.updateDisplay(value)
    end)

    -- Initial setup
    local currentMode = GCongratsDB.mode or 1
    slider:SetValue(currentMode)
    panel.updateDisplay(currentMode)

    -- Attunement Congratulations section
    local attuneHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    attuneHeader:SetPoint("TOPLEFT", flirtCheckbox, "BOTTOMLEFT", 0, -24)
    attuneHeader:SetText("Attunement Congratulations")

    local attuneDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    attuneDesc:SetPoint("TOPLEFT", attuneHeader, "BOTTOMLEFT", 0, -6)
    attuneDesc:SetWidth(420)
    attuneDesc:SetJustifyH("LEFT")
    attuneDesc:SetText("Configure attunement completion congratulations messages.")

    local attuneDB = GC_EnsureAttuneOptionsDB()

    local attuneEnabledCheckbox = GC_CreateCheckbox("GuildCongratsAttuneEnabledCheckbox", panel)
    attuneEnabledCheckbox:SetPoint("TOPLEFT", attuneDesc, "BOTTOMLEFT", 0, -12)
    attuneEnabledCheckbox._label:SetText("Enable Attunement Congrats")
    GC_SetCheckboxState(attuneEnabledCheckbox, attuneDB.enabled ~= false)
    attuneEnabledCheckbox:SetScript("OnClick", function(self)
        local checked = not not self:GetChecked()
        local db = GC_EnsureAttuneOptionsDB()
        db.enabled = checked
        GC_SetCheckboxState(self, checked)
        GC_AttuneOptionsPrint("congrats", checked)
    end)

    local attuneWhoCheckbox = GC_CreateCheckbox("GuildCongratsAttuneWhoCheckbox", panel)
    attuneWhoCheckbox:SetPoint("TOPLEFT", attuneEnabledCheckbox, "BOTTOMLEFT", 0, -6)
    attuneWhoCheckbox._label:SetText("Use hidden /who lookup for race detection")
    GC_SetCheckboxState(attuneWhoCheckbox, attuneDB.whoLookup ~= false)
    attuneWhoCheckbox:SetScript("OnClick", function(self)
        local checked = not not self:GetChecked()
        local db = GC_EnsureAttuneOptionsDB()
        db.whoLookup = checked
        GC_SetCheckboxState(self, checked)
        GC_AttuneOptionsPrint("hidden /who lookup", checked)
    end)

    local attuneSelfCheckbox = GC_CreateCheckbox("GuildCongratsAttuneSelfCheckbox", panel)
    attuneSelfCheckbox:SetPoint("TOPLEFT", attuneWhoCheckbox, "BOTTOMLEFT", 0, -6)
    attuneSelfCheckbox._label:SetText("Congratulate my own attunement completions")
    GC_SetCheckboxState(attuneSelfCheckbox, attuneDB.announceSelf == true)
    attuneSelfCheckbox:SetScript("OnClick", function(self)
        local checked = not not self:GetChecked()
        local db = GC_EnsureAttuneOptionsDB()
        db.announceSelf = checked
        GC_SetCheckboxState(self, checked)
        GC_AttuneOptionsPrint("self-congrats", checked)
    end)

    local attuneTipsCheckbox = GC_CreateCheckbox("GuildCongratsAttuneTipsCheckbox", panel)
    attuneTipsCheckbox:SetPoint("TOPLEFT", attuneSelfCheckbox, "BOTTOMLEFT", 0, -6)
    attuneTipsCheckbox._label:SetText("Include attunement-specific tips")
    GC_SetCheckboxState(attuneTipsCheckbox, attuneDB.includeTips ~= false)
    attuneTipsCheckbox:SetScript("OnClick", function(self)
        local checked = not not self:GetChecked()
        local db = GC_EnsureAttuneOptionsDB()
        db.includeTips = checked
        GC_SetCheckboxState(self, checked)
        GC_AttuneOptionsPrint("tips", checked)
    end)

    local attuneDebugCheckbox = GC_CreateCheckbox("GuildCongratsAttuneDebugCheckbox", panel)
    attuneDebugCheckbox:SetPoint("TOPLEFT", attuneTipsCheckbox, "BOTTOMLEFT", 0, -6)
    attuneDebugCheckbox._label:SetText("Enable attunement parser debug output")
    GC_SetCheckboxState(attuneDebugCheckbox, attuneDB.debug == true)
    attuneDebugCheckbox:SetScript("OnClick", function(self)
        local checked = not not self:GetChecked()
        local db = GC_EnsureAttuneOptionsDB()
        db.debug = checked
        GC_SetCheckboxState(self, checked)
        GC_AttuneOptionsPrint("debug output", checked)
    end)

    -- Store references
    panel.slider = slider
    panel.flirtCheckbox = flirtCheckbox
    panel.attuneEnabledCheckbox = attuneEnabledCheckbox
    panel.attuneWhoCheckbox = attuneWhoCheckbox
    panel.attuneSelfCheckbox = attuneSelfCheckbox
    panel.attuneTipsCheckbox = attuneTipsCheckbox
    panel.attuneDebugCheckbox = attuneDebugCheckbox

    -- Additional info
    local info = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", attuneDebugCheckbox, "BOTTOMLEFT", 0, -18)
    info:SetWidth(430)
    info:SetJustifyH("LEFT")
    info:SetText("Note: Only the elected leader will announce level-ups and Attune completions to avoid spam.\nUse /gc leader to see who is announcing, or /gc attune for advanced Attune test/parse commands.")
end

function GC_CreateOptionsPanel()
    if GC.optionsPanel then return GC.optionsPanel end

    local panel = CreateFrame("Frame", "GuildCongratsOptionsFrame")
    panel.name = "GuildCongrats"

    -- Some legacy frameworks expect these; harmless otherwise.
    panel.okay = function() end
    panel.cancel = function() end

    panel.default = function(self)
        if not GCongratsDB then GCongratsDB = {} end
        GCongratsDB.mode = 1
        GCongratsDB.enableFlirting = true
        GCongratsDB.attunements = {
            enabled = true,
            debug = false,
            announceSelf = false,
            cooldownSeconds = 300,
            minDelay = 0.8,
            maxDelay = 2.4,
            guildChannel = "GUILD",
            whoLookup = true,
            includeTips = true,
            whoTimeout = 2.0,
            whoCooldownSeconds = 10,
        }

        if self.slider then self.slider:SetValue(1) end
        if self.updateDisplay then self.updateDisplay(1) end

        if self.flirtCheckbox then
            GC_SetCheckboxState(self.flirtCheckbox, true)
        elseif _G.GuildCongratsFlirtCheckbox then
            _G.GuildCongratsFlirtCheckbox:SetChecked(true)
        end

        GC_SetCheckboxState(self.attuneEnabledCheckbox, true)
        GC_SetCheckboxState(self.attuneWhoCheckbox, true)
        GC_SetCheckboxState(self.attuneSelfCheckbox, false)
        GC_SetCheckboxState(self.attuneTipsCheckbox, true)
        GC_SetCheckboxState(self.attuneDebugCheckbox, false)

        if GC_Print then GC_Print("Settings reset to defaults") end
    end

    panel.refresh = function(self)
        if not GCongratsDB then GCongratsDB = {} end

        if self.slider then
            local mode = GCongratsDB.mode or 1
            self.slider:SetValue(mode)
        end

        if self.updateDisplay then
            self.updateDisplay(GCongratsDB.mode or 1)
        end

        local flirtOn = (GCongratsDB.enableFlirting ~= false)
        if self.flirtCheckbox then
            GC_SetCheckboxState(self.flirtCheckbox, flirtOn)
        elseif _G.GuildCongratsFlirtCheckbox then
            _G.GuildCongratsFlirtCheckbox:SetChecked(flirtOn)
        end

        local attuneDB = GC_EnsureAttuneOptionsDB()
        GC_SetCheckboxState(self.attuneEnabledCheckbox, attuneDB.enabled ~= false)
        GC_SetCheckboxState(self.attuneWhoCheckbox, attuneDB.whoLookup ~= false)
        GC_SetCheckboxState(self.attuneSelfCheckbox, attuneDB.announceSelf == true)
        GC_SetCheckboxState(self.attuneTipsCheckbox, attuneDB.includeTips ~= false)
        GC_SetCheckboxState(self.attuneDebugCheckbox, attuneDB.debug == true)
    end

    -- Build UI
    GC_CreateOptionsUI(panel)

    GC.optionsPanel = panel

    -- Register
    local ok = GC_RegisterOptionsPanel(panel)
    panel.registered = ok and true or false

    if not ok and GC_Print then
        GC_Print("Could not register settings panel. Use /gcmode 1|2|3")
    end

    return panel
end

function GC_OpenSettings()
    if not GC.optionsPanel then
        GC_CreateOptionsPanel()
    end

    if not GC.optionsPanel then
        if GC_Print then
            GC_Print("Settings panel could not be created. Use /gcmode 1|2|3")
        end
        return
    end

    -- Ensure registered (some clients want registration after load)
    if not GC.optionsPanel.registered then
        local ok = GC_RegisterOptionsPanel(GC.optionsPanel)
        GC.optionsPanel.registered = ok and true or false
    end

    local opened = GC_OpenToOptions(GC.optionsPanel)
    if not opened and GC_Print then
        GC_Print("Could not open settings UI. Use /gcmode 1|2|3")
    end
end



--------------------------------------------------------
-- Attune / Attunement Congratulations Integration
-- Merged from GuildAttunementCongrats v0.2.6
--------------------------------------------------------

local GC_ATTUNE_DEFAULTS = {
    enabled = true,
    debug = false,
    announceSelf = false,
    cooldownSeconds = 300,
    minDelay = 0.8,
    maxDelay = 2.4,
    guildChannel = "GUILD",
    whoLookup = true,
    includeTips = true,
    whoTimeout = 2.0,
    whoCooldownSeconds = 10,
}

local GC_ATTUNE_KEYWORDS = {
    -- Heroic dungeon wording
    "heroic", "heroics", "heroic dungeon", "heroic dungeons",

    -- Heroic key item names
    "flamewrought key",
    "reservoir key",
    "auchenai key",
    "warpforged key",
    "key of time",

    -- Reputation/key factions
    "honor hold", "thrallmar",
    "cenarion expedition",
    "lower city",
    "the sha'tar", "sha'tar",
    "keepers of time",

    -- Heroic key groups / wings
    "hellfire citadel heroic", "coilfang reservoir heroic", "auchindoun heroic",
    "tempest keep heroic", "caverns of time heroic",
    "hellfire heroics", "coilfang heroics", "auchindoun heroics",
    "tempest keep heroics", "caverns of time heroics",
    "hellfire citadel",
    "coilfang reservoir",
    "auchindoun",
    "tempest keep",
    "caverns of time",
    "hf heroic", "hellfire heroic",
    "cf heroic", "coilfang heroic",
    "auch heroic", "auchindoun heroic",
    "tk heroic", "tempest heroic",
    "cot heroic", "caverns heroic",

    -- TBC raid attunements
    "karazhan", "kara", "the master's key", "masters key",
    "nightbane", "nightbane attunement", "blackened urn", "summon nightbane", "summoning nightbane",
    "gruul", "gruul's lair", "gruuls lair",
    "magtheridon", "magtheridon's lair", "magtheridons lair",
    "serpentshrine cavern", "ssc", "coilfang reservoir raid",
    "the eye", "eye attunement", "tempest keep raid",
    "mount hyjal", "battle for mount hyjal", "hyjal", "vials of eternity",
    "black temple", "bt", "the hand of a'dal", "hand of a'dal", "hand of adal",
    "sunwell", "sunwell plateau",
}

local GC_ATTUNE_CLASS_LINES = {
    Warrior = {
        "That attunement never stood a chance against all that plate and rage.",
        "Another door unlocked by simply charging at the paperwork.",
        "The attunement surrendered before the first Sunder stack.",
    },
    Paladin = {
        "The Light has officially approved this attunement paperwork.",
        "Bubble, blessing, and now another attunement -- very on brand.",
        "Another holy stamp of approval for the raid grind.",
    },
    Hunter = {
        "Your pet probably did half the grind, but we will credit you anyway.",
        "Tracking attunements now counts as hunter utility.",
        "Another attunement unlocked, another adventure your pet gets dragged through.",
    },
    Rogue = {
        "Naturally the locked attunement door lost to the rogue.",
        "Sneaking past the requirements would have been easier, but grats anyway.",
        "That attunement key is just a very official lockpick now.",
    },
    Priest = {
        "The spirits, the Light, or the shadows clearly signed off on this one.",
        "Another attuned group gets a little more survivable.",
        "A healer with more attunements is basically guild infrastructure.",
    },
    Shaman = {
        "The elements have spoken: more attunement access is open.",
        "Drop a totem for the attunement grind -- it is finally done.",
        "The attunement has been cleansed, shocked, and officially completed.",
    },
    Mage = {
        "Portals, water, and now more attunement access -- the utility package grows.",
        "The attunement was probably frozen, burned, and polymorphed into submission.",
        "Another door opened by superior arcane paperwork.",
    },
    Warlock = {
        "Even the attunement key looks slightly fel-corrupted now.",
        "A demon was probably involved, but the attunement counts.",
        "Summoning stones everywhere just got a little more dangerous.",
    },
    Druid = {
        "Bear, cat, tree, moonkin -- and now attuned.",
        "Nature itself apparently endorsed this attunement.",
        "Another form unlocked: attuned dungeon-and-raid enjoyer.",
    },
}

local GC_ATTUNE_RACE_LINES = {
    Human = {
        "Stormwind bureaucracy has nothing on this attunement paperwork.",
        "A very respectable Alliance-approved attunement unlock.",
    },
    Dwarf = {
        "Ironforge should tap a keg for this one.",
        "That attunement has strong ale-and-anvil energy.",
    },
    ["Night Elf"] = {
        "Elune clearly gave this attunement grind a nod.",
        "Very graceful, very ancient, very attuned.",
    },
    Gnome = {
        "Tiny character, huge attunement access energy.",
        "The key may be bigger than you, but it still works.",
    },
    Draenei = {
        "The naaru are probably glowing a little brighter for this one.",
        "Exodar-approved attunement access achieved.",
    },
    Orc = {
        "Lok'tar -- attunement access earned the hard way.",
        "That attunement door is about to learn what zug zug means.",
    },
    Undead = {
        "Death was not enough, and apparently neither was the grind.",
        "An attunement key in cold dead hands still opens the door.",
    },
    Tauren = {
        "The Earthmother approves of this attunement-sized achievement.",
        "Large hooves, larger attunement energy.",
    },
    Troll = {
        "Da attunement grind is done, mon.",
        "The key has been blessed with premium troll swagger.",
    },
    ["Blood Elf"] = {
        "Silvermoon style has officially entered attuned mode.",
        "Elegant, dramatic, and now attunement-ready.",
    },
}

local GC_ATTUNE_OPENERS = {
    "Grats {name} on completing {attune}!",
    "Huge grats {name} -- {attune} complete!",
    "Nice work {name}, {attune} is done!",
    "Congrats {name}! Attunement access upgraded: {attune}.",
}

local GC_ATTUNE_UNKNOWN_LINES = {
    "Grats {name} on completing {attune}! Attunement secured.",
    "Huge grats {name} -- {attune} complete!",
    "Nice work {name}, {attune} is done!",
}

local GC_ATTUNE_TIPS = {
    heroic_hellfire = {
        "Bring fire resistance awareness and watch for heavy trash cleaves in Hellfire heroics.",
        "Shattered Halls loves big pulls -- mark kill targets and keep interrupts ready.",
        "Blood Furnace and Shattered Halls punish loose threat, so let the tank build first.",
    },
    heroic_coilfang = {
        "Watch threat and crowd control in Coilfang heroics; loose mobs hit clothies hard.",
        "Slave Pens and Underbog are smoother when fears, nets, and caster mobs get controlled early.",
        "Steamvaults is much easier when spell casts are interrupted and patrols are respected.",
    },
    heroic_auchindoun = {
        "Auchindoun heroics reward interrupts, crowd control, and careful line-of-sight pulls.",
        "Shadow Labyrinth can snowball fast -- break mind controls and manage fears quickly.",
        "Sethekk and Mana-Tombs are safer when caster packs are interrupted and pulled cleanly.",
    },
    heroic_tempest = {
        "Tempest Keep heroics are caster-heavy, so interrupts and line-of-sight pulls are your friends.",
        "Mechanar and Botanica go smoother when dangerous casters are interrupted or crowd controlled.",
        "Arcatraz hits hard -- bring patience, interrupts, and a healer with a strong coffee supply.",
    },
    heroic_cot = {
        "Caverns of Time heroics reward steady pacing; keep the group together and protect Medivh/Thrall mechanics.",
        "Black Morass is all about portal control -- save cooldowns for rough waves and bosses.",
        "Old Hillsbrad is smoother when the group moves together and avoids messy extra pulls.",
    },
    karazhan = {
        "For Karazhan, bring consumables and patience -- Shade, Netherspite, and Nightbane expose sloppy mechanics.",
        "Kara tip: set clear interrupts and assignments early; the raid is easier when everyone knows their job.",
        "Remember to repair before Kara. The tower has a talent for collecting durability taxes.",
    },
    nightbane = {
        "Nightbane tip: avoid Charred Earth, control skeletons during air phases, and keep healers ready for Smoking Blast.",
        "For Nightbane, ground phases are about clean positioning and air phases are about fast skeleton control.",
        "Bring a focused group for Nightbane -- fear breaks, skeleton control, and avoiding fire make the summon much smoother.",
    },
    gruul = {
        "Gruul tip: spread for Shatter and keep threat clean on High King Maulgar targets.",
        "For Gruul's Lair, assignments matter -- tanks, interrupts, and kill order make Maulgar much cleaner.",
        "Save movement brainpower for Shatter; standing too close turns friends into grenades.",
    },
    magtheridon = {
        "Magtheridon tip: cube clickers win the fight -- assign backups and practice the rotation.",
        "For Magtheridon, interrupts on Channelers and clean cube timing matter more than padding meters.",
        "Cube duty is a promotion, not a punishment. Probably.",
    },
    serpentshrine = {
        "SSC tip: bring nature/frost awareness, respect water mechanics, and do not underestimate trash.",
        "For Serpentshrine Cavern, clean assignments and patience on Lady Vashj make all the difference.",
        "SSC rewards coordination -- interrupts, positioning, and add control beat zugging every time.",
    },
    the_eye = {
        "The Eye tip: movement and add control matter -- especially once Kael'thas starts handing out homework.",
        "Tempest Keep rewards clean positioning, quick target swaps, and people actually using legendary weapons correctly.",
        "For The Eye, respect Void Reaver orbs, Solarian movement, and Kael'thas weapon assignments.",
    },
    hyjal = {
        "Hyjal tip: wave control is everything -- kill priority and staying near the raid saves attempts.",
        "For Mount Hyjal, trash waves are the boss before the boss. Stay grouped and follow kill calls.",
        "Keep an eye on decurses, fears, and wave spawns; Hyjal loves punishing distracted raiders.",
    },
    black_temple = {
        "Black Temple tip: bring focus -- interrupts, positioning, and assignment discipline matter all night.",
        "BT rewards clean mechanics. Supremus volcanoes, Bloodboil groups, and Illidan assignments are not suggestions.",
        "For Black Temple, pack consumables and humility. Illidan can smell overconfidence.",
    },
    sunwell = {
        "Sunwell tip: every global matters -- bring consumes, focus, and respect every mechanic.",
        "Sunwell Plateau is unforgiving; clean positioning and fast reaction time are part of the attunement now.",
        "For Sunwell, assume every mechanic is lethal until proven otherwise.",
    },
    generic = {
        "Tip: bring consumables, repair first, and make sure the group knows the important mechanics.",
        "Tip: new access means new responsibility -- read the boss notes before charging in.",
        "Tip: attuned is step one; surviving the place is the real achievement.",
    },
}

local GC_ATTUNE_CLASS_TOKEN_TO_DISPLAY = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER = "Hunter",
    ROGUE = "Rogue",
    PRIEST = "Priest",
    SHAMAN = "Shaman",
    MAGE = "Mage",
    WARLOCK = "Warlock",
    DRUID = "Druid",
}

local GC_ATTUNE_CLASS_ALIASES = {
    warrior = "Warrior",
    paladin = "Paladin",
    hunter = "Hunter",
    rogue = "Rogue",
    priest = "Priest",
    shaman = "Shaman",
    mage = "Mage",
    warlock = "Warlock",
    druid = "Druid",
}

local GC_ATTUNE_RACE_ALIASES = {
    human = "Human",
    dwarf = "Dwarf",
    ["night elf"] = "Night Elf",
    nightelf = "Night Elf",
    gnome = "Gnome",
    draenei = "Draenei",
    orc = "Orc",
    undead = "Undead",
    scourge = "Undead",
    tauren = "Tauren",
    troll = "Troll",
    ["blood elf"] = "Blood Elf",
    bloodelf = "Blood Elf",
}

GC.attuneRecent = GC.attuneRecent or {}
GC.attuneCache = GC.attuneCache or {}
GC.attunePendingByName = GC.attunePendingByName or {}
GC.attuneLastUsed = GC.attuneLastUsed or { opener = {}, race = {}, class = {}, fallback = {}, tip = {} }
if type(GC.attuneLastUsed.tip) ~= "table" then GC.attuneLastUsed.tip = {} end
GC.attuneLastWhoRequestAt = GC.attuneLastWhoRequestAt or 0

local function GC_AttuneEnsureDB()
    if type(GCongratsDB) ~= "table" then GCongratsDB = {} end
    if type(GuildCongratsDB) ~= "table" then GuildCongratsDB = GCongratsDB end
    if type(GCongratsDB.attunements) ~= "table" then GCongratsDB.attunements = {} end

    local db = GCongratsDB.attunements
    for k, v in pairs(GC_ATTUNE_DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local function GC_AttuneDebug(msg)
    local db = GC_AttuneEnsureDB()
    if db.debug then
        GC_Print("attunement debug: " .. tostring(msg))
    end
end

local function GC_AttuneTrim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function GC_AttuneLower(text)
    return string.lower(tostring(text or ""))
end

local function GC_AttuneCleanPlayerName(name)
    name = GC_AttuneTrim(name or "")
    name = name:gsub("^%[", ""):gsub("%]$", "")
    if Ambiguate then
        name = Ambiguate(name, "guild")
    else
        name = name:gsub("%-.*$", "")
    end
    return name
end

local function GC_AttuneStripChatCodes(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("{%a+%d*}", "")
    text = text:gsub("{rt%d}", "")
    text = text:gsub("[%z\1-\31]", "")
    return text
end

local function GC_AttuneNormalizeClass(className, classToken)
    if classToken and GC_ATTUNE_CLASS_TOKEN_TO_DISPLAY[string.upper(tostring(classToken))] then
        return GC_ATTUNE_CLASS_TOKEN_TO_DISPLAY[string.upper(tostring(classToken))]
    end

    if not className or className == "" then return nil end
    local raw = tostring(className)
    if GC_ATTUNE_CLASS_TOKEN_TO_DISPLAY[string.upper(raw)] then
        return GC_ATTUNE_CLASS_TOKEN_TO_DISPLAY[string.upper(raw)]
    end

    local lower = GC_AttuneLower(raw)
    return GC_ATTUNE_CLASS_ALIASES[lower] or raw
end

local function GC_AttuneNormalizeRace(raceName)
    if not raceName or raceName == "" then return nil end
    local raw = tostring(raceName)
    local lower = GC_AttuneLower(raw)
    local compact = lower:gsub("%s+", "")
    return GC_ATTUNE_RACE_ALIASES[lower] or GC_ATTUNE_RACE_ALIASES[compact] or raw
end

local function GC_AttunePickNonRepeating(pool, bucket, key)
    if type(pool) ~= "table" or #pool == 0 then return nil end
    local count = #pool
    if count == 1 then
        bucket[key] = 1
        return pool[1]
    end

    local idx = math.random(1, count)
    local lastIdx = bucket[key]
    local tries = 0
    while lastIdx and idx == lastIdx and tries < 20 do
        idx = math.random(1, count)
        tries = tries + 1
    end

    bucket[key] = idx
    return pool[idx]
end

local function GC_AttuneFormatMessage(template, name, attune, info)
    info = info or {}
    local raceName = info.race or "Unknown"
    local className = info.class or "Adventurer"

    template = tostring(template or GC_ATTUNE_UNKNOWN_LINES[1])
    template = template:gsub("{name}", name or "guildie")
    template = template:gsub("{attune}", attune or "their attunement")
    template = template:gsub("{race}", raceName)
    template = template:gsub("{class}", className)
    template = template:gsub("{racelower}", GC_AttuneLower(raceName))
    template = template:gsub("{classlower}", GC_AttuneLower(className))
    return template
end

local function GC_AttuneGetTipBucket(attune)
    local rawLower = GC_AttuneLower(attune or "")
    local lower = rawLower:gsub("^the%s+", "")

    if lower:find("sunwell", 1, true) then
        return "sunwell"
    elseif lower:find("black temple", 1, true) or lower == "bt" or lower:find("hand of a'dal", 1, true) or lower:find("hand of adal", 1, true) then
        return "black_temple"
    elseif lower:find("mount hyjal", 1, true) or lower:find("hyjal", 1, true) or lower:find("vials of eternity", 1, true) then
        return "hyjal"
    elseif rawLower == "the eye" or lower == "eye" or rawLower:find("the eye", 1, true) or lower:find("eye attunement", 1, true) or lower:find("tempest keep raid", 1, true) then
        return "the_eye"
    elseif lower:find("serpentshrine", 1, true) or lower == "ssc" or lower:find("coilfang reservoir raid", 1, true) then
        return "serpentshrine"
    elseif lower:find("magtheridon", 1, true) then
        return "magtheridon"
    elseif lower:find("gruul", 1, true) then
        return "gruul"
    elseif lower:find("nightbane", 1, true) or lower:find("blackened urn", 1, true) or lower:find("summon nightbane", 1, true) or lower:find("summoning nightbane", 1, true) then
        return "nightbane"
    elseif lower:find("karazhan", 1, true) or lower == "kara" or lower:find("master's key", 1, true) or lower:find("masters key", 1, true) then
        return "karazhan"
    elseif lower:find("hellfire", 1, true) or lower:find("flamewrought", 1, true) or lower:find("honor hold", 1, true) or lower:find("thrallmar", 1, true) or lower == "hf heroic" then
        return "heroic_hellfire"
    elseif lower:find("coilfang", 1, true) or lower:find("reservoir key", 1, true) or lower:find("cenarion expedition", 1, true) or lower == "cf heroic" then
        return "heroic_coilfang"
    elseif lower:find("auchindoun", 1, true) or lower:find("auchenai", 1, true) or lower:find("lower city", 1, true) or lower == "auch heroic" then
        return "heroic_auchindoun"
    elseif lower:find("caverns of time", 1, true) or lower:find("key of time", 1, true) or lower:find("keepers of time", 1, true) or lower == "cot heroic" then
        return "heroic_cot"
    elseif lower:find("tempest keep", 1, true) or lower:find("warpforged", 1, true) or lower:find("sha'tar", 1, true) or lower:find("the sha", 1, true) or lower == "tk heroic" or lower == "tempest heroic" then
        return "heroic_tempest"
    end

    return "generic"
end

local function GC_AttunePickTip(attune)
    local db = GC_AttuneEnsureDB()
    if db.includeTips == false then return nil end

    local bucket = GC_AttuneGetTipBucket(attune)
    local pool = GC_ATTUNE_TIPS[bucket] or GC_ATTUNE_TIPS.generic
    local tip = GC_AttunePickNonRepeating(pool, GC.attuneLastUsed.tip, bucket or "generic")
    return tip
end

local function GC_AttuneAppendTip(message, name, attune, info)
    local tip = GC_AttunePickTip(attune)
    if not tip or tip == "" then return message end

    local tipText = tip
    if not GC_AttuneLower(tipText):find("^tip:") then
        tipText = "Tip: " .. tipText
    end

    local full = message .. " " .. tipText
    if #full <= 245 then return full end

    local compactPrefix = GC_AttuneFormatMessage("Grats {name} on {attune}! ", name, attune, info)
    local compact = compactPrefix .. tipText
    if #compact <= 245 then return compact end

    local room = 245 - #compactPrefix - 5 -- room after "Tip: "
    if room > 24 then
        return compactPrefix .. "Tip: " .. string.sub(tip, 1, room - 3) .. "..."
    end

    return message
end

local function GC_AttunePickMessage(name, attune, info)
    info = info or {}
    local className = GC_AttuneNormalizeClass(info.class, info.classToken)
    local raceName = GC_AttuneNormalizeRace(info.race)

    if not className and not raceName then
        local fallback = GC_AttunePickNonRepeating(GC_ATTUNE_UNKNOWN_LINES, GC.attuneLastUsed.fallback, "unknown") or GC_ATTUNE_UNKNOWN_LINES[1]
        local message = GC_AttuneFormatMessage(fallback, name, attune, info)
        return GC_AttuneAppendTip(message, name, attune, info)
    end

    local opener = GC_AttunePickNonRepeating(GC_ATTUNE_OPENERS, GC.attuneLastUsed.opener, "opener") or GC_ATTUNE_OPENERS[1]
    local parts = { GC_AttuneFormatMessage(opener, name, attune, { race = raceName, class = className }) }

    if raceName and GC_ATTUNE_RACE_LINES[raceName] then
        local line = GC_AttunePickNonRepeating(GC_ATTUNE_RACE_LINES[raceName], GC.attuneLastUsed.race, raceName)
        if line then table.insert(parts, GC_AttuneFormatMessage(line, name, attune, { race = raceName, class = className })) end
    end

    if className and GC_ATTUNE_CLASS_LINES[className] then
        local line = GC_AttunePickNonRepeating(GC_ATTUNE_CLASS_LINES[className], GC.attuneLastUsed.class, className)
        if line then table.insert(parts, GC_AttuneFormatMessage(line, name, attune, { race = raceName, class = className })) end
    end

    if #parts == 1 and (raceName or className) then
        table.insert(parts, GC_AttuneFormatMessage("{race} {class} attunement access confirmed.", name, attune, { race = raceName, class = className }))
    end

    local message = table.concat(parts, " ")
    return GC_AttuneAppendTip(message, name, attune, { race = raceName, class = className })
end

local function GC_AttuneCacheCharacter(name, raceName, className, classToken, gender)
    name = GC_AttuneCleanPlayerName(name)
    if not name or name == "" then return end

    GC.attuneCache[name] = GC.attuneCache[name] or {}
    local entry = GC.attuneCache[name]

    local normalizedRace = GC_AttuneNormalizeRace(raceName)
    local normalizedClass = GC_AttuneNormalizeClass(className, classToken)

    if normalizedRace and normalizedRace ~= "" and normalizedRace ~= "Unknown" then
        entry.race = normalizedRace
    end
    if normalizedClass and normalizedClass ~= "" and normalizedClass ~= "Unknown" then
        entry.class = normalizedClass
    end
    if classToken and classToken ~= "" then
        entry.classToken = tostring(classToken)
    end
    if gender then
        entry.gender = gender
    end
    entry.updated = time()

    -- Also share data with the existing GuildCongrats guild cache.
    GC.guildCache[name] = GC.guildCache[name] or {}
    if entry.race then GC.guildCache[name].race = entry.race end
    if entry.class then GC.guildCache[name].class = entry.class end
    if entry.classToken then GC.guildCache[name].token = entry.classToken end
    if entry.gender then GC.guildCache[name].gender = entry.gender end
end

local function GC_AttuneGetCachedCharacter(name)
    name = GC_AttuneCleanPlayerName(name)
    local info = GC.attuneCache[name]
    if info then return info end
    if GC.guildCache and GC.guildCache[name] then return GC.guildCache[name] end
    return nil
end

local function GC_AttuneScanVisibleUnitsForCharacter(name)
    name = GC_AttuneCleanPlayerName(name)
    if not name or name == "" then return end

    local units = { "player", "target", "focus", "mouseover", "party1", "party2", "party3", "party4" }
    for i = 1, 40 do
        units[#units + 1] = "raid" .. i
    end

    for _, unit in ipairs(units) do
        if UnitExists and UnitExists(unit) and UnitIsPlayer and UnitIsPlayer(unit) then
            local unitName = UnitName(unit)
            if unitName and GC_AttuneCleanPlayerName(unitName) == name then
                local raceName, className, classToken, gender
                if UnitRace then raceName = UnitRace(unit) end
                if UnitClass then className, classToken = UnitClass(unit) end
                if UnitSex then gender = UnitSex(unit) end
                GC_AttuneCacheCharacter(name, raceName, className, classToken, gender)
                return GC.attuneCache[name]
            end
        end
    end
end

local function GC_AttuneScanGuildRoster()
    if not IsInGuild or not IsInGuild() then return end
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end

    local num = GetNumGuildMembers()
    if not num or num <= 0 then return end

    for i = 1, num do
        local fullName, _, _, _, classDisplayName, _, _, _, _, _, classFileName = GetGuildRosterInfo(i)
        if fullName then
            GC_AttuneCacheCharacter(fullName, nil, classDisplayName, classFileName, nil)
        end
    end
end

local function GC_AttuneIsTracked(attuneText)
    local lower = GC_AttuneLower(attuneText)
    for _, keyword in ipairs(GC_ATTUNE_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true, keyword
        end
    end
    return false, nil
end

local function GC_AttuneContainsMarker(text)
    local lower = GC_AttuneLower(text)
    return lower:find("%[attune%]") or lower:find("^%s*attune[%s:%-]") or lower:find("%sattune[%s:%-]")
end

local function GC_AttuneStripPrefix(text)
    text = GC_AttuneTrim(text or "")
    text = text:gsub("^%s*%[Attune%]%s*", "")
    text = text:gsub("^%s*%[attune%]%s*", "")
    text = text:gsub("^%s*Attune%s*[:%-]%s*", "")
    text = text:gsub("^%s*attune%s*[:%-]%s*", "")
    text = text:gsub("^[%s:%-]+", "")
    return GC_AttuneTrim(text)
end

local function GC_AttuneStripLeadingDecorations(text)
    text = GC_AttuneTrim(text or "")
    text = text:gsub("^%[([^%]]+)%]%s*", "%1 ")
    text = text:gsub("^<([^>]+)>%s*", "%1 ")
    text = text:gsub("^([^:]+):%s+", "%1 ")
    return GC_AttuneTrim(text)
end

local function GC_AttuneParseNameAndAttuneFromBody(body)
    body = GC_AttuneStripLeadingDecorations(body)

    local patterns = {
        "^(.-)%s+has%s+completed%s+the%s+attunement%s+for%s+(.+)$",
        "^(.-)%s+has%s+completed%s+attunement%s+for%s+(.+)$",
        "^(.-)%s+has%s+completed%s+the%s+(.+)%s+attunement$",
        "^(.-)%s+has%s+completed%s+(.+)$",
        "^(.-)%s+completed%s+the%s+attunement%s+for%s+(.+)$",
        "^(.-)%s+completed%s+attunement%s+for%s+(.+)$",
        "^(.-)%s+completed%s+the%s+(.+)%s+attunement$",
        "^(.-)%s+completed%s+(.+)$",
        "^(.-)%s+is%s+now%s+attuned%s+to%s+(.+)$",
        "^(.-)%s+is%s+attuned%s+to%s+(.+)$",
        "^(.-)%s+became%s+attuned%s+to%s+(.+)$",
        "^(.-)%s+has%s+become%s+attuned%s+to%s+(.+)$",
        "^(.-)%s+earned%s+(.+)$",
        "^(.-)%s+unlocked%s+(.+)$",
    }

    for _, pattern in ipairs(patterns) do
        local name, attune = body:match(pattern)
        if name and attune then
            return name, attune
        end
    end

    return nil, nil
end

local function GC_AttuneParseGuildCompletion(message, author)
    local clean = GC_AttuneStripChatCodes(message)

    if not GC_AttuneContainsMarker(clean) then
        return nil
    end

    local body = GC_AttuneStripPrefix(clean)
    local name, attune = GC_AttuneParseNameAndAttuneFromBody(body)

    if (not name or not attune) and author and author ~= "" then
        local authorShort = GC_AttuneCleanPlayerName(author)
        local lowerBody = GC_AttuneLower(body)
        local possibleAttune = nil

        possibleAttune = body:match("^(.+)%s+attunement%s+complete[!%.]*$")
            or body:match("^(.+)%s+attunement%s+is%s+complete[!%.]*$")
            or body:match("^(.+)%s+attunement%s+completed[!%.]*$")
            or body:match("^(.+)%s+complete[!%.]*$")
            or body:match("completed%s+the%s+attunement%s+for%s+(.+)$")
            or body:match("completed%s+attunement%s+for%s+(.+)$")
            or body:match("completed%s+the%s+(.+)%s+attunement$")
            or body:match("completed%s+(.+)$")
            or body:match("attuned%s+to%s+(.+)$")
            or body:match("unlocked%s+(.+)$")

        if possibleAttune and authorShort ~= "" then
            name, attune = authorShort, possibleAttune
        elseif (lowerBody:find("complete") or lowerBody:find("attuned") or lowerBody:find("unlocked")) and GC_AttuneIsTracked(body) then
            name, attune = authorShort, body
        end
    end

    if not name or not attune then
        GC_AttuneDebug("Saw Attune guild message but could not parse player/attunement: " .. clean)
        return nil
    end

    name = GC_AttuneCleanPlayerName(name)
    attune = GC_AttuneTrim(attune:gsub("^[%s:%-]+", ""):gsub("[%!%.]+$", ""))
    attune = attune:gsub("^the%s+", "")
    attune = attune:gsub("%s+attunement$", "")

    if name == "" or attune == "" then
        GC_AttuneDebug("Saw Attune guild message but parsed empty name/attunement: " .. clean)
        return nil
    end

    local isTracked, matchedKeyword = GC_AttuneIsTracked(attune)
    if not isTracked then
        isTracked, matchedKeyword = GC_AttuneIsTracked(clean)
    end

    if not isTracked then
        GC_AttuneDebug("Ignored Attunement completion because it did not look like a tracked heroic/raid attunement: " .. clean)
        return nil
    end

    return name, attune, matchedKeyword, clean
end

local function GC_AttuneShouldThrottle(name, attune)
    local db = GC_AttuneEnsureDB()
    local key = GC_AttuneLower(name .. "|" .. attune)
    local now = time()
    local last = GC.attuneRecent[key]
    if last and (now - last) < (db.cooldownSeconds or 300) then
        return true
    end
    GC.attuneRecent[key] = now
    return false
end

local function GC_AttuneSendCongrats(name, attune, info)
    local db = GC_AttuneEnsureDB()
    local msg = GC_AttunePickMessage(name, attune, info)
    local channel = db.guildChannel or "GUILD"
    GC_AttuneDebug("Sending to " .. channel .. ": " .. msg)
    SendChatMessage(msg, channel)
end

local function GC_AttuneScheduleCongrats(name, attune, info)
    local db = GC_AttuneEnsureDB()
    local minDelay = tonumber(db.minDelay) or GC_ATTUNE_DEFAULTS.minDelay
    local maxDelay = tonumber(db.maxDelay) or GC_ATTUNE_DEFAULTS.maxDelay
    if maxDelay < minDelay then maxDelay = minDelay end

    local delay = minDelay
    if maxDelay > minDelay then
        delay = minDelay + (math.random() * (maxDelay - minDelay))
    end

    GC_CreateTimer(delay, function()
        GC_AttuneSendCongrats(name, attune, info)
    end)
end

local function GC_AttuneFlushPendingForName(name)
    name = GC_AttuneCleanPlayerName(name)
    local list = GC.attunePendingByName[name]
    if type(list) ~= "table" or #list == 0 then return end

    GC.attunePendingByName[name] = nil
    local info = GC_AttuneGetCachedCharacter(name) or {}

    for _, pending in ipairs(list) do
        GC_AttuneScheduleCongrats(pending.name, pending.attune, info)
    end
end

local function GC_AttuneQueuePendingForWho(name, attune)
    name = GC_AttuneCleanPlayerName(name)
    GC.attunePendingByName[name] = GC.attunePendingByName[name] or {}
    table.insert(GC.attunePendingByName[name], { name = name, attune = attune, queued = time() })

    local db = GC_AttuneEnsureDB()
    local timeout = tonumber(db.whoTimeout) or GC_ATTUNE_DEFAULTS.whoTimeout
    GC_CreateTimer(timeout, function()
        if GC.attunePendingByName[name] then
            GC_AttuneDebug("Who lookup timed out for " .. name .. "; sending with cached/fallback info.")
            GC_AttuneFlushPendingForName(name)
        end
    end)
end

local function GC_AttuneSetWhoResultsHidden()
    if C_FriendList and C_FriendList.SetWhoToUi then
        pcall(C_FriendList.SetWhoToUi, false)
    elseif SetWhoToUI then
        pcall(SetWhoToUI, 0)
    end
end

local function GC_AttuneSendWhoQuery(query)
    if C_FriendList and C_FriendList.SendWho then
        return pcall(C_FriendList.SendWho, query)
    elseif SendWho then
        return pcall(SendWho, query)
    end
    return false
end

local function GC_AttuneTryWhoLookup(name)
    local db = GC_AttuneEnsureDB()
    if not db.whoLookup then return false end

    local now = time()
    if GC.attuneLastWhoRequestAt and GC.attuneLastWhoRequestAt > 0 and (now - GC.attuneLastWhoRequestAt) < (db.whoCooldownSeconds or 10) then
        GC_AttuneDebug("Who lookup skipped due to cooldown for " .. name)
        return false
    end

    GC_AttuneSetWhoResultsHidden()
    GC.attuneLastWhoRequestAt = now

    local ok = GC_AttuneSendWhoQuery("n-" .. name)
    if ok then
        GC_AttuneDebug("Requested hidden who lookup for " .. name)
    else
        GC_AttuneDebug("Who lookup API unavailable for " .. name)
    end
    return ok
end

local function GC_AttuneGetWhoCount()
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local ok, count = pcall(C_FriendList.GetNumWhoResults)
        if ok then return count end
    end
    if GetNumWhoResults then
        local ok, count = pcall(GetNumWhoResults)
        if ok then return count end
    end
    return 0
end

local function GC_AttuneGetWhoResult(index)
    if C_FriendList and C_FriendList.GetWhoInfo then
        local ok, a, b, c, d, e, f, g, h = pcall(C_FriendList.GetWhoInfo, index)
        if ok then
            if type(a) == "table" then
                return a.fullName or a.name, a.fullGuildName or a.guild, a.level, a.raceStr or a.race, a.classStr or a.className or a.class, a.area or a.zone, a.filename or a.classFileName, a.gender
            end
            return a, b, c, d, e, f, g, h
        end
    end

    if GetWhoInfo then
        local ok, name, guild, level, race, className, zone, classFileName, gender = pcall(GetWhoInfo, index)
        if ok then return name, guild, level, race, className, zone, classFileName, gender end
    end

    return nil
end

local function GC_AttuneHandleWhoListUpdate()
    local count = GC_AttuneGetWhoCount()
    if not count or count <= 0 then return end

    for i = 1, count do
        local whoName, _, _, raceName, className, _, classToken, gender = GC_AttuneGetWhoResult(i)
        if whoName then
            local shortName = GC_AttuneCleanPlayerName(whoName)
            GC_AttuneCacheCharacter(shortName, raceName, className, classToken, gender)

            if GC.attunePendingByName[shortName] then
                GC_AttuneDebug("Who lookup found " .. shortName .. " as " .. tostring(GC_AttuneNormalizeRace(raceName) or "?") .. " " .. tostring(GC_AttuneNormalizeClass(className, classToken) or "?"))
                GC_AttuneFlushPendingForName(shortName)
            end
        end
    end
end

local function GC_AttuneResolveAndSchedule(name, attune)
    name = GC_AttuneCleanPlayerName(name)
    GC_AttuneScanVisibleUnitsForCharacter(name)

    local info = GC_AttuneGetCachedCharacter(name) or {}
    local db = GC_AttuneEnsureDB()
    if info.race or not db.whoLookup then
        GC_AttuneScheduleCongrats(name, attune, info)
        return
    end

    GC_AttuneQueuePendingForWho(name, attune)
    local requested = GC_AttuneTryWhoLookup(name)
    if not requested then
        GC_AttuneFlushPendingForName(name)
    end
end

local function GC_AttuneOnGuildMessage(message, author)
    local db = GC_AttuneEnsureDB()
    if not db.enabled then return end

    local name, attune, keyword = GC_AttuneParseGuildCompletion(message, author)
    if not name then return end

    -- Reuse GuildCongrats' leader election so multiple addon users do not all respond.
    if not GC.isLeader then
        GC_AttuneDebug("Matched " .. tostring(name) .. " / " .. tostring(attune) .. " but standing by; active announcer is " .. tostring(GC.leaderName or "unknown") .. ".")
        return
    end

    if author and author ~= "" then
        local authorShort = GC_AttuneCleanPlayerName(author)
        if authorShort == name then
            GC_AttuneScanVisibleUnitsForCharacter(authorShort)
        end
    end

    local playerName = UnitName("player")
    if not db.announceSelf and playerName and GC_AttuneCleanPlayerName(name) == GC_AttuneCleanPlayerName(playerName) then
        GC_AttuneDebug("Ignored own Attunement completion: " .. attune)
        return
    end

    if GC_AttuneShouldThrottle(name, attune) then
        GC_AttuneDebug("Ignored duplicate completion for " .. name .. ": " .. attune)
        return
    end

    GC_AttuneDebug("Matched attunement keyword '" .. tostring(keyword) .. "' for " .. name .. ": " .. attune)
    GC_AttuneResolveAndSchedule(name, attune)
end

local function GC_AttuneShowStatus()
    local db = GC_AttuneEnsureDB()
    GC_Print("Attunement congrats enabled: " .. tostring(db.enabled))
    GC_Print("Attunement debug: " .. tostring(db.debug))
    GC_Print("Attunement congratulate self: " .. tostring(db.announceSelf))
    GC_Print("Attunement hidden /who race lookup: " .. tostring(db.whoLookup))
    GC_Print("Attunement tips included: " .. tostring(db.includeTips ~= false))
    GC_Print("Attunement cooldown seconds: " .. tostring(db.cooldownSeconds))
    if GC.isLeader then
        GC_Print("Attunement announcer: me")
    else
        GC_Print("Attunement announcer: " .. tostring(GC.leaderName or "not elected yet"))
    end
end

local function GC_AttuneShowCachedCharacter(rest)
    local name = GC_AttuneCleanPlayerName(rest or "")
    if name == "" then
        GC_Print("Usage: /gc attune cache CharacterName")
        return
    end

    GC_AttuneScanVisibleUnitsForCharacter(name)
    local info = GC_AttuneGetCachedCharacter(name)
    if not info then
        GC_Print("No cached info for " .. name .. ". Try /gc attune scan, target the player, or wait for /who lookup after an Attune message.")
        return
    end

    GC_Print(name .. ": race=" .. tostring(info.race or "?") .. ", class=" .. tostring(info.class or info.classToken or "?") .. ", updated=" .. tostring(info.updated or "?"))
end

local function GC_AttunePreviewTest(rest)
    rest = GC_AttuneTrim(rest or "")
    local raceName, className

    if rest == "" then
        raceName, className = "Human", "Paladin"
    else
        local words = {}
        for word in rest:gmatch("%S+") do words[#words + 1] = word end
        if #words >= 3 then
            raceName = words[1] .. " " .. words[2]
            className = words[3]
        elseif #words == 2 then
            raceName = words[1]
            className = words[2]
        elseif #words == 1 then
            raceName = nil
            className = words[1]
        end
    end

    local fake = "[Attune] Testguildie has completed Heroic Hellfire Citadel"
    local name, attune, keyword = GC_AttuneParseGuildCompletion(fake, "Testguildie")
    if name then
        local info = { race = GC_AttuneNormalizeRace(raceName), class = GC_AttuneNormalizeClass(className) }
        GC_Print("attune test matched keyword '" .. tostring(keyword) .. "'.")
        GC_Print("preview: " .. GC_AttunePickMessage(name, attune, info))
    else
        GC_Print("attune test failed to match.")
    end
end

local function GC_AttunePreviewParse(rest)
    rest = GC_AttuneTrim(rest or "")
    if rest == "" then
        GC_Print("Usage: /gc attune parse [Attune guild chat line]")
        return
    end

    local previewAuthor = UnitName and UnitName("player") or "GuildMember"
    local name, attune, keyword = GC_AttuneParseGuildCompletion(rest, previewAuthor)
    if name then
        GC_Print("attune parse matched: name=" .. tostring(name) .. ", attune=" .. tostring(attune) .. ", keyword=" .. tostring(keyword))
    else
        GC_Print("attune parse did not match as a tracked Attune completion. Use /gc attune debug for ignored reasons.")
    end
end

local function GC_AttuneShowHelp()
    GC_Print("Attunement commands:")
    GC_Print("/gc attune status - show attunement congrats settings")
    GC_Print("/gc attune on|off - enable/disable Attunement completion congrats")
    GC_Print("/gc attune debug - toggle Attune parser debug output")
    GC_Print("/gc attune self - toggle congratulating yourself")
    GC_Print("/gc attune who - toggle hidden /who race lookup")
    GC_Print("/gc attune tips - toggle attunement-specific tips")
    GC_Print("/gc attune scan - refresh guild roster cache")
    GC_Print("/gc attune cache CharacterName - show cached race/class")
    GC_Print("/gc attune test [race] [class] - preview a fake attunement message")
    GC_Print("/gc attune parse <Attune line> - test a pasted Attune guild line")
end

local function GC_AttuneSlash(rest)
    rest = GC_AttuneTrim(rest or "")
    local cmd, arg = rest:match("^(%S+)%s*(.-)$")
    cmd = GC_AttuneLower(cmd or "")
    arg = GC_AttuneTrim(arg or "")

    local db = GC_AttuneEnsureDB()

    if cmd == "" or cmd == "help" then
        GC_AttuneShowHelp()
    elseif cmd == "on" or cmd == "enable" then
        db.enabled = true
        GC_Print("Attune congrats enabled.")
    elseif cmd == "off" or cmd == "disable" then
        db.enabled = false
        GC_Print("Attune congrats disabled.")
    elseif cmd == "debug" then
        db.debug = not db.debug
        GC_Print("Attune debug is now " .. tostring(db.debug) .. ".")
    elseif cmd == "self" then
        db.announceSelf = not db.announceSelf
        GC_Print("Attune congratulate self is now " .. tostring(db.announceSelf) .. ".")
    elseif cmd == "who" then
        db.whoLookup = not db.whoLookup
        GC_Print("Attune hidden /who race lookup is now " .. tostring(db.whoLookup) .. ".")
    elseif cmd == "tips" or cmd == "tip" then
        db.includeTips = not db.includeTips
        GC_Print("Attune-specific tips are now " .. tostring(db.includeTips ~= false) .. ".")
    elseif cmd == "scan" or cmd == "refresh" then
        if IsInGuild and IsInGuild() and GuildRoster then GuildRoster() end
        GC_AttuneScanGuildRoster()
        GC_Print("Attune guild roster cache refreshed. Class data should be available; race data needs target/party/raid or /who lookup.")
    elseif cmd == "cache" then
        GC_AttuneShowCachedCharacter(arg)
    elseif cmd == "status" then
        GC_AttuneShowStatus()
    elseif cmd == "reset" then
        GCongratsDB.attunements = {}
        GC_AttuneEnsureDB()
        GC_Print("Attune settings reset.")
    elseif cmd == "test" then
        GC_AttunePreviewTest(arg)
    elseif cmd == "parse" then
        GC_AttunePreviewParse(arg)
    else
        GC_AttuneShowHelp()
    end
end

--------------------------------------------------------
-- Slash commands (hard-registered; does not depend on earlier code)
--------------------------------------------------------

-- Always keep gcsettings working
SLASH_GCSETTINGS1 = "/gcsettings"
SlashCmdList["GCSETTINGS"] = function()
    GC_OpenSettings()
end

-- Hard-register /gc + /guildcongrats (do NOT rely on earlier registration)
SLASH_GUILDCONGRATS1 = "/guildcongrats"
SLASH_GUILDCONGRATS2 = "/gc"

SlashCmdList["GUILDCONGRATS"] = function(msg)
    local rawMsg = msg or ""
    local msgLower = rawMsg:lower()
    local cmd, rest = rawMsg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if msgLower == "" or msgLower == "help" then
        GC_Print("GuildCongrats Commands:")
        GC_Print("/gc settings   - Open settings panel")
        GC_Print("/gc refresh    - Refresh guild roster")
        GC_Print("/gc leader     - Show current announcer")
        GC_Print("/gc force      - Force yourself as announcer (emergency)")
        GC_Print("/gc elect      - Re-run leader election")
        GC_Print("/gc diag       - Print debug state")
        GC_Print("/gc attune     - Attunement completion congrats commands")
        return
    end

    if cmd == "attune" or cmd == "attunement" or cmd == "attunements" then
        GC_AttuneSlash(rest)
        return
    end

    if msgLower == "settings" or msgLower == "options" or msgLower == "config" then
        GC_OpenSettings()
        return
    end

    if msgLower == "refresh" then
        if IsInGuild() then
            if GuildRoster then GuildRoster() end
            GC_Print("Refreshing guild roster...")
        else
            GC_Print("You are not in a guild.")
        end
        return
    end

    if msgLower == "leader" then
        if GC.isLeader then
            GC_Print("I am the current announcer.")
        elseif GC.leaderName then
            GC_Print("Current announcer is: " .. GC.leaderName)
        else
            GC_Print("No announcer elected yet.")
        end
        return
    end

    if msgLower == "force" then
        GC.isLeader = true
        GC.hasLeader = true
        GC.leaderName = UnitName("player")
        GC_Print("Forced myself as announcer. Use with caution!")
        return
    end

    if msgLower == "elect" then
        if IsInGuild() and GC_StartLeaderElection then
            GC_StartLeaderElection()
            GC_Print("Leader election started.")
        else
            GC_Print("Cannot run election (not in guild or election function missing).")
        end
        return
    end

    if msgLower == "diag" then
        GC_Print("DIAG:")
        GC_Print("  InGuild=" .. tostring(IsInGuild()))
        GC_Print("  hasLeader=" .. tostring(GC.hasLeader))
        GC_Print("  isLeader=" .. tostring(GC.isLeader))
        GC_Print("  leaderName=" .. tostring(GC.leaderName))
        GC_Print("  mode=" .. tostring((GCongratsDB and GCongratsDB.mode) or "nil"))
        GC_Print("  Slash /gc registered=" .. tostring(SlashCmdList and SlashCmdList["GUILDCONGRATS"] ~= nil))
        return
    end

    GC_Print("Unknown subcommand. Type /gc for help.")
end

--------------------------------------------------------
-- Core Event Engine (TBC 2.4.3) - ACTUALLY RUNS THE ADDON
--------------------------------------------------------

local core = CreateFrame("Frame")

core:RegisterEvent("PLAYER_LOGIN")
core:RegisterEvent("GUILD_ROSTER_UPDATE")
core:RegisterEvent("CHAT_MSG_ADDON")
core:RegisterEvent("CHAT_MSG_GUILD")
core:RegisterEvent("WHO_LIST_UPDATE")
core:RegisterEvent("PLAYER_GUILD_UPDATE")

-- Helper: start election a bit later (lets roster/prefix settle)
local function GC_KickElectionSoon()
    if not IsInGuild() then return end
    if not GC_StartLeaderElection then return end

    GC_CreateTimer(1.0, function()
        GC_StartLeaderElection()
    end)
end

core:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        GC_EnsureDB()
        if GC_AttuneEnsureDB then GC_AttuneEnsureDB() end

        -- Make sure addon comms prefix is registered ASAP (TBC-safe)
        if GC_CommsRegisterPrefix then
            GC_CommsRegisterPrefix()
        end

        -- Create + register options panel early so it appears in ESC options
        if GC_CreateOptionsPanel then
            GC_CreateOptionsPanel()
        end

        -- Seed randomness once (TBC 2.4.3 safe)
        if not GC._seeded then
            GC._seeded = true
            if math and math.randomseed then
                math.randomseed(time())
            else
                local spins = (time() % 17) + 5
                for i = 1, spins do
                    math.random()
                end
            end
        end

        -- If we're already in a guild on login, request roster and kick election
        if IsInGuild() then
            if GuildRoster then GuildRoster() end
            if GC_AttuneScanGuildRoster then GC_AttuneScanGuildRoster() end
            GC_KickElectionSoon()
        else
            GC.hasLeader  = false
            GC.isLeader   = false
            GC.leaderName = nil
        end

        GC_Print("Loaded. Watching guild roster for level ups and Attune completions.")
        return
    end

    if event == "PLAYER_GUILD_UPDATE" then
        -- Player joined/left guild or guild state changed
        if IsInGuild() then
            if GuildRoster then GuildRoster() end
            if GC_AttuneScanGuildRoster then GC_AttuneScanGuildRoster() end
            GC_KickElectionSoon()
        else
            GC.hasLeader  = false
            GC.isLeader   = false
            GC.leaderName = nil
        end
        return
    end

    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if GC_HandleAddonMessage then
            GC_HandleAddonMessage(prefix, msg, channel, sender)
        end
        return
    end

    if event == "CHAT_MSG_GUILD" then
        local message, author = ...
        if GC_AttuneOnGuildMessage then
            GC_AttuneOnGuildMessage(message, author)
        end
        return
    end

    if event == "WHO_LIST_UPDATE" then
        if GC_AttuneHandleWhoListUpdate then
            GC_AttuneHandleWhoListUpdate()
        end
        return
    end

    if event == "GUILD_ROSTER_UPDATE" then
        -- First: scan roster for level changes
        if GC_ScanGuildRoster then
            GC_ScanGuildRoster()
        end
        if GC_AttuneScanGuildRoster then
            GC_AttuneScanGuildRoster()
        end

        -- Second: if no leader yet (fresh login / reload), kick election again
        if IsInGuild() and (not GC.hasLeader) then
            GC_KickElectionSoon()
        end

        return
    end
end)

--------------------------------------------------------
-- End-of-file init marker
--------------------------------------------------------
GC_CreateTimer(0.1, function()
    if GC_Print then
        GC_Print("Initialization finished. /gc for commands. /gc settings for options.")
    end
end)